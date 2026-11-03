# Guide Fooocus — dieux et monstres de SamStone

Ce guide transforme le [bestiaire](BESTIAIRE.md) et [`stones.json`](../data/stones.json) en prompts directement utilisables dans Fooocus.

**Un seul champ Fooocus, un seul prompt positif complet par image.** Copier un bloc à la fois ; ne pas ajouter de prompt négatif, ne pas assembler des blocs séparés et ne pas compter sur la mémoire d’une image précédente. Les six dieux et les 222 cartes à refaire ont chacun leur prompt individuel. Les 53 illustrations validées sont à conserver.

## Format des images

- Cible finale carrée : PNG **496 × 496 px**, transparence alpha réelle, au plus 500 × 500 px. Si Fooocus ne propose pas cette taille ou l’alpha, redimensionner et détourer après génération.
- Personnage complet, isolé et centré, avec marge autour des extrémités. Aucun décor, sol, paysage, cadre de carte, texte, interface ou logo ; ne pas dessiner le damier de transparence.
- Vérifier le canal alpha avant intégration : Fooocus peut produire un fond opaque même si le prompt demande un fond transparent.

## Palettes précises par famille

Les hexadécimaux fixent les couleurs dominantes observées dans les références, pas des aplats uniformes. Une **légère liberté** est permise pour nuancer les matières et préserver la lisibilité ; elle ne doit pas changer l’identité de famille. Chaque prompt répète sa palette afin d’être utilisable seul.

- **Neutres :** os beige #D2C4A9, pierre gris-brun #756B60, brun terre #514239, ombres charbon #282526. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Aléators :** chair ivoire #E9D7BB, rose #D88791, rouge carmin #A92F48, prune-noir #291822, or/cuivre #B77A39. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Flétris :** os sale #D2C5AD, chair gris-beige #A39487, cendre #625A5B, prune #493447, spores violet #88549C. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Remparts :** basalte #34363B, ardoise #65666A, os ivoire #D8CFB9, rouille/cuivre #945A3B, turquoise #348B89. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Veilleurs :** bleu nuit #08152E, cobalt #174A9B, indigo #111D45, ivoire argenté #D7D1BF, bleu électrique #55BDF0. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Essaim :** vert olive #66732F, vert feuille #94A64A, racine brune #493426, ambre #C58A32, miel #E5B44E. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.
- **Assimilateurs :** fer noir #29292D, acier #626168, cuivre #A96036, rouille #713D2D, os récupéré #C9B99D, orange #E9822C. Palette dominante, avec légère liberté pour les nuances nécessaires à la matière et à la lisibilité.

## Style commun

Le style est explicitement un **léger pixel art peint**, proche des premières images : pixellisation discrète, mais visible sur les contours ET dans les zones ombrées ; petits amas irréguliers, contours un peu cassés et pas parfaitement lissés, texture peinte, dégradés fragmentés. Éviter le gros sprite 8-bit comme le rendu trop propre/vectoriel. Ambiance sombre, sujet bien éclairé et lisible, luminosité cohérente entre familles. Ce style et les contraintes PNG sont inclus dans chaque bloc autonome.

## Références validées à conserver

Pour ces images, ne pas générer de nouveau fichier. Les couleurs décrivent leurs
repères visuels et servent à garder les futures évolutions cohérentes. Les PNG
restent aussi des références de pixel art, de matière et de luminosité.

### Aléators — N1 conservés

Palette commune : chair ivoire et rose, pourpre sombre et noir ; accents rouge
carmin et or/cuivre selon l'objet de jeu. Le rose vif reste localisé aux plaies,
aux yeux ou aux pointes.

- **Dévoracle** (`f01_n1.png`) : cube de chair ivoire rosé, points noirs,
  yeux et fissures carmin ; contraste fort entre chair claire et gueules noires.
- **Griffe à jetons** (`f02_n1.png`) : chair rose pâle, griffes rouge sombre,
  reflets dorés/cuivrés des jetons.
- **Dé boiteux** (`f03_n1.png`) : faces ivoire sale et points noirs, chair
  rose violacé, bouche sombre.
- **Sou ricanant** (`f04_n1.png`) : cuivre et or ternis, brun-noir dans la
  tranche, dents ivoire et reflets rouge sombre.
- **Roulette vorace** (`f06_n1.png`) : rouge profond et noir autour de la
  roulette, détails d'or vieilli.
- **Jumeau de cuivre** (`f07_n1.png`) : cuivre oxydé, brun presque noir et
  reflets or chaud.
- **Valet à l'envers** (`f08_n1.png`) : ivoire de carte, noir et rouge vin,
  avec une chair rosée en accents.

Style à préserver : petits êtres ou objets de jeu rendus comme des créatures,
anatomie charnue inquiétante, contrastes nets, pixels visibles dans les aplats
et contours en escalier irréguliers. Ne pas transformer les signes de casino en
fond ou en accessoires flottants.

### Flétris — N1 conservés

Palette commune : os et chair gris-beige desséchés, ombres prune/violet,
cendre brune ; spores et yeux en violet plus lumineux, jamais en halo général.

- **Porte-fièvre** (`d01_n1.png`) : os ivoire sale, chair grise, violet
  saturé dans les zones contaminées.
- **Crache-cendre** (`d02_n1.png`) : gris cendre, brun de suie et violet
  maladif.
- **Clochelet malade** (`d03_n1.png`) : chair pâle, tissus bruns et cloches
  violettes.
- **Mâchoire moisie** (`d04_n1.png`) : os beige, chair gris-brun, moisissure
  prune.
- **Veuve des spores** (`d05_n1.png`) : voile gris-beige et silhouette prune,
  spores violettes.
- **Sonneur pestiféré** (`d06_n1.png`) : os pâle, tissus bruns, spores
  violet vif localisées.
- **Ronge-chair** (`d08_n1.png`) : chair desséchée beige et brune, morsures
  rouge sombre et bourgeons violacés.
- **Porte-cercueil** (`d09_n1.png`) : enveloppe funéraire brune et grise,
  os ivoire, spores violettes.
- **Exception supplémentaire : Porte-fièvre N4** (`d01_n4.png`) est aussi
  conservé.

Style à préserver : anatomie décharnée et irrégulière, matières mates, creux
profonds, motifs de maladie organiques. La contamination doit sembler pousser
du corps ; ne pas la rendre propre, géométrique ou confondable avec un nid
d'insectes.

### Remparts — N1 conservés

Palette commune : basalte gris charbon, pierre gris ardoise et os ivoire ;
plaques rouille/cuivre et fissures turquoise limitées à quelques détails.

- **Éclat cuirassé** (`r01_n1.png`) : pierre sombre, éclats ivoire et petite
  lueur turquoise.
- **Heaume errant** (`r02_n1.png`) : fer gris et noir, reflets froids,
  lueur interne turquoise.
- **Carapace vide** (`r03_n1.png`) : coque minérale gris-brun, intérieur
  noir et reflets ivoire.
- **Osselet blindé** (`r04_n1.png`) : os pâle sous une armure gris charbon,
  accents turquoise.
- **Chevalier sans visage** (`r05_n1.png`) : métal noir et gris, vide facial
  sombre, arêtes ivoire.
- **Golem de faïence** (`r06_n1.png`) : céramique ivoire cassée, ombres grises
  et fissures froides.
- **Portail d'os** (`r07_n1.png`) : os beige et gris, pièces d'armure
  sombres et rouille.
- **Colosse riveté** (`r08_n1.png`) : pierre gris charbon, plaques de fer
  rouillé et rivets cuivrés.
- **Reliquaire ambulant** (`r09_n1.png`) : pierre sombre, reliques osseuses
  ivoire et lueurs turquoise discrètes.
- **Sarcophage debout** (`r11_n1.png`) : pierre et métal gris, intérieur
  noir, marques d'os pâle.
- **Gardien des décombres** (`r12_n1.png`) : amas gris charbon, os ivoire,
  quelques plaques rouille.

Style à préserver : masses lourdes, angles brisés, texture de pierre/armure
pixellisée et centre de gravité bas. L'accent turquoise est ponctuel, pas une
émission lumineuse qui recouvre toute l'image.

### Veilleurs — N1 communs, rares et épiques conservés

N1 conservés : **Longuépine** (`h01_n1.png`), **Pique-en-haut**
(`h02_n1.png`), **Fauche-fond** (`h03_n1.png`), **Bouche-arbalète**
(`h04_n1.png`), **Échassier des brumes** (`h05_n1.png`), **Veilleur bifurqué**
(`h06_n1.png`), **Perce-voûte** (`h07_n1.png`), **Dard de traverse**
(`h08_n1.png`), **L'Œil empalé** (`h09_n1.png`) et **Le Guetteur trifide**
(`h10_n1.png`).

Palette commune à ces dix images : bleu nuit et cobalt, os ivoire, ombres
bleu-noir et accents bleu électrique concentrés dans l'œil ou la pointe. Style
élancé, directionnel, pixel art aux contours dentelés ; la lumière froide
souligne le regard et les armes organiques, sans éclairer un décor.

### Essaim — N1 conservés

Palette commune : vert olive et vert feuille assourdi, racines brun sombre,
ambre/miel pour les rayures et les yeux ; les verts restent lisibles sur des
ombres brunes.

- **Nœud vivant** (`e01_n1.png`) : fibres brun racine, lianes vert olive et
  petite gueule ambre.
- **Larve d'ancrage** (`e02_n1.png`) : corps vert sombre, abdomen brun, détails
  ambre.
- **Bourgeon mordant** (`e04_n1.png`) : bois brun, feuillage olive et gueule
  jaune-ambre.
- **Ronce rampante** (`e08_n1.png`) : racines brunes, ronces vert sombre et
  arêtes végétales plus claires.

Style à préserver : fibres entrelacées, segments organiques, pixel art rugueux.
L'Essaim paraît vivant et fonctionnel ; ne pas ajouter de moisissure violette
ou de pièces mécaniques.

### Assimilateurs — N1 communs et rares, et N1 du Démonteur conservés

Les N1 conservés sont les cartes **P01 à P08** — Collecteur de dents, Scie
boiteuse, Pince-carcasse, Dépeceur rampant, Recycleur thoracique, Préleveur de
plaques, Chirurgien d'acier et Porte-greffes — ainsi que **Le Démonteur N1**
(`p09_n1.png`).

Palette commune : métal charbon/noir, cuivre et rouille, os ivoire récupéré,
petites sources orange incandescent. Les arêtes métalliques sont irrégulières
et usées ; câbles et articulations doivent rester lisibles.

- **Collecteur de dents** (`p01_n1.png`) : mâchoire en métal noirci, dents
  ivoire, cuivre et points orange.
- **Scie boiteuse** (`p02_n1.png`) : châssis charbon, scie acier gris,
  articulations cuivre et lueur orange.
- **Pince-carcasse** (`p03_n1.png`) : carcasse sombre, pinces de fer et
  pièces osseuses ivoire.
- **Dépeceur rampant** (`p04_n1.png`) : métal noir et brun rouille, lames gris
  acier et petits accents orange.
- **Recycleur thoracique** (`p05_n1.png`) : plaques métal noirci, cuivre
  oxydé et cavité orange.
- **Préleveur de plaques** (`p06_n1.png`) : acier sombre, cuivre et pièces
  ivoire récupérées.
- **Chirurgien d'acier** (`p07_n1.png`) : colonne noir charbon, instruments
  acier et lumière orange ponctuelle.
- **Porte-greffes** (`p08_n1.png`) : carcasse brun-noir, cuivre rouillé,
  membres pâles greffés et lueur orange.
- **Le Démonteur N1** (`p09_n1.png`) : châssis brun-noir, cuivre rouillé,
  pinces et mécanique couleur acier sombre.

Style à préserver : machine lisible construite autour d'un outil dominant, pixel
art dense avec reflets en petits groupes de pixels. Ne pas confondre avec un
golem des Remparts : ici, les articulations, câbles et pièces récupérées doivent
être visibles.

### Neutres — N1 conservés

- **Mordeur des combles** (`n02_n1.png`) : os beige, brun grisâtre et gueule
  rouge-brun très sombre ; silhouette suspendue.
- **Rampant des fosses** (`n03_n1.png`) : tons terreux gris-brun, ventre plus
  pâle et gueule noire dentée.
- **Mâche-mur** (`n07_n1.png`) : chair gris-brun, yeux et pustules sombres,
  bouches rouge sang atténué.

Leur style reste celui du reste du jeu, sans motif de famille reconnaissable :
pas de casino, de spores violettes dominantes, de réseau végétal ou de pièces
mécaniques.

## Prompts des six dieux

Chaque bloc est complet et autonome : copier le bloc entier dans le champ positif Fooocus.


### Véskar — le Manipulateur

`veskar.png`

```text
Torsoless ivory living dice head, multiple large eyes and seductive evil smile. Numerous fleshy hands emerge directly below the head; each is attached to the body and holds an identifiable casino object: a coherent deck of cards, a small roulette wheel, chips and a small slot machine. Compact silhouette, no floating objects. Family identity: Cursed Casino Creature; any game objects are held or fused to the body. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; dangerous seduction and cursed casino. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Nérava — la Mère des Fièvres

`nerava.png`

```text
Ancient figure, emaciated and withered, shrouded in a torn veil of ash-colored fungal tissue. Organic growths like funerary bells hang from the shoulders and back; a few purple spores grow in the cracked skin. Long bony hands, face partially hidden. Organic disease, not a hive. Family identity: Sick and withered creature; spores and growths grow from its anatomy. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; miasma and organic contamination. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Kharûn — la Muraille

`kharun.png`

```text
Unified basalt titan with monumental shoulders; small sunken stone head, hollow eye sockets and black vertical mouth. Bones and fragments of broken armor embedded in rock as protection. Anchored posture, large defensive volumes, no mechanism. Family identity: Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; mineral mass, defense and stability. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Ilyr — le Guetteur Éternel

`ilyr.png`

```text
Non-human living observatory, tall and suspended around a large horizontal eye. Two curved and taut organic appendages frame the eye like an arc; three slender extensions similar to spears replace legs. Gaze directed towards an off-camera target, slender and asymmetrical silhouette. Family identity: Slender organic predator, focused on gaze and projecting appendages. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; central gaze and organic projection weapons. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Sylkha — la Mère-Ruche

`sylkha.png`

```text
Plant queen bee with erect thorax, striped abdomen, crown of rigid petals and plant-veined wings. A trail of roots distinct from its limbs descends beneath its body; amber eyes and well-defined insectoid limbs. No metal or purple contamination. Family identity: An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; plant organism, colony and living roots. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Énigma — la Machine Première

`enigma.png`

```text
Monumental horrific industrial machine, compact central torso on four connected supports. Severe mask, huge crushing clamp and large suction or collection arm. Plates recovered around a legible chassis, visible cables and joints, small orange incandescent heart. Consistent mechanics, no floating parts. Family identity: Horrific salvage machine with tools, cables, and joints connected to its chassis. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Dominant palette, with slight freedom for tonal nuance and material readability without changing the family identity. Immediately recognizable as a god and more imposing than an ordinary monster; living machine, recovery and absorption. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


## Prompts autonomes des cartes à recréer

Chaque bloc est un prompt positif complet pour un fichier précis. Les niveaux absents sont les références à conserver ; le sujet, sa palette, son évolution, le style, le cadrage et le format sont décrits dans chaque bloc. Aucun contexte ou image antérieure n’est nécessaire.


### Neutres


#### `n01_n1.png` — Avortons des caves, N1

```text
A standalone monster with no visual traits from another family. Appearance: Small, stocky goblins in hordes, mischievous faces and disproportionate limbs. Level-specific evolution and pose: group of 3 little goblins. Dominant colors: gray-beige skin #9B8C78, earth #51453C, bone #D0C0A2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n01_n2.png` — Avortons des caves, N2

```text
A standalone monster with no visual traits from another family. Appearance: Small, stocky goblins in hordes, mischievous faces and disproportionate limbs. Level-specific evolution and pose: 6 goblins, more agitated silhouettes. Dominant colors: gray-beige skin #9B8C78, earth #51453C, bone #D0C0A2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n01_n3.png` — Avortons des caves, N3

```text
A standalone monster with no visual traits from another family. Appearance: Small, stocky goblins in hordes, mischievous faces and disproportionate limbs. Level-specific evolution and pose: 9 goblins in a chaotic but readable cluster. Dominant colors: gray-beige skin #9B8C78, earth #51453C, bone #D0C0A2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n01_n4.png` — Avortons des caves, N4

```text
A standalone monster with no visual traits from another family. Appearance: Small, stocky goblins in hordes, mischievous faces and disproportionate limbs. Level-specific evolution and pose: 12 goblins, threat of dense horde, separate silhouettes and without decoration. Dominant colors: gray-beige skin #9B8C78, earth #51453C, bone #D0C0A2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n02_n2.png` — Mordeur des combles, N2

```text
A standalone monster with no visual traits from another family. Appearance: Hanging mouth, with no body clearly visible at first; superimposed jaws. Level-specific evolution and pose: muscular neck begins to emerge behind the mouth. Dominant colors: bone beige #D8C8A8, brown gray #6C5B4D, mouth #3C2928. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n02_n3.png` — Mordeur des combles, N3

```text
A standalone monster with no visual traits from another family. Appearance: Hanging mouth, with no body clearly visible at first; superimposed jaws. Level-specific evolution and pose: predator with thick neck, two legible jaws. Dominant colors: bone beige #D8C8A8, brown gray #6C5B4D, mouth #3C2928. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n02_n4.png` — Mordeur des combles, N4

```text
A standalone monster with no visual traits from another family. Appearance: Hanging mouth, with no body clearly visible at first; superimposed jaws. Level-specific evolution and pose: long powerful neck and superimposed mouths dominate the entire silhouette. Dominant colors: bone beige #D8C8A8, brown gray #6C5B4D, mouth #3C2928. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n03_n2.png` — Rampant des fosses, N2

```text
A standalone monster with no visual traits from another family. Appearance: Toothed burrowing worm, ringed earthy skin and large mouth. Level-specific evolution and pose: longer worm, first hard plates and enlarged mouth. Dominant colors: earth gray-brown #736B5D, pale belly #B7A58B, mouth #292526. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n03_n3.png` — Rampant des fosses, N3

```text
A standalone monster with no visual traits from another family. Appearance: Toothed burrowing worm, ringed earthy skin and large mouth. Level-specific evolution and pose: serpentiform body erect in S, thick rings. Dominant colors: earth gray-brown #736B5D, pale belly #B7A58B, mouth #292526. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n03_n4.png` — Rampant des fosses, N4

```text
A standalone monster with no visual traits from another family. Appearance: Toothed burrowing worm, ringed earthy skin and large mouth. Level-specific evolution and pose: large burrowing snake, gigantic mouth open, body folded into the frame. Dominant colors: earth gray-brown #736B5D, pale belly #B7A58B, mouth #292526. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n04_n1.png` — Gueule-de-travers, N1

```text
A standalone monster with no visual traits from another family. Appearance: Low carnivorous, asymmetrical, jaw offset laterally. Level-specific evolution and pose: small beast with mouth already slightly off-center. Dominant colors: flesh gray-beige #A8907E, charcoal #332C2B, plum #67404A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n04_n2.png` — Gueule-de-travers, N2

```text
A standalone monster with no visual traits from another family. Appearance: Low carnivorous, asymmetrical, jaw offset laterally. Level-specific evolution and pose: jaw begins to slide to the side. Dominant colors: flesh gray-beige #A8907E, charcoal #332C2B, plum #67404A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n04_n3.png` — Gueule-de-travers, N3

```text
A standalone monster with no visual traits from another family. Appearance: Low carnivorous, asymmetrical, jaw offset laterally. Level-specific evolution and pose: very visible shift, tilted head and asymmetrical shoulders. Dominant colors: flesh gray-beige #A8907E, charcoal #332C2B, plum #67404A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n04_n4.png` — Gueule-de-travers, N4

```text
A standalone monster with no visual traits from another family. Appearance: Low carnivorous, asymmetrical, jaw offset laterally. Level-specific evolution and pose: entire silhouette twisted around a huge side jaw. Dominant colors: flesh gray-beige #A8907E, charcoal #332C2B, plum #67404A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n05_n1.png` — Ogre droitier, N1

```text
A standalone monster with no visual traits from another family. Appearance: Massive ogre, gray-brown skin, dominant right arm clearly more developed than the left. Level-specific evolution and pose: stocky ogre, right arm a little too big. Dominant colors: brown skin #78634F, shadows #3B302A, bones #B8A487. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n05_n2.png` — Ogre droitier, N2

```text
A standalone monster with no visual traits from another family. Appearance: Massive ogre, gray-brown skin, dominant right arm clearly more developed than the left. Level-specific evolution and pose: right arm becomes a heavy striking limb. Dominant colors: brown skin #78634F, shadows #3B302A, bones #B8A487. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n05_n3.png` — Ogre droitier, N3

```text
A standalone monster with no visual traits from another family. Appearance: Massive ogre, gray-brown skin, dominant right arm clearly more developed than the left. Level-specific evolution and pose: oversized arm-arming, leaning posture of one's weight. Dominant colors: brown skin #78634F, shadows #3B302A, bones #B8A487. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n05_n4.png` — Ogre droitier, N4

```text
A standalone monster with no visual traits from another family. Appearance: Massive ogre, gray-brown skin, dominant right arm clearly more developed than the left. Level-specific evolution and pose: unbalanced colossus whose monstrous right arm becomes the focal point. Dominant colors: brown skin #78634F, shadows #3B302A, bones #B8A487. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n06_n1.png` — Le Drapé du seuil, N1

```text
A standalone monster with no visual traits from another family. Appearance: Legless ghost under a torn veil; twisted sides around a black opening. Level-specific evolution and pose: compact veil, small dark opening. Dominant colors: sepia veil #C5B8A0, smoked pleats #6E5B50, black opening #131214. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n06_n2.png` — Le Drapé du seuil, N2

```text
A standalone monster with no visual traits from another family. Appearance: Legless ghost under a torn veil; twisted sides around a black opening. Level-specific evolution and pose: longer sides that roll up. Dominant colors: sepia veil #C5B8A0, smoked pleats #6E5B50, black opening #131214. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n06_n3.png` — Le Drapé du seuil, N3

```text
A standalone monster with no visual traits from another family. Appearance: Legless ghost under a torn veil; twisted sides around a black opening. Level-specific evolution and pose: veil deployed in asymmetrical twists, larger opening. Dominant colors: sepia veil #C5B8A0, smoked pleats #6E5B50, black opening #131214. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n06_n4.png` — Le Drapé du seuil, N4

```text
A standalone monster with no visual traits from another family. Appearance: Legless ghost under a torn veil; twisted sides around a black opening. Level-specific evolution and pose: ample appearance whose sides form a spiral around the central black void. Dominant colors: sepia veil #C5B8A0, smoked pleats #6E5B50, black opening #131214. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n07_n2.png` — Mâche-mur, N2

```text
A standalone monster with no visual traits from another family. Appearance: Organic mass without human anatomy, covered with dark red eyes, pustules and mouths. Level-specific evolution and pose: more eyes grouped around a main mouth. Dominant colors: gray-brown flesh #78685F, eyes #211C1B, dark red mouths #773F43. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n07_n3.png` — Mâche-mur, N3

```text
A standalone monster with no visual traits from another family. Appearance: Organic mass without human anatomy, covered with dark red eyes, pustules and mouths. Level-specific evolution and pose: higher mass, pustules open into small jaws. Dominant colors: gray-brown flesh #78685F, eyes #211C1B, dark red mouths #773F43. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n07_n4.png` — Mâche-mur, N4

```text
A standalone monster with no visual traits from another family. Appearance: Organic mass without human anatomy, covered with dark red eyes, pustules and mouths. Level-specific evolution and pose: compact cluster of faces and eyes, unique and readable silhouette. Dominant colors: gray-brown flesh #78685F, eyes #211C1B, dark red mouths #773F43. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n08_n1.png` — Écorche-angle, N1

```text
A standalone monster with no visual traits from another family. Appearance: Pale, hunched climber with uneven shoulders and hinged limbs for hanging at impossible angles. Level-specific evolution and pose: small creature crouching on four angular supports. Dominant colors: gray skin #B3A590, earth #51443B, off-purple #71575B. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n08_n2.png` — Écorche-angle, N2

```text
A standalone monster with no visual traits from another family. Appearance: Pale, hunched climber with uneven shoulders and hinged limbs for hanging at impossible angles. Level-specific evolution and pose: longer limbs and protruding elbows. Dominant colors: gray skin #B3A590, earth #51443B, off-purple #71575B. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n08_n3.png` — Écorche-angle, N3

```text
A standalone monster with no visual traits from another family. Appearance: Pale, hunched climber with uneven shoulders and hinged limbs for hanging at impossible angles. Level-specific evolution and pose: broken back at an angle, asymmetrical arms and legs. Dominant colors: gray skin #B3A590, earth #51443B, off-purple #71575B. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n08_n4.png` — Écorche-angle, N4

```text
A standalone monster with no visual traits from another family. Appearance: Pale, hunched climber with uneven shoulders and hinged limbs for hanging at impossible angles. Level-specific evolution and pose: spidery silhouette folded around its own joints, without decoration. Dominant colors: gray skin #B3A590, earth #51443B, off-purple #71575B. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n24_n1.png` — Le Sac à murmures, N1

```text
A standalone monster with no visual traits from another family. Appearance: Pale skin envelope swollen by an interior presence, bumps growing from within and small breath opening. Level-specific evolution and pose: knotted skin bag, barely visible presence. Dominant colors: beige skin #B7A493, plum-brown shadows #56433F, brands #76545A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n24_n2.png` — Le Sac à murmures, N2

```text
A standalone monster with no visual traits from another family. Appearance: Pale skin envelope swollen by an interior presence, bumps growing from within and small breath opening. Level-specific evolution and pose: two internal shapes push back the skin. Dominant colors: beige skin #B7A493, plum-brown shadows #56433F, brands #76545A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n24_n3.png` — Le Sac à murmures, N3

```text
A standalone monster with no visual traits from another family. Appearance: Pale skin envelope swollen by an interior presence, bumps growing from within and small breath opening. Level-specific evolution and pose: tighter envelope, several bumps and a face in relief transparency. Dominant colors: beige skin #B7A493, plum-brown shadows #56433F, brands #76545A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n24_n4.png` — Le Sac à murmures, N4

```text
A standalone monster with no visual traits from another family. Appearance: Pale skin envelope swollen by an interior presence, bumps growing from within and small breath opening. Level-specific evolution and pose: almost humanoid bag under tension, top knot and disturbing silhouette. Dominant colors: beige skin #B7A493, plum-brown shadows #56433F, brands #76545A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n09_n1.png` — Charognard courbe, N1

```text
A standalone monster with no visual traits from another family. Appearance: Crescent-shaped predator, open bony cage and hooked skull. Level-specific evolution and pose: small curved body, skull and bony claws. Dominant colors: bone beige #C4B69D, charcoal #413931, dry brown #75624E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n09_n2.png` — Charognard courbe, N2

```text
A standalone monster with no visual traits from another family. Appearance: Crescent-shaped predator, open bony cage and hooked skull. Level-specific evolution and pose: more pronounced back arch, visible rib cage. Dominant colors: bone beige #C4B69D, charcoal #413931, dry brown #75624E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n09_n3.png` — Charognard courbe, N3

```text
A standalone monster with no visual traits from another family. Appearance: Crescent-shaped predator, open bony cage and hooked skull. Level-specific evolution and pose: large crescent-shaped predator, dominant hooked skull. Dominant colors: bone beige #C4B69D, charcoal #413931, dry brown #75624E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n10_n1.png` — Tricorne errant, N1

```text
A standalone monster with no visual traits from another family. Appearance: Bony three-horned beast, low body, protective shoulders. Level-specific evolution and pose: three small irregular horns. Dominant colors: aged bone #C9B89A, stone #625B54, brown #594331. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n10_n2.png` — Tricorne errant, N2

```text
A standalone monster with no visual traits from another family. Appearance: Bony three-horned beast, low body, protective shoulders. Level-specific evolution and pose: thickened bony shoulders, longer horns. Dominant colors: aged bone #C9B89A, stone #625B54, brown #594331. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n10_n3.png` — Tricorne errant, N3

```text
A standalone monster with no visual traits from another family. Appearance: Bony three-horned beast, low body, protective shoulders. Level-specific evolution and pose: massive beast, three distinct horns, shoulders like a natural shield. Dominant colors: aged bone #C9B89A, stone #625B54, brown #594331. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n11_n1.png` — Dos-fendu, N1

```text
A standalone monster with no visual traits from another family. Appearance: Dark boar, open or split back, emerging tusks. Level-specific evolution and pose: small furrow-backed boar. Dominant colors: brown coat #514037, dusty skin #8C6254, ivory tusks #D8C9AE. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n11_n2.png` — Dos-fendu, N2

```text
A standalone monster with no visual traits from another family. Appearance: Dark boar, open or split back, emerging tusks. Level-specific evolution and pose: larger boar, visible dorsal slit and first horns. Dominant colors: brown coat #514037, dusty skin #8C6254, ivory tusks #D8C9AE. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n11_n3.png` — Dos-fendu, N3

```text
A standalone monster with no visual traits from another family. Appearance: Dark boar, open or split back, emerging tusks. Level-specific evolution and pose: large boar bristling with horns, massive tusks and split back. Dominant colors: brown coat #514037, dusty skin #8C6254, ivory tusks #D8C9AE. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n12_n1.png` — Le Nœud hurlant, N1

```text
A standalone monster with no visual traits from another family. Appearance: Long ribbon of dark flesh tied several times around an inner maw. Level-specific evolution and pose: tight ribbon, small mouth in the center of the knot. Dominant colors: faded flesh #987A70, burgundy #482D33, ivory teeth #D7C8B3. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n12_n2.png` — Le Nœud hurlant, N2

```text
A standalone monster with no visual traits from another family. Appearance: Long ribbon of dark flesh tied several times around an inner maw. Level-specific evolution and pose: more complex knot, gaping central mouth. Dominant colors: faded flesh #987A70, burgundy #482D33, ivory teeth #D7C8B3. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n12_n3.png` — Le Nœud hurlant, N3

```text
A standalone monster with no visual traits from another family. Appearance: Long ribbon of dark flesh tied several times around an inner maw. Level-specific evolution and pose: large interlacing of flesh, screaming inner mouth as the only focus. Dominant colors: faded flesh #987A70, burgundy #482D33, ivory teeth #D7C8B3. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n13_n1.png` — La Veuve suspendue, N1

```text
A standalone monster with no visual traits from another family. Appearance: Female appearance with no legs, long hair, clawed hands and hanging body. Level-specific evolution and pose: veiled silhouette and short hair. Dominant colors: spectral skin #BEB0A2, hair #352B2D, plum veil #674A55. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n13_n2.png` — La Veuve suspendue, N2

```text
A standalone monster with no visual traits from another family. Appearance: Female appearance with no legs, long hair, clawed hands and hanging body. Level-specific evolution and pose: hair and arms lengthen, fingers hooked. Dominant colors: spectral skin #BEB0A2, hair #352B2D, plum veil #674A55. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n13_n3.png` — La Veuve suspendue, N3

```text
A standalone monster with no visual traits from another family. Appearance: Female appearance with no legs, long hair, clawed hands and hanging body. Level-specific evolution and pose: floating appearance, hair forming a wide arc around the clawed hands. Dominant colors: spectral skin #BEB0A2, hair #352B2D, plum veil #674A55. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n14_n1.png` — Ogre à deux bouches, N1

```text
A standalone monster with no visual traits from another family. Appearance: Twisted ogre, one jaw on the face and a second mouth offset on the torso or shoulder. Level-specific evolution and pose: curved ogre, discreet second mouth. Dominant colors: gray skin #887362, gules #422D2D, irritated flesh #744648. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n14_n2.png` — Ogre à deux bouches, N2

```text
A standalone monster with no visual traits from another family. Appearance: Twisted ogre, one jaw on the face and a second mouth offset on the torso or shoulder. Level-specific evolution and pose: secondary jaw well open on the torso. Dominant colors: gray skin #887362, gules #422D2D, irritated flesh #744648. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n14_n3.png` — Ogre à deux bouches, N3

```text
A standalone monster with no visual traits from another family. Appearance: Twisted ogre, one jaw on the face and a second mouth offset on the torso or shoulder. Level-specific evolution and pose: two independent mouths in distinct places, twisted posture. Dominant colors: gray skin #887362, gules #422D2D, irritated flesh #744648. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n15_n1.png` — Fouisseur aveugle, N1

```text
A standalone monster with no visual traits from another family. Appearance: Pale, massive borer, absent or sealed eyes, long digging claws. Level-specific evolution and pose: low body, claws already long. Dominant colors: pale skin #B7ADA0, earth #594B42, ivory claws #D8CCB6. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n15_n2.png` — Fouisseur aveugle, N2

```text
A standalone monster with no visual traits from another family. Appearance: Pale, massive borer, absent or sealed eyes, long digging claws. Level-specific evolution and pose: shoulders and forearms reinforced by the earth. Dominant colors: pale skin #B7ADA0, earth #594B42, ivory claws #D8CCB6. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n15_n3.png` — Fouisseur aveugle, N3

```text
A standalone monster with no visual traits from another family. Appearance: Pale, massive borer, absent or sealed eyes, long digging claws. Level-specific evolution and pose: heavy driller, shovel claws and blind smooth face. Dominant colors: pale skin #B7ADA0, earth #594B42, ivory claws #D8CCB6. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n16_n1.png` — Dévoreur de lanternes, N1

```text
A standalone monster with no visual traits from another family. Appearance: Gaunt creature, open ribcage containing stolen light. Level-specific evolution and pose: small skeletal body, weak light in the ribs. Dominant colors: charcoal body #534A45, bone #BDAF99, amber lantern #D68B36. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n16_n2.png` — Dévoreur de lanternes, N2

```text
A standalone monster with no visual traits from another family. Appearance: Gaunt creature, open ribcage containing stolen light. Level-specific evolution and pose: more open ribs, more visible amber glow. Dominant colors: charcoal body #534A45, bone #BDAF99, amber lantern #D68B36. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n16_n3.png` — Dévoreur de lanternes, N3

```text
A standalone monster with no visual traits from another family. Appearance: Gaunt creature, open ribcage containing stolen light. Level-specific evolution and pose: emaciated predator whose ribcage-lantern is the focal point. Dominant colors: charcoal body #534A45, bone #BDAF99, amber lantern #D68B36. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n17_n1.png` — Mille-gueules, N1

```text
A standalone monster with no visual traits from another family. Appearance: Clusters of distinct small mouths, dark flesh and ivory teeth. Level-specific evolution and pose: small cluster still separated into several mouths. Dominant colors: plum-brown flesh #40323A and #82656A, teeth #D7C9B2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n17_n2.png` — Mille-gueules, N2

```text
A standalone monster with no visual traits from another family. Appearance: Clusters of distinct small mouths, dark flesh and ivory teeth. Level-specific evolution and pose: The mouths merge into a single compact creature with a main mouth. Dominant colors: plum-brown flesh #40323A and #82656A, teeth #D7C9B2. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n18_n1.png` — L'Affamé du puits, N1

```text
A standalone monster with no visual traits from another family. Appearance: Hungry face emerging from a stone ledge, then emaciated body clinging to the ledge. Level-specific evolution and pose: face alone, bony fingers gripping the edge. Dominant colors: brown-gray stone #65584D, cadaverous skin #A49480, shadow #302B29. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n18_n2.png` — L'Affamé du puits, N2

```text
A standalone monster with no visual traits from another family. Appearance: Hungry face emerging from a stone ledge, then emaciated body clinging to the ledge. Level-specific evolution and pose: complete lean body rises, oversized arms, hungry face dominant. Dominant colors: brown-gray stone #65584D, cadaverous skin #A49480, shadow #302B29. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n19_n1.png` — Le Porte-visages, N1

```text
A standalone monster with no visual traits from another family. Appearance: Smooth humanoid with a face on the thorax and two living profiles on the shoulders. Level-specific evolution and pose: smooth silhouette, slightly open chest face, two side profiles. Dominant colors: gray-beige body #B7AA98, brown faces #463D3A, highlights #D6CCB9. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n19_n2.png` — Le Porte-visages, N2

```text
A standalone monster with no visual traits from another family. Appearance: Smooth humanoid with a face on the thorax and two living profiles on the shoulders. Level-specific evolution and pose: three more expressive and clearly separated faces on a still featureless body. Dominant colors: gray-beige body #B7AA98, brown faces #463D3A, highlights #D6CCB9. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n20_n1.png` — Le Replié, N1

```text
A standalone monster with no visual traits from another family. Appearance: Body bent at impossible angles, face hidden in an anatomical fold. Level-specific evolution and pose: compact folded creature, a single opening in a fold. Dominant colors: gray-beige skin #A99B89, shadows #332D2B, plum flesh #67464C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n20_n2.png` — Le Replié, N2

```text
A standalone monster with no visual traits from another family. Appearance: Body bent at impossible angles, face hidden in an anatomical fold. Level-specific evolution and pose: deeper folds, face which appears between several knotted limbs. Dominant colors: gray-beige skin #A99B89, shadows #332D2B, plum flesh #67464C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n21_n1.png` — Le Voyeur, N1

```text
A standalone monster with no visual traits from another family. Appearance: Flat, irregular black cloud filled with open eyes of varying sizes. Level-specific evolution and pose: two-dimensional shadow cloud, clear and irregularly distributed eyes, no body or decoration. Dominant colors: charcoal cloud #19191D, ivory eyes #E2D9C8, gray iris #87909A. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n22_n1.png` — La Gueule sous le lit, N1

```text
A standalone monster with no visual traits from another family. Appearance: Flattened body almost invisible, mouth much too large protruding from a tiny shape. Level-specific evolution and pose: very low and compact silhouette, large toothed mouth which protrudes from the body. Dominant colors: gray-brown body #36302E, ivory teeth #D8C9B2, red-brown flesh #744448. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `n23_n1.png` — Le Roi des oubliettes, N1

```text
A standalone monster with no visual traits from another family. Appearance: Chained, massive, beastly giant with no armor or mechanics. Level-specific evolution and pose: hunched giant with heavy chains, gray-brown skin, powerful hands and beastly face. Dominant colors: gray-brown skin #665648, shadows #302A27, chains #35363B, ivory scars #B8AA92. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Aléators


#### `f01_n2.png` — Dévoracle, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Fleshy dice, distorted faces, multiple eyes and slit mouths. Level-specific evolution and pose: more inflated cube, new cracks and a side mouth. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f01_n3.png` — Dévoracle, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Fleshy dice, distorted faces, multiple eyes and slit mouths. Level-specific evolution and pose: several living faces and asymmetrical eyes. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f01_n4.png` — Dévoracle, N4

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Fleshy dice, distorted faces, multiple eyes and slit mouths. Level-specific evolution and pose: deformed die almost entirely fleshy, mouths open on several sides. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f02_n2.png` — Griffe à jetons, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living token with a prehensile claw and inlaid coins. Level-specific evolution and pose: claw becomes a forearm, tokens welded to the flesh. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f02_n3.png` — Griffe à jetons, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living token with a prehensile claw and inlaid coins. Level-specific evolution and pose: long arm covered in coins, predatory hand. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f02_n4.png` — Griffe à jetons, N4

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living token with a prehensile claw and inlaid coins. Level-specific evolution and pose: large living arm loaded with tokens, silhouette dominated by the claw. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f03_n2.png` — Dé boiteux, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Wobbly die carried by uneven legs, dominant vertical jaw. Level-specific evolution and pose: more uneven legs, wider vertical mouth. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f03_n3.png` — Dé boiteux, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Wobbly die carried by uneven legs, dominant vertical jaw. Level-specific evolution and pose: inclined body, one leg almost too long. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f03_n4.png` — Dé boiteux, N4

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Wobbly die carried by uneven legs, dominant vertical jaw. Level-specific evolution and pose: unstable cubic beast, vertical jaw occupying almost an entire face. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f04_n2.png` — Sou ricanant, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living coin, terrifying face and edge that opens into a mouth. Level-specific evolution and pose: split edge, first teeth. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f04_n3.png` — Sou ricanant, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living coin, terrifying face and edge that opens into a mouth. Level-specific evolution and pose: a lateral jaw beginning to open. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f04_n4.png` — Sou ricanant, N4

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Living coin, terrifying face and edge that opens into a mouth. Level-specific evolution and pose: deformed penny whose entire edge forms a toothed mouth. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f05_n1.png` — Croupier manchot, N1

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Monstrous amputee dealer, cards held in remaining hand, two jaws at sides of face. Level-specific evolution and pose: small, skinny dealer, two discreet jaws. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f05_n2.png` — Croupier manchot, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Monstrous amputee dealer, cards held in remaining hand, two jaws at sides of face. Level-specific evolution and pose: cards distributed by a long arm, jaws open. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f05_n3.png` — Croupier manchot, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Monstrous amputee dealer, cards held in remaining hand, two jaws at sides of face. Level-specific evolution and pose: imposing croupier figure, two dominant side faces. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f06_n2.png` — Roulette vorace, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Flesh caster with toothed crown, the mechanism seems to devour itself. Level-specific evolution and pose: wider crown of teeth, flesh wrapped around the mechanism. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f06_n3.png` — Roulette vorace, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Flesh caster with toothed crown, the mechanism seems to devour itself. Level-specific evolution and pose: full predatory wheel, deep mouth wheel and flesh body. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f07_n2.png` — Jumeau de cuivre, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Two faces connected by the same piece, opposite on its two sides. Level-specific evolution and pose: more expressive faces, links of flesh around the edge. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f07_n3.png` — Jumeau de cuivre, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Two faces connected by the same piece, opposite on its two sides. Level-specific evolution and pose: two opposing copper faces, piece fused into a double body. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f08_n2.png` — Valet à l'envers, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Hanging card figure, inverted torsos and limbs, suggested jack motif without text. Level-specific evolution and pose: two head-to-tail torsos connected at the center. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f08_n3.png` — Valet à l'envers, N3

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Hanging card figure, inverted torsos and limbs, suggested jack motif without text. Level-specific evolution and pose: complex reverse jack, crossed limbs and living card silhouette. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f09_n1.png` — La Machine à malchance, N1

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Carnivorous slot machine, reels embedded in the body and living lever. Level-specific evolution and pose: small automaton with mouth, three visible symbolic reels. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f09_n2.png` — La Machine à malchance, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Carnivorous slot machine, reels embedded in the body and living lever. Level-specific evolution and pose: higher and more aggressive machine, lever become living member, rollers buried in the flesh. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f10_n1.png` — La Dame aux deux visages, N1

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Gambling lady whose two living profiles turn their backs on each other and never look at each other. Level-specific evolution and pose: elegant worn bust, two side profiles. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f10_n2.png` — La Dame aux deux visages, N2

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Gambling lady whose two living profiles turn their backs on each other and never look at each other. Level-specific evolution and pose: silhouette of a monstrous lady, two autonomous and opposing faces, drapery becoming flesh. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f11_n1.png` — La Banque vivante, N1

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Organic chest, eye as a lock, large mouth and small prisoner rooms. Level-specific evolution and pose: compact living chest, central locking eye, toothed mouth and side openings containing tiny silhouettes. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `f12_n1.png` — Le Dernier Pari, N1

```text
Cursed casino creature; any game objects are held or fused to the body. Appearance: Carnivorous game table, carpet become long body and mouth under the board. Level-specific evolution and pose: elongated coffee table, fleshy carpet, four articulated legs and a mouth under the edge; no readable text. Dominant colors: ivory flesh #E9D7BB, pink #D88791, carmine red #A92F48, plum-black #291822, gold/copper #B77A39. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Flétris


#### `d01_n2.png` — Porte-fièvre, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Infected carrier, organic spore openings and bells. Level-specific evolution and pose: First contaminated openings appear in the body. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d01_n3.png` — Porte-fièvre, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Infected carrier, openings and organic spore bells. Level-specific evolution and pose: several bells/spores reach the back and shoulders. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d02_n2.png` — Crache-cendre, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Beast with a swollen throat, heavy with ash and sick smoke. Level-specific evolution and pose: distended throat, ash visible in the folds. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d02_n3.png` — Crache-cendre, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Beast with a swollen throat, heavy with ash and sick smoke. Level-specific evolution and pose: plume of ash contained around the mouth, more massive body. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d02_n4.png` — Crache-cendre, N4

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Beast with a swollen throat, heavy with ash and sick smoke. Level-specific evolution and pose: deformed beast whose diseased throat and ash deposits dominate. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d03_n2.png` — Clochelet malade, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Curved figure bearing proliferating bells of flesh. Level-specific evolution and pose: two bells grow on the back. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d03_n3.png` — Clochelet malade, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Curved figure bearing proliferating bells of flesh. Level-specific evolution and pose: bigger bells, more arched limbs. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d03_n4.png` — Clochelet malade, N4

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Curved figure bearing proliferating bells of flesh. Level-specific evolution and pose: body almost buried under the organic bells, silhouette still distinct. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d04_n2.png` — Mâchoire moisie, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Fungal predator with two thick, asymmetrical mouths. Level-specific evolution and pose: second mouth opens in the neck. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d04_n3.png` — Mâchoire moisie, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Fungal predator with two thick, asymmetrical mouths. Level-specific evolution and pose: mold spreads to the back, the jaws become thick. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d04_n4.png` — Mâchoire moisie, N4

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Fungal predator with two thick, asymmetrical mouths. Level-specific evolution and pose: two-headed fungal predator, asymmetrical mouths widely open. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d05_n2.png` — Veuve des spores, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Veiled presence, long dried out sections and a trail that becomes a cloud of spores. Level-specific evolution and pose: veil stretches, trail of spores behind the legs. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d05_n3.png` — Veuve des spores, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Veiled presence, long dried out sections and a trail that becomes a cloud of spores. Level-specific evolution and pose: suspended silhouette almost drowned in its contaminated cloud. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d06_n2.png` — Sonneur pestiféré, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Hunched wearer of a hollow bell, torso and back covered in spores. Level-specific evolution and pose: wider bell, sporulated openings in the torso. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d06_n3.png` — Sonneur pestiféré, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Hunched wearer of a hollow bell, torso and back covered in spores. Level-specific evolution and pose: deformed ringer, hollow bell and spore plates covering the back. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d07_n1.png` — Griffe septique, N1

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Infected emaciated, one arm becomes a contaminated contact claw. Level-specific evolution and pose: dry body and a hand with blackened fingers. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d07_n2.png` — Griffe septique, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Infected emaciated, one arm becomes a contaminated contact claw. Level-specific evolution and pose: forearm extended into a claw, purple cracks. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d07_n3.png` — Griffe septique, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Infected emaciated, one arm becomes a contaminated contact claw. Level-specific evolution and pose: disproportionate arm-claw, infection in buds on the shoulder. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d08_n2.png` — Ronge-chair, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Compact beast covered in bite marks, small bud jaws. Level-specific evolution and pose: additional bites and two toothed buds. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d08_n3.png` — Ronge-chair, N3

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Compact beast covered in bite marks, small bud jaws. Level-specific evolution and pose: beast packed under numerous secondary jaws. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d09_n2.png` — Le Porte-cercueil, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Desiccated bearer merging with a spongy burial husk. Level-specific evolution and pose: the coffin envelope welds to the back and swallows part of the bearer. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d10_n1.png` — Le Prêcheur des fièvres, N1

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Preacher with sealed face, jaws that open into the torso. Level-specific evolution and pose: silhouette in dry dress, sewn face and small chest opening. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d10_n2.png` — Le Prêcheur des fièvres, N2

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Preacher with sealed face, jaws that open into the torso. Level-specific evolution and pose: several jaws open in the torso under the still sealed face. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d11_n1.png` — La Cathédrale malade, N1

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Creature bearing a nave of dry flesh, fungal bells and bony buttresses. Level-specific evolution and pose: unique monumental shape, arch of flesh on the back and purple bells, no background architectural decoration. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `d12_n1.png` — Le Dernier Souffle, N1

```text
Sick and withered creature; spores and growths grow from its anatomy. Appearance: Desiccated body exhaling a veil of purple ash. Level-specific evolution and pose: lean silhouette, dry ribcage and breath in a ribbon of purple ashes contained near the mouth. Dominant colors: dirty bone #D2C5AD, gray-beige flesh #A39487, ash #625A5B, plum #493447, purple spores #88549C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Remparts


#### `r01_n2.png` — Éclat cuirassé, N2

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Sheathed core, small golem with thick sides. Level-specific evolution and pose: thickened stone sides, less visible core. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r01_n3.png` — Éclat cuirassé, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Sheathed core, small golem with thick sides. Level-specific evolution and pose: small standing golem with overlapping plates. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r01_n4.png` — Éclat cuirassé, N4

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Sheathed core, small golem with thick sides. Level-specific evolution and pose: stocky stone guard, thick carapace and discreet turquoise cracks. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r02_n2.png` — Heaume errant, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Manned helm, incomplete and unbalanced armor. Level-specific evolution and pose: shoulders and an arm appear under the helm. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r02_n3.png` — Heaume errant, N3

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Manned helm, incomplete and unbalanced armor. Level-specific evolution and pose: incomplete armor torso, weight shifted to one side. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r02_n4.png` — Heaume errant, N4

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Manned helm, incomplete and unbalanced armor. Level-specific evolution and pose: wandering armor complete but asymmetrical, helm still focal point. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r03_n2.png` — Carapace vide, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Hollow shell closed on an absence, thickened then cracked. Level-specific evolution and pose: thicker shell, reduced black opening. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r03_n3.png` — Carapace vide, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Hollow shell closed on an absence, thickened then cracked. Level-specific evolution and pose: segmented carapace and visible cracks. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r03_n4.png` — Carapace vide, N4

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Hollow shell closed on an absence, thickened then cracked. Level-specific evolution and pose: split armored shell, central void always black. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r04_n2.png` — Osselet blindé, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Sheathed knucklebone, future golem with armored leg and massive arm. Level-specific evolution and pose: one leg receives a thick plate. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r04_n3.png` — Osselet blindé, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Sheathed knucklebone, future golem with armored leg and massive arm. Level-specific evolution and pose: opposite arm becomes massive, unbalanced silhouette. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r04_n4.png` — Osselet blindé, N4

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Sheathed knucklebone, future golem with armored leg and massive arm. Level-specific evolution and pose: small complete bone golem, an armored leg and a heavy arm. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r05_n2.png` — Chevalier sans visage, N2

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Faceless spectral armor, protection on both sides. Level-specific evolution and pose: armor becomes denser, helmet always empty. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r05_n3.png` — Chevalier sans visage, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Faceless spectral armor, protection on both sides. Level-specific evolution and pose: complete frontal and dorsal plates, heavy appearance without a face. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r06_n2.png` — Golem de faïence, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Golem of shards and ceramics, asymmetrical masses. Level-specific evolution and pose: new articulated shards, an overhanging shoulder. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r06_n3.png` — Golem de faïence, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Golem of shards and ceramics, asymmetrical masses. Level-specific evolution and pose: tall and irregular golem, broken ceramic and sharp cracks. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r07_n2.png` — Portail d'os, N2

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Living arch of bones, uprights and crossbars of armor forming the body. Level-specific evolution and pose: thicker uprights, additional crosspieces. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r07_n3.png` — Portail d'os, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Living arch of bones, uprights and crossbars of armor forming the body. Level-specific evolution and pose: imposing animated bone arch, readable central opening and defensive plates. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r08_n2.png` — Colosse riveté, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Stone colossus covered in riveted plates. Level-specific evolution and pose: wider torso, more riveted plates. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r08_n3.png` — Colosse riveté, N3

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Stone colossus covered in riveted plates. Level-specific evolution and pose: massive colossus, armored shoulders and prominent rivets. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r09_n2.png` — Le Reliquaire ambulant, N2

```text
Heavy, grounded, defensive creature formed from stone, bone, or a single unified armor shell. Appearance: Reliquary on legs, stone, bones and plates; procession embodied in a single body. Level-specific evolution and pose: reliquary becomes compact procession, legs and plates more massive. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r10_n1.png` — Le Bastion fendu, N1

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Manned mace split on an angle, carried by two armor forearms. Level-specific evolution and pose: living block broken on a corner, two armored arms serve as supports. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `r10_n2.png` — Le Bastion fendu, N2

```text
Heavy, grounded, defensive creature constructed of stone, bone, or unified armor. Appearance: Manned mace split on an angle, carried by two armor forearms. Level-specific evolution and pose: higher bastion, gaping crack and thickened supporting forearms. Dominant colors: basalt #34363B, slate #65666A, ivory bone #D8CFB9, rust/copper #945A3B, turquoise #348B89. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Veilleurs


#### `h01_n2.png` — Longuépine, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Predator whose forearm transforms into a long lance of cartilage. Level-specific evolution and pose: forearm spear lengthens and hardens. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h01_n3.png` — Longuépine, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Predator whose forearm transforms into a long lance of cartilage. Level-specific evolution and pose: spear arm crosses the silhouette, hunter posture. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h01_n4.png` — Longuépine, N4

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Predator whose forearm transforms into a long lance of cartilage. Level-specific evolution and pose: long predator with dominant cartilage tip, rear limbs outstretched. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h02_n2.png` — Pique-en-haut, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Living torso carrying a vertical shaft protruding from the skull. Level-specific evolution and pose: longer shaft, shoulders rise. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h02_n3.png` — Pique-en-haut, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Living torso carrying a vertical shaft protruding from the skull. Level-specific evolution and pose: body erect around the vertical axis. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h02_n4.png` — Pique-en-haut, N4

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Living torso carrying a vertical shaft protruding from the skull. Level-specific evolution and pose: very high sentinel, staff integrated into the skull and stretched silhouette. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h03_n2.png` — Fauche-fond, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Raised watchman, a pike descends under the body. Level-specific evolution and pose: body rises above the point. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h03_n3.png` — Fauche-fond, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Raised watchman, a pike descends under the body. Level-specific evolution and pose: long lower pike, suspended silhouette. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h03_n4.png` — Fauche-fond, N4

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Raised watchman, a pike descends under the body. Level-specific evolution and pose: creature at height whose spear descends well below its body. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h04_n2.png` — Bouche-arbalète, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Tubular mouth becoming an organic lateral projection mechanism. Level-specific evolution and pose: mouth lengthens into a tube and opens to the side. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h04_n3.png` — Bouche-arbalète, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Tubular mouth becoming an organic lateral projection mechanism. Level-specific evolution and pose: arcs of cartilage frame the tube. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h04_n4.png` — Bouche-arbalète, N4

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Tubular mouth becoming an organic lateral projection mechanism. Level-specific evolution and pose: complete muzzle-crossbow mechanism, organic projectile ready to go. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h05_n2.png` — Échassier des brumes, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Wading hunter, long legs, forearms in overlapping blades. Level-specific evolution and pose: longer legs, doubled forearm blades. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h05_n3.png` — Échassier des brumes, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Wading hunter, long legs, forearms in overlapping blades. Level-specific evolution and pose: tall hunter silhouette, superimposed blades and fixed gaze. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h06_n2.png` — Veilleur bifurqué, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Predator carrying two divergent lateral stingers. Level-specific evolution and pose: two darts move further away from the skull. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h06_n3.png` — Veilleur bifurqué, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Predator carrying two divergent lateral stingers. Level-specific evolution and pose: thick branches-spears, body centered between them. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h07_n2.png` — Perce-voûte, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Upright creature, vertical beak and solid legs. Level-specific evolution and pose: beak extends upwards, torso anchored. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h07_n3.png` — Perce-voûte, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Upright creature, vertical beak and solid legs. Level-specific evolution and pose: large arch borer with massive vertical beak and legs like pillars. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h08_n2.png` — Dard de traverse, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Oblique hunter, large organic shaft and contact claw. Level-specific evolution and pose: longer diagonal shaft, more visible claw. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h08_n3.png` — Dard de traverse, N3

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Oblique hunter, large organic shaft and contact claw. Level-specific evolution and pose: diagonal predator, shaft and claw form two distinct threats. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h09_n2.png` — L'Œil empalé, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Central eye suspended between two perpendicular spear-limbs. Level-specific evolution and pose: larger eye, two longer perpendicular spears and cruciform silhouette. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h10_n2.png` — Le Guetteur trifide, N2

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Sentinel with three spear arms and short lower support. Level-specific evolution and pose: three distinct spear arms frame the eye, short lower support and more imposing body. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h11_n1.png` — Le Traverse-nuit, N1

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Organic silhouette crossed by two immense unequal spears. Level-specific evolution and pose: two long spears pass through a narrow body, one significantly larger, without blood or decoration. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `h12_n1.png` — La Croisée des regards, N1

```text
Slender organic predator, focused on gaze and projecting appendages. Appearance: Four sights and four limbs placed in a cross. Level-specific evolution and pose: readable cross silhouette, four eyes facing in different directions and four matching appendages. Dominant colors: midnight blue #08152E, cobalt #174A9B, indigo #111D45, silver ivory #D7D1BF, electric blue #55BDF0. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Essaim


#### `e01_n2.png` — Nœud vivant, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Knot of fibers become stocky organism, roots and thick links. Level-specific evolution and pose: node opens into a living body, two roots act as arms. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e01_n3.png` — Nœud vivant, N3

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Knot of fibers become stocky organism, roots and thick links. Level-specific evolution and pose: thicker fibers and knotty limbs. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e01_n4.png` — Nœud vivant, N4

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Knot of fibers become stocky organism, roots and thick links. Level-specific evolution and pose: stocky organism entirely made up of roots and tense links. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e02_n2.png` — Larve d'ancrage, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Low larva which becomes an anchoring insect with an armed abdomen. Level-specific evolution and pose: legs and first shell appear. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e02_n3.png` — Larve d'ancrage, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Low larva which becomes an anchoring insect with an armed abdomen. Level-specific evolution and pose: abdomen reinforced with plates. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e02_n4.png` — Larve d'ancrage, N4

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Low larva which becomes an anchoring insect with an armed abdomen. Level-specific evolution and pose: complete anchor insect, armed abdomen and solid supports. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e03_n1.png` — Tisse-griffe, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Weaving insect, uneven claws and branched filaments. Level-specific evolution and pose: small insect with a large claw and fine wire. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e03_n2.png` — Tisse-griffe, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Weaving insect, uneven claws and branched filaments. Level-specific evolution and pose: two different claws, first branched wires. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e03_n3.png` — Tisse-griffe, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Weaving insect, uneven claws and branched filaments. Level-specific evolution and pose: longer weaving legs and network held in the limbs. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e03_n4.png` — Tisse-griffe, N4

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Weaving insect, uneven claws and branched filaments. Level-specific evolution and pose: asymmetrical weaver whose filaments start from its claws, without a canvas background. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e04_n2.png` — Bourgeon mordant, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Toothed shoot becoming organism whose upper bud becomes immense. Level-specific evolution and pose: bud opens onto teeth. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e04_n3.png` — Bourgeon mordant, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Toothed shoot becoming organism whose upper bud becomes immense. Level-specific evolution and pose: stem becomes living body and upper mouth grows. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e04_n4.png` — Bourgeon mordant, N4

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Toothed shoot becoming organism whose upper bud becomes immense. Level-specific evolution and pose: toothed plant organism dominated by an enormous mouth-bud. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e05_n1.png` — Mante des racines, N1

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Mantis rooted, claws growing larger and larger. Level-specific evolution and pose: small mantis with root legs. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e05_n2.png` — Mante des racines, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Mantis rooted, claws growing larger and larger. Level-specific evolution and pose: anterior pincers lengthen. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e05_n3.png` — Mante des racines, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Mantis rooted, claws growing larger and larger. Level-specific evolution and pose: predatory mantis with major claws and roots anchored in its own body. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e06_n1.png` — Porte-nid, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Termite conveyor carrying a living nest on its back. Level-specific evolution and pose: stocky termite, small dorsal nest. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e06_n2.png` — Porte-nid, N2

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Termite conveyor carrying a living nest on its back. Level-specific evolution and pose: open nest with larvae visible in relief. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e06_n3.png` — Porte-nid, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Termite conveyor carrying a living nest on its back. Level-specific evolution and pose: large conveyor under a voluminous dorsal nest, stable silhouette. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e07_n1.png` — Fourmilion des nerfs, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Burrowing, visible nerves and dominant abdomen. Level-specific evolution and pose: small burrowing larva, fine nerves visible. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e07_n2.png` — Fourmilion des nerfs, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Burrowing, visible nerves and dominant abdomen. Level-specific evolution and pose: abdomen increases, nerves branched on the flank. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e07_n3.png` — Fourmilion des nerfs, N3

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Burrowing, visible nerves and dominant abdomen. Level-specific evolution and pose: massive antlion, dominant abdomen and luminous but discreet nervous network. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e08_n2.png` — Ronce rampante, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Live bramble on legs, thickened roots and vertical ridges. Level-specific evolution and pose: thicker roots and better formed limbs. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e08_n3.png` — Ronce rampante, N3

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Live bramble on legs, thickened roots and vertical ridges. Level-specific evolution and pose: crawling organism bristling with vertical crests and brambles. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e09_n1.png` — La Nourrice nouée, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Living matrix with numerous pockets and three main limbs. Level-specific evolution and pose: small knotty womb, three limbs and closed pockets. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e09_n2.png` — La Nourrice nouée, N2

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Living matrix with numerous pockets and three main limbs. Level-specific evolution and pose: open pockets revealing larvae, limbs connected by fibers. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e10_n1.png` — Le Tisseur de meutes, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Winged weaver that connects its limbs with taut fibers. Level-specific evolution and pose: short-winged insect, threads between three limbs. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e10_n2.png` — Le Tisseur de meutes, N2

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Winged weaver that connects its limbs with taut fibers. Level-specific evolution and pose: spread wings and several tense fibers connecting its limbs, without web decoration. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e11_n1.png` — Le Cœur de la colonie, N1

```text
Insect-plant organism, made of living roots, segments and filaments connected to the body. Appearance: Central plant heart surrounded by a crowd of insects connected to it. Level-specific evolution and pose: amber heart core wrapped in insects and roots, compact single silhouette, no decoration. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `e12_n1.png` — La Mante-cathédrale, N1

```text
An insect-and-plant organism made of roots, segments, and living filaments connected to its body. Appearance: Giant mantis, wings and roots form an organic nave. Level-specific evolution and pose: monumental mantis, arched wings and pillared roots, clearly visible insect and plant details. Dominant colors: olive green #66732F, leaf green #94A64A, root brown #493426, amber #C58A32, honey #E5B44E. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


### Assimilateurs


#### `p01_n2.png` — Collecteur de dents, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Collection machine with industrial jaws, saw and recovery tools. Level-specific evolution and pose: larger jaw and saw, first teeth recovered in the frame. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p01_n3.png` — Collecteur de dents, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Collection machine with industrial jaws, saw and recovery tools. Level-specific evolution and pose: articulated tool arms, mechanical rib cage. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p01_n4.png` — Collecteur de dents, N4

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Collection machine with industrial jaws, saw and recovery tools. Level-specific evolution and pose: imposing collector dominated by its assembled jaws and teeth. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p02_n2.png` — Scie boiteuse, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: A machine balanced on a single wheel, with a saw on one side and a clamp on the other. Level-specific evolution and pose: wheel and saw grow larger, with an articulated clamp. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p02_n3.png` — Scie boiteuse, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: A machine balanced on a single wheel, with a saw on one side and a clamp on the other. Level-specific evolution and pose: chassis leans on its wheel; saw and clamp become dominant weapons. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p02_n4.png` — Scie boiteuse, N4

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: A machine balanced on a single wheel, with a saw on one side and a clamp on the other. Level-specific evolution and pose: unstable machine with single wheel, oblique silhouette and clearly distinct tools. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p03_n2.png` — Pince-carcasse, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Mechanical frame with large grippers, an open cage, and a harvesting jaw. Level-specific evolution and pose: longer pincers, visible rib cage. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p03_n3.png` — Pince-carcasse, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Mechanical frame with large grippers, an open cage, and a harvesting jaw. Level-specific evolution and pose: lower jaw collection appears. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p03_n4.png` — Pince-carcasse, N4

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Mechanical frame with large grippers, an open cage, and a harvesting jaw. Level-specific evolution and pose: large carcass on articulated supports, clamps and sampling jaw in the foreground. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p04_n2.png` — Dépeceur rampant, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Low machine with four legs, heavy blades and supporting hindquarters. Level-specific evolution and pose: slats thicken, four supports sharper. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p04_n3.png` — Dépeceur rampant, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Low machine with four legs, heavy blades and supporting hindquarters. Level-specific evolution and pose: rear end becomes a supporting frame. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p04_n4.png` — Dépeceur rampant, N4

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Low machine with four legs, heavy blades and supporting hindquarters. Level-specific evolution and pose: cutting machine at ground level, heavy blades and armored rear end. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p05_n2.png` — Recycleur thoracique, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Recovery torso which evolves into a chassis open to the disassembly arms. Level-specific evolution and pose: chest cavity opens, recovered parts visible. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p05_n3.png` — Recycleur thoracique, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Recovery torso which evolves into a chassis open to the disassembly arms. Level-specific evolution and pose: erected frame with two articulated tool arms and open torso. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p06_n2.png` — Préleveur de plaques, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Extractor machine with waist-level clamps and a low harvesting jaw. Level-specific evolution and pose: wider cutting pliers, jaw under the chassis. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p06_n3.png` — Préleveur de plaques, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Extractor machine with waist-level clamps and a low harvesting jaw. Level-specific evolution and pose: complete extractor with symmetrical clamps and a low harvesting jaw. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p07_n2.png` — Chirurgien d'acier, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Column of instruments turned surgical machine with extended arm. Level-specific evolution and pose: column rises, first tools appear. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p07_n3.png` — Chirurgien d'acier, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Column of instruments turned surgical machine with extended arm. Level-specific evolution and pose: surgical arm extended with several distinct instruments, vertical silhouette. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p08_n2.png` — Porte-greffes, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Carcass loaded with limbs, tools and salvaged parts. Level-specific evolution and pose: more visible grafted parts, tools held by different limbs. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p08_n3.png` — Porte-greffes, N3

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Carcass loaded with limbs, tools and salvaged parts. Level-specific evolution and pose: asymmetrical carcass carrying several salvaged limbs but all connected to the chassis. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p09_n2.png` — Le Démonteur, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Workshop on legs, two dominant clamps and hollow frame. Level-specific evolution and pose: wider workshop, oversized clamps, hollow chassis loaded with dismantling tools. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p10_n1.png` — La Broyeuse d'empreintes, N1

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Living crusher, plates marked with the imprints of absorbed victims. Level-specific evolution and pose: small jaw crusher machine, some imprints engraved in the plates. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p10_n2.png` — La Broyeuse d'empreintes, N2

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Living crusher, plates marked with the imprints of absorbed victims. Level-specific evolution and pose: massive crusher, plates covered with raised marks, no legible writing. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p11_n1.png` — Le Collecteur Zéro, N1

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Ceremonial automaton with recovered plates and two large pincers. Level-specific evolution and pose: erect and symmetrical automaton, two massive pincers, plates recovered like a coat, orange core contained. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


#### `p12_n1.png` — La Machine aux mille dépouilles, N1

```text
Horrific salvage machine with tools, cables, and joints connected to its chassis. Appearance: Low machine with dominant core, remains suspended from its chassis. Level-specific evolution and pose: crawling machine, luminous central core and some dried-out husks suspended, without realistic gore. Dominant colors: black iron #29292D, steel #626168, copper #A96036, rust #713D2D, reclaimed bone #C9B99D, orange #E9822C. Keep this exact palette dominant, allowing only slight tonal variation for materials and readability without changing the creature's color identity. Stylized, non-realistic cartoon horror / dark fantasy, with expressive exaggerated anatomy, grotesque but readable. Hand-painted art with subtle visible pixel-art clusters on both the silhouette edges and in the shading, irregular stepped edges, and broken painted gradients. Not photorealistic, not 3D, not clean vector art. Consistent soft light from the upper left; dark mood, but the subject remains clearly lit and readable, with legible midtones and deep shadows that preserve form. Show the complete subject alone, centered and occupying about 80% of the square composition, with margin around every extremity. Transparent background with a real alpha channel; final PNG, square 496 x 496 px (never over 500 x 500 px). Subject only: no setting, ground, scenery, card frame, interface, text, logo, or watermark; never draw a transparency checkerboard.
```


## Contrôle avant intégration

- Vérifier le nom et le niveau ; ne pas remplacer les 53 images conservées.
- Confirmer PNG, dimensions carrées au plus 500 × 500 px et transparence réelle sur fonds clairs et sombres.
- Vérifier silhouette complète, lisibilité à taille de carte, progression anatomique et cohérence de la palette dominante.
