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
successives de 500 parties, au moins 80 % de victoires, au plus 10 % de défaites
et une borne de confiance des non-défaites de 87 %. La validation finale de
phase 4 utilise également 80 % / 10 % / 87 % pour certifier le socle généraliste.
Les exigences des boss spécialisés restent indépendantes et inchangées.
Veskar est évalué séparément avec 60 % de victoires minimum et 20 % de défaites
maximum. Les seuils 80 % / 10 % / 87 % ci-dessus s’appliquent au groupe des autres
dieux. L’exception de Veskar est vérifiée sur l’ensemble de ses parties de chaque
palier ; ses tranches restent complètes sans seuil de taux supplémentaire par
petite série. Elle s’applique aux promotions et à la validation finale de phase 4.
Les confirmations utilisent des seeds
renouvelés et leur compteur est sauvegardé.

La garde finale applique en plus un contrôle à chaque dieu hors Veskar contre
chaque palier : au moins 80 % de victoires et au plus 10 % de défaites sur les
400 parties regroupant camps et ordres de jeu. Chaque tranche de 100 parties
de ces dieux doit conserver au moins 70 % de victoires et au plus 20 % de
défaites. Les contrôles agrégés du socle et l'exception de Veskar restent actifs.
Les promotions intermédiaires ne sont pas modifiées par ce changement.

La pré-évaluation peut avancer dans les paliers déjà maîtrisés avant PPO.
Son compteur survit aux reprises. Ses seeds sont séparés de ceux des
confirmations, ancrages et validations finales.

Le tournoi final représente 19 200 matchs : huit paliers, six dieux, deux camps,
deux ordres et 100 parties par tranche. Les résultats sont enregistrés
progressivement dans SQLite et les cas manquants peuvent être repris.
L'identité du registre inclut poids, moteur, contexte et planning.
Sa réussite permet de produire `phase4_validated.pt` avec une certification
liée aux poids exacts.

La commande PPO principale orchestre cette validation automatiquement via
`training/phase_four_automation.py`. Le candidat et son identité sont figés
avant le premier match. `latest.pt` contient l'état du cycle et reprend une
validation interrompue avant toute nouvelle optimisation. Une erreur technique
arrête le programme et ne compte pas comme un échec statistique.

Après un échec des critères, Adam et le curriculum sont conservés ; les
confirmations sont réinitialisées. Il faut au moins 100 nouvelles mises à jour,
des poids différents et les deux confirmations habituelles avant un nouveau
tournoi, avec des seeds distincts. Les critères ne sont pas assouplis.
`phase4_automation.maximum_failed_attempts` borne le nombre d'échecs à trois.
Le budget PPO reste applicable ; une validation déjà en cours peut néanmoins
se terminer après épuisement du budget. Une réussite sauvegarde le certificat
et arrête la phase 4 sans démarrer la phase 5. L'état est publié dans
`phase4_status.json` et la progression finale dans les métriques de suivi.

Une révision explicite des critères peut être appliquée à un tournoi Godot
déjà terminé avec `validate_phase4.py --reuse-recorded`. La commande retrouve
le candidat figé et le registre SQLite grâce à l'identité originale et au
planning original, vérifie les poids, le moteur et la couverture complète,
puis utilise la même fonction de calcul que la validation en direct.
Elle refuse un changement de règles, de contenu, de decks ou de planning.
Un changement des sources Python doit être autorisé explicitement.
Le rapport et le certificat indiquent les anciens et nouveaux critères,
les empreintes du candidat et du registre, et le caractère rétrospectif du
recalcul. Les snapshots originaux sont conservés ; l'ancien `latest.pt` est
archivé avant remplacement. Ce résultat ne mesure pas une généralisation
sur de nouvelles parties.

### Phase 5 — self-play

Le protocole `champion_v1` remplace le renouvellement des adversaires à
intervalles fixes. Le modèle certifié de phase 4 est le champion initial.
Le candidat conserve son optimiseur PPO et apprend en Python. Les poids de
tirage sont 60 % champion, 20 % anciens champions et 20 % bots, renormalisés
quand une catégorie n'existe pas encore. Chaque épisode garde son adversaire.

Tous les 100 updates, une présélection couvre les 36 combinaisons de dieux,
les camps et les premiers joueurs (144 matchs). Un score d'au moins 52 % peut
ouvrir une tentative après le délai minimum. Le candidat est alors figé ;
aucune optimisation ne s'effectue pendant les confirmations.
Les bots des huit paliers sont évalués en premier, puis les anciens champions.
Un échec de conservation termine la tentative avant les longues confirmations.

Une promotion exige deux confirmations indépendantes de 1 152 matchs chacune,
au moins 53 % de score et une borne de confiance bootstrap appariée supérieure
à 50 % à chaque confirmation. Le score compte les victoires pour 1 et les nuls
pour 0,5. Le bootstrap rééchantillonne les paires qui inversent les modèles sur
une même situation initiale. Il s'agit d'une estimation unilatérale à 95 %, pas
d'une garantie d'erreur globale sur toute une suite adaptative de tentatives.

Les scores de chaque dieu sont comparés au champion jouant contre lui-même sur
les mêmes situations ; une baisse supérieure à 5 points bloque la promotion.
Les confrontations individuelles sont diagnostiquées, sans plancher absolu
qui pénaliserait un désavantage naturel entre dieux. Jusqu'à trois anciens
champions, dont toujours la référence initiale, servent de garde : score minimum
48 % et baisse maximale de 5 points par rapport au champion courant contre
chaque référence. Les bots des huit paliers contrôlent aussi la conservation
du taux de victoire de phase 4, avec une baisse maximale de 5 points par palier
et 8 points par dieu. Toutes ces valeurs se trouvent dans le YAML.

Le champion est remplacé seulement après réussite des contrôles. L'objectif
de campagne est de trois promotions ; ce nombre ne prouve pas un niveau optimal.
La dernière exige en plus 1 728 duels sur de nouvelles seeds et de nouveaux
contrôles historiques et Godot. Sa réussite produit `phase5_validated.pt`, puis
arrête automatiquement le run. La patience est de 1 500 mises à jour sans
promotion ; le budget PPO reste une limite indépendante. Les arrêts pour
plateau ou budget épuisé ont le code de sortie 2 et ne produisent pas de certificat.

Le checkpoint est la source de reprise. Il contient les champions immuables,
le candidat en validation, les empreintes, les compteurs et les rapports.
Les tournois Godot parallèles enregistrent seulement les résultats compacts
dans SQLite ; les matrices de features terminales ne sont pas conservées.
Une interruption reprend les matchs manquants avant toute optimisation,
y compris si le budget est épuisé. Une erreur technique ne compte pas comme
un échec de performance. Les sources et les critères restent figés pendant
une tentative. Les modèles CPU ont un cache borné et les évaluations préservent
les générateurs aléatoires et le réglage des threads de l'apprentissage.
Une reprise autorisant explicitement un changement des seules sources Python
archive la tentative interrompue et recommence la validation des mêmes poids
sur de nouveaux seeds, avant toute mise à jour PPO. Le backend Python regroupe
les décisions des parties qui partagent un checkpoint adverse, avec un RNG
propre à chaque partie.
La collecte PPO omet l'encodage d'une observation terminale qu'elle remplacerait
immédiatement au reset. Les récompenses et statistiques finales sont enregistrées.
Les décisions du champion utilisent un masque construit depuis l'état du jeu,
en conservant la convention du codec pour les cartes répétées.

Une migration de l'ancien plan conserve poids, Adam et compteurs mais démarre
le nouveau curriculum à zéro promotion avec la phase 4 comme référence.
Les anciens fichiers et le manifeste de ligue sont archivés, sans attribuer
de validation rétroactive aux snapshots non évalués. Le statut est publié dans
`phase5_status.json`, les métriques dans TensorBoard et les preuves dans
`evaluations/phase5/`. `validate_phase5.py` vérifie le certificat automatique ;
il ne relance plus une ancienne campagne manuelle.

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
