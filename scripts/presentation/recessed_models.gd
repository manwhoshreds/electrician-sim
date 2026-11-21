class_name RecessedModels
extends RefCounted
## Models for recessed lighting work, built in code: a 6" wafer (its trim, the
## lens that lights, and the snap-shut junction box that rides on top), the
## round blank and splices for the old light's box, and the bits on the truck
## shelf (a coil of 14/2, a 2x4 guard strip).
##
## Box-view space: +Z points down, out of the ceiling; the origin's the
## ceiling face. Names match BoxView.SPEC, and add_to() puts them in the
## interior library so a BoxView finds them like any other model.

const TRIM_R := 0.086             # 6 3/4" across the trim
const HOLE_R := 0.0845            # the hole a 6" wafer wants
const WHITE := Color(0.95, 0.95, 0.93)


static func add_to(lib: Node) -> void:
	for n: Node3D in [wafer_trim(), wafer_lens(), wafer_jbox(), blank_nuts(), blank_cover()]:
		lib.add_child(n)


static func wafer_trim() -> Node3D:
	var root := Node3D.new()
	root.name = "WaferTrim"
	var trim := _disc(TRIM_R, 0.008, _mat(WHITE, 0.45))
	trim.position = Vector3(0, 0, 0.004)
	root.add_child(trim)
	var body := _disc(0.074, 0.012, _mat(Color(0.86, 0.86, 0.84), 0.5))   # the shallow back, up in the hole
	body.position = Vector3(0, 0, -0.006)
	root.add_child(body)
	for s in [-1.0, 1.0]:                                           # the two spring clips
		var clip := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 0.004, 0.03)
		clip.mesh = b
		clip.material_override = _mat(Color(0.7, 0.71, 0.72), 0.3, 0.9)
		clip.position = Vector3(s * 0.07, 0, -0.018)
		clip.rotation.y = s * 0.5
		root.add_child(clip)
	return root


static func wafer_lens() -> MeshInstance3D:
	var lens := _disc(0.07, 0.002, _mat(Color(1.0, 0.98, 0.94), 0.2))
	lens.name = "WaferLens"
	lens.position = Vector3(0, 0, 0.0085)
	return lens


## The junction box on top: open, its lid swung up, with its own leads'
## nuts sticking out the side where you can get at them.
static func wafer_jbox() -> Node3D:
	var root := Node3D.new()
	root.name = "WaferJBox"
	var grey := _mat(Color(0.32, 0.33, 0.35), 0.6)
	var box := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.05, 0.034)
	box.mesh = b
	box.material_override = grey
	box.position = Vector3(0.0, 0, -0.035)
	root.add_child(box)
	var lid := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.003, 0.05, 0.03)
	lid.mesh = lb
	lid.material_override = grey
	lid.position = Vector3(0.037, 0, -0.068)
	lid.rotation.y = 0.4
	root.add_child(lid)
	var flex := MeshInstance3D.new()                                 # the flex lead down to the wafer
	var fc := CylinderMesh.new()
	fc.top_radius = 0.004
	fc.bottom_radius = 0.004
	fc.height = 0.02
	flex.mesh = fc
	flex.material_override = _mat(Color(0.75, 0.76, 0.78), 0.4, 0.8)
	flex.position = Vector3(-0.02, 0, -0.012)
	flex.rotation.x = PI / 2
	root.add_child(flex)
	var nut_colours := {"nut_black": Color(0.85, 0.65, 0.1), "nut_white": Color(0.85, 0.65, 0.1), "f_ground": Color(0.15, 0.55, 0.2)}
	var spec: Dictionary = BoxView.SPEC["Wafer"]["terms"]
	for t: String in spec:
		root.add_child(_nut(spec[t] - Vector3(0.006, 0, 0), Vector3.RIGHT, nut_colours[t]))
		# The wafer's own lead, out of the box to the nut.
		var lead := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.0012
		lc.bottom_radius = 0.0012
		lc.height = 0.01
		lead.mesh = lc
		lead.material_override = _mat({"nut_black": Color(0.03, 0.03, 0.03), "nut_white": Color(0.9, 0.9, 0.88), "f_ground": Color(0.1, 0.5, 0.15)}[t], 0.4)
		lead.position = spec[t] - Vector3(0.012, 0, 0)
		lead.rotation.z = PI / 2
		root.add_child(lead)
	return root


## Three wire nuts on the splices in the old light's box.
static func blank_nuts() -> Node3D:
	var root := Node3D.new()
	root.name = "BlankNuts"
	var spec: Dictionary = BoxView.SPEC["Blank"]["terms"]
	for t: String in spec:
		var c := Color(0.15, 0.55, 0.2) if t == "f_ground" else Color(0.85, 0.65, 0.1)
		root.add_child(_nut(spec[t] - Vector3(0, 0, 0.006), Vector3.BACK, c))
	return root


static func blank_cover() -> Node3D:
	var root := Node3D.new()
	root.name = "BlankCover"
	var plate := _disc(0.06, 0.004, _mat(WHITE, 0.35))
	plate.position = Vector3(0, 0, 0.002)
	root.add_child(plate)
	return root


# --- On the truck --------------------------------------------------------------------

static func part_model(part: String) -> Node3D:
	var root := Node3D.new()
	match part:
		"Wafer":
			var w := Node3D.new()
			w.add_child(wafer_trim())
			w.add_child(wafer_lens())
			w.add_child(wafer_jbox())
			w.rotation.x = -PI / 2           # lying on the shelf, lens up
			root.add_child(w)
		"Blank":
			var c := blank_cover()
			c.rotation.x = -PI / 2
			root.add_child(c)
		"Romex":
			var coil := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.07
			torus.outer_radius = 0.1
			coil.mesh = torus
			coil.material_override = _mat(Color(0.9, 0.89, 0.85), 0.55)
			coil.rotation.x = PI / 2
			root.add_child(coil)
			var label := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(0.06, 0.035, 0.032)
			label.mesh = lb
			label.material_override = _mat(Color(0.85, 0.25, 0.12), 0.6)
			label.position = Vector3(0.085, 0, 0)
			root.add_child(label)
		"GuardStrip":
			var board := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(0.3, 0.038, 0.089)
			board.mesh = bb
			board.material_override = _mat(Color(0.78, 0.62, 0.4), 0.85)
			root.add_child(board)
	return root


# --- Bits ---------------------------------------------------------------------------

## A flat round thing whose faces look along Z.
static func _disc(r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 40
	mi.mesh = c
	mi.material_override = m
	mi.rotation.x = PI / 2
	return mi


## A wire nut at `at`, its open end facing back along `out`.
static func _nut(at: Vector3, out: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0025
	cone.bottom_radius = 0.006
	cone.height = 0.014
	mi.mesh = cone
	mi.material_override = _mat(c, 0.5)
	mi.position = at
	mi.basis = Basis(Quaternion(Vector3.DOWN, -out))   # the wide end at the wires, the point away
	return mi


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
