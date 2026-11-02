# Illustrations des cartes

Les illustrations sont rangées par famille : `n`, `f`, `d`, `r`, `h`, `e` et
`p`. Le format de nommage est `<identifiant>_n<niveau>.png`, par exemple
`n01_n4.png` ou `p04_n2.png`.

Le projet contient **275 PNG** : 96 N1, 81 N2, 65 N3 et 33 N4. Chaque lignée
évolutive possède une illustration propre à tous ses niveaux.

Dans `data/stones.json`, le champ `asset` de la lignée désigne l’illustration
par défaut et `levels[].asset` permet de choisir l’image propre à un niveau.
Modifier une image ne doit pas modifier les statistiques, les identifiants ou les
sauvegardes.

Conserver les fichiers `.png.import` : compression sans perte, taille d’origine
et mipmaps selon les réglages existants. Les sources restent à leur résolution
native avec transparence ; aucun rééchantillonnage n’est appliqué aux assets.
