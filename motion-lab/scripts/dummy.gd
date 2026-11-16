extends Node3D
## A non-blocking training target with an independently hinged padded torso.

signal struck(data: Dictionary)
signal reset_completed

var title: String = "목재 더미"
var kind: String = "wood"
var max_health: float = 120.0
var health: float = 120.0
var hit_radius: float = 0.58
var hit_count: int = 0
var total_damage: float = 0.0
var last_damage: float = 0.0
var attackers_enabled: bool = false
var is_attacker: bool = false
var player: Node3D
var frozen: bool = false

var upper: Node3D
var head_pivot: Node3D
var health_bar: MeshInstance3D
var health_material: StandardMaterial3D
var title_label: Label3D
var attack_arm: Node3D
var warning: MeshInstance3D
var upper_materials: Array[StandardMaterial3D] = []
var upper_colors: Array[Color] = []
var numbers: Array[Dictionary] = []
var seen_hits: Dictionary = {}
var seen_order: Array[String] = []
var impact_age: float = 10.0
var impact_power: float = 0.0
var impact_dir: float = 1.0
var break_age: float = -1.0
var idle_time: float = 0.0
var attack_clock: float = 0.0
var attack_fired: bool = false

func _ready() -> void:
	add_to_group("dummies")
	health = max_health
	_build()

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, reactive: bool = false) -> MeshInstance3D:
	var ob := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	ob.mesh = mesh
	ob.position = at
	var mat := _mat(color)
	ob.material_override = mat
	parent.add_child(ob)
	if reactive:
		upper_materials.append(mat)
		upper_colors.append(color)
	return ob

func _sphere(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, reactive: bool = true) -> MeshInstance3D:
	var ob := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 8
	ob.mesh = mesh
	ob.position = at
	var mat := _mat(color)
	ob.material_override = mat
	parent.add_child(ob)
	if reactive:
		upper_materials.append(mat)
		upper_colors.append(color)
	return ob

func _label(text: String, at: Vector3, size: int = 26) -> Label3D:
	var lab := Label3D.new()
	lab.text = text
	lab.position = at
	lab.font_size = size
	lab.pixel_size = 0.006
	lab.outline_size = 5
	lab.modulate = Color(0.76, 0.84, 0.84)
	lab.no_depth_test = false
	if ResourceLoader.exists("res://assets/fonts/NotoSansKR.otf"):
		lab.font = load("res://assets/fonts/NotoSansKR.otf")
	add_child(lab)
	return lab

func _build() -> void:
	var wood := Color(0.48, 0.29, 0.15)
	var pad := Color(0.72, 0.57, 0.34)
	var stripe := Color(0.55, 0.22, 0.16)
	if kind == "armor":
		pad = Color(0.40, 0.53, 0.57)
		stripe = Color(0.75, 0.60, 0.27)
	elif kind == "hanging":
		pad = Color(0.58, 0.67, 0.61)
		stripe = Color(0.20, 0.46, 0.45)
	if kind != "hanging":
		_box(self, Vector3(0, 0.06, 0), Vector3(0.88, 0.12, 0.58), wood)
		_box(self, Vector3(0, 0.48, -0.08), Vector3(0.12, 0.90, 0.14), wood.lightened(0.12))
	else:
		_box(self, Vector3(0, 2.35, -0.08), Vector3(0.032, 1.12, 0.032), Color(0.48, 0.57, 0.57))
	upper = Node3D.new()
	upper.position = Vector3(0, 0.78, 0)
	add_child(upper)
	_sphere(upper, Vector3(0, 0.39, 0), 0.36, 0.87, pad)
	_box(upper, Vector3(0, 0.44, 0.315), Vector3(0.65, 0.10, 0.045), stripe, true)
	_box(upper, Vector3(0, 0.21, 0.338), Vector3(0.58, 0.035, 0.028), pad.lightened(0.22), true)
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 0.85, 0)
	upper.add_child(head_pivot)
	_sphere(head_pivot, Vector3(0, 0.08, 0), 0.205, 0.36, pad.lightened(0.12))
	# Two small seams make facing and rotation legible at gameplay scale.
	_box(head_pivot, Vector3(-0.072, 0.08, 0.187), Vector3(0.035, 0.012, 0.014), wood, true)
	_box(head_pivot, Vector3(0.072, 0.08, 0.187), Vector3(0.035, 0.012, 0.014), wood, true)
	_box(self, Vector3(0, 2.06, 0.10), Vector3(0.91, 0.045, 0.04), Color(0.12, 0.17, 0.20))
	health_material = _mat(Color(0.25, 0.75, 0.67))
	health_bar = _box(self, Vector3(0, 2.06, 0.13), Vector3(0.87, 0.023, 0.025), Color.WHITE)
	health_bar.material_override = health_material
	title_label = _label(title, Vector3(0, 2.26, 0.12), 24)
	if is_attacker:
		attack_arm = Node3D.new()
		attack_arm.position = Vector3(0, 1.23, 0.28)
		add_child(attack_arm)
		_box(attack_arm, Vector3(-0.75, 0, 0), Vector3(1.50, 0.11, 0.12), Color(0.55, 0.29, 0.18))
		_box(attack_arm, Vector3(-1.46, 0, 0), Vector3(0.24, 0.20, 0.20), Color(0.79, 0.43, 0.24))
		attack_arm.rotation.z = -0.8
		warning = _box(self, Vector3(-1.20, 0.026, 0.35), Vector3(2.4, 0.025, 0.32), Color(0.73, 0.24, 0.16))
		warning.visible = false

func get_hit_center() -> Vector3:
	return global_position + Vector3(0.0, 1.14, 0.0)

func receive_hit(data: Dictionary) -> bool:
	if break_age >= 0.0:
		return false
	var key := str(data.get("attack_id", "")) + ":" + str(data.get("hit_id", 0))
	if key != ":0" and seen_hits.has(key):
		return false
	if key != ":0":
		seen_hits[key] = true
		seen_order.append(key)
		if seen_order.size() > 256:
			seen_hits.erase(seen_order.pop_front())
	var damage: float = maxf(0.0, float(data.get("damage", 10.0)))
	last_damage = damage
	total_damage += damage
	hit_count += 1
	health = maxf(0.0, health - damage)
	idle_time = 0.0
	impact_age = 0.0
	impact_power = clampf(float(data.get("strength", 1.0)), 0.45, 2.1)
	impact_dir = signf(float(data.get("direction", 1.0)))
	if impact_dir == 0.0:
		impact_dir = 1.0
	if kind == "armor":
		impact_power *= 0.72
	if float(data.get("strength", 1.0)) >= 1.2:
		attack_clock = minf(attack_clock, 0.85)
		attack_fired = false
	var info := data.duplicate()
	info["target"] = self
	info["target_name"] = title
	info["damage"] = damage
	info["target_health"] = health
	info["hit_count"] = hit_count
	if not info.has("position"):
		info["position"] = get_hit_center()
	struck.emit(info)
	var lab := _label(str(roundi(damage)), Vector3(0.05 * impact_dir, 1.73, 0.52), 32)
	lab.modulate = Color(1.0, 0.85, 0.49)
	numbers.append({"node": lab, "age": 0.0, "origin": lab.position, "direction": impact_dir})
	if health <= 0.0:
		break_age = 0.0
	return true

func reset_dummy() -> void:
	health = max_health
	break_age = -1.0
	impact_age = 10.0
	impact_power = 0.0
	idle_time = 0.0
	attack_clock = 0.0
	attack_fired = false
	seen_hits.clear()
	seen_order.clear()
	if is_instance_valid(upper):
		upper.position = Vector3(0, 0.78, 0)
		upper.rotation = Vector3.ZERO
		upper.scale = Vector3.ONE
		upper.visible = true
	reset_completed.emit()

func _process(delta: float) -> void:
	if frozen:
		return
	impact_age += delta
	idle_time += delta
	if break_age >= 0.0:
		break_age += delta
		upper.rotation.z = -impact_dir * lerpf(0.2, 1.2, minf(1.0, break_age * 3.0))
		upper.position = Vector3(impact_dir * minf(0.6, break_age), 0.78 - minf(0.6, break_age * 0.75), 0)
		if break_age > 0.75:
			upper.visible = false
		if break_age > 1.4:
			reset_dummy()
	else:
		var q: float = exp(-9.5 * impact_age) * cos(18.0 * impact_age) * impact_power
		upper.position = Vector3(impact_dir * 0.12 * q, 0.78 - maxf(0.0, q) * 0.055, 0)
		upper.rotation.z = -impact_dir * 0.31 * q
		upper.scale = Vector3(1.0 + maxf(0.0, q) * 0.065, 1.0 - maxf(0.0, q) * 0.12, 1.0)
		head_pivot.rotation.z = impact_dir * 0.10 * sin(impact_age * 18.0) * exp(-7.0 * impact_age) * impact_power
		if idle_time > 4.0 and health < max_health:
			health = minf(max_health, health + delta * max_health * 0.6)
	var flash: float = 0.0
	if impact_age < 0.045:
		flash = 0.9 * (1.0 - impact_age / 0.045)
	for i in range(upper_materials.size()):
		upper_materials[i].albedo_color = upper_colors[i].lerp(Color(1.0, 0.96, 0.76), flash)
	health_bar.scale.x = maxf(0.001, health / max_health)
	health_bar.position.x = -0.435 * (1.0 - health / max_health)
	for i in range(numbers.size() - 1, -1, -1):
		var item: Dictionary = numbers[i]
		item["age"] = float(item["age"]) + delta
		var age: float = item["age"]
		var lab: Label3D = item["node"]
		lab.position = item["origin"] + Vector3(float(item["direction"]) * age * 0.13, age * 0.7, 0)
		lab.modulate.a = clampf(1.0 - age / 0.7, 0.0, 1.0)
		if age >= 0.7:
			lab.queue_free()
			numbers.remove_at(i)
	_process_attacker(delta)

func _process_attacker(delta: float) -> void:
	if not is_attacker:
		return
	if not attackers_enabled or break_age >= 0.0:
		warning.visible = false
		attack_arm.rotation.z = lerp_angle(attack_arm.rotation.z, -0.8, delta * 8.0)
		return
	attack_clock += delta
	if attack_clock >= 2.6:
		attack_clock -= 2.6
		attack_fired = false
	var telegraph: bool = attack_clock >= 1.25 and attack_clock < 1.90
	warning.visible = telegraph
	var target: float = -0.8
	if telegraph:
		target = -1.25
	elif attack_clock >= 1.90 and attack_clock < 2.13:
		target = 0.08
	attack_arm.rotation.z = lerp_angle(attack_arm.rotation.z, target, minf(1.0, delta * 28.0))
	if attack_clock >= 1.94 and not attack_fired:
		attack_fired = true
		if is_instance_valid(player):
			var relative: Vector3 = player.global_position - global_position
			if relative.x < 0.3 and relative.x > -2.5 and absf(relative.y) < 1.65:
				if player.has_method("take_hit"):
					player.call("take_hit", 12.0, Vector3(-5.6, 3.0, 0.0))
