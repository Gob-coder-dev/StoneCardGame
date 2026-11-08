# Campagne unifiée

La campagne est un graphe orienté acyclique unique, chargé depuis
`data/campaign/campaign_v2.json`. Elle contient **120 niveaux**, **148 arêtes**
et **12 sections visuelles** sur une seule carte de **1080 × 16920** unités.
`CampaignContentLoader.DEFAULT_PATH` pointe vers ce fichier et
`campaign_version` vaut `2`.

L'ancien fichier `campaign_v1.json` reste dans le dépôt comme archive et source
de comparaison historique. Il n'est plus chargé par le jeu.

## Contenu livré

| Mesure | Valeur |
| --- | --- |
| Niveaux | 120 |
| Arêtes | 148 |
| Sections visuelles | 12 |
| Profondeur minimale / maximale | 0 / 65 |
| Plus longue série de mode | 6, dans l'introduction |
| Plus longue série d'un même dieu | 3 |
| Carte logique | 1080 × 16920 |
| Niveaux du Professeur Stone | 3 |
| Mini-boss facultatifs | 10 |
| Mini-boss obligatoires | 4 |
| Mini-boss en FT2 | 14 |
| Séries FT1 / FT2 / FT3 | 99 / 20 / 1 |
| Decks fixes uniques | 69 |
| Générateurs contraints | 2 (Véskar, Ilyr) |
| Decks miroirs fixes | 1 (Ilyr) |
| Cartes du dieu par deck fixe | 3 minimum |

### Dieux

Les trois premiers nœuds sont des tutoriels du Professeur Stone, sans thème
divin. Les 117 autres nœuds sont répartis entre les six dieux.

| Dieu | Nœuds thématiques | Nœuds à dieu réellement fixé |
| --- | ---: | ---: |
| Véskar | 20 | 15 |
| Nérava | 20 | 15 |
| Kharûn | 19 | 14 |
| Énigma | 20 | 14 |
| Ilyr | 19 | 14 |
| Sylkha | 19 | 14 |

Le total des nœuds à dieu fixé est de 86. Les autres rencontres utilisent les
règles de génération de leur mode ; leur `theme_god_id` sert à l'accent visuel et
au libellé d'inspiration, pas à verrouiller le tirage.

### Modes

| Mode | Niveaux |
| --- | ---: |
| Classique | 72 |
| Aléatoire | 18 |
| Miroir | 12 |
| Sélection | 18 |

Les tutoriels sont Classiques. L'Aléatoire apparaît au Carrefour, le Miroir suit
immédiatement, puis la Sélection rejoint les autres modes. Aucun mode ne
disparaît en fin de campagne.

Soixante-neuf Classiques utilisent un deck fixe explicite. Les exceptions
Classiques restent déclarées dans les politiques de deck et ne changent pas les
règles du mode.

### Paliers

| Palier maximal | Niveaux |
| --- | ---: |
| 1 | 2 |
| 2 | 32 |
| 3 | 52 |
| 4 | 34 |

Le palier est calculé avec `CardPowerTierRules` : niveau de forme plus décalage
de rareté, avec l'exception explicite éventuelle du catalogue. Une légendaire
niveau 1 n'est donc pas une carte de palier 1.

### Précision de l'IA

Les 120 profils utilisent **37 valeurs distinctes** entre 0 et 1. Cent nœuds
utilisent une valeur qui n'est pas un multiple de 0,25. La précision suit la
profondeur et la fonction de la rencontre, sans progression strictement
linéaire.

| Tranche de profondeur | Niveaux | Précision minimale | Précision maximale | Moyenne |
| --- | ---: | ---: | ---: | ---: |
| 0–19 | 34 | 0,00 | 0,98 | 0,376 |
| 20–39 | 32 | 0,04 | 0,93 | 0,439 |
| 40–59 | 40 | 0,04 | 0,96 | 0,677 |
| 60–79 | 14 | 0,50 | 1,00 | 0,841 |

Les mini-boss et les rencontres majeures servent de pics ; les nœuds qui suivent
une impasse ou un mini-boss peuvent redescendre pour laisser respirer le joueur.
Une bonne précision ne signifie pas nécessairement un deck plus puissant : les
profils combinent cartes modestes et IA précise, ou cartes fortes et IA moyenne.

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
| Seuil | 3 |
| Carrefour | 12 |
| Le Marais des Serments | 10 |
| Les Forges Basses | 10 |
| La Bibliothèque des Os | 10 |
| Le Marché Nocturne | 10 |
| Les Serres de Verre | 10 |
| Les Remparts Muets | 10 |
| Le Puits des Échos | 10 |
| La Cour des Masques | 10 |
| Les Jardins de Cendre | 10 |
| Cime | 15 |

Le Carrefour contient les trois tutoriels, les branches d'introduction, les
premiers mini-boss et les routes parallèles. Les neuf régions intermédiaires
utilisent neuf topologies différentes : elles ne sont pas des copies d'un même
groupe de cinq niveaux. La Cime réunit les dix nouveaux nœuds finaux et les cinq
nœuds finaux historiques.

## Format de `campaign_v2.json`

Le fichier est la source de vérité du contenu livré. Il est produit par
`tools/build_campaign_v2.py` et validé par `CampaignValidator` puis
`CampaignAudit`.

```json
{
  "id": "samstone_campaign",
  "title": "La Carte de SamStone",
  "campaign_version": 2,
  "map": {"width": 1080, "height": 16920},
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
          "le_sac_a_murmures_n1"
        ],
        "max_power_tier": 1,
        "ai_profile": {"precision": 0.0, "anticipation": false},
        "series_format": "ft1",
        "seed_policy": "fixed_per_node",
        "seed": 5000
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
| `tutorial_id` | Identifiant de tutoriel, vide hors des trois tutoriels |
| `theme_god_id` | Dieu d'accent et d'inspiration ; vide pour les tutoriels |
| `accent` | Couleur ou famille d'accent de la carte |
| `encounter` | Rencontre préparée par `CampaignEncounterFactory` |
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
| `seed_policy` | `fixed_per_node` par défaut ; `per_attempt` reste une exception explicite |
| `seed` | Graine déterministe de la rencontre |

Un deck fixe doit contenir exactement huit cartes, huit lignées distinctes,
respecter le dieu, le palier et le budget de 80 points. Pour un deck à dieu
identifié, au moins trois cartes doivent appartenir à ce dieu ; les cartes
neutres ne comptent pas dans ce minimum. Les tutoriels Pr.Stone restent
entièrement neutres. La validation utilise `DeckRules.validate_deck`, pas une
règle parallèle.

Les champs de génération sont optionnels et additifs. `generator_god_id` filtre
le pool du mode Aléatoire ou Miroir ; `generator_min_god_cards: 8` ne conserve
que les cartes du dieu, ce qui produit deux decks purs pour Véskar. Un
`mirror_fixed_deck` non vide est validé comme un deck de huit cartes, puis copié
pour les deux camps. Le validateur vérifie les mêmes règles de palier, de
lignées, de budget et de minimum de cartes du dieu que pour un deck fixe.

### Graine

Le mode Aléatoire, le Miroir et la Sélection utilisent une graine déterministe
dérivée de `campaign_version`, de l'identifiant du nœud et de la graine du
nœud. Rejouer un même nœud conserve donc son identité. Une politique
`per_attempt` ne doit être choisie que pour une rencontre explicitement conçue
pour changer à chaque tentative.

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
  victoire ouvre la suite obligatoire.
- Les rencontres ordinaires restent majoritairement en FT1.
- Le boss final utilise FT3.
- Une égalité ne donne aucun point et ouvre une manche supplémentaire.

Les 14 mini-boss sont en FT2. Six autres rencontres majeures utilisent aussi
FT2 : quatre nœuds de milieu ou de fin de campagne et deux rencontres
historiques (`veskar_02`, `kharun_02`). Le total est de 20 FT2.

### Six mini-boss signés

Six mini-boss facultatifs existants portent une identité de génération propre :
ils ne créent aucun nœud ni aucune arête supplémentaire et restent dans leur
impasse FT2.

| Nœud | Nom | Dieu imposé | Mode | Palier | IA | Particularité |
| --- | --- | --- | --- | ---: | --- | --- |
| `mini_optional_01` | La Cloche des Fièvres | Nérava | Classique | 2 | 0,35 | Deck fixe 100 % Flétri, 4 N2 + 4 N1 |
| `r03_mini` | Le Jeu des Six Faces | Véskar | Aléatoire | 3 | 0,55 | Deux decks 100 % Aléators, sans neutre |
| `r04_mini` | Le Premier Essaim | Sylkha | Classique | 2 | 1,00 + anticipation | Deck fixe 5 N1 + 3 N2 |
| `r09_mini1` | La Garde en Reflet | Ilyr | Miroir | 4 | 0,80 | Deck miroir fixe, 7 Veilleurs sur 8 cartes |
| `r11_mini` | Le Rempart de Carapace | Kharûn | Classique | 4 | 0,85 | Deck fixe à 58 boucliers, avec `carapace_vide_n4` |
| `mini_optional_02` | Les Faces du Collectionneur | Énigma | Classique | 4 | 0,90 | Deck fixe majoritairement Énigma |

Les cartes signées de Nérava, Sylkha, Kharûn et Énigma sont des decks fixes
explicites. Véskar utilise le mode Aléatoire avec un générateur filtré ; Ilyr
utilise le mode Miroir avec un deck fixe copié aux deux camps. Les deux modes
restent les modes partagés : aucune règle PVP n'est dupliquée dans la campagne.

Pour conserver la répartition 72/18/12/18, deux rencontres ordinaires
compensent les changements de mode : `r05_b2` passe en Sélection et `r10_b1`
en Miroir.

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

## Migration des sauvegardes

`campaign_version` vaut `2`. La migration est idempotente et conserve les
victoires existantes.

- Un profil de l'ancienne campagne par dieu est converti seulement quand la
  victoire désigne un nœud sans ambiguïté ; les autres victoires sont archivées
  et les statistiques du profil restent intactes.
- Un profil de la campagne unifiée à 20 niveaux conserve ses vingt victoires.
  Les nouveaux nœuds du Carrefour et la suite de la Cime s'ouvrent derrière
  `boss_required_gate` déjà terminé, sans exiger de recommencer les vingt
  niveaux.
- Un profil neuf démarre sur `tuto_01` avec la campagne à 120 niveaux.
- Une migration interrompue ou rejouée ne duplique pas les victoires et ne
  réinitialise jamais la progression.

Les identifiants des vingt nœuds historiques sont conservés. Les nouveaux
identifiants sont stables et n'entrent pas en collision avec les anciens.

## Carte et lisibilité

`CampaignMapView` rend les 120 nœuds dans le même espace logique que les
arêtes : fond, nœuds, courbes et points de contrôle partagent les coordonnées du
fichier de campagne.

- Les nœuds ont un diamètre de 150 unités et une distance minimale mesurée de
  180 unités.
- Le validateur impose une distance minimale de 170 unités et une clearance de
  76 unités entre une courbe et un nœud non relié ; toutes les arêtes livrées
  respectent ce seuil.
- Les courbes sont mises en cache et ne sont pas recalculées à chaque image.
- Les 12 labels de section sont dessinés dans la carte, pas dans un panneau
  séparé.
- Le défilement, l'inertie, le toucher et le glissement sont testés sur les
  formats téléphone et tablette.
- La caméra se centre sur la dernière zone pertinente et ne revient pas
  systématiquement en haut de la carte.

La carte reste volontairement haute : 16 920 unités pour 120 nœuds. Le
défilement est donc une partie normale de la navigation, pas un défaut de mise
en page.

## Validation automatique

`CampaignValidator` vérifie les invariants structurels et de contenu :

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

Les 69 decks fixes sont uniques. Aucun doublon exact n'est présent. Les 66 decks
à dieu identifié contiennent chacun au moins trois cartes de ce dieu ; la
répartition finale est de 39 decks à 3 cartes, 20 à 4 et 7 à 5. Les trois
tutoriels Pr.Stone restent neutres. L'audit signale une seule paire partageant
sept cartes sur huit : `tuto_01` et `tuto_02`, qui utilisent volontairement des
cartes neutres différentes du même petit palier pédagogique. Cette exception est
explicitement signalée, pas masquée.

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
`tools/campaign_deck_library.json`.

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

Dernière validation du contenu livré :

```text
GOD_SYSTEM_CHECKS: 1379 passed, 0 failed, 0 Godot errors
TACTILE : 95 vérifications, 0 échec(s), 0 erreur(s) Godot.
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
- Le fichier `campaign_v1.json` reste une archive : toute modification de
  contenu doit être faite dans `campaign_v2.json` via le builder.
