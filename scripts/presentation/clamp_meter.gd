class_name ClampMeter
extends Node3D
## The one meter you carry: a clamp meter. Red jaws on top for amps, test leads
## into the jacks at the bottom for volts and ohms, and a big dial on the face
## that says which it's reading. Nothing reads until you turn the dial to it.
##
## There's only one meter, so where the dial's turned is shared (`dial`): leave
## it on amps at the panel and it's still on amps at the water heater.
##
## Built from primitives at real size, in metres. The origin is the middle of the
## body, the face looks down +Z, the jaws are up +Y.

enum Mode { OFF, VOLTS, OHMS, AMPS }

const MODE_NAMES := ["OFF", "V~", "Ω", "A~"]
const UNITS := ["", "V AC", "Ω", "A AC"]
## Where each setting sits round the dial, in radians anticlockwise from the
## dial's right: OFF low on the left, round and up to amps at the top.
const DIAL_ANGLE := [3.75, 2.97, 2.36, 1.75]
const DIAL_AT := Vector3(0.01, 0.028, 0.0)
## The middle of the jaws: what goes round the wire.
const JAW_CENTRE := Vector3(0, 0.122, 0)

## Where the dial's turned. One meter, so it stays put between views and jobs.
static var dial := Mode.OFF

var red_jack: Node3D
var black_jack: Node3D
var _knob: Node3D
var _digits: Label3D
var _unit: Label3D
var _shown := -1


## Turns the dial one click on (step 1) or back (-1), round past OFF.
static func turn(step := 1) -> Mode:
	dial = posmod(dial + step, Mode.size()) as Mode
	return dial


## The setting the dial's on, as printed by it: "V~", "Ω", "A~" or "OFF".
static func setting() -> String:
	return MODE_NAMES[dial]


## A little picture of it for a tool belt slot, centred on `o`: red jaws, yellow
## body, dark face, the dial.
static func draw_icon(c: CanvasItem, o: Vector2) -> void:
	c.draw_arc(o + Vector2(0, -20), 11.0, 0.0, TAU, 24, Color(0.85, 0.11, 0.07), 5.0, true)
	c.draw_rect(Rect2(o + Vector2(-8, -12), Vector2(16, 8)), Color(0.85, 0.11, 0.07))
	c.draw_rect(Rect2(o + Vector2(-15, -5), Vector2(30, 40)), Color(0.96, 0.7, 0.07))
	c.draw_rect(Rect2(o + Vector2(-11, -1), Vector2(22, 32)), Color(0.17, 0.18, 0.2))
	c.draw_circle(o + Vector2(2, 7), 6.0, Color(0.96, 0.7, 0.07))
	c.draw_rect(Rect2(o + Vector2(-8, 17), Vector2(16, 8)), Color(0.66, 0.71, 0.6))


func _ready() -> void:
	_build()
	_sync_dial()


func _process(_delta: float) -> void:
	if _shown != dial:
		_sync_dial()


## What's on the display, digits only (the unit follows the dial). Blank when OFF.
func show_reading(text: String) -> void:
	if _digits != null:
		_digits.text = text if dial != Mode.OFF else ""


func _sync_dial() -> void:
	_shown = dial
	if _knob == null:
		return
	_knob.rotation.z = DIAL_ANGLE[dial] - PI / 2.0      # the pointer's drawn along +Y
	_unit.text = UNITS[dial]
	if dial == Mode.OFF:
		_digits.text = ""


# --- The model --------------------------------------------------------------------------

func _build() -> void:
	var yellow := _mat(Color(0.96, 0.7, 0.07), 0.55)
	var red := _mat(Color(0.85, 0.11, 0.07), 0.5)
	var face := _mat(Color(0.17, 0.18, 0.2), 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.5)
	var light := Color(0.9, 0.9, 0.9)

	# Body, the ridge that keeps your hand off the jaws, the red neck, then the jaws.
	_mesh(rounded_box(Vector2(0.078, 0.17), 0.034, 0.014), Vector3(0, -0.005, 0), yellow)
	_mesh(rounded_box(Vector2(0.088, 0.012), 0.038, 0.005), Vector3(0, 0.072, 0), yellow)
	_mesh(rounded_box(Vector2(0.056, 0.032), 0.03, 0.008), Vector3(0, 0.09, 0), red)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.02
	torus.outer_radius = 0.032
	torus.rings = 40
	var jaws := _mesh(torus, JAW_CENTRE, red)
	jaws.rotation.x = PI / 2.0
	jaws.scale = Vector3(1.0, 2.0, 1.0)                 # flat and deep, like real jaws
	_mesh(_box(Vector3(0.003, 0.014, 0.026)), JAW_CENTRE + Vector3(0, 0.026, 0), dark)   # where they part
	var trigger := _mesh(rounded_box(Vector2(0.014, 0.046), 0.022, 0.006), Vector3(-0.047, 0.06, 0), red)
	trigger.rotation.z = 0.35

	# The face: dark panel, dial, HOLD, display, the name.
	_mesh(rounded_box(Vector2(0.064, 0.13), 0.002, 0.008), Vector3(0, -0.005, 0.0175), face)
	_knob = Node3D.new()
	_knob.position = DIAL_AT + Vector3(0, 0, 0.019)
	add_child(_knob)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.018
	disc.bottom_radius = 0.018
	disc.height = 0.007
	disc.radial_segments = 28
	var knob := _mesh(disc, Vector3(0, 0, 0.0035), yellow, _knob)
	knob.rotation.x = PI / 2.0
	_mesh(_box(Vector3(0.008, 0.034, 0.005)), Vector3(0, 0, 0.0085), yellow, _knob)      # the grip across it
	_mesh(_box(Vector3(0.0025, 0.012, 0.001)), Vector3(0, 0.009, 0.0112), dark, _knob)    # the pointer
	for m in Mode.size():
		var a: float = DIAL_ANGLE[m]
		var at := DIAL_AT + Vector3(cos(a), sin(a), 0) * 0.027
		_text(MODE_NAMES[m], Vector3(at.x, at.y, 0.0188), 22 if m == Mode.OFF else 28, light)

	var hold := CylinderMesh.new()
	hold.top_radius = 0.0045
	hold.bottom_radius = 0.0045
	hold.height = 0.003
	_mesh(hold, Vector3(-0.021, 0.004, 0.019), _mat(Color(0.35, 0.42, 0.6), 0.5)).rotation.x = PI / 2.0
	_text("HOLD", Vector3(-0.021, -0.004, 0.0188), 14, light)

	_mesh(_box(Vector3(0.054, 0.03, 0.002)), Vector3(0, -0.03, 0.0185), _mat(Color(0.66, 0.71, 0.6), 0.45))
	var ink := Color(0.05, 0.06, 0.05)
	_digits = _text("", Vector3(-0.002, -0.034, 0.0198), 60, ink)
	_unit = _text("", Vector3(0.016, -0.02, 0.0198), 18, ink)
	_mesh(_box(Vector3(0.01, 0.005, 0.002)), Vector3(0, -0.052, 0.019), _mat(Color(0.35, 0.36, 0.38), 0.5))
	_text("CLAMP METER", Vector3(0, -0.062, 0.0188), 16, Color(0.98, 0.6, 0.12))

	# The jacks the leads plug into, down at the bottom.
	red_jack = _jack(0.018, Color(0.8, 0.08, 0.06))
	black_jack = _jack(-0.018, Color(0.07, 0.07, 0.08))
	_text("VΩ", Vector3(0.018, -0.0705, 0.0175), 14, Color(0.1, 0.1, 0.1))
	_text("COM", Vector3(-0.018, -0.0705, 0.0175), 14, Color(0.1, 0.1, 0.1))


func _jack(x: float, c: Color) -> Node3D:
	var ring := CylinderMesh.new()
	ring.top_radius = 0.0055
	ring.bottom_radius = 0.0055
	ring.height = 0.004
	var j := _mesh(ring, Vector3(x, -0.08, 0.0175), _mat(c, 0.4))
	j.rotation.x = PI / 2.0
	return j


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _text(text: String, pos: Vector3, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.00026
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	add_child(l)
	return l


## A slab with rounded corners, centred, facing +Z.
static func rounded_box(size: Vector2, depth: float, radius: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var outline: Array[Vector2] = []
	var dirs: Array[Vector2] = []
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c in 4:
		var centre: Vector2 = (corners[c] as Vector2) * (size / 2.0 - Vector2(radius, radius))
		for k in 7:
			var a := PI / 2.0 * c + PI / 2.0 * k / 6.0
			var d := Vector2(cos(a), sin(a))
			outline.append(centre + d * radius)
			dirs.append(d)
	var n := outline.size()
	var hz := depth / 2.0
	for z_sign in [1.0, -1.0]:
		var base := verts.size()
		verts.append(Vector3(0, 0, z_sign * hz))
		normals.append(Vector3(0, 0, z_sign))
		for i in n:
			verts.append(Vector3(outline[i].x, outline[i].y, z_sign * hz))
			normals.append(Vector3(0, 0, z_sign))
		for i in n:
			indices.append_array(PackedInt32Array([base, base + 1 + i, base + 1 + (i + 1) % n]))
	var ring := verts.size()
	for i in n:
		verts.append(Vector3(outline[i].x, outline[i].y, hz))
		normals.append(Vector3(dirs[i].x, dirs[i].y, 0))
		verts.append(Vector3(outline[i].x, outline[i].y, -hz))
		normals.append(Vector3(dirs[i].x, dirs[i].y, 0))
	for i in n:
		var j := (i + 1) % n
		indices.append_array(PackedInt32Array([ring + i * 2, ring + i * 2 + 1, ring + j * 2, ring + j * 2, ring + i * 2 + 1, ring + j * 2 + 1]))
	for k in range(0, indices.size(), 3):          # Godot's front faces wind clockwise
		var swap := indices[k + 1]
		indices[k + 1] = indices[k + 2]
		indices[k + 2] = swap
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
