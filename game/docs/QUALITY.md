# Qualité du code et livraison

Ce document fixe les critères de maintenance du jeu. Il complète
[`ARCHITECTURE.md`](ARCHITECTURE.md) sans dupliquer les règles fonctionnelles.

## Frontières

| Couche | Peut connaître | Ne doit pas connaître |
| --- | --- | --- |
| `domain/` | valeurs, catalogues en lecture, règles pures | scènes, transport, sauvegarde |
| `engine/` | domaine et état d'un combat | menus, campagne, sockets |
| `application/` | cas d'usage, domaine, ports de persistance/réseau | composition visuelle des scènes |
| `data/` | chargement, validation, migration, stockage | navigation et rendu |
| `network/` | protocole et transport | interface et profil persistant |
| `ui/` | projection des services et intentions du joueur | nouvelle règle métier |

Une façade de compatibilité doit annoncer explicitement sa destination, comme
`scripts/data/PvpMatchContext.gd`. Elle ne doit pas recevoir de nouvelle logique.

Le guidage interactif constitue une frontière explicite : `StoryService` et
`TutorialDirector` peuvent conserver des références faibles vers des ancres
`Control` afin de séquencer un tutoriel. Ils ne créent toutefois aucun contrôle,
ne composent aucune scène et délèguent entièrement le rendu à `ui/story/`.

## Fonctions et fichiers

- Une fonction porte une intention. Au-delà d'environ 60 lignes, vérifier si
  validation, transformation et effets de bord peuvent être nommés séparément.
- Une longueur supérieure reste acceptable pour une table de validation ou une
  construction de rapport pure si le découpage masquerait les invariants.
- Un contrôleur de scène coordonne plusieurs composants, mais ne recalcule pas
  leurs règles. Les calculs partagés exposent une projection unique, par exemple
  `PlayerData.card_upgrade_state()` pour les vues d'amélioration.
- La concision n'est pas un objectif isolé : deux lignes opaques ne remplacent
  pas dix lignes qui rendent un protocole ou une transaction vérifiable.

## Commentaires

Chaque script de production commence par sa mission et ses limites. Les
commentaires expliquent une contrainte, un invariant ou une raison ; ils ne
paraphrasent pas l'instruction suivante. Les migrations et façades historiques
indiquent pourquoi elles existent encore et leur condition de suppression.

Les guides de production artistique, dont `PROMPTS_FOOOCUS.md`, sont de la
documentation de contenu. Les consignes propres à un assistant ou à un poste de
travail restent hors du code et sont ignorées par Git.

## Performance

- Aucun chargement de fichier ou d'image ne doit être déclenché dans `_draw()`.
- Les `_process()` sont désactivés lorsqu'ils n'ont plus de travail.
- Les grandes listes réutilisent leurs vues ou chargent par secteurs.
- Une animation ne possède jamais une transaction : la sauvegarde précède sa
  présentation.
- Une optimisation doit viser une mesure ou supprimer un travail répété ; elle
  ne doit pas introduire un second cache sans cycle de vie explicite.

### Mesures du cache des menus et des textures

Mesures isolées sous Windows avec Godot 4.7.2 headless, comparées au commit
`6ee13a2`. Les délais sont les médianes de sept séries après échauffement.
Le profil avancé utilise les données du catalogue historique et la pastille
affiche les mêmes 20 paliers dans les deux versions.

| Opération sur le profil avancé | Avant | Après |
| --- | ---: | ---: |
| Clés du cache des trois pages Cartes, Quêtes et Boutique | 235 µs | 2,4 µs |
| Calcul de la pastille de quêtes | 2,81 ms | 1,26 ms |

L’échantillon de textures contient trois cartes de chacun des sept dossiers
d’illustrations et les portraits d’Énigma, Sylkha et Véskar. À résolution et
mipmaps identiques, les fichiers `.ctex` occupent 15,27 Mio sans perte,
6,28 Mio à la qualité WebP 0,92 et 5,26 Mio à la qualité 0,85. Ces chiffres
concernent le stockage des fichiers importés. WebP avec ou sans perte utilise
des textures décompressées en mémoire graphique. Les réglages livrés restent
sans perte jusqu’à la vérification des contours, des détails et de la
lisibilité sur le plateau et dans la fiche de carte sur appareil.
[Documentation Godot sur les textures](https://docs.godotengine.org/en/4.6/classes/class_compressedtexture2d.html)

Pour une comparaison Android, utiliser le même téléphone, la même version
d’Android, le même profil de jeu et le même taux de rafraîchissement. Relever
`TotalTime` sur plusieurs démarrages à froid et le `TOTAL PSS` après stabilisation
de l’accueil puis du combat. Mesurer le délai jusqu’à un accueil utilisable
séparément du temps de lancement de l’activité. [Mesures de démarrage](https://developer.android.com/topic/performance/baselineprofiles/manually-create-measure) · [Mesures mémoire](https://developer.android.com/tools/dumpsys)

```powershell
adb devices -l
adb shell am force-stop com.beastpact.game
adb shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.beastpact.game
adb shell dumpsys meminfo com.beastpact.game
```

Pour les saccades, relever les percentiles 50, 95 et 99 des intervalles de
présentation du calque du jeu pendant la même séquence accueil → collection →
carte → combat. Si le téléphone expose l’histogramme `present2present` du
calque, réinitialiser `adb shell dumpsys SurfaceFlinger --timestats -clear`,
activer la collecte avec `-enable` avant la séquence puis exporter avec `-dump`.
N’interpréter les résultats que si le calque du jeu apparaît dans le relevé.
[Collecte TimeStats AOSP](https://android.googlesource.com/platform/frameworks/native/+/master/services/surfaceflinger/TimeStats/TimeStats.cpp)

## Git

Les sources `.gd.uid`, les fichiers `<asset>.import`, les scènes, ressources,
données et `export_presets.cfg` sont versionnés. Les `.import` voisins des images
et sons conservent les réglages d'import ; le contenu généré de `.godot/` et de
l'ancien dossier `.import/` est exclu. Les bytecodes Python, builds, APK, secrets
de signature, captures de tests, journaux et métadonnées locales d'outils sont
également exclus par le `.gitignore` racine.

Les illustrations de cartes et portraits sont importés avec une limite de
768 pixels, sans modifier les PNG sources. Les mipmaps et les réglages audio
restent explicites. Les exports excluent tests, outils, sources audio alternatives,
données de conception et ancienne campagne ; le lanceur inspecte le ZIP obtenu.

## Validation avant livraison

Depuis la racine du dépôt :

```powershell
python game/tools/check_quality.py --godot godot --import --export
python -m unittest discover -s game/tools/tests -v
git diff --check
git status --short
```

Le lanceur utilise un répertoire utilisateur temporaire par processus, échoue
sur erreur de script, code de sortie non nul ou ressource encore active à la
fermeture, et garde les journaux dans `.tmp/quality/`. Les messages attendus des
tests de panne sont distingués des erreurs réelles par `TestLog`. La CI GitHub
Actions utilise Godot 4.7.2, réimporte les ressources et vérifie le contenu exporté.
Elle ne signe ni ne publie d'application.

Avant les suites, un récepteur de débogage local se connecte dès le démarrage.
`StartupChecks` compile tous les scripts de production et initialise l'accueil.
Toute erreur ou tout avertissement de compilation reçu fait échouer le contrôle :
ces avertissements sont envoyés au débogueur et ne passent pas par `TestLog`.
Les messages capturés sont conservés dans `StartupChecks.debugger.json`.
Le diagnostic natif du magasin de certificats Windows est identifié séparément
et reste visible ; les autres erreurs moteur restent bloquantes.

Les exceptions `unused_signal` sont limitées aux déclarations de contrats dont
les signaux sont émis par une sous-classe ou un collaborateur identifié dans le
commentaire. Les avertissements du projet restent activés.

Les cinq suites standard doivent terminer avec le code `0`. Elles couvrent le
jeu, les entrées, la navigation, l’équilibrage de campagne et le streaming de
la carte. Une vérification visuelle
reste obligatoire sur téléphone et tablette pour les proportions, gestes,
transitions et coûts de première ouverture.

Les résultats de la passe corrective sont consignés dans
[`AUDIT_FOLLOWUP.md`](AUDIT_FOLLOWUP.md).
