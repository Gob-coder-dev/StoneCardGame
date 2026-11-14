## Traduit les loadouts génériques en enveloppes de préparation PVP et valide
## les profils/payloads reçus. La génération reste dans ModePreparationService.
class_name PvpLoadoutFactory
extends RefCounted

var preparation := ModePreparationService.new()


func generate(mode: String, generation_seed: int, power_tier: int) -> Dictionary:
	return preparation.prepare_immediate(mode, generation_seed, power_tier, {}, {})


func draft(generation_seed: int, power_tier: int, profile_one: Dictionary,
		profile_two: Dictionary, duration: float) -> Dictionary:
	return preparation.create_draft(generation_seed, power_tier, profile_one, profile_two, duration)


static func wrap(source: GameLoadout, side: int, series: SeriesState,
		preparation_id: String) -> Loadout:
	if source == null or series == null:
		return null
	var result := Loadout.create(source.god_id, source.deck, side, series.series_id,
		preparation_id, series.round_index, series.rules_revision)
	result.generation_seed = source.generation_seed
	return result


static func from_profile(profile: Dictionary, side: int, series: SeriesState,
		preparation_id: String) -> Loadout:
	if series == null:
		return null
	var god_id := str(profile.get("god_id", ""))
	var deck: Array = (profile.get("deck", []) as Array).duplicate()
	if not DeckRules.is_deck_valid(deck, god_id):
		return null
	if series.mode != GameModeRules.MODE_CLASSIC:
		for raw_id in deck:
			if not CardPowerTierRules.is_allowed(StoneLoader.get_stone(str(raw_id)),
					series.power_tier):
				return null
	return Loadout.create(god_id, deck, side, series.series_id, preparation_id,
		series.round_index, series.rules_revision)


static func from_payload(loadout_payload: Dictionary, side: int) -> Loadout:
	var loadout := Loadout.from_dict({
		"series_id": str(loadout_payload.get("series_id", "")),
		"preparation_id": str(loadout_payload.get("preparation_id", "")),
		"round_index": int(loadout_payload.get("round_index", 1)),
		"rules_revision": int(loadout_payload.get("rules_revision", 0)),
		"side": side,
		"god_id": str(loadout_payload.get("god_id", "")),
		"deck": (loadout_payload.get("deck", []) as Array).duplicate(),
		"total_quarters": int(loadout_payload.get("total_quarters", 0)),
	})
	return loadout if loadout.is_valid() else null


static func payload(loadout: Loadout) -> Dictionary:
	if loadout == null:
		return {}
	return {
		"series_id": loadout.series_id,
		"preparation_id": loadout.preparation_id,
		"rules_revision": loadout.rules_revision,
		"round_index": loadout.round_index,
		"god_id": loadout.god_id,
		"deck": loadout.deck.duplicate(),
		"total_quarters": loadout.total_quarters,
	}

