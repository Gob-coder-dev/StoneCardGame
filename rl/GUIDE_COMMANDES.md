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

Une reprise peut prolonger `ppo.total_timesteps`, ajuster le suivi, changer de
périphérique ou déplacer l’exécutable Godot compatible. Ces changements sont
historisés dans le manifeste. Le taux d’apprentissage ne peut changer qu’avec
`--reset-optimizer`. Les paramètres qui définissent l’expérience, comme les
récompenses, `gamma`, les scénarios et le curriculum, exigent un nouveau run.

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

## Valider la phase 4

Arrêter l'entraîneur avant d'utiliser le même dossier pour la certification.
Le dernier palier doit être maîtrisé et attendre sa validation finale.

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase4.py `
  runs\ppo_phase4_aligned_v3\best.pt --config configs\ppo_phase4_vectorized.yaml
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

## Self-play et decks

```powershell
.\.venv311\Scripts\python.exe -m samstone_rl.training.ppo_self_play `
  --config configs\ppo_self_play_v2.yaml `
  --phase4 runs\ppo_phase4_aligned_v3\phase4_validated.pt
```

Reprise de phase 5 : remplacer `--phase4 ...` par
`--resume runs\ppo_self_play_v2\latest.pt`.

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase5.py `
  runs\ppo_self_play_v2\best.pt --config configs\ppo_self_play_v2.yaml
```

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
| Phase 5, confirmations / tournoi mixte de suivi | 5,1 / 5,2 milliards |
| Phase 5, finales Godot / mixtes | 5,8 / 5,9 milliards |
| Phase 6, sélection courte / moyenne / finale | 6,1 / 6,2 / 6,9 milliards |
| Spécialisation, suivi / universelle / finale | 7,1 / 7,2 / 7,9 milliards |
| Comparaisons / ablations | 8,1 / 8,2 milliards |

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
