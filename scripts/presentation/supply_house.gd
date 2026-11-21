class_name SupplyHouse
extends Node3D
## Cedar Valley Electric Supply: a store you walk into. A doorway and a big
## front window on the street side, a long counter across the room with the
## parts guy behind it, and shelving full of stock behind him. Talking to him
## is the supply house menu (see SupplyCounter).
##
## Placeholder looks: plain boxes and labels, built here so the art can be
## swapped later without touching how buying works. Local +Z faces the street;
## the origin is the middle of the floor.

const SIGN := "ELECTRIC SUPPLY"
const SIGN_COLOUR := Color(0.1, 0.4, 0.9)
const WALL := 0.2
const DOOR_X := 4.2              # the doorway, along the front
const DOOR_W := 1.5
const DOOR_H := 2.4
const WINDOW := Vector4(-5.4, 3.0, 0.3, 2.7)   # x from, x to, y from, y to
const COUNTER_Z := -1.6          # the counter runs wall to wall here
const CLERK_NAME := "Phil"

var size := Vector3(12, 4.0, 10)
var colour := Color(0.75, 0.72, 0.55)
## The parts guy. Whoever runs the counter sets what talking to him does (on_use).
var clerk: Customer
## Who he turns to look at.
var player: Node3D:
	set(v):
		player = v
		if clerk != null:
			clerk.player = v


func _ready() -> void:
	var outside := _flat(colour, 0.85)
	var inside := _flat(Color(0.86, 0.85, 0.8), 0.9)
	_build_walls(outside, inside)
	_build_front()
	_build_counter()
	_build_shelves()
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, size.y - 0.6, -0.5)
	lamp.omni_range = 11.0
	lamp.light_energy = 1.3
	lamp.light_color = Color(1.0, 0.95, 0.86)
	add_child(lamp)
	clerk = Customer.new()
	clerk.person_name = CLERK_NAME
	clerk.look_seed = 113         # same guy every visit
	clerk.waving = false
	clerk.player = player
	clerk.position = Vector3(-1.0, 0.09, COUNTER_Z - 0.75)
	add_child(clerk)
	clerk.prompt = "[E] Talk to %s at the counter" % CLERK_NAME


# --- The shell -------------------------------------------------------------------------

func _build_walls(outside: Material, inside: Material) -> void:
	var hw := size.x / 2
	var hd := size.z / 2
	var h := size.y
	_solid(Vector3(size.x, h, WALL), Vector3(0, h / 2, -hd + WALL / 2), outside)            # back
	for s in [-1.0, 1.0]:
		_solid(Vector3(WALL, h, size.z), Vector3(s * (hw - WALL / 2), h / 2, 0), outside)   # sides
	# Inside faces, a shade lighter, just proud of the walls.
	_box(Vector3(size.x - WALL * 2, h, 0.01), Vector3(0, h / 2, -hd + WALL + 0.005), inside)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.01, h, size.z - WALL * 2), Vector3(s * (hw - WALL - 0.005), h / 2, 0), inside)
	_solid(Vector3(size.x, 0.2, size.z), Vector3(0, h + 0.1, 0), _flat(Color(0.3, 0.3, 0.3), 0.9))   # roof
	_box(Vector3(size.x - WALL * 2, 0.01, size.z - WALL * 2), Vector3(0, h - 0.005, 0), _flat(Color(0.92, 0.92, 0.9), 0.9))
	_solid(Vector3(size.x - WALL * 2, 0.06, size.z - WALL * 2), Vector3(0, 0.06, 0), _flat(Color(0.55, 0.55, 0.52), 0.7))   # floor
	_box(Vector3(size.x + 0.3, 0.5, size.z + 0.3), Vector3(0, h + 0.45, 0), _flat(Color(0.93, 0.92, 0.9), 0.6))      # parapet


## The street side: wall either side of the doorway, the big window, the awning and the sign.
func _build_front() -> void:
	var hw := size.x / 2
	var z := size.z / 2 - WALL / 2
	var h := size.y
	var wall := _flat(colour, 0.85)
	var door_l := DOOR_X - DOOR_W / 2
	var door_r := DOOR_X + DOOR_W / 2
	# Left of the doorway, around the window.
	_solid(Vector3(WINDOW.x + hw, h, WALL), Vector3((-hw + WINDOW.x) / 2, h / 2, z), wall)
	_solid(Vector3(door_l - WINDOW.y, h, WALL), Vector3((WINDOW.y + door_l) / 2, h / 2, z), wall)
	var win_w := WINDOW.y - WINDOW.x
	var win_mid := (WINDOW.x + WINDOW.y) / 2
	_solid(Vector3(win_w, WINDOW.z, WALL), Vector3(win_mid, WINDOW.z / 2, z), wall)
	_solid(Vector3(win_w, h - WINDOW.w, WALL), Vector3(win_mid, (WINDOW.w + h) / 2, z), wall)
	var glass := _flat(Color(0.5, 0.65, 0.75), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.25
	_solid(Vector3(win_w, WINDOW.w - WINDOW.z, 0.04), Vector3(win_mid, (WINDOW.z + WINDOW.w) / 2, z), glass)
	# Over and right of the doorway.
	_solid(Vector3(DOOR_W, h - DOOR_H, WALL), Vector3(DOOR_X, (DOOR_H + h) / 2, z), wall)
	_solid(Vector3(hw - door_r, h, WALL), Vector3((door_r + hw) / 2, h / 2, z), wall)
	var trim := _flat(Color(0.93, 0.92, 0.9), 0.6)
	for dx in [-1.0, 1.0]:
		_box(Vector3(0.08, DOOR_H, WALL + 0.04), Vector3(DOOR_X + dx * (DOOR_W / 2 + 0.04), DOOR_H / 2, z), trim)
	_box(Vector3(DOOR_W + 0.16, 0.08, WALL + 0.04), Vector3(DOOR_X, DOOR_H + 0.04, z), trim)
	var awning := _box(Vector3(size.x * 0.9, 0.08, 1.6), Vector3(0, 2.85, size.z / 2 + 0.75), _flat(SIGN_COLOUR.darkened(0.2), 0.7))
	awning.rotation.x = 0.25
	var sign := Label3D.new()
	sign.text = SIGN
	sign.font_size = 140
	sign.pixel_size = 0.006
	sign.modulate = SIGN_COLOUR
	sign.outline_size = 18
	sign.outline_modulate = Color(0.05, 0.05, 0.05)
	sign.position = Vector3(0, maxf(size.y - 0.75, 3.55), size.z / 2 + 0.06)
	add_child(sign)
	_label("OPEN", Vector3(win_mid, 2.2, z - 0.05), 48, Color(0.95, 0.25, 0.2), true)


# --- The counter and the stock ------------------------------------------------------------

func _build_counter() -> void:
	var w := size.x - WALL * 2
	_solid(Vector3(w, 1.0, 0.7), Vector3(0, 0.5, COUNTER_Z), _flat(Color(0.35, 0.28, 0.22), 0.6))
	_box(Vector3(w, 0.05, 0.8), Vector3(0, 1.02, COUNTER_Z), _flat(Color(0.82, 0.8, 0.74), 0.4))
	# A till and a parts catalogue on the counter, by where he stands.
	_box(Vector3(0.4, 0.3, 0.35), Vector3(-1.8, 1.2, COUNTER_Z), _flat(Color(0.15, 0.15, 0.16), 0.5))
	_box(Vector3(0.45, 0.04, 0.32), Vector3(-0.2, 1.07, COUNTER_Z + 0.1), _flat(Color(0.85, 0.2, 0.15), 0.8))
	_label("PARTS COUNTER", Vector3(-1.0, 0.7, COUNTER_Z + 0.36), 36, Color(0.95, 0.95, 0.92))


## Shelving behind the counter, sorted like a real supply house, and a rack
## of odds and ends on the shop floor.
func _build_shelves() -> void:
	var back := -size.z / 2 + WALL + 0.3
	var sections := [["BREAKERS", Color(0.15, 0.2, 0.3)], ["DEVICES", Color(0.85, 0.85, 0.8)], ["LIGHTING", Color(0.9, 0.75, 0.3)],
			["WIRE", Color(0.85, 0.45, 0.15)]]
	var steel := _flat(Color(0.4, 0.42, 0.45), 0.5)
	for i in sections.size():
		var x := -4.2 + i * 2.8
		_solid(Vector3(2.4, 2.6, 0.5), Vector3(x, 1.3, back), steel)
		for level in 4:
			for k in 4:
				var stock := _flat((sections[i][1] as Color).darkened(0.1 * ((k + level) % 3)), 0.8)
				_box(Vector3(0.45, 0.35, 0.35), Vector3(x - 0.85 + k * 0.57, 0.35 + level * 0.62, back + 0.2), stock)
		_label(sections[i][0], Vector3(x, 2.85, back + 0.3), 40, Color(0.98, 0.73, 0.16))
	var rack := Vector3(-size.x / 2 + WALL + 0.35, 0, 1.6)
	_solid(Vector3(0.5, 1.8, 3.0), rack + Vector3(0, 0.9, 0), steel)
	for k in 5:
		_box(Vector3(0.3, 0.25, 0.45), rack + Vector3(0.1, 0.4 + (k % 3) * 0.5, -1.1 + k * 0.55), _flat(Color(0.7, 0.7, 0.72), 0.4))
	_label("FITTINGS", rack + Vector3(0.3, 2.0, 0), 36, Color(0.98, 0.73, 0.16)).rotation.y = PI / 2


# --- Helpers ----------------------------------------------------------------------------------

## A box you can see.
func _box(s: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = s
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	add_child(mi)
	return mi


## A box you can see and bump into.
func _solid(s: Vector3, at: Vector3, m: Material) -> void:
	_box(s, at, m)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	shape.shape = b
	body.position = at
	body.add_child(shape)
	add_child(body)


func _label(text: String, at: Vector3, font: int, c: Color, both_sides := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.05, 0.05)
	l.position = at
	l.double_sided = both_sides
	add_child(l)
	return l


func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
