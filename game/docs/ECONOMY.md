# Économie, collection et boutique

L’économie repose sur deux monnaies : les **âmes** servent aux achats ciblés et
aux améliorations, tandis que les **bougies** servent à accomplir des Rituels
aléatoires. Les copies de cartes restent persistantes. Les valeurs
d’équilibrage sont centralisées dans `data/economy/economy_config.json` et
`data/economy/rituals.json` : aucune scène ne contient de prix, de seuil,
de lot ou de probabilité en dur.

## Nouveau profil

Un nouveau joueur commence sans dieu, sans âme ni bougie, avec une banque de deck
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

## Rituels

Les Rituels sont achetables sans limite de rotation tant que le joueur possède
assez de bougies. Les quatre fiches sont affichées deux par ligne. Les trois
Rituels à lots produisent des lignées distinctes parmi les cartes neutres et
celles des dieux déjà débloqués. Le Rituel unique constitue l'exception : il
peut tirer une carte de tout le catalogue et place une carte divine dans le
coffre si son dieu est encore verrouillé.

| Rituel | Bougies | Âmes | Invocations normales |
| --- | ---: | ---: | --- |
| Petit | 15 | 10 à 20 | 2 communes ×3–5, 1 rare ×1–2 |
| Basique | 30 | 30 à 50 | 1 commune ×4–7, 2 rares ×3–5, 1 épique ×2–3 |
| Grand | 70 | 100 à 200 | 1 commune ×8–12, 2 rares ×5–8, 2 épiques ×3–5, 1 légendaire |
| Unique | 100 | 0 | 1 carte non possédée de tout le catalogue |

Le Petit et le Basique ont 10 % de chances d’utiliser leur composition
exceptionnelle. Le Rituel unique cherche en priorité une légendaire manquante,
puis une épique, une rare et une commune, sans exclure les cartes neutres ni les
dieux verrouillés. Une carte divine verrouillée rejoint le coffre ; elle compte
alors comme déjà gagnée et ne peut plus être tirée par ce Rituel. Il est
indisponible lorsque toutes les lignées sont possédées ou déjà au coffre.

Une invocation déjà au niveau maximal est montrée normalement, puis remplacée
par la moitié de sa valeur unitaire en boutique, arrondie en faveur du joueur :
3 âmes par commune, 8 par rare, 15 par épique et 500 par légendaire.

L’achat, le tirage, les cartes, les âmes et la dépense de bougies sont enregistrés
en une transaction avant l’animation. L’ouverture vit uniquement dans
`RitualOpeningContext` et n’entre jamais dans la sauvegarde : fermer le jeu ne
perd aucune récompense, mais abandonne définitivement la présentation restante.
L’animation n’est donc jamais propriétaire de l’économie et ne peut pas être
reprise.

Dans la boutique, chaque fiche de Rituel et de dieu affiche directement son
prix, mais toute la fiche reste l'unique zone tactile. Les compositions,
fourchettes et probabilités des Rituels sont réservées à la confirmation. À
l'ouverture, un seul embrasement couvre tout l'écran pour invoquer les cartes ;
les transitions entre les révélations utilisent ensuite uniquement des flammes
basses afin de ne pas répéter cet effet majeur.

## Récompenses de campagne

Seules les victoires de campagne donnent des âmes et des bougies. Chaque nœud déclare
explicitement `souls_min`, `souls_max` et ses éventuelles `card_rewards`. Le
montant est tiré de façon déterministe dans la fourchette de la tentative. Une
première victoire donne le montant complet ; rejouer un nœud déjà terminé donne
25 % du montant, arrondi par le service. Une défaite ou une égalité ne donne
rien. Une série FT2/FT3 ne récompense que sa victoire finale. Les victoires
donnent 1 bougie dans les premiers chapitres, 2 au milieu de la campagne et 5
dans les trois dernières sections ; une revanche victorieuse conserve ce montant.

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
| `RitualConfig` | charger et valider les quatre définitions de Rituels |
| `CardProgressionRules` | calculer seuils, coûts et états d’amélioration |
| `PlayerInventory` | représenter monnaies, dieux, copies, niveaux et achats persistants |
| `EconomyService` | exécuter récompenses, améliorations et achats de dieux |
| `ShopService` | produire la rotation et acheter une offre |
| `RitualRewardGenerator` | tirer des récompenses pures, distinctes et éligibles |
| `RitualService` | acheter, compenser et sauvegarder toutes les récompenses d’un Rituel |
| `RitualOpeningContext` | transporter uniquement l’animation courante en mémoire |
| `CampaignRewardService` | traduire une victoire de nœud en transaction économique |
| `PlayerData` | posséder le profil et l’enregistrer de façon atomique |

Le profil version 8 sérialise l’inventaire avec les banques de decks, les deux
monnaies et les récompenses divines différées. Les services préparent une copie du prochain
état puis appellent une seule écriture
transactionnelle. En cas d’échec disque, l’inventaire et le deck restent
inchangés en mémoire. La progression de campagne demeure dans son fichier
séparé et ne duplique aucune valeur économique.

Pour les tests de développement, `PlayerData.reset_to_starter_profile()` recrée
le départ réel et `EconomyService.unlock_all_for_development()` restaure
un catalogue complet sans modifier les règles de production.
