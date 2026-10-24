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
const CARD_DECK: int = 210
const CARD_COLLECTION: int = 300
const CARD_INFO: int = 700

## ─── Boutons ─────────────────────────────────────────────────────────────────
const BUTTON_HEIGHT: int = 120     ## hauteur standard d'un bouton
const BUTTON_WIDTH: int = 640      ## largeur standard d'un bouton de menu
const NUMBERED_BUTTON_SIZE := Vector2(128, 112)

## ─── Couleurs récurrentes ────────────────────────────────────────────────────
const COL_GOLD := Color("#e8c050")
const COL_GOLD_SOFT := Color("#d8b84a")
const COL_PARCHMENT := Color("#e8dcc0")
const COL_TEXT := Color("#e8dcc0")
const COL_TEXT_DIM := Color("#b8a888")
const COL_PANEL_BG := Color("#140c06")
const COL_BG := Color("#120a05")
const COL_SUCCESS := Color("#91d060")
const COL_WARNING := Color("#e8c878")
const COL_ERROR := Color("#f07060")
const COL_CRIMSON := Color("#6f1717")
const COL_TAB_IDLE := Color("#20150d")
const COL_TAB_BORDER := Color("#4a3a22")


## Crée une StyleBoxFlat "panneau sombre bordé d'or" réutilisable.
static func panel_style(bg: Color = COL_PANEL_BG, border: Color = COL_GOLD_SOFT, border_w: int = 3, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = GAP_MEDIUM
	sb.content_margin_right = GAP_MEDIUM
	sb.content_margin_top = GAP_SMALL
	sb.content_margin_bottom = GAP_SMALL
	return sb


static func nav_tab_style(selected: bool, highlighted: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CRIMSON if selected else COL_TAB_IDLE
	if highlighted:
		style.bg_color = style.bg_color.lightened(0.08)
	style.border_color = COL_GOLD if selected else COL_TAB_BORDER
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(12)
	return style
