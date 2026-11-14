## Mélange Fisher-Yates avec RNG explicite : même graine, même ordre et même consommation RNG.
extends RefCounted


static func apply(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap]
		values[swap] = value
