## Enregistre une action économique et ses compteurs de quête dans le même profil.
## Le journal prépare des valeurs ; seul PlayerData publie la transaction réussie.
extends RefCounted

const Journal := preload("res://scripts/application/quests/QuestJournal.gd")
const QuestStateModel := preload("res://scripts/domain/quests/QuestState.gd")


static func commit(inventory: PlayerInventory, kind: String,
		payload: Dictionary, key: String = "") -> Error:
	var state := QuestStateModel.from_dict(PlayerData.quests_dict())
	Journal.new().stage_event(state, inventory, kind, payload, key)
	return PlayerData.commit_economy(inventory, null, state.to_dict())
