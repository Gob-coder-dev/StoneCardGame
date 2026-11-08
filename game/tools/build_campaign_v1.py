"""Assemble data/campaign/campaign_v1.json.

Les decks fixes proviennent de `campaign_decks.json`, généré par
`generate_campaign_decks.py` puis revalidé par Godot. Toute la progression et
les connexions vivent dans les données : aucun contrôleur ne code un niveau.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DECKS = json.loads((ROOT / "tools" / "campaign_decks.json").read_text(encoding="utf-8"))


def encounter(mode, god_policy, deck_policy, tier, precision, anticipation=False,
              god="", deck=None, series="ft1", seed=0, seed_policy="fixed_per_node"):
    return {
        "game_mode": mode,
        "opponent_god_policy": god_policy,
        "opponent_deck_policy": deck_policy,
        "fixed_god_id": god,
        "fixed_deck": list(deck or []),
        "max_power_tier": tier,
        "ai_profile": {"precision": precision, "anticipation": anticipation},
        "series_format": series,
        "seed_policy": seed_policy,
        "seed": seed,
    }


def node(node_id, name, chapter, region, x, y, node_type, config,
         tutorial_id="", dead_end=False, mini_boss_kind="", accent=""):
    return {
        "id": node_id,
        "name": name,
        "chapter": chapter,
        "region": region,
        "type": node_type,
        "position": {"x": x, "y": y},
        "dead_end": dead_end,
        "mini_boss_kind": mini_boss_kind,
        "tutorial_id": tutorial_id,
        "accent": accent,
        "encounter": config,
        "visual": {"scale": 1.0},
    }


def classic(deck, god="", tier=2, precision=0.25, anticipation=False, seed=0,
            series="ft1", seed_policy="fixed_per_node"):
    return encounter("classic", "fixed", "fixed", tier, precision, anticipation,
                     god=god, deck=deck, seed=seed, series=series,
                     seed_policy=seed_policy)


nodes = [
    node("tuto_01", "Le Seuil", "Seuil", "Le refuge", 540, 160, "tutorial",
         classic(DECKS["neutral_n1"], tier=1, precision=0.0, seed=1101),
         tutorial_id="tutoriel_seuil", accent="#a6c79a"),
    node("tuto_02", "La Leçon", "Seuil", "Le refuge", 540, 330, "tutorial",
         classic(DECKS["neutral_n1"], tier=1, precision=0.0, seed=1102),
         tutorial_id="tutoriel_lecture", accent="#a6c79a"),
    node("tuto_03", "Le Premier Pas", "Seuil", "Le refuge", 540, 500, "tutorial",
         classic(DECKS["neutral_n2"], tier=2, precision=0.0, seed=1103),
         tutorial_id="tutoriel_premier_pas", accent="#a6c79a"),
    node("veskar_01", "La Table du Croupier", "Carrefour", "Les Aléators", 180, 700,
         "normal", classic(DECKS["veskar_n2"], god="veskar", tier=2, precision=0.25,
                           seed=2101), accent="#e75aa8"),
    node("nerava_01", "Les Fièvres Basses", "Carrefour", "Les Flétris", 540, 700,
         "normal", encounter("classic", "fixed", "generated", 2, 0.25,
                             god="nerava", seed=2102), accent="#9b6bc7"),
    node("kharun_01", "La Muraille Fendue", "Carrefour", "Les Remparts", 900, 700,
         "normal", classic(DECKS["kharun_n2"], god="kharun", tier=2, precision=0.25,
                           seed=2103), accent="#72c7d8"),
    node("mini_optional_01", "Le Collectionneur", "Racines", "Les Assimilateurs", 120, 900,
         "mini_boss", classic(DECKS["enigma_n3"], god="enigma", tier=3, precision=0.75,
                              seed=2201),
         dead_end=True, mini_boss_kind="optional", accent="#ef8b45"),
    node("veskar_02", "Le Coup Double", "Racines", "Les Aléators", 320, 900, "normal",
         encounter("random", "generated", "generated", 3, 0.5, series="ft2", seed=2202),
         accent="#e75aa8"),
    node("ilyr_01", "La Ligne de Veille", "Racines", "Les Veilleurs", 540, 900, "normal",
         encounter("classic", "fixed", "generated", 2, 0.25, god="ilyr", seed=2203),
         accent="#5fa8ff"),
    node("mirror_01", "Le Miroir de Verre", "Racines", "Le reflet", 900, 900, "normal",
         encounter("mirror", "mirrored", "mirrored", 3, 0.5, series="ft1", seed=2204),
         accent="#f0449c"),
    node("kharun_02", "Le Rempart Mobile", "Racines", "Les Remparts", 900, 1080, "normal",
         encounter("random", "generated", "generated", 3, 0.5, series="ft2", seed=2205),
         accent="#72c7d8"),
    node("sylkha_01", "La Meute Naissante", "Racines", "L’Essaim", 540, 1260, "normal",
         classic(DECKS["sylkha_n3"], god="sylkha", tier=3, precision=0.5, seed=2206),
         accent="#7fc95b"),
    node("veilleur_impasse", "Le Veilleur Immobile", "Racines", "Les Veilleurs", 900, 1260,
         "normal", classic(DECKS["ilyr_n3"], god="ilyr", tier=3, precision=0.5,
                           seed=2207),
         dead_end=True, accent="#5fa8ff"),
    node("convergence_01", "La Convergence", "Convergence", "Le passage", 540, 1440,
         "normal", encounter("draft", "fixed", "draft", 3, 0.5, god="nerava", seed=2301),
         accent="#9b6bc7"),
    node("boss_required_gate", "La Porte des Assimilateurs", "Convergence",
         "Les Assimilateurs", 540, 1620, "mini_boss",
         classic(DECKS["enigma_n4"], god="enigma", tier=4, precision=0.75, seed=2302),
         mini_boss_kind="mandatory", accent="#ef8b45"),
    node("choice_01", "Le Choix du Miroir", "Cime", "Le reflet", 540, 1800, "normal",
         encounter("classic", "profile", "mirrored", 3, 0.5, seed=2401),
         accent="#f0449c"),
    node("ilyr_02", "L’Œil du Guetteur", "Cime", "Les Veilleurs", 320, 1980, "normal",
         encounter("mirror", "mirrored", "mirrored", 4, 0.75, seed=2402),
         accent="#5fa8ff"),
    node("sylkha_02", "La Cathédrale-Mante", "Cime", "L’Essaim", 760, 1980, "normal",
         classic(DECKS["sylkha_n4"], god="sylkha", tier=4, precision=0.75, seed=2403),
         accent="#7fc95b"),
    node("mini_optional_02", "La Machine aux Mille Dépouilles", "Cime",
         "Les Assimilateurs", 1000, 1900, "mini_boss",
         classic(DECKS["enigma_n3"], god="enigma", tier=3, precision=0.75, seed=2404,
                 seed_policy="per_attempt"),
         dead_end=True, mini_boss_kind="optional", accent="#ef8b45"),
    node("final_01", "Le Visage de Pierre", "Cime", "L’objectif", 540, 2200, "boss",
         encounter("mirror", "mirrored", "mirrored", 4, 1.0, anticipation=True,
                   series="ft3", seed=2405),
         accent="#df929c"),
]


def edge(edge_id, from_id, to_id, controls=None):
    result = {"id": edge_id, "from": from_id, "to": to_id}
    if controls:
        result["controls"] = controls
    return result


edges = [
    edge("e_tuto_1_2", "tuto_01", "tuto_02"),
    edge("e_tuto_2_3", "tuto_02", "tuto_03"),
    edge("e_tuto_3_veskar", "tuto_03", "veskar_01"),
    edge("e_tuto_3_nerava", "tuto_03", "nerava_01"),
    edge("e_tuto_3_kharun", "tuto_03", "kharun_01"),
    edge("e_veskar_optional", "veskar_01", "mini_optional_01"),
    edge("e_veskar_02", "veskar_01", "veskar_02"),
    edge("e_veskar_ilyr", "veskar_01", "ilyr_01"),
    edge("e_veskar_mirror", "veskar_02", "mirror_01"),
    edge("e_ilyr_sylkha", "ilyr_01", "sylkha_01"),
    edge("e_mirror_sylkha", "mirror_01", "sylkha_01"),
    edge("e_nerava_convergence", "nerava_01", "convergence_01"),
    edge("e_kharun_02", "kharun_01", "kharun_02"),
    edge("e_kharun_impasse", "kharun_02", "veilleur_impasse"),
    edge("e_kharun_convergence", "kharun_02", "convergence_01",
         [{"x": 900, "y": 1265}, {"x": 720, "y": 1390}]),
    edge("e_sylkha_convergence", "sylkha_01", "convergence_01"),
    edge("e_convergence_gate", "convergence_01", "boss_required_gate"),
    edge("e_gate_choice", "boss_required_gate", "choice_01"),
    edge("e_choice_ilyr", "choice_01", "ilyr_02"),
    edge("e_choice_sylkha", "choice_01", "sylkha_02"),
    edge("e_choice_optional", "choice_01", "mini_optional_02"),
    edge("e_ilyr_final", "ilyr_02", "final_01"),
    edge("e_sylkha_final", "sylkha_02", "final_01"),
]

definition = {
    "id": "samstone_campaign",
    "title": "La Carte de SamStone",
    "campaign_version": 1,
    "map": {"width": 1080, "height": 2400},
    "start_node_id": "tuto_01",
    "final_node_id": "final_01",
    "nodes": nodes,
    "edges": edges,
}

out = ROOT / "data" / "campaign" / "campaign_v1.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(definition, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"wrote {out} with {len(nodes)} nodes and {len(edges)} edges")
