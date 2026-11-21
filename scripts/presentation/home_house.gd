class_name HomeHouse
extends Node3D
## Your house: small, old and yours. One bedroom, a bathroom, and a front room
## with the kitchen down one end and the desk with the computer you run the
## business from. You can walk in any time; it's never a job site.
##
## Local space like the town's houses: origin on the ground in the middle,
## +Z out the front to the street, X across. Built by Town on the home lot.

const W := 9.0                   # across the front
const D := 7.0                   # front to back
const WALL_H := 2.6
const T := 0.12                  # wall thickness
const PART := 1.5                # the inside wall, across: front room to its left, bedroom and bath to its right
const BATH_Z := 0.6              # bathroom's back wall: bath in front of it, bedroom behind
const DOOR_X := -1.6             # front door, centre
const DOOR_W := 0.95
const ROOM_DOOR_W := 0.85
const BEDROOM_DOOR_Z := -1.3
const BATH_DOOR_Z := 2.2
const INTERIOR := "res://assets/interior/interior.glb"

## Where you use the computer (the office) and go to bed. Their on_use is set by ServiceCall.
var computer: Interactable
var bed: Interactable
## Where you stand when you get up in the morning.
var wake_spot := Vector3.ZERO
var paint: StandardMaterial3D
var _desk_at := Vector3.ZERO
var _lib: Node3D
var _door: Node3D
var _door_shape: CollisionShape3D
var _door_open := false
var _door_use: Interactable


func build(town: Town) -> void:
	_lib = (load(INTERIOR) as PackedScene).instantiate()
	paint = _mat(Color(0.58, 0.56, 0.47), 0.97)          # years since it was painted
	var trim := _mat(Color(0.86, 0.84, 0.78), 0.8)
	var drywall := _mat(Color(0.8, 0.77, 0.7), 0.9)        # a bit grubby
	var floor_mat := _mat(Color(0.42, 0.33, 0.24), 0.85)   # worn wood
	var hw := W / 2.0
	var hd := D / 2.0
	# Floor, ceiling, and the foundation it sits on.
	_box(Vector3(W, 0.04, D), Vector3(0, 0.02, 0), floor_mat)
	_box(Vector3(W + 0.1, 0.3, D + 0.1), Vector3(0, -0.13, 0), _mat(Color(0.5, 0.49, 0.47), 0.9))
	_box(Vector3(W, 0.05, D), Vector3(0, WALL_H + 0.025, 0), drywall)
	# Outside walls: the outside paint on the outer face, drywall inside.
	_wall_x(-hd, -hw, hw, [], paint, drywall, -1.0)                   # back
	_wall_x(hd, -hw, hw, [[DOOR_X, DOOR_W]], paint, drywall, 1.0)     # front, with the door
	_wall_z(-hw, -hd, hd, [], paint, drywall, -1.0)                   # left
	_wall_z(hw, -hd, hd, [], paint, drywall, 1.0)                     # right
	# Inside: the wall down the middle with the bedroom and bathroom doors, and the bathroom's back wall.
	_wall_z(PART, -hd, hd, [[BEDROOM_DOOR_Z, ROOM_DOOR_W], [BATH_DOOR_Z, ROOM_DOOR_W]], drywall, drywall, 1.0)
	_wall_x(BATH_Z, PART, hw, [], drywall, drywall, 1.0)
	# Roof and gable ends, the town's own, and the windows (one boarded up).
	var roof := MeshInstance3D.new()
	roof.mesh = town._roof_mesh(W + Town.ROOF_SIDE_OVERHANG * 2, D + Town.ROOF_OVERHANG * 2, 1.4)
	roof.material_override = _mat(Color(0.24, 0.22, 0.21), 0.9)
	roof.position.y = WALL_H + 0.05
	add_child(roof)
	var gable := MeshInstance3D.new()
	gable.mesh = town._gable_mesh(W, D, 1.4)
	gable.material_override = paint
	gable.position.y = WALL_H + 0.05
	add_child(gable)
	var glass := _mat(Color(0.12, 0.16, 0.2), 0.05)
	glass.metallic = 0.8
	for spot: Array in [[Vector3(-3.4, 1.5, hd), 1.0], [Vector3(3.0, 1.6, hd), 1.0], [Vector3(-2.0, 1.5, -hd), -1.0], [Vector3(3.0, 1.5, -hd), -1.0]]:
		var at: Vector3 = spot[0]
		for side in [1.0, -1.0]:                           # seen from outside and in
			_box(Vector3(1.2, 1.0, 0.02), at + Vector3(0, 0, side * (T / 2 + 0.012)), glass)
			_box(Vector3(1.32, 1.12, 0.015), at + Vector3(0, 0, side * (T / 2 + 0.005)), trim)
	_box(Vector3(1.45, 1.3, 0.03), Vector3(3.0, 1.6, hd + T / 2 + 0.04), _mat(Color(0.62, 0.48, 0.3), 0.9))   # plywood over a broken one
	_tarp()
	_porch(hd)
	_front_door(hd)
	_furnish(hw, hd)
	# Lights in every room, on when it's dark (a dim old bulb in each).
	for at: Vector3 in [Vector3(-1.5, WALL_H - 0.3, 0.0), Vector3(3.0, WALL_H - 0.3, -1.5), Vector3(3.0, WALL_H - 0.3, 2.0)]:
		var bulb := OmniLight3D.new()
		bulb.position = at
		bulb.light_color = Color(1.0, 0.85, 0.62)
		bulb.light_energy = 1.1
		bulb.omni_range = 5.5
		bulb.add_to_group("home_light")
		add_child(bulb)
	_lib.free()


# --- Rooms --------------------------------------------------------------------------------

func _furnish(hw: float, hd: float) -> void:
	# The front room: the desk and computer against the left wall, kitchen at the back, the couch.
	var desk_at := Vector3(-hw + 0.4, 0, -0.8)
	_desk(desk_at)
	_place("BaseCabinet", Vector3(-3.0, 0, -hd), Vector3.BACK)
	_place("BaseCabinet", Vector3(-2.4, 0, -hd), Vector3.BACK)
	_place("Fridge", Vector3(-0.6, 0, -hd), Vector3.BACK)
	_place("Couch", Vector3(-0.4, 0, 2.0), Vector3.LEFT)
	# The bedroom, behind: the bed against the right wall.
	var bed_at := Vector3(hw, 0, -1.6)
	_place("Bed", bed_at, Vector3.LEFT)
	_place("Nightstand", Vector3(hw, 0, -2.9), Vector3.LEFT)
	bed = Interactable.new()
	bed.position = bed_at + Vector3(-1.0, 0, 0)
	bed.aim = Vector3(0, 0.6, 0)
	bed.aim_radius = 0.9
	bed.reach = 2.2
	bed.prompt = "[E] Go to sleep"
	add_child(bed)
	wake_spot = bed_at + Vector3(-2.1, 0, 0.3)
	# The bathroom, in front.
	_place("Toilet", Vector3(hw, 0, 2.9), Vector3.LEFT)
	_place("Vanity", Vector3(3.0, 0, BATH_Z + T / 2), Vector3.BACK)


## A cheap desk, the computer on it, a chair. The computer's where the office is.
func _desk(at: Vector3) -> void:
	var wood := _mat(Color(0.45, 0.32, 0.2), 0.7)
	var black := _mat(Color(0.05, 0.05, 0.06), 0.4)
	var grey := _mat(Color(0.3, 0.31, 0.33), 0.5)
	var x := at.x + 0.35                                  # the desk's middle, out from the wall
	_box(Vector3(0.7, 0.04, 1.3), Vector3(x, 0.74, at.z), wood)
	for dz in [-0.6, 0.6]:
		for dx in [-0.3, 0.3]:
			_box(Vector3(0.04, 0.72, 0.04), Vector3(x + dx, 0.36, at.z + dz), wood)
	_box(Vector3(0.22, 0.42, 0.45), Vector3(x - 0.1, 0.21, at.z + 0.35), black)      # the tower, under the desk
	_box(Vector3(0.05, 0.3, 0.05), Vector3(at.x + 0.12, 0.91, at.z), grey)           # monitor stand
	_box(Vector3(0.25, 0.02, 0.2), Vector3(at.x + 0.12, 0.77, at.z), grey)
	var screen := _mat(Color(0.05, 0.08, 0.12), 0.2)
	screen.emission_enabled = true
	screen.emission = Color(0.25, 0.45, 0.8)
	screen.emission_energy_multiplier = 0.9
	_box(Vector3(0.04, 0.36, 0.6), Vector3(at.x + 0.12, 1.1, at.z), black)           # monitor
	_box(Vector3(0.01, 0.32, 0.55), Vector3(at.x + 0.145, 1.1, at.z), screen)
	_box(Vector3(0.16, 0.02, 0.45), Vector3(x + 0.05, 0.77, at.z), black)            # keyboard
	_box(Vector3(0.09, 0.02, 0.06), Vector3(x + 0.08, 0.77, at.z + 0.35), black)     # mouse
	_box(Vector3(0.48, 0.06, 0.48), Vector3(x + 0.7, 0.47, at.z), grey)              # chair
	_box(Vector3(0.06, 0.5, 0.46), Vector3(x + 0.95, 0.75, at.z), grey)
	_box(Vector3(0.06, 0.44, 0.06), Vector3(x + 0.7, 0.22, at.z), grey)
	_desk_at = at
	computer = Interactable.new()
	computer.position = Vector3(at.x + 0.15, 0, at.z)
	computer.aim = Vector3(0, 1.0, 0)
	computer.aim_radius = 0.45
	computer.reach = 2.0
	computer.prompt = "[E] Use the computer"
	add_child(computer)


## Sitting at the desk, looking straight at the monitor: where the view goes when
## you use the computer. Close enough that the screen fills most of the view, with
## the bezel and a bit of desk still showing round it.
func seat_view() -> Transform3D:
	var screen := to_global(Vector3(_desk_at.x + 0.15, 1.1, _desk_at.z))
	var eye := to_global(Vector3(_desk_at.x + 0.62, 1.1, _desk_at.z))
	return Transform3D(Basis.looking_at(screen - eye, Vector3.UP), eye)


## The monitor's glass (width, height), in metres.
const SCREEN_SIZE := Vector2(0.55, 0.32)


## The middle of the monitor's glass, facing out at the chair (+Z towards you,
## +X to your right): where the desktop is drawn.
func screen_transform() -> Transform3D:
	var face := Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(_desk_at.x + 0.151, 1.1, _desk_at.z))
	return global_transform * face


func _front_door(hd: float) -> void:
	var door_mat := _mat(Color(0.3, 0.2, 0.12), 0.7)
	_door = Node3D.new()                                  # hinged on its left edge
	_door.position = Vector3(DOOR_X - DOOR_W / 2, 0, hd)
	add_child(_door)
	var leaf := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(DOOR_W, 2.05, 0.05)
	leaf.mesh = b
	leaf.material_override = door_mat
	leaf.position = Vector3(DOOR_W / 2, 1.03, 0)
	_door.add_child(leaf)
	var body := StaticBody3D.new()
	_door_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_W, 2.05, 0.08)
	_door_shape.shape = shape
	_door_shape.position = Vector3(DOOR_W / 2, 1.03, 0)
	body.add_child(_door_shape)
	_door.add_child(body)
	_door_use = Interactable.new()
	_door_use.position = Vector3(DOOR_X, 0, hd)
	_door_use.aim = Vector3(0, 1.05, 0)
	_door_use.aim_radius = 0.55
	_door_use.reach = 2.0
	_door_use.on_use = func(_p: Node3D) -> void: toggle_door()
	add_child(_door_use)
	_set_door(false)


func toggle_door() -> void:
	_set_door(not _door_open)


func _set_door(open: bool) -> void:
	_door_open = open
	_door.rotation.y = -PI / 2 * 0.95 if open else 0.0     # swings in
	_door_shape.disabled = open
	_door_use.prompt = "[E] %s the door" % ("Close" if open else "Open")


func is_door_open() -> bool:
	return _door_open


func _porch(hd: float) -> void:
	_box(Vector3(W + 0.4, 0.04, 1.6), Vector3(0, 0.02, hd + 0.8), _mat(Color(0.55, 0.54, 0.51), 0.95))
	var couch := _mat(Color(0.35, 0.3, 0.22), 0.95)       # the old couch out front
	_box(Vector3(1.8, 0.45, 0.75), Vector3(2.4, 0.23, hd + 0.9), couch, true)
	_box(Vector3(1.8, 0.5, 0.2), Vector3(2.4, 0.7, hd + 0.45), couch)
	var cardboard := _mat(Color(0.6, 0.45, 0.28), 0.9)
	_box(Vector3(0.5, 0.4, 0.45), Vector3(-3.6, 0.2, hd + 0.6), cardboard)
	_box(Vector3(0.4, 0.3, 0.4), Vector3(-3.55, 0.55, hd + 0.62), cardboard)
	var tire := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.36
	tire.mesh = torus
	tire.material_override = _mat(Color(0.05, 0.05, 0.05), 0.9)
	tire.position = Vector3(-4.2, 0.1, hd + 3.0)
	add_child(tire)


## A blue tarp over a leak, on the front of the roof.
func _tarp() -> void:
	var rise := 1.4
	var eave := Vector3(0, WALL_H + 0.05 - Town.ROOF_EAVE_DROP, D / 2 + Town.ROOF_OVERHANG)
	var ridge := Vector3(0, WALL_H + 0.05 + rise, 0)
	var tarp := _box(Vector3(2.4, 0.02, 1.8), eave.lerp(ridge, 0.45) + Vector3(-1.8, 0.14, 0), _mat(Color(0.12, 0.3, 0.72), 0.5))
	tarp.rotation.x = atan2(ridge.y - eave.y, eave.z)


# --- Building blocks ----------------------------------------------------------------------

## A wall running along X at z, from x0 to x1, with door gaps [centre, width]. `out`
## is which way its `outside` face looks (+1 toward +Z).
func _wall_x(z: float, x0: float, x1: float, gaps: Array, outside: Material, inside: Material, out: float) -> void:
	for seg: Vector2 in _segments(x0, x1, gaps):
		var mid := (seg.x + seg.y) / 2.0
		_solid(Vector3(seg.y - seg.x, WALL_H, T), Vector3(mid, WALL_H / 2, z), inside)
		_box(Vector3(seg.y - seg.x, WALL_H, 0.005), Vector3(mid, WALL_H / 2, z + out * (T / 2 + 0.003)), outside)
	for g: Array in gaps:                                  # over each door
		_box(Vector3(g[1], WALL_H - 2.1, T), Vector3(g[0], 2.1 + (WALL_H - 2.1) / 2, z), inside)


func _wall_z(x: float, z0: float, z1: float, gaps: Array, outside: Material, inside: Material, out: float) -> void:
	for seg: Vector2 in _segments(z0, z1, gaps):
		var mid := (seg.x + seg.y) / 2.0
		_solid(Vector3(T, WALL_H, seg.y - seg.x), Vector3(x, WALL_H / 2, mid), inside)
		_box(Vector3(0.005, WALL_H, seg.y - seg.x), Vector3(x + out * (T / 2 + 0.003), WALL_H / 2, mid), outside)
	for g: Array in gaps:
		_box(Vector3(T, WALL_H - 2.1, g[1]), Vector3(x, 2.1 + (WALL_H - 2.1) / 2, g[0]), inside)


## The stretches of wall between the gaps.
static func _segments(a: float, b: float, gaps: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := a
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for g: Array in sorted:
		out.append(Vector2(at, g[0] - g[1] / 2.0))
		at = g[0] + g[1] / 2.0
	out.append(Vector2(at, b))
	return out


## A piece of furniture from the interior models, against a wall, facing out of it.
func _place(name: String, at: Vector3, facing: Vector3) -> void:
	var n := _lib.get_node(name).duplicate() as Node3D
	n.basis = Basis.looking_at(-facing, Vector3.UP)
	n.position = at
	add_child(n)
	var size: Vector3 = HouseInterior.FURNITURE.get(name, Vector3.ZERO)
	if size != Vector3.ZERO:                               # something to bump into
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = Vector3(0, size.y / 2, size.z / 2)
		body.add_child(cs)
		n.add_child(body)


func _box(size: Vector3, at: Vector3, mat: Material, solid := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _solid(size: Vector3, at: Vector3, mat: Material) -> void:
	_box(size, at, mat, true)


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
