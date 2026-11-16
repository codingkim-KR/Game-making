extends Node3D

var hits: Array[Dictionary] = []
var health: float = 100000.0
var hit_radius: float = 0.65

func _ready() -> void:
	add_to_group("dummies")

func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 0.95, 0)

func get_hit_radius() -> float:
	return hit_radius

func receive_hit(hit: Dictionary) -> bool:
	# Deliberately no dedup here: the player must prevent repeated contacts.
	hits.append(hit.duplicate(true))
	health -= float(hit.get("damage", 0.0))
	return true

func reset_dummy() -> void:
	hits.clear()
	health = 100000.0
