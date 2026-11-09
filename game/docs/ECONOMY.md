# Économie, collection et boutique

L’économie repose sur une monnaie unique, les **âmes**, et sur des copies de
cartes persistantes. Ses valeurs d’équilibrage sont centralisées dans
`data/economy/economy_config.json` : aucune scène ne contient de prix, de seuil
d’amélioration ou de cadence de rotation en dur.

## Nouveau profil

Un nouveau joueur commence sans dieu, sans âme, avec une banque de deck
`neutral` et une copie niveau 1 de cinq communes neutres : Gueule-de-travers,
Ogre droitier, Le Drapé du seuil, Écorche-angle et Rampant des fosses. Un deck
sans dieu reste autorisé ensuite et ne peut contenir que des cartes neutres.

Le premier tutoriel constitue l’unique exception au deck de huit cartes : il
utilise les cinq premières cartes du deck du joueur sur un plateau 3 × 3, les
quatre premières cartes du Professeur Stone, aucune case bloquée et impose le
joueur comme premier camp. Sa première victoire donne une copie de chacune des
quatre autres communes neutres niveau 1. Les trois premières complètent
automatiquement le deck actif ; la quatrième rejoint la collection.

## Progression des cartes

La première copie d’une lignée débloque immédiatement sa forme niveau 1. Les
copies suivantes alimentent la jauge de la prochaine amélioration. Une
amélioration est une transaction atomique : les copies et les âmes ne sont
consommées que si l’enregistrement complet réussit.

| Rareté | Passage | Copies | Âmes |
| --- | --- | ---: | ---: |
| Commune | N1 → N2 | 50 | 200 |
| Commune | N2 → N3 | 100 | 700 |
| Commune | N3 → N4 | 200 | 1 500 |
| Rare | N1 → N2 | 25 | 700 |
| Rare | N2 → N3 | 50 | 1 500 |
| Épique | N1 → N2 | 15 | 1 500 |

Les légendaires n’ont pas d’amélioration. La collection montre toutes les
lignées : celles qui ne sont pas possédées et les formes supérieures encore
verrouillées sont grisées. Pour une carte possédée, la jauge affiche le nombre
de copies actuel et le seuil de la prochaine forme.

## Boutique

La boutique est le premier onglet de la barre de navigation. Elle propose
quatre offres déterministes pendant une rotation de trois heures. Une offre ne
peut être achetée qu’une fois par rotation. Recharger l’écran ou relancer le jeu
ne change donc ni le tirage ni son état d’achat.

| Rareté | Quantité | Prix |
| --- | ---: | ---: |
| Commune | 5 à 15 | 5 âmes par copie |
| Rare | 3 à 10 | 15 âmes par copie |
| Épique | 1 à 3 | 30 âmes par copie |
| Légendaire | 1 | 1 000 âmes |

Les cartes liées à un dieu verrouillé sont exclues du tirage. Les six dieux
restent visibles indépendamment de la rotation : le premier dieu acheté coûte
100 âmes, puis chaque autre dieu coûte 800 âmes. Chaque achat offre deux
communes fixes du dieu, choisies pour présenter des mécaniques différentes.

## Récompenses de campagne

Seules les victoires de campagne donnent des âmes. Chaque nœud déclare
explicitement `souls_min`, `souls_max` et ses éventuelles `card_rewards`. Le
montant est tiré de façon déterministe dans la fourchette de la tentative. Une
première victoire donne le montant complet ; rejouer un nœud déjà terminé donne
25 % du montant, arrondi par le service. Une défaite ou une égalité ne donne
rien. Une série FT2/FT3 ne récompense que sa victoire finale.

Les cartes de récompense sont accordées une seule fois. Elles sont actuellement
réservées au premier tutoriel ainsi qu’aux boss et mini-boss possédant une
récompense fixe dans les données. Les identifiants de transaction empêchent un
double paiement si un résultat ou un signal est traité deux fois.

Une carte neutre, ou une carte liée à un dieu déjà débloqué, rejoint directement
la collection. Une carte liée à un dieu encore verrouillé est conservée dans la
réserve persistante `pending_card_rewards` : elle reste inutilisable et hors de
la collection, mais l’écran de résultat annonce sa mise en attente. L’achat du
dieu transfère atomiquement toutes ses récompenses différées dans la collection.
Le chargement migre également vers cette réserve les cartes divines que les
anciennes versions auraient accordées avant le déblocage de leur dieu.

Le créateur de decks expose cette réserve depuis le bouton **Coffre**, placé à
côté de « Cartes possédées ». Sa pastille compte les lignées distinctes en
attente ; la fenêtre regroupe ensuite les cartes par dieu et affiche le nombre
exact de copies. Les sections vides ne sont jamais créées.

## Architecture et persistance

| Élément | Mission unique |
| --- | --- |
| `EconomyConfig` | charger et valider la configuration d’équilibrage |
| `CardProgressionRules` | calculer seuils, coûts et états d’amélioration |
| `PlayerInventory` | représenter âmes, dieux, copies, niveaux et achats |
| `EconomyService` | exécuter récompenses, améliorations et achats de dieux |
| `ShopService` | produire la rotation et acheter une offre |
| `CampaignRewardService` | traduire une victoire de nœud en transaction économique |
| `PlayerData` | posséder le profil et l’enregistrer de façon atomique |

Le profil version 6 sérialise l’inventaire avec les banques de decks et les
récompenses divines différées. Les services préparent une copie du prochain
état puis appellent une seule écriture
transactionnelle. En cas d’échec disque, l’inventaire et le deck restent
inchangés en mémoire. La progression de campagne demeure dans son fichier
séparé et ne duplique aucune valeur économique.

Pour les tests de développement, `PlayerData.reset_to_starter_profile()` recrée
le départ réel et `EconomyService.unlock_all_for_development()` restaure
un catalogue complet sans modifier les règles de production.
