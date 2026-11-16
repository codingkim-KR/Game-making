extends SceneTree
func _initialize() -> void:
 call_deferred("go")
func go() -> void:
 var visual=load("res://scripts/hero_visual.gd").new()
 root.add_child(visual)
 await process_frame
 for face in [-1.0,1.0]:
  var grip:=Vector3(face*.30,1.88,0)
  var s:Dictionary={"action":"ledge","weapon":2,"facing":face,"grounded":false,"action_t":0.0,"velocity":Vector3.ZERO,"ledge_grip":grip}
  for i in range(120):
   s.action_t=float(i)/60.0
   visual.update_state(s,1.0/60.0)
  var before:Array=visual.get_ledge_hands()
  for i in range(120):
   s.action_t=2.0+float(i)/60.0
   visual.update_state(s,1.0/60.0)
  var after:Array=visual.get_ledge_hands()
  assert(not visual.weapon_node.visible,"weapon must be stowed while hanging")
  for i in range(2):
   var drift:float=before[i].distance_to(after[i])
   var distance:float=Vector2(after[i].x-grip.x,after[i].y-grip.y).length()
   assert(drift<0.001,"ledge pose drift")
   assert(distance<0.05,"ledge hand outside ledge")
   print("HANG ",face," hand",i," pos ",after[i]," grip_error ",distance," drift ",drift)
  s={"action":"attack","weapon":2,"facing":face,"grounded":true,"action_t":.20,"velocity":Vector3(face*10.5,0,0),"attack_kind":"strong","attack_charged":true,"attack_charge":1.0,"charge_advancing":true,"attack_startup":8.0/60.0,"attack_active":16.0/60.0,"attack_total":42.0/60.0,"attack_id":int(face)*2,"attack_phase":"active"}
  for i in range(20): visual.update_state(s,1.0/60.0)
  var blade:Array=visual.get_blade_segment()
  var dir:Vector3=(blade[1]-blade[0]).normalized()
  assert(dir.x*face>.98,"charged rapier not pointing along dash")
  print("THRUST ",face," direction ",dir)
 print("PASS v0.5.1 visual: stable two-handed ledge hold; forward charged rapier")
 quit()
