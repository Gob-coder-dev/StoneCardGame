## Présentation pure du salon : transforme l'état applicatif en textes et états
## de contrôles. Aucune scène, aucun réseau, aucune mutation du coordinateur.
class_name PvpLobbyPresenter
extends RefCounted


static func header(lobby: Dictionary) -> Dictionary:
	if bool(lobby.get("remote_in_game", false)):
		return {"title": "ADVERSAIRE EN PARTIE",
			"hint": "Attendez son retour au salon pour relancer une partie."}
	match str(lobby.get("status", "")):
		LanLobbyCoordinator.STATUS_CONNECTED:
			return {"title": "ADVERSAIRE CONNECTÉ",
				"hint": "Vérifiez votre dieu, puis touchez PRÊT."}
		LanLobbyCoordinator.STATUS_BOTH_READY:
			return {"title": "LES DEUX JOUEURS SONT PRÊTS",
				"hint": "La partie démarre…"}
		LanLobbyCoordinator.STATUS_ERROR:
			return {"title": "ERREUR", "hint": str(lobby.get("error", ""))}
	return {"title": "SALLE OUVERTE",
		"hint": "En attente d'un adversaire sur le même Wi-Fi…"}


static func rules(lobby: Dictionary) -> Dictionary:
	var config: Dictionary = lobby.get("rules", {})
	var locked := bool(config.get("locked", false)) or bool(lobby.get("started", false))
	var host := bool(lobby.get("is_host", false))
	var remote_in_game := bool(lobby.get("remote_in_game", false))
	var mode := str(config.get("mode", GameModeRules.MODE_CLASSIC))
	var hint := ""
	if remote_in_game:
		hint = "Attendez le retour des deux joueurs au salon."
	elif locked:
		hint = "Règles verrouillées pour la série."
	elif host and mode == GameModeRules.MODE_DRAFT:
		hint = "Sélection commence au palier 2 : huit choix doubles exigent seize lignées distinctes."
	elif not host:
		hint = "Seul l'hôte peut modifier ces options."
	return {
		"config": config,
		"editable": host and not locked and not remote_in_game,
		"uses_power_tier": mode != GameModeRules.MODE_CLASSIC,
		"minimum_tier": GameModeRules.minimum_power_tier(mode),
		"hint": hint,
	}
