# Illustrations des cartes

Les PNG retenus sont rangés par famille (`n`, `f`, `d`, `r`, `h`, `e`, `p`) et
nommés selon la forme : `n01_n1.png`, `d01_n4.png`, etc. La galerie de conception
utilise ces mêmes fichiers ; les corrections se font sur ce PNG unique.

Les 96 lignées disposent d'un PNG N1 et les 81 lignées évolutives d'un N2 propre.
Les 65 lignées pouvant atteindre le N3 disposent également de leur dessin.
Le dossier contient 246 illustrations : 96 N1, 81 N2, 65 N3 et 4 N4.
52 lignées évolutives ont toutes leurs formes illustrées ; 29 N4 restent à créer.
Les quatre premiers essais N2 (N02, N03, N08, N10) ont été remplacés.
Les niveaux sans dessin propre héritent de l'image N1 de leur lignée.

Le [comparatif N1/N2](../../docs/designs/bestiaire-pixel-art-01/evolutions-n2/index.html)
présente les 81 évolutions à taille égale, avec filtres par famille et aperçu
en petites vignettes. Les légendaires gardent leur niveau unique.

Le [comparatif des lignées](../../docs/designs/bestiaire-pixel-art-01/reconstruction-lignees/index.html)
montre les dessins conservés et les nouvelles formes précédentes. L'Ogre et le
Drapé utilisent leurs anciens N1 en N3 et leurs essais appréciés en N4 ; le
Dos-fendu possède trois dessins nouveaux. Les statistiques restent inchangées.

L'Affamé du puits conserve son ancien dessin complet au N2 ; au N1, seul son
visage apparaît dans le puits, tête basculée en arrière et gueule ouverte.
Les deux premiers Fouisseurs ont une morphologie immature distincte du N3 massif.

Dans `data/stones.json`, `lineages[].asset` fournit l’image commune et
`levels[].asset` permet une illustration spécifique à une évolution. Un champ
vide conserve le dessin provisoire. Les statistiques restent indépendantes.

Conserver les réglages `.png.import` : compression sans perte, taille illimitée,
mipmaps activés. `StoneCard` adapte uniquement le rectangle d’affichage, en
respectant les proportions ; le fichier source garde sa résolution complète.

N3 : **65/65 illustrés**. Les corrections anatomiques de l'Écorche-angle, la
reconstruction des trois Tricornes et les cartes du Croupier N3 sont intégrées.
N24, F07, F08, D07, R06 et E07 conservent leur ancien dessin adulte au N3 avec
un nouveau N2 intermédiaire. Voir le [comparatif des trois niveaux](../../docs/designs/bestiaire-pixel-art-01/evolutions-n3/index.html).

Après retour sur les évolutions, 13 illustrations ont été reprises : 11 N3,
le N1 du Charognard courbe et le N2 de la Griffe septique. Les anciens PNG
sont conservés dans le dossier de conception ignoré par Git. Le
[comparatif des corrections](../../docs/designs/bestiaire-pixel-art-01/corrections-evolutions-octobre/index.html)
présente chaque lignée avec son ancien dessin pour validation artistique.
Ce lot corrige les évolutions et les appuis ; la reprise générale des rendus
trop lisses attend cette validation. Tous les PNG retenus restent en résolution
native 1254 × 1254 avec leur transparence, sans filtre ni rééchantillonnage.
