from __future__ import annotations

import argparse
import shutil
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import torch
import yaml

from samstone_rl.fast_engine import StoneCatalog
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.league import LeagueOpponent, SelfPlayLeague
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.training.validation import wilson_lower

from .roster import BOSS_GODS, BossRoster, file_checksum


class BossSpecialistTrainer(PPOTrainer):
    """Fine tune one validated universal policy for one god and final deck."""

    def __init__(self, config_path: str | Path, god_id: str,
                 roster_path: str | Path, *, universal_checkpoint: str | Path | None = None,
                 resume: str | Path | None = None) -> None:
        if god_id not in BOSS_GODS:
            raise ValueError(f"dieu inconnu: {god_id}")
        if (universal_checkpoint is None) == (resume is None):
            raise ValueError("fournir soit universal_checkpoint, soit resume")
        self.god_id = god_id
        self.roster_path = Path(roster_path).resolve()
        self.roster = BossRoster.load(self.roster_path)
        self.roster_checksum = self.roster.checksum()
        if self.roster.catalog_checksum != StoneCatalog().checksum:
            raise ValueError("le catalogue de cartes differe du registre des boss")
        selected = self.roster.deck(god_id)
        self._specialist_scenario = {"god": god_id, "deck": list(selected.stone_ids)}
        self._roster_scenarios = [
            {"god": item.god_id, "deck": list(item.stone_ids)} for item in self.roster.decks]
        config_path = Path(config_path).resolve()
        raw_config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        output_root = Path(raw_config["specialization"]["output_root"])
        if not output_root.is_absolute():
            output_root = config_path.parent.parent / output_root
        output = output_root / god_id
        source = Path(universal_checkpoint or resume).resolve()
        checkpoint = self._read_checkpoint(source)
        specialization = checkpoint.get("specialization", {})
        if universal_checkpoint is not None:
            if not checkpoint.get("phase5", {}).get("completed", False):
                raise ValueError("la specialisation exige phase5_validated.pt")
            if file_checksum(source) != self.roster.policy_checksum:
                raise ValueError("la politique universelle differe du registre")
        else:
            if specialization.get("god_id") != god_id:
                raise ValueError("le checkpoint de reprise concerne un autre dieu")
            if specialization.get("roster_checksum") != self.roster_checksum:
                raise ValueError("le checkpoint de reprise utilise un autre registre")
        if int(checkpoint["config"]["model"]["hidden_dim"]) != int(
                raw_config["model"]["hidden_dim"]):
            raise ValueError("dimension de modele incompatible")
        super().__init__(config_path, output_override=output)
        self.universal_baseline = self.output / "universal_baseline.pt"
        self.universal_checksum = (file_checksum(source) if universal_checkpoint is not None
                                   else str(specialization["universal_checksum"]))
        self.league_directory = self.output / "league"
        if universal_checkpoint is not None:
            if self.universal_baseline.exists() or self.league_directory.exists():
                raise ValueError("run deja initialise; utiliser --resume")
            shutil.copy2(source, self.universal_baseline)
        elif (not self.universal_baseline.is_file()
              or file_checksum(self.universal_baseline) != self.universal_checksum):
            raise ValueError("politique universelle initiale absente ou modifiee")
        settings = self.config["specialization"]
        self.league = SelfPlayLeague(
            self.league_directory, dict(settings["weight_schedule"][0]["weights"]),
            str(self.device))
        self.tracker.update_manifest(
            checksums={"universal_policy": self.universal_checksum,
                       "boss_roster": self.roster_checksum,
                       "catalog": self.roster.catalog_checksum},
            extra={"specialist_god": god_id, "boss_roster": str(self.roster_path)})
        if resume is not None:
            self.load_checkpoint(source)
            if not self.league.entries:
                raise ValueError("ligue absente pour ce checkpoint")
        else:
            self.model.load_state_dict(checkpoint["model"])
            self.curriculum.load_state_dict(checkpoint["curriculum"])
            self.league.register(self.universal_baseline, 0, 0.0, "current")
            self.league.register(self.universal_baseline, 0, 0.0, "best")
            self._save("latest.pt", 0, {}, 0)

    @property
    def scenarios(self) -> list[dict]:
        if hasattr(self, "_specialist_scenario"):
            return [self._specialist_scenario]
        return super().scenarios

    @staticmethod
    def _read_checkpoint(path: Path) -> dict[str, Any]:
        sidecar = path.with_suffix(path.suffix + ".sha256")
        if sidecar.is_file() and sidecar.read_text(encoding="ascii").split()[0] != file_checksum(path):
            raise ValueError(f"checksum invalide: {path}")
        return torch.load(path, map_location="cpu", weights_only=False)

    def _training_opponent(self) -> LeagueOpponent:
        return LeagueOpponent(self.league)

    def _training_scenario_options(self, scenario_index: int, agent_player: int) -> dict:
        del scenario_index
        own = self._specialist_scenario
        mirror_probability = float(self.config["specialization"].get("mirror_probability", 0.10))
        if self.rng.random() < mirror_probability:
            other = own
        else:
            other = self._roster_scenarios[int(self.rng.integers(len(self._roster_scenarios)))]
        return self._match_options(own, other, agent_player)

    @staticmethod
    def _match_options(own: dict, other: dict, agent_player: int) -> dict:
        if agent_player == 1:
            config = {"human_god": own["god"], "human_deck": list(own["deck"]),
                      "ai_god": other["god"], "ai_deck": list(other["deck"])}
        else:
            config = {"human_god": other["god"], "human_deck": list(other["deck"]),
                      "ai_god": own["god"], "ai_deck": list(own["deck"])}
        return {"config": config}

    def evaluate(self) -> dict[str, Any]:
        result = super().evaluate()
        result["specialist_vs_universal"] = self._evaluate_against_universal()
        return result

    def _evaluate_against_universal(self) -> dict[str, Any]:
        settings = self.config["specialization"]
        games = int(settings["evaluation_games_per_matchup"])
        requests = []
        for other_index, other in enumerate(self._roster_scenarios):
            for player in (1, 2):
                for first in (1, 2):
                    for offset in range(games):
                        seed = (int(settings["evaluation_seed_base"]) + other_index * 10000
                                + player * 1000 + first * 100 + offset)
                        requests.append((other, player, first, seed))
        chunks = [requests[index::self.evaluation_num_envs]
                  for index in range(self.evaluation_num_envs)]
        if self.evaluation_num_envs == 1:
            completed = self._specialist_worker(self.evaluation_envs[0], chunks[0])
        else:
            with ThreadPoolExecutor(max_workers=self.evaluation_num_envs) as executor:
                batches = executor.map(
                    lambda request: self._specialist_worker(*request),
                    zip(self.evaluation_envs, chunks, strict=True))
                completed = [item for batch in batches for item in batch]
        values = [item[1] for item in completed]
        by_matchup: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
        for opponent_god, outcome in completed:
            by_matchup[opponent_god].append(outcome)
        wins = sum(item[0] for item in values)
        draws = sum(item[1] for item in values)
        return {**self._outcome_stats(values),
                "score": (wins + 0.5 * draws) / len(values),
                "win_wilson_lower": wilson_lower(wins, len(values)),
                "by_matchup": {name: self._outcome_stats(items)
                               for name, items in by_matchup.items()}}

    def _specialist_worker(self, env, requests):
        opponent = CheckpointOpponent(self.universal_baseline, deterministic=True)
        previous, previous_player = env.opponent, env.agent_player
        results = []
        try:
            for other, player, first, seed in requests:
                options = self._match_options(self._specialist_scenario, other, player)
                info = self._evaluation_game(opponent, 0, player, first, seed, env, options)
                winner = int(info["winner"])
                results.append((str(other["god"]),
                                (winner == player, winner == 0,
                                 float(info["episode"]["margin"]))))
        finally:
            env.opponent, env.agent_player = previous, previous_player
        return results

    def _evaluation_score(self, results: dict[str, Any]) -> float:
        weight = float(self.config["specialization"]["selection_specialist_weight"])
        return (weight * float(results["specialist_vs_universal"]["score"])
                + (1.0 - weight) * float(results["win_rate"]))

    def _after_training_update(self, global_step: int, update: int,
                               episodes: list[dict], evaluation: dict | None) -> None:
        settings = self.config["specialization"]
        weights = settings["weight_schedule"][-1]["weights"]
        for item in settings["weight_schedule"]:
            if update <= int(item["until_update"]):
                weights = item["weights"]
                break
        self.league.set_weights(weights)
        outcomes: dict[str, list[tuple[bool, bool, float]]] = defaultdict(list)
        categories: Counter[str] = Counter()
        for episode in episodes:
            opponent_id = str(episode.get("opponent_id", ""))
            if not opponent_id:
                raise RuntimeError("episode specialise sans adversaire identifie")
            score = 1.0 if episode["won"] else (0.5 if episode["draw"] else 0.0)
            self.league.record_result(
                f"live_{self.god_id}", opponent_id, score, global_step,
                {"god": self.god_id, "opponent_god": episode["opponent_god"],
                 "agent_player": episode["agent_player"],
                 "first_player": episode["first_player"]})
            outcomes[str(episode["opponent_god"])].append(
                (bool(episode["won"]), bool(episode["draw"]), float(episode["margin"])))
            categories[str(episode["opponent_category"])] += 1
        league_metrics = self.league.metrics_snapshot(True)
        self.tracker.log("specialization", global_step, {
            "episodes": len(episodes), "opponent_categories": dict(categories),
            "by_matchup": {name: self._outcome_stats(items)
                           for name, items in outcomes.items()},
            "league_samples": league_metrics["samples"],
            "league_weights": league_metrics["weights"],
            "rating": self.league.ratings.get(f"live_{self.god_id}", 1500.0),
        }, {"god": self.god_id, "update": update})
        interval = int(settings["snapshot_every_updates"])
        if interval <= 0:
            raise ValueError("snapshot_every_updates doit etre positif")
        if update % interval == 0:
            name = f"checkpoints/specialist_{global_step:012d}.pt"
            self._save(name, global_step, evaluation or {}, update)
            self.league.register(self.output / name, global_step,
                                 float((evaluation or {}).get("selection_score", 0.0)), "current")
            recent = sorted((item for item in self.league.entries if item.category == "recent"),
                            key=lambda item: item.global_step)
            if len(recent) > int(settings.get("max_recent", 6)):
                self.league.reclassify(recent[0].name, "historical")
        if evaluation:
            best = self.output / "best.pt"
            if best.is_file() and int(self._read_checkpoint(best)["global_step"]) == global_step:
                self.league.register(best, global_step,
                                     float(evaluation["selection_score"]), "best")

    def _checkpoint_extra(self) -> dict[str, Any]:
        return {"specialization": {
            "completed": False, "god_id": self.god_id,
            "universal_checksum": self.universal_checksum,
            "roster_checksum": self.roster_checksum,
            "roster_path": str(self.roster_path),
        }}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Specialise un boss pour son dieu et son deck.")
    parser.add_argument("god_id", choices=BOSS_GODS)
    parser.add_argument("--config", type=Path,
                        default=Path(__file__).resolve().parents[3]
                        / "configs" / "boss_specialization.yaml")
    parser.add_argument("--roster", type=Path,
                        default=Path("runs/boss_specialists/boss_roster.json"))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--universal", type=Path, help="phase5_validated.pt")
    source.add_argument("--resume", type=Path)
    args = parser.parse_args(argv)
    trainer = BossSpecialistTrainer(
        args.config, args.god_id, args.roster,
        universal_checkpoint=args.universal, resume=args.resume)
    trainer.train()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
