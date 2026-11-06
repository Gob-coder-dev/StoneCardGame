## Calculs purs du layout de préparation. Le contrôleur applique uniquement les
## tailles retournées aux grilles et ne porte plus les règles responsive.
class_name PvpPreparationLayout
extends RefCounted


static func draft_columns(width: float) -> int:
	return 2 if width > 0.0 and width < float(UITheme.PVP_NARROW_WIDTH) else 4


static func draft_sizes(viewport_size: Vector2, scroll_size: Vector2,
		panel_min_height: float, grid_widths: Array, counts: Array,
		deck_columns: int, current_sizes: Array) -> Dictionary:
	var current_grids := grid_height(int(counts[0]), 2, int(current_sizes[0])) \
		+ grid_height(int(counts[1]), 2, int(current_sizes[1])) \
		+ grid_height(int(counts[2]), deck_columns, int(current_sizes[2]))
	var fixed_height := maxf(0.0, panel_min_height - current_grids)
	var deck_rows := ceili(float(DeckRules.DECK_SIZE) / float(deck_columns))
	var gaps := float(maxi(0, deck_rows - 1)) * UITheme.GAP_MEDIUM
	var tablet := viewport_size.y > 0.0 \
		and viewport_size.x / viewport_size.y >= UITheme.PVP_TABLET_ASPECT
	var opponent_cap := UITheme.PVP_TABLET_OPPONENT_CARD_MAX if tablet \
		else UITheme.PVP_OPPONENT_CARD_MAX
	var local_cap := UITheme.PVP_TABLET_LOCAL_CARD_MAX if tablet \
		else UITheme.PVP_LOCAL_CARD_MAX
	var deck_cap := UITheme.PVP_TABLET_DRAFT_CARD_MAX if tablet \
		else UITheme.PVP_DRAFT_CARD_MAX
	var opponent_preferred := width_limited(float(grid_widths[0]), scroll_size.x,
		opponent_cap, 2)
	var local_preferred := width_limited(float(grid_widths[1]), scroll_size.x,
		local_cap, 2)
	var deck_preferred := width_limited(float(grid_widths[2]), scroll_size.x,
		deck_cap, deck_columns)
	var available := maxf(1.0, scroll_size.y - fixed_height - gaps)
	var weighted := opponent_preferred + local_preferred \
		+ float(deck_rows) * deck_preferred
	var scale := minf(1.0, available / maxf(1.0, weighted))
	return {
		"opponent": int(maxf(120.0, floorf(opponent_preferred * scale))),
		"local": int(maxf(180.0, floorf(local_preferred * scale))),
		"deck": int(maxf(120.0, floorf(deck_preferred * scale))),
	}


static func reveal_size(scroll_size: Vector2, panel_min_height: float,
		grid_width: float, current_size: int) -> int:
	var rows := ceili(float(DeckRules.DECK_SIZE) / 2.0)
	var current_grid := grid_height(DeckRules.DECK_SIZE, 2, current_size)
	var fixed_height := maxf(0.0, panel_min_height - current_grid)
	var gaps := float(rows - 1) * UITheme.GAP_MEDIUM
	var height_limited := floorf((scroll_size.y - fixed_height - gaps) / float(rows))
	var width_limit := width_limited(grid_width, scroll_size.x,
		UITheme.PVP_FINAL_CARD_MAX, 2)
	return int(maxf(140.0,
		minf(minf(float(UITheme.PVP_FINAL_CARD_MAX), width_limit), height_limited)))


static func width_limited(grid_width: float, fallback_width: float,
		preferred: int, columns: int) -> float:
	var available := grid_width if grid_width > 0.0 else fallback_width
	var gaps := float(maxi(0, columns - 1)) * UITheme.GAP_MEDIUM
	return maxf(1.0, minf(float(preferred),
		floorf((available - gaps) / float(maxi(1, columns)))))


static func grid_height(count: int, columns: int, card_size: int) -> float:
	if count <= 0:
		return 0.0
	var rows := ceili(float(count) / float(maxi(1, columns)))
	return float(rows * card_size) + float(maxi(0, rows - 1)) * UITheme.GAP_MEDIUM

