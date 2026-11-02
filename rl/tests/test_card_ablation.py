from test_decks import synthetic_catalog

from samstone_rl.evaluation import MatchRecord, paired_ablation, replacement_variants


def _record(deck_hash: str, seed: int, winner: int) -> MatchRecord:
    return MatchRecord("engine", "catalog", "policy", deck_hash, "inari", ("a",),
                       "opponent", "izanami", ("b",), seed, 1, 1, winner, 10, 6)


def test_replacement_variants_are_legal_bounded_and_unique():
    catalog = synthetic_catalog()
    baseline = catalog.candidate("inari", [f"n{index:02d}_n2" for index in range(8)])
    variants = replacement_variants(catalog, baseline, alternatives_per_card=2,
                                    maximum_cost_delta=100)
    assert variants
    assert len({item.candidate.deck_hash for item in variants}) == len(variants)
    assert all(not catalog.problems(item.candidate) for item in variants)
    assert all(item.removed not in item.candidate.stone_ids for item in variants)
    assert all(sum(item.removed == card for item in variants) <= 2
               for card in baseline.stone_ids)


def test_paired_ablation_compares_identical_seeds():
    baseline = (_record("base", 1, 2), _record("base", 2, 1), _record("base", 3, 0))
    replacement = (_record("new", 1, 1), _record("new", 2, 1), _record("new", 3, 1))
    result = paired_ablation(baseline, replacement)
    assert result["games"] == 3
    assert result["replacement_better"] == 2
    assert result["replacement_worse"] == 0
    assert result["mean_score_delta"] == 0.5
