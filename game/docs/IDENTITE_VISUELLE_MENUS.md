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
néon simples. Le bestiaire, la campagne, la boutique, le profil et les règles
partagent le même décor : deux filets verticaux qui vont d'un bord à l'autre de
l'écran et traversent toute la hauteur. Dessinés dans l'espace écran, hors de la
zone d'artwork, ils restent pleine hauteur sur les téléphones 20:9 et passent
toujours à l'extérieur des panneaux opaques sur tablette ; leur couleur suit le
néon secondaire, donc la teinte claire du dieu quand l'écran en affiche un. L'accueil garde son halo ouvragé, les
rencontres leur arche, et la carte de campagne ne garde que ses nœuds et ses
courbes. Le rituel de pièce reçoit des cercles néon concentriques autour de la
monnaie pour en faire le point focal. Les accents néon suivent la couleur du
dieu affiché : le dieu actif sur l'accueil, dans le bestiaire et sur la carte de
campagne, le dieu sélectionné dans les rencontres, puis les deux dieux en duel,
sur le plateau et au résultat. Les deux identités sans dieu ont leur propre
palette fixe, reprise de leur illustration : Sans dieu marie un violet sombre
et un marron, Pr.Stone un gris et un rouge clair. La boutique, le profil et les
règles reprennent cette identité : la palette du dieu actif, ou celle de Sans
dieu quand aucun dieu n'est équipé. Les deux accents secondaires d'un dieu
décalent
sa teinte d'environ 40° de part et d'autre, l'un plus clair et saturé, l'autre
plus sombre : trois néons distincts restent dans la gamme du dieu sans se
confondre. En duel, le troisième accent provient de la teinte intermédiaire des
deux dieux. Les filets néon des autres décors gardent leur relief ; le rituel de
la pièce et le résultat les épaississent davantage encore. À l'accueil, le cercle
est calé sur le portrait du dieu et le nom comme les commandes remontent
au-dessus de la barre de navigation. Le plateau conserve les couleurs bleu et
rouge des camps ; seuls ses détails de fond reprennent les couleurs divines. Les
règles et les statistiques ne mettent en avant aucun dieu, mais reprennent la
palette de l'identité active. Les effets lumineux restent en marge ou à faible
contraste.
Le dessin est actualisé au chargement, au changement de dieu ou au
redimensionnement et ignore les événements d'entrée.

La carte de campagne ajoute ses propres variations dans la vue défilante, sans
modifier `MenuBackground.gd` : `CampaignSectionTheme` découpe les treize
chapitres en bandes contiguës et `CampaignSectionArt` y trace un aplat très
sombre, un grand emblème central en contour et de petits motifs de bord. Les
frontières suivent les médianes des nœuds pour absorber les chevauchements de
chapitres. Les alphas restent sous 0,50 pour les bandes, 0,16 pour les motifs
de bord et 0,07 pour l'emblème central ; aucun `Control` ni texture n'est
ajouté, et seules les sections proches du viewport sont dessinées.

La pièce du tirage reprend les codes d'une monnaie : tranche épaisse et crantée,
champ de métal en relief, liseré gravé et poinçons d'atelier. Les couleurs bleue
et rouge des camps sur le plateau restent inchangées.

Les six portraits sont fournis dans `assets/gods/`. Le champ `asset` de
`data/gods.json` en fournit le chemin ; Godot réutilise leurs ressources chargées.

## Déclinaison par écran

- Accueil : pseudo ouvrant le profil, logo, portrait du dieu actif, identité
  de sa famille, état du deck, puis deux modes de même largeur : CAMPAGNE en
  action principale et PVP dans la variation secondaire `PvpButton`. La ligne
  `ModeButtons` suit le flux du conteneur, sans position absolue ; PVP reste
  visible sans concurrencer CAMPAGNE. Un deck incomplet ouvre une modale
  `DECK INCOMPLET` au-dessus d'un voile sombre qui bloque l'accueil. Le message
  précise le nombre de cartes présentes et les actions `FERMER` et
  `COMPLÉTER MON DECK` permettent respectivement de rester sur l'accueil ou
  d'ouvrir la collection. La hauteur du portrait
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
- Carte de campagne : un graphe vertical sur le fond commun à deux filets,
  enrichi dans la vue défilante par les treize thèmes de section, avec un espace
  logique de 1080 unités et des ronds de 150 unités réduits ensemble sur
  téléphone. Les courbes passent derrière les nœuds ; terminé, accessible,
  verrouillé, tutoriel, mini-boss et boss se distinguent par la couleur et par
  la forme (coche, anneau, cadenas, livre, losange, couronne). Un nœud accessible
  ou terminé ouvre une fiche ; un nœud verrouillé reste inactif ; un glissement
  défile sans activer. La fiche présente adversaire, mode, palier, IA, deck,
  format et action de lancement. Le compteur `X / N niveaux terminés` et le
  message sur les branches restent visibles autour du défilement.
- Règles : texte ivoire et titres ambrés, logos des pouvoirs aux couleurs
  de leur famille ; valeurs toujours lues dans les règles du jeu. Une marge
  finale permet de défiler après la dernière ligne.
- Profil : pseudo modifiable, statistiques générales et décompte historique des
  sept anciens chemins (niveaux terminés sur quinze), sans avatar. La progression
  de la campagne unifiée est affichée sur sa carte, par identifiant de nœud.
- Salon PVP : les trois étapes partagent la même arche de pierre et les deux
  épées croisées en néon ; les deux courbes de l'arche reprennent chacune la
  couleur d'un dieu, et les montants rejoignent le bord bas même si le format
  d'écran est plus haut que le canevas de référence. Choix du mode (créer ou
  rejoindre), recherche (liste vivante et saisie d'adresse), puis salle
  d'attente (adresse copiable, deux cartes joueur et bouton PRÊT). L'état réseau
  est toujours écrit en toutes lettres, jamais indiqué par une couleur seule.
- Avant-combat : les portraits des deux dieux encadrent la pièce ; le cadre du
  dieu désigné par le tirage est renforcé. En combat, ces portraits restent dans
  les plaques du HUD, avec le nom du combattant, celui du dieu et le score.
  l'écran de résultat partage son traitement avec le PVP : bouquets de feux
  d'artifice amples aux motifs variés, avec des traînées effilées qui retombent
  vers le bas et mêlent les nuances du dieu vainqueur ; grand crâne néon non
  déformé, légèrement abaissé, de cette couleur en cas de défaite ; épées
  croisées aux couleurs des deux dieux en cas d'égalité. En campagne unifiée, il
  propose la manche suivante d'une série, le retour à la carte, la revanche ou
  l'accueil ; une défaite ou une égalité ne valide jamais le nœud. Sur les
  anciens parcours, il conserve le niveau suivant, la revanche, l'autre niveau,
  l'autre dieu et l'accueil.
- Préparation PVP : scène dédiée, même arche minérale que le salon. Le dieu
  local est présenté avec son illustration et sa couleur, puis ses huit cartes
  illustrées en deux colonnes et quatre lignes pour le deck final, avec points,
  palier et format. En Sélection, les deux offres adverses restent compactes et
  non interactives en haut ; les deux offres locales sont centrées et seules
  interactives, avec un verrouillage visible après le choix. Le deck en
  construction est illustré en bas avec `VOTRE DECK — X / 8` et s'actualise
  après chaque choix accepté. Chaque joueur avance à son rythme ; le premier
  deck terminé ouvre sa présentation et `PRÊT` sans attendre l'autre. Aucun
  deck adverse complet ni choix adverse n'est révélé. La taille des trois
  grilles est bornée par la hauteur restante, pas seulement par la largeur :
  les huit picks et les huit cartes finales tiennent sans scroll sur les
  canevas 1080 × 2400 et 1200 × 1920.
- Fin de match PVP : mêmes illustrations de victoire, défaite et égalité que la
  campagne, accordées au dieu gagnant ou aux deux dieux en cas d'égalité.
  Verdict local (VICTOIRE, DÉFAITE ou ÉGALITÉ), puis trois actions distinctes :
  REVANCHE / PARTIE SUIVANTE / NOUVELLE SÉRIE comme action principale, RETOUR
  AU SALON qui ramène ce joueur seul en conservant la connexion, et QUITTER qui
  ferme la session. L'autre appareil reste sur son écran et affiche `EN PARTIE`
  dans le salon jusqu'à son propre retour. Un seul camp ne peut pas relancer la
  partie : l'action principale attend que les deux téléphones la demandent.
  Même règle avant le premier coup : après le pile ou face, `COMMENCER` attend
  l'accord des deux appareils.
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

Le combat réserve le plateau et la main dans un même budget vertical. Les
téléphones hauts présentent les huit cartes en trois colonnes avec une dernière
rangée centrée ; les tablettes conservent quatre colonnes. Le surplus du canevas
ne peut donc plus devenir un espace vide entre le terrain et la main.

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

Les lanceurs automatisés doivent terminer sans échec ni erreur Godot ; leur
nombre de vérifications n'est pas figé dans la documentation. Les suites PVP
vérifient en plus le protocole, le salon et les commandes validées
par l'hôte, avec un transport simulé (voir [PVP_LOCAL.md](PVP_LOCAL.md)). Une
validation visuelle doit
compléter ces suites après chaque changement de composition : chaque dieu, les
fiches de cartes, les tiroirs ouverts, les quatre raretés, les deux propriétaires
du plateau et les cases interdites doivent être relus à la taille mobile. Un essai
sur téléphone réel reste nécessaire pour juger le confort final des gestes et le
rendu sur l'écran cible.
