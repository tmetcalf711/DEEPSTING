extends Node
## Challenge room: only enterable at full health. Entering starts 3 waves; the pedestal unlocks
## when the last wave is cleared.

var room: Room


func setup(p_room: Room) -> void:
	room = p_room
	if room.is_cleared:
		return
	room.info["wave"] = 0
	_lock_pedestals(true)
	Events.banner.emit(tr("BANNER_CHALLENGE"), "")
	_spawn_wave()


func _lock_pedestals(on: bool) -> void:
	for p in room.get_tree().get_nodes_in_group("pedestals"):
		if p.get_parent() == room.entities:
			p.locked = on


func _spawn_wave() -> void:
	var waves: Array = room.info.get("waves", [])
	var w: int = int(room.info.get("wave", 0))
	if w >= waves.size():
		return
	var free := room.free_tiles()
	RNG.shuffle(room.rng_enemies, free)
	var player_pos: Vector2 = RunController.instance.player.position if RunController.instance.player else room.center()
	var k := 0
	for id in waves[w]:
		while k < free.size() and room.tile_center(free[k]).distance_to(player_pos) < 48.0:
			k += 1
		var at := room.tile_center(free[k % maxi(1, free.size())])
		k += 1
		room.spawn_enemy(Content.get_entry("enemies", str(id)), at)


## Room hook: the last enemy of a wave died. Returns true when another wave follows.
func on_enemies_cleared() -> bool:
	var waves: Array = room.info.get("waves", [])
	room.info["wave"] = int(room.info.get("wave", 0)) + 1
	if int(room.info["wave"]) < waves.size():
		Events.toast.emit(tr("TOAST_WAVE") % [int(room.info["wave"]) + 1, waves.size()])
		room.enemies_alive += 1  # hold the room shut until the next wave lands
		room.get_tree().create_timer(0.8).timeout.connect(func() -> void:
			room.enemies_alive -= 1
			_spawn_wave())
		return true
	_lock_pedestals(false)
	return false
