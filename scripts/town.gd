class_name Town
extends Node3D
## A small town, generated in code: a grid of streets, houses with yards and
## driveways, wooden power poles with lines running to every house, and a
## downtown block with the shop. Every house gets a street address, kept in
## `houses` for the service calls.

const BLOCKS := 4              # blocks along each side
const BLOCK := 44.0            # a block, sidewalk included
const ROAD := 10.0             # two lanes
const PITCH := BLOCK + ROAD
const WALK := 2.5              # sidewalk width
const SIZE := BLOCKS * PITCH + ROAD
const DOWNTOWN := Vector2i(1, 1)
## The owner's ranch plan (see HouseInterior): 40 x 30 ft, plus a 6 ft covered
## porch across the front. Doors and windows where the plan draws them, in
## house-local metres (x across the front, +z toward the street).
const HOUSE_PLAN_WIDTH := 12.192    # 40 feet
const HOUSE_PLAN_DEPTH := 9.144     # 30 feet, porch not included
const PLAN_PORCH_DEPTH := 1.83      # 6 feet
## The roof: a gable, ridge running side to side. HouseInterior frames the
## attic to fit under exactly this, so change them here and both follow.
const ROOF_RISE := 1.8          # ridge above the top of the walls
const ROOF_OVERHANG := 0.45     # eaves past the front and back walls
const ROOF_EAVE_DROP := 0.15    # the underside at the eave, below the top of the walls
const ROOF_SIDE_OVERHANG := 0.4
const PLAN_FRONT_DOOR_X := -0.05    # into the family room
const PLAN_BACK_DOOR_X := -1.7      # out of the kitchen, past the end of the counter
const PLAN_FRONT_WINDOWS := [-3.9, 3.7]        # family room, bedroom 2
const PLAN_BACK_WINDOWS := [-3.7, 2.75, 5.1]   # over the kitchen sink, two in the master

const STREETS := ["Cedar St", "Maple St", "Birch St", "Alder St", "Spruce St"]   # east-west, north to south
const AVENUES := ["1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave"]          # north-south, west to east
const PAINT := [Color(0.82, 0.76, 0.62), Color(0.55, 0.66, 0.72), Color(0.86, 0.86, 0.82), Color(0.62, 0.7, 0.55),
		Color(0.78, 0.55, 0.45), Color(0.9, 0.82, 0.55), Color(0.5, 0.52, 0.58), Color(0.72, 0.62, 0.7)]

## [{"address": "214 Maple St", "door": Vector3, "front": Vector3 (points at the street),
##   "meter": Vector3, "size": Vector3, "two_story": bool}]
var houses: Array = []
var shop_spot := Transform3D()   # the shop's parking bays (the shop's for sale: you don't own it yet)
var shop_door := Vector3.ZERO    # in front of the shop
## Where you start out: a run-down house of your own, never a job site. One of
## `houses`, marked "home"; the truck parks in its driveway.
var home: Dictionary = {}
var home_spot := Transform3D()   # the truck, in your driveway
## Your house itself, with the computer and the bed.
var home_house: HomeHouse
## The street lamps' glass: day/night turns them up after dark.
var street_lamps: StandardMaterial3D
var home_start := Vector3.ZERO   # you, by the truck
var supply_door := Vector3.ZERO  # in front of the electrical supply house
## The supply house you walk into, with the parts guy at the counter.
var supply_house: SupplyHouse

## Material keys that use a photographed texture: prefix -> [texture, metres per tile].
const PHOTO := {"grass": ["leafy_grass", 2.5], "asphalt": ["asphalt_02", 3.5], "concrete": ["concrete_pavement", 3.0],
		"foundation": ["brushed_concrete", 2.0], "bark": ["bark_brown_02", 1.5], "paint": ["white_planks_clean", 2.0],
		"roof": ["grey_roof_tiles", 3.0], "store_": ["brick_wall_02", 2.5]}
const LEAF_VARIANTS := 4
const ARM := Vector3(0, PowerPole.HEIGHT / 2 - 0.2, 0)   # where the lines meet a pole, from its middle
const WIRE_ON_GROUND := 0.03
const METER_HEIGHT := 1.5        # middle of the meter base, off the ground
const PANEL_HEIGHT := 1.35

var _rng := RandomNumberGenerator.new()
var _mats := {}
var _wires: Array = []           # {a, b, sag} lines still strung up, all one mesh. a and b are [pole, local point], or [null, world point]
var _loose: Array = []           # the lines attached to a pole that's come down
var _falling: Array = []         # poles still moving, so their lines have to follow
var _standing_wires: MeshInstance3D
var _loose_wires: MeshInstance3D
var _shared := {}                # mesh cache


func _ready() -> void:
	_rng.seed = 1977
	_ground()
	_roads()
	for bx in BLOCKS:
		for bz in BLOCKS:
			var origin := Vector3(ROAD + bx * PITCH, 0, ROAD + bz * PITCH)
			_sidewalk(origin)
			if Vector2i(bx, bz) == DOWNTOWN:
				_downtown(origin)
			else:
				_houses(origin, bx, bz)
	_make_home()
	_poles()
	_street_lights()
	_outskirts()
	_build_wires()


func _process(_delta: float) -> void:
	if _falling.is_empty():
		return
	_draw_wires(_loose_wires, _loose)
	_falling = _falling.filter(func(p: PowerPole) -> bool: return not p.sleeping)


# --- Ground and streets -----------------------------------------------------------

func _ground() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	add_child(body)
	var grass := _mat("grass", Color(0.3, 0.42, 0.18), 0.95, 0.35)
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	_mesh(plane, Vector3(SIZE / 2, 0, SIZE / 2), grass)


func _roads() -> void:
	var asphalt := _mat("asphalt", Color(0.16, 0.16, 0.17), 0.85, 0.5)
	var yellow := _mat("yellow", Color(0.85, 0.68, 0.12), 0.6, 0.0)
	for k in BLOCKS + 1:
		var c := k * PITCH + ROAD / 2
		_box(Vector3(SIZE, 0.02, ROAD), Vector3(SIZE / 2, 0.01, c), asphalt)   # east-west
		_box(Vector3(ROAD, 0.02, SIZE), Vector3(c, 0.01, SIZE / 2), asphalt)   # north-south
		# Dashed centre lines, not across intersections.
		for b in BLOCKS:
			var start := b * PITCH + ROAD
			var d := start + 2.0
			while d < start + BLOCK - 2.0:
				_box(Vector3(2.0, 0.01, 0.15), Vector3(d + 1.0, 0.025, c), yellow)
				_box(Vector3(0.15, 0.01, 2.0), Vector3(c, 0.025, d + 1.0), yellow)
				d += 5.0


func _sidewalk(o: Vector3) -> void:
	var concrete := _mat("concrete", Color(0.62, 0.61, 0.58), 0.9, 0.25)
	var h := BLOCK / 2
	for side in [[Vector3(BLOCK, 0.04, WALK), Vector3(h, 0.02, WALK / 2)], [Vector3(BLOCK, 0.04, WALK), Vector3(h, 0.02, BLOCK - WALK / 2)],
			[Vector3(WALK, 0.04, BLOCK), Vector3(WALK / 2, 0.02, h)], [Vector3(WALK, 0.04, BLOCK), Vector3(BLOCK - WALK / 2, 0.02, h)]]:
		_box(side[0], o + side[1], concrete)


## Four houses per block, two facing the street to the north, two the south.
func _houses(o: Vector3, bx: int, bz: int) -> void:
	for i in 2:
		for j in 2:
			var lot := o + Vector3(WALK + i * (BLOCK - WALK * 2) / 2, 0, WALK + j * (BLOCK - WALK * 2) / 2)
			var lot_size := (BLOCK - WALK * 2) / 2
			var center := lot + Vector3(lot_size / 2, 0, lot_size / 2)
			var front := Vector3.FORWARD if j == 0 else Vector3.BACK   # toward the street
			var street: String = STREETS[bz] if j == 0 else STREETS[bz + 1]
			var number := (bx + 1) * 100 + i * 20 + (1 if j == 0 else 2) + bz * 4
			_house(center, front, "%d %s" % [number, street])


func _house(center: Vector3, front: Vector3, address: String) -> void:
	# Keep consuming the old layout rolls so unrelated town details retain their
	# seeded variety. Every service house now uses the owner's one-story plan.
	_rng.randf()
	_rng.randf_range(9.0, 11.5)
	_rng.randf_range(7.5, 9.0)
	var two := false
	var w := HOUSE_PLAN_WIDTH
	var d := HOUSE_PLAN_DEPTH
	var h := 5.6 if two else 3.0
	var root := Node3D.new()
	root.position = center - front * 0.7   # room for the full-width front porch
	root.rotation.y = atan2(front.x, front.z)   # local +Z faces the street
	add_child(root)
	var paint := _mat("paint%d" % houses.size(), PAINT[_rng.randi() % PAINT.size()], 0.85)
	var trim := _mat("trim", Color(0.93, 0.92, 0.9), 0.6)
	var roof := _mat("roof%d" % (_rng.randi() % 3), [Color(0.22, 0.2, 0.2), Color(0.3, 0.18, 0.14), Color(0.25, 0.3, 0.32)][_rng.randi() % 3], 0.8)
	var glass := _mat("glass", Color(0.12, 0.16, 0.2), 0.04)
	glass.metallic = 0.9
	var door_c := _mat("door%d" % (_rng.randi() % 3), [Color(0.45, 0.1, 0.08), Color(0.12, 0.2, 0.35), Color(0.25, 0.18, 0.1)][_rng.randi() % 3], 0.5)

	var shell := _part(root, "box", Vector3(w, h, d), Vector3(0, h / 2, 0), paint)
	_part(root, "box", Vector3(w + 0.1, 0.35, d + 0.1), Vector3(0, 0.17, 0), _mat("foundation", Color(0.5, 0.49, 0.47), 0.9))
	var r := _roof_mesh(w + ROOF_SIDE_OVERHANG * 2, d + ROOF_OVERHANG * 2, ROOF_RISE if not two else 1.5)
	var rm := MeshInstance3D.new()
	rm.mesh = r
	rm.material_override = roof
	rm.position.y = h
	root.add_child(rm)
	# Gable ends match the walls
	var gable := _gable_mesh(w, d, ROOF_RISE if not two else 1.5)
	var gm := MeshInstance3D.new()
	gm.mesh = gable
	gm.material_override = paint
	gm.position.y = h
	root.add_child(gm)
	# Front door, porch, windows
	var fz := d / 2
	_rng.randf_range(-w / 4, w / 4)        # preserve the old seeded roll
	var door_x := PLAN_FRONT_DOOR_X
	var door := _part(root, "box", Vector3(1.0, 2.1, 0.08), Vector3(door_x, 1.05 + 0.35, fz + 0.02), door_c)
	var door_trim := _part(root, "box", Vector3(1.25, 2.3, 0.05), Vector3(door_x, 1.15 + 0.3, fz + 0.005), trim)
	var ground_floor_windows: Array = []   # [{x, back, parts}], so a house can be opened up later
	_part(root, "box", Vector3(w + 0.6, 0.25, PLAN_PORCH_DEPTH), Vector3(0, 0.125, fz + PLAN_PORCH_DEPTH / 2),
			_mat("concrete", Color(0.62, 0.61, 0.58), 0.9))
	var back_door := _part(root, "box", Vector3(1.0, 2.1, 0.08), Vector3(PLAN_BACK_DOOR_X, 1.05 + 0.35, -fz - 0.02), door_c)
	for x: float in PLAN_FRONT_WINDOWS:
		ground_floor_windows.append({"x": x, "back": false, "parts": _window(root, Vector3(x, 1.6, fz), glass, trim)})
	for x: float in PLAN_BACK_WINDOWS:
		ground_floor_windows.append({"x": x, "back": true, "parts": _window(root, Vector3(x, 1.6, -d / 2), glass, trim, true)})
	# Driveway to the street, on the side away from the door
	var drive_x := w / 2 + 1.8 if door_x < 0 else -w / 2 - 1.8
	var road_edge := (BLOCK - WALK * 2) / 4 - 1.0 + WALK   # local z of the kerb
	_part(root, "box", Vector3(3.2, 0.04, road_edge - fz + 3.0), Vector3(drive_x, 0.02, (road_edge + fz - 3.0) / 2),
			_mat("concrete", Color(0.62, 0.61, 0.58), 0.9))
	# Electric meter on the driveway side of the house, where the service drop lands
	var mx := w / 2 + 0.06 if drive_x > 0 else -w / 2 - 0.06
	var meter_box := _meter_base(root, Vector3(signf(mx) * w / 2, METER_HEIGHT, fz - 1.5), signf(mx) * PI / 2)
	var panel_at := Vector3(signf(mx) * w / 2, PANEL_HEIGHT, fz - 0.55)
	var static_panel := _closed_panel(root, panel_at, signf(mx) * PI / 2, Vector3(signf(mx) * w / 2, METER_HEIGHT, fz - 1.5))
	var mast_foot := METER_HEIGHT + 0.22   # just inside the meter base's hub
	_part(root, "cyl", Vector3(0.03, h + 0.3 - mast_foot, 0.03), Vector3(mx, mast_foot + (h + 0.3 - mast_foot) / 2, fz - 1.5), _mat("meter", Color(0.6, 0.62, 0.62), 0.4))
	# Address number by the door
	var label := Label3D.new()
	label.text = address.split(" ")[0]
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.1, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(door_x + 1.0, 2.3, fz + 0.03)
	root.add_child(label)
	# A tree or two in the back yard, clear of the house and the lot behind.
	for t in _rng.randi_range(1, 2):
		var tp := Vector3(_rng.randf_range(-8, 8), 0, -d / 2 - _rng.randf_range(2.0, 3.6))
		_leafy_tree(root.to_global(tp))
	# Collision
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h + 1.0, d)
	cs.shape = bs
	cs.position.y = (h + 1.0) / 2
	body.add_child(cs)
	root.add_child(body)

	var xf := root.global_transform
	# The panel hangs on the same wall as the meter, facing out of it.
	var wall_side := signf(mx)
	var out := xf.basis * Vector3(wall_side, 0, 0)
	meter_box.address = address
	meter_box.street = xf * Vector3(drive_x, 0, fz + 4.0)
	houses.append({"address": address, "door": xf * Vector3(door_x, 0, fz + 1.8), "front": front, "meter_box": meter_box,
			"panel": xf * panel_at, "panel_basis": Basis(Vector3.UP, atan2(out.x, out.z)),
			"meter": xf * Vector3(mx, 1.5, fz - 1.5), "drop": xf * Vector3(mx, h + 0.3, fz - 1.5),
			"driveway": xf * Vector3(drive_x, 0, fz + 4.0), "size": Vector3(w, h, d), "two_story": two,
			# For opening the house up when a job's inside it: see HouseInterior.
			"root": root, "shell": shell, "roof": rm, "gable": gm, "body": body, "door_mesh": door, "door_trim": door_trim, "door_x": door_x,
			"back_door_mesh": back_door, "back_door_x": PLAN_BACK_DOOR_X,
			"windows": ground_floor_windows, "static_panel": static_panel, "paint": paint, "trim": trim, "meter_side": signf(mx)})


## The house's panel, shut, with its conduit from the meter. Just the box and
## the door: the working panel with everything inside replaces it during a job.
func _closed_panel(root: Node3D, p: Vector3, yaw: float, meter_at: Vector3) -> Node3D:
	var panel: Node3D = (load("res://assets/panel/panel.glb") as PackedScene).instantiate()
	panel.position = p
	panel.rotation.y = yaw
	root.add_child(panel)
	for c in panel.get_children():
		if c.name != "Enclosure" and c.name != "Door":
			c.free()
	# Along the wall from the meter, up the side of the panel, into the hub on top.
	var m := panel.to_local(root.to_global(meter_at))
	var side := -1.0 if m.x < 0.0 else 1.0
	var past := side * 0.29
	var hub := Vector3(-0.02, 0.46, 0.05)
	var corners := [Vector3(m.x - side * 0.14, m.y - 0.1, 0.045), Vector3(past, m.y - 0.1, 0.045), Vector3(past, hub.y + 0.07, 0.045),
			Vector3(hub.x, hub.y + 0.07, 0.05), hub]
	var pipe := MeshInstance3D.new()
	pipe.mesh = BoxView._tube(_bent(corners, 0.06), 0.018, 12)
	pipe.material_override = _mat("conduit", Color(0.6, 0.62, 0.63), 0.38)
	(pipe.material_override as StandardMaterial3D).metallic = 0.8
	panel.add_child(pipe)
	for mesh: GeometryInstance3D in panel.find_children("*", "GeometryInstance3D", true, false):
		mesh.visibility_range_end = 70.0
	return panel


static func _bent(corners: Array, bend: float) -> Array[Vector3]:
	var out: Array[Vector3] = [corners[0]]
	for i in range(1, corners.size() - 1):
		var a: Vector3 = corners[i - 1]
		var p: Vector3 = corners[i]
		var b: Vector3 = corners[i + 1]
		var r := minf(bend, minf(a.distance_to(p), p.distance_to(b)) * 0.45)
		var s0 := p + (a - p).normalized() * r
		var s1 := p + (b - p).normalized() * r
		for k in 9:
			var t := k / 8.0
			out.append(s0.lerp(p, t).lerp(p.lerp(s1, t), t))
	out.append(corners[-1])
	return out


## The meter base you can take apart, flat against the wall at p.
func _meter_base(root: Node3D, p: Vector3, yaw: float) -> MeterBase:
	var meter := MeterBase.new()
	meter.ground = -METER_HEIGHT
	meter.position = p
	meter.rotation.y = yaw
	root.add_child(meter)
	return meter


func _window(root: Node3D, p: Vector3, glass: Material, trim: Material, back := false) -> Array:
	var s := -1.0 if back else 1.0
	return [_part(root, "box", Vector3(1.4, 1.3, 0.06), p + Vector3(0, 0, 0.02 * s), trim),
			_part(root, "box", Vector3(1.2, 1.1, 0.06), p + Vector3(0, 0, 0.04 * s), glass),
			_part(root, "box", Vector3(0.05, 1.1, 0.07), p + Vector3(0, 0, 0.05 * s), trim)]


# --- Downtown -----------------------------------------------------------------

func _downtown(o: Vector3) -> void:
	var lot := _mat("asphalt", Color(0.16, 0.16, 0.17), 0.85)
	_box(Vector3(BLOCK - WALK * 2, 0.03, BLOCK - WALK * 2), o + Vector3(BLOCK / 2, 0.015, BLOCK / 2), lot)
	# The shop: north-west corner, facing north
	# The shop: north-west corner, facing north. Empty and for sale: a place to work toward.
	var shop := _storefront(o + Vector3(13, 0, 12), Vector3(18, 5.5, 12), Color(0.85, 0.83, 0.78), "", Color(1.0, 0.55, 0.05))
	_for_sale_sign(o + Vector3(6.0, 0, 4.2))
	# Van parking bays in front of the garage door side (east of the shop)
	var white := _mat("paint_white", Color(0.9, 0.9, 0.88), 0.6)
	for k in 3:
		_box(Vector3(0.12, 0.01, 5.0), o + Vector3(25 + k * 3.4, 0.035, 9.0), white)
	shop_spot = Transform3D(Basis(), o + Vector3(26.7, 0.6, 9.0))
	shop_door = o + Vector3(13, 0, 4.6)
	supply_door = o + Vector3(26, 0, 39.2)
	# Other stores along the south side, facing south
	_storefront(o + Vector3(10, 0, 33), Vector3(14, 4.5, 10), Color(0.6, 0.38, 0.3), "DINER", Color(0.9, 0.15, 0.1), true)
	supply_house = SupplyHouse.new()     # a store you walk into, not a closed box
	supply_house.position = o + Vector3(26, 0, 33)
	add_child(supply_house)
	_storefront(o + Vector3(37.5, 0, 31), Vector3(7, 7.5, 14), Color(0.45, 0.48, 0.52), "BANK", Color(0.9, 0.9, 0.9), true)
	houses.append({"address": "101 Birch St (Diner)", "door": o + Vector3(10, 0, 40), "front": Vector3.BACK,
			"meter": o + Vector3(17.1, 1.5, 35), "drop": o + Vector3(17.1, 4.8, 35), "driveway": o + Vector3(10, 0, 42),
			"size": Vector3(14, 4.5, 10), "two_story": false, "business": true})
	houses.append({"address": "113 Birch St (Electric Supply)", "door": o + Vector3(26, 0, 40), "front": Vector3.BACK,
			"meter": o + Vector3(32.1, 1.5, 35), "drop": o + Vector3(32.1, 4.3, 35), "driveway": o + Vector3(26, 0, 42),
			"size": Vector3(12, 4.0, 10), "business": true, "two_story": false})


## A real estate sign on two posts, facing the street to the north.
func _for_sale_sign(at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = PI                  # face north, to the street
	add_child(root)
	var post := _mat("sign_post", Color(0.3, 0.22, 0.14), 0.8)
	for x in [-0.75, 0.75]:
		_part(root, "box", Vector3(0.09, 2.2, 0.09), Vector3(x, 1.1, 0), post)
	_part(root, "box", Vector3(1.9, 1.15, 0.05), Vector3(0, 1.55, 0.06), _mat("sign_red", Color(0.72, 0.08, 0.06), 0.6))
	_part(root, "box", Vector3(1.75, 1.0, 0.06), Vector3(0, 1.55, 0.065), _mat("sign_white", Color(0.95, 0.95, 0.93), 0.6))
	var words := Label3D.new()
	words.text = "FOR SALE\nCOMMERCIAL BUILDING\nShop, office & garage\nCALL 555-0142"
	words.font_size = 52
	words.pixel_size = 0.0045
	words.modulate = Color(0.7, 0.06, 0.05)
	words.outline_size = 0
	words.position = Vector3(0, 1.55, 0.1)
	root.add_child(words)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 2.2, 0.2)
	cs.shape = bs
	cs.position.y = 1.1
	body.add_child(cs)
	root.add_child(body)


# --- Home -------------------------------------------------------------------------------

## Your house: the home nearest downtown. Faded paint, plywood over a broken
## window, a blue tarp on the roof, junk on the porch. It's a start.
func _make_home() -> void:
	var best: Dictionary = {}
	var downtown := Vector3(ROAD + DOWNTOWN.x * PITCH + BLOCK / 2, 0, ROAD + DOWNTOWN.y * PITCH + BLOCK / 2)
	for h: Dictionary in houses:
		if not h.get("business", false) and (best.is_empty() or (h["door"] as Vector3).distance_to(downtown) < (best["door"] as Vector3).distance_to(downtown)):
			best = h
	home = best
	home["home"] = true
	# Clear the lot and put up your own little house instead (HomeHouse): the
	# standard house that was here is for customers.
	var root: Node3D = home["root"]
	for c in root.get_children():
		c.free()
	for key in ["shell", "roof", "gable", "body", "door_mesh", "door_trim", "back_door_mesh", "windows", "static_panel", "panel", "panel_basis"]:
		home.erase(key)
	home_house = HomeHouse.new()
	root.add_child(home_house)
	home_house.build(self)
	var w := HomeHouse.W
	var d := HomeHouse.D
	var fz := d / 2
	var xf: Transform3D = root.global_transform
	# The driveway on the right, the meter on that side where the service drop comes in.
	var drive_x := w / 2 + 1.8
	var road_edge := (BLOCK - WALK * 2) / 4 - 1.0 + WALK
	_part(root, "box", Vector3(3.2, 0.04, road_edge - fz + 3.0), Vector3(drive_x, 0.02, (road_edge + fz - 3.0) / 2),
			_mat("concrete", Color(0.62, 0.61, 0.58), 0.9))
	var mz := fz - 1.5
	var meter_box := _meter_base(root, Vector3(w / 2, METER_HEIGHT, mz), PI / 2)
	meter_box.address = home["address"]
	meter_box.street = xf * Vector3(drive_x, 0, fz + 4.0)
	var top := HomeHouse.WALL_H + 0.35
	var mast_foot := METER_HEIGHT + 0.22
	_part(root, "cyl", Vector3(0.03, top - mast_foot, 0.03), Vector3(w / 2 + 0.06, mast_foot + (top - mast_foot) / 2, mz), _mat("meter", Color(0.6, 0.62, 0.62), 0.4))
	var label := Label3D.new()
	label.text = String(home["address"]).split(" ")[0]
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.1, 0.1, 0.1)
	label.outline_size = 0
	label.position = Vector3(HomeHouse.DOOR_X + 0.9, 2.3, fz + HomeHouse.T / 2 + 0.01)
	root.add_child(label)
	home["meter_box"] = meter_box
	home["meter"] = xf * Vector3(w / 2 + 0.06, 1.5, mz)
	home["drop"] = xf * Vector3(w / 2 + 0.06, top, mz)
	home["door"] = xf * Vector3(HomeHouse.DOOR_X, 0, fz + 1.2)
	home["driveway"] = xf * Vector3(drive_x, 0, fz + 4.0)
	home["size"] = Vector3(w, HomeHouse.WALL_H, d)
	home["paint"] = home_house.paint
	# The truck in the driveway, nose to the house, and you beside it.
	home_spot = Transform3D(xf.basis, xf * Vector3(drive_x, 0.6, fz + 2.2))
	home_start = xf * Vector3(drive_x - 2.4, 0, fz + 3.2)


func _storefront(c: Vector3, size: Vector3, color: Color, sign_text: String, sign_color: Color, south := false) -> Node3D:
	var root := Node3D.new()
	root.position = c
	root.rotation.y = 0.0 if south else PI   # local +Z faces the street
	add_child(root)
	var wall := _mat("store_%s" % sign_text, color, 0.85)
	var glass := _mat("glass", Color(0.12, 0.16, 0.2), 0.08)
	var trim := _mat("trim", Color(0.93, 0.92, 0.9), 0.6)
	_part(root, "box", size, Vector3(0, size.y / 2, 0), wall)
	_part(root, "box", Vector3(size.x + 0.3, 0.5, size.z + 0.3), Vector3(0, size.y + 0.25, 0), trim)   # parapet
	_part(root, "box", Vector3(size.x * 0.7, 2.4, 0.08), Vector3(-size.x * 0.1, 1.5, size.z / 2 + 0.02), glass)
	_part(root, "box", Vector3(1.1, 2.2, 0.1), Vector3(size.x * 0.35, 1.1, size.z / 2 + 0.03), glass)
	# Awning
	var awn := _mat("awning_%s" % sign_text, sign_color.darkened(0.2), 0.7)
	var a := _part(root, "box", Vector3(size.x * 0.9, 0.08, 1.6), Vector3(0, 2.85, size.z / 2 + 0.75), awn)
	a.rotation.x = 0.25
	var sign := Label3D.new()
	sign.text = sign_text
	sign.font_size = 140
	sign.pixel_size = 0.006
	sign.modulate = sign_color
	sign.outline_size = 18
	sign.outline_modulate = Color(0.05, 0.05, 0.05)
	sign.position = Vector3(0, maxf(size.y - 0.75, 3.55), size.z / 2 + 0.06)
	root.add_child(sign)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y / 2
	body.add_child(cs)
	root.add_child(body)
	return root


# --- Power poles and street lights ------------------------------------------------

## A line of poles down the north side of every east-west street. Each house
## gets a service drop from the nearest pole to the mast above its meter.
func _poles() -> void:
	var poles: Array[PowerPole] = []
	for k in BLOCKS + 1:
		var z := k * PITCH + ROAD + 0.6   # just inside the sidewalk, south side of the road
		if k == BLOCKS:
			z = k * PITCH - 0.6
		var prev: PowerPole = null
		var x := 4.0
		while x < SIZE - 2.0:
			var near_road := fmod(x, PITCH) < ROAD + 1.0   # don't plant one in an intersection
			if not near_road:
				var pole := _pole(Vector3(x, 0, z))
				poles.append(pole)
				if prev != null:
					for off in [-0.9, 0.0, 0.9]:
						var arm := ARM + Vector3(off, 0, 0)
						_wires.append({"a": [prev, arm], "b": [pole, arm], "sag": 0.5})
				prev = pole
			x += 27.0 if not near_road else 3.0
	for h in houses:
		var drop: Vector3 = h["drop"]
		var best := poles[0]
		for p in poles:
			if p.to_global(ARM).distance_to(drop) < best.to_global(ARM).distance_to(drop):
				best = p
		_wires.append({"a": [best, ARM + Vector3(0, -0.5, 0)], "b": [null, drop], "sag": 0.35})


func _pole(base: Vector3) -> PowerPole:
	var pole := PowerPole.new()
	pole.position = base + Vector3(0, PowerPole.HEIGHT / 2, 0)
	add_child(pole)
	pole.knocked_down.connect(_on_pole_down.bind(pole))
	var wood := _mat("pole", Color(0.32, 0.24, 0.17), 0.95)
	var top := PowerPole.HEIGHT / 2
	_mesh(_cyl_mesh("pole", 0.13, PowerPole.RADIUS, PowerPole.HEIGHT), Vector3.ZERO, wood, pole)
	_box(Vector3(2.4, 0.12, 0.12), Vector3(0, top - 0.4, 0), wood, pole)
	for off in [-0.9, 0.0, 0.9]:
		_box(Vector3(0.06, 0.14, 0.06), Vector3(off, top - 0.27, 0), _mat("insulator", Color(0.3, 0.45, 0.35), 0.3), pole)
	# Transformer can on every other pole
	if _rng.randf() < 0.5:
		_mesh(_cyl_mesh("transformer", 0.32, 0.32, 1.0), Vector3(0, top - 1.8, 0.4), _mat("transformer", Color(0.55, 0.58, 0.58), 0.5), pole)
	return pole


func _on_pole_down(pole: PowerPole) -> void:
	var still_up: Array = []
	for w in _wires:
		if w["a"][0] == pole or w["b"][0] == pole:
			_loose.append(w)
		else:
			still_up.append(w)
	_wires = still_up
	_draw_wires(_standing_wires, _wires)
	_falling.append(pole)


func _street_lights() -> void:
	var metal := _mat("lamp_pole", Color(0.25, 0.27, 0.28), 0.5)
	var lamp := _mat("lamp", Color(1.0, 0.9, 0.7), 0.3)
	street_lamps = lamp
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.6)
	lamp.emission_energy_multiplier = 0.4
	for i in BLOCKS + 1:
		for j in BLOCKS + 1:
			var corner := Vector3(i * PITCH + ROAD + 0.8, 0, j * PITCH - 0.8)
			if j == 0 or i == BLOCKS:
				continue
			_box(Vector3(0.14, 6.5, 0.14), corner + Vector3(0, 3.25, 0), metal)
			_box(Vector3(0.1, 0.1, 1.8), corner + Vector3(0, 6.45, 0.9), metal)
			_box(Vector3(0.4, 0.15, 0.6), corner + Vector3(0, 6.35, 1.8), lamp)
			# Street name sign
			var s := Label3D.new()
			s.text = "%s\n%s" % [AVENUES[i], STREETS[j]]
			s.font_size = 48
			s.pixel_size = 0.005
			s.modulate = Color(0.95, 0.95, 0.95)
			s.outline_size = 0
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.position = corner + Vector3(0, 2.8, 0)
			add_child(s)


## Forest all round the edge of town.
func _outskirts() -> void:
	var n := 0
	while n < 260:
		var p := Vector3(_rng.randf_range(-70, SIZE + 70), 0, _rng.randf_range(-70, SIZE + 70))
		if p.x > -6 and p.x < SIZE + 6 and p.z > -6 and p.z < SIZE + 6:
			continue
		_tree(p, _rng.randf_range(1.0, 1.8))
		n += 1


func _tree(p: Vector3, s := 1.0) -> void:
	var bark := _mat("bark", Color(0.3, 0.22, 0.15), 0.95)
	var leaves := _mat("leaves", Color(0.16, 0.3, 0.14), 0.9)
	s *= _rng.randf_range(0.8, 1.2)
	var trunk := _mesh(_cyl_mesh("trunk", 0.15, 0.22, 2.0), p + Vector3(0, s, 0), bark)
	trunk.scale = Vector3(s, s, s)
	for k in 3:
		var cone := _mesh(_cyl_mesh("cone", 0.0, 1.8, 3.0), p + Vector3(0, (2.4 + k * 1.5) * s, 0), leaves)
		var cs := s * (1.0 - k * 0.22)
		cone.scale = Vector3(cs, s, cs)


## A broadleaf tree: a trunk, a dark core, and a couple of hundred cards of
## leaves facing outward. The cards are shared between trees so a town of them is cheap.
func _leafy_tree(p: Vector3) -> void:
	var s := _rng.randf_range(0.9, 1.4)
	var trunk := _mesh(_cyl_mesh("trunk", 0.15, 0.22, 2.0), p + Vector3(0, s * 1.3, 0), _mat("bark", Color(0.3, 0.22, 0.15), 0.95))
	trunk.scale = Vector3(s, s * 1.3, s)
	if not _shared.has("blob"):
		var blob := SphereMesh.new()
		blob.radial_segments = 10
		blob.rings = 6
		_shared["blob"] = blob
	var core := _mesh(_shared["blob"], p + Vector3(0, 4.2 * s, 0), _mat("leaf_core", Color(0.06, 0.1, 0.04), 1.0))
	core.scale = Vector3(4.0, 3.4, 4.0) * s
	var cards := MultiMeshInstance3D.new()
	cards.multimesh = _leaf_cards(_rng.randi() % LEAF_VARIANTS)
	cards.position = p + Vector3(0, 4.2 * s, 0)
	cards.scale = Vector3.ONE * s
	add_child(cards)


func _leaf_cards(variant: int) -> MultiMesh:
	var key := "leaf_cards%d" % variant
	if _shared.has(key):
		return _shared[key]
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	quad.material = _leaf_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 240
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + variant
	for i in mm.instance_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
		var at := dir * rng.randf_range(1.6, 2.7) * Vector3(1.0, 0.85, 1.0)
		var out := (dir + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
		var roll := Basis(out, rng.randf_range(0.0, TAU))
		var up := Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT
		mm.set_instance_transform(i, Transform3D(roll * Basis.looking_at(-out, up), at))
		var light := lerpf(0.55, 1.15, clampf(dir.y * 0.5 + 0.5, 0.0, 1.0)) * rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(0.42, 0.6, 0.2) * light)
	_shared[key] = mm
	return mm


func _leaf_material() -> StandardMaterial3D:
	if _shared.has("leaf_mat"):
		return _shared["leaf_mat"]
	const SIZE := 256
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for n in 70:                         # scatter of overlapping leaves
		var c := Vector2(rng.randf_range(24, SIZE - 24), rng.randf_range(24, SIZE - 24))
		var a := rng.randf_range(0.0, TAU)
		var shade := rng.randf_range(0.65, 1.0)
		for y in range(int(c.y) - 24, int(c.y) + 24):
			for x in range(int(c.x) - 24, int(c.x) + 24):
				var d := (Vector2(x, y) - c).rotated(-a)
				var inside := (d.x / 22.0) ** 2 + (d.y / 9.0) ** 2
				if inside < 1.0 and x >= 0 and y >= 0 and x < SIZE and y < SIZE:
					var vein := 0.82 if absf(d.y) < 1.0 else 1.0
					var v := shade * vein * lerpf(1.0, 0.75, inside)
					img.set_pixel(x, y, Color(v, v, v, 1.0))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.75
	m.backlight_enabled = true
	m.backlight = Color(0.3, 0.42, 0.14)
	_shared["leaf_mat"] = m
	return m


# --- Power lines ------------------------------------------------------------------

func _build_wires() -> void:
	var m := _mat("wire", Color(0.05, 0.05, 0.05), 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_standing_wires = MeshInstance3D.new()
	_standing_wires.material_override = m
	add_child(_standing_wires)
	_loose_wires = MeshInstance3D.new()
	_loose_wires.material_override = m
	add_child(_loose_wires)
	_draw_wires(_standing_wires, _wires)


func _draw_wires(target: MeshInstance3D, wires: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for w in wires:
		var a := _wire_end(w["a"])
		var b := _wire_end(w["b"])
		# The further a pole has come down, the more slack its lines have.
		var sag: float = w["sag"] + maxf(_end_drop(w["a"]), _end_drop(w["b"])) * 0.8
		var pts: Array[Vector3] = []
		for i in 9:
			var t := i / 8.0
			var p := a.lerp(b, t) + Vector3.DOWN * sin(t * PI) * sag
			p.y = maxf(p.y, WIRE_ON_GROUND)
			pts.append(p)
		for i in 8:
			_tube(st, pts[i], pts[i + 1], 0.022)
	target.mesh = st.commit()


func _wire_end(end: Array) -> Vector3:
	return end[0].to_global(end[1]) if end[0] != null else end[1]


## How far below its usual height a pole has brought this end of a line.
func _end_drop(end: Array) -> float:
	return maxf(ARM.y + PowerPole.HEIGHT / 2 - _wire_end(end).y, 0.0) if end[0] != null else 0.0


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir)
	for k in 4:
		var a0 := TAU * k / 4
		var a1 := TAU * (k + 1) / 4
		var o0 := (side * cos(a0) + up * sin(a0)) * r
		var o1 := (side * cos(a1) + up * sin(a1)) * r
		for v in [[a + o0, o0], [b + o0, o0], [b + o1, o1], [a + o0, o0], [b + o1, o1], [a + o1, o1]]:
			st.set_normal((v[1] as Vector3).normalized())
			st.add_vertex(v[0])


# --- Roof meshes ----------------------------------------------------------------

## Two roof slopes, ridge along X. w and d include the overhang.
func _roof_mesh(w: float, d: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w / 2
	var hd := d / 2
	var ridge_a := Vector3(-hw, rise, 0)
	var ridge_b := Vector3(hw, rise, 0)
	var t := 0.12
	for s in [-1.0, 1.0]:
		var ea := Vector3(-hw, -ROOF_EAVE_DROP, s * hd)
		var eb := Vector3(hw, -ROOF_EAVE_DROP, s * hd)
		var n := Vector3(0, hd, s * (rise + ROOF_EAVE_DROP)).normalized()
		_quad(st, ridge_a + n * t, ridge_b + n * t, eb + n * t, ea + n * t, n)
		_quad(st, ridge_a, ea, eb, ridge_b, -n)
	return st.commit()


func _gable_mesh(w: float, d: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var x: float = s * w / 2
		var n := Vector3(s, 0, 0)
		for v in [Vector3(x, 0, -d / 2), Vector3(x, 0, d / 2), Vector3(x, rise - 0.05, 0)]:
			st.set_normal(n)
			st.add_vertex(v)
		for v in [Vector3(x, 0, d / 2), Vector3(x, 0, -d / 2), Vector3(x, rise - 0.05, 0)]:
			st.set_normal(-n)
			st.add_vertex(v)
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, b, c, a, c, d, a, c, b, a, d, c]:
		st.set_normal(n)
		st.add_vertex(v)


# --- Helpers ------------------------------------------------------------------

func _mat(key: String, c: Color, rough: float, noise := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := _photo_surface(key, c)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		if noise > 0.0:
			m.albedo_texture = _blotches(noise)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.05, 0.05, 0.05)
	_mats[key] = m
	return m


## The photo material for this key, or null if it's a plain colour.
func _photo_surface(key: String, c: Color) -> StandardMaterial3D:
	if key == "paint_white":             # parking lines
		return null
	for prefix: String in PHOTO:
		if not key.begins_with(prefix):
			continue
		var tint := Color.WHITE
		match prefix:
			"grass":
				tint = Color(0.7, 1.0, 0.5)
			"paint":
				tint = c                 # the boards are white, so this is the house colour
			"roof":
				tint = Color(c.r * 2.6, c.g * 2.6, c.b * 2.6)
			"store_":
				tint = c.lightened(0.35)
		var m := Surfaces.photo(PHOTO[prefix][0], PHOTO[prefix][1], tint)
		if prefix == "grass" or prefix == "asphalt":
			_break_up_tiling(m)
		return m
	return null


## Big soft patches of light and dark, so you can't see the texture repeating.
func _break_up_tiling(m: StandardMaterial3D) -> void:
	m.detail_enabled = true
	m.detail_albedo = _blotches(0.35)
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3(0.03, 0.03, 0.03)


func _blotches(amount: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 5
	nt.noise = fn
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1).darkened(amount))
	ramp.set_color(1, Color(1, 1, 1).lightened(amount * 0.4))
	nt.color_ramp = ramp
	return nt


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## One shared cylinder mesh per key (poles, trunks, cones...).
func _cyl_mesh(key: String, top: float, bottom: float, h: float) -> CylinderMesh:
	if not _shared.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = 12
		_shared[key] = c
	return _shared[key]


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, pos, mat, parent)


func _part(parent: Node3D, kind: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: Mesh
	if kind == "cyl":
		var c := CylinderMesh.new()
		c.top_radius = size.x
		c.bottom_radius = size.x
		c.height = size.y
		mesh = c
	else:
		var b := BoxMesh.new()
		b.size = size
		mesh = b
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
