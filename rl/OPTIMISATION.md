# Optimisation du RL — seconde passe

Les cinq étapes de travail ont été menées : référence mesurée, réduction des
coûts techniques, compaction des calculs tactiques, essai de parallélisation,
puis calibrage et validation technique. Les règles, les features du réseau et
l’algorithme PPO conservent leur signification.

## Changements retenus

- Captures : calcul limité aux actions légales et aux échantillons d’attaque
  distincts, puis restitution dans le format public habituel.
- Ripostes : calcul sur des vecteurs contigus regroupant les actions légales.
  Les échantillons sont partagés seulement si leurs propriétaires et défenses
  sont identiques **après** résolution de tous les effets.
- Voisinages du plateau précalculés et immuables ; maximum des ripostes mis à
  jour en place.
- Métriques PPO transférées ensemble vers le CPU par minibatch. Les contrôles
  de gradients non finis restent actifs.
- Workers CPU optionnels et persistants, buffers privés, catalogue partagé en
  lecture seule, ordre des résultats conservé et fermeture idempotente.
  Les lots inférieurs à 128 états restent séquentiels.
- Import circulaire entre les packages batch et vectoriel corrigé. Un test
  vérifie leur import dans un processus vierge.
- Benchmarks avec échauffement exclu, JSON, configuration, versions logicielles,
  provenance et mesures individuelles. Le profil tactique couvre 18 positions
  des six dieux, en début, milieu et fin de partie.
- Affichage du benchmark corrigé pour les mises à jour sans réinitialisation
  de partie : leur temps de reset vaut zéro.

Les opérations numériques s’appuient sur NumPy. Aucune extension C++/Rust/JIT
supplémentaire n’a été construite : la voie développée et mesurée utilise la
compaction et les workers CPU. Le benchmark fournit le profil permettant de
réexaminer ultérieurement l’intérêt d’une extension.

## Mesures sur le poste de développement

Windows, Python 3.11.9, GPU AMD Radeon RX 6800. Un thread de calcul PyTorch/BLAS,
256 environnements sauf indication, batch de 2 048 transitions, une époque PPO,
palier `precision_100_anticipation`. Évaluations de promotion désactivées.
Trois mises à jour d’échauffement sont exclues. Les trois premières lignes
utilisent 20 mises à jour mesurées ; les autres réglages en utilisent huit.
Les campagnes de calibrage ont été exécutées successivement.

| Variante | Décisions/s, médiane | Secondes/update, médiane |
| --- | ---: | ---: |
| Référence avant optimisation, DirectML, 256 env. | 456.4 | 4.488 |
| Noyau compact, DirectML, 256 env., 1 worker | 628.2 | 3.260 |
| Noyau compact, DirectML, 256 env., 2 workers | 734.3 | 2.789 |
| DirectML, 128 env., 1 worker | 615.8 | 3.326 |
| DirectML, 512 env., 1 worker | 630.6 | 3.247 |
| CPU, 256 env., 1 worker | 455.6 | 4.496 |

Le débit global passe de **456 à 734 décisions/s**, soit **+60,9 %** pour ce
benchmark collecte + optimisation. Le temps médian passe de 4,488 à 2,789 s.
Le gain du noyau compact seul est de **37,7 %** en débit.

L’espace de travail tactique annoncé passe de 31 à 62 Mio avec deux workers.
Le RSS observé en fin du benchmark à deux workers est d’environ 662 Mio ; ce
chiffre n’est pas une mesure du pic mémoire. Les temps internes des workers
sont cumulés et ne doivent pas être additionnés au temps mural des updates.

512 environnements doublent le workspace sans gain convaincant dans cet essai.
Le réglage officiel reste donc à 256 environnements et un worker par défaut.
Pour ce poste, **deux workers constituent l’option mesurée recommandée** dans
un nouveau run. Le choix reste explicite pour les autres matériels.

Avec un worker, les paliers `precision_0` et `precision_100` atteignent
respectivement 972.8 et 625.9 décisions/s sur huit updates mesurées. Ils
complètent le calibrage ; ces valeurs ne mesurent pas un gain avant/après.

Un prototype à deux workers atteignait 739,7 décisions/s ; la version intégrée
atteint 734,3. Un micro-benchmark a aussi comparé 1, 2 et 4 workers avec contrôle
d’égalité des sorties. Quatre workers n’ont pas été retenus. Aucun seuil de
performance dépendant du matériel n’est imposé dans les tests.

## Validation

- Suite complète avec Godot et DirectML : **162 tests réussis en 269,19 s**.
- Ruff : analyse et formatage des 129 fichiers Python conformes.
- Comparaison du noyau compact à l’ancien calcul dense dans un oracle réservé
  aux tests : actions invalides, échantillons identiques et différents, six dieux.
- Égalité des sorties série/parallèle, lots petits, grands et vides, croissance
  des buffers, fermeture répétée et refus d’utilisation après fermeture.
- Contrôles de parité avec les moteurs scalaire et Godot dans la suite complète.
- Trois essais DirectML, seeds 9101, 9102 et 9103, avec deux workers : sauvegarde
  après 8 192 transitions, reprise des poids et de 14 états d’optimiseur, puis
  poursuite jusqu’à 16 384 transitions chacun. Total : 49 152 transitions.

Les résultats détaillés sont conservés localement sous `.tmp/rl-opt/`, ignoré
par Git. Les commandes reproductibles sont dans le [guide](GUIDE_COMMANDES.md).

## Portée et utilisation

Dans le YAML d’un **nouveau run**, ajouter `tactical_workers: 2` sous
`environment`. Le défaut reste 1. Utiliser les mécanismes documentés de migration
des poids lorsque la provenance du code a changé ; les anciens runs n’ont pas
été modifiés par les benchmarks.

Les essais courts vérifient la stabilité technique, pas la convergence sur une
campagne longue. Les mesures excluent les tournois Godot de certification et ne
prédisent pas leur durée. Changer le nombre d’environnements à batch constant
change aussi la longueur des rollouts : cela exige une expérience d’apprentissage
contrôlée avant d’adopter un nouveau réglage.
