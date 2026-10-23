## Identifiants des pouvoirs déclarés dans le champ "effects" de stones.json.
## Moteur, interface et validation lisent ces constantes au lieu de recopier
## les textes ; ContentValidator signale tout identifiant absent de ALL.
extends RefCounted

## Déclin : Miasme, affaiblit définitivement les voisines après les attaques.
const WEAKEN_ADJACENT := "weaken_adjacent"
## Déclin : Échec corrosif, affaiblit le camp adverse si la pose ne capture rien.
const WEAKEN_ON_MISS := "weaken_enemies_on_miss"
## Essaim : aura de groupe entre pierres Essaim alliées reliées.
const SWARM := "swarm"
## Pillage : la force vaincue devient des boucliers sur la pierre attaquante.
const SHIELD_THEFT := "shield_theft"

## Pouvoirs de la famille Déclin : une carte n'en porte qu'un seul.
const DECLINE: Array[String] = [WEAKEN_ADJACENT, WEAKEN_ON_MISS]
const ALL: Array[String] = [WEAKEN_ADJACENT, WEAKEN_ON_MISS, SWARM, SHIELD_THEFT]
