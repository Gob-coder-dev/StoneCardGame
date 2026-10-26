# Illustrations des cartes

Les PNG retenus sont rangés par famille (`n`, `f`, `d`, `r`, `h`, `e`, `p`) et
nommés selon la forme : `n01_n1.png`, `d01_n4.png`, etc. La galerie de conception
utilise ces mêmes fichiers ; les corrections se font sur ce PNG unique.

Les 96 lignées disposent d'un PNG N1 et les 81 lignées évolutives d'un N2 propre.
Le dossier contient 203 illustrations : 96 N1, 81 N2, 22 N3 et 4 N4.
30 lignées évolutives ont toutes leurs formes illustrées.
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

N3 : **22/65 illustrés**, 13 dessins intégrés, quatre essais à reprendre après la limite de génération ;
43 restent à produire. Voir le [comparatif et le plan de reprise](../../docs/designs/bestiaire-pixel-art-01/evolutions-n3/index.html).
