# Architecture et critères de validation — SamStone RL

Ce document décrit le logiciel actuel et les expériences restant à conduire.
Implémentation, vérification technique, entraînement et certification sont des
états distincts. Une promesse d'invincibilité ne peut pas être déduite des tests
du logiciel dans un jeu avec hasard et information cachée.

## Responsabilités

| Domaine | Responsabilité |
| --- | --- |
| Catalogue | Charger le manifeste du jeu, valider et exposer des définitions immuables |
| État scalaire | Représenter et cloner les parties, indépendamment de PPO |
| Règles Python | Accélérer la collecte et rester contrôlées par Godot |
| Noyaux vectorisés | Évaluer les actions et effets avec des buffers réutilisables |
| Modèles | Construire et utiliser les politiques dans toutes les phases |
| PPO | Coordonner collecte, récompenses, optimisation et curriculum |
| Optimisation | Calculer pertes, gradients et diagnostics sans gérer Godot |
| Évaluation | Appliquer les plannings et enregistrer durablement les résultats |
| Checkpoints | Vérifier les contrats et récupérer une transaction interrompue |
| Spécialisation | Associer une politique à son dieu et son deck final |
| Observabilité | Agréger les mesures, puis rendre des rapports séparément |
| Export | Encoder les poids float32 et vérifier leur inférence dans Godot |

La référence utilise 256 environnements, huit décisions par environnement,
un batch de 2 048 transitions et dix processus Godot pour les évaluations.
Ce réglage doit être mesuré sur chaque matériel.

## Identités et formats

L'empreinte commune de contenu v2 couvre les champs de combat, niveaux,
lignées et affiliations. Les textes et illustrations en sont exclus. Le
snapshot de construction des decks signe aussi ses contraintes et coûts.
Les sources des règles Godot sont signées séparément, avec des fins de ligne
normalisées et un tri de chemins identique entre plateformes. La provenance
Python identifie le code d'apprentissage ; le manifeste de l'arbitre contient
la version de Godot et les schémas.

Les checkpoints v2 conservent ces identités, les poids, Adam, le curriculum,
les RNG et les compteurs d'évaluation. Un journal permet de récupérer un
remplacement interrompu du modèle et de son empreinte. Une autre corruption
est rejetée. Une reprise redémarre les épisodes en cours.

Le chargeur commun couvre ActorCritic et TacticalActorCritic. L'observation v1
contient 929 valeurs ; 128 actions sont possibles et les features tactiques v2
contiennent 79 valeurs par action. Leur signification est indépendante de
l'heuristique du bot enseignant.

## Phases et critères

### Phase 4 — politique universelle

Logiciel implémenté. Huit paliers : précision 0, 25, 50 et 100 %, puis
anticipation 25, 50, 75 et 100 %. La configuration exige deux confirmations
successives de 500 parties, au moins 85 % de victoires, au plus 7 % de défaites
et ses autres critères statistiques. Les confirmations utilisent des seeds
renouvelés et leur compteur est sauvegardé.

La pré-évaluation peut avancer dans les paliers déjà maîtrisés avant PPO.
Son compteur survit aux reprises. Ses seeds sont séparés de ceux des
confirmations, ancrages et validations finales.

Le tournoi final représente 19 200 matchs : huit paliers, six dieux, deux camps,
deux ordres et 100 parties par tranche. Les résultats sont enregistrés
progressivement dans SQLite et les cas manquants peuvent être repris.
L'identité du registre inclut poids, moteur, contexte et planning.
Sa réussite permet de produire `phase4_validated.pt` avec une certification
liée aux poids exacts.

### Phase 5 — self-play

Logiciel implémenté. L'initialisation exige une phase 4 certifiée et compatible.
La ligue conserve des adversaires gelés et borne leur cache mémoire. Un épisode
garde son adversaire même si le cache cesse de le référencer.

La validation compare candidat et politique initiale contre les bots Godot,
puis mesure les matchs entre dieux. Les critères sont ceux du YAML.
`phase5_validated.pt` est produit après réussite ; une nouvelle mise à jour PPO
nécessite une nouvelle validation.

### Phase 6 — recherche de decks

Logiciel implémenté. La politique est gelée. Les decks proviennent du catalogue
Godot et sont validés par ses règles. Les candidats sont comparés sur des
plannings communs et les résultats mis en cache avec leur contexte.
Le mode `--pilot` sert aux essais techniques et ne produit pas une validation
officielle.

### Phase 6B — spécialisation

Logiciel implémenté. Six rapports officiels cohérents et leur politique
universelle constituent le registre des boss. Un run entraîne chaque dieu
avec son deck final. Les validators contrôlent amélioration, matchups,
conservation du niveau contre les bots et cohérence du registre.

### Export et intégration Godot

Export `.sspolicy` et inférence native implémentés. Les tests comparent
observations, features, logits, actions et valeurs PyTorch/Godot.
La préparation des projections est répartissable sur plusieurs images ;
l'évaluation des actions utilise le contrat `MoveSearch` du jeu.

L'activation passe explicitement par `AITurnRunner.create_neural_ai()`.
Les profils existants restent actifs jusqu'à sélection d'artefacts certifiés.
L'export Godot embarque l'identité des règles avant la compilation des scripts.

Restent à conduire sur les modèles retenus : campagne statistique finale,
mesure mémoire/latence sur téléphone cible et sélection des six artefacts livrés.

### Observabilité

Implémentée : JSONL, TensorBoard, alertes, rapports de progression, statistiques
par dieu et carte et ablations appariées. Les associations de cartes doivent
être confirmées à matchup, politique, camp et ordre comparables avant de servir
à une décision d'équilibrage.

## Vérification et expériences

- Unités : encodage, masques, PPO/GAE, curriculum et statistiques numériques.
- Parité : moteurs scalaire/vectorisé et référence Godot, effets et six dieux.
- Raccordement : modèle tactique dans ligue, évaluateurs et spécialistes.
- Persistance : écrasement refusé, verrou concurrent, corruption et interruption.
- Inférence : mêmes entrées/sorties PyTorch/Godot et préparation incrémentale.
- Régression : CI RL déclenchée aussi par les modifications du jeu.

Les certifications synthétiques des fixtures vérifient les raccordements :
elles ne constituent pas des modèles de boss à distribuer.

Mesurer séparément préparation, environnement, optimisation, évaluation et
entrées/sorties. Comparer avec échauffement, répétitions et budgets identiques.
Un gain de vitesse du réseau ne prouve pas à lui seul un gain de niveau.

Les changements de récompense, curriculum et hyperparamètres doivent être
isolés, évalués sur plusieurs graines d'entraînement et confirmés sur des parties
Godot réservées. La prédiction auxiliaire de marge reste expérimentale et
désactivée dans la configuration officielle.
