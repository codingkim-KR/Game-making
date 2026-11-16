extends SceneTree

var player
var dummy
var world: Node3D
var anchor: Node3D
var failures: Array[String] = []
var passed: Array[String] = []
var details: Dictionary = {}
var notices: Array[String] = []
var watchdog: Timer
var visual_checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String, detail: Variant = "") -> void:
	details[label] = detail.duplicate(true) if detail is Array or detail is Dictionary else detail
	if condition:
		passed.append(label)
		print("PASS ", label, " ", str(detail))
	else:
		failures.append(label)
		push_error("FAIL " + label + " " + str(detail))

func _step(frames: int) -> void:
	for _i in range(frames):
		await physics_frame
		await process_frame

func _set_input(values: Dictionary = {}) -> void:
	player.set_test_input(values)

func _tap(action: String, held: int = 2) -> void:
	_set_input({action: true})
	await _step(held)
	_set_input()
	await _step(1)

func _place(pos: Vector3 = Vector3.ZERO, settle: int = 8) -> void:
	_set_input()
	player.reset_at(pos)
	await _step(settle)
	dummy.reset_dummy()
	notices.clear()

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	world.add_child(body)

func _snapshot() -> Dictionary:
	return player.get_visual_state()

func _on_timeout() -> void:
	failures.append("watchdog_timeout")
	_write_report()
	quit(2)

func _run() -> void:
	watchdog = Timer.new()
	watchdog.wait_time = 100.0
	watchdog.one_shot = true
	root.add_child(watchdog)
	watchdog.timeout.connect(_on_timeout)
	watchdog.start()
	for action in ["move_left", "move_right", "walk", "jump", "dodge", "attack", "strong", "guard", "wire", "down", "up", "weapon1", "weapon2", "weapon3"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 8))
	_box(Vector3(10.25, 3, 0), Vector3(0.5, 6, 4))
	_box(Vector3(-20, 2.75, 0), Vector3(4, 0.5, 4))
	anchor = Node3D.new()
	anchor.position = Vector3(4, 6, 0)
	world.add_child(anchor)
	anchor.add_to_group("wire_anchors")
	var PlayerScript = load("res://scripts/player.gd")
	player = PlayerScript.new()
	world.add_child(player)
	player.notice.connect(func(message: String) -> void: notices.append(message))
	var DummyScript = load("res://tools/qa_dummy.gd")
	dummy = DummyScript.new()
	dummy.position = Vector3(1.0, 0, 0)
	world.add_child(dummy)
	await _place()
	_check(player.is_on_floor(), "ground_contact")
	await _test_movement()
	await _test_jumps()
	await _test_air_dodge()
	await _test_wall()
	await _test_attacks()
	await _test_charge()
	await _test_landing_and_facing()
	await _test_wire()
	await _test_defense_damage_reset()
	await _test_real_dummy()
	await _test_visual_assets()
	_set_input()
	_write_report()
	watchdog.stop()
	quit(0 if failures.is_empty() else 1)

func _test_movement() -> void:
	await _place()
	_set_input({"move": 1.0})
	await _step(30)
	var running_distance: float = player.position.x
	_check(running_distance > 1.5, "run_moves_player", running_distance)
	var old_vx: float = player.velocity.x
	_set_input({"move": -1.0})
	await _step(1)
	_check(player.velocity.x < old_vx and player.velocity.x > -old_vx * 0.9, "reversal_brakes_without_instant_velocity_flip", [old_vx, player.velocity.x])
	await _step(20)
	_check(player.velocity.x < -1.0 and float(_snapshot().get("facing", 0)) < 0, "reversal_finishes_left", player.velocity)
	_set_input()
	await _step(24)
	_check(absf(player.velocity.x) < 0.15, "release_brakes_to_rest", player.velocity.x)
	await _place()
	_set_input({"move": 1.0, "walk": true})
	await _step(30)
	_check(player.position.x > 0.2 and player.position.x < running_distance * 0.65, "walk_distinct_from_run", {"walk": player.position.x, "run": running_distance})
	_check(absf(player.position.z) < 0.0001, "movement_stays_in_sideview_plane", player.position.z)

func _jump_height(hold: int) -> float:
	await _place()
	_set_input({"jump": true})
	var top: float = 0.0
	for i in range(90):
		await _step(1)
		top = maxf(top, player.position.y)
		if i == hold:
			_set_input()
		if i > 10 and player.is_on_floor():
			break
	_set_input()
	return top

func _test_jumps() -> void:
	var short_h: float = await _jump_height(2)
	var high_h: float = await _jump_height(24)
	_check(high_h > short_h * 1.2 and short_h > 0.15, "variable_jump_height", {"tap": short_h, "hold": high_h})
	await _place()
	_set_input({"jump": true, "move": 1.0})
	await _step(12)
	_set_input({"move": 1.0})
	await _step(2)
	var before: float = player.velocity.y
	_set_input({"jump": true, "move": 1.0})
	await _step(2)
	_check(player.velocity.y <= before + 0.1, "no_unrequested_double_jump", [before, player.velocity.y])
	_set_input({"move": -1.0})
	await _step(1)
	_check(player.velocity.x > -3.0, "midair_reversal_preserves_inertia", player.velocity.x)

	await _place(Vector3(-18.5, 3, 0))
	_set_input({"move": 1.0})
	var left_edge := false
	for _i in range(40):
		await _step(1)
		if not player.is_on_floor():
			left_edge = true
			break
	_set_input({"move": 1.0, "jump": true})
	await _step(2)
	_check(left_edge and player.velocity.y > 1.0, "coyote_jump_after_leaving_platform", {"left": left_edge, "vy": player.velocity.y})

	await _place(Vector3(-4, 0.65, 0), 0)
	player.velocity.y = -3.0
	for _i in range(20):
		await _step(1)
		if player.position.y < 0.22:
			break
	_set_input({"jump": true})
	await _step(8)
	_check(player.position.y > 0.3 and player.velocity.y > 0, "landing_jump_buffer_executes_once", {"y": player.position.y, "vy": player.velocity.y})
	_set_input()

func _test_air_dodge() -> void:
	await _place(Vector3(-4, 12, 0), 0)
	await _tap("dodge")
	_check(str(_snapshot().get("action")) == "dodge", "air_dodge_starts")
	await _step(22)
	await _tap("dodge")
	_check(str(_snapshot().get("action")) != "dodge", "second_air_dodge_rejected")
	await _step(100)
	_check(player.is_on_floor(), "air_dodge_lands")
	_set_input({"jump": true})
	await _step(8)
	await _tap("dodge")
	_check(str(_snapshot().get("action")) == "dodge", "landing_restores_air_dodge")

func _test_wall() -> void:
	await _place(Vector3(9.6, 2.5, 0), 0)
	_set_input({"move": 1.0})
	await _step(20)
	_check(player.is_on_wall() and player.position.y > 0.1, "wall_contact_above_ground", {"position": player.position, "velocity": player.velocity})
	_check(player.velocity.y > -5.0, "wall_slide_limits_descent", player.velocity.y)
	_set_input({"move": 1.0, "jump": true})
	await _step(2)
	_check(player.velocity.x < -0.5 and player.velocity.y > 1.0, "wall_kick_moves_away_and_up", player.velocity)
	_set_input({"move": 1.0})
	await _step(3)
	_check(player.velocity.x < 0, "wall_kick_initial_outward_push_protected", player.velocity.x)

func _test_attacks() -> void:
	var damages: Array[float] = []
	var expected := [3, 4, 4]
	for w in range(3):
		await _place()
		player.weapon = w
		await _tap("attack")
		await _step(90)
		_check(dummy.hits.size() == 1, "single_hit_dedup_weapon_" + str(w), dummy.hits)
		if dummy.hits.size() > 0:
			damages.append(float(dummy.hits[0].get("damage", 0)))
		_check(str(_snapshot().get("action")) in ["idle", "move"], "attack_recovers_weapon_" + str(w), _snapshot().get("action"))
		await _place()
		player.weapon = w
		await _tap("attack", 1)
		var queued: Dictionary = {}
		for i in range(300):
			var state: Dictionary = _snapshot()
			var idx: int = int(state.get("attack_index", 0))
			if str(state.get("attack_phase")) == "active" and idx < int(expected[w]) - 1 and not queued.has(idx):
				_set_input({"attack": true})
				queued[idx] = true
			else:
				_set_input()
			await _step(1)
			if i > 30 and str(_snapshot().get("action")) in ["idle", "move"]:
				break
		_check(dummy.hits.size() == int(expected[w]), "full_combo_weapon_" + str(w), {"hits": dummy.hits.size(), "queued": queued.keys()})
		var ids: Dictionary = {}
		for hit in dummy.hits:
			ids[hit.get("attack_id", -1)] = true
		_check(ids.size() == dummy.hits.size(), "combo_uses_unique_attack_ids_weapon_" + str(w), ids.keys())
	if damages.size() == 3:
		_check(damages[1] > damages[0] and damages[0] > damages[2], "weapon_damage_profiles_differ", damages)

func _test_charge() -> void:
	await _place()
	player.weapon = 1
	_set_input({"strong": true})
	await _step(45)
	_check(str(_snapshot().get("action")) == "charge" and float(_snapshot().get("charge_ratio", 0)) >= 0.70, "greatsword_charge_accumulates", _snapshot().get("charge_ratio"))
	await _step(30)
	_set_input()
	await _step(100)
	_check(dummy.hits.size() == 1, "charged_attack_releases_one_hit", dummy.hits)
	var charged_damage: float = float(dummy.hits[0].get("damage", 0)) if not dummy.hits.is_empty() else 0
	await _place()
	player.weapon = 1
	await _tap("strong", 2)
	await _step(90)
	var plain_damage: float = float(dummy.hits[0].get("damage", 0)) if not dummy.hits.is_empty() else 0
	_check(charged_damage > plain_damage and plain_damage > 0, "charge_changes_attack_strength", {"charged": charged_damage, "tap": plain_damage})
	await _place()
	player.weapon = 1
	_set_input({"strong": true})
	await _step(20)
	_set_input({"strong": true, "dodge": true})
	await _step(12)
	_check(str(_snapshot().get("action")) != "charge", "charge_cancels_into_dodge", _snapshot().get("action"))

func _test_landing_and_facing() -> void:
	await _place()
	player.reset_at(Vector3(0, 0.5, 0))
	player.weapon = 0
	player.velocity.y = -2.0
	await _tap("attack")
	_check(str(_snapshot().get("attack_kind")) == "air", "reset_into_air_does_not_reuse_stale_floor", _snapshot().get("attack_kind"))
	await _step(60)
	_check(player.is_on_floor() and dummy.hits.size() == 1 and str(dummy.hits[0].get("kind", "")) == "air", "aerial_hit_landing_does_not_duplicate_damage", dummy.hits)
	await _place()
	player.weapon = 0
	await _tap("attack", 1)
	for _i in range(20):
		await _step(1)
		if str(_snapshot().get("attack_phase")) == "active":
			break
	_set_input({"move": -1.0})
	await _step(1)
	_check(float(_snapshot().get("facing", 0)) > 0, "active_attack_direction_is_locked", _snapshot().get("facing"))

	await _place()
	player.weapon = 1
	await _tap("attack", 1)
	for _i in range(30):
		await _step(1)
		if str(_snapshot().get("attack_phase")) == "active":
			break
	_set_input({"weapon": 2})
	await _step(3)
	_check(player.weapon == 1, "weapon_swap_does_not_cancel_active_attack", player.weapon)
	await _step(90)
	_check(player.weapon == 2, "weapon_swap_executes_after_recovery", player.weapon)

func _attach_wire(w: int = 0) -> bool:
	anchor.position = Vector3(4, 6, 0)
	await _place(Vector3(1, 3.5, 0), 0)
	player.weapon = w
	player.velocity.x = 2.0
	await _tap("wire")
	return bool(_snapshot().get("rope_connected", false))

func _test_wire() -> void:
	var attached: bool = await _attach_wire()
	_check(attached, "wire_attaches_to_anchor", _snapshot().get("rope_anchor"))
	if attached:
		var max_distance: float = 0
		var initial_distance: float = player.position.distance_to(anchor.position)
		for _i in range(20):
			await _step(1)
			max_distance = maxf(max_distance, player.position.distance_to(anchor.position))
		_check(max_distance < initial_distance + 1.4, "wire_constraint_bounds_swing_radius", {"initial": initial_distance, "max": max_distance})
		var before: Vector3 = player.velocity
		await _tap("jump", 1)
		_check(not bool(_snapshot().get("rope_connected", true)), "wire_jump_releases")
		_check(player.velocity.y < before.y + 1.5, "wire_release_does_not_grant_extra_jump_impulse", {"before": before, "after": player.velocity})

	attached = await _attach_wire(1)
	if attached:
		await _tap("attack")
		_check(bool(_snapshot().get("rope_connected", false)) and str(_snapshot().get("action")) != "attack", "greatsword_wire_light_preserves_attachment")
		await _tap("strong", 1)
		_check(not bool(_snapshot().get("rope_connected", true)) and str(_snapshot().get("action")) == "attack", "greatsword_wire_strong_releases_and_attacks", _snapshot().get("attack_kind"))
	attached = await _attach_wire(2)
	if attached:
		await _tap("attack")
		_check(bool(_snapshot().get("rope_connected", false)) and str(_snapshot().get("action")) == "attack", "rapier_can_attack_while_wire_attached", _snapshot().get("attack_kind"))
	anchor.position = Vector3(5, 12, 0)
	await _place(Vector3(1, 8, 0), 1)
	await _tap("dodge")
	await _step(24)
	var before_attach_dodges: int = int(_snapshot().get("air_dodges_left", -1))
	await _tap("wire")
	if bool(_snapshot().get("rope_connected", false)):
		await _step(12)
		await _tap("dodge")
		_check(before_attach_dodges == 0 and int(_snapshot().get("air_dodges_left", -1)) == 0 and bool(_snapshot().get("rope_connected", false)) and str(_snapshot().get("action")) != "dodge", "wire_does_not_refill_air_dodge")
	else:
		_check(false, "wire_does_not_refill_air_dodge", "fixture could not attach after air dodge")

func _test_defense_damage_reset() -> void:
	await _place()
	var hp: float = player.health
	player.take_hit(20.0, Vector3(-5, 2, 0))
	_check(player.health < hp, "unprotected_hit_damages_player", [hp, player.health])
	var injured: float = player.health
	player.take_hit(20.0, Vector3(-5, 2, 0))
	_check(is_equal_approx(player.health, injured), "hurt_grace_prevents_duplicate_damage")
	await _place()
	hp = player.health
	_set_input({"guard": true})
	await _step(3)
	player.take_hit(20.0, Vector3(-5, 2, 0))
	_check(is_equal_approx(player.health, hp), "timed_guard_parries_front_hit", {"hp": player.health, "notices": notices})
	await _place()
	hp = player.health
	await _tap("dodge", 3)
	player.take_hit(20.0, Vector3(-5, 2, 0))
	_check(is_equal_approx(player.health, hp), "dodge_window_avoids_damage")
	await _place()
	player.take_hit(9999.0, Vector3(-5, 2, 0))
	_check(str(_snapshot().get("action")) == "dead", "lethal_hit_enters_death")
	await _place()
	_check(player.health > 0 and not bool(_snapshot().get("rope_connected", true)) and str(_snapshot().get("action")) == "idle", "reset_restores_playable_state", _snapshot())

func _test_real_dummy() -> void:
	if not FileAccess.file_exists("res://scripts/dummy.gd"):
		_check(false, "real_dummy_available")
		return
	var DummyScript = load("res://scripts/dummy.gd")
	var actual = DummyScript.new()
	world.add_child(actual)
	actual.position = Vector3(-10, 0, 0)
	await _step(1)
	var hit := {"attack_id": 89898, "position": Vector3(-10, 1, 0), "direction": 1.0, "strength": 1.0, "damage": 12.0, "weapon": 0}
	var first: bool = actual.receive_hit(hit)
	var duplicate: bool = actual.receive_hit(hit)
	_check(first and not duplicate, "real_dummy_deduplicates_same_attack")
	actual.reset_dummy()
	var after_reset: bool = actual.receive_hit(hit)
	_check(after_reset, "real_dummy_reset_clears_hit_history")
	actual.queue_free()
	await _step(1)

func _test_visual_assets() -> void:
	_check(FileAccess.file_exists("res://assets/hero.glb"), "live_skinned_hero_asset_present")
	if not FileAccess.file_exists("res://assets/hero.glb"):
		return
	var packed = load("res://assets/hero.glb")
	if packed is PackedScene:
		var scene = packed.instantiate()
		world.add_child(scene)
		var skeletons: Array[Node] = scene.find_children("*", "Skeleton3D", true, false)
		var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
		_check(not skeletons.is_empty(), "hero_has_real_skeleton")
		_check(not players.is_empty(), "hero_has_authored_animation_bank")
		if not players.is_empty():
			visual_checks["animations"] = players[0].get_animation_list()
			var required := ["walk", "run", "jump", "jump_land", "sword_1", "sword_2", "sword_3", "great_1", "great_2", "great_3", "great_4", "rapier_1", "rapier_2", "rapier_3", "rapier_4", "rapier_idle", "guard", "hit", "death"]
			var missing: Array[String] = []
			for clip in required:
				if not players[0].has_animation(clip):
					missing.append(clip)
			_check(missing.is_empty(), "required_authored_clips_available", missing)
		if not skeletons.is_empty():
			visual_checks["bones"] = skeletons[0].get_bone_count()
			_check(skeletons[0].find_bone("hand_r") >= 0 and skeletons[0].find_bone("hand_l") >= 0, "weapon_and_wire_hand_bones_available")
		scene.queue_free()
		await _step(1)
	else:
		_check(false, "hero_glb_imports_as_scene")

func _write_report() -> void:
	var report := {"engine": Engine.get_version_info()["string"], "passed": passed, "failures": failures, "details": details, "visual_assets": visual_checks, "scope": "Actual Godot headless 3D physics and controller, controlled fixtures. No rendered-image or Windows-execution claim.", "platform": OS.get_name()}
	var f := FileAccess.open("res://docs/QA_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("LAB_V05_QA_SUMMARY ", passed.size(), " passed, ", failures.size(), " failed")
