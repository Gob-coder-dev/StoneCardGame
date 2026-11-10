## Contrats de progression : profil initial, copies, transactions, dieux et
## rotation de boutique. Les écritures utilisent uniquement le profil de test.
extends "res://tests/support/CombatTestSuite.gd"

const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const Config := preload("res://scripts/data/economy/EconomyConfig.gd")
const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const Shop := preload("res://scripts/application/economy/ShopService.gd")
const Rituals := preload("res://scripts/application/economy/RitualService.gd")
const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const RitualGenerator := preload("res://scripts/domain/economy/RitualRewardGenerator.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const CampaignRewards := preload("res://scripts/application/campaign/CampaignRewardService.gd")
const Fixture := preload("res://tests/support/PlayerProfileFixture.gd")


func run() -> void:
	var fixture := Fixture.new(Codec.starter_profile())
	_test_starter()
	await _test_locked_level_ui()
	await _test_collection_economy_ui()
	await _test_menu_balance_ui()
	_test_first_tutorial_reward()
	PlayerData._apply_profile(Codec.starter_profile())
	await _test_deferred_god_reward()
	PlayerData._apply_profile(Codec.starter_profile())
	_test_three_by_three_state()
	await _test_rewards_and_upgrade()
	_test_god_purchase()
	_test_shop()
	_test_ritual_config_and_transactions()
	_test_ritual_compositions()
	_test_ritual_compensation_and_unique()
	await _test_shop_screen()
	await _test_ritual_opening_screen()
	await _test_result_reward_ui()
	fixture.restore()


func _test_starter() -> void:
	var config := Config.get_config()
	_check(Config.problems(config).is_empty(),
		"économie : la configuration livrée est cohérente")
	_check(CampaignRewards._candles_for_chapter("Seuil") == 1
		and CampaignRewards._candles_for_chapter("Les Forges Basses") == 2
		and CampaignRewards._candles_for_chapter("Cime") == 5,
		"économie : la campagne distribue une, deux puis cinq bougies selon sa progression")
	var shop: Dictionary = config.get("shop", {})
	_check(int(shop.get("common", {}).get("souls_per_copy", 0)) == 5
		and int(shop.get("rare", {}).get("souls_per_copy", 0)) == 15
		and int(shop.get("epic", {}).get("souls_per_copy", 0)) == 30,
		"boutique : les copies communes, rares et épiques coûtent 5, 15 et 30 âmes")
	var deck := PlayerData.get_active_deck()
	_check(PlayerData.player_god_id == "" and deck.size() == 5
		and PlayerData.souls() == 0 and PlayerData.candles() == 0
		and PlayerData.unlocked_god_ids().is_empty(),
		"économie : le nouveau profil commence sans dieu, sans monnaie et avec cinq cartes")
	var owned := true
	for stone_id in deck:
		owned = owned and PlayerData.owns_stone(str(stone_id)) \
			and StoneLoader.stone_affinity(str(stone_id)) == "neutral"
	_check(owned, "économie : les cinq communes neutres N1 sont réellement possédées")


func _test_locked_level_ui() -> void:
	var page := (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := PlayerData.get_active_deck()
	page._on_info_requested("gueule_de_travers_n1")
	page.info_sheet._select_level(2)
	var preview: StoneCard = page.info_sheet.card_container.get_child(0)
	_check(page.info_sheet.use_button.disabled
		and page.info_sheet.use_button.text == "AMÉLIORER"
		and page.info_sheet.use_button.theme_type_variation == &"UpgradeButton"
		and page.info_sheet.upgrade_price_row.visible
		and page.info_sheet.upgrade_soul_icon.texture != null
		and page.info_sheet.upgrade_price.text == "200"
		and preview.modulate.a < 1.0,
		"collection : le prochain niveau grisé affiche son action et son prix")
	# L'appel direct protège aussi le domaine contre un signal fabriqué ou une
	# future régression de l'état disabled du bouton.
	page.info_sheet.use_button.pressed.emit()
	_check(PlayerData.get_active_deck() == before,
		"collection : un niveau verrouillé ne peut jamais être équipé")
	page.queue_free()
	await get_tree().process_frame


func _test_collection_economy_ui() -> void:
	var page := (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var options: GridContainer = page.god_options
	var first_slot: VBoxContainer = page.deck_rows.get_child(0).get_child(0)
	var progress := first_slot.get_node("Progress") as CardProgressBar
	var godless_option := options.get_child(0)
	_check(page.god_name.text == "SANS DIEU" and options.get_child_count() == 1
		and str(godless_option.get_meta("god_id", "missing")) == ""
		and godless_option.get_node("Content/Portrait").has_portrait(),
		"collection : un profil neuf affiche Sans dieu avec sa stèle et aucun dieu non acheté")
	_check(page.locked_collection_rows.visible and page.locked_collection_title.visible
		and page.locked_collection_title.text == "CARTES NON POSSÉDÉES",
		"collection : les cartes absentes vivent dans une section séparée")
	_check(progress.visible and progress.count_label.text == "1/50",
		"collection : chaque carte du deck montre une jauge compacte de copies")
	var starter_lineage := StoneLoader.stone_lineage(PlayerData.get_active_deck()[0])
	var starter_wrapper: VBoxContainer = page._collection_grid._wrappers[starter_lineage]
	_check(starter_wrapper.get_parent() == page._collection_grid._owned_grid,
		"collection : une carte N1 débloquée appartient aux cartes possédées en aperçu N1")
	page._select_preview_level(2)
	_check(starter_wrapper.get_parent() == page._collection_grid._locked_grid,
		"collection : sa N2 verrouillée passe dans les cartes non possédées en aperçu N2")
	page._select_preview_level(1)
	var deck_card := first_slot.get_child(0) as StoneCard
	var deck_card_size := deck_card.size
	var deck_wrapper_size := first_slot.size
	var deck_row := first_slot.get_parent() as HBoxContainer
	var deck_positions: Array = deck_row.get_children().map(func(wrapper: Control):
		return wrapper.position)
	page._open_card_actions(PlayerData.get_active_deck()[0], first_slot,
		CardActionDrawer.Source.DECK)
	for _frame in range(4):
		await get_tree().process_frame
	var drawer: CardActionDrawer = page._action_drawer
	_check(drawer != null and drawer.upgrade_button.visible
		and drawer.upgrade_soul_icon.texture != null
		and drawer.upgrade_title.text == "AMÉLIORER"
		and not drawer.upgrade_price.text.to_upper().contains("ÂME"),
		"collection : Améliorer est dans le tiroir et son prix utilise le pictogramme")
	_check(drawer.get_parent() == page.action_drawer_layer
		and deck_card.size == deck_card_size and first_slot.size == deck_wrapper_size
		and deck_row.get_children().map(func(wrapper: Control):
			return wrapper.position) == deck_positions,
		"deck : le tiroir superposé ne redimensionne ni la carte ni sa rangée")
	var deck_rect := first_slot.get_global_rect()
	_check(drawer.visible and drawer.global_position.y >= deck_rect.end.y
		and is_equal_approx(drawer.size.x, deck_rect.size.x),
		"deck : le tiroir reste sous la carte et reprend sa largeur")
	page.scroll.scroll_vertical += 20
	await get_tree().process_frame
	_check(not is_instance_valid(page._action_drawer),
		"deck : le tiroir se ferme au premier défilement au lieu de se déplacer")
	page.queue_free()
	await get_tree().process_frame


func _test_menu_balance_ui() -> void:
	var scenes: Array[String] = [
		"res://scenes/menus/MainMenu.tscn",
		"res://scenes/menus/CollectionScreen.tscn",
		"res://scenes/menus/HowToPlay.tscn",
		"res://scenes/menus/Stats.tscn",
	]
	var valid := true
	for path in scenes:
		var page := (load(path) as PackedScene).instantiate()
		add_child(page)
		await get_tree().process_frame
		var soul_balances := page.find_children("SoulBalance", "SoulBalance", true, false)
		var candle_balances := page.find_children("CandleBalance", "CandleBalance", true, false)
		valid = valid and soul_balances.size() == 1 and candle_balances.size() == 1 \
			and (soul_balances[0] as SoulBalance).amount_label.text == UIFormat.integer(PlayerData.souls()) \
			and (candle_balances[0] as CandleBalance).amount_label.text == UIFormat.integer(PlayerData.candles())
		page.queue_free()
		await get_tree().process_frame
	_check(valid, "économie : âmes et bougies sont visibles ensemble dans tous les menus généraux")


func _test_rewards_and_upgrade() -> void:
	var service := Economy.new()
	var lineage := "gueule_de_travers"
	var reward := service.grant_reward("test:upgrade", 200,
		[{"lineage_id": lineage, "copies": 49}], [], 2)
	var duplicate := service.grant_reward("test:upgrade", 200,
		[{"lineage_id": lineage, "copies": 49}], [], 2)
	_check(bool(reward.get("ok", false)) and bool(duplicate.get("already_applied", false))
		and PlayerData.souls() == 200
		and PlayerData.candles() == 2
		and int(PlayerData.card_entry(lineage)["copies"]) == 50,
		"économie : une récompense est atomique et idempotente")
	var page := (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var wrapper: VBoxContainer = page._collection_grid._wrappers[lineage]
	page._open_card_actions("gueule_de_travers_n1", wrapper,
		CardActionDrawer.Source.COLLECTION)
	for _frame in range(4):
		await get_tree().process_frame
	page._action_drawer.upgrade_button.pressed.emit()
	var preview: StoneCard = page.info_sheet.card_container.get_child(0)
	_check(page.info_sheet.visible
		and page.info_sheet._shown_variant == "gueule_de_travers_n2"
		and page.info_sheet.use_button.text == "AMÉLIORER"
		and page.info_sheet.use_button.theme_type_variation == &"UpgradeButton"
		and page.info_sheet.upgrade_price_row.visible
		and page.info_sheet.upgrade_price.text == "200"
		and not page.info_sheet.use_button.disabled
		and preview.modulate.a < 1.0
		and int(PlayerData.card_entry(lineage)["unlocked_level"]) == 1,
		"collection : le tiroir ouvre le prochain niveau grisé sans l'améliorer")
	page.info_sheet._select_level(1)
	var previous_level_is_available: bool = \
		page.info_sheet.use_button.text == "UTILISER" \
		and page.info_sheet.use_button.theme_type_variation == &"PrimaryButton" \
		and not page.info_sheet.upgrade_price_row.visible
	page.info_sheet._select_level(2)
	page.info_sheet.use_button.pressed.emit()
	_check(previous_level_is_available and page.info_sheet.visible
		and page.info_sheet._shown_variant == "gueule_de_travers_n2"
		and page.info_sheet.use_button.text == "UTILISER"
		and page.info_sheet.use_button.theme_type_variation == &"PrimaryButton"
		and not page.info_sheet.upgrade_price_row.visible
		and preview.modulate == Color.WHITE
		and PlayerData.souls() == 0
		and int(PlayerData.card_entry(lineage)["unlocked_level"]) == 2
		and int(PlayerData.card_entry(lineage)["copies"]) == 0,
		"collection : améliorer depuis la fiche débloque la carte sans fermer l'aperçu")
	page.queue_free()
	await get_tree().process_frame


func _test_first_tutorial_reward() -> void:
	var result := Economy.new().grant_reward("test:first_tutorial", 12, [
		{"lineage_id": "avortons_des_caves", "copies": 1},
		{"lineage_id": "mordeur_des_combles", "copies": 1},
		{"lineage_id": "mache_mur", "copies": 1},
		{"lineage_id": "le_sac_a_murmures", "copies": 1},
	], ["avortons_des_caves_n1", "mordeur_des_combles_n1", "mache_mur_n1"])
	_check(bool(result.get("ok", false)) and PlayerData.get_active_deck().size() == 8
		and PlayerData.owns_stone("le_sac_a_murmures_n1") and PlayerData.souls() == 12,
		"économie : le premier tutoriel offre quatre cartes et complète le deck avec trois")


func _test_three_by_three_state() -> void:
	var state := GameState.new(3)
	state.setup_hands(PlayerData.get_active_deck(), [])
	_check(state.board_size == 3 and state.board.size() == 9
		and RulesEngine.get_free_cells(state).size() == 9
		and state.adjacent_positions(1, 1).size() == 4,
		"tutoriel : le moteur construit un vrai plateau 3 × 3 sans coordonnées 4 × 4")


func _test_deferred_god_reward() -> void:
	var service := Economy.new()
	var lineage := "porte_fievre"
	var reward := service.grant_reward("test:locked-god-reward", 11,
		[{"lineage_id": lineage, "copies": 2}])
	var duplicate := service.grant_reward("test:locked-god-reward", 11,
		[{"lineage_id": lineage, "copies": 2}])
	var inventory := PlayerData.inventory_dict()
	_check(bool(reward.get("ok", false))
		and bool(duplicate.get("already_applied", false))
		and (reward.get("cards", []) as Array).is_empty()
		and (reward.get("deferred_cards", []) as Array).size() == 1
		and not PlayerData.owns_stone("porte_fievre_n1")
		and int(inventory.get("pending_card_rewards", {}).get(lineage, 0)) == 2
		and PlayerData.pending_card_reward_count() == 1
		and PlayerData.pending_card_reward_copy_count() == 2,
		"économie : une carte divine différée reste hors collection et idempotente")
	PlayerData._apply_profile(Codec.decode(PlayerData.get_profile()))
	_check(int(PlayerData.inventory_dict().get("pending_card_rewards", {}).get(lineage, 0)) == 2
		and not PlayerData.owns_stone("porte_fievre_n1"),
		"économie : la récompense différée survit à la sérialisation du profil")
	service.grant_reward("test:drawer-layout", 0, [
		{"lineage_id": "avortons_des_caves", "copies": 1},
		{"lineage_id": "mordeur_des_combles", "copies": 1},
		{"lineage_id": "mache_mur", "copies": 1},
	])
	var page := (load("res://scenes/menus/CollectionScreen.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var collection_wrappers: Array = [
		page._collection_grid._wrappers["avortons_des_caves"],
		page._collection_grid._wrappers["mordeur_des_combles"],
		page._collection_grid._wrappers["mache_mur"],
	]
	var positions_before: Array = collection_wrappers.map(func(wrapper: Control):
		return wrapper.position)
	var lateral_alignment_valid := true
	for raw_wrapper in collection_wrappers:
		var tested_wrapper := raw_wrapper as VBoxContainer
		var tested_card := tested_wrapper.get_child(0) as StoneCard
		page._open_card_actions(tested_card.get_stone_id(), tested_wrapper,
			CardActionDrawer.Source.COLLECTION)
		for _frame in range(4):
			await get_tree().process_frame
		var target_rect := tested_wrapper.get_global_rect()
		var drawer_rect: Rect2 = page._action_drawer.get_global_rect()
		lateral_alignment_valid = lateral_alignment_valid \
			and absf(drawer_rect.position.x - target_rect.position.x) < 1.0 \
			and absf(drawer_rect.size.x - target_rect.size.x) < 1.0
	_check(lateral_alignment_valid,
		"collection : le tiroir reste aligné sur les cartes gauche, centrale et droite")
	var selected_wrapper := collection_wrappers[1] as VBoxContainer
	var selected_card := selected_wrapper.get_child(0) as StoneCard
	var card_size_before := selected_card.size
	var wrapper_size_before := selected_wrapper.size
	page._open_card_actions("mordeur_des_combles_n1", selected_wrapper,
		CardActionDrawer.Source.COLLECTION)
	for _frame in range(4):
		await get_tree().process_frame
	var positions_after: Array = collection_wrappers.map(func(wrapper: Control):
		return wrapper.position)
	var collection_rect := selected_wrapper.get_global_rect()
	_check(page._action_drawer.get_parent() == page.action_drawer_layer
		and selected_card.size == card_size_before
		and selected_wrapper.size == wrapper_size_before
		and positions_after == positions_before
		and page._action_drawer.visible
		and page._action_drawer.global_position.y >= collection_rect.end.y
		and is_equal_approx(page._action_drawer.size.x, collection_rect.size.x),
		"collection : sélectionner une carte superpose le tiroir sans déplacer la grille")
	page._open_pending_rewards()
	var vault: PendingRewardsVault = page.pending_rewards_vault
	var section := vault.groups_container.get_child(1) as PanelContainer
	var grid := section.get_child(0).get_child(1) as GridContainer
	var quantity := grid.get_child(0).get_node("Quantity") as Label
	_check(page.pending_rewards_button.get_parent() == page.get_node(
		"Content/Scroll/Page/CollectionTitle")
		and page.pending_rewards_badge.visible and page.pending_rewards_badge.text == "1"
		and vault.visible and section.get_meta("god_id") == "nerava"
		and quantity.text == "×2",
		"collection : le coffre regroupe les copies en attente sous leur dieu")
	_check(service.grant_development_souls(89) == OK, "économie : préparation du premier achat")
	var bought := service.buy_god("nerava")
	await get_tree().process_frame
	_check(bool(bought.get("ok", false)) and PlayerData.has_unlocked_god("nerava")
		and PlayerData.owns_stone("porte_fievre_n1")
		and (bought.get("released_cards", []) as Array).size() == 1
		and not PlayerData.inventory_dict().get("pending_card_rewards", {}).has(lineage)
		and not page.pending_rewards_badge.visible
		and vault.empty_label.visible,
		"économie : acheter le dieu libère atomiquement ses récompenses différées")
	page.queue_free()
	await get_tree().process_frame


func _test_god_purchase() -> void:
	var service := Economy.new()
	_check(service.grant_development_souls(100) == OK and service.god_price() == 100,
		"économie : le premier dieu coûte 100 âmes")
	var bought := service.buy_god("veskar")
	_check(bool(bought.get("ok", false)) and PlayerData.has_unlocked_god("veskar")
		and PlayerData.souls() == 0 and service.god_price() == 800,
		"économie : le premier achat débloque le dieu puis fixe le prix à 800")
	_check(int(PlayerData.card_entry("devoracle")["copies"]) == 1
		and int(PlayerData.card_entry("sou_ricanant")["copies"]) == 1,
		"économie : Véskar offre deux communes aux mécaniques différentes")


func _test_shop() -> void:
	var service := Shop.new()
	var first := service.state(10_800 * 42 + 10)
	var second := service.state(10_800 * 42 + 500)
	var offers: Array = first.get("offers", [])
	var valid: bool = bool(first.get("ok", false)) and offers.size() == 4 \
		and offers == second.get("offers", [])
	for offer in offers:
		var affinity := StoneLoader.stone_affinity(str(offer.get("stone_id", "")))
		valid = valid and (affinity == "neutral" or affinity == "veskar")
	_check(valid, "boutique : quatre offres stables excluent les dieux verrouillés")
	var economy := Economy.new()
	economy.grant_development_souls(2000)
	var offer: Dictionary = offers[0]
	var purchased := service.buy_offer(str(offer.get("id", "")), 10_800 * 42 + 1000)
	var repeated := service.buy_offer(str(offer.get("id", "")), 10_800 * 42 + 1000)
	_check(bool(purchased.get("ok", false)) and not bool(repeated.get("ok", true)),
		"boutique : une offre ne peut être achetée qu'une fois par rotation")


func _test_ritual_config_and_transactions() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	_check(RitualConfigModel.problems().is_empty()
		and RitualConfigModel.definitions().size() == 4,
		"Rituels : les quatre définitions sont valides et pilotées par les données")
	var service := Rituals.new()
	var state := service.state()
	var unique: Dictionary = (state.get("rituals", []) as Array)[3]
	_check(bool(unique.get("available", false)),
		"Rituels : l'invocation unique accepte les cartes neutres sans dieu débloqué")
	_check(Economy.new().grant_development_candles(100) == OK,
		"Rituels : le solde de test reçoit ses bougies")
	var before := PlayerData.candles()
	var purchased := service.purchase("small", 310_001)
	var opening: Dictionary = purchased.get("opening", {})
	var rewards: Array = opening.get("rewards", [])
	var lineages := {}
	var eligible := rewards.size() == 4 and str(rewards[0].get("type", "")) == "souls"
	for reward in rewards:
		if str(reward.get("type", "")) != "card":
			continue
		var lineage_id := str(reward.get("lineage_id", ""))
		lineages[lineage_id] = true
		eligible = eligible and StoneLoader.stone_affinity(str(reward.get("stone_id", ""))) == "neutral"
	_check(bool(purchased.get("ok", false)) and PlayerData.candles() == before - 15
		and lineages.size() == 3 and eligible,
		"Rituels : l'achat retire 15 bougies, attribue les récompenses et fige trois monstres distincts")
	var serialized := Codec.decode(PlayerData.get_profile())
	_check(not serialized.get("inventory", {}).has("pending_ritual_opening"),
		"Rituels : aucune ouverture visuelle n'est conservée dans la sauvegarde")


func _test_ritual_compositions() -> void:
	var inventory := InventoryModel.from_dict(Codec.starter_profile().get("inventory", {}))
	var basic := RitualConfigModel.definition("basic")
	var normal: Dictionary = {}
	var lucky: Dictionary = {}
	for seed in range(1, 5000):
		var generated := RitualGenerator.generate(basic, inventory, seed)
		if bool(generated.get("lucky", false)) and lucky.is_empty():
			lucky = generated
		elif not bool(generated.get("lucky", false)) and normal.is_empty():
			normal = generated
		if not normal.is_empty() and not lucky.is_empty():
			break
	var normal_counts := _ritual_rarity_counts(normal.get("rewards", []))
	var lucky_counts := _ritual_rarity_counts(lucky.get("rewards", []))
	_check(normal_counts == {"common": 1, "rare": 2, "epic": 1}
		and lucky_counts == {"common": 1, "rare": 1, "epic": 1, "legendary": 1},
		"Rituels : le Basique possède ses compositions normale et exceptionnelle exactes")
	var grand := RitualGenerator.generate(RitualConfigModel.definition("grand"),
		inventory, 610_001)
	var grand_counts := _ritual_rarity_counts(grand.get("rewards", []))
	var quantities_valid := true
	for reward in grand.get("rewards", []):
		if str(reward.get("type", "")) != "card":
			continue
		var copies := int(reward.get("copies", 0))
		match str(reward.get("rarity", "")):
			"common": quantities_valid = quantities_valid and copies >= 8 and copies <= 12
			"rare": quantities_valid = quantities_valid and copies >= 5 and copies <= 8
			"epic": quantities_valid = quantities_valid and copies >= 3 and copies <= 5
			"legendary": quantities_valid = quantities_valid and copies == 1
	_check(grand_counts == {"common": 1, "rare": 2, "epic": 2, "legendary": 1}
		and quantities_valid,
		"Rituels : le Grand garantit six invocations et respecte chaque fourchette")


func _ritual_rarity_counts(rewards: Array) -> Dictionary:
	var result := {}
	for reward in rewards:
		if str(reward.get("type", "")) != "card":
			continue
		var rarity := str(reward.get("rarity", ""))
		result[rarity] = int(result.get(rarity, 0)) + 1
	return result


func _test_ritual_compensation_and_unique() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var inventory := InventoryModel.from_dict(PlayerData.inventory_dict())
	for stone in StoneLoader.get_all_stones():
		var stone_id := str(stone.get("id", ""))
		if StoneLoader.stone_level(stone_id) != 1 or StoneLoader.stone_affinity(stone_id) != "neutral":
			continue
		var lineage_id := StoneLoader.stone_lineage(stone_id)
		inventory.cards[lineage_id] = {
			"unlocked_level": StoneLoader.lineage_max_level(lineage_id), "copies": 0}
	inventory.candles = 100
	_check(PlayerData.commit_inventory(inventory) == OK,
		"Rituels : préparation atomique d'une collection neutre maximale")
	var service := Rituals.new()
	var souls_before := PlayerData.souls()
	var compensated := service.purchase("small", 410_001)
	var opening: Dictionary = compensated.get("opening", {})
	var compensation_total := 0
	var all_maxed := true
	for reward in opening.get("rewards", []):
		if str(reward.get("type", "")) == "card":
			all_maxed = all_maxed and bool(reward.get("maxed", false))
			compensation_total += int(reward.get("compensation_souls", 0))
	_check(bool(compensated.get("ok", false)) and all_maxed and compensation_total > 0
		and PlayerData.souls() > souls_before + compensation_total,
		"Rituels : chaque lot maximal devient une compensation arrondie en faveur du joueur")
	PlayerData._apply_profile(Codec.starter_profile())
	inventory = _inventory_with_only_missing("porte_fievre")
	inventory.candles = 200
	PlayerData.commit_inventory(inventory)
	var unique_locked := service.purchase("unique", 510_001)
	var locked_rewards: Array = unique_locked.get("opening", {}).get("rewards", [])
	var locked_card: Dictionary = locked_rewards[0] if not locked_rewards.is_empty() else {}
	_check(bool(unique_locked.get("ok", false)) and locked_rewards.size() == 1
		and bool(locked_card.get("deferred", false))
		and int(PlayerData.inventory_dict().get("pending_card_rewards", {}).get("porte_fievre", 0)) == 1,
		"Rituels : une carte d'un dieu verrouillé rejoint immédiatement le coffre")
	var state := service.state()
	var completed_unique: Dictionary = (state.get("rituals", []) as Array)[3]
	_check(not bool(completed_unique.get("available", true)),
		"Rituels : l'invocation unique se bloque quand chaque lignée est possédée ou au coffre")
	PlayerData._apply_profile(Codec.starter_profile())
	inventory = _inventory_with_only_missing("avortons_des_caves")
	inventory.candles = 100
	PlayerData.commit_inventory(inventory)
	var unique_neutral := service.purchase("unique", 510_002)
	var neutral_rewards: Array = unique_neutral.get("opening", {}).get("rewards", [])
	var neutral_card: Dictionary = neutral_rewards[0] if not neutral_rewards.is_empty() else {}
	_check(bool(unique_neutral.get("ok", false))
		and PlayerData.owns_stone("avortons_des_caves_n1")
		and not bool(neutral_card.get("deferred", false)),
		"Rituels : l'invocation unique peut débloquer directement une carte neutre")


func _inventory_with_only_missing(missing_lineage: String) -> PlayerInventory:
	var inventory := InventoryModel.from_dict(Codec.starter_profile().get("inventory", {}))
	inventory.cards.clear()
	inventory.pending_card_rewards.clear()
	var seen := {}
	for stone in StoneLoader.get_all_stones():
		var stone_id := str(stone.get("id", ""))
		var lineage_id := StoneLoader.stone_lineage(stone_id)
		if lineage_id == "" or seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		if lineage_id == missing_lineage:
			continue
		if StoneLoader.stone_affinity(stone_id) == "neutral":
			inventory.cards[lineage_id] = {"unlocked_level": 1, "copies": 0}
		else:
			inventory.pending_card_rewards[lineage_id] = 1
	return inventory


func _test_shop_screen() -> void:
	var scene := load("res://scenes/menus/ShopScreen.tscn") as PackedScene
	var page := scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(page.offers_grid.get_child_count() == 4 and page.rituals_grid.get_child_count() == 4
		and page.gods_grid.get_child_count() == 6 and page.offers_grid.columns == 2
		and page.rituals_grid.columns == 2 and page.gods_grid.columns == 2
		and page.soul_balance.amount_label.text == UIFormat.integer(PlayerData.souls())
		and page.candle_balance.amount_label.text == UIFormat.integer(PlayerData.candles())
		and page.rituals_grid.get_child(0) is BaseButton
		and page.gods_grid.get_child(0) is BaseButton,
		"boutique : cartes, Rituels et dieux restent en deux colonnes avec leurs deux soldes")
	var ritual_card: Control = page.rituals_grid.get_child(0)
	var god_card: Control = page.gods_grid.get_child(0)
	var ritual_price := ritual_card.find_child("Price", true, false)
	var god_price := god_card.find_child("Price", true, false)
	_check(ritual_price != null and god_price != null
		and ritual_price.get_node("Amount").text == "15"
		and god_price.get_node("Amount").text == UIFormat.integer(page._economy.god_price())
		and not _tree_contains_text(ritual_card, "invocations")
		and not _tree_contains_text(ritual_card, "% exceptionnel"),
		"boutique : les prix restent visibles sur les fiches et les statistiques détaillées restent dans la modale")
	page._show_ritual_offer("small")
	_check(page.purchase_modal.visible and page.purchase_modal._kind == "ritual"
		and page.purchase_modal.confirm_button.text == "15"
		and "Invocations" in page.purchase_modal.details_label.text,
		"boutique : toucher un Rituel ouvre sa confirmation sans acheter")
	page.purchase_modal.close()
	page._show_god_offer("veskar")
	_check(page.purchase_modal.visible and page.purchase_modal._kind == "god"
		and page.purchase_modal.confirm_button.text == UIFormat.integer(page._economy.god_price()),
		"boutique : toucher un dieu ouvre son portrait et sa confirmation")
	page.queue_free()
	await get_tree().process_frame


func _test_ritual_opening_screen() -> void:
	PlayerData._apply_profile(Codec.starter_profile())
	var inventory := _inventory_with_only_missing("avortons_des_caves")
	inventory.candles = 100
	PlayerData.commit_inventory(inventory)
	var purchase := Rituals.new().purchase("unique", 710_001)
	RitualOpeningContext.begin(purchase.get("opening", {}))
	var page := (load("res://scenes/menus/RitualOpening.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(not page._opening.is_empty() and page.sigil_button.visible
		and page.title_label.text == "RITUEL UNIQUE"
		and page.get_node_or_null("Margin/Page/Header/BackButton") == null,
		"Rituels : l'ouverture transitoire commence sur un sceau fixe sans bouton Retour")
	var sigil_position: Vector2 = page.sigil.position
	var sigil_scale: Vector2 = page.sigil.scale
	await page._on_sigil_pressed()
	_check(page.reward_button.visible and page.prompt_label.text == "Touchez pour révéler",
		"Rituels : l'embrasement plein écran produit la première invocation face cachée")
	_check(page.sigil.visible and page.sigil.position == sigil_position and page.sigil.scale == sigil_scale,
		"Rituels : le sceau reste immobile derrière toute l'ouverture")
	await page._on_reward_pressed()
	_check(page.prompt_label.text == "Touchez pour poursuivre"
		and not PlayerData.inventory_dict().has("pending_ritual_opening"),
		"Rituels : le retournement révèle une récompense déjà acquise sans persister l'animation")
	page.flames.ignite_minor()
	await page.flames.finished
	_check(not page.flames._full_screen,
		"Rituels : les transitions suivantes utilisent seulement les petites flammes")
	await page._on_reward_pressed()
	var summary_tile: Control = page.summary_grid.get_child(0)
	_check(page.summary.visible and page.finish_button.visible
		and page.summary_grid.columns == 2 and summary_tile.custom_minimum_size.x >= 320.0,
		"Rituels : la dernière carte conduit à un récapitulatif agrandi")
	page.queue_free()
	RitualOpeningContext.clear()
	await get_tree().process_frame
	_check(RitualOpeningContext.current().is_empty(),
		"Rituels : fermer l'ouverture abandonne sa présentation sans file de reprise")


func _test_result_reward_ui() -> void:
	var saved := {
		"campaign_node_id": BattleContext.campaign_node_id,
		"campaign_service": BattleContext.campaign_service,
		"selected_npc_id": BattleContext.selected_npc_id,
		"selected_opponent": BattleContext.selected_opponent.duplicate(true),
		"winner": BattleContext.last_winner,
		"human": BattleContext.last_score_human,
		"ai": BattleContext.last_score_ai,
		"reward": BattleContext.last_reward.duplicate(true),
	}
	var opponent := OpponentCatalog.build("veskar", "n1", "tres_facile")
	BattleContext.campaign_node_id = "reward_ui_test"
	BattleContext.campaign_service = null
	BattleContext.select_opponent(opponent)
	BattleContext.last_winner = GameState.PLAYER_HUMAN
	BattleContext.last_score_human = 24
	BattleContext.last_score_ai = 9
	BattleContext.last_reward = {
		"souls": 11,
		"candles": 2,
		"cards": [{"lineage_id": "avortons_des_caves", "copies": 2}],
		"deferred_cards": [{"lineage_id": "porte_fievre", "copies": 1,
			"god_id": "nerava"}],
	}
	var page := (load("res://scenes/menus/Result.tscn") as PackedScene).instantiate()
	add_child(page)
	await get_tree().process_frame
	_check(page.rewards.visible and page.reward_divider.visible
		and page.reward_soul_amount.text == "×11"
		and page.reward_candle_row.visible and page.reward_candle_amount.text == "×2"
		and page.reward_cards.get_child_count() == 2
		and (page.reward_cards.get_child(1) as VBoxContainer).get_child_count() == 3
		and ((page.reward_cards.get_child(1) as VBoxContainer).get_child(2) as Label).text \
			== "APRÈS NÉRAVA"
		and page.result_label.get_parent() == page.rewards.get_parent(),
		"résultat : victoire, score et récompenses partagent une carte lisible et illustrée")
	page.queue_free()
	await get_tree().process_frame
	BattleContext.campaign_node_id = str(saved["campaign_node_id"])
	BattleContext.campaign_service = saved["campaign_service"]
	BattleContext.selected_npc_id = str(saved["selected_npc_id"])
	BattleContext.selected_opponent = saved["selected_opponent"]
	BattleContext.last_winner = int(saved["winner"])
	BattleContext.last_score_human = int(saved["human"])
	BattleContext.last_score_ai = int(saved["ai"])
	BattleContext.last_reward = saved["reward"]


func _tree_contains_text(root: Node, needle: String) -> bool:
	if root is Label and needle.to_lower() in (root as Label).text.to_lower():
		return true
	for child in root.get_children():
		if _tree_contains_text(child, needle):
			return true
	return false
