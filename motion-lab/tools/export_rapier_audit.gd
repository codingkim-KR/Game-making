extends SceneTree
func _init() -> void:call_deferred("probe")
func probe() -> void:
 var node=load("res://assets/hero.glb").instantiate();root.add_child(node)
 var sk:Skeleton3D=node.find_children("*","Skeleton3D",true,false)[0]
 var ap:AnimationPlayer=node.find_children("*","AnimationPlayer",true,false)[0]
 var grip:Node3D=node.find_child("GripR",true,false)
 ap.play("rapier_1")
 for i in 17:
  ap.seek(i*.1,true);sk.force_update_all_bone_transforms();await process_frame
  var p:Transform3D=sk.get_bone_global_pose(sk.find_bone("hand_r"))*grip.transform
  print("THRUST ",i*.1," hand ",p.origin," tip ",p*Vector3(0,.85,0))
 quit()
