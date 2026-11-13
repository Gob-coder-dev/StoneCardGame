"""Application déclarative de la courbe de difficulté de campagne."""
from __future__ import annotations

from collections import defaultdict
from typing import Any


def apply_balance(nodes: dict[str, dict[str, Any]],
                  depth: dict[str, int], config: dict[str, Any],
                  intro_ids: set[str],
                  predecessors: dict[str, list[str]]) -> None:
    chapters = config["chapters"]
    required_gap = float(config.get("required_boss_precision_gap", 0.06))
    required_bosses = {
        node_id for node_id, node in nodes.items()
        if node.get("mini_boss_kind") == "mandatory" or node.get("type") == "boss"
    }
    boss_approaches = {
        parent_id
        for boss_id in required_bosses
        for parent_id in predecessors.get(boss_id, [])
    }
    by_chapter: dict[str, list[str]] = defaultdict(list)
    for node_id, node in nodes.items():
        by_chapter[node["chapter"]].append(node_id)

    for chapter, node_ids in by_chapter.items():
        if chapter not in chapters:
            raise ValueError(f"profil de chapitre absent : {chapter}")
        profile = chapters[chapter]
        ordered = sorted(node_ids, key=lambda value: (depth[value], value))
        ordinary = [value for value in ordered
                    if nodes[value]["type"] not in {"tutorial", "mini_boss", "boss"}
                    and value not in intro_ids]
        for node_id in ordered:
            node = nodes[node_id]
            node["stage_id"] = str(profile["stage_id"])
            if node["type"] == "tutorial" or node_id in intro_ids:
                node["balance_profile"] = "tutorial" if node["type"] == "tutorial" else "initiation"
                continue
            challenge = bool(node.get("dead_end", False) or node.get("mini_boss_kind") == "optional"
                             or "_path_" in node_id)
            if node["type"] == "boss":
                balance_profile = "boss"
            elif node["type"] == "mini_boss":
                balance_profile = "challenge" if challenge else "required_boss"
            elif node_id in boss_approaches:
                balance_profile = "boss_approach"
            elif challenge:
                balance_profile = "challenge"
            else:
                balance_profile = "standard"
            node["balance_profile"] = balance_profile

            ratio = _ratio(node_id, ordinary)
            tier = _interpolate_int(int(profile["tier_min"]),
                                    int(profile["tier_max"]), ratio)
            precision = _interpolate(float(profile["precision_min"]),
                                     float(profile["precision_max"]), ratio)
            if node_id in boss_approaches:
                precision = min(precision,
                                float(profile["precision_max"]) - required_gap)
            if challenge:
                challenge_max = float(profile["challenge_precision_max"])
                precision = min(challenge_max, precision + (challenge_max - precision) * 0.72)
            if node["type"] == "mini_boss":
                precision = min(float(profile["challenge_precision_max"]), precision + 0.04)
            if node["type"] == "boss":
                precision = float(profile["challenge_precision_max"])

            encounter = node["encounter"]
            encounter["max_power_tier"] = tier
            encounter["ai_profile"] = {
                "precision": round(precision, 2),
                "anticipation": precision >= 0.92 and node["stage_id"] in {"late_game", "endgame"},
            }
            if node["type"] in {"mini_boss", "boss"}:
                encounter["series_format"] = "ft3" if node["type"] == "boss" else "ft2"
            elif node_id in config.get("normal_ft2_nodes", []):
                encounter["series_format"] = "ft2"
            else:
                encounter["series_format"] = "ft1"
            _ensure_allowed_mode(node, profile, config)
            # La Selection exige un catalogue assez large pour proposer huit
            # paires legales a n'importe quel dieu du joueur.
            if encounter["game_mode"] == "draft":
                encounter["max_power_tier"] = max(3, encounter["max_power_tier"])

    # Le dernier boss est la seule rencontre qui atteint volontairement 100 %.
    if "final_01" in nodes:
        nodes["final_01"]["encounter"]["ai_profile"] = {
            "precision": 1.0, "anticipation": True}
        nodes["final_01"]["encounter"]["series_format"] = "ft3"

    _smooth_optional_branches(nodes)
    _smooth_required_bosses(nodes, predecessors, chapters, required_gap)


def deck_target_ratio(node: dict[str, Any]) -> float:
    profile = str(node.get("balance_profile", "standard"))
    return {
        "tutorial": 0.25,
        "initiation": 0.30,
        "boss_approach": 0.36,
        "standard": 0.46,
        "required_boss": 0.64,
        "challenge": 0.78,
        "boss": 0.90,
    }.get(profile, 0.50)


def _smooth_required_bosses(nodes: dict[str, dict[str, Any]],
                            predecessors: dict[str, list[str]],
                            chapters: dict[str, dict[str, Any]],
                            precision_gap: float) -> None:
    """Impose un vrai pic de difficulté aux passages obligatoires.

    Une approche directe reste sous le plafond ordinaire du chapitre. Le boss
    qui la suit gagne au moins ``precision_gap``, ne baisse jamais de palier et
    reste borné par le plafond de challenge déclaré par l'authoring.
    """
    for boss_id, boss in nodes.items():
        is_required = boss.get("mini_boss_kind") == "mandatory"
        if not is_required and boss.get("type") != "boss":
            continue
        parent_ids = [value for value in predecessors.get(boss_id, [])
                      if value in nodes]
        if not parent_ids:
            continue
        profile = chapters[boss["chapter"]]
        ceiling = float(profile["challenge_precision_max"])
        approach_ceiling = max(float(profile["precision_min"]),
                               float(profile["precision_max"]) - precision_gap)
        for parent_id in parent_ids:
            parent = nodes[parent_id]
            parent_precision = float(
                parent["encounter"]["ai_profile"]["precision"])
            rounded_approach = round(approach_ceiling, 2)
            if parent_precision > rounded_approach:
                parent["encounter"]["ai_profile"] = {
                    "precision": rounded_approach,
                    # Une approche plafonnée reste un combat de préparation :
                    # l'anticipation à 92 % est réservée au pic qui la suit.
                    "anticipation": rounded_approach > 0.92
                        and parent.get("stage_id") in {"late_game", "endgame"},
                }
        parent_precision = max(
            float(nodes[value]["encounter"]["ai_profile"]["precision"])
            for value in parent_ids
        )
        boss_precision = max(
            float(boss["encounter"]["ai_profile"]["precision"]),
            parent_precision + precision_gap,
        )
        boss_precision = min(ceiling, boss_precision)
        rounded_boss = round(boss_precision, 2)
        boss["encounter"]["ai_profile"] = {
            "precision": rounded_boss,
            "anticipation": rounded_boss >= 0.92
                and boss.get("stage_id") in {"late_game", "endgame"},
        }
        boss["encounter"]["max_power_tier"] = max(
            int(boss["encounter"]["max_power_tier"]),
            max(int(nodes[value]["encounter"]["max_power_tier"])
                for value in parent_ids),
        )


def _smooth_optional_branches(nodes: dict[str, dict[str, Any]]) -> None:
    """Garantit une montee lisible jusqu'a chaque mini-boss d'impasse."""
    for boss_id, boss in nodes.items():
        if boss.get("type") != "mini_boss" or boss.get("mini_boss_kind") != "optional":
            continue
        prefix = f"{boss_id}_path_"
        path_ids = sorted(
            (value for value in nodes if value.startswith(prefix)),
            key=lambda value: int(value.removeprefix(prefix)),
        )
        if not path_ids:
            continue
        boss_precision = float(boss["encounter"]["ai_profile"]["precision"])
        start = max(0.0, boss_precision - 0.02 * (len(path_ids) + 1))
        for index, path_id in enumerate(path_ids, start=1):
            precision = min(boss_precision - 0.01,
                            start + 0.02 * (index - 1))
            nodes[path_id]["encounter"]["ai_profile"] = {
                "precision": round(precision, 2),
                "anticipation": precision >= 0.92
                    and nodes[path_id].get("stage_id") in {"late_game", "endgame"},
            }


def _ensure_allowed_mode(node: dict[str, Any], profile: dict[str, Any],
                         config: dict[str, Any]) -> None:
    encounter = node["encounter"]
    mode = str(encounter["game_mode"])
    if mode in profile["allowed_modes"]:
        return
    fallback = str(config.get("mode_fallbacks", {}).get(mode, "classic"))
    theme = str(node.get("theme_god_id", ""))
    encounter["game_mode"] = fallback
    encounter["generator_god_id"] = ""
    encounter["generator_min_god_cards"] = 0
    encounter["mirror_fixed_deck"] = []
    encounter["fixed_deck"] = []
    if fallback == "classic":
        encounter["opponent_god_policy"] = "fixed"
        encounter["opponent_deck_policy"] = "fixed"
        encounter["fixed_god_id"] = theme
    elif fallback == "random":
        encounter["opponent_god_policy"] = "generated"
        encounter["opponent_deck_policy"] = "generated"
        encounter["fixed_god_id"] = ""


def _ratio(node_id: str, ordered: list[str]) -> float:
    if not ordered or node_id not in ordered or len(ordered) == 1:
        return 0.5
    return ordered.index(node_id) / float(len(ordered) - 1)


def _interpolate(minimum: float, maximum: float, ratio: float) -> float:
    return minimum + (maximum - minimum) * max(0.0, min(1.0, ratio))


def _interpolate_int(minimum: int, maximum: int, ratio: float) -> int:
    return round(_interpolate(float(minimum), float(maximum), ratio))
