## UITheme.gd
## Constantes de design centralisées pour TOUTE l'interface.
## Toutes les valeurs sont pensées pour le canevas de référence 1080×1920
## (ratio 9:16). Le mode d'étirement "canvas_items" les met automatiquement à
## l'échelle de l'écran réel (1080p, 720p, etc.) en conservant le ratio.
##
## Règle du projet : ne JAMAIS poser une marge/taille de police "au hasard"
## dans un écran. On se réfère à ces constantes, pour une UI cohérente partout.
## Pour tout aérer davantage plus tard, il suffit de changer ces valeurs.
class_name UITheme
extends RefCounted

## ─── Marges & espacements (en pixels du canevas 1080 de large) ───────────────
const MARGIN_SCREEN: int = 48      ## marge entre le contenu et le bord d'écran
const GAP_LARGE: int = 40          ## entre grandes sections
const GAP_MEDIUM: int = 28         ## entre éléments d'une section
const GAP_SMALL: int = 16          ## entre éléments proches

## Distance commune aux appuis et au défilement, dans le canevas 1080×1920.
const TOUCH_SLOP: int = 18

## ─── Tailles de police ───────────────────────────────────────────────────────
const FONT_TITLE: int = 64         ## titres d'écran (MON DECK, etc.)
const FONT_SUBTITLE: int = 44      ## sous-titres
const FONT_BODY: int = 36          ## texte courant
const FONT_SMALL: int = 30         ## texte secondaire
const FONT_SCORE: int = 60         ## gros chiffres (scores)
const FONT_BANNER: int = 38        ## bandeau de tour

## ─── HUD de combat ───────────────────────────────────────────────────────────
const HUD_PLATE_HEIGHT: int = 150  ## hauteur fixe des plaques joueur / adversaire
const HUD_CENTER_WIDTH: int = 90   ## zone fixe du symbole central
const FONT_HUD_CENTER: int = 56    ## flèche du joueur actif ou « VS »

## ─── Disposition et tailles des cartes ──────────────────────────────────────
const DECK_COLUMNS: int = 4
const CARD_HAND: int = 220
const CARD_REPLACEMENT: int = 220  ## Indépendante de la taille des cartes en main.
const CARD_DECK: int = 200
const CARD_COLLECTION: int = 300
const CARD_PREVIEW_EDGE_MARGIN: float = 0.06
const CARD_PREVIEW_POWER_BADGE_SCALE: float = 2.0
const CARD_DECK_EDGE_MARGIN: float = 0.04
const DECK_CARD_GAP: int = 40
const CARD_NAME_MAX_FONT_SIZE: int = 64
const CARD_COST_MAX_FONT_SIZE: int = 96
const RULES_END_SPACE: int = 120

## ─── Boutons ─────────────────────────────────────────────────────────────────
const BUTTON_HEIGHT: int = 120     ## hauteur standard d'un bouton
const BUTTON_WIDTH: int = 640      ## largeur standard d'un bouton de menu
const NUMBERED_BUTTON_SIZE := Vector2(128, 112)
const HOME_PORTRAIT_MIN_HEIGHT: float = 300.0
const HOME_PORTRAIT_MAX_HEIGHT: float = 620.0
const HOME_RESERVED_HEIGHT: float = 1320.0
const GOD_DECK_PANEL_HEIGHT: int = 310
const GOD_DECK_PORTRAIT_WIDTH: int = 470
const GOD_DRAWER_TILE_HEIGHT: int = 300
const GOD_PREBATTLE_PORTRAIT_SIZE := Vector2(280, 270)
const GOD_HUD_PORTRAIT_SIZE := Vector2(104, 104)

## ─── Couleurs récurrentes ────────────────────────────────────────────────────
const COL_BG := Color("#151922")
const COL_PANEL_BG := Color("#272d38")
const COL_SURFACE := Color("#343e4d")
const COL_BORDER := Color("#575361")
const COL_TEXT := Color("#e9e1d1")
const COL_TEXT_DIM := Color("#b5b6c0")
const COL_ACCENT := Color("#d7a24d")
const COL_ACCENT_LIGHT := Color("#f0cc8b")
const COL_INK := Color("#211b18")
const COL_SUCCESS := Color("#a6c79a")
const COL_WARNING := Color("#e6bc78")
const COL_ERROR := Color("#df929c")
const COL_DANGER := Color("#713c49")
const COL_TAB_IDLE := Color("#1c222d")
const COL_TAB_BORDER := Color("#434855")
const COL_SELECTED := Color("#453c35")

## Lecture des cartes : le minerai sombre indique la famille, le contour extérieur
## indique la rareté. Un contour unique évite la confusion entre les deux canaux.
const COL_RARITY_COMMON := Color("#bfb7aa")
const COL_RARITY_RARE := Color("#9fd9ff")
const COL_RARITY_EPIC := Color("#d9a8ff")
const COL_RARITY_LEGENDARY := Color("#ffb63b")

## Plateau : le camp appartient à la case, pas au cadre de la carte. Les fonds
## sombres restent assez larges autour des lames pour être lus sur téléphone.
const COL_BOARD_EMPTY_BG := Color("#1b1719")
const COL_BOARD_EMPTY_EDGE := Color("#514852")
const COL_BOARD_HUMAN_BG := Color("#102d4a")
const COL_BOARD_HUMAN_EDGE := Color("#55adff")
const COL_BOARD_AI_BG := Color("#48171f")
const COL_BOARD_AI_EDGE := Color("#ff5f6d")
const COL_BOARD_BLOCKED_BG := Color("#080a0e")
const COL_BOARD_BLOCKED_EDGE := Color("#a44050")
const COL_BOARD_BLOCKED_MARK := Color("#eadfc9")
const COL_BOARD_BLOCKED_SHADOW := Color("#7f2638")
## Alias conservés pour le HUD et les composants existants.
const COL_GOLD := COL_ACCENT
const COL_GOLD_SOFT := COL_BORDER
const COL_PARCHMENT := COL_TEXT
const COL_CRIMSON := COL_DANGER


static func rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"rare", "uncommon": return COL_RARITY_RARE
		"epic": return COL_RARITY_EPIC
		"legendary": return COL_RARITY_LEGENDARY
		_: return COL_RARITY_COMMON


## Surface d'ardoise commune aux panneaux, fiches et listes.
static func panel_style(bg: Color = COL_PANEL_BG, border: Color = COL_BORDER, border_w: int = 2, radius: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = GAP_MEDIUM
	sb.content_margin_right = GAP_MEDIUM
	sb.content_margin_top = GAP_SMALL
	sb.content_margin_bottom = GAP_SMALL
	sb.shadow_color = Color(0.025, 0.035, 0.055, 0.45)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 6)
	return sb


static func nav_tab_style(selected: bool, highlighted: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_SELECTED if selected else COL_TAB_IDLE
	if highlighted:
		style.bg_color = style.bg_color.lightened(0.08)
	style.border_color = COL_ACCENT if selected else COL_TAB_BORDER
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(12)
	return style


## Cadre commun des portraits ; l'écran garde la responsabilité de leur taille.
static func god_portrait_style(family_color: Color, emphasized: bool = false) -> StyleBoxFlat:
	var style := panel_style(COL_BG.darkened(0.12),
		COL_ACCENT_LIGHT if emphasized else family_color, 6 if emphasized else 3, 14)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## Relief et états communs aux boutons de tous les écrans.
static func button_style(primary: bool = false, pressed: bool = false, hovered: bool = false) -> StyleBoxFlat:
	var bg := COL_ACCENT if primary else COL_SURFACE
	if pressed:
		bg = bg.darkened(0.16)
	elif hovered:
		bg = bg.lightened(0.09)
	var style := panel_style(bg, COL_ACCENT_LIGHT if primary else COL_BORDER, 2, 14)
	style.border_width_bottom = 3 if pressed else 6
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.shadow_size = 2 if pressed else 4
	style.shadow_offset = Vector2(0, 2 if pressed else 5)
	return style
