class_name RecessedWork
extends Node3D
## Recessed lights going in where an old ceiling light was: everything in the
## house for it, from below and from the attic. Built by HouseInterior when the
## building has a recessed request; the electrics are BuildingElectricalModel's.
##
## From the room: F on the old light lays them out (CeilingLayout). Each
## pencil mark gets a 6" hole saw. Once cable's down a hole, the wafer there
## is a BoxView like any other box: land the leads, push it up, clips snap.
##
## From the attic: each hole and the old light's box is a point you can pull
## cable from or run it to, daisy-chained from the old box out. Along a joist
## bay the cable just lies there. Across the joists you bore through them
## (F) or go over the tops on a 2x4 guard strip (E), stapled down. This attic
## has pull-down stairs, so it counts as accessible: over the tops with no
## guard strip is a violation the inspector writes up.

const HOLE_SECONDS := 1.4
const SLACK_FEET := 2             # a foot left hanging at each end to make up on

var house: HouseInterior
var electrical: BuildingElectricalModel
var room: Rect2                   # the ceiling, x/z, house-local
var ceiling := 0.0                # the ceiling's underside
var joist_top := 0.0              # the tops of the joists, where cable crosses over
var joist_bottom := 0.0
var attic_floor := 0.0
var joists: Array[float] = []     # each joist's x
var fixture: BoxView              # the old light
var switch_box: BoxView           # its switch, which the wafers hang off too

var layout: CeilingLayout
var wafers := {}                  # wafer id -> BoxView, once it's got cable
var _marks: Array[Interactable] = []
var _points := {}                 # id ("" for the old box's id too) -> attic Interactable
var _holding := ""                # the point you've pulled cable from, up in the attic
var _hole_nodes: Array[Node3D] = []
var _cables: Node3D
var _cutting := -1


func _ready() -> void:
	_cables = Node3D.new()
	add_child(_cables)
	layout = CeilingLayout.new()
	layout.room = room
	layout.ceiling = ceiling
	layout.floor_y = HouseInterior.FLOOR
	layout.count = electrical.wafer_ids().size()
	layout.obstacles = [[fixture.position.x, fixture.position.z]]
	for d: BoxView in house.detectors:
		if room.has_point(Vector2(d.position.x, d.position.z)):
			layout.obstacles.append([d.position.x, d.position.z])
	layout.done.connect(_laid_out)
	add_child(layout)
	_rebuild()


func _process(_delta: float) -> void:
	_refresh_fixture_prompt()
	for id: String in _points:
		_point_prompt(id, _points[id])


# --- Building what's there ------------------------------------------------------------

## Everything in the house as the model has it: marks, holes, wafers, cable.
func _rebuild() -> void:
	for m in _marks:
		m.queue_free()
	_marks.clear()
	for n in _hole_nodes:
		n.queue_free()
	_hole_nodes.clear()
	for p: Node in _points.values():
		p.queue_free()
	_points.clear()
	var marks: Array = electrical.recessed.get("marks", [])
	var ids := electrical.wafer_ids()
	_add_point(electrical.recessed["fixture"], Vector2(fixture.position.x, fixture.position.z))
	for i in marks.size():
		var at := Vector2(marks[i][0], marks[i][1])
		if not electrical.hole_cut(i):
			_add_mark(i, at)
			continue
		_add_hole(at)
		_add_point(ids[i], at)
		if not electrical.fed(ids[i]):
			_add_hole_hint(at)
		if electrical.fed(ids[i]) and not wafers.has(ids[i]):
			wafers[ids[i]] = house.add_wafer(ids[i], Vector3(at.x, ceiling, at.y), switch_box)
	_draw_cables()
	_refresh_fixture_prompt()


func _refresh_fixture_prompt() -> void:
	if fixture == null:
		return
	if electrical.any_cut():
		fixture.alt_prompt = ""
	else:
		fixture.alt_prompt = "[F] Lay out the wafers (tape measure)" if not electrical.laid_out() else "[F] Redo the layout (nothing's cut yet)"
	fixture.on_alt = open_layout


func open_layout(p: Node3D) -> void:
	if electrical.any_cut():
		return
	layout.marks = (electrical.recessed.get("marks", []) as Array).duplicate(true)
	layout.open(p)


func _laid_out(marks: Array) -> void:
	electrical.lay_out(marks)
	var flaws := CeilingLayout.flaws(marks, room)
	house.hud_say("Pencil marks are up. Looks good to me." if flaws.is_empty() else "Marks are up. Hmm. " + flaws[0])
	_rebuild()


func flaws() -> Array[String]:
	return CeilingLayout.flaws(electrical.recessed.get("marks", []), room)


# --- From the room: pencil marks and the hole saw -----------------------------------

func _add_mark(i: int, at: Vector2) -> void:
	var mark := Interactable.new()
	mark.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)   # +Z down, out of the ceiling
	mark.position = Vector3(at.x, ceiling, at.y)
	mark.prompt = "[E] Cut a 6\" hole here (hole saw, on a ladder)"
	mark.on_use = func(_p: Node3D) -> void: cut(i)
	mark.reach = 1.0
	mark.facing = Vector3.BACK
	mark.aim_radius = 0.09
	mark.height_range = Vector2(-4.0, -1.5)
	var lead := StandardMaterial3D.new()
	lead.albedo_color = Color(0.2, 0.2, 0.22, 0.75)
	lead.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for a in [PI / 4, -PI / 4]:
		var stroke := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.008)
		stroke.mesh = q
		stroke.material_override = lead
		stroke.position = Vector3(0, 0, 0.002)
		stroke.rotation.z = a
		mark.add_child(stroke)
	add_child(mark)
	_marks.append(mark)


## Cuts the hole at mark `i`: the saw goes up, dust comes down, and the plug
## of drywall drops out. A joist showing in the hole is fine for a wafer.
func cut(i: int, animate := true) -> void:
	if electrical.hole_cut(i) or _cutting >= 0:
		return
	var at: Array = electrical.recessed["marks"][i]
	if not animate or not is_inside_tree():
		_finish_cut(i)
		return
	_cutting = i
	var spot := Vector3(at[0], ceiling, at[1])
	var saw := _hole_saw()
	saw.position = spot + Vector3(0, -0.35, 0)
	add_child(saw)
	var dust := _dust(spot)
	add_child(dust)
	var t := create_tween()
	t.tween_property(saw, "position", spot + Vector3(0, -0.03, 0), 0.35)
	t.tween_callback(func() -> void: dust.emitting = true)
	t.parallel().tween_method(func(a: float) -> void: saw.rotation.y = a, 0.0, 60.0, HOLE_SECONDS)
	t.tween_property(saw, "position", spot + Vector3(0, -0.4, 0), 0.3)
	t.tween_callback(func() -> void:
		saw.queue_free()
		dust.emitting = false
		get_tree().create_timer(2.0).timeout.connect(dust.queue_free)
		_drop_plug(spot)
		_cutting = -1
		_finish_cut(i))


func _finish_cut(i: int) -> void:
	electrical.cut_hole(i)
	var at: Array = electrical.recessed["marks"][i]
	var joist := joists.any(func(x: float) -> bool: return absf(x - float(at[0])) < RecessedModels.HOLE_R)
	var left := range(electrical.wafer_ids().size()).filter(func(j: int) -> bool: return not electrical.hole_cut(j)).size()
	var next := " %d to go." % left if left > 0 else " That's all of them. Next: up in the attic (stairs in the hall ceiling), run 14/2 from the old light's box to each hole. The wafers go in from down here once cable's down the hole."
	house.hud_say("Hole's cut.%s%s" % [" There's a joist showing at the edge. Doesn't matter: it's a wafer." if joist else "", next])
	_rebuild()


func _hole_saw() -> Node3D:
	var root := Node3D.new()
	var cup := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = RecessedModels.HOLE_R
	c.bottom_radius = RecessedModels.HOLE_R
	c.height = 0.045
	c.radial_segments = 32
	cup.mesh = c
	cup.material_override = _mat(Color(0.25, 0.25, 0.27), 0.35, 0.9)
	root.add_child(cup)
	var arbor := MeshInstance3D.new()
	var a := CylinderMesh.new()
	a.top_radius = 0.008
	a.bottom_radius = 0.008
	a.height = 0.12
	arbor.mesh = a
	arbor.material_override = _mat(Color(0.7, 0.7, 0.72), 0.3, 0.9)
	arbor.position = Vector3(0, -0.08, 0)
	root.add_child(arbor)
	var drill := MeshInstance3D.new()
	var d := BoxMesh.new()
	d.size = Vector3(0.07, 0.2, 0.06)
	drill.mesh = d
	drill.material_override = _mat(Color(0.85, 0.6, 0.1), 0.6)
	drill.position = Vector3(0, -0.24, 0)
	root.add_child(drill)
	return root


func _dust(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 60
	p.lifetime = 1.4
	p.position = at + Vector3(0, -0.02, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = RecessedModels.HOLE_R
	p.emission_ring_inner_radius = RecessedModels.HOLE_R * 0.9
	p.emission_ring_height = 0.005
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, -2.0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	p.mesh = q
	var m := _mat(Color(0.92, 0.91, 0.88), 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = m
	return p


func _drop_plug(at: Vector3) -> void:
	var plug := RecessedModels._disc(RecessedModels.HOLE_R - 0.002, 0.0127, _mat(Color(0.86, 0.84, 0.79), 0.9))
	plug.position = at + Vector3(0, -0.01, 0)
	plug.rotation = Vector3.ZERO           # a CylinderMesh lies flat as it is
	add_child(plug)
	var land := Vector3(at.x + randf_range(-0.15, 0.15), HouseInterior.FLOOR + 0.007, at.z + randf_range(-0.15, 0.15))
	var t := create_tween()
	t.tween_property(plug, "position", land, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(plug, "rotation", Vector3(randf_range(-0.2, 0.2), randf() * TAU, 0), 0.55)


## The hole, seen from below: dark, with a joist across it if one's there.
func _add_hole(at: Vector2) -> void:
	var dark := RecessedModels._disc(RecessedModels.HOLE_R, 0.002, _mat(Color(0.04, 0.035, 0.03), 1.0))
	dark.rotation = Vector3.ZERO
	dark.position = Vector3(at.x, ceiling - 0.0012, at.y)
	add_child(dark)
	_hole_nodes.append(dark)
	for x in joists:
		var dx := x - at.x
		if absf(dx) < RecessedModels.HOLE_R - 0.01:
			var chord := 2.0 * sqrt(RecessedModels.HOLE_R * RecessedModels.HOLE_R - dx * dx)
			var wood := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(minf(0.045, RecessedModels.HOLE_R - absf(dx) + 0.02), 0.002, chord * 0.92)
			wood.mesh = b
			wood.material_override = _mat(Color(0.66, 0.5, 0.32), 0.85)
			wood.position = Vector3(x, ceiling - 0.0026, at.y)
			add_child(wood)
			_hole_nodes.append(wood)


## Looking up at a hole that's got no cable yet: what's next. Once cable's
## down it, the wafer's BoxView takes this spot.
func _add_hole_hint(at: Vector2) -> void:
	var hint := Interactable.new()
	hint.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)
	hint.position = Vector3(at.x, ceiling, at.y)
	hint.prompt = "Empty hole, no cable yet: that comes from the attic.  [E] How?"
	hint.on_use = func(_p: Node3D) -> void:
		house.hud_say("Attic stairs pull down from the hall ceiling. Up there, E on the old light's box grabs the cable end; E on this hole runs it here. You need a coil of 14/2 in your bag.")
	hint.reach = 1.0
	hint.facing = Vector3.BACK
	hint.aim_radius = 0.09
	hint.height_range = Vector2(-4.0, -1.5)
	add_child(hint)
	_hole_nodes.append(hint)


# --- From the attic: pulling cable ------------------------------------------------------

func _add_point(id: String, at: Vector2) -> void:
	var p := Interactable.new()
	p.position = Vector3(at.x, attic_floor, at.y)
	p.reach = 1.3
	p.height_range = Vector2(-0.5, 0.6)
	p.aim_radius = 0.12
	p.on_use = func(_pl: Node3D) -> void: use_point(id)
	p.on_alt = func(_pl: Node3D) -> void: use_point(id, true)
	add_child(p)
	_points[id] = p


## Where a point is, x/z.
func _at(id: String) -> Vector2:
	var p: Interactable = _points[id]
	return Vector2(p.position.x, p.position.z)


## Joists a run from `a` to `b` crosses.
func crossings(a: Vector2, b: Vector2) -> int:
	var lo := minf(a.x, b.x)
	var hi := maxf(a.x, b.x)
	return joists.filter(func(x: float) -> bool: return x > lo and x < hi).size()


func feet(a: Vector2, b: Vector2) -> int:
	return ceili((absf(a.x - b.x) + absf(a.y - b.y)) * 3.281) + SLACK_FEET


func _point_prompt(id: String, p: Interactable) -> void:
	p.alt_prompt = ""
	var is_old: bool = id == electrical.recessed["fixture"]
	var where := "the old light's box" if is_old else "this hole"
	if _holding == "":
		if electrical.bare_runs().any(func(r: Dictionary) -> bool: return r["to"] == id):
			p.alt_prompt = "[F] Lay a guard strip under the run to here" if house.inventory.has("GuardStrip") else "Bare across the joists: needs a 2x4 guard strip"
		if electrical.fed(id) and not electrical.feeds_on(id):
			p.prompt = "[E] Pull 14/2 from %s (%d ft on hand)" % [where, house.inventory.cable_on_hand()]
		elif not electrical.fed(id):
			p.prompt = "Hole for a wafer. Pull cable here from the old light's box or a wafer that's got it."
		else:
			p.prompt = "Cable in and on to the next."
		return
	if id == _holding:
		p.prompt = "[E] Put the cable end down"
		return
	if electrical.fed(id) or is_old:
		p.prompt = "Already got cable. Pull it to a hole that hasn't."
		return
	var a := _at(_holding)
	var b := _at(id)
	var n := crossings(a, b)
	var ft := feet(a, b)
	if n == 0:
		p.prompt = "[E] Run it here along the joist bay (%d ft)" % ft
	else:
		p.prompt = ("[E] Over the joist tops on a guard strip (%d ft)" if house.inventory.has("GuardStrip") else "[E] Over the joist tops, no guard strip (%d ft)") % ft
		p.alt_prompt = "[F] Bore through the %d joist%s (%d ft)" % [n, "" if n == 1 else "s", ft]


## E (or F, `alt`) on a point up in the attic. Returns what happened, for tests:
## "pulled", "dropped", "ran", "guarded", or why not. F bores through the
## joists on a run, or puts a guard strip under one that went over them bare.
func use_point(id: String, alt := false) -> String:
	if _holding == "":
		if alt and electrical.bare_runs().any(func(r: Dictionary) -> bool: return r["to"] == id):
			if not house.inventory.use("GuardStrip"):
				house.hud_say("You'll need a 2x4 guard strip from the %s." % _truck())
				return "no_strip"
			_bill("GuardStrip")
			electrical.guard_run(id)
			_draw_cables()
			house.hud_say("Guard strip down across the joists, cable stapled to it.")
			return "guarded"
		if alt:
			return ""
		if not electrical.fed(id) or electrical.feeds_on(id):
			return "nothing_to_pull"
		if house.inventory.cable_on_hand() <= SLACK_FEET:
			house.hud_say("You need a coil of 14/2 in your bag. It's on the %s, or the supply house." % _truck())
			return "no_cable"
		_holding = id
		house.hud_say("Got the end of the cable. Walk it to the next hole.")
		return "pulled"
	if id == _holding:
		_holding = ""
		return "dropped"
	if electrical.fed(id) or id == electrical.recessed["fixture"]:
		return "already_fed"
	var a := _at(_holding)
	var b := _at(id)
	var n := crossings(a, b)
	var ft := feet(a, b)
	var how := "bay" if n == 0 else ("bored" if alt else ("guarded" if house.inventory.has("GuardStrip") else "bare"))
	if not house.inventory.pull_cable(ft):
		house.hud_say("That's %d ft and you've only got %d on hand. Get another coil." % [ft, house.inventory.cable_on_hand()])
		return "short"
	if how == "guarded":
		house.inventory.use("GuardStrip")
		_bill("GuardStrip")
	var err := electrical.run_cable(_holding, id, how, ft)
	if err != "":
		return err
	if house.job != null and house.job.kind == "recessed":
		house.job.cable_feet += ft
	var from := _holding
	_holding = ""
	var from_view := house.view_for_device(electrical.device(from))
	if from_view != null:
		from_view.wiring_changed()
	_rebuild()
	match how:
		"bay":
			house.hud_say("%d ft along the bay and down the hole. Splice it on at the far end too." % ft)
		"bored":
			house.hud_say("Bored %d joist%s dead centre and fished it through. %d ft." % [n, "" if n == 1 else "s", ft])
		"guarded":
			house.hud_say("Over the joists on a 2x4 guard strip, stapled every few feet. %d ft." % ft)
		"bare":
			house.hud_say("Over the joist tops with nothing on it. With pull-down stairs up here, that's a violation.")
	return "ran"


func _bill(part: String) -> void:
	if house.job != null and house.job.kind == "recessed":
		house.job.materials_used.append(part)


func _truck() -> String:
	return house.van.spec()["word"] if house.van != null else "truck"


## The cable that's been run, up in the attic: across the joists first (over
## them, on a strip, or through them), then down the bay, and down each hole.
func _draw_cables() -> void:
	for c in _cables.get_children():
		c.queue_free()
	var white := _mat(Color(0.88, 0.87, 0.82), 0.55)
	var wood := _mat(Color(0.8, 0.64, 0.42), 0.85)
	var dark := _mat(Color(0.05, 0.04, 0.03), 0.9)
	for r: Dictionary in electrical.recessed.get("runs", []):
		if not _points.has(r["from"]) or not _points.has(r["to"]):
			continue
		var a := _at(r["from"])
		var b := _at(r["to"])
		var y := joist_top + 0.008
		match r["how"]:
			"bored":
				y = (joist_top + joist_bottom) / 2.0
			"guarded":
				y = joist_top + 0.038 + 0.008
		var down := joist_bottom + 0.01
		var corners: Array[Vector3] = [Vector3(a.x, down, a.y), Vector3(a.x, y, a.y), Vector3(b.x, y, a.y),
			Vector3(b.x, maxf(y, joist_top + 0.008), b.y), Vector3(b.x, down, b.y)]
		if r["how"] == "bay":
			corners = [Vector3(a.x, down, a.y), Vector3(a.x, down + 0.01, a.y), Vector3(b.x, down + 0.01, a.y), Vector3(b.x, down + 0.01, b.y), Vector3(b.x, down, b.y)]
		var tube := MeshInstance3D.new()
		tube.mesh = BoxView._tube(Town._bent(corners, 0.05), 0.0055, 8)
		tube.material_override = white
		_cables.add_child(tube)
		if r["how"] == "guarded":
			var strip := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(absf(b.x - a.x) + 0.3, 0.038, 0.089)
			strip.mesh = sb
			strip.material_override = wood
			strip.position = Vector3((a.x + b.x) / 2.0, joist_top + 0.019, a.y)
			_cables.add_child(strip)
		elif r["how"] == "bored":
			for x in joists:
				if x > minf(a.x, b.x) and x < maxf(a.x, b.x):
					var hole := RecessedModels._disc(0.012, 0.05, dark)
					hole.rotation = Vector3(0, 0, PI / 2)
					hole.position = Vector3(x, y, a.y)
					_cables.add_child(hole)


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
