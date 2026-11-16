extends SceneTree
func _init() -> void:
 call_deferred("probe")
func v3(v: Vector3) -> Array:
 return [v.x,v.y,v.z]
func probe() -> void:
 var scene = load("res://assets/hero.glb").instantiate()
 root.add_child(scene)
 var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
 var animator: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
 var grip: Node3D = scene.find_child("GripR",true,false)
 var tip: Node3D = scene.find_child("GripTipR",true,false)
 var clips: Dictionary = {}
 for name in animator.get_animation_list():
  var a: Animation = animator.get_animation(name)
  clips[name] = {"length": a.length,"tracks":a.get_track_count(),"first_track":str(a.track_get_path(0)) if a.get_track_count()>0 else ""}
 var samples: Dictionary = {}
 for name in ["sword_idle","sword_1","rapier_1"]:
  animator.play(name)
  animator.seek(0.25 if name=="sword_1" else 0.7666667 if name=="rapier_1" else 0.0,true)
  await process_frame
  skeleton.force_update_all_bone_transforms()
  await process_frame
  samples[name]={"grip":v3(grip.global_position),"tip":v3(tip.global_position),"blade_direction":v3((tip.global_position-grip.global_position).normalized()),"head":v3(skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin)}
 var result={"skeleton_path":str(scene.get_path_to(skeleton)),"animation_player_path":str(scene.get_path_to(animator)),"bone_count":skeleton.get_bone_count(),"grip_path":str(scene.get_path_to(grip)),"tip_path":str(scene.get_path_to(tip)),"clips":clips,"samples":samples}
 var f=FileAccess.open("res://assets/godot_hero_probe.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(result,"  "))
 print(JSON.stringify(result))
 quit(0)
