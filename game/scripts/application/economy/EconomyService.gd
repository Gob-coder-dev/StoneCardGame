## EconomyService.gd
## Point d'entrée transactionnel pour les âmes, copies, améliorations et dieux.
## Il prépare une copie de l'inventaire et PlayerData ne la publie qu'après une
## sauvegarde réussie.
class_name EconomyService
extends RefCounted

const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const ProgressionRules := preload("res://scripts/domain/economy/CardProgressionRules.gd")
const ConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")


func grant_reward(transaction_id: String, souls: int, cards: Array = [],
		starter_deck_cards: Array = []) -> Dictionary:
	if transaction_id == "":
		return _fail("Identifiant de récompense absent.")
	if souls < 0:
		return _fail("Montant d'âmes invalide.")
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	if next.has_transaction(transaction_id):
		return {"ok": true, "reason": "", "already_applied": true,
			"souls": 0, "cards": []}
	var normalized: Array = []
	for raw in cards:
		if not raw is Dictionary:
			return _fail("Récompense de carte invalide.")
		var lineage_id := str(raw.get("lineage_id", ""))
		var amount := int(raw.get("copies", 0))
		if StoneLoader.lineage_max_level(lineage_id) <= 0 or amount <= 0:
			return _fail("Récompense inconnue : %s." % lineage_id)
		normalized.append({"lineage_id": lineage_id, "copies": amount})
	next.souls += souls
	for reward in normalized:
		next.add_copies(str(reward["lineage_id"]), int(reward["copies"]))
	next.mark_transaction(transaction_id)
	var deck_override: Variant = null
	if not starter_deck_cards.is_empty() and PlayerData.player_god_id == "":
		var current := PlayerData.get_active_deck()
		if current.size() < DeckRules.DECK_SIZE:
			for raw_stone_id in starter_deck_cards:
				var stone_id := str(raw_stone_id)
				if next.owns_stone(stone_id) and current.size() < DeckRules.DECK_SIZE \
						and DeckRules.lineage_index(current, StoneLoader.stone_lineage(stone_id)) < 0:
					current.append(stone_id)
			deck_override = current
	var error := PlayerData.commit_economy(next, deck_override)
	if error != OK:
		return _save_fail(error)
	return {"ok": true, "reason": "", "already_applied": false,
		"souls": souls, "cards": normalized}


func upgrade_card(lineage_id: String) -> Dictionary:
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var upgraded := ProgressionRules.upgrade(lineage_id, next.entry(lineage_id),
		next.souls, ConfigModel.get_config())
	if not bool(upgraded.get("ok", false)):
		return upgraded
	next.cards[lineage_id] = (upgraded["entry"] as Dictionary).duplicate(true)
	next.souls = int(upgraded["souls"])
	var error := PlayerData.commit_inventory(next)
	if error != OK:
		return _save_fail(error)
	return upgraded


func god_price() -> int:
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	var config := ConfigModel.get_config()
	return int(config.get("other_god_price", 800)) \
		if inventory.first_god_discount_used else int(config.get("first_god_price", 100))


func buy_god(god_id: String) -> Dictionary:
	if StoneLoader.get_god(god_id).is_empty():
		return _fail("Dieu inconnu.")
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	if next.has_god(god_id):
		return _fail("Ce dieu est déjà débloqué.")
	var config := ConfigModel.get_config()
	var price := int(config.get("other_god_price", 800)) \
		if next.first_god_discount_used else int(config.get("first_god_price", 100))
	if next.souls < price:
		return _fail("Pas assez d'âmes.")
	var gifts: Variant = config.get("god_gifts", {}).get(god_id, [])
	if not gifts is Array or gifts.size() != 2:
		return _fail("Les cartes offertes de ce dieu sont mal configurées.")
	for lineage_id in gifts:
		if StoneLoader.lineage_max_level(str(lineage_id)) <= 0:
			return _fail("Carte offerte inconnue : %s." % lineage_id)
	next.souls -= price
	next.unlock_god(god_id)
	next.first_god_discount_used = true
	var granted: Array = []
	for lineage_id in gifts:
		next.add_copies(str(lineage_id), 1)
		granted.append({"lineage_id": str(lineage_id), "copies": 1})
	var error := PlayerData.commit_inventory(next)
	if error != OK:
		return _save_fail(error)
	return {"ok": true, "reason": "", "price": price, "cards": granted}


## Outils de test/développement. Aucun écran de production ne les appelle.
func grant_development_souls(amount: int) -> Error:
	if amount <= 0:
		return ERR_INVALID_PARAMETER
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	next.souls += amount
	return PlayerData.commit_inventory(next)


func unlock_all_for_development(copies_per_lineage: int = 1000) -> Error:
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	for god in StoneLoader.get_all_gods():
		next.unlock_god(str(god.get("id", "")))
	next.first_god_discount_used = true
	var seen := {}
	for stone in StoneLoader.get_all_stones():
		var lineage_id := StoneLoader.stone_lineage(str(stone.get("id", "")))
		if seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		next.cards[lineage_id] = {
			"unlocked_level": StoneLoader.lineage_max_level(lineage_id),
			"copies": maxi(0, copies_per_lineage),
		}
	return PlayerData.commit_inventory(next)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _save_fail(error: Error) -> Dictionary:
	return {"ok": false, "reason": "Sauvegarde impossible (%s)." % error_string(error),
		"error": error}
