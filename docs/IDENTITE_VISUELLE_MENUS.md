# Identité des menus — Le cabinet des monstres

Les menus mettent en scène un refuge de collectionneur : fond bleu nuit,
ardoise, métal patiné, texte ivoire et éclairage ambré. Les portraits et les
couleurs des familles apportent l'identité horrifique. Les surfaces de lecture
restent calmes et les commandes principales se distinguent par leur couleur.

## Palette et composants

| Rôle | Couleur |
| --- | --- |
| Fond | `#151922` |
| Panneau | `#272d38` |
| Bouton secondaire | `#343e4d` |
| Bordure | `#575361` |
| Texte | `#e9e1d1` |
| Texte secondaire | `#b5b6c0` |
| Action principale | `#d7a24d` |
| Accent clair | `#f0cc8b` |

`UITheme.gd` possède les couleurs et les fabriques de styles. `RefugeTheme.gd`
construit la ressource `assets/ui/samstone_theme.tres` depuis ces valeurs. Les
variations `PrimaryButton` et `DangerButton` distinguent l'action principale
et le retrait d'une carte ; les boutons ordinaires héritent de l'ardoise.
Le thème définit également les états désactivés, le focus clavier, les champs
de saisie et les barres de défilement.

## Fonds et illustrations

`MenuBackground.gd` remplace `ParchmentBackground.gd`. Ses quatre ambiances
partagent la même palette : refuge, bestiaire, carnet et rencontres. Les arches,
les rayonnages et les lanternes sont dessinés avec les commandes natives de
Godot. Le centre est réservé au contenu et le décor ignore les événements.

Le décor est redessiné au chargement et au redimensionnement, sans boucle
`_process`. Sur l'accueil uniquement, une légère modulation du décor évolue
par tween ; elle ne redessine pas les formes à chaque image. Le décor utilise
des positions fixes et ne consomme aucun hasard de combat.

Les six portraits existants sont copiés sans retouche dans `assets/gods/`.
Le champ `asset` de `data/gods.json` en fournit le chemin ; Godot réutilise ses
ressources chargées. Le jeu ne charge pas de fichier depuis `docs/designs/`.

## Déclinaison par écran

- Accueil : pseudo ouvrant le profil, logo, portrait du dieu actif, identité
  de sa famille, état du deck et bouton de lancement. La hauteur du portrait
  s'adapte à l'espace disponible pour conserver les commandes accessibles.
  Le titre et la famille utilisent 40 pixels, l'état du deck 44 pixels sur une
  ligne, dans le canevas de référence.
- Bestiaire : l'identité du dieu et ses trois decks partagent un panneau. Son
  nom, son titre, sa famille et les boutons 1/2/3 occupent la colonne gauche ;
  son grand portrait ouvre à droite un tiroir de six choix en 3 × 2. Les cases
  remplies et vides du deck suivent leur largeur pour rester carrées. Les cartes
  et leurs tiroirs restent dans le défilement existant.
- Fiche : grande illustration, statistiques sur une ligne, niveaux numérotés,
  bouton Utiliser remonté et fermeture ; défilement tactile conservé. La carte
  remplit la largeur disponible ; son conteneur réserve la même hauteur pour
  qu'elle reste carrée et ne recouvre pas les textes. Son logo de pouvoir est
  agrandi pour cette vue et le même pictogramme précède le texte d'explication.
- Rencontres : portraits de famille, difficulté, identité de l'adversaire,
  panneau de détail et bouton Affronter.
- Règles : texte ivoire et titres ambrés, logos des pouvoirs aux couleurs
  de leur famille ; valeurs toujours lues dans les règles du jeu. Une marge
  finale permet de défiler après la dernière ligne.
- Profil : pseudo modifiable, statistiques et progression, sans avatar.
- Avant-combat : les portraits des deux dieux encadrent la pièce ; le cadre du
  dieu désigné par le tirage est renforcé. En combat, ces portraits restent dans
  les plaques du HUD, avec le nom du combattant, celui du dieu et le score.
  L'écran de résultat conserve le même décor et ses commandes.
- Navigation : trois onglets avec icônes SVG au-dessus des libellés. Les
  enfants décoratifs ignorent la souris et le tactile ; les boutons d'origine
  conservent les connexions et la gestion des glissements.

Les cadres et bandeaux des cartes utilisent des tons minéraux. Leur lecture
repose sur quatre couches qui ne se remplacent jamais : la case indique le camp,
le large minerai sombre indique la famille, le liseré lumineux indique la rareté
et le pictogramme indique le pouvoir.
La refonte ne modifie pas les statistiques, les decks ni le séquençage du combat.

### Cartes et plateau

Les raretés utilisent à la fois une teinte et une forme : ivoire mat et trait
simple pour Commune, argent cyan avec reflet pour Rare, violet à double trait
pour Épique, puis or lumineux et coins ornés pour Légendaire. La sélection est
un halo extérieur et conserve donc ce liseré visible. La couleur de famille est
assombrie et désaturée afin de ne pas se confondre avec une rareté vive.

Sur le plateau, une case alliée est bleu nuit avec un contour bleu clair, tandis
qu'une case adverse est rouge sombre avec un contour rouge clair plus anguleux.
La couleur change au moment de l'impact d'une capture. Une case interdite devient
presque noire, bordée de cramoisi, avec une grande croix ivoire ombrée et des
entailles diagonales. `BlockedCellOverlay` dessine ces signes à l'échelle de la
case : leur lisibilité ne dépend d'aucune police installée.

Les aperçus utilisent `StoneCard.set_edge_margin_ratio` pour agrandir le cadre :
4 % de marge dans le deck, 6 % dans la fiche. Dans le deck, `set_marker_scale`
conserve la taille normale des lames et boucliers malgré cette marge réduite.
Les rangées et colonnes réservent 40 pixels entre les cases ; le panneau et les
tiroirs laissent aussi de la place aux symboles qui dépassent. Le plateau, la
main et les autres vues conservent la marge par défaut de 12 %.

Le coût et le nom grandissent avec la carte, dans les limites définies par
`UITheme`. Les noms longs et coûts décimaux s'ajustent à leur espace disponible.
La largeur du badge de niveau suit le texte et reste alignée au coin inférieur
droit de l'illustration. Le dessin et les positions des symboles utilisent les
mêmes réglages ; aucun calcul permanent n'est ajouté dans `_process`.

Les pictogrammes d'explication utilisent `PowerBadge` et `StoneSymbols`, comme
les règles et les cartes. Une carte neutre masque simplement cette zone et rend
toute la largeur à son texte.

## Contrôle

Les suites `GodSystemChecks` et `TouchInputChecks` couvrent les parcours
existants. `MenuChecks` vérifie en plus le chargement des six portraits et le
passage des gestes à travers le décor de l'accueil. Le contrôle graphique doit
inclure les différents dieux, les fiches, les menus ouverts, les tiroirs et un
écran moins haut. Les essais utilisent un profil temporaire, restauré ensuite.

Validation après les corrections de lisibilité : 433 contrôles généraux et 63 contrôles tactiles
réussis, sans échec ni erreur Godot comptabilisée. Le rendu PC a été capturé
sur 19 vues, dont les six dieux, les panneaux ouverts et une composition de
1080 × 1600 pour l'accueil moins haut. Les derniers réglages des symboles,
textes et badges ont aussi été contrôlés sur 12 captures ciblées, notamment un
deck Horizon, son tiroir ouvert et des fiches avec nom long ou coût décimal.
Une planche supplémentaire vérifie ensemble les quatre raretés, les deux camps
et deux cases interdites à la taille réelle du plateau mobile.
Les 203 PNG des cartes sont identiques
à ceux du début de la refonte ; les six portraits conservent les octets de
leurs sources. Un essai sur téléphone réel reste nécessaire pour juger le
confort final et le rendu sur son écran.
