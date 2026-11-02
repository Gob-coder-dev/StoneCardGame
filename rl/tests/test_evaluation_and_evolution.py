import pytest
from test_decks import synthetic_catalog

from samstone_rl.evaluation import (
    CandidateEvaluation,
    ComparisonCase,
    ComparisonOutcome,
    MatchRecord,
    MatchStore,
    compute_fitness,
    grouped_summary,
    paired_delta,
)
from samstone_rl.evaluation.phase_six_gate import PhaseSixGate, write_gate_result
from samstone_rl.training.deck_evolution import (
    DeckEvolution,
    EvolutionConfig,
    EvolutionStateStore,
    RankedCandidate,
)


def record(candidate_hash: str, opponent: str, seed: int, won: bool) -> MatchRecord:
    return MatchRecord("engine", "catalog", "policy", candidate_hash, "inari", ("a",),
                       opponent, "inari", ("b",), seed, 1, 1, 1 if won else 2,
                       10 if won else 6, 6 if won else 10)


def test_sqlite_cache_and_conservative_fitness(tmp_path):
    records = tuple(record("candidate", "easy" if index < 50 else "hard", index, index % 4 != 0)
                    for index in range(100))
    with MatchStore(tmp_path / "matches.sqlite3") as store:
        store.insert_many(records)
        restored = store.records_for("engine", "catalog", "policy", "candidate")
        assert len(restored) == 100
        assert store.find("engine", "catalog", "policy", "candidate", "easy", ("b",), 0, 1, 1)
        assert store.find("engine", "catalog", "policy", "candidate", "easy", ("changed",), 0, 1, 1) is None
    evaluation = compute_fitness(restored)
    assert evaluation.games == 100
    assert evaluation.win_rate == 0.75
    assert 0.0 < evaluation.wilson_lower < evaluation.win_rate
    assert evaluation.worst_matchup_win_rate == 0.74


def test_paired_checkpoint_summary_compares_identical_cases():
    cases = tuple(ComparisonCase(index, 100 + index, 0, "inari", 1, 1, 0)
                  for index in range(3))
    reference = (
        ComparisonOutcome("reference", "a.pt", cases[0], 1, 2, 10),
        ComparisonOutcome("reference", "a.pt", cases[1], 2, -1, 12),
        ComparisonOutcome("reference", "a.pt", cases[2], 0, 0, 14),
    )
    candidate = (
        ComparisonOutcome("candidate", "b.pt", cases[0], 1, 3, 10),
        ComparisonOutcome("candidate", "b.pt", cases[1], 1, 2, 12),
        ComparisonOutcome("candidate", "b.pt", cases[2], 0, 0, 14),
    )
    summary = grouped_summary(candidate)
    assert summary["overall"]["wins"] == 2
    assert summary["by_god"]["inari"]["games"] == 3
    delta = paired_delta(reference, candidate)
    assert delta == {"games": 3, "candidate_better": 1, "same": 2,
                     "candidate_worse": 0, "decisive_games": 1,
                     "two_sided_sign_p_value": 1.0, "mean_score_delta": 1 / 3}


class AcceptAll:
    def require_all_valid(self, candidates):
        assert tuple(candidates)


def test_evolution_is_resumable_and_improves_toy_objective(tmp_path):
    catalog = synthetic_catalog()

    def evaluate(candidate):
        score = sum(catalog.variants[item].level for item in candidate.stone_ids) / 24.0
        from samstone_rl.evaluation import CandidateEvaluation
        return CandidateEvaluation(candidate.deck_hash, 100, int(score * 100), 0,
                                   100 - int(score * 100), score, score, score, score, score)

    config = EvolutionConfig(population_size=12, elites=2, crossover_children=6,
                             strong_mutations=2, random_immigrants=2,
                             tournament_size=3, generations=3)
    state = EvolutionStateStore(tmp_path / "state.json")
    evolution = DeckEvolution(catalog, AcceptAll(), evaluate, "policy", config, state, 91)
    ranking = evolution.run("inari")
    assert len(ranking) == 12
    assert state.path.is_file()
    resumed = DeckEvolution(catalog, AcceptAll(), evaluate, "policy", config, state, 999)
    assert resumed.run("inari")[0].candidate == ranking[0].candidate
    changed = EvolutionConfig(population_size=12, elites=2, crossover_children=6,
                              strong_mutations=2, random_immigrants=2,
                              tournament_size=3, generations=4)
    with pytest.raises(ValueError, match="configuration"):
        DeckEvolution(catalog, AcceptAll(), evaluate, "policy", changed, state, 999).run("inari")


def test_phase_six_gate_is_strict_and_writes_atomic_artifact(tmp_path):
    catalog = synthetic_catalog()
    candidate = catalog.candidate("inari", [f"n{index:02d}_n3" for index in range(8)])
    evaluation = CandidateEvaluation(candidate.deck_hash, 2400, 1440, 0, 960,
                                     0.60, 0.58, 0.45, 0.1, 0.55)
    ranking = (RankedCandidate(candidate, evaluation),)
    gate = PhaseSixGate(0.55, 0.40)

    payload = write_gate_result(tmp_path / "gate.json", "inari", ranking, gate,
                                "engine", "catalog", "policy")

    assert payload["passed"] is True
    assert (tmp_path / "gate.json").is_file()
    assert not (tmp_path / "gate.json.tmp").exists()
    assert PhaseSixGate(0.61, 0.40).passes(ranking) is False
    pilot = write_gate_result(tmp_path / "pilot.json", "inari", ranking, gate,
                              "engine", "catalog", "policy", official=False)
    assert pilot["thresholds_passed"] is True
    assert pilot["passed"] is False
