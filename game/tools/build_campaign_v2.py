"""Construit la campagne de 162 nœuds à partir d'un plan de graphe explicite.

Le script ne fabrique pas de decks : il choisit dans `campaign_deck_library.json`
des decks déjà produits et validés par Godot. Les identifiants des 20 nœuds de
la première campagne unifiée sont conservés ; la version passe à 3 pour que la
migration des sauvegardes soit explicite. Les dix mini-boss facultatifs reçoivent
2 à 5 niveaux d'approche monochrome, insérés dans leur branche.
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
STONE_RARITY = {}
STONE_LEVEL = {}
STONE_TIER = {}
RARITY_OFFSET = {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
for lineage in STONES["lineages"]:
    for level_index, form in enumerate(lineage["levels"], start=1):
        form_id = str(form["id"])
        rarity = str(lineage.get("rarity", ""))
        level = int(form.get("level", level_index))
        LINEAGE[form_id] = str(lineage["id"])
        STONE_GOD[form_id] = str(lineage.get("god_id", "neutral"))
        STONE_RARITY[form_id] = rarity
        STONE_LEVEL[form_id] = level
        STONE_TIER[form_id] = int(form.get("power_tier", level + RARITY_OFFSET[rarity]))

MODES = {"C": "classic", "R": "random", "M": "mirror", "D": "draft"}

# Decks fixes signés : mini-boss et premières rencontres volontairement
# contrôlées. Ils sont réservés avant le tirage dans la bibliothèque pour
# qu'aucune rencontre ordinaire ne les duplique.
CURATED_DECKS = {
    "veskar_01": [
        "de_boiteux_n1", "devoracle_n1", "griffe_a_jetons_n1", "sou_ricanant_n1",
        "gueule_de_travers_n1", "ogre_droitier_n1",
        "croupier_manchot_n1", "jumeau_de_cuivre_n1",
    ],
    "nerava_01": [
        "clochelet_malade_n1", "crache_cendre_n1", "machoire_moisie_n1", "porte_fievre_n1",
        "le_drape_du_seuil_n1", "rampant_des_fosses_n1",
        "griffe_septique_n1", "ronge_chair_n1",
    ],
    "kharun_01": [
        "carapace_vide_n1", "eclat_cuirasse_n1", "heaume_errant_n1", "osselet_blinde_n1",
        "ecorche_angle_n1", "le_sac_a_murmures_n1",
        "chevalier_sans_visage_n1", "colosse_rivete_n1",
    ],
    "ilyr_01": [
        "bouche_arbalete_n1", "fauche_fond_n1", "longuepine_n1", "pique_en_haut_n1",
        "mache_mur_n1", "avortons_des_caves_n1",
        "dard_de_traverse_n1", "perce_voute_n1",
    ],
    "sylkha_01": [
        "bourgeon_mordant_n1", "larve_dancrage_n1", "nud_vivant_n1", "tisse_griffe_n1",
        "mordeur_des_combles_n1", "gueule_de_travers_n1",
        "fourmilion_des_nerfs_n1", "mante_des_racines_n1",
    ],
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

# Initiations obligatoires : les quatre communes N1 du dieu et quatre communes
# neutres N1 sont copiées à l'identique aux deux camps. Ces loadouts transitoires
# permettent d'essayer chaque dieu sans l'acheter ni modifier le profil.
INTRO_TRIALS = {
    "init_veskar": dict(name="La Table des Reflets", god="veskar", precision=0.03,
        deck=["de_boiteux_n1", "devoracle_n1", "griffe_a_jetons_n1", "sou_ricanant_n1",
              "gueule_de_travers_n1", "ogre_droitier_n1", "le_drape_du_seuil_n1", "rampant_des_fosses_n1"]),
    "init_nerava": dict(name="Le Reflet des Fièvres", god="nerava", precision=0.04,
        deck=["clochelet_malade_n1", "crache_cendre_n1", "machoire_moisie_n1", "porte_fievre_n1",
              "ecorche_angle_n1", "le_sac_a_murmures_n1", "mache_mur_n1", "mordeur_des_combles_n1"]),
    "init_kharun": dict(name="Le Reflet des Remparts", god="kharun", precision=0.05,
        deck=["carapace_vide_n1", "eclat_cuirasse_n1", "heaume_errant_n1", "osselet_blinde_n1",
              "gueule_de_travers_n1", "le_drape_du_seuil_n1", "ogre_droitier_n1", "rampant_des_fosses_n1"]),
    "init_ilyr": dict(name="Le Reflet des Veilleurs", god="ilyr", precision=0.06,
        deck=["bouche_arbalete_n1", "fauche_fond_n1", "longuepine_n1", "pique_en_haut_n1",
              "ecorche_angle_n1", "le_sac_a_murmures_n1", "mache_mur_n1", "mordeur_des_combles_n1"]),
    "init_sylkha": dict(name="Le Reflet de l'Essaim", god="sylkha", precision=0.08,
        deck=["bourgeon_mordant_n1", "larve_dancrage_n1", "nud_vivant_n1", "tisse_griffe_n1",
              "gueule_de_travers_n1", "ogre_droitier_n1", "le_drape_du_seuil_n1", "rampant_des_fosses_n1"]),
    "init_enigma": dict(name="Le Reflet des Assimilateurs", god="enigma", precision=0.10,
        deck=["collecteur_de_dents_n1", "depeceur_rampant_n1", "pince_carcasse_n1", "scie_boiteuse_n1",
              "ecorche_angle_n1", "le_sac_a_murmures_n1", "mache_mur_n1", "mordeur_des_combles_n1"]),
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

# Les six mini-boss signés gardent leur identité ; les quatre autres sont
# alignés sur la même exigence de difficulté. Le générateur n'est renseigné
# que lorsque le mode ne porte pas déjà un dieu fixe.
OPTIONAL_MINI_TUNING = {
    "mini_optional_01": dict(precision=0.80, anticipation=False, theme_god="nerava"),
    "r03_mini": dict(precision=0.80, anticipation=False, theme_god="veskar"),
    "r04_mini": dict(precision=0.85, anticipation=False, theme_god="sylkha"),
    "r05_mini": dict(precision=0.88, anticipation=False, theme_god="kharun"),
    "r06_mini": dict(precision=0.90, anticipation=False,
                      theme_god="sylkha", generator_god="sylkha", generator_min=8),
    "r09_mini1": dict(precision=0.92, anticipation=True, theme_god="ilyr"),
    "r09_mini2": dict(precision=0.92, anticipation=True, theme_god="ilyr"),
    "r10_mini": dict(precision=0.95, anticipation=True, theme_god="nerava"),
    "r11_mini": dict(precision=0.95, anticipation=True, theme_god="kharun"),
    "mini_optional_02": dict(precision=1.0, anticipation=True, theme_god="enigma"),
}

# Une impasse facultative reçoit 2 à 5 niveaux avant son mini-boss. La
# longueur augmente avec l'avancement ; le mode et le dieu du mini-boss sont
# conservés sur toute la branche.
OPTIONAL_PATHS = {
    "mini_optional_01": dict(length=2, names=[
        "Le Vestibule des Fièvres", "La Salle des Souffles"]),
    "r03_mini": dict(length=2, names=[
        "Le Détour des Dés", "La Passe Truquée"]),
    "r04_mini": dict(length=3, names=[
        "La Coulée des Larves", "Le Nid des Soufflets",
        "L’Antichambre de l’Essaim"]),
    "r05_mini": dict(length=3, names=[
        "Les Rayons Interdits", "Le Cabinet des Dettes",
        "La Chambre d’Encre"]),
    "r06_mini": dict(length=3, names=[
        "La Ruelle des Peaux", "Le Comptoir des Os",
        "Le Passage du Colporteur"]),
    "r09_mini1": dict(length=4, names=[
        "Le Puits des Reflets", "La Galerie des Veilleurs",
        "Le Mur des Échos", "La Garde sans Ombre"]),
    "r09_mini2": dict(length=4, names=[
        "Le Chœur Bas", "Les Voix Noyées", "La Nef des Murmures",
        "L’Autel du Chœur"]),
    "r10_mini": dict(length=4, names=[
        "La Galerie des Fièvres", "Le Bal des Masques",
        "La Loge des Malades", "Le Théâtre des Contagions"]),
    "r11_mini": dict(length=4, names=[
        "Les Allées Calcinées", "Le Mur des Cendres",
        "La Forge Éteinte", "Le Chemin des Carapaces"]),
    "mini_optional_02": dict(length=5, names=[
        "Le Seuil des Dépouilles", "La Salle des Mille Yeux",
        "Le Couloir des Faces", "Le Cabinet des Peaux",
        "Le Trône du Collectionneur"]),
}

# Placement local des approches. Les couloirs extérieurs évitent de décaler
# les nœuds existants : seuls les nouveau chemin et son mini-boss bougent.
# offset_y est relatif à la ligne du prédécesseur ; xs alterne les deux bords
# libres de la region. Les valeurs maintiennent 170 unités entre les centres.
OPTIONAL_PATH_LAYOUTS = {
    "mini_optional_01": dict(xs=[80, 80], offset_y=0, boss_x=90),
    "r03_mini": dict(xs=[1000, 940], offset_y=0, boss_x=760),
    "r04_mini": dict(xs=[1000, 940, 1000], offset_y=0, boss_x=900),
    "r05_mini": dict(xs=[80, 160, 80], offset_y=0, boss_x=100),
    "r06_mini": dict(xs=[1000, 1000, 940], offset_y=120, boss_x=900),
    "r09_mini1": dict(xs=[80, 160, 80, 160], offset_y=0, boss_x=80),
    "r09_mini2": dict(xs=[1000, 940, 1000, 940], offset_y=0, boss_x=1000),
    "r10_mini": dict(xs=[1000, 940, 1000, 940], offset_y=0, boss_x=960),
    # Le dernier tronçon remonte par le bord gauche. Le décaler à x=0
    # empêche l'arête vers le mini-boss de retraverser les trois approches
    # précédentes, ce que le validateur géométrique refuse à juste titre.
    "r11_mini": dict(xs=[80, 80, 80, 0], offset_y=-240, boss_y=15840,
                       boss_x=0),
    "mini_optional_02": dict(xs=[1000, 940, 1000, 940, 1000], offset_y=0,
                             boss_x=960),
}

PATH_STEP = 240

# Les trois premiers nœuds gardent leurs IDs. Deux combats d'entraînement puis
# six initiations miroir forment désormais une rampe obligatoire avant le
# carrefour historique.
OLD = {
    "tuto_01": dict(name="Le Seuil", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="tutoriel_seuil", type="tutorial", accent="#a6c79a"),
    "tuto_02": dict(name="La Leçon", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="tutoriel_lecture", type="tutorial", accent="#a6c79a"),
    "tuto_03": dict(name="Le Premier Pas", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="tutoriel_premier_pas", type="tutorial", accent="#a6c79a"),
    "tuto_04": dict(name="La Main Assurée", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="", type="tutorial", accent="#a6c79a"),
    "tuto_05": dict(name="Le Dernier Exercice", chapter="Seuil", region="Le refuge", mode="C", tier=1,
                    precision=0.0, anticipation=False, god="", deck_kind="neutral_n1",
                    tutorial="", type="tutorial", accent="#a6c79a"),
    "veskar_01": dict(name="La Table du Croupier", chapter="Carrefour", region="Les Aléators",
                      mode="C", tier=2, precision=0.10, god="veskar", deck_kind="fixed",
                      legacy_id="bot_veskar_n2_facile"),
    "nerava_01": dict(name="Les Fièvres Basses", chapter="Carrefour", region="Les Flétris",
                      mode="C", tier=2, precision=0.12, god="nerava", deck_kind="fixed",
                      legacy_id="bot_nerava_n2_facile"),
    "kharun_01": dict(name="La Muraille Fendue", chapter="Carrefour", region="Les Remparts",
                      mode="C", tier=2, precision=0.10, god="kharun", deck_kind="fixed",
                      legacy_id="bot_kharun_n2_facile"),
    "mini_optional_01": dict(name="Le Collectionneur", chapter="Carrefour", region="Les Assimilateurs",
                             mode="C", tier=3, precision=0.75, god="enigma", type="mini_boss",
                             mini_kind="optional", dead_end=True),
    "veskar_02": dict(name="Le Coup Double", chapter="Carrefour", region="Les Aléators",
                      mode="R", tier=3, precision=0.5, god="", series="ft2"),
    "ilyr_01": dict(name="La Ligne de Veille", chapter="Carrefour", region="Les Veilleurs",
                    mode="C", tier=2, precision=0.16, god="ilyr", deck_kind="fixed",
                    legacy_id="bot_ilyr_n2_facile"),
    "mirror_01": dict(name="Le Miroir de Verre", chapter="Carrefour", region="Le reflet",
                      mode="M", tier=3, precision=0.5, god=""),
    "kharun_02": dict(name="Le Rempart Mobile", chapter="Carrefour", region="Les Remparts",
                      mode="R", tier=3, precision=0.5, god="", series="ft2"),
    "sylkha_01": dict(name="La Meute Naissante", chapter="Carrefour", region="L’Essaim",
                      mode="C", tier=2, precision=0.18, god="sylkha", deck_kind="fixed",
                      legacy_id="bot_sylkha_n34_moyen"),
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
    "tuto_04": (3, 540), "tuto_05": (4, 540),
    "veskar_01": (0, 160), "nerava_01": (0, 540), "kharun_01": (0, 920),
    "mini_optional_01": (1, 90), "veskar_02": (1, 390), "ilyr_01": (1, 680),
    "kharun_02": (1, 940),
    "sylkha_01": (2, 280),    "mirror_01": (2, 640), "veilleur_impasse": (2, 940),
    "convergence_01": (3, 540), "boss_required_gate": (4, 540),
}

OLD_EDGES = [
    ("tuto_01", "tuto_02"), ("tuto_02", "tuto_03"),
    ("tuto_03", "tuto_04"), ("tuto_04", "tuto_05"),
    ("tuto_05", "init_veskar"), ("init_veskar", "init_nerava"),
    ("init_nerava", "init_kharun"), ("init_kharun", "init_ilyr"),
    ("init_ilyr", "init_sylkha"), ("init_sylkha", "init_enigma"),
    ("init_enigma", "veskar_01"), ("init_enigma", "nerava_01"),
    ("init_enigma", "kharun_01"),
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
            "legacy_opponent_id": spec.get("legacy_id", ""),
        },
        "rewards": {},
        "visual": {"scale": 1.0},
    }
    nodes[node_id] = node


# ── Seuil, initiations et carrefour historique ───────────────────────────────
start_y = 160
tutorial_ids = ["tuto_01", "tuto_02", "tuto_03", "tuto_04", "tuto_05"]
for node_id in tutorial_ids:
    depth, x = OLD_COORDS[node_id]
    add_node(node_id, OLD[node_id], x, start_y + depth * 240)
# Seule cette rencontre accepte le deck initial de cinq cartes. Elle est un
# contrat de contenu explicite, pas une exception dispersée dans l'interface.
nodes["tuto_01"]["encounter"].update({
    "board_size": 3,
    "player_hand_size": 5,
    "opponent_hand_size": 4,
    "allow_incomplete_player_deck": True,
    "blocked_cells": [],
    "forced_first_player": 1,
})
# Les deux combats de transition restent volontairement favorables au joueur.
for node_id in ["tuto_04", "tuto_05"]:
    nodes[node_id]["encounter"]["forced_first_player"] = 1

trial_y = start_y + len(tutorial_ids) * 240
for index, (node_id, trial) in enumerate(INTRO_TRIALS.items()):
    spec = dict(name=trial["name"], chapter="Initiations", region="La galerie des reflets",
                mode="M", tier=1, precision=trial["precision"], anticipation=False,
                god="", type="normal", series="ft1")
    add_node(node_id, spec, 540, trial_y + index * 240)
    node = nodes[node_id]
    node["theme_god_id"] = trial["god"]
    node["encounter"].update({
        "generator_god_id": trial["god"],
        "generator_min_god_cards": 4,
        "mirror_fixed_deck": list(trial["deck"]),
        "forced_first_player": 1,
    })

last_intro_y = trial_y + (len(INTRO_TRIALS) - 1) * 240
carrefour_y = last_intro_y + 340
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

# Les quatre mini-boss facultatifs restants reçoivent la même exigence de
# difficulté. Une contrainte de génération rend aussi leur dieu réel cohérent
# avec celui de l'impasse.
for node_id, spec in OPTIONAL_MINI_TUNING.items():
    if node_id not in nodes:
        raise SystemExit(f"mini-boss facultatif absent : {node_id}")
    node = nodes[node_id]
    enc = node["encounter"]
    node["type"] = "mini_boss"
    node["mini_boss_kind"] = "optional"
    node["dead_end"] = True
    enc["generator_god_id"] = spec.get("generator_god", enc.get("generator_god_id", ""))
    enc["generator_min_god_cards"] = spec.get("generator_min",
                                                enc.get("generator_min_god_cards", 0))
    if spec.get("theme_god"):
        node["theme_god_id"] = spec["theme_god"]


def branch_god(node: dict) -> str:
    """Dieu réellement combattu par un mini-boss, tous modes confondus."""
    enc = node["encounter"]
    return str(enc.get("fixed_god_id") or enc.get("generator_god_id")
               or node.get("theme_god_id", ""))


def insert_optional_paths() -> dict:
    """Insère les branches avant les mini-boss facultatifs.

    Les branches sont placées localement dans des couloirs extérieurs libres :
    aucun nœud existant n'est décalé, donc aucune arête historique ne s'étire.
    Seul le mini-boss descend sous son prédécesseur, avec ses nouveaux niveaux
    d'approche. Les couloirs et les offsets sont explicites par branche.
    """
    branch_pred = {}
    for edge in edges:
        if edge["to"] in OPTIONAL_PATHS:
            branch_pred[edge["to"]] = edge["from"]
    if set(branch_pred) != set(OPTIONAL_PATHS):
        raise SystemExit("un mini-boss facultatif n'a pas exactement une entrée")

    inserted = {}
    ordered = sorted(OPTIONAL_PATHS, key=lambda boss_id: nodes[boss_id]["position"]["y"],
                     reverse=True)
    for boss_id in ordered:
        path_spec = OPTIONAL_PATHS[boss_id]
        names = list(path_spec["names"])
        count = int(path_spec["length"])
        layout = OPTIONAL_PATH_LAYOUTS.get(boss_id, {})
        xs = list(layout.get("xs", []))
        if count < 2 or count > 5 or len(names) != count or len(xs) != count:
            raise SystemExit(f"branche facultative invalide pour {boss_id}")
        pred_id = branch_pred[boss_id]
        pred_y = nodes[pred_id]["position"]["y"]
        before = len(edges)
        edges[:] = [edge for edge in edges
                    if not (edge["from"] == pred_id and edge["to"] == boss_id)]
        if len(edges) != before - 1:
            raise SystemExit(f"arête de mini-boss introuvable : {pred_id} -> {boss_id}")

        offset_y = int(layout.get("offset_y", 0))
        boss = nodes[boss_id]
        enc = boss["encounter"]
        mode = enc["game_mode"]
        mode_key = {value: key for key, value in MODES.items()}[mode]
        god = branch_god(boss)
        if god == "":
            raise SystemExit(f"dieu absent sur la branche de {boss_id}")
        path_ids = []
        for index, name in enumerate(names):
            path_id = f"{boss_id}_path_{index + 1}"
            spec = {
                "name": name, "chapter": boss["chapter"], "region": boss["region"],
                "mode": mode_key, "type": "normal", "dead_end": False,
                "god": god if mode in ("classic", "draft") else "",
                "tier": 2, "precision": 0.0, "series": "ft1",
            }
            add_node(path_id, spec, xs[index],
                     pred_y + offset_y + PATH_STEP * (index + 1))
            path_node = nodes[path_id]
            path_node["theme_god_id"] = god
            if mode in ("random", "mirror"):
                path_node["encounter"]["generator_god_id"] = enc.get("generator_god_id", "")
                path_node["encounter"]["generator_min_god_cards"] = enc.get(
                    "generator_min_god_cards", 0)
            path_ids.append(path_id)
        boss["position"]["x"] = float(layout.get("boss_x", boss["position"]["x"]))
        boss_y = layout.get("boss_y")
        if boss_y is None:
            boss_y = pred_y + offset_y + PATH_STEP * (count + 1)
        boss["position"]["y"] = float(boss_y)
        chain = [pred_id] + path_ids + [boss_id]
        for source, target in zip(chain, chain[1:]):
            add_edge(source, target)
        inserted[boss_id] = path_ids
    return inserted


optional_paths = insert_optional_paths()

# Le couloir gauche des approches de r11_mini traverse la rangée r12. Ces deux
# nœuds existants sont seulement décalés vers la droite pour ouvrir le passage ;
# le reste du graphe garde ses positions et ses arêtes courtes.
nodes["r12_a"]["position"]["x"] = 260.0
nodes["r12_a1"]["position"]["x"] = 170.0

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
    if node_id in INTRO_TRIALS:
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

# Les niveaux d'approche montent d'un palier avant le mini-boss. Le dernier
# palier ne dépasse jamais celui du mini-boss, et la Sélection reste au moins
# au palier 3 comme toutes les Sélections de campagne.
for boss_id, path_ids in optional_paths.items():
    boss_tier = int(nodes[boss_id]["encounter"]["max_power_tier"])
    low_tier = max(2, boss_tier - 1)
    high_count = max(1, len(path_ids) // 2)
    for index, path_id in enumerate(path_ids):
        tier = low_tier if index < len(path_ids) - high_count else boss_tier
        if nodes[path_id]["encounter"]["game_mode"] == "draft":
            tier = max(3, tier)
        nodes[path_id]["encounter"]["max_power_tier"] = tier

# ── Thèmes de dieu : équilibre global, sans dieu fixe dans les modes variables ─
theme_counts = Counter()
last_theme = ""
forced_theme = {}
for node_id, trial in INTRO_TRIALS.items():
    theme_counts[trial["god"]] += 1
for boss_id, path_ids in optional_paths.items():
    boss_theme = branch_god(nodes[boss_id])
    forced_theme[boss_id] = boss_theme
    for path_id in path_ids:
        forced_theme[path_id] = boss_theme
for node_id, theme in forced_theme.items():
    nodes[node_id]["theme_god_id"] = theme
    theme_counts[theme] += 1
fixed_pending = []
variable = []
for node_id, node in nodes.items():
    if node["type"] == "tutorial" or node_id in forced_theme or node_id in INTRO_TRIALS:
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
    if node_id in OLD or node["type"] == "tutorial" or node_id in INTRO_TRIALS:
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

# Les mini-boss facultatifs sont tous des pics de difficulté. Les niveaux
# d'approche montent vers leur précision sans jamais la dépasser, et le dernier
# niveau de la branche reste un cran sous le mini-boss.
for boss_id, spec in OPTIONAL_MINI_TUNING.items():
    boss = nodes[boss_id]
    boss_precision = float(spec["precision"])
    boss["encounter"]["ai_profile"] = {
        "precision": boss_precision,
        "anticipation": bool(spec["anticipation"]),
    }
    path_ids = optional_paths[boss_id]
    count = len(path_ids)
    start = max(0.40, boss_precision - 0.25)
    end = boss_precision - 0.05
    for index, path_id in enumerate(path_ids):
        ratio = float(index) / float(max(1, count - 1))
        precision = round(start + (end - start) * ratio, 2)
        path = nodes[path_id]
        path["encounter"]["ai_profile"] = {
            "precision": precision,
            "anticipation": bool(spec["anticipation"] and precision >= 0.90),
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

# Récompenses explicites dans le JSON final. Le montant croît avec le palier,
# la précision et le statut du niveau ; seules les premières victoires de
# mini-boss/boss distribuent aussi des cartes.
FIRST_TUTORIAL_REWARDS = [
    "avortons_des_caves_n1", "mordeur_des_combles_n1",
    "mache_mur_n1", "le_sac_a_murmures_n1",
]
for node_id, node in nodes.items():
    enc = node["encounter"]
    tier = int(enc["max_power_tier"])
    precision = float(enc["ai_profile"]["precision"])
    boss_bonus = 18 if node["type"] == "boss" else 10 if node["type"] == "mini_boss" else 0
    base = 8 + tier * 3 + round(precision * 12) + boss_bonus
    node["rewards"] = {
        "souls_min": int(base),
        "souls_max": int(base + 5 + tier),
        "card_rewards": [],
    }
    if node_id == "tuto_01":
        node["rewards"]["card_rewards"] = FIRST_TUTORIAL_REWARDS
    elif node["type"] in {"mini_boss", "boss"}:
        fixed = enc.get("fixed_deck", [])
        wanted = 2 if node["type"] == "boss" else 1
        node["rewards"]["card_rewards"] = list(fixed[:wanted])

# ── Contrôles de construction ───────────────────────────────────────────────
if len(nodes) != 162:
    raise SystemExit(f"162 nœuds attendus, obtenu {len(nodes)}")
if len(set(depth)) != 1 and max(depth.values()) < 45:
    raise SystemExit("profondeur de graphe insuffisante")
if len(edges) != 190:
    raise SystemExit(f"190 arêtes attendues, obtenu {len(edges)}")
weak_decks = []
for node_id, node in nodes.items():
    god = node["encounter"].get("fixed_god_id", "")
    deck = node["encounter"].get("fixed_deck", [])
    if god and deck and god_card_count(deck, god) < 3:
        weak_decks.append(node_id)
if weak_decks:
    raise SystemExit("decks fixes sans trois cartes du dieu : " + ", ".join(weak_decks))

for node_id, trial in INTRO_TRIALS.items():
    deck = trial["deck"]
    god = trial["god"]
    if len(deck) != 8 or len(lineages(deck)) != 8:
        raise SystemExit(f"initiation miroir invalide sur {node_id}")
    if god_card_count(deck, god) != 4 or god_card_count(deck, "neutral") != 4:
        raise SystemExit(f"initiation {node_id} sans répartition 4/4")
    if any(STONE_RARITY.get(card) != "common" or STONE_LEVEL.get(card) != 1
           or STONE_TIER.get(card) != 1 for card in deck):
        raise SystemExit(f"initiation {node_id} avec une carte hors palier 1")

for node_id in ["veskar_01", "nerava_01", "kharun_01", "ilyr_01", "sylkha_01"]:
    deck = nodes[node_id]["encounter"]["fixed_deck"]
    tiers = Counter(STONE_TIER.get(card, 0) for card in deck)
    if tiers != Counter({1: 6, 2: 2}):
        raise SystemExit(f"courbe initiale invalide sur {node_id}: {dict(tiers)}")

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
    "campaign_version": 5,
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
