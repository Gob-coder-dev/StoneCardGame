# SamStone RL

Projet Python d'entraînement des intelligences artificielles « Boss » de
SamStone. Il partage le dépôt avec le jeu, mais reste un projet autonome avec
ses propres dépendances, tests, configurations et artefacts.

> **État actuel : reconstruction.** Le code présent vient d'un premier
> prototype qui contient des erreurs connues. Il ne faut pas lancer
> d'entraînement long avant la validation des phases 0 à 4.

## Objectifs

Le projet poursuit deux objectifs complémentaires :

1. entraîner six boss extrêmement forts, un par dieu, avec une stratégie et un
   deck optimisés ;
2. produire des statistiques d'équilibrage sur les cartes, les dieux, les
   matchups, l'avantage du premier joueur et les terrains.

Une invincibilité mathématique ne peut pas être garantie à cause du hasard, de
l'information cachée et des contres de deck. La cible est une robustesse mesurée
contre une large ligue d'adversaires, de decks et de seeds jamais vus pendant
l'entraînement.

## Décisions techniques

- Le moteur Godot reste l'unique source des règles.
- L'entraînement est réalisé hors ligne avec Python, Gymnasium et PyTorch.
- Le simulateur est déterministe pour un seed donné et ne dépend d'aucune frame
  d'animation.
- L'agent ne voit jamais le contenu de la main adverse.
- La politique apprend d'abord à jouer avec des decks fixes ; une boucle
  évolutionnaire recherche ensuite les meilleurs decks légaux.
- Une politique universelle apprend les six dieux avant un éventuel fine-tuning
  de six boss spécialisés.
- Les modèles finaux sont exportés en poids `float32` compacts et exécutés
  directement par Godot. ONNX ne fait pas partie de la cible actuelle.
- L'APK contient les poids et les decks : aucune connexion, installation Python
  ou phase d'apprentissage n'est nécessaire sur le téléphone.

## Organisation

```text
rl/
├── README.md
├── PLAN_DE_DEVELOPPEMENT.md
├── pyproject.toml
├── requirements.txt
├── configs/
├── scripts/
├── src/samstone_rl/
│   ├── bridge/       # Processus Godot et protocole JSON
│   ├── envs/         # Environnements Gymnasium et encodages
│   ├── models/       # Réseaux acteur-critique
│   ├── opponents/    # Adversaires aléatoires, moteur et checkpoints
│   ├── training/     # PPO, évaluation puis self-play
│   └── utils/        # Seeds, chemins et journalisation
└── tests/

game/tools/rl_sim/    # Adaptateur GDScript, dans le projet Godot
```

Le simulateur GDScript reste sous `game/` afin de charger les scripts du moteur
avec `res://`. Le code Python le lance avec `--path ../game`.

## Installation de développement

Python 3.11 est la version de référence.

```powershell
cd rl
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e .
```

Le chemin de Godot devra être fourni par l'argument de la commande, la variable
`GODOT_BIN`, ou un exécutable `godot` disponible dans le `PATH`. Aucun chemin
utilisateur ne doit être codé en dur.

Les commandes d'entraînement resteront désactivées dans la documentation tant
que le test d'intégration ne peut pas terminer une partie complète.

## Chaîne d'apprentissage visée

```text
moteur Godot synchrone
→ environnement Gymnasium masqué
→ PPO contre adversaire aléatoire
→ validation contre l'IA actuelle
→ self-play et ligue historique
→ évolution des decks
→ fine-tuning par dieu
→ tournoi final et sélection des six boss
```

Quelques milliers de parties serviront à valider la chaîne. La création de boss
très forts demandera vraisemblablement des centaines de milliers ou des millions
de parties, exécutées en parallèle et évaluées sur des seeds réservés.

## Intégration dans le jeu

Chaque artefact final comprendra :

- les poids et dimensions du réseau ;
- la version de l'observation et de l'espace d'actions ;
- le dieu et le deck du boss ;
- les normalisations et métadonnées nécessaires ;
- un checksum ;
- les résultats de son évaluation.

Godot utilisera un encodeur identique à celui de Python, exécutera le réseau,
masquera les actions illégales et choisira la meilleure action. Des fixtures
« observation → logits → action » vérifieront la parité Python/Godot avant tout
export Android.

Une variante hybride pourra ensuite utiliser le réseau pour proposer les
meilleurs coups et le moteur existant pour analyser seulement ces candidats.

## Statistiques d'équilibrage

Les simulations enregistreront au minimum : seed, dieux, decks, versions des
politiques, premier joueur, cases bloquées, résultat, marge, cartes jouées,
positions, captures, effets déclenchés et durée de partie.

Les rapports sépareront les performances de la politique, du deck et du dieu.
Un taux d'utilisation élevé ne suffira pas à déclarer une carte trop forte : les
comparaisons devront être contrôlées par matchup, coût, position de départ et
niveau de l'adversaire.

Voir [PLAN_DE_DEVELOPPEMENT.md](PLAN_DE_DEVELOPPEMENT.md) pour les étapes et les
critères de validation.
