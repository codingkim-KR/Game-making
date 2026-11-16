extends SceneTree
func _init() -> void:call_deferred("probe")
func probe() -> void:
 var node=load("res://assets/hero.glb").instantiate();root.add_child(node)
 var sk:Skeleton3D=node.find_children("*","Skeleton3D",true,false)[0]
 var ap:AnimationPlayer=node.find_children("*","AnimationPlayer",true,false)[0]
 var b=sk.find_bone("upperarm_r");print("REST ",sk.get_bone_rest(b).basis.get_rotation_quaternion()," INITIALPOSE ",sk.get_bone_pose_rotation(b)," RESTPOS ",sk.get_bone_rest(b).origin,"POSEPOS ",sk.get_bone_pose_position(b))
 var a:Animation=ap.get_animation("sword_idle")
 for i in a.get_track_count():
  if str(a.track_get_path(i)).ends_with(":upperarm_r"):
   if a.track_get_type(i)==Animation.TYPE_ROTATION_3D:print("ROTTRACK ",a.rotation_track_interpolate(i,0.0))
   if a.track_get_type(i)==Animation.TYPE_POSITION_3D:print("POSTRACK ",a.position_track_interpolate(i,0.0))
 ap.play("sword_idle");ap.seek(0,true);await process_frame
 print("AFTERPOSE ",sk.get_bone_pose_rotation(b),"POSEPOS ",sk.get_bone_pose_position(b))
 quit()
