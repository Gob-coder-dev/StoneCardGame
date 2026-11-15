# SamStone RL

Entraînement hors ligne des six boss : collecte rapide en Python, apprentissage
PPO avec PyTorch, évaluations et certifications dans le moteur Godot du jeu.
Le contrat couvre les matchs **4 × 4, huit cartes et 128 actions**. Les tutoriels
3 × 3 ne font pas partie de ce format.

## Installation et utilisation

Python **3.11** et Godot **4.7.2** sont utilisés pour les vérifications.
Les environnements CPU et DirectML possèdent chacun leurs dépendances
verrouillées, outils de construction inclus.

```powershell
# Depuis rl/ : choisir CPU ou DirectML, puis installer le paquet local.
py -3.11 -m venv .venv311
.\.venv311\Scripts\python.exe -m pip install -r requirements-directml.lock
.\.venv311\Scripts\python.exe -m pip install --no-build-isolation --no-deps -e .
.\.venv311\Scripts\python.exe -m pip check
$env:GODOT_BIN = "C:\chemin\vers\Godot_v4.7.2-stable_win64_console.exe"
```

Pour CPU, utiliser `requirements-cpu.lock` et `device: cpu` dans le YAML.
Chaque processus du pont Godot dispose de données utilisateur temporaires :
il ne modifie pas la sauvegarde personnelle du joueur.

Le [guide des commandes](GUIDE_COMMANDES.md) détaille migration, entraînement,
validations et export. Les critères sont dans le [plan](PLAN_DE_DEVELOPPEMENT.md).
Le [bilan de validation](VALIDATION.md) détaille les corrections, contrôles et mesures.

## Contrats et compatibilité

- Le catalogue provient de `game/data/stones/manifest.json` et de ses familles.
  Ses définitions Python sont accessibles en lecture seule.
- L'observation v1 contient 929 valeurs ; les features tactiques v2 contiennent
  79 valeurs par action. Python et Godot partagent leur signification, leurs
  normalisations et leur générateur d'aperçus déterministes.
- L'estimation de riposte des features du réseau est une enveloppe publique
  stable. Le bot Godot conserve son propre modèle de riposte, d'aura et de fin
  de partie : améliorer ce bot ne change pas implicitement les entrées du réseau.
- Les checkpoints v2 conservent architecture, schémas, poids, optimiseur,
  curriculum, compteurs d'évaluation, RNG, provenance et identité de l'arbitre.
- La reprise complète exige des contrats compatibles. Les épisodes en cours
  sont réinitialisés : elle ne promet pas une trajectoire bit à bit identique
  sur tous les périphériques.
- Après modification des règles, du contenu ou des schémas, les anciens poids
  peuvent initialiser un nouveau run avec `--weights-only`. L'optimiseur,
  les compteurs, le curriculum et les certifications repartent alors de zéro.
- Un run existant ne peut pas être recréé implicitement. Un verrou système
  empêche plusieurs entraîneurs d'écrire dans le même dossier.

## Chaîne d'entraînement

1. Phase 4 : politique universelle tactique contre les profils Godot.
2. Phase 5 : self-play contre une ligue de checkpoints gelés.
3. Phase 6 : recherche de decks avec une politique universelle certifiée.
4. Phase 6B : spécialisation d'une politique par dieu et deck final.
5. Export : fichier `.sspolicy` float32 et inférence incrémentale dans Godot.

La configuration principale est `configs/ppo_phase4_vectorized.yaml` :
256 environnements Python, huit décisions par environnement, batch PPO de
2 048 transitions et dix arbitres Godot. Le curriculum comprend quatre niveaux
de précision puis quatre niveaux d'anticipation.

Les confirmations périodiques renouvellent leurs seeds. Pré-évaluation,
confirmations, ancrages et tournoi final ont des plages séparées dans la
configuration officielle. La validation finale de phase 4 conserve ses matchs
sur disque et reprend les cas manquants à contexte et poids identiques.

Une certification porte sur les poids exacts, leurs contrats et un rapport
réussi. Une mise à jour PPO produit un nouveau candidat à valider. Le seul
booléen `completed` ne suffit pas à certifier un modèle.

## Organisation

```text
configs/                  expériences et critères officiels
scripts/                  commandes, suivi, benchmarks et export
src/samstone_rl/
  fast_engine/            état scalaire, règles et RNG d'aperçus
  batch_engine/           collecte et encodage avec buffers réutilisables
  vector_engine/          noyaux tactiques et effets, référence scalaire conservée
  bridge/                 processus Godot isolés et pool persistant
  envs/                   contrat Gymnasium et observation publique
  tactics/                features par action versionnées
  models/                 construction commune, modèles et export
  training/               coordination PPO, optimisation, évaluation et checkpoints
  evaluation/             tournois durables, decks et comparaisons appariées
  specialization/         registre et apprentissage des six boss
  observability/          métriques, alertes, agrégation et rendu des rapports
  utils/                  provenance, certifications, verrouillage et statistiques
tests/                    unités, raccordement des phases et parité Godot
runs/, checkpoints/, artifacts/  résultats générés, ignorés par Git
```

## Vérification

```powershell
.\.venv311\Scripts\python.exe -m ruff check src scripts tests
.\.venv311\Scripts\python.exe -m pytest -q
```

Définir `GODOT_BIN` pour les tests d'intégration. La CI couvre aussi les
modifications des règles et données du jeu ; DirectML est vérifié localement.
Les tests comparent les états et scores tactiques des six dieux, les entrées et
sorties PyTorch/Godot et les reprises après interruption.

## Statut des modèles

Les outils d'entraînement, observabilité, export et inférence sont implémentés.
Les six boss doivent encore être entraînés ou réévalués puis certifiés avec les
contrats actuels avant leur activation. Les profils existants restent actifs
par défaut. La latence et la mémoire de l'inférence complète doivent également
être mesurées sur le téléphone cible.

Les benchmarks précisent matériel, périphérique, configuration, palier,
échauffement et répétitions. Le débit, le temps complet d'une mise à jour et le
niveau de jeu à budget égal sont des mesures distinctes.
