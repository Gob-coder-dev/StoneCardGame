## Normalisation des nombres persistés, y compris les floats relus depuis JSON.
## Refuse les types composites et les valeurs non finies avant toute conversion.
extends RefCounted

const MAX_EXACT_JSON_INTEGER: int = 9007199254740991


static func read(value: Variant, fallback: int = 0, minimum: int = 0,
		maximum: int = MAX_EXACT_JSON_INTEGER) -> int:
	if value is int:
		return clampi(value, minimum, maximum)
	if value is float and is_finite(value):
		return int(clampf(value, float(minimum), float(maximum)))
	return fallback
