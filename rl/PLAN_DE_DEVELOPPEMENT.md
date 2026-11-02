# Plan de développement — SamStone RL

Ce document décrit l'architecture cible et les conditions de passage entre les
phases. L'historique des prototypes a été retiré : seule l'implémentation
actuelle fait référence.

## 1. Résultat attendu

Le projet doit produire six boss, un par dieu, composés d'une politique et d'un
deck optimisé. Ils seront intégrés dans Godot, embarqués dans l'APK et
fonctionneront hors ligne. Les mêmes simulations fourniront des statistiques
sur les cartes, dieux, terrains, matchups et ordres de départ.

Une invincibilité absolue n'est pas une cible vérifiable dans un jeu contenant
du hasard et de l'information cachée. La cible est une robustesse statistique
sur une ligue diverse et des seeds jamais utilisés pour l'optimisation.

## 2. Principes non négociables

1. **Godot est canonique** : les promotions et validations utilisent le moteur
   réel du jeu.
2. **Le moteur Python est contrôlé** : il accélère la collecte, sans décider de
   la qualité finale d'un checkpoint.
3. **Aucune information cachée** : la politique et les bots d'entraînement ne
   consultent jamais la véritable main adverse.
4. **Victoire avant captures** : la récompense terminale domine le shaping.
5. **Évaluation séparée** : seeds et matchs d'évaluation ne sont pas réutilisés
   pour apprendre.
6. **Reproductibilité** : configuration, checksums, RNG, curriculum et état
   Adam sont sauvegardés.
7. **Mesures avant optimisation** : toute modification de performance possède
   un benchmark reproductible.
8. **Déploiement local** : les poids sont exécutés par Godot, sans Python,
   ONNX, serveur ou connexion dans l'APK.

## 3. Architecture de référence

```text
Expérience rapide                        Validation canonique
┌──────────────────────┐                ┌──────────────────────┐
│ 64 états batch       │                │ 10 processus Godot   │
│ encodage direct      │                │ seeds réservés       │
└──────────┬───────────┘                └──────────┬───────────┘
           │ observations/actions                  │ résultats
           └──────────────┬────────────────────────┘
                          ▼
                ┌──────────────────┐
                │ Gym + PPO        │
                │ curriculum       │
                │ checkpoints      │
                └────────┬─────────┘
                         ▼
                TensorBoard / JSONL
```

Une unique boucle PPO gère toutes les largeurs de collecte. `python_batch`
apprend à partir des mêmes règles que `python`, mais encode directement les
états dans les tenseurs PPO sans reconstruire les dictionnaires du bridge.
Godot reste le backend d'évaluation. L'observation, le codec d'actions, la
récompense et les checkpoints restent communs.

Configuration officielle : `configs/ppo_phase4_tactical.yaml`.

## 4. État des phases

### Phase 0 — monorepo et outillage

**Statut : implémentée.**

- projets `game/` et `rl/` séparés ;
- package Python sous `src/` ;
- Python 3.11 et dépendances déclarées ;
- chemins portables via `GODOT_BIN` ;
- artefacts locaux exclus de Git ;
- lint et tests automatisés.

### Phase 1 — simulateur Godot synchrone

**Statut : implémentée.**

- reset déterministe ;
- observation publique pour les deux camps ;
- actions légales et application atomique d'un placement ;
- captures issues directement du moteur de combat ;
- score, fin de partie et changement de joueur synchrones.

Garde restante avant publication : campagne longue de 10 000 parties et corpus
élargi pour toutes les combinaisons d'effets aléatoires.

### Phase 2 — pont Python/Godot

**Statut : implémentée.**

- socket TCP locale avec timeouts ;
- diagnostics séparés du protocole ;
- fermeture gracieuse et détection des processus morts ;
- pool multi-processus pour évaluations et recherche de decks ;
- manifeste et checksum du catalogue.

### Phase 3 — environnement Gymnasium

**Statut : implémentée.**

- observation canonique de taille stable ;
- 128 actions masquées ;
- alternance agent/adversaire dans une transition Gym ;
- deux camps, ordres de départ et terrains ;
- récompense symétrique : victoire/défaite `±2`, marge finale bornée et petite
  variation du contrôle durable du plateau après la réponse adverse ;
- captures immédiates non récompensées dans la configuration de production.

### Phase 4 — PPO et curriculum

**Statut : implémentée, entraînement long en cours.**

- acteur-critique tactique masqué : une tête partagée compare chaque coup légal
  à partir de la carte, de la case, des captures et de la menace de riposte ;
- PPO, GAE, clipping, entropie et bootstrap ;
- batch fixe de 2 048 transitions ;
- 64 environnements `python_batch` pour l'expérience ;
- évaluation uniforme sur 500 matchs avec dix processus Godot ;
- curriculum unique `0 → 0,25 → 0,5 → 1` sans anticipation, puis
  `anticipation 25 % → 50 % → 75 % → 100 %` ;
- tirage d'anticipation par décision, reproductible par seed ;
- import `--weights-only` pour changer de curriculum sans hériter de son état ;
- exposition adaptative aux dieux et terrains faibles ;
- replay de 20 % des anciens paliers ;
- checkpoints atomiques `latest`, `best` et snapshots.

Promotion d'un palier :

- `win_rate >= 0,85` ;
- `loss_rate <= 0,07` pour les paliers intermédiaires ;
- `non_loss_wilson_lower >= 0,90`.
- deux évaluations consécutives de 500 parties conformes avant promotion.

La garde finale couvre les huit paliers, six dieux, deux camps et deux ordres de
départ. Seul son checkpoint `phase4_validated.pt` peut activer la phase 5.

#### Historique de validation tactique

Une expérience isolée a testé une politique conditionnée par action avant son
adoption dans le PPO de production. Le réseau conserve une tête résiduelle identique à la
politique 512 importée et ajoute un scorer partagé recevant, pour chaque coup
légal, la carte, la case, la capture immédiate et la menace de riposte.

- diagnostic décision par décision exporté en JSON et CSV ;
- calcul déterministe sans consommation du hasard réel ni main cachée ;
- ancien checkpoint préservé exactement au moment de l'import ;
- passages intermédiaires officiels : 85 % de victoires, 7 % de défaites
  maximum, Wilson des non-défaites à 90 % et deux confirmations ;
- comparaison obligatoire sur 2 880 mêmes seeds avant adoption ;
- backend Python pendant le pilote, schéma également exposé et testé dans Godot,
  puis validation Godot complète seulement si l'amélioration est démontrée.

Le calcul complet est dorénavant le chemin principal du boss, puis sera mesuré
sur l'APK avant l'export final.

### Phase 5 — self-play et ligue

**Statut : code d'entraînement et de validation implémenté ; campagne non lancée.**

- checkpoints adverses figés pendant une partie ;
- catégories courant, récent, historique et meilleur ;
- ancrage Godot toujours présent ;
- transition progressive jusqu'à 75 % de self-play ;
- classement et historique persistants.
- matchs entre les six dieux et leurs presets (90 % de duels croisés, 10 % de
  miroirs dans la configuration actuelle) ;
- boucle PPO dédiée avec reprise, snapshots et métriques de matchup ;
- évaluation périodique sur 144 matchs mixtes contre la politique validée de
  phase 4, en plus des 500 parties contre le dernier bot Godot.

La garde finale utilise des seeds non employés pendant l'entraînement ni les
évaluations périodiques. Elle compare candidat et politique de phase 4 contre
les cinq profils Godot, sur les mêmes scénarios : 5 × 6 × 2 camps × 2 ordres ×
12 seeds × 2 politiques = 2 880 matchs. Elle joue aussi 6 × 6 × 2 × 2 × 12 =
1 728 duels contre le checkpoint figé de phase 4. Total : 4 608 matchs.
Critères configurables dans `ppo_self_play_v2.yaml` : 500 mises à jour minimum,
régression maximale de 5 points par palier Godot et 8 points par dieu, score
global d'au moins 52 % contre la politique de phase 4, borne Wilson de victoire
d'au moins 49 %, score d'au moins 45 % par dieu et 30 % par matchup. Le seul
checkpoint officiel pour la phase 6 est `phase5_validated.pt`.

Travaux pendant la campagne de phase 5 :

1. suivre les matchups et les cinq ancrages Godot ;
2. lancer la garde finale sur le meilleur checkpoint ;
3. retenir une politique universelle validée ;
4. décider si un fine-tuning par dieu apporte un gain réel.

### Phase 6 — optimisation des decks

**Statut : infrastructure implémentée, campagne longue non exécutée.**

- catalogue extrait de Godot ;
- génération, croisement et mutation de decks légaux ;
- évaluation sur seeds communs, deux camps et deux ordres ;
- cache SQLite et reprise après interruption ;
- rapports d'équilibrage ;
- garde finale indépendante de la population d'entraînement.

Le réseau reste figé pendant l'évaluation d'une population. Un gain de deck ne
doit jamais être confondu avec un gain de politique.

### Phase 6B — spécialisation des six boss

**Statut : entraînement, gardes et statistiques implémentés ; campagne non exécutée.**

- registre immuable construit depuis les six rapports officiels de phase 6 ;
- un run indépendant par dieu, initialisé avec `phase5_validated.pt` ;
- dieu et deck final fixes pour l'agent, adversaires répartis sur les six decks ;
- ligue persistante de checkpoints courant, récents, historiques et meilleur ;
- ancrage continu contre les profils Godot ;
- comparaison périodique contre la politique universelle sur seeds fixes ;
- reprise exacte, checkpoints atomiques et TensorBoard par dieu ;
- garde finale exigeant gain global, robustesse par matchup et absence de
  régression importante contre Godot ;
- garde globale des six poids et classement descriptif des boss.

Cette phase ne remplace pas la politique universelle : elle produit six copies
spécialisées. Un checkpoint n'est officiel qu'après `validate_boss.py`, et le
lot n'est exportable qu'après `validate_boss_roster.py`.

### Phase 7 — intégration dans Godot

**Statut : à réaliser après sélection des politiques et decks.**

- définir le format compact des poids `float32` ;
- implémenter l'inférence du MLP dans Godot ;
- partager le schéma d'observation et le codec d'actions ;
- comparer logits et actions sur des fixtures PyTorch/Godot ;
- mesurer mémoire et latence sur téléphone réel ;
- embarquer six couples `(poids, deck)` dans l'APK.

### Phase 8 — observabilité et équilibrage

**Statut : implémentée.**

- métriques JSONL versionnées ;
- TensorBoard ;
- alertes KL, clipping, entropie, variance et régression ;
- rapports HTML ;
- statistiques par dieu, camp, terrain et ordre de départ ;
- débit décisions/s et parties/s ;
- télémétrie de la recherche de decks.
- classement des dieux sur échantillons communs ;
- taux de sélection des cartes dans les populations et top decks ;
- taux d'utilisation lorsqu'une carte est réellement disponible en main ;
- détection des cartes jamais sélectionnées grâce au snapshot du catalogue ;
- ablations appariées sur les mêmes seeds pour tester les remplacements de
  cartes sans confondre chance, camp, terrain ou adversaire.

## 5. Parité du moteur rapide

Le moteur Python implémente placements, lames normales et longues, boucliers,
lames aléatoires, pile ou face, Miasme, Corrosion, vol de boucliers et Essaim.

Validation obligatoire :

- observation identique après chaque coup déterministe ;
- mêmes actions légales et captures ;
- mêmes invariants de score et de fin ;
- parité batch/scalar sur les six dieux, les deux camps et tous les profils ;
- aucun contenu de main adverse dans l'anticipation ;
- évaluation officielle exclusivement dans Godot.

La mise en production de `python_batch` a également exigé une suite complète
de tests Python, 22 tests avec le véritable exécutable Godot, des benchmarks à
32/64/128 environnements et un test d'endurance de 1 024 000 transitions PPO.

Python et Godot n'utilisent pas le même générateur pseudo-aléatoire. Les tirages
ne sont donc pas identiques seed par seed, mais doivent suivre les mêmes lois.
Cette différence ne peut pas promouvoir un modèle, puisque Godot reste l'oracle.

Référence de performance actuelle : environ 388 parties/s et 2 914 décisions/s
sur 1 024 000 transitions PPO. À lot identique, `python_batch` est environ
1,9 fois plus rapide que `python`. La largeur 64 est retenue : 128 états
n'apportent pratiquement aucun gain supplémentaire sur la machine de référence.

Le palier `precision_100_anticipation` utilise un cache comportemental à deux
niveaux : enveloppes offensives immuables de chaque variante, puis profil de
riposte public indexé par dieu et lignées déjà posées. Le plateau reste évalué
pour chaque simulation et aucune carte cachée n'entre dans la clé. Cette
optimisation conserve exactement les valeurs et choix du bot tout en faisant
passer le benchmark avec anticipation de 6,74 à 26,56 parties/s (×3,9).

## 6. Procédure de validation

Avant un entraînement long :

```powershell
.\.venv311\Scripts\python.exe -m ruff check .
.\.venv311\Scripts\python.exe -m pytest tests -q
.\.venv311\Scripts\python.exe scripts\benchmark_fast_training.py `
  --config configs\ppo_phase4_tactical.yaml --updates 12 --num-envs 64 `
  --backend python_batch
```

Avant la phase 5 :

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase4.py `
  runs\ppo_phase4_tactical\best.pt `
  --config configs\ppo_phase4_tactical.yaml
```

Avant de retenir un deck :

```powershell
.\.venv311\Scripts\python.exe scripts\validate_phase5.py `
  runs\ppo_self_play_v2\best.pt --config configs\ppo_self_play_v2.yaml
.\.venv311\Scripts\python.exe scripts\validate_phase6.py runs\deck_evolution\reports
```

Avant l'APK : parité des logits, tests sur appareil, mesure de latence et test
hors ligne complet.

## 7. Règles de maintenance

- Une seule configuration officielle par workflow.
- Aucun nouveau backend sans test différentiel.
- Aucun seuil de promotion dans le code : tous restent configurables.
- Aucun chemin absolu dans les fichiers versionnés.
- Aucun checkpoint ou run supprimé automatiquement.
- Une fonctionnalité expérimentale vit dans une branche ou derrière une option,
  pas dans une seconde boucle d'entraînement copiée.
- Toute nouvelle métrique possède un nom stable et une définition documentée.
