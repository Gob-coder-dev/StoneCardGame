# Corrections et validation du RL — 15 novembre 2026

Le chemin officiel utilise le catalogue actuel du jeu et le modèle tactique
sur toute la chaîne PPO, self-play, recherche de decks, spécialisation et export.
Les anciens runs et checkpoints ont été conservés. Les commandes actualisées
figurent dans [GUIDE_COMMANDES.md](GUIDE_COMMANDES.md).

## Corrections apportées

| Constat de l’audit | Correction |
| --- | --- |
| Ancien catalogue `stones.json` introuvable | Lecture du manifeste et des sept familles, validation du contenu et définitions Python immuables. |
| Architecture tactique perdue entre phases | Fabrique et contrat communs ; dimensions, architecture et schémas enregistrés et vérifiés. |
| Identités de contenu incompatibles | Empreinte canonique commune Python/Godot ; identités distinctes pour contenu, règles et decks. |
| Scores tactiques différents | Features réseau v2 indépendantes du bot enseignant ; aperçus déterministes communs et tests des six dieux. |
| Aléatoire de l’effet essaim différent | Même hachage de graine que Godot ; flux portable pour les tests de parité. |
| Certifications trop peu liées aux règles | Certification des poids exacts, du rapport et de l’arbitre ; refus des contrats périmés. |
| Écrasement accidentel d’un run | Création, reprise et évaluation explicites ; verrou système exclusif. |
| Reprise bloquée après prolongation du budget | Champs opérationnels autorisés explicitement, historique des configurations et contrôle du reset de l’optimiseur. |
| Confirmations répétant les mêmes parties | Compteurs persistants et espaces de seeds séparés par usage et par phase. |
| Fermeture incomplète des ressources | `close()` idempotent, gestionnaires de contexte et nettoyage des constructeurs en échec. |
| Test statistique instable sur grands effectifs | Calcul du test des signes dans le domaine logarithmique. |
| Dépendances incohérentes | Python 3.11, deux verrous CPU/DirectML, suppression du conflit torchaudio et vérificateur d’environnement. |
| Tournoi phase 4 séquentiel et non reprenable | Workers réutilisés, reprise des processus et registre SQLite durable par contexte et poids. |
| Checkpoint et SHA pouvant diverger après interruption | Écriture atomique avec journal de récupération vérifié. |
| Projection tactique et concaténation coûteuses | Projection d’état factorisée, mêmes paramètres et équivalence des sorties et gradients. |
| Buffers et exécuteurs reconstruits | Réutilisation du stockage PPO, accès aux tableaux batch et exécuteur persistant du pool. |
| Cache de ligue et écritures non bornés | Cache LRU de huit modèles, résultats journalisés et écritures regroupées. |
| Responsabilités mélangées | Modules séparés pour collecte, optimisation, évaluation, checkpoints, état et rendu des rapports. |
| Duplication et code mort | Chargements, SHA et statistiques partagés ; retrait du wrapper inutilisé et de l’ancienne session self-play. |
| Intégration du modèle dans Godot absente | Export `.sspolicy`, chargement vérifié, inférence incrémentale et adaptateur `MoveSearch`. |
| Nom DirectML mal interprété par des évaluateurs | Résolution commune du périphérique dans comparateur, adversaires gelés et évaluateurs de decks. |
| Documentation obsolète | README, plan, guide de migration, commandes de validation et limites réécrits. |

La référence scalaire et les noyaux vectorisés restent distincts : leurs
responsabilités sont différentes et leur équivalence est vérifiée. Les méthodes
`forward` nécessaires à PyTorch restent disponibles.

## Contrôles effectués

- Suite finale complète : **159 tests réussis** en 305,89 s, avec Godot et
  DirectML, incluant les régressions de reprise et les deux architectures.
- Commandes documentées : **18 sur 18** chargées correctement avec `--help`.
- Ruff : analyse et formatage vérifiés sur les sources, scripts et tests.
- Dépendances : `pip check` sans conflit ; installation éditable du paquet vérifiée.
- Environnement : catalogue de 275 formes, identité des règles et du contenu
  comparée entre Python et Godot ; vraie mise à jour de paramètres sur DirectML.
- Parité : parties complètes pour les six dieux et 24 matchs supplémentaires
  avec decks légaux croisés ; états, captures et scores tactiques comparés.
- Export : mêmes observations, features, logits, valeurs et choix de coup dans
  PyTorch et Godot pour les deux architectures. Le parcours de l’interface
  masque aussi la main adverse et avance le calcul par tranches.
- Persistance : verrou concurrent, refus d’écrasement, corruption, transaction
  interrompue, reprise de tournoi et récupération du journal de ligue.
- Reprise DirectML réelle : sauvegarde après 16 transitions, rechargement des
  poids et de 14 états d’optimiseur, poursuite jusqu’à 32 transitions réussie.
- Godot : **2 088 contrôles des règles et 108 contrôles tactiles réussis** ;
  démarrage sans diagnostic applicatif dans le débogueur.
- Pack de ressources Godot : **188,99 Mio**, archive intègre, aucune ressource
  de test/outillage interdite, empreinte des règles embarquée et vérifiée.

Les journaux détaillés sont conservés localement sous `.tmp/rl-fixes/`, ignoré
par Git. Le message Windows concernant le magasin de certificats racine est
un diagnostic d’environnement identifié séparément. Les tests d’erreurs de
sauvegarde provoquent volontairement certains messages, puis vérifient leur
traitement. Un export de ressources ne constitue pas une validation d’APK.

## Mesures de performance

Poste Windows, Python 3.11.9, PyTorch 2.4.1, un thread CPU, GPU AMD Radeon RX 6800.
Le benchmark du réseau utilise 256 observations, deux échauffements et cinq
répétitions alternant l’ordre des deux implémentations.

| Calcul réseau avant/arrière | Concaténation, médiane | Factorisation, médiane | Rapport |
| --- | ---: | ---: | ---: |
| CPU | 384,1 ms | 144,8 ms | **2,65×** |
| DirectML | 8,79 ms | 6,58 ms | **1,34×** |

La concaténation intermédiaire de **80 Mio** est évitée pour ce lot. Ces mesures
portent sur le réseau, pas sur le temps total d’entraînement ni sur le niveau
atteint par la politique.

Essai PPO DirectML avec la configuration officielle, 256 environnements,
2 048 transitions par lot, trois mises à jour, une époque et palier
`precision_100_anticipation_50` :

- **459,7 décisions/s**, **57,5 parties terminées/s**, médianes sur cet essai court.
- **4,455 s/mise à jour**, collecte et optimisation incluses.
- **100 % de couverture vectorisée**, espace de travail réutilisé de 31 Mio.

Cet essai désactive les évaluations Godot, les checkpoints périodiques et la
pré-évaluation de promotion. Il vérifie la boucle d’apprentissage ; il ne mesure
pas la convergence ni le débit d’une campagne complète avec ses validations.

## Réévaluation des anciens poids

Les deux checkpoints existants de `runs/ppo_phase4_vectorized/` ont été chargés
sans modification et comparés sur les mêmes 72 cas Godot, avec les six dieux,
les deux camps, les deux ordres et les trois nombres de cases bloquées. Le
profil adverse est `precision_025`, avec l’espace de seeds de comparaison.

| Checkpoint | Victoires | Nuls | Défaites | Taux de victoire |
| --- | ---: | ---: | ---: | ---: |
| `best.pt` | 69 | 3 | 0 | 95,83 % |
| `latest.pt` | 68 | 3 | 1 | 94,44 % |

Ce contrôle confirme leur réutilisation technique avec les règles et features
actuelles. Il ne certifie pas les huit paliers : la différence entre ces deux
résultats n’est pas significative au test des signes (`p = 0,5`). L’import de
poids dans un nouveau run reste explicite et ne transmet aucune certification.

## Blocage DirectML des évaluations parallèles — 15 novembre 2026

Le démarrage à froid des dix évaluateurs a reproduit un blocage natif dans
`torch.as_tensor(..., device=directml)`, lors du transfert des features tactiques.
Les connexions Godot étaient établies et les simulations seules fonctionnaient.
Le choix entre les exécutables principal et console de Godot n'était donc pas
la cause démontrée. Une initialisation seule du réseau ne suffisait pas sur un
lot prolongé : les transferts, l'inférence et la lecture de l'action sont désormais
protégés par un verrou commun aux évaluateurs DirectML. Les simulations Godot
restent parallèles ; CPU et CUDA conservent leur fonctionnement précédent.

Contrôle isolé avec la configuration vectorisée officielle, l'import de
`runs/ppo_phase4_vectorized/best.pt`, dix processus Godot et 500 parties au palier
`precision_0` (offset de seed `400100000`) : **492 victoires, 6 nuls, 2 défaites**, en
**31,2 secondes démarrage compris**, première partie terminée à **3,6 secondes**.
Ces mesures décrivent cet essai local ; elles ne certifient pas les autres paliers.
Le run utilisateur et ses checkpoints n'ont pas été modifiés par ce contrôle.

Un test de non-régression lance une évaluation DirectML à froid dans un nouveau
processus, avec dix évaluateurs et une limite de temps. Il vérifie la fin des dix
parties, la progression et la conservation de l'état aléatoire PyTorch. Ce test
reproduisait le blocage avant la protection des transferts et passe après.

## Travail expérimental restant

La correction du logiciel ne produit pas automatiquement six boss validés.
Aucune campagne longue ni tournoi final de 19 200 parties n’a été lancé ici.
Les modèles retenus doivent passer les gardes actuelles, puis la mémoire et la
latence doivent être mesurées sur le téléphone cible. Les profils existants
restent actifs tant que les artefacts certifiés ne sont pas sélectionnés.

La CI CPU/Godot est configurée ; les vérifications rapportées ici ont été
exécutées localement sous Windows, pas sur un runner GitHub Linux.
