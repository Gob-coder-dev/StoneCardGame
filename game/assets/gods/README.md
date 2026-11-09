# Portraits des dieux

Ces six PNG reprennent les illustrations déjà retenues, à leur résolution
native de 1254 × 1254 pixels, avec leur transparence. Ils sont livrés avec le
jeu ; leur affichage ne dépend pas des documents de conception locaux.

| Fichier | Dieu |
| --- | --- |
| `veskar.png` | Véskar, le Manipulateur |
| `nerava.png` | Nérava, la Mère des Fièvres |
| `kharun.png` | Kharûn, la Muraille |
| `ilyr.png` | Ilyr, le Guetteur Éternel |
| `sylkha.png` | Sylkha, la Mère-Ruche |
| `enigma.png` | Énigma, la Machine Première |

Le champ `asset` de [gods.json](../../data/gods.json) fournit le portrait à
l'accueil, au sélecteur de dieu et aux rencontres. Les identifiants historiques
des dieux restent inchangés pour préserver les sauvegardes.

## Identités sans dieu

Deux illustrations distinctes représentent l'absence de dieu sans créer de
nouveau dieu jouable :

| Fichier | Rôle |
| --- | --- |
| `sans_dieu.png` | Identité du joueur humain qui ne choisit aucun dieu |
| `pr_stone.png` | Portrait de Pr.Stone, adversaire IA sans dieu |

`GodIdentity` ([scripts/data/GodIdentity.gd](../../scripts/data/GodIdentity.gd))
résout ces deux identités : un humain sans dieu reçoit `sans_dieu.png`, un bot
sans dieu reçoit `pr_stone.png`. Pr.Stone reste hors de `gods.json` pour ne
jamais devenir un dieu jouable.

Conserver les fichiers `.png.import` : compression sans perte, taille d'origine
et mipmaps. Les six portraits divins proviennent des créations antérieures ;
les deux identités sans dieu ont été ajoutées pour distinguer le joueur du bot.
