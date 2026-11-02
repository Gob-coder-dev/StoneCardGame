from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import torch
import yaml

from samstone_rl.bridge import GodotProtocolError
from samstone_rl.fast_engine import StoneCatalog
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.validation import wilson_lower


class PhaseFiveTrainer(PPOTrainer):
    """Continue a validated phase-4 policy against a frozen-checkpoint league."""

    def __init__(self, config_path: str | Path, *,
                 phase4_checkpoint: str | Path | None = None,
                 resume: str | Path | None = None) -> None:
        if (phase4_checkpoint is None) == (resume is None):
            raise ValueError("fournir soit phase4_checkpoint, soit resume")
        source = Path(phase4_checkpoint or resume).resolve()
        checkpoint = self._read_verified_checkpoint(source)
        phase5_state = checkpoint.get("phase5", {})
        if phase4_checkpoint is not None and not checkpoint.get("curriculum", {}).get("completed"):
            raise ValueError("la phase 5 exige phase4_validated.pt")
        if resume is not None and not phase5_state.get("initial_policy_checksum"):
            raise ValueError("resume exige un checkpoint de phase 5")
        if phase4_checkpoint is not None:
            requested = yaml.safe_load(Path(config_path).resolve().read_text(encoding="utf-8"))
            original = checkpoint.get("config", {})
            for key in ("scenarios", "reward"):
                before = original.get("environment", {}).get(key)
                after = requested["environment"][key]
                if before is not None and before != after:
                    raise ValueError(f"phase 5 et phase 4 n'utilisent pas les memes {key}")
            original_model = original.get("model", {}).get("hidden_dim")
            if original_model is not None and int(original_model) != int(
                    requested["model"]["hidden_dim"]):
                raise ValueError("la dimension du modele differe de la phase 4")
            manifest = source.parent / "run_manifest.json"
            if manifest.is_file():
                expected_catalog = json.loads(manifest.read_text(encoding="utf-8")).get(
                    "checksums", {}).get("catalog")
                if expected_catalog and expected_catalog != StoneCatalog().checksum:
                    raise ValueError("les cartes ont change depuis la validation de phase 4")
        super().__init__(config_path)
        settings = self.config["phase5"]
        directory = Path(settings["league_directory"])
        self.league_directory = (directory if directory.is_absolute()
                                 else Path(config_path).resolve().parent.parent / directory).resolve()
        if self.league_directory != (self.output / "league").resolve():
            raise ValueError("phase5.league_directory doit etre output_dir/league")
        self.phase4_baseline = self.output / "phase4_baseline.pt"
        self.phase4_checksum = (self._file_checksum(source) if phase4_checkpoint is not None
                                else str(phase5_state["initial_policy_checksum"]))
        if phase4_checkpoint is not None:
            if self.phase4_baseline.exists() or self.league_directory.exists():
                raise ValueError("run de phase 5 deja initialise; utiliser --resume")
            shutil.copy2(source, self.phase4_baseline)
        elif (not self.phase4_baseline.is_file()
              or self._file_checksum(self.phase4_baseline) != self.phase4_checksum):
            raise ValueError("checkpoint phase 4 initial absent ou modifie")
        self.tracker.update_manifest(checksums={"initial_policy": self.phase4_checksum})
        self.league = SelfPlayLeague(self.league_directory,
                                     dict(settings["weight_schedule"][0]["weights"]),
                                     str(self.device))
        # Certification applies to exact weights only. Any further PPO update
        # produces a new candidate that must pass the gate again.
        self.phase5_completed = False
        if resume is not None:
            self.load_checkpoint(source)
            if not self.league.entries:
                raise ValueError("ligue absente pour ce checkpoint de reprise")
        else:
            self.model.load_state_dict(checkpoint["model"])
            self.curriculum.load_state_dict(checkpoint["curriculum"])
            if not self.curriculum.completed:
                raise ValueError("curriculum phase 4 non valide")
            self.league.register(self.phase4_baseline, 0, 0.0, "current")
            self.league.register(self.phase4_baseline, 0, 0.0, "best")
            self._save("latest.pt", 0, {}, 0)

    @staticmethod
    def _read_verified_checkpoint(path: Path) -> dict[str, Any]:
        checksum_path = path.with_suffix(path.suffix + ".sha256")
        if checksum_path.is_file():
            expected = checksum_path.read_text(encoding="ascii").split()[0]
            actual = PPOTrainer._file_checksum(path)
            if actual != expected:
                raise ValueError(f"checksum invalide pour {path}")
        return torch.load(path, map_location="cpu", weights_only=False)

    def _training_opponent(self) -> LeagueOpponent:
        return LeagueOpponent(self.league)

    def _training_scenario_options(self, scenario_index: int, agent_player: int,
                                   blocked: list[list[int]] | None = None) -> dict:
        own = self.scenarios[scenario_index]
        if self.rng.random() < float(self.config["phase5"].get("mirror_probability", 0.1)):
            opponent_index = scenario_index
        else:
            choices = [index for index in range(len(self.scenarios)) if index != scenario_index]
            opponent_index = choices[int(self.rng.integers(len(choices)))]
        other = self.scenarios[opponent_index]
        if agent_player == 1:
            config = {"human_god": own["god"], "human_deck": list(own["deck"]),
                      "ai_god": other["god"], "ai_deck": list(other["deck"])}
        else:
            config = {"human_god": other["god"], "human_deck": list(other["deck"]),
                      "ai_god": own["god"], "ai_deck": list(own["deck"])}
        if blocked is not None:
            config["blocked"] = blocked
        return {"config": config}

    def evaluate(self) -> dict[str, Any]:
        result = super().evaluate()
        result["mixed_vs_phase4"] = self._evaluate_mixed()
        return result

    def _evaluate_mixed(self) -> dict[str, Any]:
        settings = self.config["phase5"]
        games = int(settings.get("mixed_eval_games_per_pair", 1))
        if games <= 0:
            raise ValueError("mixed_eval_games_per_pair doit etre positif")
        requests = []
        for own_index, own in enumerate(self.scenarios):
            for other_index, other in enumerate(self.scenarios):
                for agent_player in (1, 2):
                    for first_player in (1, 2):
                        for offset in range(games):
                            seed = (int(settings["mixed_eval_seed_base"])
                                    + own_index * 1000000 + other_index * 10000
                                    + agent_player * 1000 + first_player * 100 + offset)
                            requests.append((own, other, agent_player, first_player, seed))
        chunks = [requests[index::self.evaluation_num_envs]
                  for index in range(self.evaluation_num_envs)]
        baseline = CheckpointOpponent(self.phase4_baseline, deterministic=True)
        if self.evaluation_num_envs == 1:
            outcomes = self._mixed_worker(self.evaluation_envs[0], chunks[0], baseline)
        else:
            with ThreadPoolExecutor(max_workers=self.evaluation_num_envs) as executor:
                batches = executor.map(
                    lambda request: self._mixed_worker(*request),
                    ((env, chunk, baseline) for env, chunk in zip(
                        self.evaluation_envs, chunks, strict=True)))
                outcomes = [result for batch in batches for result in batch]
        by_god = defaultdict(list)
        by_matchup = defaultdict(list)
        all_outcomes = []
        for own_god, other_god, outcome in outcomes:
            all_outcomes.append(outcome)
            by_god[own_god].append(outcome)
            by_matchup[f"{own_god}_vs_{other_god}"].append(outcome)
        wins = sum(outcome[0] for outcome in all_outcomes)
        draws = sum(outcome[1] for outcome in all_outcomes)
        count = len(all_outcomes)
        return {**self._outcome_stats(all_outcomes),
                "score": (wins + 0.5 * draws) / count,
                "win_wilson_lower": wilson_lower(wins, count),
                "by_god": {name: self._outcome_stats(values)
                           for name, values in by_god.items()},
                "by_matchup": {name: self._outcome_stats(values)
                               for name, values in by_matchup.items()}}

    def _mixed_worker(self, env, requests, baseline):
        previous, previous_player = env.opponent, env.agent_player
        outcomes = []
        try:
            for own, other, player, first, seed in requests:
                if player == 1:
                    config = {"human_god": own["god"], "human_deck": list(own["deck"]),
                              "ai_god": other["god"], "ai_deck": list(other["deck"])}
                else:
                    config = {"human_god": other["god"], "human_deck": list(other["deck"]),
                              "ai_god": own["god"], "ai_deck": list(own["deck"])}
                attempts = int(self.config["evaluation"].get("godot_retry_attempts", 2))
                if attempts <= 0:
                    raise ValueError("evaluation.godot_retry_attempts doit etre positif")
                for attempt in range(attempts):
                    try:
                        info = self._evaluation_game(
                            baseline, 0, player, first, seed, env,
                            {"config": config.copy()})
                        break
                    except GodotProtocolError:
                        env.close()
                        if attempt + 1 == attempts:
                            raise
                episode = info["episode"]
                winner = int(info["winner"])
                outcomes.append((str(own["god"]), str(other["god"]),
                                 (winner == player, winner == 0, float(episode["margin"]))))
        finally:
            env.opponent, env.agent_player = previous, previous_player
        return outcomes

    def _evaluation_score(self, results: dict[str, Any]) -> float:
        weight = float(self.config["phase5"].get("selection_mixed_weight", 0.7))
        if not 0.0 <= weight <= 1.0:
            raise ValueError("selection_mixed_weight doit etre entre 0 et 1")
        return (weight * float(results["mixed_vs_phase4"]["score"])
                + (1.0 - weight) * float(results["win_rate"]))

    def _after_training_update(self, global_step: int, update: int,
                               episodes: list[dict], evaluation: dict | None) -> None:
        settings = self.config["phase5"]
        schedule = settings["weight_schedule"]
        weights = schedule[-1]["weights"]
        for item in schedule:
            if update <= int(item["until_update"]):
                weights = item["weights"]
                break
        self.league.set_weights(weights)
        categories: Counter[str] = Counter()
        matchups: Counter[str] = Counter()
        by_god: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
        by_matchup: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
        by_category: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
        for episode in episodes:
            opponent_id = str(episode.get("opponent_id", ""))
            if not opponent_id:
                raise RuntimeError("episode de ligue sans adversaire identifie")
            score = 1.0 if episode["won"] else (0.5 if episode["draw"] else 0.0)
            self.league.record_result(
                "live", opponent_id, score, global_step,
                {"god": episode["god"], "opponent_god": episode["opponent_god"],
                 "agent_player": episode["agent_player"],
                 "first_player": episode["first_player"]})
            categories[str(episode["opponent_category"])] += 1
            matchups[f"{episode['god']}_vs_{episode['opponent_god']}"] += 1
            outcome = (bool(episode["won"]), bool(episode["draw"]),
                       float(episode["margin"]))
            by_god[str(episode["god"])].append(outcome)
            by_matchup[f"{episode['god']}_vs_{episode['opponent_god']}"].append(outcome)
            by_category[str(episode["opponent_category"])].append(outcome)
        league_metrics = self.league.metrics_snapshot(True)
        self.tracker.log("self_play", global_step, {
            "episodes": len(episodes), "by_category": dict(categories),
            "by_matchup": dict(matchups),
            "outcomes_by_god": {name: self._outcome_stats(values)
                                for name, values in by_god.items()},
            "outcomes_by_matchup": {name: self._outcome_stats(values)
                                    for name, values in by_matchup.items()},
            "outcomes_by_category": {name: self._outcome_stats(values)
                                     for name, values in by_category.items()},
            "league_entries": league_metrics["entries"],
            "league_samples": league_metrics["samples"],
            "league_weights": league_metrics["weights"],
            "live_rating": self.league.ratings.get("live", 1500.0),
        }, {"update": update})
        interval = int(settings["snapshot_every_updates"])
        if interval <= 0:
            raise ValueError("snapshot_every_updates doit etre positif")
        if update % interval == 0:
            name = f"checkpoints/league_{global_step:012d}.pt"
            self._save(name, global_step, evaluation or {}, update)
            self.league.register(self.output / name, global_step,
                                 float((evaluation or {}).get("selection_score", 0.0)), "current")
            # Keep recent and historical opponents represented without changing
            # snapshots already selected by an ongoing episode.
            recent = sorted((item for item in self.league.entries if item.category == "recent"),
                            key=lambda item: item.global_step)
            if len(recent) > int(settings.get("max_recent", 6)):
                self.league.reclassify(recent[0].name, "historical")
        if evaluation and self.best_stage_index == self.curriculum.stage_index:
            best = self.output / "best.pt"
            if best.is_file() and int(self._read_verified_checkpoint(best)["global_step"]) == global_step:
                self.league.register(best, global_step,
                                     float(evaluation["selection_score"]), "best")

    def _checkpoint_extra(self) -> dict[str, Any]:
        return {"phase5": {"completed": self.phase5_completed,
                           "initial_policy_checksum": self.phase4_checksum,
                           "league_directory": str(self.league_directory)}}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Entraine la ligue de self-play (phase 5).")
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[3]
                        / "configs" / "ppo_self_play_v2.yaml")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--phase4", type=Path, help="checkpoint phase4_validated.pt")
    group.add_argument("--resume", type=Path, help="checkpoint de phase 5")
    args = parser.parse_args(argv)
    trainer = PhaseFiveTrainer(args.config, phase4_checkpoint=args.phase4, resume=args.resume)
    trainer.train()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
