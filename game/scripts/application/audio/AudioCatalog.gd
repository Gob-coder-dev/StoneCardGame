## Catalogue unique de la banque audio.
##
## Les identifiants sont stables et les chemins ne sont recopiés nulle part
## ailleurs. Les clés de scène utilisent seulement le nom du fichier `.tscn`
## pour ne pas dupliquer les chemins de GameRoutes et survivre à un déplacement
## de dossier.
class_name AudioCatalog
extends RefCounted

## Métadonnées lues par AudioService sur n'importe quel BaseButton.
const META_SFX := "audio_sfx"
const META_SILENT := "audio_silent"

## Effets sonores.
const SFX_BUTTON := "button"
const SFX_BUTTON_2 := "button_2"
const SFX_PURCHASE := "purchase"
const SFX_STONE_PLACE_LOCAL := "stone_place_local"
const SFX_STONE_PLACE_REMOTE := "stone_place_remote"
const SFX_ATTACK := "attack"
const SFX_ATTACK_MISS := "attack_miss"
const SFX_CAPTURED := "captured"
const SFX_WEAKNESS := "weakness"
const SFX_REPAIR := "repair"
const SFX_RANDOM_BLADE := "random_blade"
const SFX_SWARM := "swarm"
const SFX_PILLAGE := "pillage"
const SFX_COIN_FLIP := "coin_flip"
const SFX_COIN_FLIP_START_BATTLE := "coin_flip_start_battle"
const SFX_COIN_FLIP_VALIDATE := "coin_flip_validate"
const SFX_COIN_FLIP_WRONG := "coin_flip_wrong"
const SFX_BIG_FLAME := "big_flame"
const SFX_LITTLE_FLAME := "little_flame"
const SFX_REVEAL := "reveal"
const SFX_WOOSH := "woosh"
const SFX_ROUND_WON := "round_won"
const SFX_ROUND_DEFEAT := "round_defeat"
const SFX_VICTORY := "victory"
const SFX_DEFEAT := "defeat"
const SFX_DRAW := "draw"

## Effets de résultat qui sont en réalité des morceaux complets. Ils coupent la
## musique de fond le temps de leur diffusion.
const JINGLES := [
	SFX_ROUND_WON,
	SFX_ROUND_DEFEAT,
	SFX_VICTORY,
	SFX_DEFEAT,
	SFX_DRAW,
]

const SFX_PATHS := {
	SFX_BUTTON: "res://data/audio/sfx/ui/button.mp3",
	SFX_BUTTON_2: "res://data/audio/sfx/ui/button_2.mp3",
	SFX_PURCHASE: "res://data/audio/sfx/economy/purchase.wav",
	SFX_STONE_PLACE_LOCAL: "res://data/audio/sfx/combat/stone_place_1.wav",
	SFX_STONE_PLACE_REMOTE: "res://data/audio/sfx/combat/stone_place_2.wav",
	SFX_ATTACK: "res://data/audio/sfx/combat/attack.wav",
	SFX_ATTACK_MISS: "res://data/audio/sfx/combat/attack_miss.wav",
	SFX_CAPTURED: "res://data/audio/sfx/combat/captured.wav",
	SFX_WEAKNESS: "res://data/audio/sfx/combat/weakness.wav",
	SFX_REPAIR: "res://data/audio/sfx/combat/repair.wav",
	SFX_RANDOM_BLADE: "res://data/audio/sfx/combat/random_blade.wav",
	SFX_SWARM: "res://data/audio/sfx/combat/swarm.wav",
	SFX_PILLAGE: "res://data/audio/sfx/combat/pillage.wav",
	SFX_COIN_FLIP: "res://data/audio/sfx/coin_flip/coin_flip.wav",
	SFX_COIN_FLIP_START_BATTLE: "res://data/audio/sfx/coin_flip/coin_flip_start_battle.wav",
	SFX_COIN_FLIP_VALIDATE: "res://data/audio/sfx/coin_flip/coin_flip_validate.mp3",
	SFX_COIN_FLIP_WRONG: "res://data/audio/sfx/coin_flip/coin_flip_wrong.wav",
	SFX_BIG_FLAME: "res://data/audio/sfx/ritual/big_flame.wav",
	SFX_LITTLE_FLAME: "res://data/audio/sfx/ritual/little_flame.wav",
	SFX_REVEAL: "res://data/audio/sfx/ritual/reveal.wav",
	SFX_WOOSH: "res://data/audio/sfx/ritual/woosh.mp3",
	SFX_ROUND_WON: "res://data/audio/sfx/result/round_won.mp3",
	SFX_ROUND_DEFEAT: "res://data/audio/sfx/result/round_defeat.mp3",
	SFX_VICTORY: "res://data/audio/sfx/result/victory.mp3",
	SFX_DEFEAT: "res://data/audio/sfx/result/defeat.mp3",
	SFX_DRAW: "res://data/audio/sfx/result/draw.mp3",
}

## Musiques.
const MUSIC_MAIN_THEME := "main_theme"
const MUSIC_MAP := "map"
const MUSIC_BATTLE := "battle"
const MUSIC_RITUAL := "ritual"
const DEFAULT_MUSIC := MUSIC_MAIN_THEME

const MUSIC_PATHS := {
	MUSIC_MAIN_THEME: "res://data/audio/music/main_theme.ogg",
	MUSIC_MAP: "res://data/audio/music/map.ogg",
	MUSIC_BATTLE: "res://data/audio/music/battle.ogg",
	MUSIC_RITUAL: "res://data/audio/music/ritual.wav",
}

## Une seule piste par écran. Les clés sont les noms de fichiers de scène.
const SCENE_MUSIC := {
	"MainMenu.tscn": MUSIC_MAIN_THEME,
	"ShopScreen.tscn": MUSIC_MAIN_THEME,
	"CollectionScreen.tscn": MUSIC_MAIN_THEME,
	"HowToPlay.tscn": MUSIC_MAIN_THEME,
	"Stats.tscn": MUSIC_MAIN_THEME,
	"Quests.tscn": MUSIC_MAIN_THEME,
	"PvpLobby.tscn": MUSIC_MAIN_THEME,
	"PvpPreparation.tscn": MUSIC_MAIN_THEME,
	"Result.tscn": MUSIC_MAIN_THEME,
	"PvpResult.tscn": MUSIC_MAIN_THEME,
	"EncounterSelect.tscn": MUSIC_MAP,
	"EncounterPath.tscn": MUSIC_MAP,
	"CampaignMap.tscn": MUSIC_MAP,
	"CampaignPreparation.tscn": MUSIC_MAP,
	"PreBattle.tscn": MUSIC_MAP,
	"Board.tscn": MUSIC_BATTLE,
	"RitualOpening.tscn": MUSIC_RITUAL,
}


static func sfx_path(id: String) -> String:
	return str(SFX_PATHS.get(id, ""))


static func music_path(id: String) -> String:
	return str(MUSIC_PATHS.get(id, ""))


static func is_jingle(id: String) -> bool:
	return JINGLES.has(id)


## Choisit la musique à partir du chemin complet d'une scène.
static func music_for_scene(scene_path: String) -> String:
	return str(SCENE_MUSIC.get(scene_path.get_file(), DEFAULT_MUSIC))
