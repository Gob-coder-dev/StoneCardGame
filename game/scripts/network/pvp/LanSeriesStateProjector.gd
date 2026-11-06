## Construit la vue locale et confidentielle d'une série. Aucun envoi réseau et
## aucune mutation : le coordinateur lui fournit uniquement ses snapshots.
class_name LanSeriesStateProjector
extends RefCounted


static func build(phase: String, is_host: bool, local_side: int,
		rules: Dictionary, series: SeriesState, preparation_id: String,
		loadout_one: Loadout, loadout_two: Loadout, confirmed_one: bool,
		confirmed_two: bool, draft: DraftEngine, client_draft: Dictionary,
		client_chosen: String, deadline_unix_ms: int, remaining_seconds: float) -> Dictionary:
	var own := loadout_one if local_side == GameState.PLAYER_ONE else loadout_two
	var own_complete := false
	var complete := false
	if draft != null:
		own_complete = draft.complete_for(local_side)
		complete = draft.is_complete()
	elif not client_draft.is_empty():
		own_complete = bool(client_draft.get("own_complete", false))
		complete = bool(client_draft.get("complete", false))
	return {
		"phase": phase,
		"is_host": is_host,
		"local_side": local_side,
		"series_id": series.series_id if series != null else "",
		"rules_revision": int(rules.get("revision", 0)),
		"preparation_id": preparation_id,
		"round_index": series.round_index if series != null else 0,
		"series": SeriesEngine.public_state(series),
		"own_loadout": own.to_dict() if own != null else {},
		"own_draft_complete": own_complete,
		"draft_complete": complete,
		"own_ready": confirmed_one if local_side == GameState.PLAYER_ONE else confirmed_two,
		"opponent_ready": confirmed_two if local_side == GameState.PLAYER_ONE else confirmed_one,
		"draft": draft_view(local_side, draft, client_draft, client_chosen,
			remaining_seconds),
		"deadline_unix_ms": deadline_unix_ms,
		"remaining_seconds": remaining_seconds,
	}


static func draft_view(local_side: int, draft: DraftEngine, client_draft: Dictionary,
		client_chosen: String, remaining_seconds: float) -> Dictionary:
	if draft != null:
		var host_view := draft.public_state(local_side)
		host_view["remaining_seconds"] = remaining_seconds
		return host_view
	if client_draft.is_empty():
		return {}
	var offers: Array = client_draft.get("offers_one", []) \
		if local_side == GameState.PLAYER_ONE else client_draft.get("offers_two", [])
	return {
		"started": true,
		"complete": bool(client_draft.get("complete", false)),
		"complete_one": bool(client_draft.get("complete_one", false)),
		"complete_two": bool(client_draft.get("complete_two", false)),
		"own_complete": bool(client_draft.get("own_complete", false)),
		"opponent_complete": bool(client_draft.get("opponent_complete", false)),
		"step": int(client_draft.get("own_step", 0)),
		"own_step": int(client_draft.get("own_step", 0)),
		"opponent_step": int(client_draft.get("opponent_step", 0)),
		"offers_step": int(client_draft.get("offers_step", 0)),
		"total_steps": DeckRules.DECK_SIZE,
		"cost_quarters": int(client_draft.get("cost_quarters", 0)),
		"offers_one": (client_draft.get("offers_one", []) as Array).duplicate(true),
		"offers_two": (client_draft.get("offers_two", []) as Array).duplicate(true),
		"own_side": local_side,
		"own_offers": offers.duplicate(true),
		"own_chosen": client_chosen,
		"own_deck": (client_draft.get("own_deck", []) as Array).duplicate(true),
		"opponent_locked": false,
		"remaining_seconds": remaining_seconds,
	}
