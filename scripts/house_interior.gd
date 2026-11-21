class_name HouseInterior
extends Node3D
## The inside of the house you're working at. It's built when the job starts
## and taken away when it's done, so only one house in town has an inside.
##
## The plain box the town drew for the house is hidden and replaced with real
## walls, built to the owner's ranch plan: 40 x 30 ft with a covered porch.
## Looking from the street, the kitchen/dining is back left with an L of
## counters and the back door, the family room front left with the front door.
## Down the middle: the laundry (water heater, washer, dryer) at the back, the
## master bath under it, a hall across to the bedrooms, and the hall bath with
## bedroom 2's closet. The master bedroom (with a walk-in closet) is back right,
## bedroom 2 front right. The plan's walls are in WALLS; check positions
## against it, and layout_violations() checks the boxes and furniture.
## Every light, plug and appliance hangs off a circuit in the panel, so when a
## breaker's off its room goes dark, and a burnt breaker makes its lights flicker.
##
## Added as a child of the house's root: local +Z faces the street, the floor
## is at FLOOR. Models come from art/interior.py.

const LIBRARY := "res://assets/interior/interior.glb"
## The owner's smoke detector, base and harness (art/smoke_detector.blend).
const SMOKE_DETECTOR := "res://assets/smoke_detector/smoke_detector.glb"
const APPLIANCE_FRIDGE := "res://assets/appliances/KA-F1000_FridgeSBS_V1.glb"
const APPLIANCE_STOVE := "res://assets/appliances/KA-F600_Stove_V1.glb"
const APPLIANCE_MICROWAVE := "res://assets/appliances/KA_Micro_V2.glb"
const APPLIANCE_WASHER := "res://assets/appliances/KA-F600_Washer_V1.glb"
const APPLIANCE_DRYER := "res://assets/appliances/KA-F600_Dryer_V1.glb"
## The owner's electric water heater (blend/water_heater.blend, built by
## art/water_heater_covers.py): 560 mm x 1.5 m, origin at the middle of its base,
## front (element covers, junction box) toward +Z.
const WATER_HEATER := "res://assets/water_heater/water_heater.glb"
const HVAC_SYSTEM := preload("res://scripts/hvac_system.gd")
const FLOOR := 0.36
const CEILING := 2.95
const WALL := 0.15               # outside walls
const SKIN := 0.02               # the siding on the outside of them
const PARTITION := 0.1           # inside walls
const DOOR_W := 1.0
const DOOR_H := 2.1
const INNER_DOOR_W := 0.85
const WINDOW := Vector2(1.2, 1.1)
const WINDOW_Y := 1.6
const PLUG_Y := 0.35             # above the floor
const COUNTER_PLUG_Y := 1.07
const SWITCH_Y := 1.2
## Inside faces of the outside walls, for the plan's 40 x 30 ft (local metres).
const XL := -5.946
const XR := 5.946
const ZB := -4.422               # back
const ZF := 4.422                # front
## The plan's inside walls: [name, axis, at, from, to, doors]. Axis "x" runs
## front to back at that x; "z" runs across at that z. Doors are [centre, width].
const WALLS := [
	["core_west", "x", -0.98, ZB, -0.04, [[-3.3, 0.8]]],        # kitchen | laundry, master bath (laundry door)
	["laundry_bath", "z", -2.62, -0.98, 1.96, []],               # laundry | master bath
	["core_east", "x", 1.96, ZB, -0.04, [[-1.35, 0.8]]],         # laundry, master bath | master (bath door)
	["hall_north", "z", -0.04, -0.98, 3.59, [[2.6, 0.85]]],      # master bath, master | hall (master door)
	["closet_west", "x", 3.59, -0.46, 1.14, []],                 # end of the hall | walk-in closet
	["closet_north", "z", -0.46, 3.59, XR, [[5.1, 0.8]]],        # master | walk-in closet (closet door)
	["hall_south", "z", 1.14, 0.83, XR, [[1.35, 0.75], [3.0, 0.85]]],   # hall | hall bath, bedroom 2
	["bath2_west", "x", 0.83, 1.14, ZF, []],                     # family room | hall bath, closet
	["bath2_south", "z", 2.99, 0.83, 2.38, []],                  # hall bath | bedroom 2's closet
	["bed2_west", "x", 2.38, 1.14, ZF, [[3.75, 0.8]]],           # hall bath, closet | bedroom 2 (closet door)
]

## Floor space each piece of furniture takes up, for bumping into: width, height, depth.
const FURNITURE := {
	"Fridge": Vector3(0.9, 1.78, 0.75), "BaseCabinet": Vector3(0.6, 0.92, 0.64), "SinkCabinet": Vector3(0.6, 0.92, 0.64),
	"Range": Vector3(0.76, 1.12, 0.66), "Couch": Vector3(2.0, 0.88, 0.9), "TVStand": Vector3(1.3, 0.5, 0.43),
	"Bed": Vector3(1.72, 0.62, 2.13), "Nightstand": Vector3(0.48, 0.55, 0.42), "Toilet": Vector3(0.42, 0.81, 0.7),
	"Vanity": Vector3(0.82, 0.85, 0.53), "Tub": Vector3(1.5, 0.56, 0.76),
}

var house: Dictionary            # the town's record of the house
var sim: ElectricalPanel
var electrical: BuildingElectricalModel
## The model already came from a previous visit; random construction details
## are still rolled to keep the global dice order, but must not overwrite it.
var electrical_restored := false
## Handed down to every box: what you carry, the job, the vehicle.
var inventory: Inventory
var job: ActiveJob
var van: Van
## The outlets you can open up and work on.
var boxes: Array[BoxView] = []
var detectors: Array[BoxView] = []
## Every plug, switch and light: {kind, slot, node}. The later jobs work on these.
var devices: Array[Dictionary] = []

var _w := 0.0
var _d := 0.0
var _h := 0.0
var _lib: Node3D
var _smoke_lib: Node3D
var _hidden: Array[Node3D] = []
var _lights: Array[Dictionary] = []   # {slot, box (the fixture), switch, mat, omni}
var _ceiling_holes: Array[Vector3] = []   # x, z, half the size
## The attic, if it's a one-story house.
var junctions: Array[BoxView] = []
## Recessed lights going in (or in) where the master bedroom's light was.
var recessed: RecessedWork
## The master bedroom's ceiling, x/z: inside faces of the bath wall, the
## outside wall, the back wall and the closet wall.
const MASTER_CEILING := Rect2(1.96 + PARTITION / 2.0, ZB, XR - (1.96 + PARTITION / 2.0), -0.46 - PARTITION / 2.0 - ZB)
var _joists: Array[float] = []
var has_attic := false
var _ks := 1.0                   # which side the kitchen's on
var _hatch := Vector2.ZERO
var _attic_floor := 0.0
var _player_in_attic: Node = null
var _saved_ambient := -1.0
var _glows: Array[Dictionary] = []    # clocks and screens that show a circuit's live
var _door: Node3D
var _door_open := false
var _door_use: Interactable
var _door_shape: CollisionShape3D
var _back_door := {}
## Where the customer can be: "outside" and "inside" the front door, and places
## to hang out, each [position, the way they face].
var spots := {}
var hangouts: Array = []
var _t := 0.0
var _furniture: Array[Node3D] = []
var appliances: Array[Appliance] = []
var hvac: Node3D
## The water heater in the laundry: its electrics and water (the building
## model's), and the close-up.
var heater: WaterHeater
var heater_view: WaterHeaterView
var _holes := {}                 # wall -> [hole] cut for outlet boxes
var _partition_doors: Array[Dictionary] = []
var _drywall: StandardMaterial3D
var _trim: Material
var _box_model_i := 0
var _detector_model_i := 0
var _junction_model_i := 0


func _ready() -> void:
	if electrical == null:
		electrical = BuildingElectricalModel.residential(house["address"], sim, house["two_story"])
	heater = electrical.water_heater
	var size: Vector3 = house["size"]
	_w = size.x
	_d = size.z
	_h = size.y
	_lib = (load(LIBRARY) as PackedScene).instantiate()
	RecessedModels.add_to(_lib)
	_drywall = _plain(Color(0.86, 0.84, 0.79), 0.85)
	_trim = house["trim"]
	_open_up()
	_build_front_door()
	_build_rooms()        # first, so the walls know where the boxes go
	_build_installs()
	_build_attic()
	_build_recessed()
	_build_shell()
	_build_partitions()
	for box in boxes:
		for n in _furniture:
			var d := n.global_position - box.global_position
			if Vector2(d.x, d.z).length() < 0.75 and d.y < 0.1:
				box.clutter.append(n)


## How every box and detector in the house was left.
func snapshot() -> Dictionary:
	return electrical.snapshot()


## Put the house back how it was last time. The layout's the same every
## build, so the boxes line up one for one.
func restore(state: Dictionary) -> void:
	electrical.restore(state)
	for b in boxes + detectors + junctions:
		(b as BoxView)._refresh()


func view_for_device(device: ElectricalDevice) -> BoxView:
	for b in boxes + detectors + junctions:
		if (b as BoxView).device == device:
			return b
	return null


## Rebind views when a pending data-driven call receives its final identity
## after construction has completed.
func bind_job(value: ActiveJob) -> void:
	job = value
	if heater_view != null:
		heater_view.job = value
	for b in boxes + detectors + junctions:
		(b as BoxView).job = value


## A short world message from something in the house, such as an appliance.
func hud_say(line: String) -> void:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p != null and p.hud != null:
		p.hud.show_message(line, 2.5)


## Puts the town's plain house back and goes away.
## Is this spot (in the world) inside the house, attic included?
func contains(at: Vector3) -> bool:
	var p := to_local(at)
	return absf(p.x) < _w / 2.0 + 0.25 and absf(p.z) < _d / 2.0 + 0.25 and p.y < _h + 3.0


func close_up() -> void:
	if _player_in_attic != null:
		_leave_attic(_player_in_attic)
	for n in _hidden:
		n.visible = true
	_set_old_collision(true)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_lib):
		_lib.free()
	if is_instance_valid(_smoke_lib):
		_smoke_lib.free()


## What the house pulls on each circuit by itself, in amps: the lights that
## are on, and the things that cycle. Everything else reads nothing until
## someone runs it.
func _report_draw() -> void:
	var d := {}
	for l in _lights:
		var fixture: BoxView = l["box"]
		if fixture.device.lamp_volts() > 50.0:
			var amps := 0.5 * (l["switch"] as BoxView).device.light_scale() if l["switch"] != null else 0.5
			if fixture.device.kind == "Wafer":
				amps = 0.1                     # 12 W of LED
			d[l["slot"]] = d.get(l["slot"], 0.0) + amps + (0.6 if fixture.device.kind == "Fan" else 0.0)
	var cycles := {5: [18.6, 400.0, 90.0]}
	for slot: int in cycles:
		var c: Array = cycles[slot]
		if fmod(_t + slot * 37.0, c[1]) < c[2]:          # compressor, blower, element: on a while, off a while
			d[slot] = d.get(slot, 0.0) + c[0]
	d[10] = d.get(10, 0.0) + 0.05                       # clocks on standby
	d[1] = d.get(1, 0.0) + 0.05
	sim.draw = d


func _process(delta: float) -> void:
	_t += delta
	_report_draw()
	var levels := {}
	for l in _lights:
		var fixture: BoxView = l["box"]
		var level := _level_of(fixture.device.lamp_volts(), l["slot"])
		if l["switch"] != null:
			level *= (l["switch"] as BoxView).device.light_scale()
		(l["omni"] as Light3D).light_energy = level * (2.0 if fixture.device.kind == "Wafer" else 1.2)
		(l["mat"] as StandardMaterial3D).emission_energy_multiplier = level * 3.0
		if level > 0.25:
			fixture.note_working()
			for sw: BoxView in l.get("switches", []):
				sw.note_working()
	for g in _glows:
		var level := 0.0
		if g["outlet"] != null:
			level = _level_of((g["outlet"] as BoxView).device.face_volts(), int(g["slot"]))
		else:
			var slot: int = g["slot"]
			if not levels.has(slot):
				levels[slot] = _level(slot)
			level = levels[slot]
		(g["mat"] as StandardMaterial3D).emission_energy_multiplier = level * float(g["energy"])


## How brightly a circuit's lights burn: full on 120 V, flickering on the sag
## a burnt breaker gives, off when it's dead.
func _level(slot: int) -> float:
	return _level_of(sim.circuit_volts(slot), slot)


func _level_of(v: float, slot: int) -> float:
	if v > 105.0:
		return 1.0
	if v > 50.0:
		return 0.3 + 0.7 * absf(sin(_t * 23.0 + slot) * sin(_t * 6.7 + slot * 2.0))
	return 0.0


# --- Opening the house up -------------------------------------------------------------

func _open_up() -> void:
	# The roof and its gable ends stay: the attic is framed to fit under them.
	for key in ["shell", "door_mesh", "door_trim", "back_door_mesh"]:
		if house.has(key):
			_hide(house[key])
	for win: Dictionary in house["windows"]:
		for part: Node3D in win["parts"]:
			_hide(part)
	_set_old_collision(false)


func _hide(n: Node3D) -> void:
	n.visible = false
	_hidden.append(n)


func _set_old_collision(on: bool) -> void:
	for c in (house["body"] as Node).get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on


# --- Walls, floor and ceiling ---------------------------------------------------------

func _build_shell() -> void:
	var hw := _w / 2.0
	var hd := _d / 2.0
	var top := minf(_h, 3.0)
	var paint: Material = house["paint"]
	for back in [false, true]:
		var s := -1.0 if back else 1.0
		var holes: Array = []
		if not back:
			holes.append({"c": house["door_x"], "w": DOOR_W, "y0": 0.0, "y1": FLOOR + DOOR_H})
		elif house.has("back_door_x"):
			holes.append({"c": house["back_door_x"], "w": DOOR_W, "y0": 0.0, "y1": FLOOR + DOOR_H})
		holes.append_array(_holes.get("back" if back else "front", []))
		for win: Dictionary in house["windows"]:
			if win["back"] == back:
				holes.append({"c": win["x"], "w": WINDOW.x, "y0": WINDOW_Y - WINDOW.y / 2, "y1": WINDOW_Y + WINDOW.y / 2})
				_build_window(win["x"], s)
		for r: Array in _segments(-hw, hw, holes, 0.0, top):
			var u := Vector2(r[0], r[1])
			var y := Vector2(r[2], r[3])
			_block(Vector3(u.y - u.x, y.y - y.x, SKIN), Vector3((u.x + u.y) / 2, (y.x + y.y) / 2, s * (hd - SKIN / 2)), paint, false)
			var inner := Vector2(maxf(u.x, -hw + SKIN), minf(u.y, hw - SKIN))
			_block(Vector3(inner.y - inner.x, y.y - y.x, WALL - SKIN), Vector3((inner.x + inner.y) / 2, (y.x + y.y) / 2, s * (hd - SKIN - (WALL - SKIN) / 2)),
					_drywall, true)
	for s in [-1.0, 1.0]:
		_block(Vector3(SKIN, top, _d), Vector3(s * (hw - SKIN / 2), top / 2, 0), paint, false)
		for r: Array in _segments(-hd + WALL, hd - WALL, _holes.get("right" if s > 0 else "left", []), 0.0, top):
			_block(Vector3(WALL - SKIN, r[3] - r[2], r[1] - r[0]), Vector3(s * (hw - SKIN - (WALL - SKIN) / 2), (r[2] + r[3]) / 2, (r[0] + r[1]) / 2),
					_drywall, true)
	if _h > top:   # a two-story house: the upstairs stays shut
		_block(Vector3(_w, _h - top, _d), Vector3(0, (top + _h) / 2, 0), paint, false)
	var room := Vector2(_w - WALL * 2, _d - WALL * 2)
	_build_ceiling(room, _plain(Color(0.93, 0.92, 0.89), 0.9))
	var wood := Surfaces.photo("white_planks_clean", 1.6, Color(0.5, 0.33, 0.2))
	_block(Vector3(room.x, FLOOR - 0.3, room.y), Vector3(0, (FLOOR + 0.3) / 2, 0), wood, true)


# --- The attic -------------------------------------------------------------------------

const JOIST_H := 0.14
const HATCH_HALF := 0.3


## Joists and insulation over the ceiling, top plates over every wall, the
## roof framing, a hatch from the hall, and the house's wiring: home runs up
## from the panel into junction boxes, and cables on from them to everything
## they feed, dropping down through holes drilled in the top plates.
func _build_attic() -> void:
	if house["two_story"]:
		return
	has_attic = true
	var hw := _w / 2.0
	var hd := _d / 2.0
	var top := minf(_h, 3.0)
	_attic_floor = top + JOIST_H
	var wood := _plain(Color(0.66, 0.5, 0.32), 0.85)
	var fluff := _plain(Color(0.93, 0.74, 0.5), 1.0)
	var x := -hw + 0.25
	while x < hw - 0.1:
		_block(Vector3(0.045, JOIST_H, _d - 0.12), Vector3(x, top + JOIST_H / 2, 0), wood, false)
		_joists.append(x)
		x += 0.41
	_block(Vector3(_w - 0.1, 0.1, _d - 0.1), Vector3(0, top + 0.05, 0), fluff, false)
	# Top plates: the double 2x4 on top of each wall, standing up through the insulation.
	var plate := func(size: Vector3, at: Vector3) -> void: _block(size, at, wood, false)
	for s in [-1.0, 1.0]:
		plate.call(Vector3(_w - 0.1, 0.12, WALL - 0.02), Vector3(0, top + 0.06, s * (hd - WALL / 2)))
		plate.call(Vector3(WALL - 0.02, 0.12, _d - 0.1), Vector3(s * (hw - WALL / 2), top + 0.06, 0))
	for w: Array in WALLS:                # one over every inside wall of the plan
		var at: float = w[2]
		var mid := (float(w[3]) + float(w[4])) / 2.0
		var length := float(w[4]) - float(w[3])
		if w[1] == "x":
			plate.call(Vector3(PARTITION, 0.12, length), Vector3(at, top + 0.06, mid))
		else:
			plate.call(Vector3(length, 0.12, PARTITION), Vector3(mid, top + 0.06, at))
	# Something to walk on, the roof to bump your head on, and the gable ends.
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	_collider(floor_body, Vector3(_w - 0.1, 0.04, _d - 0.1), Vector3(0, _attic_floor - 0.02, 0))
	# The roof is the town's own house roof (Town.ROOF_*), left on: this is its
	# decking and rafters seen from underneath, and something solid to bump your
	# head on. Rafters stop where the roof comes down too low to clear the
	# ceiling, so they never show in the rooms or come out through the roof.
	var ridge := Vector3(0, top + Town.ROOF_RISE, 0)
	var deck := _plain(Color(0.72, 0.6, 0.42), 0.9)
	for s in [-1.0, 1.0]:
		var eave := Vector3(0, top - Town.ROOF_EAVE_DROP, s * (_d / 2 + Town.ROOF_OVERHANG))   # the underside, at the eave
		var down: Vector3 = (eave - ridge).normalized()   # along the slope, from the ridge down
		var out := Vector3(0, absf(down.z), -down.y * s)   # square off the underside, up and out
		var frame := Basis(Vector3.RIGHT, out, Vector3.RIGHT.cross(out))
		var along := (eave - ridge).length()
		var mid := (eave + ridge) / 2
		var roof := StaticBody3D.new()
		roof.transform = Transform3D(frame, mid + out * 0.05)
		add_child(roof)
		_collider(roof, Vector3(_w, 0.1, along), Vector3.ZERO)
		var sheathing := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(_w - 0.02, 0.012, along)
		sheathing.mesh = sb
		sheathing.material_override = deck
		sheathing.transform = Transform3D(frame, mid - out * 0.007)
		add_child(sheathing)
		var depth := 0.12
		var clear := top + 0.012                         # rafters stay above the ceiling's top
		var reach_t := clampf((ridge.y - 0.012 - depth - clear) / (ridge.y - eave.y), 0.0, 1.0)
		var length := along * reach_t
		var rx := -hw + 0.3
		while rx < hw:
			var r := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.045, depth, length)
			r.mesh = b
			r.material_override = wood
			r.add_to_group("rafter")
			r.transform = Transform3D(frame, Vector3(rx, 0, 0) + ridge + down * (length / 2) - out * (0.012 + depth / 2))
			add_child(r)
			rx += 0.6
		var gable := StaticBody3D.new()
		add_child(gable)
		_collider(gable, Vector3(0.1, Town.ROOF_RISE, _d), Vector3(s * hw, top + Town.ROOF_RISE / 2, 0))
	# The hatch in the hall ceiling, where the hall meets the family room.
	_hatch = Vector2(0.2, 0.55)
	_ceiling_holes.append(Vector3(_hatch.x, _hatch.y, HATCH_HALF))
	for dx in [-1.0, 1.0]:
		_block(Vector3(0.04, 0.03, HATCH_HALF * 2 + 0.08), Vector3(_hatch.x + dx * (HATCH_HALF + 0.02), CEILING - 0.01, _hatch.y), _trim, false)
		_block(Vector3(HATCH_HALF * 2 + 0.08, 0.03, 0.04), Vector3(_hatch.x, CEILING - 0.01, _hatch.y + dx * (HATCH_HALF + 0.02)), _trim, false)
	_block(Vector3(0.56, 0.02, 0.56), Vector3(_hatch.x + 0.75, _attic_floor + 0.01, _hatch.y), _plain(Color(0.9, 0.9, 0.87), 0.8), false)   # the cover, set aside
	var up := Interactable.new()
	up.position = Vector3(_hatch.x, FLOOR, _hatch.y)
	up.reach = 1.0
	up.height_range = Vector2(-0.5, 0.5)
	up.aim = Vector3(0, CEILING - FLOOR, 0)  # look up at the hatch
	up.aim_radius = HATCH_HALF
	up.prompt = "[E] Pull down the attic stairs and climb up"
	up.on_use = _enter_attic
	add_child(up)
	var down := Interactable.new()
	down.position = Vector3(_hatch.x, _attic_floor, _hatch.y)
	down.reach = 1.0
	down.height_range = Vector2(-0.5, 0.5)
	down.aim_radius = HATCH_HALF
	down.prompt = "[E] Climb down"
	down.on_use = _leave_attic
	add_child(down)
	_build_wiring(hw, hd)


func _enter_attic(p: Node) -> void:
	_player_in_attic = p
	p.global_position = to_global(Vector3(_hatch.x - 0.6, _attic_floor + 0.05, _hatch.y))
	p.velocity = Vector3.ZERO
	p.set_crouched(true)
	var env := _environment()
	if env != null:
		_saved_ambient = env.ambient_light_energy
		env.ambient_light_energy = 0.12      # it's dark up here: the headlamp's all you've got


func _leave_attic(p: Node) -> void:
	_player_in_attic = null
	p.global_position = to_global(Vector3(_hatch.x, FLOOR + 0.05, _hatch.y + 0.7))
	p.velocity = Vector3.ZERO
	p.set_crouched(false)
	var env := _environment()
	if env != null and _saved_ambient >= 0.0:
		env.ambient_light_energy = _saved_ambient


## Wafers asked for (or in) in the master bedroom: marks, holes, cable, wafers.
func _build_recessed() -> void:
	if not has_attic or electrical.recessed.is_empty():
		return
	var fixture := view_for_device(electrical.device(electrical.recessed["fixture"]))
	recessed = RecessedWork.new()
	recessed.house = self
	recessed.electrical = electrical
	recessed.room = MASTER_CEILING
	recessed.ceiling = CEILING
	recessed.joist_bottom = minf(_h, 3.0)
	recessed.joist_top = recessed.joist_bottom + JOIST_H
	recessed.attic_floor = _attic_floor
	recessed.joists = _joists
	recessed.fixture = fixture
	for l in _lights:
		if l["box"] == fixture:
			recessed.switch_box = l["switch"]
	add_child(recessed)


## A wafer, once cable's down its hole: a box like any other, lit off the old
## light's switch.
func add_wafer(id: String, pos: Vector3, switch_box: BoxView) -> BoxView:
	var mat := _plain(Color(0.98, 0.97, 0.94), 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.93, 0.8)
	var box := BoxView.new()
	box.lib = _lib
	box.device = electrical.device(id)
	_hand_down(box)
	box.room = "master bedroom"
	box.glow_mat = mat
	box.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)   # +Z points down, out of the ceiling
	box.position = pos
	add_child(box)
	boxes.append(box)
	var spot := SpotLight3D.new()
	spot.position = pos + Vector3(0, -0.02, 0)
	spot.rotation.x = -PI / 2
	spot.light_color = Color(1.0, 0.92, 0.8)
	spot.spot_range = 4.0
	spot.spot_angle = 55.0
	spot.light_energy = 0.0
	add_child(spot)
	_lights.append({"slot": box.device.slot, "box": box, "switch": switch_box, "switches": [switch_box] if switch_box != null else [], "mat": mat, "omni": spot})
	return box


func _environment() -> Environment:
	var we := get_tree().get_first_node_in_group("world_env") as WorldEnvironment
	return we.environment if we != null else null


## Home runs from the panel up into junction boxes, and on from them to
## everything they feed. Which box feeds what is the building model's (it's
## the electrics, saved with the house); this only lays the cable to match.
func _build_wiring(hw: float, hd: float) -> void:
	var ms: float = house["meter_side"]
	var y := _attic_floor
	var panel_spot := Vector3(ms * (hw - WALL - 0.1), y, hd - 0.55)
	var near_bed := _junction(Vector3(4.0, y, -2.0), 13, "both bedrooms", null)
	var far_bed := _junction(Vector3(4.2, y, 2.6), 13, "the far bedroom", near_bed)
	var living := _junction(Vector3(-2.8, y, -0.2), 12, "the living room and kitchen lights", null)
	var bath := _junction(Vector3(0.4, y, -1.3), 11, "the bathroom", null)
	var yellow := _plain(Color(0.85, 0.66, 0.12), 0.55)
	var white := _plain(Color(0.86, 0.85, 0.8), 0.55)
	_cable(panel_spot, near_bed.position, white)
	_cable(near_bed.position, far_bed.position, white)
	_cable(panel_spot, living.position, white)
	_cable(panel_spot, bath.position, yellow)
	var hole := _plain(Color(0.05, 0.04, 0.03), 0.9)
	var feeds: Array = []
	feeds.append_array(boxes)
	feeds.append_array(detectors)
	for dev: BoxView in feeds:
		if dev.device.junction == null:
			continue
		var j := view_for_device(dev.device.junction)
		if j == null:
			continue
		var end := Vector3(dev.position.x, y, dev.position.z)
		var on_ceiling: bool = dev.device.family == "ceiling" or dev.device.family == "smoke"
		if not on_ceiling:
			# Down through the top plate over the wall: back from the face to the plate's middle.
			end -= dev.basis.z * PARTITION / 2.0
			_box(self, Vector3(0.03, 0.005, 0.03), Vector3(end.x, minf(_h, 3.0) + 0.122, end.z), hole)
		_cable(j.position, end, yellow if j.device.slot == 11 else white, not on_ceiling)


func _junction(at: Vector3, slot: int, label: String, parent: BoxView) -> BoxView:
	var j := BoxView.new()
	j.lib = _lib
	j.device = electrical.device(electrical.junction_ids[_junction_model_i])
	_junction_model_i += 1
	_hand_down(j)
	j.room = label
	j.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)   # +Z up, out of the box
	j.position = at + Vector3(0, 0.054, 0)                       # sitting on the joist
	add_child(j)
	junctions.append(j)
	return j


func _cable(a: Vector3, b: Vector3, mat: Material, into_wall := false) -> void:
	var lift := Vector3(0, 0.015, 0)
	var corners := [a + lift, Vector3(b.x, a.y, a.z) + lift, b + lift]
	if into_wall:
		corners.append(b + Vector3(0, -0.3, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = BoxView._tube(Town._bent(corners, 0.08), 0.005, 8)
	mi.material_override = mat
	add_child(mi)


## The ceiling, cut into pieces round the holes the light boxes sit in.
func _build_ceiling(room: Vector2, mat: Material) -> void:
	var xs := [-room.x / 2, room.x / 2]
	var zs := [-room.y / 2, room.y / 2]
	for c in _ceiling_holes:
		xs.append_array([c.x - c.z, c.x + c.z])
		zs.append_array([c.y - c.z, c.y + c.z])
	xs.sort()
	zs.sort()
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var w: float = xs[i + 1] - xs[i]
			var d: float = zs[j + 1] - zs[j]
			if w < 0.0005 or d < 0.0005:
				continue
			var at := Vector2((xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2)
			if _ceiling_holes.any(func(c: Vector3) -> bool: return absf(at.x - c.x) < c.z and absf(at.y - c.y) < c.z):
				continue
			_block(Vector3(w, 0.05, d), Vector3(at.x, CEILING + 0.025, at.y), mat, false)


## Cuts the holes out of a wall running from a to b: the pieces left over, as [u0, u1, y0, y1].
func _segments(a: float, b: float, holes: Array, y0: float, y1: float) -> Array:
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["c"] < q["c"])
	var out: Array = []
	var u := a
	for h: Dictionary in sorted:
		var l: float = h["c"] - h["w"] / 2
		var r: float = h["c"] + h["w"] / 2
		if l > u:
			out.append([u, l, y0, y1])
		if h["y0"] > y0:
			out.append([l, r, y0, h["y0"]])
		if h["y1"] < y1:
			out.append([l, r, h["y1"], y1])
		u = r
	if u < b:
		out.append([u, b, y0, y1])
	return out


## A window you can see through, with trim outside and a sill inside.
func _build_window(x: float, s: float) -> void:
	var hd := _d / 2.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.7, 0.75, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.3
	_block(Vector3(WINDOW.x, WINDOW.y, 0.01), Vector3(x, WINDOW_Y, s * (hd - WALL / 2)), glass, true)
	_block(Vector3(0.04, WINDOW.y, 0.04), Vector3(x, WINDOW_Y, s * (hd - WALL / 2)), _trim, false)
	for y in [WINDOW_Y + WINDOW.y / 2 + 0.05, WINDOW_Y - WINDOW.y / 2 - 0.05]:
		_block(Vector3(WINDOW.x + 0.2, 0.1, 0.04), Vector3(x, y, s * (hd + 0.02)), _trim, false)
	for dx in [-1.0, 1.0]:
		_block(Vector3(0.1, WINDOW.y + 0.2, 0.04), Vector3(x + dx * (WINDOW.x / 2 + 0.05), WINDOW_Y, s * (hd + 0.02)), _trim, false)
	_block(Vector3(WINDOW.x + 0.1, 0.03, 0.1), Vector3(x, WINDOW_Y - WINDOW.y / 2 + 0.015, s * (hd - WALL)), _trim, false)


## The plan's inside walls (WALLS), with their doorways, and holes cut where
## a box went into them.
func _build_partitions() -> void:
	for w: Array in WALLS:
		var cuts: Array = []
		for d: Array in w[5]:
			_partition_doors.append({"axis": w[1], "wall": w[2], "center": d[0], "width": d[1]})
			cuts.append({"c": d[0], "w": d[1], "y0": FLOOR, "y1": FLOOR + DOOR_H})
		cuts.append_array(_holes.get(w[0], []))
		var at: float = w[2]
		for r: Array in _segments(w[3], w[4], cuts, FLOOR, CEILING):
			var length: float = r[1] - r[0]
			var mid: float = (r[0] + r[1]) / 2.0
			var y: float = (r[2] + r[3]) / 2.0
			if w[1] == "x":
				_block(Vector3(PARTITION, r[3] - r[2], length), Vector3(at, y, mid), _drywall, true)
			else:
				_block(Vector3(length, r[3] - r[2], PARTITION), Vector3(mid, y, at), _drywall, true)


## Checks the built house against the plan, for the tests and the smoke run:
## every wall box sits on the face of a wall (not buried in it, not floating),
## clear of every doorway, and everything is inside the house.
func layout_violations() -> Array[String]:
	var out: Array[String] = []
	for b: BoxView in boxes:
		var id := electrical.id_of(b.device)
		var p := b.position
		if p.x < XL - 0.01 or p.x > XR + 0.01 or p.z < ZB - 0.01 or p.z > ZF + 0.01:
			out.append("%s is outside the house at %s" % [id, str(p)])
		if b.device.family == "ceiling":
			continue
		var wall := _wall_under(p, b.basis.z)
		if wall == "":
			out.append("%s isn't on the face of any wall at %s" % [id, str(p)])
		for door: Dictionary in _partition_doors:
			var across := absf((p.x if door["axis"] == "x" else p.z) - float(door["wall"]))
			var along := p.z if door["axis"] == "x" else p.x
			if across < 0.12 and absf(along - float(door["center"])) < float(door["width"]) / 2.0 + 0.08:
				out.append("%s is in a doorway at %s" % [id, str(p)])
	for n: Node3D in _furniture:
		var p := n.position
		if p.x < XL - 0.02 or p.x > XR + 0.02 or p.z < ZB - 0.02 or p.z > ZF + 0.02:
			out.append("%s is outside the house at %s" % [n.get_child(0).name if n.get_child_count() > 0 else n.name, str(p)])
	return out


## Which wall a box at `p`, facing `out`, is on the face of, or "".
func _wall_under(p: Vector3, out: Vector3) -> String:
	var faces := [["left", "x", XL, ZB, ZF], ["right", "x", XR, ZB, ZF], ["back", "z", ZB, XL, XR], ["front", "z", ZF, XL, XR]]
	for w: Array in WALLS:
		var normal := 1.0 if (out.x if w[1] == "x" else out.z) > 0.0 else -1.0
		faces.append([w[0], w[1], float(w[2]) + normal * PARTITION / 2.0, w[3], w[4]])
	for f: Array in faces:
		var facing_axis := absf(out.x) > 0.9 if f[1] == "x" else absf(out.z) > 0.9
		var across: float = p.x if f[1] == "x" else p.z
		var along: float = p.z if f[1] == "x" else p.x
		if facing_axis and absf(across - float(f[2])) < 0.01 and along > float(f[3]) and along < float(f[4]):
			return f[0]
	return ""


# --- Front door -----------------------------------------------------------------------

func _build_front_door() -> void:
	var made := _build_door(house["door_x"], 1.0, "front door")
	_door = made["node"]
	_door_shape = made["shape"]
	_door_use = made["use"]
	_door_use.on_use = func(_p: Node3D) -> void: _toggle_door()
	var x: float = house["door_x"]
	var hd := _d / 2.0
	spots["outside"] = to_global(Vector3(x, 0.0, hd + 1.4))
	spots["inside"] = to_global(Vector3(x, FLOOR, hd - 0.7))
	if house.has("back_door_x"):
		_back_door = _build_door(house["back_door_x"], -1.0, "back door")
		_back_door["open"] = false
		(_back_door["use"] as Interactable).on_use = func(_p: Node3D) -> void: _toggle_back_door()


## A door in the front (side 1) or back (side -1) wall, hinged on its -X side
## and swinging in, with trim both sides and a hidden ramp up from the yard.
func _build_door(x: float, side: float, what: String) -> Dictionary:
	var hd := _d / 2.0
	var wall_z := side * (hd - WALL / 2)
	for s in [-1.0, 1.0]:
		var z := side * (hd + 0.02) if s > 0.0 else side * (hd - WALL - 0.01)
		for dx in [-1.0, 1.0]:
			_block(Vector3(0.09, DOOR_H + 0.09, 0.03), Vector3(x + dx * (DOOR_W / 2 + 0.045), FLOOR + (DOOR_H + 0.09) / 2, z), _trim, false)
		_block(Vector3(DOOR_W + 0.18, 0.09, 0.03), Vector3(x, FLOOR + DOOR_H + 0.045, z), _trim, false)
	_block(Vector3(DOOR_W, 0.03, WALL + 0.04), Vector3(x, FLOOR - 0.012, wall_z), _plain(Color(0.55, 0.42, 0.28), 0.5), false)
	var node := Node3D.new()
	node.position = Vector3(x - DOOR_W / 2 + 0.01, 0, wall_z)
	if side < 0.0:
		node.rotation.y = PI            # the back door swings in too, into the kitchen
		node.position.x = x + DOOR_W / 2 - 0.01
	add_child(node)
	var slab := Vector3(DOOR_W - 0.03, DOOR_H - 0.02, 0.045)
	var at := Vector3(slab.x / 2, FLOOR + slab.y / 2 + 0.005, 0)
	var paint: Material = (house["door_mesh"] as MeshInstance3D).material_override
	_box(node, slab, at, paint)
	for panel_y in [0.55, 1.45]:
		for s in [-1.0, 1.0]:
			_box(node, Vector3(slab.x - 0.24, 0.62, 0.01), at + Vector3(0, panel_y - slab.y / 2, s * 0.025), paint)
	var brass := _plain(Color(0.75, 0.55, 0.22), 0.3)
	brass.metallic = 1.0
	for s in [-1.0, 1.0]:
		_box(node, Vector3(0.05, 0.05, 0.05), Vector3(slab.x - 0.08, FLOOR + 0.95, s * 0.045), brass)
	# Solid while it's shut. Open, it's swung back against the wall out of your way.
	var body := StaticBody3D.new()
	node.add_child(body)
	_collider(body, slab, at)
	var use := Interactable.new()
	use.position = Vector3(x, 0, side * hd)
	use.reach = 1.3
	use.aim = Vector3(0, FLOOR + DOOR_H / 2, 0)
	use.aim_radius = 0.55
	use.prompt = "[E] Open the %s" % what
	add_child(use)
	# The floor's up a step from the yard: a ramp you don't see.
	var start := Vector3(x, 0.0, side * (hd + 2.4))
	var end := Vector3(x, FLOOR, side * (hd - 0.25))
	var ramp := StaticBody3D.new()
	ramp.position = (start + end) / 2
	ramp.look_at_from_position(ramp.position, end, Vector3.UP)
	add_child(ramp)
	_collider(ramp, Vector3(1.3, 0.1, start.distance_to(end)), Vector3(0, -0.05, 0))
	return {"node": node, "shape": body.get_child(0), "use": use}


func _toggle_door() -> void:
	_door_open = not _door_open
	_door_shape.disabled = _door_open
	_door_use.prompt = "[E] Close the front door" if _door_open else "[E] Open the front door"
	var t := create_tween()
	t.tween_property(_door, "rotation:y", 1.65 if _door_open else 0.0, 0.5).set_trans(Tween.TRANS_SINE)


func _toggle_back_door() -> void:
	var open: bool = not _back_door["open"]
	_back_door["open"] = open
	(_back_door["shape"] as CollisionShape3D).disabled = open
	(_back_door["use"] as Interactable).prompt = "[E] %s the back door" % ("Close" if open else "Open")
	var t := create_tween()
	t.tween_property(_back_door["node"], "rotation:y", PI + (1.65 if open else 0.0), 0.5).set_trans(Tween.TRANS_SINE)


func open_front_door() -> void:
	if not _door_open:
		_toggle_door()


# --- Rooms ----------------------------------------------------------------------------

## The box for a job's fault: the range outlet for a range job, a GFCI for a
## GFCI job, otherwise a plain receptacle.
func pick_box(fault: String) -> BoxView:
	var want := "Range" if fault.begins_with("range") else ("GFCI" if fault == "bad_gfci" else "Receptacle")
	var pool := boxes.filter(func(b: BoxView) -> bool: return b.device.kind == want)
	return pool.pick_random()


func total_shocks() -> int:
	return boxes.reduce(func(n: int, b: BoxView) -> int: return n + b.work.shocks, 0) + (heater_view.work.shocks if heater_view != null else 0)


func total_arcs() -> int:
	return boxes.reduce(func(n: int, b: BoxView) -> int: return n + b.work.arcs, 0) + (heater_view.work.arcs if heater_view != null else 0)


func _hand_down(b: BoxView) -> void:
	b.inventory = inventory
	b.job = job
	b.van = van


## Everything in the rooms, in the order the building model lists its boxes
## (saves and callbacks find a box by its place in that list): kitchen,
## family room, master bath, master, bedroom 2, hall bath, laundry.
func _build_rooms() -> void:
	_ks = -1.0                        # the kitchen's on the left, looking from the street

	# Kitchen/dining. Down the left wall from the back corner: a corner cabinet,
	# the range, a cabinet and the fridge. Along the back wall: microwave and
	# toaster cabinets, the sink under the window, the dishwasher, one more.
	_place(["BaseCabinet"], Vector3(XL, FLOOR, ZB + 0.3), Vector3.RIGHT)
	var range_z := ZB + 0.6 + 0.381
	var stove := _place_asset(APPLIANCE_STOVE, Vector3(XL, FLOOR, range_z), Vector3.RIGHT,
			Vector3(0.6, 0.88, 0.61), Vector3(0.762, 0.88, 0.66))     # 600 mm model at a 30 in opening
	_place(["BaseCabinet"], Vector3(XL, FLOOR, range_z + 0.381 + 0.3), Vector3.RIGHT)
	var fridge_z := range_z + 0.381 + 0.6 + 0.5
	var fridge := _place_asset(APPLIANCE_FRIDGE, Vector3(XL, FLOOR, fridge_z), Vector3.RIGHT,
			Vector3(1.0, 2.0, 0.62), Vector3(1.0, 2.0, 0.62))
	var corner := XL + 0.64
	var run := [corner + 0.3, corner + 0.9, corner + 1.5, corner + 2.1, corner + 2.7]
	_place(["BaseCabinet"], Vector3(run[0], FLOOR, ZB), Vector3.BACK)
	_place(["BaseCabinet"], Vector3(run[1], FLOOR, ZB), Vector3.BACK)
	_place(["SinkCabinet"], Vector3(run[2], FLOOR, ZB), Vector3.BACK)
	_place(["BaseCabinet"], Vector3(run[3], FLOOR, ZB), Vector3.BACK)
	var steel := _plain(Color(0.7, 0.72, 0.74), 0.35)
	steel.metallic = 0.8
	_box(self, Vector3(0.58, 0.78, 0.02), Vector3(run[3], FLOOR + 0.45, ZB + 0.65), steel)   # the dishwasher's door
	_place(["BaseCabinet"], Vector3(run[4], FLOOR, ZB), Vector3.BACK)
	var mw := _place_asset(APPLIANCE_MICROWAVE, Vector3(run[0], FLOOR + 0.915, ZB), Vector3.BACK,
			Vector3(0.45, 0.3, 0.27), Vector3(0.52, 0.35, 0.31), false)
	var toaster := _place(["Toaster"], Vector3(run[1], FLOOR + 0.915, ZB + 0.12), Vector3.BACK, false)
	var range_box := _box_on("Range", "left", range_z, FLOOR + 0.16, 1, 1, "kitchen")
	var mw_box := _box_on("Receptacle", "back", run[0] - 0.15, FLOOR + 1.35, 1, 10, "kitchen")
	var fridge_box := _box_on("Receptacle", "left", fridge_z, FLOOR + 1.2, 1, 16, "kitchen")
	var toaster_box := _box_on("Receptacle", "back", run[1] - 0.15, FLOOR + COUNTER_PLUG_Y, 1, 9, "kitchen")
	_box_on("Receptacle", "back", run[4] - 0.15, FLOOR + COUNTER_PLUG_Y, 1, 9, "kitchen")
	_make_appliance(stove, "stove", "range", 1, range_box, 0.7)
	_make_appliance(fridge, "fridge", "fridge", 16, fridge_box, 0.75, true)
	_make_appliance(mw, "microwave", "microwave", 10, mw_box, 0.3)
	_make_appliance(toaster, "toaster", "toaster", 9, toaster_box, 0.25)
	_floor_tile(Vector2(XL, -1.03), Vector2(ZB, ZB + 3.4), Color(0.78, 0.76, 0.7))
	var kitchen_light := _light(Vector3(-3.4, CEILING, -2.7), 12, "kitchen")
	_switch_on("core_west", -2.3, -1, kitchen_light, 12, "kitchen")

	# Family room: the TV on the left wall, the couch facing it.
	var tv_z := 2.4
	_place(["TVStand"], Vector3(XL, FLOOR, tv_z), Vector3.RIGHT)
	var tv := _place(["TV", "TVScreen"], Vector3(XL, FLOOR, tv_z), Vector3.RIGHT, false)
	_glow(tv["TVScreen"], 12, Color(0.35, 0.55, 0.9), 0.8)
	var couch := Vector3(-2.4, FLOOR, tv_z)
	_place(["Couch"], couch, Vector3.LEFT)
	# Where the customer spends their time: on the couch, and at the toaster.
	hangouts.append([to_global(couch + Vector3(-0.45, 0, 0.35)), global_basis * Vector3.LEFT, true])
	hangouts.append([to_global(Vector3(run[1], FLOOR, ZB + 1.0)), global_basis * Vector3.FORWARD, false])
	var tv_box := _box_on("Receptacle", "left", tv_z + 0.8, FLOOR + PLUG_Y, 1, 12, "living room")
	_box_on("Receptacle", "front", -2.0, FLOOR + PLUG_Y, -1, 12, "living room")
	_box_on("Receptacle", "bath2_west", 2.6, FLOOR + PLUG_Y, -1, 12, "living room")
	var tv_appliance := _make_appliance(tv, "TV", "TV", 12, tv_box, 0.35)
	tv_appliance.add_glow((tv["TVScreen"] as MeshInstance3D).material_override)
	var living_light := _light(Vector3(-2.6, CEILING, 2.0), 12, "living room")
	# A 3-way pair: one beside the front door, one where the hall begins.
	var by_door := _box_on("ThreeWay", "bath2_west", 3.95, FLOOR + SWITCH_Y, -1, 12, "living room", "line")
	var by_hall := _box_on("ThreeWay", "core_west", -0.5, FLOOR + SWITCH_Y, -1, 12, "living room", "load")
	by_door.device.partner = by_hall.device
	by_hall.device.partner = by_door.device
	living_light.device.feed = by_hall.device
	for l in _lights:
		if l["box"] == living_light:
			l["switch"] = by_hall
			l["switches"] = [by_door, by_hall]
	_smoke(Vector3(-2.0, CEILING, 0.3), "living room")

	# Master bath, under the laundry: vanity on the laundry wall, toilet on the
	# kitchen side, the tub along the hall wall, the linen cupboard in its corner.
	_place(["Vanity"], Vector3(0.7, FLOOR, -2.57), Vector3.BACK)
	_place(["Toilet"], Vector3(-0.93, FLOOR, -1.9), Vector3.RIGHT)
	_place(["Tub"], Vector3(1.1, FLOOR, -0.09), Vector3.FORWARD)
	_block(Vector3(1.1, 2.0, 0.8), Vector3(-0.38, FLOOR + 1.0, -0.49), _plain(Color(0.9, 0.88, 0.83), 0.6), true)   # linen
	_box_on("GFCI", "laundry_bath", 1.4, FLOOR + COUNTER_PLUG_Y, 1, 11, "bathroom")
	_floor_tile(Vector2(-0.93, 1.91), Vector2(-2.57, -0.09), Color(0.82, 0.84, 0.85))
	var bath_light := _light(Vector3(0.5, CEILING, -1.35), 11, "bathroom")
	_switch_on("core_east", -2.0, -1, bath_light, 11, "bathroom")

	# Master (back right) and bedroom 2 (front right): beds against the right wall.
	for room: Dictionary in [
			{"name": "master bedroom", "bed": -2.4, "stand": -3.6, "side": -3.95, "other": ["back", 3.95, 1], "light": Vector3(3.95, CEILING, -2.4),
				"switch": ["hall_north", 3.3, -1], "smoke": Vector3(3.0, CEILING, -1.0)},
			{"name": "front bedroom", "bed": 2.75, "stand": 1.55, "side": 4.0, "other": ["front", 2.8, -1], "light": Vector3(4.15, CEILING, 2.9),
				"switch": ["hall_south", 3.7, 1], "smoke": Vector3(3.3, CEILING, 2.2)}]:
		_place(["Bed"], Vector3(XR, FLOOR, room["bed"]), Vector3.LEFT)
		_place(["Nightstand"], Vector3(XR, FLOOR, room["stand"]), Vector3.LEFT)
		var name: String = room["name"]
		_box_on("Receptacle", "right", room["side"], FLOOR + PLUG_Y, -1, 13, name)
		var other: Array = room["other"]
		_box_on("Receptacle", other[0], other[1], FLOOR + PLUG_Y, other[2], 13, name)
		var bed_light := _light(room["light"], 13, name)
		var sw: Array = room["switch"]
		_switch_on(sw[0], sw[1], sw[2], bed_light, 13, name)
		_smoke(room["smoke"], name)

	# Hall bath: vanity and toilet along bedroom 2's wall.
	_place(["Vanity"], Vector3(2.33, FLOOR, 1.7), Vector3.LEFT)
	_place(["Toilet"], Vector3(2.33, FLOOR, 2.6), Vector3.LEFT)
	_box_on("GFCI", "bed2_west", 2.22, FLOOR + COUNTER_PLUG_Y, -1, 11, "hall bathroom")
	_floor_tile(Vector2(0.88, 2.33), Vector2(1.19, 2.94), Color(0.82, 0.84, 0.85))
	var hall_bath_light := _light(Vector3(1.6, CEILING, 2.05), 11, "hall bathroom")
	_switch_on("hall_south", 2.05, 1, hall_bath_light, 11, "hall bathroom")

	# Laundry: water heater in the corner by the door, washer and dryer along
	# the back wall on their own 120 V and 240 V circuits.
	var washer := _place_asset(APPLIANCE_WASHER, Vector3(0.55, FLOOR, ZB), Vector3.BACK,
			Vector3(0.6, 0.8, 0.64), Vector3(0.66, 0.88, 0.72))
	var dryer := _place_asset(APPLIANCE_DRYER, Vector3(1.3, FLOOR, ZB), Vector3.BACK,
			Vector3(0.6, 0.8, 0.64), Vector3(0.66, 0.88, 0.72))
	var washer_box := _box_on("Receptacle", "back", 0.55, FLOOR + 1.05, 1, 14, "laundry")
	_make_appliance(washer, "washer", "washer", 14, washer_box, 0.75)
	var dryer_appliance := _make_appliance(dryer, "dryer", "dryer", 2, null, 0.75)
	dryer_appliance.voltage = 240
	_water_heater(Vector3(-0.6, FLOOR, -4.1))
	_floor_tile(Vector2(-0.93, 1.91), Vector2(ZB, -2.67), Color(0.74, 0.74, 0.72))
	var laundry_light := _light(Vector3(0.5, CEILING, -3.5), 12, "laundry")
	_switch_on("laundry_bath", -0.55, -1, laundry_light, 12, "laundry")
	_build_hvac()


## The water heater, standing at `at` with its front to the room, solid to bump into.
func _water_heater(at: Vector3) -> void:
	var model := (load(WATER_HEATER) as PackedScene).instantiate() as Node3D
	model.name = "WaterHeater"
	model.position = at
	add_child(model)
	_furniture.append(model)
	# The WARNING on the junction cover is printed on: it mustn't throw a shadow.
	for label: GeometryInstance3D in model.find_children("*WarningLabel*", "GeometryInstance3D", true, false):
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	add_child(body)
	_collider(body, Vector3(0.56, 1.5, 0.56), at + Vector3(0, 0.75, 0))
	heater_view = WaterHeaterView.new()
	heater_view.name = "WaterHeaterView"
	heater_view.heater = heater
	heater_view.sim = sim
	heater_view.model = model
	heater_view.position = at
	heater_view.inventory = inventory
	heater_view.job = job
	heater_view.van = van
	add_child(heater_view)


# --- New outlets customers asked for -------------------------------------------------------

## Where on this plan each of the building model's install spots is: wall,
## along, height, side (as _box_on).
const INSTALL_PLACES := {"bedroom_desk": ["back", 2.5, PLUG_Y, 1], "living_room_lamp": ["bath2_west", 1.6, PLUG_Y, -1]}

var _install_marks := {}         # install id -> the pencil mark you cut in at


## Every outlet asked for: a pencil mark where it's wanted, or the box, if
## it's been cut in already.
func _build_installs() -> void:
	for id in electrical.install_ids():
		if electrical.roughed_in(id):
			_install_box(id)
		else:
			_install_mark(id)


func _install_spot(id: String) -> Array:
	var place: Array = INSTALL_PLACES[electrical.installs[id]["spot"]]
	return _wall_spot(place[0], place[1], FLOOR + float(place[2]), place[3])


## Where the new outlet's wanted (or is), in the world.
func install_mark_position(id: String) -> Vector3:
	return to_global(_install_spot(id)[0])


func _install_mark(id: String) -> void:
	var spot := _install_spot(id)
	var mark := Interactable.new()
	mark.basis = Basis.looking_at(-spot[1], Vector3.UP)
	mark.position = spot[0]
	mark.prompt = "[E] Cut a box in at the pencil mark"
	mark.on_use = func(_p: Node3D) -> void: cut_in(id)
	mark.reach = 1.3
	mark.facing = Vector3.BACK
	mark.aim_radius = 0.08
	mark.height_range = Vector2(-2.5, 0.6)
	var pencil := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.1)
	pencil.mesh = quad
	pencil.position = Vector3(0, 0, 0.002)
	var lead := StandardMaterial3D.new()
	lead.albedo_color = Color(0.25, 0.25, 0.27)
	lead.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lead.albedo_color.a = 0.55
	pencil.material_override = lead
	mark.add_child(pencil)
	add_child(mark)
	_install_marks[id] = mark


func _install_box(id: String) -> BoxView:
	var place: Array = INSTALL_PLACES[electrical.installs[id]["spot"]]
	var spot := _install_spot(id)
	return _outlet("Receptacle", spot[0], spot[1], electrical.device(id).slot, place[0], electrical.rooms[id], "", electrical.device(id))


## Cuts the box in at the mark and fishes the cable back to the nearest
## working outlet in the room. Needs an old-work box and cable in your hands.
## "" if done, or why not.
func cut_in(id: String) -> String:
	if not inventory.has("OldWork"):
		hud_say("You'll need an old-work box and a length of cable in your bag. Check the %s." % (van.spec()["word"] if van != null else "truck"))
		return "no_box"
	var at := _install_spot(id)[0] as Vector3
	var best: BoxView = null
	for source_id in electrical.source_candidates_in(electrical.installs[id]["room"]):
		var v := view_for_device(electrical.device(source_id))
		if v != null and (best == null or v.position.distance_to(at) < best.position.distance_to(at)):
			best = v
	if best == null:
		hud_say("There's no working outlet in here to feed it from.")
		return "no_source"
	var err := electrical.rough_in(id, electrical.id_of(best.device))
	if err != "":
		return err
	inventory.use("OldWork")
	if job != null and id in job.equipment_ids:
		job.materials_used.append("OldWork")
	(_install_marks[id] as Node).queue_free()
	_install_marks.erase(id)
	var v := _install_box(id)
	best.wiring_changed()
	hud_say("Box cut in. The cable's fished back to the outlet %.1f m along the wall." % best.position.distance_to(v.position))
	return ""


## Where a box goes on a wall, and which way it faces. `wall` is "left",
## "right", "back", "front" (the outside walls' inside faces) or a WALLS name;
## for those, `side` is which face: -1 the low-x / low-z side, 1 the other.
func _wall_spot(wall: String, along: float, height: float, side: int) -> Array:
	match wall:
		"left":
			return [Vector3(XL, height, along), Vector3.RIGHT]
		"right":
			return [Vector3(XR, height, along), Vector3.LEFT]
		"back":
			return [Vector3(along, height, ZB), Vector3.BACK]
		"front":
			return [Vector3(along, height, ZF), Vector3.FORWARD]
	for w: Array in WALLS:
		if w[0] == wall:
			var face: float = float(w[2]) + side * PARTITION / 2.0
			if w[1] == "x":
				return [Vector3(face, height, along), Vector3(side, 0, 0)]
			return [Vector3(along, height, face), Vector3(0, 0, side)]
	push_error("No wall called %s" % wall)
	return [Vector3.ZERO, Vector3.BACK]


func _box_on(kind: String, wall: String, along: float, height: float, side: int, slot: int, room: String, role := "") -> BoxView:
	var spot := _wall_spot(wall, along, height, side)
	return _outlet(kind, spot[0], spot[1], slot, wall, room, role)


func _switch_on(wall: String, along: float, side: int, fixture: BoxView, slot: int, room: String) -> BoxView:
	var spot := _wall_spot(wall, along, FLOOR + SWITCH_Y, side)
	return _switch(spot[0], spot[1], fixture, slot, wall, room)


func _floor_tile(x: Vector2, z: Vector2, c: Color) -> void:
	_block(Vector3(x.y - x.x, 0.004, z.y - z.x), Vector3((x.x + x.y) / 2, FLOOR + 0.002, (z.x + z.y) / 2), _plain(c, 0.35), false)


# --- Putting things in ------------------------------------------------------------------

## Central air for the plan: the air handler up in the attic over the hall
## (where ranch houses put it) with its return grille in the hall ceiling,
## the thermostat on the hall wall, and the condenser out back on its pad
## with the disconnect on the wall beside it. Simple models until there's HVAC art.
func _build_hvac() -> void:
	var metal := _plain(Color(0.58, 0.62, 0.63), 0.55)
	var dark := _plain(Color(0.12, 0.14, 0.15), 0.7)
	var hd := _d / 2.0
	var attic := minf(_h, 3.0) + JOIST_H
	var handler := _box(self, Vector3(1.2, 0.55, 0.6), Vector3(1.6, attic + 0.3, 0.55), metal)
	handler.name = "AirHandler"
	var grille := _box(self, Vector3(0.6, 0.01, 0.4), Vector3(1.6, CEILING - 0.006, 0.55), dark)
	grille.name = "AirHandlerReturn"
	var pad := _plain(Color(0.6, 0.6, 0.58), 0.9)
	var condenser_pos := Vector3(1.2, 0.43, -hd - 0.75)
	_block(Vector3(1.0, 0.05, 1.0), Vector3(condenser_pos.x, 0.025, condenser_pos.z), pad, false)
	_block(Vector3(0.9, 0.76, 0.9), condenser_pos, metal, true)
	_cylinder(0.32, 0.035, condenser_pos + Vector3(0, 0.4, 0), dark, false)
	var disconnect_pos := Vector3(2.1, 1.35, -hd - 0.08)
	_block(Vector3(0.28, 0.42, 0.12), disconnect_pos, metal, false)
	var thermostat_pos := Vector3(0.9, FLOOR + 1.45, -0.04 + PARTITION / 2.0 + 0.015)
	_block(Vector3(0.12, 0.18, 0.03), thermostat_pos, _plain(Color(0.88, 0.86, 0.8), 0.4), false)
	hvac = HVAC_SYSTEM.new()
	hvac.sim = sim
	hvac.interior = self
	hvac.thermostat_position = thermostat_pos
	hvac.disconnect_position = disconnect_pos
	add_child(hvac)


func _cylinder(radius: float, height: float, pos: Vector3, mat: Material, solid: bool) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	view.position = pos
	add_child(view)
	if solid:
		var body := StaticBody3D.new()
		add_child(body)
		_collider(body, Vector3(radius * 2.0, height, radius * 2.0), pos)

## Copies of the named models, standing at pos with their front toward `facing`.
## The first one gets something solid to bump into, if it's furniture.
func _place(names: Array, pos: Vector3, facing: Vector3, solid := true) -> Dictionary:
	var node := Node3D.new()
	node.basis = Basis.looking_at(-facing, Vector3.UP)
	node.position = pos
	add_child(node)
	var parts := {}
	for n: String in names:
		var model: Node3D = _lib.get_node(n).duplicate()
		node.add_child(model)
		parts[n] = model
	parts["node"] = node
	_furniture.append(node)
	if solid and FURNITURE.has(names[0]):
		var size: Vector3 = FURNITURE[names[0]]
		var body := StaticBody3D.new()
		node.add_child(body)
		_collider(body, size, Vector3(0, size.y / 2, size.z / 2))
	return parts


## Places one imported Asset Library model. Its source uses a back-left floor
## origin, so the child is centered inside the same wrapper our house uses.
func _place_asset(path: String, pos: Vector3, facing: Vector3, source_size: Vector3,
		size: Vector3, solid := true) -> Dictionary:
	var node := Node3D.new()
	node.basis = Basis.looking_at(-facing, Vector3.UP)
	# `pos` is the wall line. Imported meshes have their depth centered around
	# the wrapper, so move the whole appliance into the room by half its depth.
	node.position = pos + facing * (size.z / 2.0 + 0.015)
	add_child(node)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.position = Vector3(-size.x / 2.0, 0.0, -size.z / 2.0)
	model.scale = size / source_size
	node.add_child(model)
	_furniture.append(node)
	if solid:
		var body := StaticBody3D.new()
		node.add_child(body)
		_collider(body, size, Vector3(0, size.y / 2.0, 0))
	return {"node": node, "model": model}


## Makes a placed model usable and ties its operation to a real branch circuit.
func _make_appliance(placed: Dictionary, title: String, electrical_name: String, slot: int,
		outlet: BoxView, slide: float, initially_on := false) -> Appliance:
	var a := Appliance.new()
	a.node = placed["node"]
	a.title = title
	a.appliance = electrical_name
	a.slot = slot
	a.outlet = outlet
	a.slide = slide
	a.sim = sim
	a.interior = self
	a.on = initially_on
	add_child(a)
	appliances.append(a)
	return a


func _device(kind: String, pos: Vector3, facing: Vector3, slot: int) -> Dictionary:
	var placed := _place([kind], pos, facing, false)
	var device := {"kind": kind, "slot": slot, "node": placed["node"]}
	devices.append(device)
	return device


## A receptacle in a box you can open up, with a hole cut in the wall behind it.
func _outlet(kind: String, pos: Vector3, facing: Vector3, slot: int, wall: String, room: String, role := "", device: ElectricalDevice = null) -> BoxView:
	var along_z := wall == "left" or wall == "right" or WALLS.any(func(w: Array) -> bool: return w[0] == wall and w[1] == "x")
	if not _holes.has(wall):
		_holes[wall] = []
	var size := Vector2(0.08, 0.125) if kind == "Range" else Vector2(0.054, 0.092)
	_holes[wall].append({"c": pos.z if along_z else pos.x, "w": size.x, "y0": pos.y - size.y / 2, "y1": pos.y + size.y / 2})
	var box := BoxView.new()
	box.lib = _lib
	if device != null:
		box.device = device                # a new outlet a customer asked for
	else:
		box.device = electrical.device(electrical.box_ids[_box_model_i])
		_box_model_i += 1
	_hand_down(box)
	box.room = room
	box.basis = Basis.looking_at(-facing, Vector3.UP)
	box.position = pos
	add_child(box)
	boxes.append(box)
	devices.append({"kind": kind, "slot": slot, "node": box})
	return box


## A ceiling light on its own box, with a hole cut in the ceiling for it.
func _light(pos: Vector3, slot: int, room: String) -> BoxView:
	_ceiling_holes.append(Vector3(pos.x, pos.z, 0.05))
	var mat := _plain(Color(0.95, 0.93, 0.88), 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.62)
	var box := BoxView.new()
	box.lib = _lib
	box.device = electrical.device(electrical.box_ids[_box_model_i])
	_box_model_i += 1
	_hand_down(box)
	box.room = room
	box.glow_mat = mat
	box.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)   # +Z points down, out of the ceiling
	box.position = pos
	add_child(box)
	boxes.append(box)
	var omni := OmniLight3D.new()
	omni.position = pos + Vector3(0, -0.35, 0)
	omni.light_color = Color(1.0, 0.86, 0.66)
	omni.omni_range = 5.5
	omni.light_energy = 0.0
	add_child(omni)
	_lights.append({"slot": slot, "box": box, "switch": null, "mat": mat, "omni": omni})
	devices.append({"kind": "Fixture", "slot": slot, "node": box})
	return box


## The wall switch that feeds a light.
func _switch(pos: Vector3, facing: Vector3, fixture: BoxView, slot: int, wall: String, room: String) -> BoxView:
	var box := _outlet("Switch", pos, facing, slot, wall, room)
	fixture.device.feed = box.device
	for l in _lights:
		if l["box"] == fixture:
			l["switch"] = box
			l["switches"] = [box]
	return box


## A smoke detector on the ceiling, on the bedroom circuit.
func _smoke(pos: Vector3, room: String) -> void:
	if _smoke_lib == null:
		_smoke_lib = (load(SMOKE_DETECTOR) as PackedScene).instantiate()
		# Its colours are painted on its vertices: tell the material to use them.
		for mi: MeshInstance3D in _smoke_lib.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if m != null:
					m.vertex_color_use_as_albedo = true
	var d := BoxView.new()
	d.lib = _lib
	d.smoke_lib = _smoke_lib
	d.device = electrical.device(electrical.detector_ids[_detector_model_i])
	_detector_model_i += 1
	_hand_down(d)
	d.room = room
	var made := randi_range(2018, 2024)
	if not electrical_restored:
		d.device.made = made
	d.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)   # +Z down, out of the ceiling
	d.position = pos
	add_child(d)
	detectors.append(d)
	_ceiling_holes.append(Vector3(pos.x, pos.z, 0.047))         # its box, behind it: no wider than the base


func sound_alarms() -> void:
	for d in detectors:
		d.alarm()


## A detector for a smoke job: a weak battery, or one past its date.
func pick_smoke(fault: String) -> BoxView:
	var d: BoxView = detectors.pick_random()
	if fault == "smoke_battery":
		d.device.battery_low = true
	else:
		d.device.made = randi_range(2009, 2015)
	return d


## A light and its switch for a light job: [the one with the fault, the other one].
func pick_light(where: String, room := "") -> Array:
	var pool := _lights.filter(func(l: Dictionary) -> bool: return BuildingElectricalModel.in_room((l["box"] as BoxView).room, room) and (l["box"] as BoxView).device.original != "Wafer")
	var l: Dictionary = pool.pick_random()
	if where == "switch3":
		return [(l["switches"] as Array).pick_random(), l["box"]]
	return [l["box"], l["switch"]] if where == "fixture" else [l["switch"], l["box"]]


## A clock or screen that lights up while its circuit's live.
func _glow(mesh: MeshInstance3D, slot: int, color: Color, energy: float, outlet: BoxView = null) -> void:
	var mat := _plain(color * 0.15, 0.2)
	mat.emission_enabled = true
	mat.emission = color
	mesh.material_override = mat
	_glows.append({"slot": slot, "mat": mat, "energy": energy, "outlet": outlet})


# --- Helpers ----------------------------------------------------------------------------

func _block(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	_box(self, size, pos, mat)
	if solid:
		var body := StaticBody3D.new()
		add_child(body)
		_collider(body, size, pos)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _collider(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	parent.add_child(col)


func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
