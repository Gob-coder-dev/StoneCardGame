# Guide des commandes — SamStone RL

Toutes les commandes suivantes se lancent depuis `rl/`, sauf indication.
Les chemins de Godot sont des exemples à adapter au poste.

## Installer et vérifier

Utiliser Python 3.11. Le venv Python 3.14 ne convient pas à cet environnement.
Pour DirectML sous Windows :

```powershell
py -3.11 -m venv .venv311
.\.venv311\Scripts\python.exe -m pip install -r requirements-directml.lock
.\.venv311\Scripts\python.exe -m pip install --no-build-isolation --no-deps -e .
$env:GODOT_BIN = "C:\chemin\vers\Godot_v4.7.2-stable_win64.exe"
.\.venv311\Scripts\python.exe scripts\check_environment.py --strict-lock
```

Pour CPU, installer `requirements-cpu.lock` et remplacer `device: directml`
par `device: cpu` dans la configuration choisie. Les deux environnements sont
verrouillés séparément ; ne pas remplacer PyTorch seul dans le venv DirectML.

Le vérificateur contrôle Python, les dépendances, une vraie mise à jour sur le
périphérique, le catalogue et les identités Python/Godot. `--skip-godot` vérifie
uniquement la partie Python. Il ne crée pas de run. Le pont Godot isole les
données utilisateur de chaque processus.

```powershell
.\.venv311\Scripts\python.exe -m pip check
.\.venv311\Scripts\python.exe -m ruff check src scripts tests
.\.venv311\Scripts\python.exe -m pytest -q
```

## Choisir création, migration ou reprise

Depuis le 17 novembre 2026, la collecte officielle est autonome en Python :
`profile_backend: python`, avec quatre processus CPU persistants réglables par
`python_profile_workers`. Les scores reproduisent MoveEvaluator, RiposteModel
et EndgameSearch, y compris les tirages PCG des aperçus natifs. Les ripostes
sont calculées par lots NumPy. Les features tactiques du réseau conservent leur
contrat LCG indépendant. Godot n'est appelé que pour les validations et tests.
`profile_backend: godot` reste disponible pour les diagnostics de conformité.

Pour le run v3 existant, arrêter le processus puis reprendre son `latest.pt`
avec `--allow-python-source-change --quiet`, sans `--weights-only`. La migration
Godot → Python fidèle conserve Adam, le palier, les compteurs et les poids.
Le manifeste enregistre le changement ; tous les autres champs de l'identité
moteur doivent correspondre. Une migration depuis `python_approximate` exige
un nouveau run et l'import des poids.

Le protocole Godot utilise `monster` / `monster_id` ; le pont traduit les noms
historiques internes du RL pour conserver le format des modèles et historiques.
Après un renommage de classes Godot, effectuer une importation dans l'éditeur
avant le lancement headless afin de régénérer son cache de classes.

Importer `runs/ppo_phase4_vectorized_v2/latest.pt` avec `--weights-only` dans le
run v3 : les poids sont conservés, Adam et les compteurs sont réinitialisés.
La pré-évaluation retrouve les paliers maîtrisés. L'ancien run reste intact.
Ne pas utiliser `--allow-python-source-change` pour contourner le changement
de moteur/catalogue associé au renommage.

Le suivi `training/by_opponent_stage`, `training/by_god` et
`training/by_blocked_count` sépare les parties terminées par adversaire réel,
dieu et terrain. Les alertes d'évaluation sont calculées par palier et portent
ce palier dans le journal ; les anciens scores globaux ne leur servent pas de
référence. Les ancrages de 24 parties restent des signaux peu précis, à confirmer.

La configuration officielle est `configs/ppo_phase4_vectorized.yaml` et le
nouveau dossier est `runs/ppo_phase4_aligned_v3/`. Les anciens runs restent
conservés. Le programme refuse de créer implicitement un run dans un dossier
contenant déjà des résultats et bloque les écritures concurrentes.

Créer un nouveau modèle :

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_vectorized.yaml
```

Importer des poids antérieurs au contrat v2, dans un dossier neuf :

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_vectorized.yaml `
  --resume runs\ppo_phase4_vectorized_v2\latest.pt --weights-only --quiet
```

L'import conserve les poids compatibles. Il initialise un nouvel optimiseur,
un nouveau curriculum et de nouveaux compteurs ; il ne transmet aucune
certification. Si l'architecture classique est importée dans le modèle tactique,
les couches compatibles sont transférées et la tête tactique est initialisée.

La pré-évaluation officielle peut avancer dans les paliers déjà maîtrisés.
Elle réalise deux confirmations par palier, sans apprentissage entre elles,
puis démarre PPO au premier échec. Les compteurs sont sauvegardés.

Reprendre le run aligné v3 après un arrêt :

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_vectorized.yaml `
  --resume runs\ppo_phase4_aligned_v3\latest.pt --allow-python-source-change --quiet
```

Une reprise conserve l'état d'apprentissage enregistré, mais redémarre les
parties en cours. Les mises à jour postérieures au dernier checkpoint peuvent
être perdues lors d'un arrêt. `Ctrl+C` ne garantit pas la sauvegarde d'une
optimisation incomplète.

Après un changement de règles, de contenu ou de schéma, utiliser un nouveau run
et `--weights-only`. Un changement volontaire de learning rate compatible exige
`--reset-optimizer`. Ne pas contourner un refus d'empreinte en modifiant le
manifeste ou le fichier `.sha256`.

Les scripts de campagne, de boutique et d'inventaire entrent aussi dans
l'empreinte globale Godot. Si seuls ces fichiers hors combat ont changé,
la reprise vérifie automatiquement les empreintes individuelles, puis conserve
la progression et journalise la migration. Les nouveaux checkpoints contiennent
ces empreintes ; pour un ancien checkpoint, une version Git parmi les 64 derniers
commits doit correspondre exactement à l'ancienne empreinte globale. Sans cette
preuve, ou si un script de combat, du bot, le catalogue ou le contrat change,
la reprise reste refusée. `--allow-python-source-change` autorise séparément
les changements Python vérifiés ; il ne désactive aucun de ces contrôles.

Une reprise peut prolonger `ppo.total_timesteps`, ajuster le suivi, changer de
périphérique ou déplacer l’exécutable Godot compatible. Ces changements sont
historisés dans le manifeste. Le taux d’apprentissage ne peut changer qu’avec
`--reset-optimizer`. Les paramètres qui définissent l’expérience, comme les
récompenses, `gamma`, les scénarios et le curriculum, exigent un nouveau run.

## Reprise principale avec le seuil de Veskar à 60 %

Dans `configs/ppo_phase4_vectorized.yaml`, `curriculum.god_thresholds` et
`evaluation.final_gate.god_thresholds` exigent au moins 60 % de victoires et au
plus 20 % de défaites pour Veskar. Les autres dieux conservent les seuils du
parcours principal. Ils sont évalués en groupe, indépendamment de Veskar, avec
leurs contrôles de confiance et leurs limites par tranche habituels.

Veskar est jugé sur l’ensemble de ses parties dans une confirmation, puis sur
l’ensemble de ses parties de chaque palier lors de la validation finale. Les
tranches camp/premier joueur restent obligatoires et complètes ; leurs petites
séries n’imposent pas chacune le seuil de victoire de Veskar.

Depuis `rl/`, reprendre les poids et Adam du run principal :

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_vectorized.yaml `
  --resume runs\ppo_phase4_aligned_v3\latest.pt `
  --allow-python-source-change `
  --quiet
```

Le changement des critères conserve le palier et l’optimiseur mais remet à zéro
les confirmations et relance la pré-évaluation de ce palier. Le passage à la
phase suivante exige toujours les validations Godot ; aucun résultat n’est forcé.
L’option de changement Python est nécessaire après le nettoyage et les correctifs.
Elle ne permet pas de changer les récompenses, le contenu ou les schémas.

Les campagnes Veskar terminées ont été retirées des scripts et de la documentation.
Leurs résultats et checkpoints locaux sous `artifacts/` sont conservés ; les
anciens modèles restent lisibles. Les tests de non-régression et les outils de
validation générale sont maintenus.

## Suivi et benchmarks

```powershell
.\.venv311\Scripts\python.exe -m tensorboard.main `
  --logdir runs\ppo_phase4_aligned_v3\tensorboard --port 6006
.\.venv311\Scripts\python.exe scripts\monitor_training.py runs\ppo_phase4_aligned_v3 --follow --interval 5
.\.venv311\Scripts\python.exe scripts\generate_training_report.py runs\ppo_phase4_aligned_v3
```

TensorBoard est accessible à `http://localhost:6006` pendant son exécution.

Test court du chemin officiel, avec sorties temporaires et sans évaluation
Godot ni pré-évaluation de promotion :

```powershell
.\.venv311\Scripts\python.exe scripts\benchmark_fast_training.py `
  --config configs\ppo_phase4_vectorized.yaml --updates 3 `
  --num-envs 8 --batch-size 64 --epochs 1 --device directml
```

Profil représentatif d'un palier tactique :

```powershell
.\.venv311\Scripts\python.exe scripts\benchmark_fast_training.py `
  --config configs\ppo_phase4_vectorized.yaml --updates 5 `
  --num-envs 256 --batch-size 2048 `
  --stage precision_100_anticipation_50 --device directml
```

Comparaison isolée de la projection du réseau, avec échauffement et ordre alterné :

```powershell
.\.venv311\Scripts\python.exe scripts\benchmark_policy.py `
  --device directml --batch-size 256 --iterations 5 --warmup 2 `
  --output artifacts\benchmark_policy.json
```

Ces mesures ne remplacent pas une comparaison de niveau à budget d'apprentissage
égal sur plusieurs graines. Ne pas modifier simultanément récompenses,
curriculum et paramètres PPO pour interpréter une expérience.

## Phase 4 automatique et validation finale

Le lancement principal suffit désormais pour apprendre, confirmer les paliers,
valider le candidat final et s'arrêter après certification :

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_cleanrl `
  --config configs\ppo_phase4_vectorized.yaml `
  --resume runs\ppo_phase4_aligned_v3\latest.pt `
  --allow-python-source-change `
  --quiet
```

Les confirmations intermédiaires conservent leurs critères. Après celles du
dernier palier, PPO s'interrompt pendant le tournoi Godot de 19 200 parties.
Le candidat est figé sous `evaluations/phase4/candidates/`. Une réussite crée
`phase4_validated.pt`, sauvegarde `latest.pt` et arrête le programme. La phase 5
se lance ensuite séparément.

Un échec des critères reprend l'apprentissage avec Adam conservé. La tentative
suivante exige au moins 100 nouvelles mises à jour, de nouveaux poids et deux
nouvelles confirmations. Ses seeds sont distincts des tentatives précédentes.
Le programme s'arrête aussi après trois validations finales échouées ou après
épuisement de `ppo.total_timesteps`, avec un code de sortie 2 et sans certification.
Ces limites se règlent dans `phase4_automation` et `ppo`. Augmenter
`maximum_failed_attempts` ou le budget PPO permet de reprendre depuis `latest.pt`.

Le checkpoint historique du run v3, sans cet automate, reprend d'abord PPO
et renouvelle ses confirmations avant de proposer un nouveau candidat : il
ne relance pas immédiatement le tournoi manuel déjà échoué.

Pour suivre l'état même avec `--quiet`, dans un autre PowerShell depuis `rl/` :

```powershell
while ($true) {
  Clear-Host
  Get-Content runs\ppo_phase4_aligned_v3\phase4_status.json -Raw -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 5
}
```

`phase` indique `training`, `validating`, `completed`, `retry_limit_reached` ou
`budget_exhausted`. Pendant le tournoi, `completed_games` et `total_games`
indiquent la progression, également enregistrée sous `final_gate_progress` dans
TensorBoard. Le fichier de statut informe ; le checkpoint contient l'état de
reprise faisant autorité.

Après une interruption, relancer exactement la commande principale ci-dessus.
Une validation en cours reprend ses matchs manquants sur le même candidat,
avant toute mise à jour PPO. Une erreur technique reste visible et ne compte
pas parmi les échecs statistiques. Garder les sources et les critères du
candidat pendant cette reprise : `--allow-python-source-change` ne permet pas
de mélanger deux contextes dans une validation figée.

La commande de validation manuelle reste disponible pour un diagnostic isolé.
Arrêter l'entraîneur avant de l'utiliser dans le même dossier. Le dernier
palier doit être maîtrisé et attendre sa validation finale.

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase4.py `
  runs\ppo_phase4_aligned_v3\latest.pt --config configs\ppo_phase4_vectorized.yaml
```

Le tournoi complet représente 19 200 parties. Ses résultats sont conservés sous
`evaluations/phase4/` ; relancer avec le même checkpoint et contexte reprend les
cas manquants. Une réussite produit `phase4_validated.pt` et sa certification.
Une modification des poids ou de l'arbitre définit un autre tournoi.

Pour réévaluer des poids antérieurs sans refaire un apprentissage, ajouter
`--reevaluate` à la commande de validation. Ce mode importe les poids compatibles
et exécute la garde complète avec les contrats actuels. Les anciens compteurs
sont conservés comme provenance de la source ; ils ne deviennent pas des étapes
d'apprentissage du nouveau run. Il ne faut pas utiliser les résultats partiels
de ce tournoi pour ajuster les hyperparamètres.

## Recalculer une validation finale avec les critères révisés

Les critères d'entrée en phase 5 conservent les contrôles globaux et l'exception
de Veskar. Chaque dieu hors Veskar doit aussi obtenir au moins 80 % de victoires
et au plus 10 % de défaites par palier sur 400 parties. Les tranches de 100
parties ont un plancher de victoire de 70 % et un plafond de défaite de 20 %.
Ces changements concernent la garde finale, pas les confirmations de promotion.

Le run v3 ayant déjà terminé ses trois tournois, recalculer les résultats du
dernier candidat sans reprendre PPO ni rejouer les matchs :

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
.\.venv311\Scripts\python.exe scripts\validate_phase4.py `
  runs\ppo_phase4_aligned_v3\latest.pt `
  --config configs\ppo_phase4_vectorized.yaml `
  --reuse-recorded `
  --allow-python-source-change
```

Ajouter `--check-only` pour vérifier sans écrire de certificat. Godot ne sert
ici qu'à vérifier le manifeste du moteur ; les résultats sont lus dans le
registre original. Une incompatibilité ou une série incomplète arrête la
commande sans lancer de nouvelles parties et sans certifier le modèle.

Une réussite crée `phase4_validated.pt`, met à jour `latest.pt` et le statut
`completed`, en conservant les poids, Adam et les compteurs. L'ancien latest
est archivé sous `evaluations/phase4/candidates/*.before_reassessment.pt`.
Le rapport révisé `*.reassessment.json` conserve le caractère rétrospectif,
les deux jeux de critères et les empreintes des preuves. Les candidats et
leurs anciens rapports restent intacts. Ce recalcul ne constitue pas une
nouvelle évaluation indépendante. Il n'assouplit pas automatiquement les seuils.
Après réussite, lancer la phase 5 avec la commande suivante.

## Phase 5 : champion, candidat et arrêt automatique

La configuration `configs/ppo_self_play_80_varied.yaml` utilise quatre ratios,
de 7 cartes du dieu et 1 neutre à 4 cartes du dieu et 4 neutres. Chaque
composition compte 8 lignées distinctes et coûte exactement 80 points.
Pour chaque dieu et chaque ratio, la collecte tire parmi 4 decks. Les
évaluations tournent sur 2 autres decks, puis 2 decks supplémentaires sont
réservés à la validation finale. Les deux politiques évaluées conservent
les mêmes decks, terrains et graines dans les comparaisons appariées.
Le script `generate_phase5_deck_pools.py` reconstruit la configuration et
fait valider tous les decks par Godot.

Depuis `rl/`, démarrer le run à decks variés à partir du champion certifié.

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
$env:PYTHONPATH = (Resolve-Path "artifacts\phase5_compat_7163154e\rl_varied\src").Path
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_80_varied.yaml `
  --transfer-from runs\ppo_self_play_80\phase5_validated.pt `
  --allow-python-source-change --quiet
```

Pour reprendre ce run, utiliser `--resume runs\ppo_self_play_80_varied\latest.pt`
à la place de `--transfer-from ...`. TensorBoard lit
`runs\ppo_self_play_80_varied\tensorboard`.

Pour entraîner la phase 5 avec les six decks validés à 80 points, utiliser
`configs/ppo_self_play_80.yaml`. L'option `--transfer-from` prend le
`latest.pt` du run source et charge les poids de son dernier champion promu.
Le run à 80 points démarre avec son propre compteur de promotions et son
propre optimiseur. La référence de phase 4 est évaluée avec les decks à
80 points lors des contrôles contre les bots. Avec les sources de la copie
compatible chargées depuis `rl/` :

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
$env:PYTHONPATH = (Resolve-Path "artifacts\phase5_compat_7163154e\rl_budget80\src").Path
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_80.yaml `
  --transfer-from runs\ppo_self_play_v2\latest.pt `
  --allow-python-source-change --quiet
```

Après le premier lancement, utiliser `--resume runs\ppo_self_play_80\latest.pt`
pour continuer ce run. Les événements TensorBoard sont enregistrés dans
`runs\ppo_self_play_80\tensorboard`. Après certification, le checkpoint de
ce run pour la phase 6 est `runs\ppo_self_play_80\phase5_validated.pt`.

La collecte reste en Python et les validations utilisent Godot. Un démarrage
avec `--phase4` fait du modèle de phase 4 le premier champion figé. Le champion
change seulement après deux confirmations réussies et les contrôles de
conservation par dieu, contre les anciens champions et les bots.

Pour le run de phase 5 déjà commencé avec l'ancien plan, arrêter d'abord
l'ancien entraîneur, puis migrer dans le même dossier :

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godot\Godot_v4.7.2-stable_win64.exe"
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_v2.yaml `
  --resume runs\ppo_self_play_v2\latest.pt `
  --migrate-legacy-phase5 `
  --allow-python-source-change `
  --quiet
```

La migration conserve les poids, Adam, le RNG et les compteurs d'apprentissage.
Le nombre de promotions repart de zéro avec le champion de phase 4 ; le modèle
ayant déjà appris reste le candidat. L'ancien checkpoint est archivé dans
`checkpoints/legacy_phase5_source.pt` et le manifeste dans
`league/legacy_manifest.json`. Les anciens fichiers restent sur disque.

Pour les reprises suivantes, sans autre changement du code :

```powershell
.\.venv311\Scripts\python.exe -u -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_v2.yaml `
  --resume runs\ppo_self_play_v2\latest.pt `
  --quiet
```

Pour démarrer un nouveau run, le dossier configuré doit être neuf. Remplacer
`--resume ...` par `--phase4 runs\ppo_phase4_aligned_v3\phase4_validated.pt`.
Si seules les sources Python diffèrent depuis la certification de phase 4,
`--allow-python-source-change` autorise explicitement cette transition.
Les règles, le contenu, les schémas, les decks et les récompenses restent vérifiés.

Le déroulement par défaut est le suivant :

- Présélection toutes les 100 mises à jour : 144 duels équilibrés, score minimum
  52 %. Une présélection réussie ne remplace pas le champion.
- Le candidat figé passe d'abord les contrôles contre les bots des huit paliers,
  puis contre les anciens champions. Chaque palier couvre les 36 confrontations
  de dieux, dont 6 miroirs. Le candidat et la référence jouent les mêmes parties.
  Un échec arrête la tentative immédiatement.
- Deux confirmations distinctes de 1 152 duels, au moins 53 % de
  score et borne bootstrap appariée supérieure à 50 % à chaque confirmation.
- Contrôle de conservation par dieu contre le champion.
  Les désavantages entre dieux sont comparés à leur référence, sans imposer un
  même taux de victoire absolu à toutes les confrontations.
- Trois promotions visées. La dernière exige aussi 1 728 duels indépendants et
  de nouveaux contrôles historiques et Godot. Après réussite, le programme
  produit `phase5_validated.pt` et s'arrête automatiquement.

Le score compte victoire = 1, nul = 0,5 et défaite = 0. Le bootstrap travaille
sur les paires qui inversent les modèles dans les mêmes conditions initiales.
Il estime la confiance dans le score ; il ne prouve pas que le niveau maximal
du jeu a été atteint. Les confirmations et la fin de campagne ont des seeds
distincts de la présélection et de la collecte.

Le bloc `phase5.adaptive_opponents` fixe la part initiale de bots à 40 %.
Toutes les 100 mises à jour, un suivi Godot compare le candidat à la référence
de phase 4 sur les mêmes 36 confrontations. Le suivi utilise ses propres
graines et registres. Deux suivis concordants ajustent le ratio de 5 points,
dans l’intervalle de 25 % à 50 %. Les profils dont l’écart dépasse le seuil
de conservation reçoivent davantage de parties. La moitié des tirages de bots
reste uniforme sur les huit profils. Le ratio et la série de résultats sont
stockés dans le checkpoint. Si le suivi est interrompu, le programme reprend
les parties manquantes avant la prochaine collecte.

L’activation sur un ancien checkpoint ouvre une nouvelle fenêtre de patience
à partir de la mise à jour sauvegardée. Les poids, Adam, les champions et les
rapports existants sont repris. Après une mise à jour du code, utiliser
`--allow-python-source-change` à la première reprise. Avec une copie compatible
du jeu, `PYTHONPATH` doit désigner les sources RL mises à jour de cette copie.
`phase5_status.json` affiche la part cible de bots et la prochaine mise à jour
de suivi. Les écarts et poids par profil apparaissent dans `phase5_bot_followup`.

Le programme s'arrête également après 1 500 mises à jour sans promotion ou
après épuisement du budget PPO. Ces arrêts ont le code de sortie 2 et ne
produisent pas de certificat. `maximum_updates_without_promotion` ou
`ppo.total_timesteps` peuvent être augmentés avant une reprise. Les critères
ne sont jamais assouplis automatiquement.

Une validation interrompue reprend ses matchs manquants avant toute optimisation.
Après un changement des seules sources Python, `--allow-python-source-change`
recommence la validation du candidat figé avec de nouveaux seeds et registres.
La tentative précédente est conservée dans `superseded_attempts`. La nouvelle
validation précède toute mise à jour PPO. Les changements de critères ou de
règles exigent de reprendre le contexte d'origine. Une erreur technique reste
visible avec `--quiet` et ne compte pas comme un échec de performance.

Le backend Python regroupe les décisions des parties qui utilisent le même
checkpoint adverse. Chaque partie conserve son générateur aléatoire. Pour
mesurer ce regroupement avec les poids et l'optimiseur du run courant, arrêter
l'entraînement puis lancer depuis `rl/` :

```powershell
.\.venv311\Scripts\python.exe -u scripts\benchmark_champion_batch.py `
  --checkpoint runs\ppo_self_play_v2\latest.pt
```

Le benchmark alterne les décisions individuelles et groupées dans des dossiers
temporaires. Il mesure la collecte et les mises à jour PPO, après échauffement.
Le rapport est écrit dans `artifacts/champion_batch_benchmark.json`. Les mesures
excluent les évaluations Godot et les sauvegardes. Les petits écarts d'arrondi
entre tailles de lots peuvent faire diverger les trajectoires d'apprentissage.

Pour comparer ensuite la collecte avec le masque direct et l'encodage terminal
évité dans PPO, utiliser la commande suivante. `--ablation` mesure chaque
changement séparément, puis les deux ensemble, dans les deux ordres.

```powershell
.\.venv311\Scripts\python.exe -u scripts\benchmark_champion_batch.py `
  --checkpoint runs\ppo_self_play_v2\latest.pt `
  --comparison rollout --ablation `
  --output artifacts\phase5_rollout_optimizations.json
```

Les appels publics à `BatchSamStoneEnv.step()` produisent l'observation finale.
La collecte PPO demande `encode_terminal=False`, enregistre récompenses et
résultat, puis réinitialise chaque partie terminée avant la prochaine décision.
Le masque adverse direct conserve la convention du premier emplacement pour
une carte répétée dans la main.

Le champion utilise aussi le moteur tactique vectorisé pendant la collecte
Python. Pour mesurer le gain avec les mêmes poids et la même configuration,
comparer le calcul tactique individuel et groupé avec cette commande.

```powershell
.\.venv311\Scripts\python.exe -u scripts\benchmark_champion_batch.py `
  --checkpoint runs\ppo_self_play_v2\latest.pt `
  --comparison tactics `
  --output artifacts\phase5_champion_tactics.json
```

Dans un autre terminal, depuis `rl/` :

```powershell
.\.venv311\Scripts\python.exe -m tensorboard.main `
  --logdir runs\ppo_self_play_v2\tensorboard --port 6006
```

Pour le suivi de l'état, dans un autre terminal :

```powershell
.\.venv311\Scripts\python.exe scripts\monitor_training.py runs\ppo_self_play_v2 --follow
```

TensorBoard : `http://localhost:6006`. Les séries utiles sont
`evaluation/score`, `phase5_curriculum/promotions`,
`phase5_curriculum/updates_since_promotion` et
`phase5_promotion/minimum_confirmation_score_lower`.
`phase5_status.json` distingue `training`, `evaluating`, `completed`, `plateau`
et `budget_exhausted`, avec la sous-étape et la progression des matchs.

Les champions sont sous `league/champion_*.pt`, les candidats et rapports sous
`evaluations/phase5/candidates/`, et les résultats compacts dans les registres
SQLite de `evaluations/phase5/`. Le cache des modèles CPU est borné. Le rapport
certifié identifie les politiques de référence et les registres utilisés.

La validation finale est automatique. Pour inspecter ensuite le certificat :

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase5.py `
  runs\ppo_self_play_v2\latest.pt --config configs\ppo_self_play_v2.yaml
```

Cette commande vérifie le certificat existant ; elle ne lance pas un autre
apprentissage ni l'ancien tournoi manuel.

## Decks après phase 5

Après certification de phase 5, lancer la recherche pour les six dieux :

```powershell
foreach ($god in @("veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma")) {
  .\.venv311\Scripts\python.exe scripts\run_deck_evolution.py $god `
    runs\ppo_self_play_v2\phase5_validated.pt --config configs\deck_evolution.yaml
  if ($LASTEXITCODE -ne 0) { throw "Recherche interrompue pour $god" }
}
.\.venv311\Scripts\python.exe scripts\validate_phase6.py runs\deck_evolution
.\.venv311\Scripts\python.exe scripts\build_boss_roster.py `
  runs\deck_evolution runs\ppo_self_play_v2\phase5_validated.pt
```

Le mode `--pilot` est réservé aux essais techniques et produit des rapports
non officiels. La reprise d'évolution exige le même moteur, catalogue,
configuration et checkpoint. Les registres et états antérieurs aux nouveaux
contrats doivent être régénérés.

## Spécialiser et exporter

Exemple pour Veskar, à répéter pour les six dieux :

```powershell
.\.venv311\Scripts\python.exe scripts\train_boss.py veskar `
  --universal runs\ppo_self_play_v2\phase5_validated.pt
.\.venv311\Scripts\python.exe scripts\validate_boss.py veskar `
  runs\boss_specialists\veskar\best.pt
.\.venv311\Scripts\python.exe scripts\validate_boss_roster.py
.\.venv311\Scripts\python.exe scripts\export_policy.py `
  runs\boss_specialists\veskar\boss_veskar_validated.pt `
  --output artifacts\bosses\veskar.sspolicy
```

L'export normal exige une certification du boss compatible avec le code actuel.
`--allow-unvalidated` produit une fixture de diagnostic, refusée par l'IA du jeu.
Le format contient métadonnées, poids float32 et empreintes d'intégrité.

Après sélection des artefacts, les copier dans les ressources du jeu et activer
explicitement le boss avec `AITurnRunner.create_neural_ai(policy_path)`.
Le dieu, le deck et les règles doivent correspondre au modèle. L'extension
éditeur embarque l'identité des règles dans les exports Godot avant la
compilation des scripts. Mesurer la latence et la mémoire sur le téléphone cible
avant de livrer les six boss.

En cas d'artefact incompatible, l'IA utilise le profil existant de précision
maximale avec anticipation pour que la partie puisse continuer. Le diagnostic
de chargement reste visible dans Godot.

## Benchmarks des optimisations

Pour mesurer les optimisations CPU et la collecte, depuis `rl/` :

```powershell
.\.venv311\Scripts\python.exe scripts\benchmark_fast_training.py `
  --config configs\ppo_phase4_vectorized.yaml --device directml `
  --num-envs 256 --batch-size 2048 --epochs 1 --stage precision_100_anticipation `
  --warmup 3 --updates 20 --tactical-workers 2 --output artifacts\benchmark.json
.\.venv311\Scripts\python.exe scripts\benchmark_tactical.py `
  --iterations 20 --workers 1 2 4 --output artifacts\tactical-profile.json
```

`--warmup` exclut les premières mises à jour des mesures. Le JSON conserve la
configuration et les mesures individuelles. Le profil tactique couvre les six
dieux en début, milieu et fin de partie, et vérifie l'égalité des résultats
pour chaque nombre de workers. Ne pas exécuter deux benchmarks simultanément.

Pour activer les workers dans un **nouveau run**, ajouter
`tactical_workers: 2` sous `environment` dans son YAML. Le défaut est 1 ; les
petits lots restent séquentiels. Les workers réutilisent leurs propres buffers,
ce qui augmente la mémoire utilisée. Comparer les résultats sur le poste cible.
Les temps tactiques détaillés des workers sont cumulés ; le débit global et le
temps par mise à jour mesurent le temps réellement écoulé.

Changer le nombre d'environnements à batch constant change la longueur des
rollouts et peut affecter l'apprentissage. Un benchmark de vitesse seul ne
justifie pas ce changement dans une campagne existante.

## Plages d'évaluation

Les seeds de collecte restent inférieurs à `2**31`. Les configurations v2
réservent des espaces différents aux phases et aux validations :

| Usage | Base |
| --- | ---: |
| Phase 4, confirmations / ancrages / pré-évaluation / finale | 4,1 / 4,2 / 4,5 / 4,9 milliards |
| Phase 5, base champion/candidat | 6 × 10¹² |
| Phase 6, sélection courte / moyenne / finale | 6,1 / 6,2 / 6,9 milliards |
| Spécialisation, suivi / universelle / finale | 7,1 / 7,2 / 7,9 milliards |
| Comparaisons / ablations | 8,1 / 8,2 milliards |

La phase 5 ajoute à sa base un domaine par type d'évaluation (pas de 10¹⁰),
une tentative (pas de 10⁶) et une ronde (pas de 10⁴). Les deux rôles d'une paire
et les modèles de référence comparés utilisent volontairement la même seed.

Les seeds communs entre candidats d'une même comparaison sont intentionnels :
ils permettent une mesure appariée. Les parties finales ne servent pas à choisir
les hyperparamètres.

## Diagnostic des refus

- **Run déjà initialisé** : reprendre son `latest.pt` ou choisir un dossier neuf.
- **Run utilisé** : arrêter l'autre entraîneur ou évaluateur qui possède son verrou.
- **Provenance incompatible** : importer les poids dans une nouvelle expérience.
- **Seul le code Python diffère** : après vérification des modifications (par
  exemple une option d'affichage), reprendre avec `--resume ... --allow-python-source-change`.
  Cette autorisation conserve le curriculum, Adam et les compteurs ; elle est
  enregistrée dans le manifeste et ne permet pas de changer les règles, le contenu,
  les schémas, le modèle, les récompenses ou le moteur Godot.
- **Certification absente ou périmée** : réévaluer le checkpoint exact avec le jeu actuel.
- **Checksum invalide** : restaurer une copie saine ; le journal récupère uniquement
  une transaction interrompue dont il reconnaît les octets.
- **Godot indisponible** : vérifier `GODOT_BIN`, sa version et le chemin vers
  l'exécutable principal `Godot_*_win64.exe` pour un lancement direct.
- **Évaluation initiale figée sur `completed_games: 0` avec DirectML** : les
  premières copies CPU → GPU pouvaient se bloquer dans les threads d'évaluation.
  Le trainer initialise désormais une inférence déterministe dans le thread
  principal avant de lancer les matchs en parallèle. Arrêter l'ancien processus
  puis relancer avec le code corrigé ; le choix du lanceur console Godot ne
  corrige pas ce blocage.
- **Conflit de dépendances** : recréer un venv depuis le verrou correspondant au périphérique.

Les messages Windows sur le magasin de certificats racine sont distingués des
états et erreurs du jeu dans les diagnostics de qualité Godot.
