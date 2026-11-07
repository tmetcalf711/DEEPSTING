extends RefCounted
## Field Journal-style: reveals every room on the floor, secrets included.


static func activate(_player: Node2D, _params: Dictionary) -> void:
	var rc := RunController.instance
	for a in rc.layout["rooms"]:
		rc.layout["rooms"][a]["revealed"] = true
	Events.minimap_changed.emit()
	Events.toast.emit(TranslationServer.translate("TOAST_MAP_REVEALED"))
