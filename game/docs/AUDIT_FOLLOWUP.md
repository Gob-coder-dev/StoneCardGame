# Suivi des corrections de l'audit

Passe corrective du 14 novembre 2026, projet 0.8.1, Godot 4.7.2.
Les modifications concernent le jeu et ses outils de validation. Les règles de
combat, l'équilibrage de la campagne et les illustrations originales sont conservés.

## Fiabilité du jeu

| Constat | Correction |
| --- | --- |
| Une quotidienne déjà payée pouvait ne plus payer les jours suivants | La preuve du paiement quotidien est le couple jour/palier enregistré avec la récompense. Les anciennes clés sans date ne bloquent plus les jours suivants. |
| Le recul de l'horloge pouvait rouvrir un ancien jour | Le journal ne remplace un jour que par un jour ultérieur. |
| Les événements de campagne confondaient les manches d'une même tentative | La clé contient campagne, niveau, tentative et manche. Les captures de chaque manche et la victoire finale FT2/FT3 sont distinctes. |
| Un réessai après une panne tardive pouvait recalculer une récompense de replay | `CampaignResultPersistence` conserve le résultat, la nature de la victoire et la tentative. Les étapes déjà réussies ne sont pas exécutées à nouveau dans la session. |
| Une récompense affichée pouvait devenir nulle après réessai | La récompense réussie reste attachée à la même opération de résultat. |
| Les achats et leurs compteurs de quête étaient deux écritures indépendantes | Boutique, amélioration et Rituel passent par `EconomyTransaction`, qui enregistre inventaire et quêtes dans le même profil. Les événements séparés ont été retirés des écrans. |
| Un deck neutre invalide pouvait laisser les nouvelles quêtes en mémoire | Le rejet restaure aussi l'état précédent des quêtes. |
| Des statistiques mal formées pouvaient casser les calculs | `IntegerValue`, `ProfileStatsRules`, les règles de cartes et les modèles de quête/inventaire nettoient les valeurs relues. La rotation de boutique est validée avant utilisation. |
| Un ancien exécutable pouvait réécrire un profil futur | La version est vérifiée au chargement ; les écritures sont bloquées pour les profils plus récents. Le format actuel est 11. |
| Le client PVP restait bloqué après un coup refusé | Le refus libère l'intention en attente ; le client peut rejouer. La validation locale précède l'envoi. |
| Une intention PVP sans réponse pouvait attendre indéfiniment | Le délai de confirmation couvre aussi l'attente avant acceptation de l'intention. |
| Le résultat PVP précédait la preuve du dernier tour | L'hôte garde le résultat en attente jusqu'à l'accord des empreintes. Une désynchronisation annule ce résultat. |
| Des messages tardifs pouvaient agir après interruption ou fin | Une interruption ferme le coordinateur ; un résultat dupliqué n'émet pas une seconde fin. |
| La progression des illustrations ne fonctionnait pas pour un profil sans dieu | L'activité du préchauffage est explicite et le catalogue neutre est pris en charge. |
| Le test tactile supposait toujours une offre achetable | La fixture de défilement prépare un profil de départ et vérifie la présence des offres avant de les manipuler. Une collection historique complète pouvait légitimement produire une boutique vide. |
| La fermeture pouvait signaler des playbacks audio encore actifs | Arrêt des lecteurs et court délai réel avant fermeture. Les tests vérifient aussi les diagnostics de sortie. |
| Le tout premier import pouvait échouer sur le thème | La palette est préchargée explicitement. La correction complémentaire ci-dessous supprime aussi tout script de la ressource chargée avant l'arbre. |

## Architecture et code

Les responsabilités ajoutées sont séparées par intention :

- `QuestEventRules` traduit une action en compteurs ; `QuestJournal` prépare le
  journal ; `QuestService` expose consultation et réclamation.
- `EconomyTransaction` réunit achat et compteurs avant l'écriture ;
  `CardRewardGrant` applique la politique commune de copies, coffre et compensation.
- `CampaignResultPersistence` possède l'avancement d'une sauvegarde de résultat ;
  `BattleContext` conserve le contexte transitoire des écrans.
- `ProfileStatsRules` calcule et normalise les statistiques sans stockage.
- `JsonFile`, `SeededShuffle` et `PathNodeButton` remplacent les lectures JSON,
  mélanges déterministes et comportements de parcours répétés.
- Le salon lit directement l'état de `PvpLobbyFlow`, sans ses neuf propriétés relais.

Les anciennes générations uniformes de draft et de suites de coûts sans appelant,
leurs caches/constantes, plusieurs méthodes inutilisées et un UID orphelin ont été
retirés. Les tests des voisins du plateau utilisent maintenant l'API d'instance,
qui respecte aussi les plateaux 3×3.

| Fichier simplifié | Lignes avant | Lignes après |
| --- | ---: | ---: |
| `LoadoutGenerator.gd` | 586 | 401 |
| `BattleContext.gd` | 375 | 300 |
| `QuestService.gd` | 441 | 294 |
| `PvpLobbyController.gd` | 748 | 709 |

Les longues opérations de `CampaignAudit`, `CampaignValidator` et
`CampaignMatchDriver` sont découpées en phases nommées. Les méthodes d'audit
conservent leurs mêmes clés et les contrôles de contenu continuent de passer.
Quelques fonctions de validation de schémas et de construction visuelle restent
au-delà de 60 lignes : cette longueur reste acceptable lorsqu'elles décrivent une
seule table cohérente. Une limite numérique ne remplace pas la cohésion.

Le code de production passe de 36 333 à 36 419 lignes environ (+0,24 %) : les
validations et services explicites compensent le code mort supprimé. Le travail
vise la fiabilité et la suppression des répétitions, pas une minification.

Les commentaires expliquent les invariants, politiques et limites de reprise.
README, architecture et guide de qualité décrivent maintenant le format 11,
les transactions et les règles d'import. Le générateur Python ne publie plus de
fichier et n'imprime plus de rapport lors d'un simple import de module.

## Performance, ressources et Git

- Le clonage d'un état de combat n'alloue plus un plateau vide jetable ; le RNG
  est réutilisé dans chaque état tout en conservant le hasard cloné indépendant.
- La préparation lit directement son chronomètre. Elle ne recopie plus les deux
  loadouts et l'état complet à chaque image.
- Dialogue et spotlight arrêtent leur traitement au repos. La musique suit
  le signal de changement de scène au lieu de sonder la scène à chaque image.
- Le catalogue de lignées utilise son index plutôt que de recopier toutes les formes.
- Les transactions répétées de campagne utilisent des curseurs ordonnés. Le test
  de 4 000 actions confirme deux curseurs et la conservation de la protection
  contre les doublons. Les récompenses uniques conservent leurs preuves permanentes.
- Les 275 images de cartes et les huit portraits ont une limite d'import de
  768 pixels. Les PNG originaux et les mipmaps sont conservés.
- Les fichiers voisins `<asset>.import` et les `.gd.uid` sont à versionner.
  `.godot/`, les anciens caches `.import/`, captures de tests, APK, journaux,
  répertoires temporaires et secrets restent ignorés. Aucun cache Godot n'est suivi.
- L'export exclut tests, outils, anciennes données de campagne, sources audio
  alternatives et données de conception. Son contenu est inspecté automatiquement.

| Mesure comparable | Ancien APK présent sur le poste | Export de contrôle corrigé |
| --- | ---: | ---: |
| Ressources importées compressées | 402,53 Mio | 187,67 Mio |

La baisse mesurée de ces ressources est d'environ **53 %**. Le ZIP de données
complet fait **188,97 Mio**. Ce ZIP ne contient pas les bibliothèques Android,
contrairement à l'ancien APK de 431,69 Mio : ces deux tailles totales ne sont
pas directement comparables. Aucune mesure de RAM GPU sur téléphone n'est déduite
de la taille des fichiers.

## Validation effectuée

Les mêmes contrôles ont été lancés depuis une copie du jeu **sans `.godot/`**,
avec réimport complet et répertoires utilisateur temporaires :

| Contrôle | Résultat |
| --- | --- |
| Premier import sans cache | Réussi, aucune erreur de script |
| `GodSystemChecks` | 2 088 réussies, 0 échec, 0 erreur Godot inattendue |
| `TouchInputChecks` | 108 réussies, 0 échec, 0 erreur Godot inattendue |
| `EconomyCampaignChecks` | 471 réussies, 0 échec, 0 erreur Godot inattendue |
| Fermeture des trois scènes | Aucun diagnostic de fuite de ressource/instance |
| Tests Python d'authoring | 2 réussis : import sans écriture et campagne générée identique à la livraison |
| Export ZIP | Réussi, aucun fichier des répertoires exclus |
| Références littérales de ressources | Aucun chemin manquant trouvé |
| Sources JSON et Python | Analyse réussie |
| `git diff --check` | Réussi |

La suite ciblée recouvre une partie de la suite principale : ses assertions ne
doivent pas être additionnées pour annoncer une couverture indépendante.
Les tests de panne annoncent volontairement certains messages ; `TestLog`
les distingue des erreurs réelles. Le poste émet aussi un diagnostic de magasin
de certificats Windows et un avertissement de SDK Android non configuré,
sans erreur de script ni échec de l'export de données.

Pour reproduire depuis la racine :

```powershell
python game/tools/check_quality.py --godot godot --import --export
python -m unittest discover -s game/tools/tests -v
```

Le lanceur conserve ses diagnostics dans `.tmp/quality/`. Le workflow
`.github/workflows/game-quality.yml` prépare les mêmes vérifications sur GitHub.
Il a été ajouté localement ; aucune exécution distante ni publication n'a été effectuée.

## Vérifications restantes sur matériel

Une note absolue de « 10/10 » ne serait pas vérifiable à partir de ces seuls
contrôles. Il reste à produire un APK avec le SDK Android, vérifier les images
768 pixels en plein écran et mesurer démarrage, mémoire et fluidité sur téléphone
et tablette. Le PVP doit aussi être essayé entre deux appareils réels, notamment
pendant une perte de réseau, une mise en veille et la fin d'une série.

La reprise de résultat mémorise ses étapes pendant la session ; les fichiers de
profil et de campagne restent distincts. Une garantie de transaction unique
durable entre ces fichiers demanderait un journal de reprise persistant séparé.
Les tests présents couvrent les échecs d'écriture et réessais dans la session,
pas toutes les interruptions matérielles possibles.

## Complément : diagnostics visibles dans l'éditeur

Le lancement avec le débogueur connecté a révélé une lacune des vérifications
précédentes : Godot transmet les avertissements de compilation directement au
débogueur, sans les envoyer au logger des suites. Une exécution headless seule
ne permettait donc pas d'annoncer l'absence de ces avertissements.

La ressource de thème est maintenant constituée de données sans script. La
fabrique ne travaille qu'après création du SceneTree ; l'aperçu de l'éditeur
est généré par `BakeInterfaceTheme`, avec UID et identifiants de styles stables.
Cela supprime le code exécuté pendant le chargement précoce du thème.

Les avertissements réels ont été traités : variables et paramètres ne masquent
plus une fonction, une classe ou une propriété ; les divisions entières sont
explicites ; les branches de types incompatibles et les conversions vers `Error`
sont clarifiées ; les paramètres et variables réellement inutilisés sont retirés.
Les clés JSON et réseau, notamment `seed`, restent inchangées. Quelques signaux
de contrat utilisés par leurs collaborateurs ont une annotation ciblée et documentée.

Le lanceur connecte désormais un débogueur local avant le chargement du jeu,
compile les 238 scripts de production et vérifie l'accueil. Il échoue sur tout
diagnostic d'application et conserve les messages reçus en JSON. Le diagnostic
de certificats natif Windows reste visible et identifié séparément.

Validation de ce complément depuis une nouvelle copie sans cache : import
réussi, **0 diagnostic d'application** avec débogueur connecté, 2 088
vérifications principales et 108 tactiles réussies, export de contrôle conforme.
Une injection volontaire de paramètre masquant la fonction `seed` dans cette
copie temporaire fait bien échouer le contrôle ; le fichier de test est ensuite
retiré. Deux régénérations successives du thème donnent le même contenu.
Les journaux sont dans `.tmp/quality/debugger-fix/clean/` ; le refus attendu
du test de garde est conservé séparément dans `expected-warning/`.
