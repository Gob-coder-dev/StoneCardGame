import numpy as np
import pytest

from samstone_rl.decks import DeckCatalog, DeckGenerator, DeckOperators


def synthetic_catalog() -> DeckCatalog:
    variants = []
    for lineage_index in range(12):
        lineage = f"n{lineage_index:02d}"
        for level in range(1, 4):
            variants.append(
                {
                    "stone_id": f"{lineage}_n{level}",
                    "lineage_id": lineage,
                    "level": level,
                    "max_level": 3,
                    "affinity": "neutral" if lineage_index < 10 else "veskar",
                    "cost": float(level + lineage_index % 3),
                }
            )
    return DeckCatalog(
        {
            "schema_version": 1,
            "deck_size": 8,
            "deck_budget": 40,
            "checksum": "synthetic",
            "gods": [{"id": "veskar"}],
            "variants": variants,
        }
    )


def test_generation_mutation_and_crossover_stay_legal():
    catalog = synthetic_catalog()
    rng = np.random.default_rng(123)
    generator = DeckGenerator(catalog)
    operators = DeckOperators(catalog)
    candidates = [generator.random_candidate("veskar", rng) for _ in range(100)]
    assert all(not catalog.problems(candidate) for candidate in candidates)
    mutated = [operators.mutate(candidate, rng) for candidate in candidates]
    assert all(not catalog.problems(candidate) for candidate in mutated)
    children = [
        operators.crossover(candidates[index], mutated[index], rng)
        for index in range(len(candidates))
    ]
    assert all(not catalog.problems(candidate) for candidate in children)
    assert all(
        len({catalog.variants[item].lineage_id for item in candidate.stone_ids}) == 8
        for candidate in children
    )


def test_candidate_hash_ignores_input_order():
    catalog = synthetic_catalog()
    generator = DeckGenerator(catalog)
    candidate = generator.random_candidate("veskar", np.random.default_rng(2))
    reversed_candidate = catalog.candidate("veskar", reversed(candidate.stone_ids))
    assert reversed_candidate.stone_ids == candidate.stone_ids
    assert reversed_candidate.deck_hash == candidate.deck_hash


def test_budget_matching_preserves_existing_lineages_order_and_affinities():
    catalog = synthetic_catalog()
    generator = DeckGenerator(catalog)
    original = ("n11_n1", "n06_n1", "n05_n1", "n10_n1", "n04_n1", "n03_n1", "n02_n1", "n01_n1")
    target = catalog.cost(original) + 2
    matched = generator.match_budget("veskar", original, target)
    assert catalog.cost(matched) == target
    assert catalog.candidate("veskar", matched)
    assert [catalog.variants[x].lineage_id for x in matched] == [
        catalog.variants[x].lineage_id for x in original
    ]
    assert max(catalog.variants[x].level for x in matched) <= 3
    with pytest.raises(ValueError, match="indisponible"):
        generator.match_budget("veskar", original, 0.25)
