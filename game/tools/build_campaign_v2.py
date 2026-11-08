"""Construit la campagne de 120 nœuds à partir d'un plan de graphe explicite.

Le script ne fabrique pas de decks : il choisit dans `campaign_deck_library.json`
des decks déjà produits et validés par Godot. Les identifiants des 20 nœuds de
la première campagne unifiée sont conservés ; la version passe à 2 pour que la
migration des sauvegardes soit explicite.
"""
from __future__ import annotations

import json
import math
from collections import Counter, defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = json.loads((ROOT / "tools" / "campaign_deck_library.json").read_text(encoding="utf-8"))
GODS = ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]
GODS_DATA = {str(g["id"]): g for g in json.loads((ROOT / "data" / "gods.json").read_text(encoding="utf-8"))["gods"]}
STONES = json.loads((ROOT / "data" / "stones.json").read_text(encoding="utf-8"))
LINEAGE = {}
STONE_GOD = {}
for lineage in STONES["lineages"]:
    for form in lineage["levels"]:
        form_id = str(form["id"])
        LINEAGE[form_id] = str(lineage["id"])
        STONE_GOD[form_id] = str(lineage.get("god_id", "neutral"))

MODES = {"C": "classic", "R": "random", "M": "mirror", "D": "draft"}

# Decks signés des six mini-boss de campagne. Ils sont réservés avant le tirage
# dans la bibliothèque pour qu'aucune rencontre ordinaire ne les duplique.
CURATED_DECKS = {
    "mini_optional_01": [
        "porte_fievre_n2", "crache_cendre_n2", "clochelet_malade_n2",
        "machoire_moisie_n2", "veuve_des_spores_n1", "sonneur_pestifere_n1",
        "griffe_septique_n1", "ronge_chair_n1",
    ],
    "r04_mini": [
        "nud_vivant_n2", "larve_dancrage_n1", "tisse_griffe_n2",
        "bourgeon_mordant_n2", "mante_des_racines_n1", "porte_nid_n1",
        "fourmilion_des_nerfs_n1", "ronce_rampante_n1",
    ],
    "r11_mini": [
        "carapace_vide_n4", "le_sarcophage_debout_n1", "le_reliquaire_ambulant_n2",
        "golem_de_faience_n3", "eclat_cuirasse_n4", "colosse_rivete_n3",
        "portail_dos_n3", "le_gardien_des_decombres_n1",
    ],
    "mini_optional_02": [
        "collecteur_de_dents_n3", "scie_boiteuse_n3", "mordeur_des_combles_n4",
        "gueule_de_travers_n4", "chirurgien_dacier_n2", "rampant_des_fosses_n4",
        "preleveur_de_plaques_n3", "pince_carcasse_n3",
    ],
    # 7 Veilleurs + 1 neutre : le Miroir reste très majoritairement Ilyr.
    "r09_mini1": [
        "longuepine_n4", "pique_en_haut_n4", "fauche_fond_n4",
        "bouche_arbalete_n4", "veilleur_bifurque_n1", "perce_voute_n1",
        "dard_de_traverse_n2", "avortons_des_caves_n1",
    ],
}

# Six mini-boss facultatifs existants reçoivent une identité et des contraintes
# de génération propres. Les modes changent sur deux d'entre eux, compensés par
# les deux bascules de MODE_REWORK pour conserver 72/18/12/18.
MINI_REWORK = {
    "mini_optional_01": dict(
        name="La Cloche des Fièvres", mode="classic", god_policy="fixed",
        deck_policy="fixed", fixed_god="nerava", tier=2, precision=0.35,
        anticipation=False),
    "r03_mini": dict(
        name="Le Jeu des Six Faces", mode="random", god_policy="generated",
        deck_policy="generated", fixed_god="", tier=3, precision=0.55,
        anticipation=False, generator_god="veskar", generator_min=8),
    "r04_mini": dict(
        name="Le Premier Essaim", mode="classic", god_policy="fixed",
        deck_policy="fixed", fixed_god="sylkha", tier=2, precision=1.0,
        anticipation=True),
    "r09_mini1": dict(
        name="La Garde en Reflet", mode="mirror", god_policy="mirrored",
        deck_policy="mirrored", fixed_god="", tier=4, precision=0.8,
        anticipation=False, generator_god="ilyr", generator_min=7,
        mirror_deck=True),
    "r11_mini": dict(
        name="Le Rempart de Carapace", mode="classic", god_policy="fixed",
        deck_policy="fixed", fixed_god="kharun", tier=4, precision=0.85,
        anticipation=False),
    "mini_optional_02": dict(
        name="Les Faces du Collectionneur", mode="classic", god_policy="fixed",
        deck_policy="fixed", fixed_god="enigma", tier=4, precision=0.9,
        anticipation=False),
}

MODE_REWORK = {"r05_b2": "draft", "r10_b1": "mirror"}

# Les trois premiers nœuds et le carrefour historique restent les mêmes IDs.
OLD = {
    "tuto_01": dict(name="Le Seuil", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="tutoriel_seuil", type="tutorial", accent="#a6c79a"),
    "tuto_02": dict(name="La Leçon", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="tutoriel_lecture", type="tutorial", accent="#a6c79a"),
    "tuto_03": dict(name="Le Premier Pas", chapter="Seuil", region="Le refuge", mode="C", tier=2,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n2",
                    tutorial="tutoriel_premier_pas", type="tutorial", accent="#a6c79a"),
    "veskar_01": dict(name="La Table du Croupier", chapter="Carrefour", region="Les Aléators",
                      mode="C", tier=2, precision=0.25, god="veskar"),
    "nerava_01": dict(name="Les Fièvres Basses", chapter="Carrefour", region="Les Flétris",
                      mode="C", tier=2, precision=0.25, god="nerava", deck_kind="generated"),
    "kharun_01": dict(name="La Muraille Fendue", chapter="Carrefour", region="Les Remparts",
                      mode="C", tier=2, precision=0.25, god="kharun"),
    "mini_optional_01": dict(name="Le Collectionneur", chapter="Carrefour", region="Les Assimilateurs",
                             mode="C", tier=3, precision=0.75, god="enigma", type="mini_boss",
                             mini_kind="optional", dead_end=True),
    "veskar_02": dict(name="Le Coup Double", chapter="Carrefour", region="Les Aléators",
                      mode="R", tier=3, precision=0.5, god="", series="ft2"),
    "ilyr_01": dict(name="La Ligne de Veille", chapter="Carrefour", region="Les Veilleurs",
                    mode="C", tier=2, precision=0.25, god="ilyr", deck_kind="generated"),
    "mirror_01": dict(name="Le Miroir de Verre", chapter="Carrefour", region="Le reflet",
                      mode="M", tier=3, precision=0.5, god=""),
    "kharun_02": dict(name="Le Rempart Mobile", chapter="Carrefour", region="Les Remparts",
                      mode="R", tier=3, precision=0.5, god="", series="ft2"),
    "sylkha_01": dict(name="La Meute Naissante", chapter="Carrefour", region="L’Essaim",
                      mode="C", tier=3, precision=0.5, god="sylkha"),
    "veilleur_impasse": dict(name="Le Veilleur Immobile", chapter="Carrefour", region="Les Veilleurs",
                             mode="C", tier=3, precision=0.5, god="ilyr", dead_end=True),
    "convergence_01": dict(name="La Convergence", chapter="Carrefour", region="Le passage",
                           mode="D", tier=3, precision=0.5, god="nerava"),
    "boss_required_gate": dict(name="La Porte des Assimilateurs", chapter="Carrefour",
                               region="Les Assimilateurs", mode="C", tier=3, precision=0.75,
                               god="enigma", type="mini_boss", mini_kind="mandatory",
                               series="ft2"),
    "choice_01": dict(name="Le Choix du Miroir", chapter="Cime", region="Le reflet",
                      mode="C", tier=3, precision=0.5, god="", profile=True,
                      deck_kind="mirrored"),
    "ilyr_02": dict(name="L’Œil du Guetteur", chapter="Cime", region="Les Veilleurs",
                    mode="M", tier=4, precision=0.75, god=""),
    "sylkha_02": dict(name="La Cathédrale-Mante", chapter="Cime", region="L’Essaim",
                      mode="C", tier=4, precision=0.75, god="sylkha"),
    "mini_optional_02": dict(name="La Machine aux Mille Dépouilles", chapter="Cime",
                             region="Les Assimilateurs", mode="C", tier=4, precision=0.75,
                             god="enigma", type="mini_boss", mini_kind="optional",
                             dead_end=True, seed_policy="per_attempt"),
    "final_01": dict(name="Le Visage de Pierre", chapter="Cime", region="L’objectif",
                     mode="M", tier=4, precision=1.0, anticipation=True, god="",
                     type="boss", series="ft3"),
}

# Coordonnées des 20 nœuds historiques, réparties pour laisser respirer les branches.
OLD_COORDS = {
    "tuto_01": (0, 540), "tuto_02": (1, 540), "tuto_03": (2, 540),
    "veskar_01": (0, 160), "nerava_01": (0, 540), "kharun_01": (0, 920),
    "mini_optional_01": (1, 90), "veskar_02": (1, 390), "ilyr_01": (1, 680),
    "kharun_02": (1, 940),
    "sylkha_01": (2, 280),    "mirror_01": (2, 640), "veilleur_impasse": (2, 940),
    "convergence_01": (3, 540), "boss_required_gate": (4, 540),
}

OLD_EDGES = [
    ("tuto_01", "tuto_02"), ("tuto_02", "tuto_03"),
    ("tuto_03", "veskar_01"), ("tuto_03", "nerava_01"), ("tuto_03", "kharun_01"),
    ("veskar_01", "mini_optional_01"), ("veskar_01", "veskar_02"),
    ("veskar_01", "ilyr_01"), ("veskar_02", "mirror_01"),
    ("ilyr_01", "sylkha_01"), ("mirror_01", "sylkha_01"),
    ("nerava_01", "convergence_01"), ("kharun_01", "kharun_02"),
    ("kharun_02", "veilleur_impasse"), ("kharun_02", "convergence_01"),
    ("sylkha_01", "convergence_01"), ("convergence_01", "boss_required_gate"),
]

PATTERNS = {
    "P1": {
        "roles": ["entry", "a", "b", "a1", "a2", "b1", "m", "c", "exit", "mini"],
        "coords": {"entry": (0, 540), "a": (1, 300), "b": (1, 780),
                   "a1": (2, 180), "a2": (2, 420), "b1": (2, 780),
                   "m": (3, 540), "c": (4, 400), "exit": (5, 540), "mini": (4, 760)},
        "edges": [("entry", "a"), ("entry", "b"), ("a", "a1"), ("a", "a2"),
                  ("b", "b1"), ("a1", "m"), ("a2", "m"), ("b1", "m"),
                  ("m", "c"), ("m", "mini"), ("c", "exit")],
        "mini": ["mini"],
    },
    "P2": {
        "roles": ["entry", "a", "b", "mini", "a1", "a2", "b1", "d", "m", "gate"],
        "coords": {"entry": (0, 540), "a": (1, 240), "b": (1, 600), "mini": (1, 900),
                   "a1": (2, 200), "a2": (2, 400), "b1": (2, 600), "d": (3, 480),
                   "m": (4, 540), "gate": (5, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("entry", "mini"),
                  ("a", "a1"), ("a", "a2"), ("b", "b1"),
                  ("a1", "m"), ("b1", "m"), ("a2", "d"), ("d", "m"), ("m", "gate")],
        "mini": ["mini"], "gate": "gate",
    },
    "P3": {
        "roles": ["entry", "a", "b", "a1", "b1", "a2", "b2", "m", "exit", "mini"],
        "coords": {"entry": (0, 540), "a": (1, 320), "b": (1, 760),
                   "a1": (2, 200), "b1": (2, 760), "a2": (3, 300),
                   "b2": (3, 760), "mini": (3, 100), "m": (4, 540), "exit": (5, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("a", "a1"), ("b", "b1"),
                  ("a1", "a2"), ("a1", "mini"), ("b1", "b2"),
                  ("a2", "m"), ("b2", "m"), ("m", "exit")],
        "mini": ["mini"],
    },
    "P4": {
        "roles": ["entry", "a", "b", "c", "mini", "a1", "b1", "c1", "m", "exit"],
        "coords": {"entry": (0, 540), "a": (1, 120), "b": (1, 360), "c": (1, 600),
                   "mini": (1, 860), "a1": (2, 200), "b1": (2, 540),
                   "c1": (2, 860), "m": (3, 540), "exit": (4, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("entry", "c"), ("entry", "mini"),
                  ("a", "a1"), ("b", "b1"), ("c", "c1"),
                  ("a1", "m"), ("b1", "m"), ("c1", "m"), ("m", "exit")],
        "mini": ["mini"],
    },
    "P5": {
        "roles": ["entry", "a", "b", "m1", "c", "d", "m2", "e", "f", "gate"],
        "coords": {"entry": (0, 540), "a": (1, 300), "b": (1, 780),
                   "m1": (2, 540), "c": (3, 300), "d": (3, 780),
                   "m2": (4, 540), "e": (5, 300), "f": (5, 780), "gate": (6, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("a", "m1"), ("b", "m1"),
                  ("m1", "c"), ("m1", "d"), ("c", "m2"), ("d", "m2"),
                  ("m2", "e"), ("m2", "f"), ("e", "gate"), ("f", "gate")],
        "gate": "gate",
    },
    "P6": {
        "roles": ["entry", "a", "b", "c", "a1", "b1", "c1", "m1", "m2", "exit"],
        "coords": {"entry": (0, 540), "a": (1, 160), "b": (1, 540), "c": (1, 900),
                   "a1": (2, 160), "b1": (2, 540), "c1": (2, 900),
                   "m1": (3, 400), "m2": (3, 680), "exit": (4, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("entry", "c"),
                  ("a", "a1"), ("b", "b1"), ("c", "c1"),
                  ("a1", "m1"), ("a1", "m2"), ("b1", "m1"), ("c1", "m2"),
                  ("m1", "exit"), ("m2", "exit")],
    },
    "P7": {
        "roles": ["entry", "a", "b", "c", "mini1", "mini2", "a1", "b1", "m", "exit"],
        "coords": {"entry": (0, 540), "a": (1, 300), "b": (1, 780), "c": (1, 540),
                   "mini1": (2, 120), "mini2": (2, 960), "a1": (2, 300),
                   "b1": (2, 780), "m": (3, 540), "exit": (4, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("entry", "c"),
                  ("a", "mini1"), ("a", "a1"), ("b", "mini2"), ("b", "b1"),
                  ("a1", "m"), ("b1", "m"), ("c", "m"), ("m", "exit")],
        "mini": ["mini1", "mini2"],
    },
    "P8": {
        "roles": ["entry", "a", "b", "c", "a1", "b1", "m", "d", "gate", "mini"],
        "coords": {"entry": (0, 540), "a": (1, 240), "b": (1, 540), "c": (1, 840),
                   "a1": (2, 240), "b1": (2, 540), "d": (2, 760),
                   "mini": (2, 960), "m": (3, 540), "gate": (4, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("entry", "c"),
                  ("entry", "d"),
                  ("a", "a1"), ("b", "b1"), ("c", "d"), ("c", "mini"),
                  ("a1", "m"), ("b1", "m"), ("d", "m"), ("m", "gate")],
        "mini": ["mini"], "gate": "gate",
    },
    "P9": {
        "roles": ["entry", "a", "b", "a1", "a2", "b1", "b2", "m", "mini", "exit"],
        "coords": {"entry": (0, 540), "a": (1, 300), "b": (1, 780),
                   "a1": (2, 160), "a2": (2, 440), "b1": (2, 640), "b2": (2, 920),
                   "m": (3, 540), "mini": (4, 900), "exit": (4, 540)},
        "edges": [("entry", "a"), ("entry", "b"), ("a", "a1"), ("a", "a2"),
                  ("b", "b1"), ("b", "b2"), ("a1", "m"), ("a2", "m"),
                  ("b1", "m"), ("b2", "m"), ("m", "mini"), ("m", "exit")],
        "mini": ["mini"],
    },
}

# Ordre et noms des régions. Les modes sont donnés dans l'ordre des rôles du motif.
REGIONS = [
    dict(id="r03", prefix="r03", pattern="P1", chapter="Le Marais des Serments",
         region="Les Vœux Noyés", names=[
             "Le Gué des Promesses", "La Passe des Noyés", "Les Roseaux Témoins",
             "La Barque Sans Rame", "Le Serment de Vase", "L'Île aux Dettes",
             "Le Bras de Tourbe", "La Cloche Engloutie", "Le Passage des Larmes",
             "Le Gardien des Vœux"],
         modes=["C", "C", "R", "C", "C", "C", "D", "C", "C", "R"],
         optional=["mini"]),
    dict(id="r04", prefix="r04", pattern="P2", chapter="Les Forges Basses",
         region="Les Souffles", names=[
             "Les Soufflets Basses", "La Coulée Rouge", "Le Marteau Veuf",
             "Les Scories Vivantes", "L'Enclume des Vœux", "Le Canal de Métal",
             "La Forge aux Os", "Les Étincelles Froides", "Le Souffle du Four",
             "La Porte des Fontes"],
         modes=["C", "C", "C", "M", "D", "C", "C", "C", "D", "C"],
         optional=["mini"], gate="gate"),
    dict(id="r05", prefix="r05", pattern="P3", chapter="La Bibliothèque des Os",
         region="Les Archives", names=[
             "Le Seuil des Archives", "Les Rayons Muets", "La Salle des Dettes",
             "L'Index de Fer", "Les Marges Vivantes", "Le Catalogue des Oubliés",
             "La Reliure de Peau", "Le Silence des Livres", "La Sortie des Copistes",
             "L'Encre Dévoreuse"],
         modes=["C", "C", "C", "D", "C", "C", "C", "C", "R", "D"],
         optional=["mini"]),
    dict(id="r06", prefix="r06", pattern="P4", chapter="Le Marché Nocturne",
         region="Les Échanges", names=[
             "Le Marché aux Noms", "Les Lanternes Sourdes", "La Bourse Vide",
             "Le Comptoir des Dettes", "Le Colporteur de Peaux",
             "La Rue des Serments", "Les Cageots d'Os", "La Monnaie Fendue",
             "Le Grand Change", "La Ruelle des Adieux"],
         modes=["C", "M", "R", "C", "R", "C", "C", "D", "C", "C"],
         optional=["mini"]),
    dict(id="r07", prefix="r07", pattern="P5", chapter="Les Serres de Verre",
         region="Les Greffes", names=[
             "Les Serres de Verre", "La Voûte Tiède", "Les Racines en Cloche",
             "Le Croisement des Sèves", "Les Fruits Témoins", "La Saignée Verte",
             "Le Nœud de Verre", "Les Greffes Lumineuses", "La Floraison Muette",
             "La Cloche de Sève"],
         modes=["C", "C", "R", "C", "M", "D", "C", "C", "C", "M"],
         gate="gate"),
    dict(id="r08", prefix="r08", pattern="P6", chapter="Les Remparts Muets",
         region="Les Assiégés", names=[
             "Les Remparts Muets", "La Brèche Nord", "Le Chemin de Ronde",
             "La Tour sans Guetteur", "Les Meurtrières", "Le Pont-levis Grippé",
             "Les Pierres Tombées", "La Cour des Assiégés", "Le Beffroi Fendu",
             "La Poterne des Vents"],
         modes=["C", "R", "C", "D", "C", "M", "C", "R", "D", "C"]),
    dict(id="r09", prefix="r09", pattern="P7", chapter="Le Puits des Échos",
         region="Les Profondeurs", names=[
             "Le Puits des Échos", "La Margelle Usée", "Les Seaux Vides",
             "Le Fil des Voix", "La Bouche du Puits", "Le Chœur Noyé",
             "La Descente Basse", "Les Parois Humides", "Le Fond Sans Nom",
             "La Remontée des Oubliés"],
         modes=["C", "R", "C", "C", "M", "D", "C", "D", "R", "C"],
         optional=["mini1", "mini2"]),
    dict(id="r10", prefix="r10", pattern="P8", chapter="La Cour des Masques",
         region="Les Visages", names=[
             "La Cour des Masques", "Le Banquet des Visages", "La Galerie des Miroirs",
             "Le Trône Vide", "Les Masques Fendus", "La Danse des Doubles",
             "Le Grand Dévoilement", "La Loge du Roi", "Le Sceau du Visage",
             "Le Mime Absolu"],
         modes=["C", "C", "C", "M", "C", "C", "C", "D", "R", "D"],
         optional=["mini"], gate="gate"),
    dict(id="r11", prefix="r11", pattern="P9", chapter="Les Jardins de Cendre",
         region="Les Cendres", names=[
             "Les Jardins de Cendre", "Les Allées Grises", "Le Bassin Fumé",
             "Les Fleurs de Suie", "Le Verger Calciné", "Les Rameaux Noirs",
             "La Source Amère", "Le Cœur du Jardin", "Le Gardien des Cendres",
             "La Porte Calcinée"],
         modes=["C", "R", "R", "C", "D", "C", "R", "C", "D", "C"],
         optional=["mini"]),
]

R12 = dict(id="r12", prefix="r12", chapter="Cime", region="L'Objectif", names=[
    "Le Dernier Seuil", "La Montée de Pierre", "Les Escaliers Fendus",
    "Le Vent des Cimes", "La Voûte des Serments", "Les Statues Borgnes",
    "Le Chemin des Rois", "La Salle des Échos", "La Terrasse du Silence",
    "Le Cercle des Visages"],
    coords={"entry": (0, 540), "a": (1, 160), "b": (1, 540), "c": (1, 900),
            "a1": (2, 120), "a2": (2, 360), "b1": (2, 540), "b2": (2, 720),
            "c1": (2, 960), "m": (3, 540)},
    edges=[("entry", "a"), ("entry", "b"), ("entry", "c"),
           ("a", "a1"), ("a", "a2"), ("b", "b1"), ("b", "b2"),
           ("c", "c1"), ("a1", "m"), ("a2", "m"), ("b1", "m"),
           ("b2", "m"), ("c1", "m")],
    modes=["C", "C", "R", "C", "R", "D", "M", "D", "M", "C"])

LATE = {
    "choice_01": dict(name=OLD["choice_01"]["name"], chapter="Cime", region="Le reflet",
                      mode="C", tier=3, precision=0.5, god="", profile=True,
                      deck_kind="mirrored", coord=(4, 540)),
    "ilyr_02": dict(name=OLD["ilyr_02"]["name"], chapter="Cime", region="Les Veilleurs",
                    mode="M", tier=4, precision=0.75, god="", coord=(5, 240)),
    "sylkha_02": dict(name=OLD["sylkha_02"]["name"], chapter="Cime", region="L’Essaim",
                      mode="C", tier=4, precision=0.75, god="sylkha", coord=(5, 720)),
    "mini_optional_02": dict(name=OLD["mini_optional_02"]["name"], chapter="Cime",
                             region="Les Assimilateurs", mode="C", tier=4,
                             precision=0.75, god="enigma", type="mini_boss",
                             mini_kind="optional", dead_end=True, series="ft2",
                             seed_policy="per_attempt", coord=(5, 960)),
    "final_01": dict(name=OLD["final_01"]["name"], chapter="Cime", region="L’objectif",
                     mode="M", tier=4, precision=1.0, anticipation=True, god="",
                     type="boss", series="ft3", coord=(6, 540)),
}

PRECISIONS = [0.04, 0.07, 0.11, 0.15, 0.19, 0.23, 0.28, 0.32, 0.37, 0.41,
              0.46, 0.52, 0.57, 0.63, 0.68, 0.74, 0.79, 0.84, 0.89, 0.93,
              0.96, 0.06, 0.13, 0.21, 0.34, 0.43, 0.54, 0.61, 0.71, 0.81,
              0.91, 0.98]

# Les identifiants des vingt nœuds précédents restent stables. Les nouveaux
# nœuds suivent un identifiant de région + rôle, jamais un numéro de difficulté.
nodes = {}
edges = []
edge_ids = set()


def add_edge(source: str, target: str, controls=None) -> None:
    key = (source, target)
    if key in {(e["from"], e["to"]) for e in edges}:
        return
    edge_id = "e_%s_%s" % (source, target)
    if edge_id in edge_ids:
        edge_id += "_b"
    edge_ids.add(edge_id)
    value = {"id": edge_id, "from": source, "to": target}
    if controls:
        value["controls"] = controls
    edges.append(value)


def add_node(node_id: str, spec: dict, x: float, y: float) -> None:
    mode = MODES[spec["mode"]]
    node_type = spec.get("type", "normal")
    mini_kind = spec.get("mini_kind", "")
    dead_end = bool(spec.get("dead_end", False))
    god = spec.get("god", "")
    profile = bool(spec.get("profile", False))
    deck_kind = spec.get("deck_kind", "")
    series = spec.get("series", "ft3" if node_type == "boss" else
                     "ft2" if node_type == "mini_boss" else "ft1")
    # Une rencontre fixe utilise son dieu ; un mode Aléatoire/Miroir n'a pas de
    # dieu adverse fixe. Le thème est renseigné après l'équilibrage global.
    if mode == "classic":
        god_policy = "profile" if profile else "fixed"
        deck_policy = {"fixed": "fixed", "generated": "generated",
                       "mirrored": "mirrored"}.get(deck_kind, "fixed")
    elif mode == "random":
        god_policy, deck_policy = "generated", "generated"
    elif mode == "mirror":
        god_policy, deck_policy = "mirrored", "mirrored"
    else:
        god_policy, deck_policy = "fixed", "draft"
        profile = False
    node = {
        "id": node_id,
        "name": spec["name"],
        "chapter": spec["chapter"],
        "region": spec["region"],
        "type": node_type,
        "position": {"x": int(x), "y": int(y)},
        "dead_end": dead_end,
        "mini_boss_kind": mini_kind,
        "tutorial_id": spec.get("tutorial", ""),
        "theme_god_id": "",
        "accent": spec.get("accent", ""),
        "encounter": {
            "game_mode": mode,
            "opponent_god_policy": god_policy,
            "opponent_deck_policy": deck_policy,
            "fixed_god_id": god if god_policy == "fixed" else "",
            "fixed_deck": [],
            "generator_god_id": "",
            "generator_min_god_cards": 0,
            "mirror_fixed_deck": [],
            "max_power_tier": int(spec.get("tier", 2)),
            "ai_profile": {"precision": float(spec.get("precision", 0.0)),
                           "anticipation": bool(spec.get("anticipation", False))},
            "series_format": series,
            "seed_policy": spec.get("seed_policy", "fixed_per_node"),
            "seed": 0,
        },
        "visual": {"scale": 1.0},
    }
    nodes[node_id] = node


# ── Seuil et carrefour historique ────────────────────────────────────────────
start_y = 160
for node_id in ["tuto_01", "tuto_02", "tuto_03"]:
    depth, x = OLD_COORDS[node_id]
    add_node(node_id, OLD[node_id], x, start_y + depth * 240)
carrefour_y = start_y + 2 * 240 + 340
for node_id in ["veskar_01", "nerava_01", "kharun_01", "mini_optional_01",
                "veskar_02", "ilyr_01", "mirror_01", "kharun_02",
                "sylkha_01", "veilleur_impasse", "convergence_01",
                "boss_required_gate"]:
    depth, x = OLD_COORDS[node_id]
    add_node(node_id, OLD[node_id], x, carrefour_y + depth * 240)
for source, target in OLD_EDGES:
    add_edge(source, target)

# ── Régions intermédiaires ──────────────────────────────────────────────────
previous_exit = "boss_required_gate"
region_start = carrefour_y + 4 * 240 + 340
for region in REGIONS:
    pattern = PATTERNS[region["pattern"]]
    names = region["names"]
    roles = pattern["roles"]
    max_depth = max(depth for depth, _x in pattern["coords"].values())
    for index, role in enumerate(roles):
        node_id = "r%s_%s" % (region["prefix"][1:], role)
        spec = {
            "name": names[index],
            "chapter": region["chapter"],
            "region": region["region"],
            "mode": region["modes"][index],
            "type": "mini_boss" if role in pattern.get("mini", []) else "normal",
            "mini_kind": "optional" if role in pattern.get("mini", []) else "",
            "dead_end": role in pattern.get("mini", []),
            "god": "",
            "tier": 0,
            "precision": 0.0,
            "series": "ft2" if role in pattern.get("mini", []) else "ft1",
        }
        if role == pattern.get("gate"):
            spec["type"] = "mini_boss"
            spec["mini_kind"] = "mandatory"
            spec["dead_end"] = False
            spec["series"] = "ft2"
        depth, x = pattern["coords"][role]
        add_node(node_id, spec, x, region_start + depth * 240)
    for source_role, target_role in pattern["edges"]:
        add_edge("r%s_%s" % (region["prefix"][1:], source_role),
                 "r%s_%s" % (region["prefix"][1:], target_role))
    add_edge(previous_exit, "r%s_entry" % region["prefix"][1:])
    previous_exit = "r%s_%s" % (region["prefix"][1:], pattern.get("gate", "exit"))
    region_start += max_depth * 240 + 340

# ── Cime : 10 nouveaux nœuds puis les cinq nœuds historiques ────────────────
for index, role in enumerate(["entry", "a", "b", "c", "a1", "a2", "b1", "b2", "c1", "m"]):
    node_id = "r12_%s" % role
    spec = {
        "name": R12["names"][index], "chapter": R12["chapter"], "region": R12["region"],
        "mode": R12["modes"][index], "type": "normal", "god": "",
        "tier": 0, "precision": 0.0, "series": "ft1",
    }
    depth, x = R12["coords"][role]
    add_node(node_id, spec, x, region_start + depth * 240)
for source_role, target_role in R12["edges"]:
    add_edge("r12_%s" % source_role, "r12_%s" % target_role)
add_edge(previous_exit, "r12_entry")
for node_id in ["choice_01", "ilyr_02", "sylkha_02", "mini_optional_02", "final_01"]:
    spec = dict(LATE[node_id])
    depth, x = spec.pop("coord")
    add_node(node_id, spec, x, region_start + depth * 240)
add_edge("r12_m", "choice_01")
for target in ["ilyr_02", "sylkha_02", "mini_optional_02"]:
    add_edge("choice_01", target)
for source in ["ilyr_02", "sylkha_02"]:
    add_edge(source, "final_01")

# ── Identités et contraintes des six mini-boss ──────────────────────────────
for node_id, mode in MODE_REWORK.items():
    if node_id not in nodes:
        raise SystemExit(f"nœud de rééquilibrage absent : {node_id}")
    enc = nodes[node_id]["encounter"]
    enc["game_mode"] = mode
    enc["fixed_god_id"] = ""
    enc["fixed_deck"] = []
    if mode == "draft":
        enc["opponent_god_policy"] = "fixed"
        enc["opponent_deck_policy"] = "draft"
    elif mode == "mirror":
        enc["opponent_god_policy"] = "mirrored"
        enc["opponent_deck_policy"] = "mirrored"
    else:
        raise SystemExit(f"rééquilibrage de mode non pris en charge : {mode}")

for node_id, spec in MINI_REWORK.items():
    if node_id not in nodes:
        raise SystemExit(f"mini-boss absent : {node_id}")
    node = nodes[node_id]
    enc = node["encounter"]
    node["name"] = spec["name"]
    node["type"] = "mini_boss"
    node["mini_boss_kind"] = "optional"
    node["dead_end"] = True
    enc["game_mode"] = spec["mode"]
    enc["opponent_god_policy"] = spec["god_policy"]
    enc["opponent_deck_policy"] = spec["deck_policy"]
    enc["fixed_god_id"] = spec["fixed_god"]
    enc["fixed_deck"] = []
    enc["series_format"] = "ft2"
    enc["max_power_tier"] = spec["tier"]
    enc["ai_profile"] = {"precision": spec["precision"],
                         "anticipation": spec["anticipation"]}
    enc["generator_god_id"] = spec.get("generator_god", "")
    enc["generator_min_god_cards"] = spec.get("generator_min", 0)
    enc["mirror_fixed_deck"] = (list(CURATED_DECKS[node_id])
                                 if spec.get("mirror_deck", False) else [])

# ── Graphe, profondeurs et tiers ─────────────────────────────────────────────
outgoing = defaultdict(list)
incoming = defaultdict(list)
for edge in edges:
    outgoing[edge["from"]].append(edge["to"])
    incoming[edge["to"]].append(edge["from"])

order = []
visited = set()


def visit(node_id: str) -> None:
    if node_id in visited:
        return
    visited.add(node_id)
    for child in outgoing[node_id]:
        visit(child)
    order.append(node_id)


visit("tuto_01")
topological = list(reversed(order))
depth = {node_id: 0 for node_id in nodes}
for node_id in topological:
    for parent in incoming[node_id]:
        depth[node_id] = max(depth[node_id], depth[parent] + 1)
max_depth = max(depth.values())


def base_tier(d: int) -> int:
    if d <= 12:
        return 2
    if d <= 26:
        return 2 if d % 5 else 3
    if d <= 40:
        return 2 if d % 6 in (0, 3) else 3
    if d <= 52:
        return 3 if d % 3 else 4
    return 4 if d % 7 else 3


for node_id, node in nodes.items():
    if node["type"] == "tutorial":
        continue
    if node_id in OLD:
        continue
    d = depth[node_id]
    tier = base_tier(d)
    if node["mini_boss_kind"]:
        tier = max(3, min(4, tier + (1 if node["mini_boss_kind"] == "optional" else 0)))
    if node["encounter"]["series_format"] == "ft2":
        tier = max(3, tier)
    # Le draft doit construire huit paires légales pour les six dieux jouables.
    # Le palier 2 ne fournit pas toujours un plan sûr pour certains couples ;
    # la Sélection de campagne commence donc au palier 3.
    if node["encounter"]["game_mode"] == "draft":
        tier = max(3, tier)
    if node["type"] == "boss":
        tier = 4
    node["encounter"]["max_power_tier"] = tier

# Les quatre rencontres majeures ordinaires restent en FT2, comme les mini-boss.
for node_id in ["r05_m", "r08_m1", "r09_m", "r12_m"]:
    nodes[node_id]["encounter"]["series_format"] = "ft2"

# Les paliers des mini-boss signés sont des choix de design : Nérava et Sylkha
# restent accessibles tôt, les quatre autres ferment la progression.
for node_id, spec in MINI_REWORK.items():
    nodes[node_id]["encounter"]["max_power_tier"] = spec["tier"]

# ── Thèmes de dieu : équilibre global, sans dieu fixe dans les modes variables ─
theme_counts = Counter()
last_theme = ""
fixed_pending = []
variable = []
for node_id, node in nodes.items():
    if node["type"] == "tutorial":
        continue
    fixed = node["encounter"].get("fixed_god_id", "")
    if fixed:
        node["theme_god_id"] = fixed
        theme_counts[fixed] += 1
    elif node["encounter"]["opponent_god_policy"] == "fixed":
        fixed_pending.append(node_id)
    else:
        variable.append(node_id)


def choose_theme() -> str:
    ordered = sorted(GODS, key=lambda g: (theme_counts[g], 0 if g != last_theme else 1,
                                           GODS.index(g)))
    return ordered[0]


# Les dieux réellement combattus doivent eux aussi être équilibrés. On remplit
# d'abord les rencontres à dieu fixe, puis les thèmes des modes variables.
for node_id in fixed_pending:
    theme = choose_theme()
    nodes[node_id]["theme_god_id"] = theme
    nodes[node_id]["encounter"]["fixed_god_id"] = theme
    last_theme = theme
    theme_counts[theme] += 1

for node_id in variable:
    theme = choose_theme()
    nodes[node_id]["theme_god_id"] = theme
    last_theme = theme
    theme_counts[theme] += 1

# La cime reste thématiquement liée aux Assimilateurs, sans changer son mode.
if nodes["final_01"]["theme_god_id"] != "enigma":
    old_theme = nodes["final_01"]["theme_god_id"]
    theme_counts[old_theme] -= 1
    theme_counts["enigma"] += 1
    nodes["final_01"]["theme_god_id"] = "enigma"

for index, (node_id, node) in enumerate(nodes.items()):
    theme = node.get("theme_god_id", "")
    if theme:
        node["accent"] = str(GODS_DATA[theme].get("color", "#f0449c"))
        # Un nœud Classique ou Sélection à dieu fixe doit vraiment porter ce
        # dieu dans sa rencontre ; le thème ne sert qu'à l'équilibrage visuel
        # des modes Aléatoire et Miroir.
        if (node["encounter"]["opponent_god_policy"] == "fixed"
                and not node["encounter"]["fixed_god_id"]):
            node["encounter"]["fixed_god_id"] = theme
    node["encounter"]["seed"] = 5000 + index * 37

# ── Précisions et anticipation des nouveaux nœuds ───────────────────────────
for node_id, node in nodes.items():
    if node_id in OLD or node["type"] == "tutorial":
        continue
    d = depth[node_id]
    region_index = list(nodes).index(node_id) // 10
    if d <= 14:
        p = PRECISIONS[(d * 3 + region_index) % 14]
        p = min(p, 0.28)
    elif d >= 48:
        late = [0.74, 0.79, 0.84, 0.89, 0.93, 0.96,
                0.77, 0.82, 0.86, 0.91, 0.94, 0.88]
        p = late[(d * 5 + len(node_id) * 3 + region_index) % len(late)]
    else:
        p = PRECISIONS[(d * 3 + region_index * 2 + len(node_id)) % len(PRECISIONS)]
    if d >= 56:
        p = max(p, 0.84)
    if node["mini_boss_kind"] == "mandatory":
        p = min(0.98, p + 0.02)
    if node["type"] == "boss":
        p = 1.0
    node["encounter"]["ai_profile"] = {
        "precision": round(p, 2),
        "anticipation": p >= 0.93 and d >= 52,
    }
for node_id in ["final_01"]:
    nodes[node_id]["encounter"]["ai_profile"] = {"precision": 1.0, "anticipation": True}

# Les six mini-boss gardent leur courbe de difficulté propre, y compris les
# deux rencontres très tôt dans la campagne.
for node_id, spec in MINI_REWORK.items():
    nodes[node_id]["encounter"]["ai_profile"] = {
        "precision": spec["precision"],
        "anticipation": spec["anticipation"],
    }

# ── Decks fixes distincts ───────────────────────────────────────────────────
neutral_used = set()


def sorted_deck(deck: list[str]) -> tuple[str, ...]:
    return tuple(sorted(deck))


def lineages(deck: list[str]) -> set[str]:
    return {LINEAGE.get(card, card) for card in deck}


def god_card_count(deck: list[str], god_id: str) -> int:
    return sum(1 for card in deck if STONE_GOD.get(card) == god_id)


reserved_decks = {sorted_deck(deck) for deck in CURATED_DECKS.values()}
if len(reserved_decks) != len(CURATED_DECKS):
    raise SystemExit("deux decks de mini-boss sont exactement identiques")
used_decks = set()
selected_decks = []
for node_id, node in nodes.items():
    enc = node["encounter"]
    policy = enc["opponent_deck_policy"]
    if policy != "fixed":
        continue
    if node_id in CURATED_DECKS:
        deck = list(CURATED_DECKS[node_id])
        enc["fixed_deck"] = deck
        used_decks.add(sorted_deck(deck))
        selected_decks.append(lineages(deck))
        continue
    tier = int(enc["max_power_tier"])
    god = ""
    if node["type"] == "tutorial":
        bucket = LIBRARY["neutral"].get("neutral_n%d" % tier, [])
    else:
        god = enc.get("fixed_god_id", "")
        bucket = LIBRARY["gods"].get("%s_n%d" % (god, tier), [])
    if not bucket:
        raise SystemExit(f"Pas de deck pour {node_id} ({god if not node['type'] == 'tutorial' else 'neutral'} n{tier})")
    best = None
    best_score = None
    for candidate in bucket:
        identity = sorted_deck(candidate["deck"])
        if identity in used_decks or identity in reserved_decks:
            continue
        if god and god_card_count(candidate["deck"], god) < 3:
            continue
        overlap = max((len(lineages(candidate["deck"]) & used) for used in selected_decks),
                      default=0)
        score = (overlap, len(identity), abs(sum(ord(c) for c in node_id) % 17 -
                                             int(candidate["seed"]) % 17))
        if best_score is None or score < best_score:
            best_score = score
            best = candidate
    if best is None:
        raise SystemExit(f"Bibliothèque épuisée pour {node_id}")
    deck = list(best["deck"])
    enc["fixed_deck"] = deck
    used_decks.add(sorted_deck(deck))
    selected_decks.append(lineages(deck))

# ── Contrôles de construction ───────────────────────────────────────────────
if len(nodes) != 120:
    raise SystemExit(f"120 nœuds attendus, obtenu {len(nodes)}")
if len(set(depth)) != 1 and max(depth.values()) < 45:
    raise SystemExit("profondeur de graphe insuffisante")
if len(edges) < 145:
    raise SystemExit(f"graphe trop pauvre : {len(edges)} arêtes")
weak_decks = []
for node_id, node in nodes.items():
    god = node["encounter"].get("fixed_god_id", "")
    deck = node["encounter"].get("fixed_deck", [])
    if god and deck and god_card_count(deck, god) < 3:
        weak_decks.append(node_id)
if weak_decks:
    raise SystemExit("decks fixes sans trois cartes du dieu : " + ", ".join(weak_decks))

# Quelques arêtes historiques traversent un couloir encombré : deux points de
# contrôle explicites gardent le tracé hors des ronds voisins.
for edge in edges:
    if edge["from"] == "kharun_02" and edge["to"] == "convergence_01":
        y1 = nodes["kharun_02"]["position"]["y"]
        # Godot utilise cubic_interpolate (poignées), pas une Bézier brute :
        # ces poignées gardent la courbe à distance des ronds du carrefour.
        edge["controls"] = [
            {"x": 560, "y": y1 - 40},
            {"x": 240, "y": y1 + 160},
        ]

# La hauteur inclut la marge basse dessinée par CampaignMapView.
map_height = max(n["position"]["y"] for n in nodes.values()) + 300

result = {
    "id": "samstone_campaign",
    "title": "La Carte de SamStone",
    "campaign_version": 2,
    "map": {"width": 1080, "height": int(map_height)},
    "start_node_id": "tuto_01",
    "final_node_id": "final_01",
    "nodes": list(nodes.values()),
    "edges": edges,
}

out = ROOT / "data" / "campaign" / "campaign_v2.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# ── Rapport de construction ─────────────────────────────────────────────────
def report() -> None:
    mode_counts = Counter(n["encounter"]["game_mode"] for n in nodes.values())
    tier_counts = Counter(n["encounter"]["max_power_tier"] for n in nodes.values())
    theme_counts = Counter(n["theme_god_id"] for n in nodes.values() if n["theme_god_id"])
    fixed_god_counts = Counter(n["encounter"]["fixed_god_id"] for n in nodes.values()
                               if n["encounter"]["fixed_god_id"])
    series_counts = Counter(n["encounter"]["series_format"] for n in nodes.values())
    optional = [n for n in nodes.values() if n["mini_boss_kind"] == "optional"]
    mandatory = [n for n in nodes.values() if n["mini_boss_kind"] == "mandatory"]
    dead_ends = [n for n in nodes.values() if not outgoing[n["id"]]]
    multi_exit = [n for n in nodes.values() if len(outgoing[n["id"]]) >= 2]
    merges = [n for n in nodes.values() if len(incoming[n["id"]]) >= 2]
    three_way = [n for n in nodes.values() if len(outgoing[n["id"]]) >= 3]
    four_way = [n for n in nodes.values() if len(outgoing[n["id"]]) >= 4]
    print(f"écrit {out} : {len(nodes)} nœuds, {len(edges)} arêtes, "
          f"profondeur {max(depth.values())}, carte {map_height}")
    print("modes", dict(mode_counts))
    print("paliers", dict(tier_counts))
    print("thèmes", dict(theme_counts))
    print("dieux fixes", dict(fixed_god_counts))
    print("séries", dict(series_counts))
    print(f"mini-boss optionnels {len(optional)}, obligatoires {len(mandatory)}, "
          f"impasses {len(dead_ends)}")
    print(f"multi-sorties {len(multi_exit)}, 3+ {len(three_way)}, 4+ {len(four_way)}, "
          f"regroupements {len(merges)}")
    print("decks fixes", len(used_decks))


report()
