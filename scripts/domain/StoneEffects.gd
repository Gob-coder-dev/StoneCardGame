## Identifiants des pouvoirs déclarés dans le champ "effects" de stones.json.
## Moteur, interface et validation lisent ces constantes au lieu de recopier
## les textes ; ContentValidator signale tout identifiant absent de ALL.
extends RefCounted

## Déclin : Miasme, aura continue qui affaiblit de 1 les voisines adverses.
const WEAKEN_ADJACENT := "weaken_adjacent"
## Déclin : Échec corrosif, chaque pierre adverse qui résiste à l'attaque perd
## 2 de force jusqu'à la fin du prochain coup du lanceur.
const WEAKEN_ON_FAILED_ATTACK := "weaken_on_failed_attack"
## Essaim : aura de groupe entre pierres Essaim alliées reliées.
const SWARM := "swarm"
## Pillage : la force vaincue devient des boucliers sur la pierre attaquante.
const SHIELD_THEFT := "shield_theft"

## Pouvoirs de la famille Déclin : une carte n'en porte qu'un seul.
const DECLINE: Array[String] = [WEAKEN_ADJACENT, WEAKEN_ON_FAILED_ATTACK]
const ALL: Array[String] = [WEAKEN_ADJACENT, WEAKEN_ON_FAILED_ATTACK, SWARM, SHIELD_THEFT]
