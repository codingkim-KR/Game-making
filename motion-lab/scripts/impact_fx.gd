extends Node3D
## A brief contact burst. It follows the contact point, never the whole blade.

var hit: Dictionary = {}
var age: float = 0.0
var lifetime: float = 0.36
var bits: Array[Dictionary] = []
var ring: MeshInstance3D
var ring_mat: StandardMaterial3D
var core: MeshInstance3D
var core_mat: StandardMaterial3D

func setup(data: Dictionary) -> void:
	hit = data.duplicate()
	if is_inside_tree():
		global_position = hit.get("position", Vector3.ZERO)

func _ready() -> void:
	global_position = hit.get("position", Vector3.ZERO)
	global_position.z = 0.46
	var weapon: int = int(hit.get("weapon", 0))
	var strength: float = clampf(float(hit.get("strength", 1.0)), 0.4, 2.2)
	var direction: float = signf(float(hit.get("direction", 1.0)))
	if direction == 0.0:
		direction = 1.0
	var accent := Color(0.40, 0.91, 0.94)
	if weapon == 1:
		accent = Color(1.0, 0.66, 0.26)
	elif weapon == 2:
		accent = Color(0.76, 0.90, 1.0)
	core_mat = _material(Color(1.0, 0.97, 0.76))
	core = _quad_star(0.12 * strength, 0.04 * strength, core_mat)
	add_child(core)
	if weapon == 2:
		core.scale.x = 1.65
	ring_mat = _material(accent)
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.075
	torus.outer_radius = 0.087
	torus.rings = 16
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2.0
	add_child(ring)
	var count: int = 10 if weapon == 1 else 7
	for i in range(count):
		var a: float = -1.10 + float(i) / maxf(1.0, float(count - 1)) * 2.20
		var velocity := Vector3(cos(a) * direction, sin(a), 0.0) * (1.3 + 0.22 * float(i % 4)) * strength
		var mat := _material(accent if i % 3 != 0 else Color(1.0, 0.95, 0.65))
		var spark := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.065 + 0.015 * float(i % 3), 0.014, 0.014)
		spark.mesh = mesh
		spark.material_override = mat
		spark.rotation.z = atan2(velocity.y, velocity.x)
		add_child(spark)
		bits.append({"node": spark, "velocity": velocity, "mat": mat, "start": Vector3.ZERO})
	# A few brown splinters communicate the dummy's wooden material.
	for i in range(3):
		var mat := _material(Color(0.76, 0.48, 0.24))
		var chip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.035, 0.055, 0.018)
		chip.mesh = mesh
		chip.material_override = mat
		add_child(chip)
		bits.append({"node": chip, "velocity": Vector3(direction * (0.8 + i * 0.38), 1.0 + i * 0.28, 0.0), "mat": mat, "start": Vector3.ZERO, "spin": 5.0 + i})

func _process(delta: float) -> void:
	age += delta
	var t := age / lifetime
	if t >= 1.0:
		queue_free()
		return
	if is_instance_valid(core):
		core.visible = age < 0.075
		core.scale *= maxf(0.0, 1.0 - delta * 6.0)
	if is_instance_valid(ring):
		ring.scale = Vector3.ONE * (0.65 + t * 3.0)
		ring_mat.albedo_color.a = maxf(0.0, 0.65 * (1.0 - t * 1.8))
	for bit in bits:
		var n: MeshInstance3D = bit["node"]
		var velocity: Vector3 = bit["velocity"]
		n.position = velocity * age + Vector3(0.0, -2.8 * age * age, 0.0)
		if bit.has("spin"):
			n.rotation.z += float(bit["spin"]) * delta
		var mat: StandardMaterial3D = bit["mat"]
		mat.albedo_color.a = maxf(0.0, 1.0 - t)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _quad_star(radius: float, width: float, mat: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var a := float(i) * PI / 2.0
		var p := Vector3(cos(a), sin(a), 0.0) * radius
		var normal := Vector3(-sin(a), cos(a), 0.0) * width
		surface.add_vertex(normal)
		surface.add_vertex(p)
		surface.add_vertex(-normal)
	var ob := MeshInstance3D.new()
	ob.mesh = surface.commit()
	ob.material_override = mat
	return ob
