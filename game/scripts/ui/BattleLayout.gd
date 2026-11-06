## Calcul pur de la composition verticale du combat.
##
## Le canevas `expand` ajoute de la hauteur aux téléphones étroits et de la
## largeur aux tablettes. Cette classe utilise les deux contraintes pour éviter
## que le surplus soit absorbé entre le plateau carré et la main.
class_name BattleLayout
extends RefCounted

const PHONE_HAND_COLUMNS := 3
const REGULAR_HAND_COLUMNS := 4
const MIN_BOARD_RATIO_FOR_LARGE_HAND := 0.84
const MAX_PHONE_HAND_CARD := 320.0
## Le rendu 4x2 de la tablette était déjà correct : on le conserve et on
## réserve l'agrandissement 3x3 aux canevas réellement hauts.
const MAX_REGULAR_HAND_CARD := 220.0
const MIN_HAND_CARD := 150.0


static func calculate(content_size: Vector2, fixed_height: float,
		section_gap: float, card_gap: float, deck_size: int) -> Dictionary:
	var width := maxf(1.0, content_size.x)
	var height_for_board_and_hand := maxf(1.0,
		content_size.y - fixed_height - section_gap * 3.0)
	var phone := _candidate(width, height_for_board_and_hand,
		PHONE_HAND_COLUMNS, card_gap, deck_size, MAX_PHONE_HAND_CARD)
	if float(phone["board_side"]) >= width * MIN_BOARD_RATIO_FOR_LARGE_HAND:
		return phone
	return _candidate(width, height_for_board_and_hand,
		REGULAR_HAND_COLUMNS, card_gap, deck_size, MAX_REGULAR_HAND_CARD)


static func _candidate(width: float, available_height: float, columns: int,
		card_gap: float, deck_size: int, card_cap: float) -> Dictionary:
	var rows := ceili(float(deck_size) / float(columns))
	var width_card := floorf(
		(width - card_gap * float(columns - 1)) / float(columns))
	var card_size := clampf(width_card, MIN_HAND_CARD, card_cap)
	var hand_height := card_size * float(rows) + card_gap * float(rows - 1)
	var board_side := minf(width, available_height - hand_height)
	if board_side < 1.0:
		# Repli pour les fenêtres exceptionnellement courtes : la main réduit
		# d'abord, le plateau conserve ensuite tout l'espace restant.
		card_size = MIN_HAND_CARD
		hand_height = card_size * float(rows) + card_gap * float(rows - 1)
		board_side = maxf(1.0, minf(width, available_height - hand_height))
	return {
		"hand_columns": columns,
		"hand_rows": rows,
		"hand_card_size": floorf(card_size),
		"hand_height": floorf(hand_height),
		"board_side": floorf(board_side),
	}
