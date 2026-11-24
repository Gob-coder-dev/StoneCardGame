"""Explicit god exceptions, evaluated independently of the remaining gods.

Exceptions use pooled games within one evaluation/stage. Their balanced slices
still require complete coverage, but do not inherit the core rate floors.
"""

import math
from collections.abc import Mapping


def parse_god_thresholds(values=None):
    if values is None:
        return {}
    if not isinstance(values, Mapping):
        raise ValueError("god_thresholds doit etre un dictionnaire")
    result = {}
    for god, settings in values.items():
        if (
            not isinstance(god, str)
            or not god
            or not isinstance(settings, Mapping)
            or set(settings) != {"minimum_win_rate", "maximum_loss_rate"}
        ):
            raise ValueError("seuils par dieu invalides")
        rates = {name: float(value) for name, value in settings.items()}
        if not all(math.isfinite(v) and 0 <= v <= 1 for v in rates.values()):
            raise ValueError("les seuils par dieu doivent etre entre 0 et 1")
        result[god] = rates
    return result


def threshold_groups(by_god, thresholds, core_check):
    """Return auditable criteria for core gods and each configured exception."""
    if not isinstance(by_god, Mapping) or not by_god:
        return {"eligible": False, "missing_gods": sorted(thresholds), "groups": {}}
    missing = sorted(set(thresholds) - set(by_god))
    groups = {}
    core = [0, 0, 0]
    for god, counts in by_god.items():
        wins, draws, games = (int(counts[name]) for name in ("wins", "draws", "games"))
        if min(wins, draws, games - wins - draws) < 0 or games <= 0:
            return {"eligible": False, "invalid_god": god, "groups": {}}
        if god not in thresholds:
            core = [a + b for a, b in zip(core, (wins, draws, games), strict=True)]
            continue
        win_rate, loss_rate = wins / games, (games - wins - draws) / games
        settings = thresholds[god]
        groups[god] = dict(
            wins=wins,
            draws=draws,
            games=games,
            win_rate=win_rate,
            loss_rate=loss_rate,
            criteria=settings,
            eligible=(
                win_rate + 1e-12 >= settings["minimum_win_rate"]
                and loss_rate <= settings["maximum_loss_rate"] + 1e-12
            ),
        )
    groups["core"] = {
        "wins": core[0],
        "draws": core[1],
        "games": core[2],
        **(core_check(*core) if core[2] else {"eligible": True}),
    }
    return dict(
        eligible=not missing and all(g["eligible"] for g in groups.values()),
        missing_gods=missing,
        groups=groups,
    )
