extends RefCounted
# Weapon meshes are authored here; the hero remains the external skinned model.
# Local +Y is the blade direction. Origin is the middle of the grip.

static func material(col: Color, glow: bool = false) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = col
 m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 m.roughness = 0.8
 if glow:
  m.emission_enabled = true
  m.emission = col
  m.emission_energy_multiplier = 0.25
 return m

static func box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 n.mesh = mesh
 n.material_override = mat
 n.position = center
 parent.add_child(n)
 return n

static func build(kind: int) -> Dictionary:
 var root := Node3D.new()
 root.name = ["Sword", "Greatsword", "Rapier"][clampi(kind,0,2)]
 var lengths := [0.817,1.161,0.90]
 var widths := [0.116,0.241,0.035]
 var grips := [0.215,0.31,0.185]
 var guard_widths := [0.31,0.405,0.25]
 var length: float = lengths[kind]
 var width: float = widths[kind]
 var grip: float = grips[kind]
 var guard_y: float = grip * 0.5
 var base: float = guard_y + 0.047
 var dark := material(Color("33485c"))
 var steel := material(Color("8cafb8"))
 var edge := material(Color("edf0d3"))
 var copper := material(Color("a67848"))
 var gold := material(Color("d9b46a"))
 var leather := material(Color("352b31"))
 box(root,Vector3.ZERO,Vector3(0.065,grip,0.075),leather)
 for sign_value in [-1,1]:
  box(root,Vector3(0,grip*0.28*sign_value,0),Vector3(0.071,0.028,0.079),copper)
 box(root,Vector3(0,guard_y,0),Vector3(guard_widths[kind],0.055,0.09),copper)
 box(root,Vector3(0,-grip*0.5-0.03,0),Vector3(0.09,0.07,0.09),gold)
 # Four-sided cross section, tapered metal blade. No transparent blade ghosts.
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var verts := [Vector3(-width*.5,base,0),Vector3(0,base,0.028),Vector3(width*.5,base,0),Vector3(0,base,-0.028),Vector3(-width*.38,base+length*.78,0),Vector3(0,base+length*.78,0.022),Vector3(width*.38,base+length*.78,0),Vector3(0,base+length*.78,-0.022),Vector3(0,base+length,0)]
 if kind == 2:
  for i in range(verts.size()):
   verts[i].z *= 0.45
 var tri := [[0,1,5],[0,5,4],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7],[4,5,8],[5,6,8],[6,7,8],[7,4,8]]
 var colors := [Color("709aa5"),Color("b6d1cf"),Color("edf0d3"),Color("4a6479")]
 for i in range(tri.size()):
  st.set_color(colors[(i/2) % 4])
  for idx in tri[i]: st.add_vertex(verts[idx])
 st.generate_normals()
 var blade := MeshInstance3D.new()
 blade.mesh = st.commit()
 var blade_mat := StandardMaterial3D.new()
 blade_mat.vertex_color_use_as_albedo = true
 blade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 blade.material_override = blade_mat
 root.add_child(blade)
 if kind == 2:
  var basket := MeshInstance3D.new()
  var torus := TorusMesh.new()
  torus.inner_radius = 0.075
  torus.outer_radius = 0.09
  torus.rings = 16
  torus.ring_segments = 6
  basket.mesh = torus
  basket.material_override = gold
  basket.position = Vector3(0,guard_y-0.025,0)
  root.add_child(basket)
  box(root,Vector3(0.07,0.0,0),Vector3(0.018,grip*.78,0.018),gold)
 elif kind == 1:
  box(root,Vector3(0,base+0.08,0.031),Vector3(0.10,0.16,0.015),copper)
  for side in [-1,1]:
   box(root,Vector3(side*guard_widths[kind]*.43,guard_y-0.02,0),Vector3(0.06,0.08,0.10),gold)
 else:
  box(root,Vector3(0,base+0.03,0.031),Vector3(0.055,0.05,0.015),gold)
 return {"root":root,"base":Vector3(0,base,0),"tip":Vector3(0,base+length,0),"grip":grip}
