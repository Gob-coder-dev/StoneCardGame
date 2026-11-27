"""CPU inference, durable compact tournaments and paired phase-5 benchmarks."""

from collections import OrderedDict, defaultdict
from contextlib import contextmanager
from copy import deepcopy

import torch

from samstone_rl.bridge import GodotProtocolError
from samstone_rl.evaluation.tournament import run_tournament, tournament_path
from samstone_rl.models.policy import act_from_info, build_policy
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.training.phase_five_decks import assign_match_decks
from samstone_rl.training.phase_five_protocol import duel_cases, duel_summary, outcome_stats
from samstone_rl.utils.checkpoints import file_checksum, policy_checksum


@contextmanager
def cpu_inference_threads():
    """Avoid nested CPU pools for single-state inference; restore PPO's setting."""
    previous = torch.get_num_threads()
    if previous != 1:
        torch.set_num_threads(1)
    try:
        yield
    finally:
        if previous != 1:
            torch.set_num_threads(previous)


class PhaseFiveArena:
    def __init__(self, trainer):
        self.trainer = trainer
        self.config = trainer.config
        self.scenarios = trainer.scenarios
        self._opponents = OrderedDict()

    def live_actor(self):
        if next(self.trainer.model.parameters()).device.type == "cpu":
            return deepcopy(self.trainer.model).eval()
        # Model construction must not consume the learner's Torch RNG.
        with torch.random.fork_rng(devices=[]):
            actor = build_policy(self.config)
        actor.load_state_dict(
            {k: v.detach().cpu() for k, v in self.trainer.model.state_dict().items()}
        )
        actor.eval()
        return actor

    def opponent(self, path):
        key = (str(path.resolve()), file_checksum(path))
        if key not in self._opponents:
            with cpu_inference_threads(), torch.random.fork_rng(devices=[]):
                self._opponents[key] = CheckpointOpponent(path, device="cpu", deterministic=True)
            if len(self._opponents) > 8:
                self._opponents.popitem(last=False)
        self._opponents.move_to_end(key)
        return self._opponents[key]

    def options(self, case):
        home, away = self.scenarios[case["left"]], self.scenarios[case["right"]]
        return {
            "config": dict(
                human_god=home["god"],
                ai_god=away["god"],
                human_deck=list(case.get("left_deck", home["deck"])),
                ai_deck=list(case.get("right_deck", away["deck"])),
                first_player=case["first"],
            )
        }

    def _play(self, env, case, actor, opponent):
        attempts = int(self.config["evaluation"].get("godot_retry_attempts", 2))
        if attempts < 1:
            raise ValueError("godot_retry_attempts doit etre positif")
        for attempt in range(attempts):
            try:
                env.opponent, env.agent_player = opponent, case["player"]
                obs, info = env.reset(seed=case["seed"], options=self.options(case))
                while "episode" not in info:
                    with torch.no_grad():
                        action, _, _ = act_from_info(actor, obs, info)
                    obs, _, _, _, info = env.step(int(action.item()))
                # A terminal feature matrix is large and irrelevant to the audit.
                return dict(
                    winner=int(info["winner"]),
                    margin=float(info["episode"]["margin"]),
                    turns=int(info["episode"]["turns"]),
                )
            except GodotProtocolError:
                env.close()
                if attempt + 1 == attempts:
                    raise

    def run(self, cases, actor, opponent, label, opponent_identity):
        trainer = self.trainer
        previous = [(env.opponent, env.agent_player) for env in trainer.evaluation_envs]
        identity = dict(
            protocol="champion_v1",
            provenance=trainer.provenance,
            oracle=trainer._evaluation_manifest(),
            actor=policy_checksum(actor),
            opponent=opponent_identity,
            scenarios=self.scenarios,
            label=label,
        )
        try:
            with cpu_inference_threads():
                outcomes = run_tournament(
                    cases,
                    trainer.evaluation_envs,
                    lambda env, case: self._play(env, case, actor, opponent(case)),
                    trainer.output / "evaluations/phase5",
                    identity,
                    lambda completed, total: trainer._phase5_progress(label, completed, total),
                )
            if trainer.phase5_state.get("pending") is not None:
                ledger = tournament_path(cases, trainer.output / "evaluations/phase5", identity)
                trainer._phase5_evidence.append(
                    dict(
                        path=str(ledger.relative_to(trainer.output)),
                        games=len(cases),
                        identity=identity,
                    )
                )
            return outcomes
        finally:
            for env, (original, player) in zip(trainer.evaluation_envs, previous, strict=True):
                env.opponent, env.agent_player = original, player

    def duels(self, actor, opponent_path, repetitions, seed, label):
        opponent = self.opponent(opponent_path)
        cases = duel_cases(len(self.scenarios), repetitions, seed)
        assign_match_decks(cases, self.scenarios, seed, label)
        outcomes = self.run(
            cases, actor, lambda _: opponent, label, policy_checksum(opponent.model)
        )
        return cases, outcomes, duel_summary(cases, outcomes, self.scenarios)

    def champion_reference(self, cases, champion_path, label):
        opponent = self.opponent(champion_path)
        # Both policies are the champion: one physical match supplies both views.
        physical = [case for case in cases if case["player"] == 1]
        outcomes = self.run(
            physical, opponent.model, lambda _: opponent, label, policy_checksum(opponent.model)
        )
        by_block = {
            case["block"]: outcome for case, outcome in zip(physical, outcomes, strict=True)
        }
        return duel_summary(cases, [by_block[c["block"]] for c in cases], self.scenarios)

    def retention(self, actor, reference_path, repetitions, seed, label="retention"):
        trainer = self.trainer
        cases = []
        gods = len(self.scenarios)
        rotation = seed // 1_000_000
        deck_seed = seed
        for stage in range(len(trainer.curriculum.stages)):
            for own in range(gods):
                for rival in range(gods):
                    for repeat in range(repetitions):
                        # Rotate the four camp/opening combinations across
                        # equally represented ordered matchups and repeats.
                        setup = (own * gods + rival + stage + repeat + rotation) % 4
                        camp, opening = divmod(setup, 2)
                        left, right = (own, rival) if camp == 0 else (rival, own)
                        cases.append(
                            dict(
                                left=left,
                                right=right,
                                player=camp + 1,
                                first=opening + 1,
                                seed=seed,
                                stage=stage,
                            )
                        )
                        seed += 1
        assign_match_decks(cases, self.scenarios, deck_seed, label)

        def profile(case):
            return trainer.curriculum.stages[case["stage"]].opponent()

        profiles = [
            dict(
                name=s.name,
                precision=s.precision,
                anticipation=s.anticipation,
                probability=s.anticipation_probability,
            )
            for s in trainer.curriculum.stages
        ]
        candidate = self.run(cases, actor, profile, f"{label}_candidate", profiles)
        reference = self.opponent(reference_path)
        baseline = self.run(cases, reference.model, profile, f"{label}_reference", profiles)

        def summarize(outcomes):
            groups = defaultdict(list)
            for case, info in zip(cases, outcomes, strict=True):
                score = 0.5 if info["winner"] == 0 else float(info["winner"] == case["player"])
                groups[f"stage:{trainer.curriculum.stages[case['stage']].name}"].append(score)
                own = case["left"] if case["player"] == 1 else case["right"]
                groups[f"god:{self.scenarios[own]['god']}"].append(score)
            return {key: outcome_stats(values) for key, values in groups.items()}

        candidate, baseline = summarize(candidate), summarize(baseline)
        settings = self.config["phase5"]["retention"]
        deltas = {key: candidate[key]["win_rate"] - baseline[key]["win_rate"] for key in baseline}
        failed = [
            key
            for key, delta in deltas.items()
            if delta
            < -float(
                settings[
                    "maximum_stage_regression"
                    if key.startswith("stage:")
                    else "maximum_god_regression"
                ]
            )
            - 1e-12
        ]
        return dict(
            matchups="all_ordered",
            games_per_policy=len(cases),
            passed=not failed,
            win_rate_deltas=deltas,
            failed_groups=failed,
            candidate=candidate,
            reference=baseline,
        )
