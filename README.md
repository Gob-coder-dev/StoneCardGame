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
moteur que le jeu via `res://`. Le simulateur Python accélère la collecte ;
des tests de parité et les évaluations Godot contrôlent sa compatibilité.

## Démarrage rapide

### Jeu

```powershell
cd game
godot --editor --path .
```

Tests principaux depuis la racine du dépôt :

```powershell
python game/tools/check_quality.py --godot godot --import --export
```

Le lanceur utilise des données utilisateur temporaires et conserve les journaux
dans `.tmp/quality/`, sans toucher au profil de jeu du poste.

### Reinforcement learning

Le trainer possède une collecte vectorisée, des évaluations Godot et un export
de politiques pour l'inférence native. Les anciens poids doivent être importés
dans un nouveau run puis réévalués lorsque les règles ou contrats changent.

```powershell
cd rl
py -3.11 -m venv .venv311
.\.venv311\Scripts\python.exe -m pip install -r requirements-directml.lock
.\.venv311\Scripts\python.exe -m pip install --no-build-isolation --no-deps -e .
.\.venv311\Scripts\python.exe -m pip check
```

La feuille de route et les critères de validation sont détaillés dans le
[plan de développement RL](rl/PLAN_DE_DEVELOPPEMENT.md). Le
[guide des commandes](rl/GUIDE_COMMANDES.md) précise le choix CPU/DirectML,
les migrations et les validations.

## Intégration des boss

L'entraînement a lieu hors du jeu avec Python et PyTorch. Les politiques finales
sont exportées sous forme de poids compacts, puis exécutées localement par Godot.
L'APK embarquera donc les modèles et les six decks de boss : aucun serveur,
Python ou entraînement sur le téléphone ne sera nécessaire.
