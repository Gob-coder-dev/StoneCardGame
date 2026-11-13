"""Attribution déterministe des récompenses de première victoire."""
from __future__ import annotations

from collections import defaultdict
from typing import Any


RARITY_RANK = {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
STAGE_MAX_RARITY = {
    "tutorial": "common",
    "initiation": "common",
    "early_game": "rare",
    "pre_epic": "rare",
    "epic_intro": "epic",
    "epic_game": "epic",
    "pre_legendary": "epic",
    "legendary_intro": "legendary",
    "legendary_game": "legendary",
    "late_game": "legendary",
    "endgame": "legendary",
}


def assign_rewards(nodes: dict[str, dict[str, Any]], config: dict[str, Any],
                   stone_catalog: dict[str, dict[str, str]],
                   lineage_catalog: dict[str, dict[str, str]]) -> None:
    interval = max(1, int(config.get("normal_card_interval", 4)))
    chapter_indices: dict[str, int] = defaultdict(int)
    for node_id, node in nodes.items():
        encounter = node["encounter"]
        tier = int(encounter["max_power_tier"])
        precision = float(encounter["ai_profile"]["precision"])
        boss_bonus = 18 if node["type"] == "boss" else 10 if node["type"] == "mini_boss" else 0
        base = 8 + tier * 3 + round(precision * 12) + boss_bonus
        cards: list[dict[str, Any]] = []
        profile_id = ""
        if node_id == "tuto_01":
            cards = [
                {"lineage_id": "avortons_des_caves", "copies": 1},
                {"lineage_id": "mordeur_des_combles", "copies": 1},
                {"lineage_id": "mache_mur", "copies": 1},
                {"lineage_id": "le_sac_a_murmures", "copies": 1},
            ]
        elif node["type"] in {"mini_boss", "boss"}:
            profile_id = "boss" if node["type"] == "boss" else "mini_boss"
            cards = _cards_for(node, config["profiles"][profile_id],
                               stone_catalog, lineage_catalog)
        elif node["type"] == "normal" and encounter["game_mode"] in {"classic", "draft"}:
            index = chapter_indices[node["chapter"]]
            chapter_indices[node["chapter"]] += 1
            if index > 0 and index % interval == interval - 1:
                profile_id = "normal_two" if (index // interval) % 2 else "normal_one"
                cards = _cards_for(node, config["profiles"][profile_id],
                                   stone_catalog, lineage_catalog)
        node["rewards"] = {
            "souls_min": int(base),
            "souls_max": int(base + 5 + tier),
            "card_rewards": cards,
        }


def _cards_for(node: dict[str, Any], profile: dict[str, Any],
               stones: dict[str, dict[str, str]],
               lineages: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    slots = int(profile["card_slots"])
    copies = int(profile["copies_per_slot"])
    max_rarity = STAGE_MAX_RARITY[str(node.get("stage_id", "early_game"))]
    candidates: list[str] = []
    seen: set[str] = set()
    theme = str(node.get("theme_god_id", ""))
    for stone_id in node["encounter"].get("fixed_deck", []):
        lineage_id = stones.get(stone_id, {}).get("lineage_id", "")
        if (lineage_id and lineage_id not in seen
                and lineages.get(lineage_id, {}).get("affinity") == theme):
            seen.add(lineage_id)
            candidates.append(lineage_id)
    for lineage_id, value in lineages.items():
        if lineage_id in seen or value["affinity"] != theme:
            continue
        if RARITY_RANK[value["rarity"]] <= RARITY_RANK[max_rarity]:
            candidates.append(lineage_id)
    candidates = [value for value in candidates
                  if value in lineages
                  and RARITY_RANK[lineages[value]["rarity"]] <= RARITY_RANK[max_rarity]]
    max_rank = RARITY_RANK[max_rarity]
    target_rank = max_rank if profile.get("rarity_preference") == "peak" \
        else max(0, max_rank - 1)
    candidates.sort(key=lambda value: (
        abs(RARITY_RANK[lineages[value]["rarity"]] - target_rank),
        -RARITY_RANK[lineages[value]["rarity"]], value))
    return [{
        "lineage_id": value,
        # Une legendaire est definitive des sa premiere copie.
        "copies": 1 if lineages[value]["rarity"] == "legendary" else copies,
    } for value in candidates[:slots]]
