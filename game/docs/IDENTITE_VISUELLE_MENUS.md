# Identité des menus — L'arène machiavélique

Les menus reprennent la composition sobre du jeu : fonds charbon et basalte,
texte ivoire, métal incandescent et lueurs néon violettes ou carmin. Les halos
et sigils sont volontairement discrets autour des zones de contenu ; ils donnent
une identité démoniaque sans gêner la lecture des cartes et des règles.

## Palette et composants

| Rôle | Couleur |
| --- | --- |
| Fond | `#101013` |
| Panneau | `#1b191e` |
| Bouton secondaire | `#29262e` |
| Bordure | `#514653` |
| Texte | `#eee7e2` |
| Texte secondaire | `#bcb2bd` |
| Action principale | `#dd6847` |
| Accent clair | `#ffad7d` |
| Néon rituel | `#c14cff` |
| Néon carmin | `#f0449c` |

`UITheme.gd` possède les couleurs et les fabriques de styles. `RefugeTheme.gd`
construit la ressource `assets/ui/samstone_theme.tres` depuis ces valeurs. Les
variations `PrimaryButton` et `DangerButton` distinguent l'action principale
et le retrait d'une carte ; les boutons ordinaires héritent de l'ardoise.
Le thème définit également les états désactivés, le focus clavier, les champs
de saisie et les barres de défilement.

## Fonds et illustrations

`MenuBackground.gd` dessine un fond de pierre sombre avec quelques formes
néon simples : halo ouvragé à l'accueil, filets roses sur toute la hauteur du
bestiaire, angles fins dans les règles, arche des rencontres et rails du chemin
des niveaux. Le rituel de
pièce reçoit des cercles néon concentriques autour de la monnaie pour en faire le
point focal. Les accents néon suivent la couleur du dieu affiché : le dieu
actif sur l'accueil et dans le bestiaire, le dieu sélectionné dans les
rencontres, puis les deux dieux en duel, sur le plateau et au résultat. Les
deux accents secondaires d'un dieu décalent sa teinte d'environ 40° de part et
d'autre, l'un plus clair et saturé, l'autre plus sombre : trois néons distincts
restent dans la gamme du dieu sans se confondre. En duel, le troisième accent
provient de la teinte intermédiaire des deux dieux. Les filets néon sont plus
épais sur tous les décors sauf le profil et le bestiaire, dont les panneaux
occupent déjà la largeur ; le rituel de la pièce et le résultat les épaississent
davantage encore. À l'accueil, le cercle est calé sur le portrait du dieu et le
nom comme les commandes remontent au-dessus de la barre de navigation. Le plateau conserve les couleurs bleu et rouge des
camps ; seuls ses détails de fond reprennent les couleurs divines. Les règles et
les statistiques restent neutres. Les effets lumineux restent en marge ou à
faible contraste.
Le dessin est actualisé au chargement, au changement de dieu ou au
redimensionnement et ignore les événements d'entrée.

La pièce du tirage reprend les codes d'une monnaie : tranche épaisse et crantée,
champ de métal en relief, liseré gravé et poinçons d'atelier. Les couleurs bleue
et rouge des camps sur le plateau restent inchangées.

Les six portraits sont fournis dans `assets/gods/`. Le champ `asset` de
`data/gods.json` en fournit le chemin ; Godot réutilise leurs ressources chargées.

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
- Rencontres : une grille de cases de dieux (portrait, nom, famille, cadre et
  motif de famille), puis un chemin serpentin de quinze ronds par adversaire.
  Chaque palier de cartes forme un chapitre et chaque difficulté un rond ;
  terminé, ouvert et verrouillé se distinguent par la couleur et par la forme
  (coche, numéro, cadenas). Les ronds terminés et le rond ouvert sont
  sélectionnables pour rejouer un niveau ; un rond verrouillé reste inactif.
  Le pied de page fixe rappelle le dieu, le niveau choisi et la progression,
  avec le bouton Affronter toujours accessible.
- Règles : texte ivoire et titres ambrés, logos des pouvoirs aux couleurs
  de leur famille ; valeurs toujours lues dans les règles du jeu. Une marge
  finale permet de défiler après la dernière ligne.
- Profil : pseudo modifiable, statistiques générales et progression des sept
  chemins (niveaux terminés sur quinze), sans avatar.
- Avant-combat : les portraits des deux dieux encadrent la pièce ; le cadre du
  dieu désigné par le tirage est renforcé. En combat, ces portraits restent dans
  les plaques du HUD, avec le nom du combattant, celui du dieu et le score.
  L'écran de résultat conserve le même décor et propose le niveau suivant après
  une victoire, puis revanche, autre niveau, autre dieu et accueil ; le suivant
  disparaît après une défaite ou au dernier rond.
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
passage des gestes à travers le décor de l'accueil. Les essais utilisent un profil
temporaire, restauré ensuite.

Au dernier contrôle automatisé, 514 vérifications générales réussissent, sans
échec et sans erreur Godot ; les 80 vérifications tactiles réussissent. Une
validation visuelle doit
compléter ces suites après chaque changement de composition : chaque dieu, les
fiches de cartes, les tiroirs ouverts, les quatre raretés, les deux propriétaires
du plateau et les cases interdites doivent être relus à la taille mobile. Un essai
sur téléphone réel reste nécessaire pour juger le confort final des gestes et le
rendu sur l'écran cible.
