# Plan de développement — SamStone RL

Ce document est la feuille de route de référence du trainer. Une phase n'est
terminée que lorsque ses critères de validation sont automatisés et passent de
manière reproductible.

## 1. Résultat attendu

Le projet doit livrer six boss, un pour chacun des dieux de SamStone :

| Boss | Identifiant moteur |
| --- | --- |
| Véskar | `inari` |
| Nérava | `izanami` |
| Kharûn | `hachiman` |
| Ilyr | `tsukuyomi` |
| Sylkha | `okuninushi` |
| Énigma | `susanoo` |

Chaque boss est un couple `(politique, deck)` évalué contre une ligue diverse.
Les modèles et leurs decks seront embarqués dans l'APK et fonctionneront hors
ligne. Le même système produira des données d'équilibrage contrôlées.

## 2. Principes non négociables

1. **Une seule source de règles** : aucune mécanique de combat n'est recodée en
   Python. Le simulateur appelle le moteur Godot.
2. **Parité avant performance** : un simulateur rapide mais divergent est
   inutilisable.
3. **Information réaliste** : la main adverse et le futur aléatoire restent
   masqués.
4. **Déterminisme** : seed, decks, terrain et politiques identiques donnent la
   même trace.
5. **Évaluation séparée** : les seeds et adversaires d'évaluation ne servent pas
   à l'optimisation.
6. **Victoire avant captures** : l'objectif terminal domine toute récompense
   intermédiaire.
7. **Mesures avant optimisation** : aucune promesse de débit ou de latence sans
   benchmark reproductible.
8. **Déploiement simple** : poids compacts exécutés par Godot ; pas de dépendance
   ONNX, Python ou réseau dans l'APK.

## 3. Architecture cible

```text
StoneCardGame/
├── game/
│   ├── project.godot
│   ├── assets/
│   ├── data/
│   ├── scenes/
│   ├── scripts/
│   ├── tests/
│   └── tools/rl_sim/
│       ├── HeadlessSim.tscn
│       ├── HeadlessRunner.gd
│       ├── MatchSimulator.gd
│       └── StateSerializer.gd
└── rl/
    ├── configs/
    ├── scripts/
    ├── src/samstone_rl/
    │   ├── bridge/
    │   ├── envs/
    │   ├── models/
    │   ├── opponents/
    │   ├── training/
    │   └── utils/
    └── tests/
```

`game/tools/rl_sim/` est une couche d'intégration, pas un second moteur. Les
récompenses, rollouts et algorithmes d'apprentissage appartiennent à `rl/`.

## 4. Phase 0 — fondations du monorepo

**Statut : en cours.**

### Travaux

- [x] Séparer `game/` et `rl/`.
- [x] Conserver l'adaptateur GDScript sous le `res://` du jeu.
- [x] Déplacer le code Python dans un package `src/samstone_rl`.
- [x] Déclarer le package avec `pyproject.toml`.
- [x] Corriger les règles Git qui ignoraient le code source `env/`.
- [x] Ignorer tous les environnements virtuels et artefacts locaux.
- [x] Documenter l'intégration finale sans ONNX.
- [ ] Recréer un seul environnement Python 3.11 dans `rl/.venv`.
- [ ] Verrouiller un ensemble de dépendances testé sur une installation neuve.
- [ ] Ajouter `pytest`, le lint et la vérification de types minimale.
- [x] Supprimer les chemins absolus et utiliser `GODOT_BIN`/CLI/`PATH`.
- [ ] Ajouter une commande de diagnostic CPU et DirectML.

### Critères de validation

- Un clone neuf installe le trainer avec une commande documentée.
- Aucun cache, environnement virtuel ou run n'apparaît dans Git.
- Le projet Godot s'ouvre et ses tests se lancent depuis `game/`.
- Les imports Python fonctionnent après `python -m pip install -e .`.

## 5. Phase 1 — simulateur Godot synchrone et fidèle

**Statut : prototype à remplacer.**

### 5.1 Moteur de match headless

Créer `MatchSimulator.gd`, sans `TurnManager` ni attente de frame. Un appel à
`step` doit effectuer atomiquement :

```text
validation PlacementRules
→ CombatResolver.apply_move
→ RulesEngine.calculate_score
→ détection de fin
→ changement de joueur si nécessaire
```

Le résultat brut contient les captures retournées par `CombatResolver`, pas une
différence de score qui compterait aussi la pierre posée.

### 5.2 Reset déterministe

`reset(config)` doit :

- exiger un seed entier ;
- valider les deux dieux et les deux decks ;
- produire ou accepter les cases bloquées ;
- produire ou accepter le premier joueur ;
- initialiser le générateur propre à `GameState` ;
- refuser clairement toute configuration invalide.

La distribution du jeu est conservée : 0, 1 ou 2 cases bloquées avec les mêmes
probabilités et un premier joueur équilibré.

### 5.3 API primitive

Le serveur expose :

- `ping` ;
- `reset` ;
- `legal_actions` pour le joueur courant ;
- `step` pour appliquer exactement un coup ;
- `get_state` pour le diagnostic ;
- `shutdown`.

Le wrapper Gym gérera les réponses de l'adversaire. Cette primitive permettra
aussi le self-play où Python contrôle les deux camps.

### 5.4 Observation publique

`StateSerializer.serialize_for_player(state, observer)` doit fonctionner pour
les deux joueurs. Il expose la propre main, la taille de la main adverse et
toutes les informations publiques du plateau, sans RNG caché ni cartes adverses.

### 5.5 Tests de parité

- Parties scriptées comparées tour par tour au vrai moteur.
- Toutes les familles et tous les effets couverts.
- Cas de hasard répétés avec les mêmes seeds.
- États comparés après chaque coup, pas seulement au score final.

### Critères de validation

- 10 000 parties aléatoires terminent sans blocage ni action invalide.
- Un même seed produit la même trace JSON complète.
- Toute action annoncée légale est acceptée.
- Toute action illégale est refusée sans mutation de l'état.
- Le score total correspond toujours au nombre de pierres posées.
- Zéro divergence avec le moteur utilisé par le jeu sur le corpus de parité.

## 6. Phase 2 — pont Python/Godot robuste

**Statut : prototype à remplacer.**

### Travaux

- Lancer `game/project.godot` depuis un chemin configurable.
- Remplacer les `sleep` et `readline` bloquants par une lecture asynchrone avec
  timeout.
- Séparer stdout protocolaire et stderr de diagnostic.
- Préfixer les réponses, par exemple `RL_JSON:`, pour ignorer les logs Godot.
- Vérifier l'identifiant de chaque requête.
- Détecter les processus morts et conserver les dernières lignes d'erreur.
- Ajouter un contexte `with GodotProcess(...)` et une fermeture gracieuse.
- Garantir `terminate`, puis `kill` en dernier recours.
- Préparer `batch_reset` et `batch_step` pour plusieurs matchs par processus.

### Tests

- Protocole JSON valide et invalide.
- Logs parasites avant et entre les réponses.
- Timeout de démarrage et de commande.
- Crash du processus.
- Fermeture normale et forcée.
- Cent cycles de démarrage/arrêt sans processus orphelin.
- Plusieurs parties complètes via le pont.

### Critères de validation

- Aucune opération réseau local ne peut attendre sans limite.
- Une erreur contient la commande, l'identifiant et le diagnostic Godot utile.
- Le test d'intégration termine une partie et libère toujours le processus.

## 7. Phase 3 — environnement Gymnasium

**Statut : prototype à remplacer.**

### 7.1 Observation canonique

Structurer l'observation avant de l'aplatir :

```text
board  : [16, F_case]
hand   : [8, F_carte]
global : [F_partie]
mask   : [128]
```

Une pierre posée doit encoder au minimum son propriétaire relatif, son auteur,
ses quatre faces, lames normales/aléatoires/longues/Essaim, boucliers,
faiblesses, effets, affinité et données publiques nécessaires aux transitions.

Chaque emplacement de la main encode la carte et ses mécaniques. Deux cartes
tactiquement différentes ne doivent jamais produire la même observation.

Le point de vue est canonique : `moi`, `adversaire`, `vide`. Le même modèle peut
ainsi jouer depuis les deux camps. Le schéma reçoit un numéro de version stable.

### 7.2 Espace d'actions

Conserver `8 × 16 = 128` actions : emplacement de main puis case. Le masque est
un tableau booléen. Une action illégale déclenche une erreur en développement ;
elle n'est jamais remplacée silencieusement par une autre.

### 7.3 Cycle Gym

`reset` fait jouer l'adversaire s'il commence, puis renvoie une décision de
l'agent. `step` applique le coup de l'agent, laisse l'adversaire répondre jusqu'à
la prochaine décision de l'agent ou la fin, puis renvoie la transition.

Les adversaires utilisent une interface commune :

- aléatoire ;
- IA actuelle de Godot ;
- checkpoint RL, à partir de la phase 5.

### 7.4 Récompense

La référence initiale est : victoire `+1`, défaite `-1`, égalité `0`. Captures,
marge et effets sont des métriques. Un shaping éventuel doit être faible,
documenté et fondé sur un potentiel de différence de score afin de ne pas rendre
une défaite riche en captures préférable à une victoire.

### Critères de validation

- `gymnasium.utils.env_checker.check_env` passe.
- Toutes les observations appartiennent à leur espace déclaré.
- Le masque correspond exactement aux actions Godot.
- Aucun contenu de main adverse ou futur RNG n'est présent.
- Les deux camps, premiers joueurs et terrains sont couverts.
- Seeds identiques : épisodes identiques.

## 8. Phase 4 — PPO et preuve d'apprentissage

**Statut : prototype à remplacer.**

Cette phase démontre que la chaîne apprend ; elle ne cherche pas encore le boss
final.

### 8.1 Modèle initial

Utiliser un MLP acteur-critique compact : encodeur partagé, 128 logits d'action
et une valeur scalaire. Le masque booléen est appliqué aux logits avant la
distribution catégorielle. CPU d'abord ; DirectML seulement après validation.

### 8.2 PPO correct

La mise à jour doit recalculer `new_log_prob`, utiliser
`exp(new_log_prob - old_log_prob)`, l'entropie réelle, le clipping PPO, GAE et le
bootstrap correct aux frontières d'épisode. Actions et masques sont stockés en
`long` et `bool`.

Tester explicitement que :

- les paramètres de la tête acteur reçoivent un gradient ;
- les poids changent après une optimisation ;
- le ratio n'est pas constamment égal à 1 ;
- aucune probabilité n'est attribuée à une action masquée.

### 8.3 Progression contrôlée

1. Sur-apprendre un scénario minuscule déterministe.
2. Apprendre contre un adversaire aléatoire avec un deck fixe.
3. Généraliser sur des seeds réservés.
4. Alterner camp, premier joueur et terrains.
5. Étendre aux six dieux et à plusieurs decks fixes.
6. Affronter l'IA actuelle du jeu.

### 8.4 Batching et reproductibilité

Utiliser plusieurs environnements ou plusieurs matchs batchés. Chaque
environnement reçoit un seed dérivé et enregistré. Un run conserve configuration,
version du code, versions des dépendances et checkpoints `latest`/`best`.

### 8.5 Mesures

Journaliser retours, victoire/égalité/défaite, marge, durée, captures, actions
invalides, entropie, KL approximative, clip fraction, variance expliquée,
étapes/seconde et parties/seconde.

### Critères de validation

- Le scénario jouet est résolu de manière reproductible.
- La politique progresse significativement contre l'aléatoire sur des seeds
  qu'elle n'a jamais vus.
- Le résultat est mesuré depuis les deux camps avec intervalle de confiance.
- Un checkpoint rechargé reproduit ses décisions déterministes.
- Aucune action illégale n'est émise.
- Une évaluation séparée contre l'IA actuelle est disponible.

## 9. Phase 5 — self-play et ligue

- Politique universelle conditionnée par le dieu, le deck et l'état public.
- Mélange d'adversaires `current`, récents, historiques et exploitants.
- Échantillonnage équilibré des dieux, camps, terrains et seeds.
- Elo et matrice de matchups calculés sur un tournoi séparé.
- Prévention de l'oubli catastrophique par conservation d'une ligue historique.

Critère principal : aucune ancienne politique importante ni stratégie simple ne
doit devenir un contre stable sans être réintroduite dans la ligue.

## 10. Phase 6 — évolution des decks

La recherche de deck est une boucle extérieure, séparée de PPO : génération de
decks légaux, tournois courts, sélection, mutation et réévaluation. Les
contraintes viennent des règles Godot : huit cartes, budget, lignées uniques,
niveaux existants et compatibilité avec le dieu.

La politique et les decks sont améliorés en alternance. Les six meilleurs
couples `(politique, deck)` sont ensuite fine-tunés et soumis à un tournoi final.

## 11. Phase 7 — intégration locale dans Godot

- Exporter poids `float32`, dimensions, normalisations et manifeste versionné.
- Ajouter l'encodeur, le codec d'actions et l'inférence dans Godot.
- Intégrer les six configurations de boss à l'APK.
- Vérifier des fixtures `observation → logits → action` entre PyTorch et Godot.
- Mesurer latence et mémoire sur un vrai appareil Android.
- Ajouter éventuellement une recherche limitée aux meilleurs coups proposés par
  le réseau si elle améliore nettement la force du boss.

ONNX n'est envisagé de nouveau que si une mesure sur appareil prouve que
l'inférence Godot est insuffisante.

## 12. Phase 8 — rapports d'équilibrage

Conserver pour chaque match : seed, versions, dieux, decks, premier joueur,
terrain, résultat, marge, actions, cartes, positions, captures et effets. Les
rapports comparent cartes et dieux à contexte égal et distinguent force du deck,
force de la politique et avantage structurel du matchup.

## 13. Ordre de livraison

```text
Phase 0 validée
→ simulateur et parité
→ pont fiable
→ environnement validé
→ preuve PPO
→ self-play
→ decks
→ six boss intégrés
→ rapports d'équilibrage
```

Aucune phase ne doit être accélérée en lançant un entraînement coûteux avant la
validation de la phase précédente.
