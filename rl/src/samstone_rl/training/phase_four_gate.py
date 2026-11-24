"""One schedule and one scoring path for live and recorded phase-4 matches."""

from collections import defaultdict

from samstone_rl.training.curriculum import stages_from_config
from samstone_rl.training.validation import EvaluationSlice, PhaseFourGateReport


def phase_four_cases(config: dict, seed_offset: int = 0) -> list[dict]:
    settings = config["evaluation"]["final_gate"]
    seed = int(settings["seed_base"]) + seed_offset
    cases = []
    for stage in range(len(stages_from_config(config["curriculum"].get("stages")))):
        for scenario in range(len(config["environment"]["scenarios"])):
            for agent in (1, 2):
                for first in (1, 2):
                    for _ in range(int(settings["games_per_slice"])):
                        cases.append(
                            dict(
                                stage=stage, scenario=scenario, agent=agent, first=first, seed=seed
                            )
                        )
                        seed += 1
    return cases


def phase_four_report(config: dict, cases: list[dict], outcomes: list[dict]) -> PhaseFourGateReport:
    stages = stages_from_config(config["curriculum"].get("stages"))
    scenarios = config["environment"]["scenarios"]
    settings = config["evaluation"]["final_gate"]
    groups = defaultdict(list)
    for case, info in zip(cases, outcomes, strict=True):
        winner = info["winner"]
        if type(winner) is not int or winner not in (0, 1, 2):
            raise ValueError("vainqueur invalide dans le tournoi enregistre")
        groups[(case["stage"], case["scenario"], case["agent"], case["first"])].append(winner)
    slices = []
    for (stage, scenario, agent, first), winners in groups.items():
        wins, draws = winners.count(agent), winners.count(0)
        slices.append(
            EvaluationSlice(
                stages[stage].name,
                str(scenarios[scenario]["god"]),
                agent,
                first,
                wins,
                draws,
                len(winners) - wins - draws,
            )
        )
    return PhaseFourGateReport.build(
        slices,
        (stage.name for stage in stages),
        (str(s["god"]) for s in scenarios),
        overall_threshold=float(settings["overall_win_rate"]),
        confidence_floor=float(settings["confidence_floor"]),
        slice_floor=float(settings["minimum_slice_win_rate"]),
        minimum_games_per_slice=int(settings["games_per_slice"]),
        **{
            key: settings.get(key)
            for key in (
                "maximum_loss_rate",
                "non_loss_confidence_floor",
                "maximum_slice_loss_rate",
                "god_thresholds",
                "core_god_thresholds",
            )
        },
    )
