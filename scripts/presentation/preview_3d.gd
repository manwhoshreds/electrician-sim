class_name Preview3D
extends RefCounted
## A little 3D window for a 2D screen: a model in its own world, lit and framed,
## optionally turning. Used for the parts on the truck screen and the products
## on the website.


## The window. `spinners` collects the pivot to turn, if `spin`.
static func make(model: Node3D, size_px: Vector2i, spin: bool, spinners: Array[Node3D], look := Vector3(0.45, 0.35, 1.0)) -> Control:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = size_px
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = size_px
	frame.add_child(vp)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	var box := bounds(model)
	model.position = -box.get_center()
	var cam := Camera3D.new()
	cam.fov = 30.0
	var reach := box.size.length() * 0.5 / tan(deg_to_rad(cam.fov / 2.0)) * 1.15
	vp.add_child(cam)
	cam.look_at_from_position(look.normalized() * maxf(reach, 0.05), Vector3.ZERO, Vector3.UP)
	cam.near = 0.002
	cam.far = maxf(reach * 4.0, 10.0)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(1, 2, 2), Vector3.ZERO, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(-2, 0.5, 1), Vector3.ZERO, Vector3.UP)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	if spin:
		spinners.append(pivot)
	return frame


## The model's box, from its meshes, in its own space (before it's in a tree).
static func bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model:
			xf = (n as Node3D).transform * xf if n is Node3D else xf
			n = n.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if model.rotation != Vector3.ZERO:
		box = Transform3D(Basis.from_euler(model.rotation), Vector3.ZERO) * box
	return box if not first else AABB(Vector3(-0.05, -0.05, -0.05), Vector3(0.1, 0.1, 0.1))


## A box of a colour, for building simple models.
static func block(parent: Node3D, size: Vector3, at: Vector3, c: Color, metal := 0.2, rough := 0.45) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat(c, metal, rough)
	mi.position = at
	parent.add_child(mi)
	return mi


static func rod(parent: Node3D, r: float, length: float, at: Vector3, c: Color, rot := Vector3.ZERO, sides := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = length
	m.radial_segments = sides
	mi.mesh = m
	mi.material_override = mat(c, 0.6, 0.35)
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func mat(c: Color, metal := 0.2, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m
