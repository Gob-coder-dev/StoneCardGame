# SamStone RL

Ce dossier entraîne les six futurs boss de SamStone. L'entraînement est local :
les règles du jeu sont simulées rapidement en Python, tandis que Godot reste la
référence pour les évaluations et la validation finale. Aucun serveur n'est
requis pour le boss embarqué dans l'APK.

## Chemin officiel

La phase 4 utilise `configs/ppo_phase4_vectorized.yaml` et produit ses
artefacts dans `runs/ppo_phase4_vectorized/`. Le moteur vectorise les coups
contrefactuels, les menaces de riposte, les auras et les faiblesses sur des
lots de 256 parties. Essaim et Pillage sont eux aussi traités exactement dans
le noyau vectorisé, sans retour au simulateur partie par partie. PPO tourne sur
DirectML afin d'utiliser aussi les GPU AMD sous Windows. Godot reste obligatoire
pour toutes les promotions.

La politique `tactical_actor_critic` évalue chaque coup légal avec les données
publiques du plateau : carte, case, capture immédiate, menace de riposte et
variation de contrôle. Ce calcul fait partie du boss final ; il n'est pas un
outil d'entraînement temporaire.

Le curriculum est :

```text
precision 0 -> 0,25 -> 0,50 -> 1,00
-> anticipation 25 % -> 50 % -> 75 % -> 100 %
```

Chaque palier demande deux évaluations indépendantes de 500 parties avec au
moins 85 % de victoires et au plus 7 % de défaites. La validation finale de la
phase 4 est plus stricte : 85 % de victoires et au plus 5 % de défaites, sur
tous les paliers, dieux, camps et ordres de départ.

Lors d'une première création avec `--weights-only`, une pré-évaluation parcourt
immédiatement les paliers déjà maîtrisés. Elle conserve les deux évaluations
indépendantes exigées par palier, mais n'entraîne pas entre elles. Au premier
échec, PPO reprend normalement sur ce palier ; ce point est sauvegardé dans
`latest.pt`.

## Structure

```text
configs/                 configurations actives des phases 4, 5, 6 et 6B
scripts/                 lancement, suivi, validations et rapports
src/samstone_rl/
  batch_engine/          collecte rapide Python
  bridge/                protocole avec Godot
  envs/                  environnement Gym et encodage
  fast_engine/           règles Python contrôlées
  models/                politique PPO tactique
  tactics/               features par action
  vector_engine/         noyaux d'anticipation vectorises et fallbacks exacts
  training/              PPO, curriculum, self-play et decks
  specialization/        entraînement des six boss
tests/                   tests unitaires et intégration Godot
runs/                    checkpoints et métriques, ignorés par Git
```

## Phases restantes

- **Phase 4** : politique universelle tactique contre les bots Godot.
- **Phase 5** : self-play et ligue de checkpoints.
- **Phase 6** : recherche de decks et statistiques d'équilibrage.
- **Phase 6B** : spécialisation d'un boss par dieu.
- **Phase 7** : export des poids pour Godot.
- **Phase 8** : observabilité, TensorBoard et rapports.

Le guide complet des commandes est dans [GUIDE_COMMANDES.md](GUIDE_COMMANDES.md).
L'architecture et les critères de validation sont dans
[PLAN_DE_DEVELOPPEMENT.md](PLAN_DE_DEVELOPPEMENT.md).

## Vérification développeur

Depuis `rl/` :

```powershell
.\.venv311\Scripts\python.exe -m pytest -q
.\.venv311\Scripts\python.exe -m ruff check src tests scripts
```

Benchmark reproductible du palier tactique principal :

```powershell
.\.venv311\Scripts\python.exe scripts\benchmark_fast_training.py `
  --config configs\ppo_phase4_vectorized.yaml `
  --updates 5 `
  --batch-size 2048 `
  --num-envs 256 `
  --stage precision_100_anticipation_50 `
  --device directml
```

La prédiction auxiliaire de la marge finale est expérimentale et désactivée
dans le run officiel. Elle apprend sur les épisodes du rollout courant, sans
imitation du bot et sans mémoire de replay. Son test A/B apparié est décrit dans
le guide des commandes.
