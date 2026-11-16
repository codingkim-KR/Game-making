extends Node3D
## Four connected practice stations. Geometry and collision share the same bounds.

signal target_struck(data: Dictionary)

const DummyScript = preload("res://scripts/dummy.gd")
var dummies: Array[Node3D] = []
var anchors: Array[Node3D] = []
var player: Node3D
var attackers_enabled: bool = false
var frozen: bool = false
var spawns: Array[Vector3] = [Vector3(-4.2, 0.06, 0), Vector3(10.65, 0.06, 0), Vector3(17.1, 1.26, 0), Vector3(32.0, 0.06, 0)]
var font: Font
var moving_platform: AnimatableBody3D
var platform_time: float = 0.0

func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/NotoSansKR.otf"):
		font = load("res://assets/fonts/NotoSansKR.otf")
	_build_shell()
	_build_stations()

func _material(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _box(name_: String, at: Vector3, size_: Vector3, color: Color, solid: bool = false) -> Node3D:
	var root_: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root_.name = name_
	root_.position = at
	add_child(root_)
	var mesh := BoxMesh.new()
	mesh.size = size_
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(color)
	root_.add_child(visual)
	if solid:
		var body := root_ as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 1
		var shape := BoxShape3D.new()
		shape.size = size_
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	return root_

func _platform(name_: String, center_x: float, top: float, width: float, thickness: float = 0.3) -> void:
	_box(name_, Vector3(center_x, top - thickness * 0.5, -0.05), Vector3(width, thickness, 1.7), Color(0.16, 0.22, 0.27), true)
	_box(name_ + "Edge", Vector3(center_x, top + 0.014, 0.50), Vector3(width, 0.028, 0.032), Color(0.43, 0.67, 0.65))
	_box(name_ + "FrontBand", Vector3(center_x, top - 0.10, 0.81), Vector3(width, 0.045, 0.025), Color(0.24, 0.34, 0.39))

func _label(text: String, at: Vector3, size_: int = 28, color: Color = Color(0.65, 0.76, 0.79)) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size_
	label.pixel_size = 0.007
	label.outline_size = 4
	label.modulate = color
	label.no_depth_test = false
	if font:
		label.font = font
	add_child(label)
	return label

func _build_shell() -> void:
	_box("HallBack", Vector3(18.0, 3.0, -2.0), Vector3(60.0, 10.0, 0.18), Color(0.046, 0.067, 0.088))
	# Recessed masonry and narrow uprights retain depth without competing with motion.
	for x in range(-8, 49, 4):
		_box("BackPillar_%d" % x, Vector3(float(x), 2.85, -1.82), Vector3(0.16, 7.1, 0.18), Color(0.064, 0.091, 0.112))
	for y in [0.0, 2.5, 5.0]:
		_box("BackBand_" + str(y), Vector3(18.0, y, -1.80), Vector3(60, 0.035, 0.03), Color(0.079, 0.111, 0.132))
	_platform("MainFloor", 4.5, 0.0, 29.0, 0.9) # [-10,19]
	_platform("FarFloor", 36.0, 0.0, 20.0, 0.9) # [26,46]
	_box("LeftLimit", Vector3(-10.3, 3.0, 0), Vector3(0.5, 8.0, 2.0), Color(0.11, 0.15, 0.19), true)
	_box("RightLimit", Vector3(46.3, 3.0, 0), Vector3(0.5, 8.0, 2.0), Color(0.11, 0.15, 0.19), true)
	for x in range(-8, 46):
		if x > 18 and x < 26:
			continue
		_box("FloorMark_%d" % x, Vector3(float(x), -0.12, 0.84), Vector3(0.014, 0.10 if x % 5 else 0.20, 0.022), Color(0.29, 0.40, 0.44))
	# The dark pit is visibly below the playable floor; root handles falling resets.
	_box("PitBack", Vector3(22.5, -2.8, -1.25), Vector3(7.0, 5.5, 0.08), Color(0.018, 0.027, 0.037))
	_label("낙하 시 자동 복귀", Vector3(22.5, -1.3, -0.9), 24, Color(0.48, 0.58, 0.64))

func _build_stations() -> void:
	_label("01   검술과 이동", Vector3(1.5, 3.65, -1.3), 34, Color(0.76, 0.81, 0.76))
	_label("차지 자동 발동 · 세검 관통 돌진", Vector3(1.5, 3.26, -1.3), 23)
	_add_dummy(Vector3(0.0, 0.0, 0), "목재", "wood", 120.0)
	_add_dummy(Vector3(1.6, 0.0, 0), "관통 표적", "wood", 120.0)
	_add_dummy(Vector3(3.2, 0.0, 0), "강화 목재", "armor", 220.0)
	_platform("CeilingBar", 7.1, 3.3, 1.6, 0.24)
	_label("천장 접촉", Vector3(7.1, 3.70, -1.3), 21)
	# High wall and landing ledges are solid, not scenery-only markers.
	_label("02   벽차기와 매달리기", Vector3(12.4, 4.35, -1.3), 30, Color(0.76, 0.81, 0.76))
	_platform("WallStep", 9.6, 0.70, 1.1, 0.30)
	_platform("WallTower", 12.1, 3.0, 0.65, 3.0)
	_platform("WallLanding", 14.3, 1.2, 1.9, 0.32)
	# Bright side strips explicitly identify the grippable wall surface.
	_box("WallLeftGrip", Vector3(11.762, 1.52, 0.60), Vector3(0.022, 2.85, 0.035), Color(0.40, 0.72, 0.68))
	_box("WallRightGrip", Vector3(12.438, 1.52, 0.60), Vector3(0.022, 2.85, 0.035), Color(0.40, 0.72, 0.68))
	_label("매달린 뒤 앞 / 위로 올라서기", Vector3(10.0, 2.55, -1.3), 20)
	_add_dummy(Vector3(14.3, 1.2, 0), "벽차기 표적", "wood", 100.0)
	# Jump from the elevated approach, attach, swing, and release across the gap.
	_platform("WireApproach", 17.0, 1.2, 3.2, 0.32)
	_platform("WireExit", 27.0, 1.2, 2.0, 0.32)
	var ramp := _box("ExitRamp", Vector3(29.5, 0.5072, -0.05), Vector3(3.2311, 0.20, 1.7), Color(0.19, 0.29, 0.33), true)
	ramp.rotation.z = -atan2(1.2, 3.0)
	_label("03   와이어", Vector3(22.5, 6.35, -1.3), 34, Color(0.76, 0.81, 0.76))
	_label("연결 · 진자 이동 · 이탈 공격", Vector3(22.5, 5.98, -1.3), 22)
	_add_anchor(Vector3(20.1, 5.2, 0), "Anchor_A")
	_add_anchor(Vector3(24.6, 5.2, 0), "Anchor_B")
	_add_dummy(Vector3(22.6, 1.50, 0), "공중 표적", "hanging", 100.0)
	# The final station is opt-in: it never attacks while the player is learning input.
	_label("04   방어와 피격", Vector3(35.8, 3.65, -1.3), 34, Color(0.76, 0.81, 0.76))
	_label("T  공격 장치 켜기 / 끄기", Vector3(35.8, 3.26, -1.3), 23)
	_add_dummy(Vector3(36.0, 0.0, 0), "공격 장치", "armor", 180.0, true)
	_add_dummy(Vector3(41.0, 0.0, 0), "연격 표적", "wood", 140.0)
	_build_moving_platform()
	_label("이동 발판", Vector3(43.5, 1.32, -1.3), 21)
	for i in range(4):
		var p: Vector3 = get_spawn(i)
		_box("SpawnMark_%d" % i, Vector3(p.x, p.y - 0.025, 0.35), Vector3(0.38, 0.012, 0.16), Color(0.65, 0.48, 0.24))

func _add_dummy(at: Vector3, text: String, kind_: String, hp: float, hostile: bool = false) -> Node3D:
	var dummy := DummyScript.new()
	dummy.title = text
	dummy.kind = kind_
	dummy.max_health = hp
	dummy.is_attacker = hostile
	dummy.position = at
	dummy.name = "Dummy_%d" % dummies.size()
	add_child(dummy)
	dummy.struck.connect(_on_dummy_struck)
	dummies.append(dummy)
	return dummy

func _add_anchor(at: Vector3, name_: String) -> void:
	var root_ := Node3D.new()
	root_.name = name_
	root_.position = at
	root_.add_to_group("wire_anchors")
	root_.set_meta("grapple", true)
	add_child(root_)
	anchors.append(root_)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.12
	mesh.outer_radius = 0.17
	mesh.rings = 20
	mesh.ring_segments = 8
	ring.mesh = mesh
	ring.rotation.x = PI / 2.0
	ring.material_override = _material(Color(0.72, 0.61, 0.33))
	root_.add_child(ring)
	var center := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	center.mesh = ball
	center.material_override = _material(Color(0.50, 0.96, 0.89))
	root_.add_child(center)
	_box(name_ + "Support", Vector3(at.x, at.y + 0.62, -0.32), Vector3(0.08, 1.15, 0.08), Color(0.19, 0.29, 0.32))

func _on_dummy_struck(data: Dictionary) -> void:
	target_struck.emit(data)

func get_spawn(zone: int = 0) -> Vector3:
	return spawns[clampi(zone, 0, spawns.size() - 1)]

func get_zone_for_x(x: float) -> int:
	if x < 8.0:
		return 0
	if x < 15.4:
		return 1
	if x < 30.0:
		return 2
	return 3

func configure_player(value: Node3D) -> void:
	player = value
	for dummy in dummies:
		dummy.set("player", player)

func set_attackers_enabled(value: bool) -> void:
	attackers_enabled = value
	for dummy in dummies:
		dummy.set("attackers_enabled", value)

func set_frozen(value: bool) -> void:
	frozen = value
	for dummy in dummies:
		dummy.set("frozen", value)

func reset_dummies() -> void:
	for dummy in dummies:
		dummy.call("reset_dummy")

func _build_moving_platform() -> void:
	moving_platform = AnimatableBody3D.new()
	moving_platform.name = "MovingPlatform"
	moving_platform.position = Vector3(43.5, 0.47, -0.05)
	moving_platform.collision_layer = 1
	moving_platform.collision_mask = 1
	moving_platform.sync_to_physics = false
	add_child(moving_platform)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 0.22, 1.7)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(Color(0.25, 0.46, 0.48))
	moving_platform.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	moving_platform.add_child(collision)

func _physics_process(delta: float) -> void:
	if frozen:
		return
	platform_time += delta
	if is_instance_valid(moving_platform):
		moving_platform.position.x = 43.5 + sin(platform_time * 0.85) * 0.65
