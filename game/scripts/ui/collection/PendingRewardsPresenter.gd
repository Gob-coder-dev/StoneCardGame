## Transforme la réserve économique en groupes prêts à afficher. Ce composant
## ne possède aucun nœud et ne peut pas modifier l'inventaire.
class_name PendingRewardsPresenter
extends RefCounted


static func groups() -> Array:
	var by_god := PlayerData.pending_card_rewards_by_god()
	var result: Array = []
	for god in MonsterLoader.get_all_gods():
		var god_id := str(god.get("id", ""))
		var raw_cards: Array = by_god.get(god_id, [])
		if raw_cards.is_empty():
			continue
		var cards: Array = raw_cards.duplicate(true)
		cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var monster_a := MonsterLoader.get_monster(MonsterLoader.variant_id(str(a["lineage_id"]), 1))
			var monster_b := MonsterLoader.get_monster(MonsterLoader.variant_id(str(b["lineage_id"]), 1))
			return str(monster_a.get("name", "")).naturalnocasecmp_to(
				str(monster_b.get("name", ""))) < 0)
		result.append({"god": god.duplicate(true), "cards": cards})
	return result
