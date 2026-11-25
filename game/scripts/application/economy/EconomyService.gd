## EconomyService.gd
## Point d'entrée transactionnel pour les monnaies, copies, améliorations et dieux.
## Il prépare une copie de l'inventaire et PlayerData ne la publie qu'après une
## sauvegarde réussie.
class_name EconomyService
extends RefCounted

const Transaction := preload("res://scripts/application/economy/EconomyTransaction.gd")
const CardGrant := preload("res://scripts/domain/economy/CardRewardGrant.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const ProgressionRules := preload("res://scripts/domain/economy/CardProgressionRules.gd")
const ConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")


func grant_reward(transaction_id: String, souls: int, cards: Array = [],
		starter_deck_cards: Array = [], candles: int = 0) -> Dictionary:
	var prepared := prepare_reward(transaction_id, souls, cards, starter_deck_cards, candles)
	if not prepared["ok"]:
		return prepared
	var receipt: Dictionary = prepared["receipt"]
	if receipt["already_applied"]:
		return receipt
	var error := PlayerData.commit_economy(prepared["inventory"], prepared["deck_override"])
	return receipt if error == OK else _save_fail(error)


## Prépare les gains et leur reçu pour une transaction de profil plus large.
func prepare_reward(transaction_id: String, souls: int, cards: Array,
		starter_deck_cards: Array, candles: int) -> Dictionary:
	if transaction_id == "":
		return _fail("Identifiant de récompense absent.")
	if souls < 0:
		return _fail("Montant d'âmes invalide.")
	if candles < 0:
		return _fail("Montant de bougies invalide.")
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	if next.has_transaction(transaction_id):
		return {"ok": true, "inventory": next, "deck_override": null,
			"receipt": {"ok": true, "reason": "", "already_applied": true,
				"souls": 0, "candles": 0, "cards": [], "deferred_cards": []}}
	next.souls += souls
	next.candles += candles
	var granted: Array = []
	var deferred: Array = []
	for raw in cards:
		# Les cartes de campagne gardent leurs copies, y compris au niveau maximal.
		# La compensation des invocations et quetes est une politique explicite.
		var applied := CardGrant.apply(next, raw, false)
		if not bool(applied.get("ok", false)):
			return applied
		var reward: Dictionary = applied["reward"]
		if bool(reward.get("deferred", false)):
			deferred.append(reward)
		else:
			granted.append(reward)
	next.mark_transaction(transaction_id)
	return {"ok": true, "inventory": next,
		"deck_override": _reward_deck(next, starter_deck_cards),
		"receipt": {"ok": true, "reason": "", "already_applied": false,
			"souls": souls, "candles": candles, "cards": granted, "deferred_cards": deferred}}


func _reward_deck(inventory: PlayerInventory, starter_deck_cards: Array) -> Variant:
	if starter_deck_cards.is_empty() or PlayerData.player_god_id != "":
		return null
	var current := PlayerData.get_active_deck()
	if current.size() >= DeckRules.DECK_SIZE:
		return null
	for raw_monster_id in starter_deck_cards:
		var monster_id := str(raw_monster_id)
		if inventory.owns_monster(monster_id) and current.size() < DeckRules.DECK_SIZE \
				and DeckRules.lineage_index(current, MonsterLoader.monster_lineage(monster_id)) < 0:
			current.append(monster_id)
	return current


func upgrade_card(lineage_id: String) -> Dictionary:
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	var upgraded := ProgressionRules.upgrade(lineage_id, next.entry(lineage_id),
		next.souls, ConfigModel.get_config())
	if not bool(upgraded.get("ok", false)):
		return upgraded
	next.cards[lineage_id] = (upgraded["entry"] as Dictionary).duplicate(true)
	next.souls = int(upgraded["souls"])
	var error := Transaction.commit(next, "upgrade_purchase", {
		"souls": int(upgraded["spent_souls"]),
	})
	if error != OK:
		return _save_fail(error)
	return upgraded


func god_price() -> int:
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	var config := ConfigModel.get_config()
	return int(config.get("other_god_price", 800)) \
		if inventory.first_god_discount_used else int(config.get("first_god_price", 100))


func buy_god(god_id: String) -> Dictionary:
	if MonsterLoader.get_god(god_id).is_empty():
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
		if MonsterLoader.lineage_max_level(str(lineage_id)) <= 0:
			return _fail("Carte offerte inconnue : %s." % lineage_id)
	next.souls -= price
	next.unlock_god(god_id)
	next.first_god_discount_used = true
	var released := next.release_pending_for_god(god_id)
	var granted: Array = []
	for lineage_id in gifts:
		next.add_copies(str(lineage_id), 1)
		granted.append({"lineage_id": str(lineage_id), "copies": 1})
	var error := PlayerData.commit_inventory(next)
	if error != OK:
		return _save_fail(error)
	return {"ok": true, "reason": "", "price": price, "cards": granted,
		"released_cards": released}


## Outils de test/développement. Aucun écran de production ne les appelle.
func grant_development_souls(amount: int) -> Error:
	if amount <= 0:
		return ERR_INVALID_PARAMETER
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	next.souls += amount
	return PlayerData.commit_inventory(next)


func grant_development_candles(amount: int) -> Error:
	if amount <= 0:
		return ERR_INVALID_PARAMETER
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	next.candles += amount
	return PlayerData.commit_inventory(next)


func unlock_all_for_development(copies_per_lineage: int = 1000) -> Error:
	var next := InventoryModel.from_dict(PlayerData.inventory_dict())
	for god in MonsterLoader.get_all_gods():
		next.unlock_god(str(god.get("id", "")))
	# Le profil de développement reçoit déjà tout le catalogue : aucune
	# récompense différée ne doit rester en double dans la sauvegarde.
	next.pending_card_rewards.clear()
	next.first_god_discount_used = true
	var seen := {}
	for monster in MonsterLoader.get_all_monsters():
		var lineage_id := MonsterLoader.monster_lineage(str(monster.get("id", "")))
		if seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		next.cards[lineage_id] = {
			"unlocked_level": MonsterLoader.lineage_max_level(lineage_id),
			"copies": maxi(0, copies_per_lineage),
		}
	return PlayerData.commit_inventory(next)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _save_fail(error: Error) -> Dictionary:
	return {"ok": false, "reason": "Sauvegarde impossible (%s)." % error_string(error),
		"error": error}
