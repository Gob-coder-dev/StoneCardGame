# Campagne unifiée

La campagne est un graphe orienté acyclique unique, chargé depuis
`data/campaign/campaign_v2.json`. Elle contient **162 niveaux**, **190 arêtes**
et **13 sections visuelles** sur une seule carte de **1080 × 19800** unités.
`CampaignContentLoader.DEFAULT_PATH` pointe vers ce fichier et
`campaign_version` vaut `6`.

L'ancien fichier `campaign_v1.json` reste dans le dépôt comme archive et source
de comparaison historique. Il n'est plus chargé par le jeu.

## Contenu livré

| Mesure | Valeur |
| --- | --- |
| Niveaux | 162 |
| Arêtes | 190 |
| Sections visuelles | 13 |
| Profondeur minimale / maximale | 0 / 77 |
| Plus longue série de mode | 21, parcours Classique d'apprentissage |
| Plus longue série d'un même dieu | 6, approches et mini-boss d'Énigma |
| Carte logique | 1080 × 19800 |
| Niveaux du Professeur Stone | 5 |
| Mini-boss facultatifs | 10 |
| Mini-boss obligatoires | 4 |
| Mini-boss en FT2 | 14 |
| Séries FT1 / FT2 / FT3 | 144 / 17 / 1 |
| Decks fixes uniques | 94 |
| Générateurs contraints | 12 nœuds, dont 3 mini-boss (Véskar, Sylkha, Ilyr) |
| Decks miroirs fixes | 7 (six initiations et Ilyr) |
| Cartes du dieu par deck fixe | 3 minimum |

### Dieux

Les cinq premiers nœuds sont des tutoriels du Professeur Stone, sans thème
divin. Ils sont suivis de six initiations miroir, une par dieu.

| Dieu | Nœuds thématiques | Nœuds à dieu réellement fixé |
| --- | ---: | ---: |
| Véskar | 26 | 18 |
| Nérava | 26 | 21 |
| Kharûn | 26 | 21 |
| Énigma | 27 | 21 |
| Ilyr | 26 | 16 |
| Sylkha | 26 | 17 |

Le total des nœuds à dieu fixé est de 114. Les autres rencontres utilisent les
règles de génération de leur mode ; leur `theme_god_id` sert à l'accent visuel et
au libellé d'inspiration, pas à verrouiller le tirage.

### Modes

| Mode | Niveaux |
| --- | ---: |
| Classique | 95 |
| Aléatoire | 21 |
| Miroir | 21 |
| Sélection | 25 |

Les tutoriels sont Classiques. Les six initiations qui suivent sont des Miroirs
fixes : les deux camps reçoivent le même dieu et le même deck de quatre communes
du dieu et quatre communes neutres, toutes N1. Le Carrefour reste Classique
pour consolider les règles. L'Aléatoire et le Miroir libre arrivent dans le
Marais ; la Sélection commence après le premier jalon, dans la Bibliothèque,
au palier 3 minimum. Aucun mode ne disparaît en fin de campagne.

Quatre-vingt-quatorze rencontres utilisent un deck fixe explicite. Les exceptions
Classiques restent déclarées dans les politiques de deck et ne changent pas les
règles du mode.

### Paliers

| Palier maximal | Niveaux |
| --- | ---: |
| 1 | 13 |
| 2 | 42 |
| 3 | 36 |
| 4 | 71 |

Le palier est calculé avec `CardPowerTierRules` : niveau de forme plus décalage
de rareté, avec l'exception explicite éventuelle du catalogue. Une légendaire
niveau 1 n'est donc pas une carte de palier 1.

### Précision de l'IA

Les 162 profils utilisent **83 valeurs distinctes** entre 0 et 1. 151 nœuds
utilisent une valeur qui n'est pas un multiple de 0,25. La précision suit la
profondeur et la fonction de la rencontre, sans progression strictement
linéaire.

| Tranche de profondeur | Niveaux | Précision minimale | Précision maximale | Moyenne |
| --- | ---: | ---: | ---: | ---: |
| 0–19 | 31 | 0,00 | 0,38 | 0,165 |
| 20–39 | 45 | 0,27 | 0,75 | 0,489 |
| 40–59 | 46 | 0,48 | 0,90 | 0,695 |
| 60–79 | 40 | 0,74 | 1,00 | 0,869 |

Les mini-boss et les rencontres majeures servent de pics ; les nœuds qui suivent
une impasse ou un mini-boss peuvent redescendre pour laisser respirer le joueur.
Une bonne précision ne signifie pas nécessairement un deck plus puissant : les
profils combinent cartes modestes et IA précise, ou cartes fortes et IA moyenne.

Toute approche directe d'un mini-boss obligatoire ou du boss final porte le
profil `boss_approach`. Sa précision est plafonnée sous le maximum ordinaire du
chapitre et son deck vise la partie basse de la bibliothèque disponible. Le boss
doit ensuite avoir au moins **0,06** de précision supplémentaire et un palier au
moins égal. Le générateur et `CampaignProgressionValidator` contrôlent tous les
deux cette règle afin qu'une régénération ne puisse pas réintroduire une
inversion. Au premier passage, La Convergence utilise six cartes de palier 1 et
deux de palier 2 à 0,24, avant La Porte des Assimilateurs à 0,30 en FT2.

## Topologie

| Mesure | Valeur |
| --- | ---: |
| Nœuds avec plusieurs sorties | 29 |
| Embranchements à exactement 2 sorties | 20 |
| Embranchements à exactement 3 sorties | 7 |
| Embranchements à exactement 4 sorties | 2 |
| Nœuds de regroupement | 18 |
| Regroupements à 2 entrées | 10 |
| Regroupements à 3 entrées ou plus | 8 |
| Impasses | 12 |

Les 12 impasses comprennent les 10 mini-boss facultatifs, le cul-de-sac
`veilleur_impasse` et le boss final. Les 11 impasses hors boss final sont donc
toutes secondaires.

Les quatre mini-boss obligatoires sont placés sur des passages incontournables.
Les mini-boss facultatifs n'ont aucune sortie. Aucun nœud ne verrouille une
branche par un choix exclusif : terminer un nœud ouvre toutes ses sorties, et un
regroupement est débloqué par **n'importe lequel** de ses prédécesseurs.

### Sections visuelles

| Section | Niveaux |
| --- | ---: |
| Seuil | 5 |
| Initiations | 6 |
| Carrefour | 14 |
| Le Marais des Serments | 12 |
| Les Forges Basses | 13 |
| La Bibliothèque des Os | 13 |
| Le Marché Nocturne | 13 |
| Les Serres de Verre | 10 |
| Les Remparts Muets | 10 |
| Le Puits des Échos | 18 |
| La Cour des Masques | 14 |
| Les Jardins de Cendre | 14 |
| Cime | 20 |

Le Seuil contient les cinq tutoriels et la section Initiations les six duels
miroir obligatoires. Le Carrefour ouvre ensuite les branches d'introduction,
les premiers mini-boss et les routes parallèles. Les neuf régions intermédiaires
utilisent neuf topologies différentes : elles ne sont pas des copies d'un même
groupe de cinq niveaux. La Cime réunit les vingt nœuds finaux, dont les cinq
niveaux historiques et les approches du Collectionneur.

## Format de `campaign_v2.json`

Le fichier est la source de vérité du contenu livré. Il est produit par
`tools/build_campaign_v2.py` et validé par `CampaignValidator` puis
`CampaignAudit`.

```json
{
  "id": "samstone_campaign",
  "title": "La Carte de SamStone",
  "campaign_version": 6,
  "map": {"width": 1080, "height": 19800},
  "start_node_id": "tuto_01",
  "final_node_id": "final_01",
  "nodes": [
    {
      "id": "tuto_01",
      "name": "Le Seuil",
      "chapter": "Seuil",
      "region": "Le refuge",
      "type": "tutorial",
      "position": {"x": 540, "y": 160},
      "dead_end": false,
      "mini_boss_kind": "",
      "tutorial_id": "tutoriel_seuil",
      "theme_god_id": "",
      "accent": "#a6c79a",
      "encounter": {
        "game_mode": "classic",
        "opponent_god_policy": "fixed",
        "opponent_deck_policy": "fixed",
        "fixed_god_id": "",
        "fixed_deck": [
          "le_drape_du_seuil_n1",
          "avortons_des_caves_n1",
          "mordeur_des_combles_n1",
          "ogre_droitier_n1",
          "rampant_des_fosses_n1",
          "gueule_de_travers_n1",
          "ecorche_angle_n1",
          {"lineage_id": "le_sac_a_murmures", "copies": 1}
        ],
        "max_power_tier": 1,
        "ai_profile": {"precision": 0.0, "anticipation": false},
        "series_format": "ft1",
        "seed_policy": "fixed_per_node",
        "seed": 5000,
        "board_size": 3,
        "player_hand_size": 5,
        "opponent_hand_size": 4,
        "allow_incomplete_player_deck": true,
        "blocked_cells": [],
        "forced_first_player": 1
      },
      "rewards": {
        "souls_min": 11,
        "souls_max": 17,
        "card_rewards": [
          {"lineage_id": "avortons_des_caves", "copies": 1},
          {"lineage_id": "mordeur_des_combles", "copies": 1},
          {"lineage_id": "mache_mur", "copies": 1},
          "le_sac_a_murmures_n1"
        ]
      },
      "visual": {"scale": 1.0}
    }
  ],
  "edges": [{"id": "e_tuto_01_tuto_02", "from": "tuto_01", "to": "tuto_02"}]
}
```

### Nœud

| Champ | Rôle |
| --- | --- |
| `id` | Identifiant stable, utilisé par la progression et les statistiques |
| `name` | Nom affiché dans la fiche |
| `chapter` | Section visuelle de la carte |
| `region` | Sous-zone narrative et thème de la fiche |
| `type` | `tutorial`, `normal`, `mini_boss` ou `boss` selon le rôle |
| `position` | Coordonnées logiques `x` / `y` de la carte |
| `dead_end` | Déclare explicitement une impasse |
| `mini_boss_kind` | Vide, `optional` ou `mandatory` |
| `tutorial_id` | Identifiant de tutoriel, vide hors des cinq tutoriels |
| `stage_id` | Phase globale de puissance (`early_game`, `epic_intro`, etc.) |
| `balance_profile` | Fonction du niveau : standard, challenge ou boss |
| `theme_god_id` | Dieu d'accent et d'inspiration ; vide pour les tutoriels |
| `accent` | Couleur ou famille d'accent de la carte |
| `encounter` | Rencontre préparée par `CampaignEncounterFactory` |
| `rewards` | Fourchette d’âmes et cartes fixes accordées à la première victoire |
| `visual` | Paramètres visuels facultatifs, sans effet sur les règles |

### Rencontre

| Champ | Rôle |
| --- | --- |
| `game_mode` | `classic`, `random`, `mirror` ou `draft` |
| `opponent_god_policy` | Politique de dieu du mode existant |
| `opponent_deck_policy` | Deck fixe, généré ou dupliqué selon le mode |
| `fixed_god_id` | Dieu adverse réellement fixé, ou vide |
| `fixed_deck` | Huit identifiants de formes pour un deck fixe |
| `generator_god_id` | Dieu imposé aux modes Aléatoire/Miroir, ou vide |
| `generator_min_god_cards` | Minimum de cartes de ce dieu ; 8 impose un deck pur |
| `mirror_fixed_deck` | Deck exact copié aux deux camps en Miroir, ou vide |
| `max_power_tier` | Palier maximal autorisé pour la rencontre |
| `ai_profile` | Précision, anticipation et réglages réels du profil |
| `series_format` | `ft1`, `ft2` ou `ft3` |
| `seed_policy` | `fixed_per_node` pour un contenu signé ; `per_attempt` pour toute génération |
| `seed` | Graine déterministe de la rencontre |
| `board_size` | Taille du plateau, 4 par défaut et 3 pour le premier tutoriel |
| `player_hand_size` / `opponent_hand_size` | Nombre de cartes réellement distribuées |
| `allow_incomplete_player_deck` | Exception explicite, autorisée uniquement sur `tuto_01` |
| `blocked_cells` | Cases bloquées fixes de la rencontre ; vide signifie aucune case |
| `forced_first_player` | Camp imposé au premier tour, ou tirage normal si absent |

Un deck fixe doit contenir exactement huit cartes, huit lignées distinctes,
respecter le dieu, le palier et le budget de 80 points. Pour un deck à dieu
identifié, au moins trois cartes doivent appartenir à ce dieu ; les cartes
neutres ne comptent pas dans ce minimum. Les tutoriels Pr.Stone restent
entièrement neutres. La validation utilise `DeckRules.validate_deck`, pas une
règle parallèle.

Les champs de génération sont optionnels et additifs. `generator_god_id` filtre
le pool du mode Aléatoire ou Miroir. `generator_min_god_cards` est une vraie
contrainte du solveur : 7 garantit au moins sept cartes du dieu et 8 exclut
toutes les cartes neutres. Une valeur hors de 0–8 est refusée, jamais corrigée
silencieusement. Un
`mirror_fixed_deck` non vide est validé comme un deck de huit cartes, puis copié
pour les deux camps. Le validateur vérifie les mêmes règles de palier, de
lignées, de budget et de minimum de cartes du dieu que pour un deck fixe.

Le moteur de plateau lit `board_size` depuis `GameState`; règles de placement,
effets, IA, vue et animations utilisent tous cette même valeur. Le 3 × 3 n’est
donc pas un faux plateau 4 × 4 masqué. En dehors du premier tutoriel, les
valeurs par défaut restent un plateau 4 × 4 et huit cartes par camp.

### Récompenses

Chaque nœud livré possède une fourchette `souls_min` / `souls_max`. Les cartes
de `card_rewards` sont des couples `lineage_id` / `copies`, fixes et accordés
une seule fois ; les âmes d’une
revanche victorieuse sont réduites à 25 %. Une défaite, une égalité ou une
manche intermédiaire de FT2/FT3 ne déclenche aucune transaction. Le détail de
la progression économique est décrit dans [ECONOMY.md](ECONOMY.md). La table
`campaign_candles_by_chapter` accorde en plus 1, 2 ou 5 bougies à toute victoire
finale selon le chapitre, y compris lors d’une revanche.

Les boss et mini-boss donnent deux lignées différentes. Les rencontres
ordinaires en distribuent ponctuellement une x2 ou deux x1. La rareté suit la
phase de campagne : communes sur l'apprentissage, rares avant le premier
jalon, épiques après celui-ci, puis légendaires après le second. Une récompense
légendaire reste à une copie puisqu'elle n'a aucun niveau supérieur.

### Graine

La graine de base reste déterministe à partir de `campaign_version`, de
l'identifiant et de la graine déclarée. Une rencontre générée — Aléatoire,
Sélection, Miroir sans deck fixe ou Classique à deck généré — lui ajoute le
numéro de tentative : relancer le niveau produit donc un nouveau tirage. Un
Miroir à deck fixe et les rencontres Classiques écrites à la main restent en
`fixed_per_node`. Le validateur refuse une génération accidentellement figée.

`CampaignPreparation` et `PvpPreparation` projettent leurs états dans la même
`ModePreparationView`. Les offres, le deck en construction, le dieu, le deck
final et le calcul responsive ont ainsi un rendu identique. En Sélection, le
chronomètre est actualisé chaque image depuis la session sans reconstruire les
cartes ; seule la seconde affichée change.

## Dieux et thèmes

`theme_god_id` ne remplace pas `fixed_god_id`.

- En Classique à dieu fixe, le dieu adverse réel et le thème coïncident.
- En Aléatoire ou en Miroir, le thème fournit l'accent de carte et le libellé
  « inspiration » ; le tirage applique les règles du mode.
- En Sélection, le thème colore la rencontre sans modifier le plan de draft.

Cette séparation permet d'équilibrer les thèmes sur la carte sans fausser les
règles d'équité des modes générés.

## Mini-boss, formats et séries

Tous les mini-boss sont en **FT2**. Le mode peut être Classique, Aléatoire,
Miroir ou Sélection, à condition que la préparation du mode fonctionne déjà avec
le format de série.

- Un mini-boss **facultatif** termine une impasse, n'a aucune sortie et n'est
  jamais nécessaire pour atteindre le boss final.
- Un mini-boss **obligatoire** est placé sur un passage incontournable ; sa
  victoire ouvre la suite obligatoire. Il reste plus précis que chacune de ses
  approches directes et ne descend jamais sous leur palier de puissance.
- Les rencontres ordinaires restent majoritairement en FT1.
- Le boss final utilise FT3.
- Une égalité ne donne aucun point et ouvre une manche supplémentaire.

Les 14 mini-boss sont en FT2. Trois rencontres ordinaires majeures utilisent
aussi FT2. Le total est donc de 17 FT2 ; le boss final est l'unique FT3.

### Dix mini-boss facultatifs et leurs approches

Chaque impasse facultative possède maintenant une chaîne de 2 à 5 niveaux
ordinaires avant son mini-boss. Ces niveaux reprennent le dieu et le mode du
mini-boss, montent progressivement de palier et de précision, et restent en FT1.
Le mini-boss reste le pic de la branche, en FT2 et sans sortie. Les cinq
approches de `mini_optional_02` forment la plus longue chaîne ; celle de
`r09_mini1` est passée au thème Ilyr pour coïncider avec son deck miroir réel.

| Nœud | Nom | Dieu imposé | Mode | Palier | IA | Approches | Particularité |
| --- | --- | --- | --- | ---: | --- | ---: | --- |
| `mini_optional_01` | La Cloche des Fièvres | Nérava | Classique | 2 | 0,38 | 2 | Premier challenge facultatif |
| `r03_mini` | Le Jeu des Six Faces | Véskar | Aléatoire | 2 | 0,56 | 2 | Deux decks 100 % Aléators, sans neutre |
| `r04_mini` | Le Premier Essaim | Sylkha | Classique | 2 | 0,63 | 3 | Pic de fin de phase pré-épique |
| `r05_mini` | L'Encre Dévorante | Kharûn | Sélection | 3 | 0,68 | 3 | Premier challenge de Sélection |
| `r06_mini` | Le Colporteur de Peaux | Sylkha | Aléatoire | 3 | 0,75 | 3 | Générateur Sylkha à 8 cartes |
| `r09_mini1` | La Garde en Reflet | Ilyr | Miroir | 4 | 0,90 | 4 | Deck miroir fixe, 7 Veilleurs sur 8 cartes |
| `r09_mini2` | Le Chœur Noyé | Ilyr | Sélection | 4 | 0,90 | 4 | Draft Ilyr |
| `r10_mini` | Le Mime Absolu | Nérava | Sélection | 4 | 0,93 + anticipation | 4 | Draft Nérava |
| `r11_mini` | Le Rempart de Carapace | Kharûn | Classique | 4 | 0,96 + anticipation | 4 | Deck fixe de fin de campagne |
| `mini_optional_02` | Les Faces du Collectionneur | Énigma | Classique | 4 | 1,00 + anticipation | 5 | Deck fixe majoritairement Énigma |

Les cartes signées de Nérava, Sylkha, Kharûn et Énigma sont des decks fixes
explicites. Véskar et Sylkha utilisent l'Aléatoire avec un générateur filtré ;
Ilyr utilise le Miroir avec un deck fixe copié aux deux camps. Les modes
restent ceux du jeu partagé : aucune règle PVP n'est dupliquée dans la campagne.

Les 34 niveaux d'approche sont ajoutés sans supprimer aucune impasse ni rendre
un mini-boss obligatoire. Le graphe reste acyclique, les mini-boss facultatifs
restent les seuls nœuds qui ferment leur branche, et les anciennes sauvegardes
qui les avaient déjà vaincus reçoivent leurs niveaux d'approche terminés.

## Progression et déblocage

`CampaignUnlockRules` applique une seule règle :

1. Le nœud de départ est toujours accessible sur un profil neuf.
2. Terminer un nœud ouvre toutes ses sorties.
3. Un regroupement est accessible dès qu'un seul prédécesseur est terminé.
4. Aucune branche n'est exclusive.
5. Une branche secondaire reste disponible indéfiniment.
6. Un nœud terminé reste rejouable.

La progression ne sauvegarde jamais les decks générés, les offres de draft, une
route choisie ou un état réseau. Elle conserve uniquement les identifiants des
nœuds terminés, les tentatives, le dernier nœud consulté, les états de tutoriel
et l'archive de migration.

Deux mini-boss obligatoires commandent aussi l'accès global aux raretés :

- `r04_gate`, La Porte des Fontes, ouvre les cartes épiques. Aucun niveau
  antérieur ne dépasse le palier 2 ;
- `r07_gate`, La Cloche de Sève, ouvre les cartes légendaires. Aucun niveau
  antérieur ne dépasse le palier 3.

Ces jalons sont dérivés des nœuds terminés : aucune seconde copie de l'état
n'est ajoutée au profil. La boutique, les Rituels et les quêtes lisent tous la
même projection `ContentAccessState`.

## Migration des sauvegardes

`campaign_version` vaut `6`. La migration est idempotente et conserve les
victoires existantes.

- Un profil de l'ancienne campagne par dieu est converti seulement quand la
  victoire désigne un nœud sans ambiguïté ; les autres victoires sont archivées
  et les statistiques du profil restent intactes.
- Un profil de la campagne unifiée à 20 niveaux conserve ses vingt victoires.
  Si un ancien mini-boss facultatif est terminé, ses 2 à 5 nouveaux niveaux
  d'approche sont marqués terminés : la sauvegarde de référence passe ainsi à
  27 victoires, sans rejouer l'impasse. Les nouveaux nœuds du Carrefour et la
  suite de la Cime s'ouvrent derrière `boss_required_gate` déjà terminé.
- Un profil neuf démarre sur `tuto_01` avec la campagne à 162 niveaux.
- Une migration interrompue ou rejouée ne duplique pas les victoires et ne
  réinitialise jamais la progression.

Les identifiants des vingt nœuds historiques sont conservés. Les nouveaux
identifiants sont stables et n'entrent pas en collision avec les anciens.

## Carte et lisibilité

La carte est **virtualisée** : les 162 nœuds et les 190 arêtes restent dans les
données, mais seuls les nœuds des secteurs utiles possèdent un `Control`. Le
fond, les nœuds, les courbes et les points de contrôle partagent toujours le
même espace logique et le même facteur d'échelle.

- `CampaignMapLayout` calcule les positions, le rectangle visible logique et le
  défilement d'une ancre, sans instancier d'interface.
- `CampaignMapChunkManager` découpe la carte en secteurs de `540 × 360` unités.
  Ses marges sont directionnelles : davantage de contenu est préparé devant le
  geste que derrière lui. Une zone de conservation distincte évite les cycles
  chargement/déchargement sans garder plusieurs écrans inutiles en mémoire.
- `CampaignMapView` instancie la première zone par un lot initial de 8 nœuds,
  puis au maximum 6 nœuds par image. Les vues retirées sont recyclées dans un
  pool borné au lieu d'être recréées pendant chaque aller-retour. Le streaming
  n'est réévalué qu'après 120 unités logiques de déplacement.
- `CampaignMapRenderIndex` précalcule une seule fois les courbes et leur emprise
  verticale. `CampaignMapView` ne demande ensuite que les arêtes de la bande de
  rendu courante, avec une marge de sécurité de 420 unités ; cette liste n'est
  reconstruite qu'au passage d'une bande de 360 unités.
- `CampaignMapPositionState` conserve une ancre de niveau, un offset logique et
  une position de `ScrollContainer` de secours, avec un numéro de version. Il
  est stocké dans `CampaignProgress.map_navigation`, séparément des nœuds
  terminés et de `last_selected`.
- Le premier accès sans position sauvegardée ouvre au début. Les accès suivants
  restaurent l'ancre avant de charger la zone, sans parcourir les niveaux
  intermédiaires. Si l'ancre a disparu, le repli utilise le dernier niveau
  terminé existant, puis le focus disponible, puis le départ.
- La position est écrite après 0,65 s d'inactivité de défilement et lors de la
  fermeture ou du lancement d'un niveau ; elle n'est jamais écrite par pixel.
- L'indicateur « Chargement de la carte… » n'apparaît qu'après 0,28 s sans que
  la zone demandée soit prête. Il ne bloque aucune entrée et disparaît dès que
  le lot est terminé.
- Les nœuds ont un diamètre de 150 unités et une distance minimale mesurée de
  180 unités. Le placement local des approches conserve cette distance. Les
  courbes sont précalculées par l'index spatial et les nœuds disponibles seuls
  animent leur pulsation ; les 162 anciens `_process()` ne sont plus exécutés.
- Les labels de section sont limités aux chapitres proches du viewport.
- `CampaignSectionTheme` transforme les treize chapitres en bandes contiguës :
  la frontière entre deux chapitres est placée au milieu de leurs médianes Y,
  ce qui absorbe les plages qui se chevauchent. `CampaignSectionArt` dessine
  ensuite, dans le repère logique, un aplat sombre avec fondu, un emblème
  central en contour et des motifs de bord. Les alphas restent sous 0,50,
  0,16 et 0,07 ; seules les sections proches du viewport sont parcourues et
  aucun `Control` n'est créé.
- Le défilement, l'inertie, le toucher et le glissement sont testés sur les
  formats téléphone et tablette.

La carte reste volontairement haute : 19 800 unités pour 162 nœuds. Le
défilement est donc une partie normale de la navigation, pas un défaut de mise
en page.

Les approches des mini-boss facultatifs sont placées localement dans les
couloirs libres de leur impasse. Le builder ne décale pas globalement les nœuds
existants : il place les approches et leur mini-boss, puis décale seulement
`r12_a` et `r12_a1` de quelques dizaines d'unités pour ouvrir le couloir de
`r11_mini`. Les arêtes historiques gardent ainsi leur longueur et leur tracé,
au lieu de traverser la carte après l'insertion des nouveaux niveaux.

### Mesures de la refactorisation

Mesures headless sur la machine de développement, avec
`tests/MeasureCampaignMap.tscn` :

| Mesure | Avant | Après (mesure historique sur 154 nœuds) |
| --- | ---: | ---: |
| Lecture + validation structurelle du contenu | 5 849,65 ms | 30,78 ms |
| Construction de la vue | 47,84 ms | 5,82 ms |
| Ajout de la page complète | 59,86 ms | 9,41 ms |
| Nœuds visuels à l'ouverture | 154 | 8 immédiatement, 23 après 6 frames |
| Mémoire statique approximative | 49,06 Mo | 45,04 Mo |

Une seconde passe, destinée au défilement mobile, réduit dans la zone la plus
dense le maximum théorique de contrôles de nœud conservés de 73 à 44 (environ
40 %) et le nombre d'arêtes rendues de 88 à 37 (environ 58 %). Ces valeurs
proviennent du graphe actuel et d'un viewport logique de téléphone ; elles sont
vérifiées par `tests/CampaignMapOptimizationChecks.tscn`, qui parcourt toute la
hauteur de la carte et contrôle aussi la réutilisation du pool.

La validation complète des générations et de la géométrie reste exécutée par
`CampaignContentLoader.read(path, true)` avec `CampaignGenerationValidator` et
`CampaignLayoutValidator` ; elle n'est plus dans le chemin d'ouverture. Sur la
même mesure historique, les 154 générations réelles prenaient environ 9,03 s et les
contrôles structurels et géométriques environ 28 ms et 58 ms. Ces coûts sont
donc payés par les tests de livraison, jamais par le joueur. Les chiffres ne
constituent pas un objectif garanti sur tous les appareils, mais la réduction
du travail synchrone est structurelle, pas un simple masquage derrière un écran
de chargement.

### Chargement et déchargement

- Le rectangle de chargement utilise la taille réelle du viewport, la position
  du `ScrollContainer`, le sens du déplacement et des marges calculées en unités
  logiques ; il prend en compte les deux axes pour les branches latérales.
- Les demandes en double et les callbacks d'une carte fermée sont filtrés par
  les identifiants chargés/en attente et par la durée de vie des `Control`.
- Un nœud sélectionné qui sort de la zone garde son état logique ; il est
  reconfiguré avec cet état à son retour.
- Les vues hors zone sont réinitialisées puis placées dans un pool borné ; elles
  ne traitent plus aucune image tant qu'elles sont détachées.
- Les arêtes et repères sont filtrés par un index spatial immuable : aucun scan
  des 190 arêtes n'est effectué à chaque pixel ni à chaque lot de nœuds.
- La progression n'est jamais recalculée ni modifiée par un chargement ou un
  déchargement.

## Validation automatique

`CampaignValidator.problems(definition)` vérifie les invariants structurels et
les données immédiatement vérifiables. `CampaignGenerationValidator` prépare
réellement les decks et drafts, `CampaignProgressionValidator` garantit la
courbe, les FT et le caractère incontournable des jalons, tandis que
`CampaignLayoutValidator` contrôle
la distance des courbes aux nœuds. Ces deux validations coûteuses sont activées
par `CampaignContentLoader.read(path, true)` dans les tests de livraison, mais
pas à chaque clic sur Campagne.

Il vérifie :

- identifiants uniques, arêtes valides, absence de cycles ;
- nœud de départ, nœud final et nœuds accessibles ;
- cohérence des impasses et des mini-boss ;
- mini-boss facultatifs sans sortie ;
- mini-boss obligatoires non contournables ;
- mini-boss en FT2 et boss final en FT3 ;
- modes connus et préparation possible ;
- decks fixes légaux, au bon palier et avec huit lignées distinctes ;
- au moins trois cartes du dieu dans chaque deck fixe à dieu identifié ;
- dieu imposé connu et deck miroir fixe légal lorsqu'ils sont déclarés ;
- génération réelle des decks contraints, y compris les decks purs ;
- thème divin valide et positions dans la carte ;
- absence de collision majeure entre courbe et nœud.

`CampaignAudit` produit les métriques de livraison : nombre de niveaux, dieux,
modes, paliers, FT1/FT2/FT3, mini-boss, impasses, sorties, regroupements,
profondeur, séries consécutives de modes et de dieux, précisions, decks uniques,
minimum de cartes du dieu par deck fixe, doublons, nœuds inaccessibles, arêtes
dupliquées et cycles. Les tests de `CampaignAuditChecks` échouent si les
objectifs de contenu ne sont plus tenus.

### Decks

Les 94 decks fixes sont uniques. Aucun doublon exact n'est présent. Les 89 decks
à dieu identifié contiennent chacun au moins trois cartes de ce dieu. Les cinq
tutoriels Pr.Stone restent neutres. Les cinq premières rencontres du Carrefour
emploient chacune six cartes de palier 1 et seulement deux de palier 2. Les six
initiations imposent quant à elles quatre communes N1 du dieu et quatre
communes N1 neutres, identiques pour les deux camps.

Un deck fixe peut être :

- offensif, défensif ou équilibré ;
- centré sur le pouvoir du dieu ;
- régulier en puissance ou avec une carte forte compensée par des cartes moins
  coûteuses ;
- à coût total variable dans la limite de 80 points.

Les decks ne sont pas tous les huit meilleures cartes du palier et ne changent
pas d'une seule carte pour simuler une nouvelle identité.

## Ajouter ou modifier du contenu

Le JSON livré est généré. La source de vérité de construction est
`tools/build_campaign_v2.py` et la bibliothèque de decks est
`tools/campaign_deck_library.json`. La courbe par chapitre et les profils de
récompense vivent dans `data/campaign/authoring/balance_stages.json` et
`reward_profiles.json`. `tools/campaign_builder/` applique ces politiques sans
les mélanger au plan topologique.

### Ajouter un niveau

1. Ajouter le nœud dans le plan du builder, avec un identifiant stable.
2. Lui donner une section, une position, un type et une rencontre.
3. Relier ses prédécesseurs et successeurs dans les arêtes.
4. Déclarer `dead_end` et `mini_boss_kind` si nécessaire.
5. Régénérer :

   ```sh
   python tools/build_campaign_v2.py
   ```

6. Lancer `GodSystemChecks` : le validateur et l'audit doivent rester verts.

Pour un mini-boss à contrainte de génération, renseigner en plus
`generator_god_id` et, si nécessaire, `generator_min_god_cards` ou
`mirror_fixed_deck`. Un deck pur Véskar utilise `generator_min_god_cards: 8` ;
un Miroir Ilyr 7/8 utilise `mirror_fixed_deck` et un minimum de 7.

### Ajouter une branche

1. Choisir un nœud de divergence existant.
2. Ajouter au moins deux sorties non exclusives.
3. Faire diverger les rencontres par dieu, deck, mode, palier ou précision.
4. Rejoindre une branche à un regroupement existant ou nouveau.
5. Vérifier que le regroupement reste ANY et qu'aucune sortie n'est perdue.

Une branche ne doit pas être une simple décoration d'un niveau : elle doit
proposer une rencontre réellement différente.

### Ajouter un deck fixe

1. Choisir huit formes compatibles avec le dieu et le palier.
2. Vérifier huit lignées distinctes, le budget de 80 points et l'identité
   stratégique.
3. Valider le deck avec `DeckRules.validate_deck`.
4. Ajouter le deck à `tools/campaign_deck_library.json` avec un nom unique.
5. Le référencer dans le builder pour le nœud concerné.
6. Régénérer et vérifier l'audit des doublons.

### Ajouter un mini-boss FT2

1. Créer un nœud `mini_boss` avec `series_format: "ft2"`.
2. Choisir `optional` ou `mandatory`.
3. Pour un facultatif, ne déclarer aucune sortie et le placer au bout d'une
   impasse.
4. Pour un obligatoire, l'insérer sur un passage sans contournement.
5. Vérifier que le mode choisi prépare correctement une série FT2.
6. Lancer les tests de graphe, de série et de résultat.

## Tests et vérifications

Commandes de référence :

```sh
godot --headless --fixed-fps 60 --path . res://tests/GodSystemChecks.tscn
godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
```

La livraison exige zéro échec, zéro erreur Godot et zéro avertissement non
explicitement attendu. Le nombre de vérifications varie avec les contrats de
contenu et n'est volontairement pas figé dans cette documentation.

Mesure reproductible :

```sh
godot --headless --fixed-fps 60 --path . res://tests/MeasureCampaignMap.tscn
```

Les erreurs `PlayerData: profil non enregistré` et les avertissements de profil
illisible qui apparaissent dans les journaux sont provoqués par les tests
d'échec volontaires. Les lanceurs les distinguent des échecs réels et terminent
avec le code `0`.

## Limites connues

- La lisibilité finale doit encore être confirmée visuellement sur un téléphone
  Android exporté ; les tests headless valident les dimensions, les gestes et
  les collisions, pas le rendu d'un écran physique.
- La paire de tutoriels partage sept cartes sur huit ; c'est une exception
  pédagogique signalée par l'audit.
- Le cache de secteurs est volontairement simple : les `Control` libérés ne sont
  pas remis dans un pool. Le profilage ne montrait pas l'instanciation répétée
  comme coût dominant ; un pool pourra être ajouté si une mesure sur appareil
  réel le justifie.
- Le fichier `campaign_v1.json` reste une archive : toute modification de
  contenu doit être faite dans `campaign_v2.json` via le builder.
