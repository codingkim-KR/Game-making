extends SceneTree

var player
var hero
var dummy
var world: Node3D
var failures: Array[String] = []
var passed: Array[String] = []
var details: Dictionary = {}
var ready_to_animate := false

func _initialize() -> void:
	call_deferred("_run")

func _process(dt: float) -> bool:
	if ready_to_animate:
		hero.update_state(player.get_visual_state(), dt)
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

func _place(weapon: int, face: float) -> void:
	_input()
	player.reset_at(Vector3.ZERO)
	player.weapon = weapon
	await _step(15)
	_input({"move": face})
	await _step(2)
	_input()
	await _step(20)
	dummy.position = player.position + Vector3(face, 0, 0)
	dummy.reset_dummy()

func _run() -> void:
	for action in ["move_left", "move_right", "walk", "jump", "dodge", "attack", "strong", "guard", "wire", "down", "up", "weapon1", "weapon2", "weapon3"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 8)
	collider.shape = shape
	floor_body.position.y = -0.5
	floor_body.add_child(collider)
	world.add_child(floor_body)
	player = load("res://scripts/player.gd").new()
	world.add_child(player)
	hero = load("res://scripts/hero_visual.gd").new()
	hero.name = "Visual"
	player.add_child(hero)
	dummy = load("res://tools/qa_dummy.gd").new()
	world.add_child(dummy)
	ready_to_animate = true
	await _step(30)
	var segment: Array = hero.get_blade_segment()
	_check(segment.size() == 2 and segment[0].distance_to(segment[1]) > 0.3,
		"real_skinned_weapon_socket_available", segment)
	for face in [1.0, -1.0]:
		for weapon in range(3):
			await _place(weapon, face)
			_input({"attack": true})
			await _step(1)
			_input()
			await _step(90)
			_check(dummy.hits.size() == 1, "live_single_weapon_%d_face_%d" % [weapon, int(face)],
				{"hits": dummy.hits.size(), "blade": hero.get_blade_segment()})
			await _place(weapon, face)
			var expected: int = [3, 4, 4][weapon]
			_input({"attack": true})
			await _step(1)
			_input()
			var queued: Dictionary = {}
			for i in range(300):
				var state: Dictionary = player.get_visual_state()
				var idx: int = int(state.get("attack_index", 0))
				if str(state.get("attack_phase")) == "active" and idx < expected - 1 and not queued.has(idx):
					_input({"attack": true})
					queued[idx] = true
				else:
					_input()
				await _step(1)
				if i > 30 and str(player.get_visual_state().get("action")) in ["idle", "move"]:
					break
			var hit_ids: Array = []
			for hit in dummy.hits:
				hit_ids.append(hit.get("attack_id"))
			_check(dummy.hits.size() == expected, "live_combo_weapon_%d_face_%d" % [weapon, int(face)],
				{"hits": dummy.hits.size(), "expected": expected, "ids": hit_ids, "queued": queued.keys()})
	_input()
	var report := {"engine": Engine.get_version_info().string, "platform": OS.get_name(),
		"scope": "Actual imported skeleton, HeroVisual sampling, weapon sockets and controller swept collision. Headless; no rendered visual quality claim.",
		"passed": passed, "failures": failures, "details": details}
	var file := FileAccess.open("res://docs/QA_live_collision.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LAB_V05_LIVE_COLLISION_SUMMARY ", passed.size(), " passed, ", failures.size(), " failed")
	quit(0 if failures.is_empty() else 1)
