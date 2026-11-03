# Guide d'utilisation — SamStone RL

Toutes les commandes ci-dessous sont à lancer depuis le dossier `rl` dans
PowerShell.

```powershell
cd "C:\Users\yanis\Desktop\Codes\godot\cardgame\StoneCardGame\rl"
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
```

`GODOT_BIN` est requis par l'entraînement officiel : les évaluations utilisent
Godot. Il doit être défini dans chaque nouveau terminal qui entraîne, valide ou
évalue un checkpoint avec Godot.

## Fichiers et dossiers actifs

```text
configs/ppo_phase4_tactical.yaml   phase 4 officielle
runs/ppo_phase4_rebalanced/        checkpoints et métriques de phase 4
configs/ppo_self_play_v2.yaml      phase 5, après validation de phase 4
configs/deck_evolution.yaml         phase 6, recherche de decks
configs/boss_specialization.yaml    phase 6B, un boss par dieu
```

Un run contient notamment :

```text
latest.pt             dernier checkpoint complet, à utiliser pour reprendre
best.pt               meilleur checkpoint d'évaluation
metrics.jsonl         métriques d'entraînement et évaluation
alerts.jsonl          alertes de santé
run_manifest.json     configuration et empreintes de reproductibilité
tensorboard/          événements TensorBoard
```

## Première création de la phase 4 officielle

Le dossier `runs/ppo_phase4_rebalanced/` doit être vide ou absent. Cette commande
importe seulement les poids du meilleur checkpoint tactique existant : le nouvel
optimiseur et le curriculum officiel repartent au palier `precision_0`.

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_tactical.yaml `
  --resume checkpoints\phase4_pre_rebalance_best.pt `
  --weights-only
```

`--weights-only` est réservé à cette création : il copie les poids, mais jamais
l'état Adam, les compteurs, les RNG ou le palier de la source.

La première exécution effectue automatiquement une pré-évaluation : deux tests
indépendants de chaque palier sont lancés sans entraînement intermédiaire. Les
paliers validés sont sautés ; au premier échec, l'entraînement PPO commence à
ce niveau. Cette progression est sauvegardée dans `latest.pt`, y compris si
l'exécution est interrompue pendant la pré-évaluation.

## Reprendre la phase 4

Après un arrêt normal ou `Ctrl+C`, reprendre avec le dernier checkpoint complet :

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_tactical.yaml `
  --resume runs\ppo_phase4_rebalanced\latest.pt
```

Ne pas ajouter `--weights-only` lors d'une reprise. `--reset-optimizer` ne sert
que lorsqu'on veut volontairement conserver les poids et le curriculum, mais
réinitialiser Adam après un changement d'hyperparamètres compatible.

## Suivi en direct

TensorBoard :

```powershell
.\.venv311\Scripts\python.exe -m tensorboard.main `
  --logdir runs\ppo_phase4_rebalanced\tensorboard `
  --port 6006
```

Puis ouvrir `http://localhost:6006`.

Surveillance des alertes et dernières évaluations :

```powershell
.\.venv311\Scripts\python.exe scripts\monitor_training.py `
  runs\ppo_phase4_rebalanced `
  --follow `
  --interval 20
```

Nombre de parties observées :

```powershell
.\.venv311\Scripts\python.exe scripts\training_stats.py `
  runs\ppo_phase4_rebalanced
```

Profil des vingt dernières mises à jour :

```powershell
.\.venv311\Scripts\python.exe scripts\profile_training.py `
  runs\ppo_phase4_rebalanced `
  --last-updates 20
```

## Arrêt et reprise

`Ctrl+C` arrête le processus ; les checkpoints sont atomiques. Le travail depuis
la dernière sauvegarde peut être perdu, mais un `latest.pt` valide reste
rechargeable. Attendre la fin d'une évaluation limite ce petit écart.

## Validation finale de phase 4

Quand l'entraînement indique que le dernier palier est prêt pour validation :

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase4.py `
  runs\ppo_phase4_rebalanced\best.pt `
  --config configs\ppo_phase4_tactical.yaml
```

Si elle réussit, la commande crée
`runs/ppo_phase4_rebalanced/phase4_validated.pt`. C'est le seul checkpoint qui
autorise officiellement la phase 5.

## Phases ultérieures

Phase 5 :

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_v2.yaml `
  --phase4 runs\ppo_phase4_rebalanced\phase4_validated.pt
```

Phase 6, recherche de decks :

```powershell
.\.venv311\Scripts\python.exe scripts\run_deck_evolution.py `
  --config configs\deck_evolution.yaml
```

Phase 6B, spécialisation :

```powershell
.\.venv311\Scripts\python.exe scripts\train_boss.py `
  --config configs\boss_specialization.yaml
```

## Repartir de zéro

Ne supprimer que le run visé, jamais `runs/` en entier. Par exemple, pour une
nouvelle phase 4, arrêter le processus puis supprimer manuellement le dossier
`runs/ppo_phase4_rebalanced/`. Lancer ensuite la commande de « Première création
de la phase 4 officielle ».
