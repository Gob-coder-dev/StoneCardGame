## Compatibilite du protocole offline avec le serialiseur embarque.
extends RefCounted
const Serializer := preload("res://scripts/ai/neural/StateSerializer.gd")
static func serialize_for_player(state: GameState, observer: int) -> Dictionary:
    return Serializer.serialize_for_player(state, observer)
