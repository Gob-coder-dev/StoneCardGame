"""Choose decks from reproducible training and held-out phase-5 pools."""

from collections import Counter
from random import Random

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.decks.catalog import DeckCatalog
from samstone_rl.decks.validation import GodotDeckValidator

FAMILY_COUNTS = ("7", "6", "5", "4")
DECK_POOLS = ("training_decks", "validation_decks", "holdout_decks")


def validate_deck_pools(environment):
    scenarios = environment["scenarios"]
    if not any(key in case for case in scenarios for key in DECK_POOLS):
        return
    with GodotProcess(godot_path=environment.get("godot_path")) as bridge:
        catalog = DeckCatalog(bridge.deck_catalog())
        candidates = []
        used = set()
        for scenario in scenarios:
            god = scenario["god"]
            for key in DECK_POOLS:
                pool = scenario.get(key, {})
                if set(pool) != set(FAMILY_COUNTS) or any(not decks for decks in pool.values()):
                    raise ValueError(f"ratios manquants pour {god} dans {key}")
                for ratio, decks in pool.items():
                    for deck in decks:
                        candidate = catalog.candidate(god, deck)
                        family = sum(catalog.variants[card].affinity == god for card in deck)
                        if family != int(ratio) or catalog.cost(deck) != catalog.deck_budget:
                            raise ValueError(f"ratio ou budget invalide pour {god} dans {key}")
                        if candidate.deck_hash in used:
                            raise ValueError(f"composition dupliquee pour {god} dans {key}")
                        used.add(candidate.deck_hash)
                        candidates.append(candidate)
            if scenario["deck"] not in scenario["training_decks"]["6"]:
                raise ValueError(f"deck par defaut absent du pool de formation pour {god}")
        validator = GodotDeckValidator(bridge, catalog)
        if any(
            not result.valid or result.cost != catalog.deck_budget
            for result in validator.validate_many(candidates)
        ):
            raise ValueError("Godot a refuse un deck ou son budget")


def training_deck(scenario, rng):
    pool = scenario.get("training_decks")
    if pool is None:
        return scenario["deck"]
    decks = pool[FAMILY_COUNTS[int(rng.integers(len(FAMILY_COUNTS)))]]
    return decks[int(rng.integers(len(decks)))]


def assign_match_decks(cases, scenarios, seed, label):
    """Rotate ratios by god and camp, reusing a physical setup on role swaps."""
    pool = "holdout_decks" if label.startswith(("final_", "history_5_")) else "validation_decks"
    if pool not in scenarios[0]:
        return
    rng = Random(seed)
    offsets = {
        (i, side): rng.randrange(len(FAMILY_COUNTS))
        for i in range(len(scenarios))
        for side in ("left", "right")
    }
    orders = {}
    for index, side in offsets:
        for ratio in FAMILY_COUNTS:
            decks = scenarios[index][pool][ratio]
            orders[index, side, ratio] = rng.sample(decks, len(decks))
    counts = Counter()
    setups = {}
    for case in cases:
        if case["seed"] not in setups:
            setup = {}
            for side in ("left", "right"):
                index = case[side]
                key = (index, side)
                turn = counts[key]
                ratio = FAMILY_COUNTS[(offsets[key] + turn) % len(FAMILY_COUNTS)]
                counts[key] += 1
                decks = orders[index, side, ratio]
                setup[f"{side}_deck"] = decks[turn // len(FAMILY_COUNTS) % len(decks)]
                setup[f"{side}_ratio"] = ratio
            setups[case["seed"]] = setup
        case.update(setups[case["seed"]])
