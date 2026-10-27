# Charte des illustrations — pixel art horrifique

Cette charte fixe la direction **actuelle** des cartes et des portraits de dieux.
Elle complète la [direction artistique du bestiaire](DIRECTION_ARTISTIQUE_MONSTRES.md).
La mention « pixel art léger » dans l'ancien plan de reprise des N3 décrit une
étape antérieure : **elle ne doit plus servir de consigne de production**.

## Résultat recherché

Toutes les illustrations doivent former un même bestiaire horrifique, sombre mais
lisible sur téléphone. La référence de style est le **niveau 1 des quatre
premières cartes communes** de chacune de ces familles : Aléators (`f01`–`f04`),
Flétris (`d01`–`d04`), Remparts (`r01`–`r04`) et Essaim (`e01`–`e04`). Ces seize
images sont conservées comme étalons. Leurs pixels se distinguent dans les
contours **et dans les surfaces** : volumes, ombres et reflets sont construits
en amas nets de carrés, sans dégradé lisse caché sous un contour crénelé.

Le Ronge-chair, le Recycleur thoracique, Kharûn et Sylkha repris au début de
l'harmonisation ont été **validés et restent en place**. Pour les images
suivantes, viser des pixels **un peu plus marqués** que sur ces quatre rendus,
tout en conservant leur richesse et leur lisibilité. « Pixel art subtil » ou
« légèrement pixellisé » ne décrit pas le résultat attendu.

Garder les PNG à leur résolution native de production et leur transparence.
Leur taille de fichier ne doit pas être ramenée à 48 × 48 ou 64 × 64 pixels.
Le rendu peut évoquer un sprite détaillé d'environ 110 à 128 pixels logiques
sur une grande toile native : carrés réguliers bien visibles, courbes en
escaliers, surfaces faites de groupes de tons francs. Éviter l'aérographe, les
dégradés continus, les contours lissés, le grain ajouté et l'aspect peinture
numérique trop propre. Un simple filtre de pixellisation ne remplace pas un
dessin reconstruit en pixels.

## Ce qui est déjà approuvé

La phase en cours est une **harmonisation de style**, pas une nouvelle recherche
de créatures. Pour chaque niveau, partir de **son image approuvée** et préserver :

- la silhouette, la posture, la direction du regard et le cadrage ;
- les proportions, le nombre et la position des membres, doigts, griffes,
  antennes, yeux et autres organes ;
- les accessoires, leurs symboles, leur prise en main et leur côté ;
- la palette, les matières, la luminosité sombre mais lisible et la transparence.

Ne pas ajouter de cornes, d'armure, de membre ou de décor pour rendre la carte
« plus impressionnante ». Les évolutions N1/N2/N3 déjà validées doivent rester
visuellement distinctes : on pixellise **chaque illustration différente** sans
ramener les niveaux à la même pose ni transformer un niveau en simple copie
plus détaillée du précédent. Les N4 encore absents constituent un chantier
séparé ; cette charte ne les crée pas par anticipation.

## Contrôles de cohérence avant intégration

### Anatomie

- Compter les doigts et les griffes sur **chaque** main ou patte visible, puis
  comparer les niveaux d'une même créature. Vérifier la position des pouces :
  deux mains opposées ne doivent pas avoir le pouce du même côté par erreur.
- Vérifier qu'aucun membre ne flotte. Sur Énigma et les machines, toutes les
  pattes, pinces et outils sont reliés au châssis.
- Pour les insectes adultes concernés, distinguer **six pattes en trois
  paires**, deux antennes et les autres éléments (ailes, racines, filaments).
  Ne pas ajouter une septième patte ni compter une liane comme un membre.
- Conserver les côtés établis : l'amputation du Croupier manchot et la
  main-lance de Longuépine ne changent pas de côté entre niveaux.
- Préserver les particularités explicites de la lignée : les Avortons des caves
  gagnent en nombre avec les niveaux, avec leurs couleurs d'origine ; une
  variante adulte solitaire changerait le concept.

### Objets et symboles

- Dés : pas deux faces visibles identiques ; un œil qui tient lieu de point
  compte dans la valeur de sa face. Respecter les valeurs des faces opposées
  lorsque la géométrie du dé permet de les voir.
- Jeu de cartes : montrer aussi pique et trèfle, en noir, et cœur et carreau,
  en rouge. Pour les quatre as de Véskar ou du Croupier, chacun a une enseigne
  différente, avec un indice cohérent. Les doigts doivent réellement tenir
  le paquet ou les cartes.
- Roulette : une seule couronne de cases et une seule piste à bille.
  Machine à sous : symboles adaptés, tels que 7, cloches ou cerises, et non
  enseignes de cartes à jouer.
- Machines des Assimilateurs : quelques grands organes lisibles (pince, roue,
  scie, aspiration) plutôt qu'une multitude de pièces minuscules.

### Lecture et lumière

Comparer chaque nouveau rendu à son original, aux autres niveaux et aux cartes
de sa famille. Garder les masses sombres de l'univers, mais rendre lisibles
la tête, les membres et le point focal à la taille d'une carte sur mobile.
Ne pas éclaircir automatiquement les corrections anatomiques ni assombrir toute
une vague : les premières cartes validées servent d'étalon de luminosité.
L'illustration d'un dieu doit rester plus imposante et reconnaissable que les
cartes de sa famille, sans devenir illisible ou excessivement détaillée.

## Méthode de reprise

1. Examiner le PNG natif approuvé et les autres niveaux de sa lignée. Noter les
   éléments faciles à perdre : nombre de doigts, côté d'un accessoire, signes,
   luminosité et différence entre niveaux.
2. Générer **une seule illustration par image**, avec son original comme
   première référence et deux des seize étalons N1 pour la taille des pixels.
   Les étalons imposent le **style**, jamais leur créature ni leur palette.
3. Examiner le rendu à sa taille native et à une taille proche de son affichage
   dans le jeu. Contrôler séparément le style des pixels, l'anatomie, les
   objets, la transparence, la lumière et la continuité de la lignée.
4. Intégrer uniquement le PNG retenu, à sa résolution native, dans `assets/`.
   Conserver les originaux, consigner source et prompt, puis vérifier les
   fichiers. Ne modifier ni les statistiques, ni les identifiants, ni les
   sauvegardes du jeu pour une simple harmonisation visuelle.

Si le générateur est indisponible, noter le point de reprise. Ne pas remplacer
les images en attente par un rééchantillonnage ou un filtre automatique.

## État du chantier au 27 octobre 2026

Sur **252 illustrations** existantes (246 cartes et 6 dieux), le dernier
inventaire validé compte **90 reprises intégrées**, **42 images conservées
après examen**, **16 étalons N1 conservés**, et **104 images en attente**.
Les six portraits de dieux ont été traités. La reprise doit commencer par
`e07_n2`, puis `e07_n3` et le reste de l'Essaim ; viennent ensuite les
Veilleurs, les Assimilateurs et les Neutres. Le [journal de production et la
galerie](designs/bestiaire-pixel-art-01/harmonisation-pixel-art/README.md)
contiennent l'inventaire par fichier et les prompts exacts. Ce décompte est
un **instantané**, pas une preuve que les 104 illustrations restantes sont
terminées.
