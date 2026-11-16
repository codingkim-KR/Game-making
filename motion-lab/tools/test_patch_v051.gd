extends SceneTree

# Full controller + authored character: behavior tests for charge and ledge patch.
var player
var hero
var world: Node3D
var targets: Array = []
var failures: Array[String] = []
var passed: Array[String] = []
var details: Dictionary = {}
var animate := false

func _initialize() -> void:
	call_deferred("_run")

func _process(dt: float) -> bool:
	if animate:
		hero.update_state(player.get_visual_state(), 0.0 if player.hitstop_remaining > 0 else dt)
	return false

func _step(frames: int) -> void:
	for _i in range(frames):
		await physics_frame
		await process_frame

func _input(values: Dictionary = {}) -> void:
	player.set_test_input(values)

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	details[label] = detail.duplicate(true) if detail is Array or detail is Dictionary else detail
	if ok:
		passed.append(label)
		print("PASS ", label, " ", detail)
	else:
		failures.append(label)
		push_error("FAIL " + label + " " + str(detail))

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = pos
	body.add_child(collider)
	world.add_child(body)
	return body

func _place(weapon: int = 0, pos: Vector3 = Vector3.ZERO, settle: int = 12) -> void:
	_input()
	player.reset_at(pos)
	player.weapon = weapon
	await _step(settle)

func _target(x: float, radius: float = 0.35):
	var target = load("res://tools/qa_dummy.gd").new()
	target.position = Vector3(x, 0, 0)
	target.hit_radius = radius
	world.add_child(target)
	targets.append(target)
	return target

func _clear_targets() -> void:
	for target in targets:
		target.queue_free()
	targets.clear()
	await _step(2)

func _run() -> void:
	for action in ["move_left", "move_right", "walk", "jump", "dodge", "attack", "strong", "guard", "wire", "down", "up", "weapon1", "weapon2", "weapon3"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 8))
	_box(Vector3(12, 1.5, 0), Vector3(4, 3, 4))
	player = load("res://scripts/player.gd").new()
	world.add_child(player)
	hero = load("res://scripts/hero_visual.gd").new()
	hero.name = "Visual"
	player.add_child(hero)
	animate = true
	await _step(30)
	await _test_auto_charge()
	await _test_piercing_dash()
	await _test_ledge()
	_input()
	await _test_arena_spawns()
	var report := {"engine": Engine.get_version_info().string, "platform": OS.get_name(),
		"scope": "Actual Godot physics, live imported skeletal poses and socket collision. Charge auto-release, displacement, piercing, solid wall and ledge input regression checks. No rendered visual quality or Windows-execution claim.",
		"passed": passed, "failures": failures, "details": details}
	var file := FileAccess.open("res://docs/QA_patch_v051.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LAB_V051_PATCH_SUMMARY ", passed.size(), " passed, ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)

func _test_auto_charge() -> void:
	var full_frames := [36, 60, 30]
	var first_frames := [18, 30, 12]
	for w in range(3):
		await _place(w)
		var initial_id: int = player.attack_id
		_input({"strong": true})
		await _step(full_frames[w] - 2)
		_check(player.action == "charge" and player.attack_id == initial_id,
			"no_premature_auto_release_weapon_%d" % w,
			{"action": player.action, "charge": player.get_visual_state().get("charge_ratio")})
		await _step(5)
		_check(player.action == "attack" and player.attack_id == initial_id + 1,
			"full_charge_auto_releases_weapon_%d" % w,
			{"action": player.action, "charge": player.attack_spec.get("charge", -1), "id": player.attack_id})
		_check(float(player.attack_spec.get("charge", 0)) >= 0.99,
			"auto_release_has_full_strength_weapon_%d" % w, player.attack_spec)
		await _step(200)
		_check(player.attack_id == initial_id + 1 and player.action == "free",
			"held_button_does_not_repeat_weapon_%d" % w,
			{"action": player.action, "attacks": player.attack_id - initial_id})
		var distance: float = player.position.x
		var expected: bool = distance > 0.25 and distance < 1.25 if w < 2 else distance > 2.0 and distance < 4.5
		_check(expected, "charged_forward_distance_weapon_%d" % w, distance)
		await _place(w)
		initial_id = player.attack_id
		_input({"strong": true})
		await _step(first_frames[w] + 1)
		_input()
		await _step(2)
		_check(player.action == "attack" and player.attack_id == initial_id + 1
			and float(player.attack_spec.get("charge", 0)) > 0
			and float(player.attack_spec.get("charge", 1)) < 1,
			"early_manual_charge_release_weapon_%d" % w,
			{"action": player.action, "charge": player.attack_spec.get("charge", -1)})
		await _step(150)
		await _place(w)
		_input({"strong": true})
		await _step(2)
		_input()
		await _step(2)
		_check(player.action == "attack" and float(player.attack_spec.get("charge", 1)) == 0,
			"tap_remains_uncharged_strong_weapon_%d" % w,
			{"action": player.action, "charge": player.attack_spec.get("charge", -1)})
		await _step(120)

func _test_piercing_dash() -> void:
	await _place(2)
	for x in [1.0, 2.0, 3.0]:
		_target(x)
	_input({"strong": true})
	await _step(240)
	var all_once := true
	var ids: Dictionary = {}
	var hits: Array = []
	for target in targets:
		hits.append(target.hits.size())
		all_once = all_once and target.hits.size() == 1
		for hit in target.hits:
			ids[hit.get("attack_id")] = true
	_check(all_once, "rapier_dash_pierces_three_targets_once", {"hits": hits, "end_x": player.position.x})
	_check(ids.size() == 1, "rapier_dash_uses_one_attack_for_all_targets", ids.keys())
	await _clear_targets()
	await _place(2)
	var wall := _box(Vector3(2.0, 1.5, 0), Vector3(0.4, 3.0, 4.0))
	var beyond = _target(3.2)
	await _step(2)
	_input({"strong": true})
	await _step(240)
	_check(player.position.x < 1.60 and player.position.x > 0.5,
		"rapier_dash_stops_at_solid_wall", player.position)
	_check(beyond.hits.is_empty(), "rapier_dash_does_not_damage_through_wall", beyond.hits)
	wall.queue_free()
	await _clear_targets()
	# Charge leftward too: forward must follow facing rather than world +X.
	await _place(2, Vector3(-3, 0, 0))
	_input({"move": -1.0})
	await _step(3)
	_input()
	await _step(20)
	var start_x: float = player.position.x
	_input({"strong": true})
	await _step(200)
	_check(player.position.x < start_x - 2.0, "rapier_dash_follows_left_facing", {"from": start_x, "to": player.position.x})

func _catch_ledge(face: float = 1.0) -> bool:
	await _place(0, Vector3(9.70 if face > 0 else 14.30, 1.52, 0), 0)
	player.velocity.y = -0.3
	_input({"move": face})
	for _i in range(20):
		await _step(1)
		if player.action == "ledge":
			return true
	return false

func _test_ledge() -> void:
	for face in [1.0, -1.0]:
		var caught: bool = await _catch_ledge(face)
		_check(caught, "ledge_grab_geometry_face_%d" % int(face), player.position)
		if not caught:
			continue
		var held_pos: Vector3 = player.position
		await _step(120)
		_check(player.action == "ledge" and player.position.distance_to(held_pos) < 0.005,
			"held_approach_does_not_auto_climb_face_%d" % int(face), {"action": player.action, "position": player.position})
		_input()
		var hand_start: Array = hero.get_ledge_hands() if hero.has_method("get_ledge_hands") else []
		await _step(120)
		_check(player.action == "ledge" and player.position.distance_to(held_pos) < 0.005,
			"ledge_waits_stationary_without_input_face_%d" % int(face), {"action": player.action, "position": player.position})
		var hand_end: Array = hero.get_ledge_hands() if hero.has_method("get_ledge_hands") else []
		var hands_fixed: bool = hand_start.size() == 2 and hand_end.size() == 2
		if hands_fixed:
			for i in range(2):
				hands_fixed = hands_fixed and hand_start[i].distance_to(hand_end[i]) < 0.015
		_check(hands_fixed, "ledge_hand_pose_does_not_cycle_face_%d" % int(face), {"start": hand_start, "end": hand_end})
		var grip: Vector3 = player.get_visual_state().get("ledge_grip", Vector3.ZERO)
		var hands_at_grip: bool = hand_end.size() == 2
		for hand in hand_end:
			hands_at_grip = hands_at_grip and Vector2(hand.x - grip.x, hand.y - grip.y).length() < 0.26
		_check(hands_at_grip, "ledge_hands_reach_top_face_%d" % int(face), {"hands": hand_end, "grip": grip})
		_input({"move": face})
		await _step(2)
		_check(player.action == "climb", "fresh_forward_starts_pullup_face_%d" % int(face), player.action)
		_input()
		await _step(90)
		_check(player.is_on_floor() and player.position.y > 2.95 and player.position.x > 10.0 and player.position.x < 14.0,
			"forward_pullup_finishes_on_top_face_%d" % int(face), {"position": player.position, "action": player.action})
	var caught: bool = await _catch_ledge()
	_check(caught, "ledge_regrab_fixture_for_up", player.position)
	if caught:
		_input()
		await _step(10)
		_input({"up": true})
		await _step(2)
		_check(player.action == "climb", "up_input_starts_pullup", player.action)
		_input()
		await _step(90)
		_check(player.is_on_floor() and player.position.y > 2.95, "up_pullup_finishes_on_top", player.position)
	caught = await _catch_ledge()
	if caught:
		_input({"down": true})
		await _step(10)
		_check(player.action != "ledge" and player.position.y < 1.5, "down_input_drops_from_ledge", player.position)

func _test_arena_spawns() -> void:
	# Isolate the actual arena from the earlier controlled ledge and wall fixtures.
	animate = false
	world.queue_free()
	await _step(2)
	world = Node3D.new()
	root.add_child(world)
	var arena = load("res://scripts/arena.gd").new()
	world.add_child(arena)
	await _step(3)
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.78
	capsule.radius = 0.24
	for station in range(4):
		var spawn: Vector3 = arena.get_spawn(station)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, spawn + Vector3.UP * 0.89)
		query.collision_mask = 1
		query.collide_with_areas = false
		var overlaps: Array = arena.get_world_3d().direct_space_state.intersect_shape(query)
		var names: Array = []
		for overlap in overlaps:
			names.append(str(overlap.get("collider")))
		_check(overlaps.is_empty(), "arena_spawn_capsule_clear_station_%d" % station,
			{"spawn": spawn, "overlapping_bodies": names})
