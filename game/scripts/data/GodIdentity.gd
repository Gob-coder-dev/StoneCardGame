## Identités d'affichage des camps sans dieu.
##
## Le vide reste la donnée du domaine : aucun dieu n'est équipé. L'interface
## doit en revanche distinguer un joueur humain d'un bot. Un humain sans dieu
## porte la stèle « Sans dieu » ; un adversaire IA sans dieu porte le portrait
## de Pr.Stone. Ces deux identités ne font jamais partie de `gods.json`.
class_name GodIdentity
extends RefCounted

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const PLAYER_GODLESS_ASSET := "res://assets/gods/sans_dieu.png"


## Identité d'un camp humain. Un identifiant vide ou inconnu devient « Sans
## dieu » ; un dieu valide reste inchangé.
static func player(god_id: String) -> Dictionary:
	var god := StoneLoader.get_god(god_id)
	return god if not god.is_empty() else player_godless()


## Identité d'un adversaire IA. Un bot sans dieu reste Pr.Stone ; un dieu
## valide reste inchangé.
static func bot(god_id: String) -> Dictionary:
	var god := StoneLoader.get_god(god_id)
	return god if not god.is_empty() else bot_godless()


static func player_godless() -> Dictionary:
	return {
		"id": "",
		"name": "Sans dieu",
		"title": "Deck neutre",
		"family_name": "Pierres neutres",
		"description": "Un deck entièrement neutre, sans pouvoir divin.",
		"asset": PLAYER_GODLESS_ASSET,
	}


static func bot_godless() -> Dictionary:
	var source := OpponentCatalogModel.neutral_source()
	return {
		"id": str(source.get("id", "")),
		"name": "Sans dieu",
		"family_name": "",
		"description": str(source.get("description", "")),
		"asset": str(source.get("asset", "")),
	}
