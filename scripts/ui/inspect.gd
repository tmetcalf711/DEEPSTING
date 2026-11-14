extends RefCounted
## Builds the "what is this?" label shown in the HUD side panel when the wasp is near an item,
## ware or pickup. Every inspectable actor returns one of these dictionaries from inspect_info():
##   {title, kind, body, extra, color: Color, icon: Texture2D}
## Curse of the Toxic Fog hides items (they read as "???").

const QUALITY_COLORS: Array[Color] = [Color(0.65, 0.65, 0.65), Color(0.95, 0.95, 0.95), Color(0.45, 0.95, 0.45), Color(0.45, 0.7, 1.0), Color(1.0, 0.78, 0.25)]


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


static func blind() -> bool:
	return RunController.instance != null and RunController.instance.curse_effect() == "blind_items"


static func unknown() -> Dictionary:
	return {"title": _t("INSPECT_UNKNOWN"), "kind": _t("INSPECT_KIND_ITEM"), "body": _t("INSPECT_UNKNOWN_DESC"),
		"extra": "", "color": Color(0.7, 0.7, 0.75), "icon": Art.texture("items", "unknown")}


static func for_item(id: String) -> Dictionary:
	if id == "":
		return {}
	if blind():
		return unknown()
	var it: Dictionary = Content.get_entry("items", id)
	var q: int = clampi(int(it.get("quality", 1)), 0, 4)
	var kind := _t("INSPECT_KIND_ACTIVE") if it.get("kind", "") == "active" else _t("INSPECT_KIND_ITEM")
	for e in it.get("effects", []):
		if e.get("type", "") == "active":
			kind += "  ·  " + (_t("INSPECT_CHARGE") % int(e.get("charge", 1)))
	return {"title": _t(it.get("name_key", id)), "kind": kind + "  ·  " + (_t("INSPECT_QUALITY") % q),
		"body": _t(it.get("desc_key", "")), "extra": "", "color": QUALITY_COLORS[q], "icon": Art.texture("items", id)}


static func for_trinket(id: String) -> Dictionary:
	var t: Dictionary = Content.get_entry("trinkets", id)
	return {"title": _t(t.get("name_key", id)), "kind": _t("INSPECT_KIND_TRINKET"), "body": _t(t.get("desc_key", "")),
		"extra": _t("INSPECT_SWAP_HINT") if RunState.trinket != "" else "", "color": Color(0.9, 0.78, 0.5), "icon": Art.texture("trinkets", id)}


static func for_fossil(id: String) -> Dictionary:
	var f: Dictionary = Content.get_entry("fossils", id)
	return {"title": _t(f.get("name_key", id)), "kind": _t("INSPECT_KIND_FOSSIL"), "body": _t(f.get("desc_key", "")),
		"extra": _t("INSPECT_USE_HINT"), "color": Color(0.85, 0.8, 0.68), "icon": Art.texture("fossils", id)}


static func for_fluid(color_id: String) -> Dictionary:
	var fid: String = load("res://scripts/player/effect_host.gd").fluid_for_color(color_id)
	var known: bool = RunState.fluids_identified.has(fid) or RunState.flags.get("identify_fluids", false)
	return {"title": load("res://scripts/player/effect_host.gd").fluid_display_name(color_id), "kind": _t("INSPECT_KIND_FLUID"),
		"body": _t("INSPECT_FLUID_KNOWN") if known else _t("INSPECT_FLUID_UNKNOWN"), "extra": _t("INSPECT_USE_HINT"),
		"color": load("res://scripts/actors/pickup.gd").fluid_color(color_id), "icon": Art.texture("ui", "fluid")}


## A pickup on the floor (or for sale): the payload decides trinket / fossil / fluid.
static func for_pickup(data: Dictionary, payload: String) -> Dictionary:
	match str(data.get("kind", "")):
		"trinket": return for_trinket(payload) if payload != "" else {}
		"fossil": return for_fossil(payload) if payload != "" else {}
		"fluid": return for_fluid(payload) if payload != "" else {}
	return {"title": _t(data.get("name_key", "")), "kind": _t("INSPECT_KIND_PICKUP"), "body": _t("INSPECT_PICKUP_" + str(data["kind"]).to_upper()),
		"extra": "", "color": Color(0.85, 0.85, 0.8), "icon": Art.texture("pickups", str(data["id"]))}
