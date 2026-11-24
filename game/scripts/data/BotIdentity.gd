## Identité du professeur encore utilisé dans la campagne et les tutoriels.
extends RefCounted

const NEUTRAL_BOT_NAME := "Pr.Stone"


static func neutral_source() -> Dictionary:
	return {
		"id": "pr_stone", "name": NEUTRAL_BOT_NAME,
		"description": "Adversaire sans dieu, son deck est composé uniquement de cartes neutres.",
		"asset": "res://assets/gods/pr_stone.png",
		"color": "#bdb4ab", "secondary_color": "#e08a82",
	}


static func stars_text(count: int) -> String:
	var filled := clampi(count, 0, 5)
	return "★".repeat(filled) + "☆".repeat(5 - filled)
