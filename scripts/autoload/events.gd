extends Node
## Global signal bus. Systems emit and listen here instead of holding references to each other.
## Add new signals here (with typed args) rather than creating ad-hoc buses.

# --- App / flow ---
signal scene_change_requested(scene_path: String)
signal game_paused(paused: bool)
signal settings_changed()

# --- Run lifecycle ---
signal run_started(seed_value: int)
signal run_ended(victory: bool)
signal floor_entered(floor_index: int)
signal room_entered(room_index: int)
signal room_cleared(room_index: int)

# --- Player ---
signal player_damaged(amount: int, source: String)
signal player_healed(amount: int)
signal player_died()
signal stats_changed()
signal item_picked_up(item_id: String)
signal consumables_changed()

# --- Economy / colony ---
signal haul_started(room_index: int, value: int)
signal haul_completed(room_index: int, resource_type: String, value: int)
signal brood_rescued(brood_id: String, mutated: bool)
signal comb_banked(amount: int)

# --- Combat ---
signal enemy_killed(enemy_id: String, champion: bool)
signal boss_killed(boss_id: String, no_damage: bool)

# --- Meta ---
signal achievement_unlocked(achievement_id: String)
signal content_unlocked(kind: String, id: String)

# --- Debug ---
signal debug_message(text: String)
