# SamStone

Ce dépôt est un monorepo contenant le jeu **SamStone** et son environnement
d'entraînement par renforcement. Les deux projets évoluent ensemble, mais
gardent leurs dépendances, tests et cycles d'exécution séparés.

## Projets

| Dossier | Rôle | Documentation |
| --- | --- | --- |
| [`game/`](game/) | Jeu Godot 4.7, moteur de règles, interface et tests | [README du jeu](game/README.md) |
| [`rl/`](rl/) | Simulateur d'entraînement, environnement Gymnasium, modèles et analyses | [README RL](rl/README.md) |

La fine couche Godot utilisée par le trainer se trouve dans
`game/tools/rl_sim/`. Elle reste dans le projet Godot afin d'accéder au même
moteur que le jeu via `res://`, sans recopier les règles en Python.

## Démarrage rapide

### Jeu

```powershell
cd game
godot --editor --path .
```

Tests principaux depuis la racine du dépôt :

```powershell
godot --headless --fixed-fps 60 --path game res://tests/GodSystemChecks.tscn
godot --headless --fixed-fps 60 --path game res://tests/TouchInputChecks.tscn
```

### Reinforcement learning

Le trainer est en cours de reconstruction. Les anciens fichiers constituent un
prototype et ne doivent pas encore servir à lancer un entraînement long.

```powershell
cd rl
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e .
```

La feuille de route et les critères de validation sont détaillés dans le
[plan de développement RL](rl/PLAN_DE_DEVELOPPEMENT.md).

## Intégration des boss

L'entraînement a lieu hors du jeu avec Python et PyTorch. Les politiques finales
sont exportées sous forme de poids compacts, puis exécutées localement par Godot.
L'APK embarquera donc les modèles et les six decks de boss : aucun serveur,
Python ou entraînement sur le téléphone ne sera nécessaire.
