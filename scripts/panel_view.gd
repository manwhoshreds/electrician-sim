class_name PanelView
extends Interactable
## The house's electrical panel: a 3D model on the wall, and the close-up where
## you work on it. The origin is on the wall at the panel's centre, +Z points
## out of the wall. Everything you can click is a point in 3D, matched against
## the mouse on screen.
##
## Inside it's wired like the real thing: cables come in through the top and
## bottom, the hots land on the breakers, neutrals on the side bars, bare
## grounds on the bar along the bottom.
##
## Hand: door, breaker handles, pulling and seating breakers.
## Screwdriver: the cover screw, breaker terminals.
## Clamp meter: Q turns the dial. On V~ or Ω, left click places the probe in
##   your hand, right click the black. On A~, click a wire to put the jaws round it.
## Click a probe or the clamp where it sits to take it off. R takes them all off.
## Scroll to lean in. Tab for your job notes.

enum Tool { HAND, DRIVER, METER }

const TOOL_NAMES := ["Hand", "Screwdriver", "Clamp meter"]
const W := 0.46
const H := 0.86
const DEPTH := 0.1
const ROW := 0.046
const TOP_ROW := 0.16            # y of the first row of breakers
const HANDLE_X := 0.055
const TERM_X := 0.114
const WIRE_Z := 0.08
const FAR_VIEW := 1.12           # camera distance, leaned back...
const NEAR_VIEW := 0.5           # ...and leaned right in
const VIEW_ANGLE := 0.42         # how far round to the side you stand
const MAX_READINGS := 8
const CLOSEUP_KEYS := [["LMB", "Use Tool"], ["RMB", "Black Probe"], ["Q", "Turn Dial"], ["R", "Leads Off"], ["Scroll", "Lean In"], ["Tab", "Notes"], ["Esc", "Step Back"]]
const SCREWS := [Vector3(0.0, -0.39, 0.099)]   # the dead front has just the one
const RED_PEN_DIR := Vector3(0.3, -0.42, 1.0)
const BLACK_PEN_DIR := Vector3(-0.3, -0.42, 1.0)
const CABLE_COLOUR := {15: Color(0.9, 0.88, 0.82), 20: Color(0.85, 0.7, 0.18), 30: Color(0.85, 0.42, 0.12), 40: Color(0.1, 0.1, 0.11)}

var _breaker_pick := 0         # which of the bag's breaker sizes is up next
var sim: ElectricalPanel
var target_slot := 0
## What you carry (a breaker to clip in), and the job (notes, what it's waiting on).
var inventory: Inventory
var job: ActiveJob
var meter_pos := Vector3.ZERO    # world position of the house's meter
var house_front := Vector3.FORWARD

var door_open := false
var cover_on := true
var cover_removed := false       # has it ever been off
## What you did here: measured the target, tested it dead, got shocked.
var work := WorkLog.new()

var _player: Node3D
var _open := false
var _tool := Tool.HAND
var _screws_in := [true]
var _points := {}                # voltage test points: id -> {pos, label, short}
var _clamps := {}                # clamp points: id -> {pos, dir, label, short}
var _red := ""                   # where each probe is sitting
var _black := ""
var _clamped := ""
var _readings: Array[String] = []
var _visuals := {}               # breaker slot -> its meshes
var _hover := {}
var _readout_t := 0.0
var _volts_shown := 0.0
var _amps_shown := 0.0
var _zoom := 0.0                 # 0 leaned back, 1 leaned in
var _corner := 1.0               # which way along the wall (local X) the house's front corner is
var _eye := Vector3.ZERO
var _look := Vector3.ZERO

var _door: Node3D
var _cover: Node3D
var _screw_meshes: Array[MeshInstance3D] = []
var _main_handle: MeshInstance3D
var _cam: Camera3D
var _lamp: SpotLight3D
var _click: AudioStreamPlayer

var _meter: Node3D               # in your off hand: the meter and the hand holding it
var _held_meter: ClampMeter
var _work_hand: HandRig
var _work_sleeve: MeshInstance3D
var _work_cuff: MeshInstance3D
var _work_pose := ""
var _work_side := 1.0            # +1: your right hand does the work, meter on the left
var _tool_basis := Basis.IDENTITY
var _raise := 0.0                # 0 hands down at your sides, 1 up and working
var _sleeve_mat: StandardMaterial3D
var _glove_mat: StandardMaterial3D
var _red_pen: Node3D
var _black_pen: Node3D
var _red_lead: MeshInstance3D
var _black_lead: MeshInstance3D
var _driver: Node3D
var _clamp: ClampMeter           # the same meter, left hanging on a wire by its jaws

var _ui: CanvasLayer
var _overlay: Control
var _flash: ColorRect
var _tool_buttons: Array[Button] = []
var _notes_panel: PanelContainer
var _log: Label
var _notes: Label
var _hint_label: Label
var _toast: Label
var _toast_t := 0.0
var _door_button: Button
var _cover_button: Button


func _ready() -> void:
	super()
	reach = 2.2
	aim_radius = 0.35
	prompt = "[E] Open up the panel"
	on_use = open
	_corner = -1.0 if (global_basis.inverse() * house_front).x < 0.0 else 1.0
	_work_side = -_corner
	_define_points()
	_build_model()
	_build_ui()
	_build_sound()
	sim.tripped.connect(_on_tripped)
	_sync()
	_show_tools(false)


func _process(delta: float) -> void:
	sim.tick(delta)
	if not _open:
		return
	_update_camera(delta)
	_hover = _pick_at(get_viewport().get_mouse_position())
	_update_held_tools()
	_readout_t -= delta
	if _readout_t <= 0.0:
		_readout_t = 0.2
		_update_readouts()
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			_notes_panel.visible = not _notes_panel.visible
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			_take_leads_off()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_Q:
			_turn_dial(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < TOOL_NAMES.size():
			_select_tool(i)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + (0.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.15), 0.0, 1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var p := _pick_at(event.position)
			if not p.is_empty():
				_click_on(p, event.button_index)
			get_viewport().set_input_as_handled()


func open(p: Node3D) -> void:
	_player = p
	_open = true
	p.target = self
	p.hud.set_closeup(true, CLOSEUP_KEYS)
	_update_camera(1.0)
	_cam.make_current()
	_lamp.visible = true
	_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_buttons()
	_update_readouts()
	_raise = 0.0
	create_tween().tween_property(self, "_raise", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_work_hand.visible = true
	_work_sleeve.visible = true
	_work_cuff.visible = true
	_update_held_tools()


func close() -> void:
	_open = false
	_show_tools(false)
	_player.target = null
	_player.hud.set_closeup(false)
	_player.camera.make_current()
	_lamp.visible = false
	_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## You stand off to one side so you see the corner of the house and the yard
## past the panel. Lean in and moving the mouse looks around.
func _update_camera(delta: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var ndc := (get_viewport().get_mouse_position() / view * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)
	var dist := lerpf(FAR_VIEW, NEAR_VIEW, _zoom)
	var half_high := dist * tan(deg_to_rad(_cam.fov / 2.0))
	var pan := Vector3(ndc.x * 0.14 * _zoom, -ndc.y * maxf(H / 2.0 - half_high, 0.0), 0.0)
	var look_want := Vector3(_corner * 0.075 * (1.0 - _zoom), 0.0, 0.05) + pan
	var eye_want := look_want + Vector3(-_corner * VIEW_ANGLE, 0.03, 1.0).normalized() * dist
	var blend := minf(1.0, delta * 10.0)
	_eye = _eye.lerp(eye_want, blend)
	_look = _look.lerp(look_want, blend)
	_cam.look_at_from_position(to_global(_eye), to_global(_look), Vector3.UP)


# --- Layout -----------------------------------------------------------------------

static func _side(slot: int) -> float:
	return -1.0 if slot % 2 == 1 else 1.0


static func _row(slot: int) -> int:
	return int((slot - 1) / 2)


static func _y(slot: int) -> float:
	return TOP_ROW - _row(slot) * ROW


## Cables for the top four rows come in from above, the rest from below.
static func _from_top(slot: int) -> bool:
	return _row(slot) < 4


func _define_points() -> void:
	for leg in ["L1", "L2"]:
		var x := -0.04 if leg == "L1" else 0.04
		_points["line_" + leg] = {"pos": Vector3(x, 0.335, 0.066), "label": "Line lug %s (always hot)" % leg, "short": "Line " + leg}
		_points["bus_" + leg] = {"pos": Vector3(x, 0.212, 0.05), "label": "Bus %s" % leg, "short": "Bus " + leg}
		_clamps["main_" + leg] = {"pos": Vector3(x, 0.385, 0.05), "dir": Vector3.UP, "label": "Service conductor %s" % leg, "short": "Service " + leg}
	_points["neutral"] = {"pos": Vector3(-0.2, 0.235, 0.056), "label": "Neutral bar", "short": "N"}
	_points["neutral2"] = {"pos": Vector3(0.2, 0.235, 0.056), "label": "Neutral bar", "short": "N"}
	_points["ground"] = {"pos": Vector3(0.0, -0.33, 0.05), "label": "Ground bar", "short": "G"}
	for b in sim.circuits:
		for p: int in b.poles:
			var s := _side(p)
			var y := _y(p)
			var where := "%s, slot %d" % [b.name, p]
			_points["term_%d" % p] = {"pos": Vector3(s * TERM_X, y, 0.082), "label": where + " terminal", "short": "Brk %d" % p}
			_points["stab_%d" % p] = {"pos": Vector3(s * 0.04, y, 0.03), "label": "Bus tab, slot %d" % p, "short": "Stab %d" % p}
			# On the straight bit where the wire turns in to its terminal. Matches art/panel.py.
			_clamps["wire_%d" % p] = {"pos": Vector3(s * (TERM_X + 0.022), y, WIRE_Z), "dir": Vector3(s, 0, 0),
					"label": where + " hot wire", "short": "Brk %d" % p}


# --- What's under the mouse -------------------------------------------------------

func _pick_at(mouse: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for p: Dictionary in _picks():
		var world := to_global(p["pos"] as Vector3)
		if _cam.is_position_behind(world):
			continue
		var d := _cam.unproject_position(world).distance_to(mouse)
		if d < float(p.get("r", 24.0)) and d < best_d:
			best = p
			best_d = d
	return best


func _picks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match _tool:
		Tool.HAND:
			if not door_open:
				out.append({"kind": "door", "label": "Open the door", "pos": Vector3(0, 0, 0.11), "r": 260.0})
				return out
			out.append({"kind": "main", "label": "Main breaker %d A" % sim.main_rating, "pos": Vector3(0, 0.27, 0.095), "r": 40.0})
			for b in sim.circuits:
				if b.breaker.present:
					var s := _side(b.slot)
					for p: int in b.poles:
						var verb := "pull it" if not b.wire_landed else _state_word(b)
						out.append({"kind": "breaker", "slot": b.slot, "pos": Vector3(s * HANDLE_X, _y(p), 0.09),
								"label": "%d  %s  %d A  (%s)" % [b.slot, b.name, b.breaker.rating, verb]})
				elif not cover_on:
					var carrying := breaker_choice()
					var label: String = "Empty slot. Breakers are in the truck."
					if carrying > 0:
						label = "Clip in the %d A breaker%s" % [carrying, "  (right click: another size)" if inventory.bag_breakers().size() > 1 else ""]
					out.append({"kind": "slot", "slot": b.slot, "pos": Vector3(_side(b.slot) * 0.07, _y(b.slot), 0.06), "r": 34.0, "label": label})
		Tool.DRIVER:
			if door_open and cover_on:
				for i in SCREWS.size():
					if _screws_in[i]:
						out.append({"kind": "screw", "i": i, "pos": SCREWS[i], "label": "Cover screw", "r": 32.0})
			elif not cover_on:
				for b in sim.circuits:
					if b.breaker.present:
						var verb := "land the wire" if not b.wire_landed else "take the wire off"
						out.append({"kind": "terminal", "slot": b.slot, "pos": _points["term_%d" % b.poles[0]]["pos"],
								"label": "%s terminal: %s" % [b.name, verb]})
		Tool.METER:
			if cover_on:
				return out
			if ClampMeter.dial == ClampMeter.Mode.VOLTS or ClampMeter.dial == ClampMeter.Mode.OHMS:
				for id: String in _points:
					if _point_exists(id):
						var seated := id == _red or id == _black
						out.append({"kind": "probe", "id": id, "pos": _points[id]["pos"], "label": ("Take the probe off: " if seated else "") + _points[id]["label"]})
			elif ClampMeter.dial == ClampMeter.Mode.AMPS:
				for id: String in _clamps:
					out.append({"kind": "clamp", "id": id, "pos": _clamps[id]["pos"], "label": ("Take the clamp off: " if id == _clamped else "") + _clamps[id]["label"]})
	return out


## A breaker's terminal goes with it. The bus tab only shows once it's gone.
func _point_exists(id: String) -> bool:
	if id.begins_with("term_"):
		return sim.circuit_at(int(id.substr(5))).breaker.present
	if id.begins_with("stab_"):
		return not sim.circuit_at(int(id.substr(5))).breaker.present
	return true


func _state_word(b: Circuit) -> String:
	if b.breaker.tripped:
		return "tripped"
	return "on" if b.breaker.on else "off"


# --- Doing things -----------------------------------------------------------------

func _click_on(p: Dictionary, button: int) -> void:
	match p["kind"]:
		"door":
			_set_door(true)
		"screw":
			_remove_screw(p["i"])
		"main":
			sim.toggle_main()
			_snap()
			_say("Main breaker %s." % ("ON" if sim.main_on else "OFF"))
		"breaker":
			_hand_on_breaker(p["slot"])
		"slot":
			if button == MOUSE_BUTTON_RIGHT:
				_breaker_pick += 1        # the next size in the bag
			else:
				_clip_in(p["slot"])
		"terminal":
			_screw_terminal(p["slot"])
		"probe":
			if not _lift_probe(p["id"], button):
				if button == MOUSE_BUTTON_RIGHT or (_red != "" and _black == ""):
					_black = p["id"]
				else:
					_red = p["id"]
				_take_reading()
		"clamp":
			if p["id"] == _clamped:
				_clamped = ""
			else:
				_clamped = p["id"]
				_take_current()
	_sync()
	_refresh_buttons()
	_update_readouts()
	_update_held_tools()


## Clicking a point a probe is already on takes that probe off. If both are on
## the same point, the button says which one.
func _lift_probe(id: String, button: int) -> bool:
	if id == _black and (button == MOUSE_BUTTON_RIGHT or id != _red):
		_black = ""
		return true
	if id == _red:
		_red = ""
		return true
	return false


## Both probes and the clamp, whichever tool you've got in your hand.
func _take_leads_off() -> void:
	if _red == "" and _black == "" and _clamped == "":
		return
	_red = ""
	_black = ""
	_clamped = ""
	_say("Probes and clamp off.")
	_update_readouts()
	_update_held_tools()


func _hand_on_breaker(slot: int) -> void:
	var b := sim.circuit_at(slot)
	if not b.wire_landed:
		if sim.bus_live():
			_arc_flash()
			return
		sim.pull(slot)
		var term := "term_%d" % slot
		_red = "" if _red == term else _red
		_black = "" if _black == term else _black
		_snap()
		_say("Breaker out. There's the bus tab it was clipped onto.")
		return
	sim.toggle(slot)
	_snap()
	_say("%s: %s." % [b.name, _state_word(b)])


func _screw_terminal(slot: int) -> void:
	var b := sim.circuit_at(slot)
	if b.poles.size() > 1:
		_say("No double-pole stock on the truck. Leave the %s alone." % b.name)
		return
	if b.wire_landed:
		if sim.terminal_live(slot):
			_shock(slot)
			return
		sim.set_wire(slot, false)
		_say("Wire's off the terminal.")
	else:
		sim.set_wire(slot, true)
		_say("Wire landed and tight.")
	_snap()


## Which breaker from your bag goes in next, by rating (0 if you've none).
## Right click on an empty slot steps through the sizes you're carrying.
func breaker_choice() -> int:
	var sizes := inventory.bag_breakers()
	return sizes[posmod(_breaker_pick, sizes.size())] if not sizes.is_empty() else 0


func _clip_in(slot: int) -> void:
	var rating := breaker_choice()
	if rating == 0:
		_say("No breakers in your bag. They're in the truck.")
		return
	if sim.bus_live():
		_arc_flash()
		return
	sim.install(slot, rating)
	inventory.use(PartSpec.breaker_id(rating))
	job.part_used(slot, rating)
	_snap()
	_say("New %d A breaker clipped in, switched off. Land the wire." % rating)


func _remove_screw(i: int) -> void:
	_screws_in[i] = false
	_screw_meshes[i].visible = false
	_snap()
	if not _screws_in.has(true):
		cover_on = false
		cover_removed = true
		var t := create_tween()
		t.tween_property(_cover, "position", Vector3(0, 0, 0.9), 0.3)
		t.tween_callback(func() -> void: _cover.visible = false)
		_say("Cover off. Everything behind it is live.")


func _refit_cover() -> void:
	cover_on = true
	_screws_in = [true]
	for m in _screw_meshes:
		m.visible = true
	_cover.visible = true
	_cover.position = Vector3.ZERO
	_red = ""
	_black = ""
	_clamped = ""
	_snap()
	_refresh_buttons()
	_update_readouts()
	_update_held_tools()


func _set_door(open_it: bool) -> void:
	door_open = open_it
	_door.visible = true
	var t := create_tween()
	t.tween_property(_door, "rotation:y", -_corner * 2.0 if open_it else 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	if open_it:
		t.tween_callback(func() -> void: _door.visible = false)
	_refresh_buttons()


func _select_tool(t: int) -> void:
	_tool = t as Tool
	_tool_buttons[t].button_pressed = true
	_update_held_tools()


## Click the dial round. Whatever's already hooked up reads on the new setting.
func _turn_dial(step: int) -> void:
	ClampMeter.turn(step)
	_snap()
	_say("Dial: %s" % ClampMeter.setting())
	_take_reading()
	_take_current()
	_update_readouts()
	_update_held_tools()


static func _is_reference(id: String) -> bool:
	return id == "neutral" or id == "neutral2" or id == "ground"


## Both probes are down: note what the meter says on whatever the dial's on.
func _take_reading() -> void:
	if _red == "" or _black == "":
		return
	if ClampMeter.dial == ClampMeter.Mode.VOLTS:
		_take_voltage()
	elif ClampMeter.dial == ClampMeter.Mode.OHMS:
		_add_reading("%s to %s:  %s" % [_points[_red]["short"], _points[_black]["short"], _ohms_text()])


## Ohms only means anything dead. Neutral and ground are bonded in here, so
## they read near nothing to each other; anything else is open as far as the
## meter can tell.
func _ohms() -> float:
	if _red == _black or (_is_reference(_red) and _is_reference(_black)):
		return 0.2
	return -1.0


func _live_under_probes() -> bool:
	return sim.voltage(_red, "ground") > 5.0 or sim.voltage(_black, "ground") > 5.0


func _ohms_text() -> String:
	if _live_under_probes():
		return "voltage on it! Ohms is for dead circuits"
	var r := _ohms()
	return "OL (open)" if r < 0.0 else "%.1f ohms" % r


func _take_voltage() -> void:
	var v := sim.voltage(_red, _black)
	_add_reading("%s to %s:  %.1f V" % [_points[_red]["short"], _points[_black]["short"], v])
	var other := ""
	if _is_reference(_black):
		other = _red
	elif _is_reference(_red):
		other = _black
	if other == "":
		return
	var term := "term_%d" % target_slot
	var bus := "bus_" + ElectricalPanel.leg_of(target_slot)
	if other == term:
		work.measured_target = true
	if not sim.bus_live() and v < 5.0 and (other == term or other == bus):
		work.verified_dead = true


func _take_current() -> void:
	if _clamped == "" or ClampMeter.dial != ClampMeter.Mode.AMPS:
		return
	_add_reading("%s:  %.1f A" % [_clamps[_clamped]["short"], sim.current(_clamped)])
	if _clamped == "wire_%d" % target_slot:
		work.measured_amps = true


func _add_reading(line: String) -> void:
	_readings.push_front(line)
	if _readings.size() > MAX_READINGS:
		_readings.pop_back()


func _shock(slot: int) -> void:
	if inventory != null and inventory.insulated_gloves:
		_buzz()
		_say("Terminal %d was live! Your rubber gloves took it." % slot, 4.0)
		return
	work.shocks += 1
	_fade_flash(Color(0.75, 0.85, 1.0, 0.85), 0.5)
	_buzz()
	_say("ZAP! Terminal %d was live. That'll cost you." % slot, 4.0)


func _arc_flash() -> void:
	work.arcs += 1
	_fade_flash(Color(1.0, 0.98, 0.85, 1.0), 1.4)
	_buzz()
	_say("ARC FLASH! Never work the bus with the main on. Turn it off first.", 5.0)


func _on_tripped(slot: int) -> void:
	_snap()
	_sync()
	if _open:
		_say("Breaker %d just tripped." % slot)


func _say(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_t = seconds


func _fade_flash(c: Color, seconds: float) -> void:
	_flash.color = c
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, seconds)


## Where the job stands, written like an apprentice's next instruction.
func _hint() -> String:
	var t := sim.circuit_at(target_slot)
	var state := sim.check_repair(target_slot)
	if state == "ok" or state == "oversize" or state == "undersize":
		if not cover_on:
			return "Check it reads right, then refit the cover."
		if door_open:
			return "Close the door."
		return "Buttoned up. Step back and go talk to the customer."
	if not door_open:
		return "Click the door to open the panel."
	if cover_on:
		return "Screwdriver: take out the cover screw."
	if not work.measured_target:
		return "Find the circuit in the Panel Directory (Esc). Clamp meter on V~ (Q turns the dial): one probe on its terminal, the other on a neutral bar."
	if not work.measured_amps:
		return "Dial to A~ (Q) and clamp its hot wire. What's it pulling right now?"
	var trips: bool = t.breaker.fault == Breaker.Fault.WEAK or t.heater > 0.0
	if trips and not job.load_tested:
		return "Breaker reset and on, clamp on its wire, then go ask the customer to run the %s. Watch the amps when it goes." % (t.appliance if t.appliance != "" else "load")
	if t.heater > 0.0:
		return "It went over the rating, and the breaker did its job. Too much on one circuit: go tell the customer."
	if t.breaker.present and t.breaker.fault != Breaker.Fault.NONE:
		if inventory.bag_breakers().is_empty():
			return "Bad breaker? Fetch a replacement of the same rating from the back of the truck."
		if sim.bus_live():
			return "Main breaker off before you go near it."
		if not work.verified_dead:
			return "Test dead on V~: probe its terminal or the bus to neutral. Trust the meter, not the switch."
		if t.wire_landed:
			return "Breaker off, then Screwdriver on its terminal to free the wire."
		return "Hand: pull the old breaker."
	if not t.breaker.present:
		return "Hand: clip the new breaker into the empty slot."
	if not t.wire_landed:
		return "Screwdriver: land the wire on the new breaker."
	if not sim.service_on:
		return "The meter's pulled, so the whole house is dead. Plug it back in to test."
	if not sim.main_on:
		return "Main back on."
	return "Switch the new breaker on, then test it."


## The digits settle onto the value over a moment, like a real meter.
func _update_readouts() -> void:
	var both := _red != "" and _black != ""
	var v := sim.voltage(_red, _black) if both else 0.0
	_volts_shown = lerpf(_volts_shown, v, 0.65)
	var a := sim.current(_clamped) if _clamped != "" else 0.0
	_amps_shown = lerpf(_amps_shown, a, 0.65)
	var lcd := ""
	match ClampMeter.dial:
		ClampMeter.Mode.VOLTS:
			lcd = "%.1f" % clampf(_noisy(_volts_shown, 0.12), 0.0, 999.9)
		ClampMeter.Mode.OHMS:
			lcd = "OL" if not both or _ohms() < 0.0 else ("----" if _live_under_probes() else "%.1f" % _ohms())
		ClampMeter.Mode.AMPS:
			lcd = "%.1f" % _noisy(_amps_shown, 0.05)
	_held_meter.show_reading(lcd)
	_clamp.show_reading(lcd)
	_log.text = "\n".join(_readings) if not _readings.is_empty() else "Nothing measured yet."
	_notes.text = "\n".join(job.notes)
	_hint_label.text = _hint()


func _noisy(value: float, amount: float) -> float:
	if value < 0.5:
		return randf_range(0.0, 0.2)
	return value + randf_range(-amount, amount)


func _refresh_buttons() -> void:
	_door_button.visible = door_open and cover_on
	_cover_button.visible = not cover_on


# --- Tools in your hands ----------------------------------------------------------

## Where the mouse points on an imaginary sheet just in front of the guts.
func _cursor_point() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var from := to_local(_cam.project_ray_origin(mouse))
	var along := to_local(_cam.project_ray_origin(mouse) + _cam.project_ray_normal(mouse)) - from
	if absf(along.z) < 0.001:
		return Vector3(0, 0, 0.09)
	return from + along * ((0.09 - from.z) / along.z)


## Your hands and tools exist only while you're working. Walk away and you take them with you.
func _show_tools(on: bool) -> void:
	for n: Node3D in [_meter, _red_pen, _black_pen, _red_lead, _black_lead, _driver, _clamp, _work_hand, _work_sleeve, _work_cuff]:
		n.visible = on


func _update_held_tools() -> void:
	if not _open:
		return
	var at := _cursor_point()
	if not _hover.is_empty():
		at = _hover["pos"]
	var leads := _tool == Tool.METER and (ClampMeter.dial == ClampMeter.Mode.VOLTS or ClampMeter.dial == ClampMeter.Mode.OHMS)
	var red_in_hand := leads and _red == ""
	var black_in_hand := leads and _red != "" and _black == ""
	var holding_driver := _tool == Tool.DRIVER

	# The arm comes in from the lower corner of your view and reaches across,
	# with the back of the glove toward you so you can see the hand.
	var shoulder := to_local(_cam.to_global(Vector3(_work_side * 0.42, -0.5, -0.25)))
	var forward := Vector3(-_work_side * 0.62, 0.58, -0.52).normalized()
	var dorsal := Vector3(_work_side * 0.25, 0.3, 1.0)
	dorsal = (dorsal - forward * dorsal.dot(forward)).normalized()
	var hand_basis := Basis(dorsal.cross(-forward), dorsal, -forward)
	_tool_basis = Basis(Quaternion(Vector3.UP, (dorsal * 0.85 - forward * 0.45).normalized()))

	# The meter's in your off hand, unless its jaws are hanging on a wire.
	_clamp.visible = _clamped != ""
	if _clamped != "":
		_seat_clamp(_clamps[_clamped]["pos"], _clamps[_clamped]["dir"])
	_meter.visible = _clamped == "" and (_tool == Tool.METER or _red != "" or _black != "")
	_meter.position.y = -0.085 - (1.0 - _raise) * 0.3
	var on := _clamp if _clamped != "" else _held_meter
	_pose_pen(_red_pen, _red_lead, _red, red_in_hand, at, RED_PEN_DIR, on.red_jack)
	_pose_pen(_black_pen, _black_lead, _black, black_in_hand, at, BLACK_PEN_DIR, on.black_jack)
	_driver.visible = holding_driver
	if holding_driver:
		_driver.position = at
		_driver.basis = _tool_basis

	# Put the right part of the hand on the job.
	var pose := "point"
	var goal := at + Vector3.BACK * 0.006
	if red_in_hand or black_in_hand or holding_driver:
		pose = "pinch"
		goal = at + _tool_basis.y * 0.06
	if pose != _work_pose:
		_work_pose = pose
		_work_hand.set_pose(pose)
	var anchor := _work_hand.joint("index-finger-tip")
	if pose == "pinch":
		anchor = (_work_hand.joint("index-finger-tip") + _work_hand.joint("thumb-tip")) / 2.0
	var wrist := goal - hand_basis * anchor + Vector3.DOWN * (1.0 - _raise) * 0.45
	_work_hand.transform = Transform3D(hand_basis, wrist)
	_shape_arm(wrist, forward, shoulder)


## A two-bone arm: shoulder to elbow to wrist, wearing a work shirt.
func _shape_arm(wrist: Vector3, forward: Vector3, shoulder: Vector3) -> void:
	const UPPER := 0.32
	const FOREARM := 0.27
	var along := wrist - shoulder
	var reach := clampf(along.length(), 0.08, UPPER + FOREARM - 0.002)
	var axis := along.normalized()
	var x := (UPPER * UPPER - FOREARM * FOREARM + reach * reach) / (2.0 * reach)
	var pole := Vector3(_work_side * 0.7, -1.0, 0.2)
	pole = (pole - axis * pole.dot(axis)).normalized()
	var elbow := shoulder + axis * x + pole * sqrt(maxf(UPPER * UPPER - x * x, 0.0))
	var path := _smooth([wrist + forward * 0.012, wrist - forward * 0.07, elbow.lerp(wrist, 0.35), elbow, shoulder], 8)
	_work_sleeve.mesh = _tube(path, 0.0, 14, _arm_radii(path.size()))
	_work_cuff.mesh = _tube(_smooth([wrist + forward * 0.02, wrist - forward * 0.03, wrist - forward * 0.075], 3), 0.0, 14,
			PackedFloat32Array([0.036, 0.037, 0.038, 0.04, 0.042, 0.044, 0.046]))


## Thin at the wrist, fuller up the forearm, with the creases cloth gets.
func _arm_radii(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in count:
		var f := float(i) / (count - 1)
		out.append(lerpf(0.034, 0.047, smoothstep(0.0, 0.3, f)) + f * 0.008 + sin(f * 70.0) * 0.0009)
	return out


func _pose_pen(pen: Node3D, lead: MeshInstance3D, placed: String, in_hand: bool, at: Vector3, dir: Vector3, jack: Node3D) -> void:
	pen.visible = placed != "" or in_hand
	lead.visible = pen.visible
	if not pen.visible:
		return
	pen.position = _points[placed]["pos"] if placed != "" else at
	pen.basis = _tool_basis if placed == "" else Basis(Quaternion(Vector3.UP, dir.normalized()))
	var d := pen.basis.y
	var grip := pen.position + d * 0.125
	var end := to_local(jack.global_position)
	var mid := grip.lerp(end, 0.5) + Vector3.DOWN * 0.14
	lead.mesh = _tube(_smooth([grip, grip + d * 0.03, mid, end + Vector3.DOWN * 0.03, end]), 0.0028)


## Jaws round the wire, the meter hanging off it with its face turned toward
## you so you can read it.
func _seat_clamp(pos: Vector3, wire_dir: Vector3) -> void:
	const SIZE := 0.8                  # a touch small, so it doesn't hide half the panel
	var axis := (wire_dir + Vector3.BACK * 0.8).normalized()      # through the jaws
	var hint := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var up := (hint - axis * hint.dot(axis)).normalized()
	var b := Basis(up.cross(axis), up, axis)
	_clamp.transform = Transform3D(b.scaled_local(Vector3.ONE * SIZE), pos - b * ClampMeter.JAW_CENTRE * SIZE)


func _build_tools() -> void:
	_build_hand()
	_build_meter()
	var red := _m(Color(0.8, 0.08, 0.06), 0.0, 0.45)
	var black := _m(Color(0.07, 0.07, 0.08), 0.0, 0.45)
	_red_pen = _make_pen(RED_PEN_DIR, red)
	_black_pen = _make_pen(BLACK_PEN_DIR, black)
	_red_lead = _lead(red)
	_black_lead = _lead(black)

	_driver = Node3D.new()
	add_child(_driver)
	_cyl(_driver, 0.0035, 0.09, Vector3(0, 0.045, 0), _m(Color(0.75, 0.76, 0.78), 0.9, 0.3))
	_cyl(_driver, 0.013, 0.1, Vector3(0, 0.14, 0), _m(Color(0.9, 0.55, 0.08), 0.0, 0.45))

	_clamp = ClampMeter.new()
	add_child(_clamp)


## The clamp meter stays in your off hand, on the open side of the view.
func _build_meter() -> void:
	_meter = Node3D.new()
	_meter.position = Vector3(_corner * 0.125, -0.085, -0.3)
	_meter.rotation = Vector3(0.1, -_corner * 0.22, _corner * 0.1)
	_meter.scale = Vector3.ONE * 0.55
	_cam.add_child(_meter)
	_held_meter = ClampMeter.new()
	_meter.add_child(_held_meter)
	_build_holding_hand()


## Your other hand, behind the meter with its fingers round the edge. It lives in the meter's own space.
func _build_holding_hand() -> void:
	var h := _work_side                  # +1: it's your left hand
	var hand := HandRig.new()
	hand.is_right = h < 0.0
	hand.material = _glove_material()
	_meter.add_child(hand)
	var fingers := Vector3(h * 0.85, 0.5, 0.0).normalized()
	var back := Vector3(h * 0.12, 0.0, -1.0)
	back = (back - fingers * back.dot(fingers)).normalized()
	hand.transform = Transform3D(Basis(back.cross(-fingers), back, -fingers), Vector3(-h * 0.06, -0.16, -0.045))
	hand.set_pose.call_deferred("wrap", true)
	var wrist := hand.position
	var path := _smooth([wrist + fingers * 0.012, wrist - fingers * 0.07, wrist + Vector3(-h * 0.2, -0.26, -0.03), wrist + Vector3(-h * 0.36, -0.7, -0.06)], 8)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = _tube(path, 0.0, 14, _arm_radii(path.size()))
	sleeve.material_override = _sleeve_material()
	_meter.add_child(sleeve)
	var cuff := MeshInstance3D.new()
	cuff.mesh = _tube(_smooth([wrist + fingers * 0.02, wrist - fingers * 0.03, wrist - fingers * 0.075], 3), 0.0, 14,
			PackedFloat32Array([0.036, 0.037, 0.038, 0.04, 0.042, 0.044, 0.046]))
	cuff.material_override = _glove_material()
	_meter.add_child(cuff)


func _build_hand() -> void:
	_work_hand = HandRig.new()
	_work_hand.is_right = _work_side > 0.0
	_work_hand.material = _glove_material()
	add_child(_work_hand)
	_work_sleeve = MeshInstance3D.new()
	_work_sleeve.material_override = _sleeve_material()
	add_child(_work_sleeve)
	_work_cuff = MeshInstance3D.new()
	_work_cuff.material_override = _glove_material()
	add_child(_work_cuff)


func _sleeve_material() -> StandardMaterial3D:
	if _sleeve_mat == null:
		_sleeve_mat = Surfaces.photo("denim_fabric", 0.22, Color(0.3, 0.36, 0.5), false)
		_sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _sleeve_mat


func _glove_material() -> StandardMaterial3D:
	if _glove_mat == null:
		_glove_mat = HandRig.skin_material()
	return _glove_mat


## A test probe: its origin is the metal tip, the body runs back along `dir`.
func _make_pen(dir: Vector3, body: Material) -> Node3D:
	var pen := Node3D.new()
	pen.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	add_child(pen)
	_cyl(pen, 0.0014, 0.024, Vector3(0, 0.012, 0), _m(Color(0.8, 0.8, 0.82), 0.95, 0.25))
	_cyl(pen, 0.0055, 0.1, Vector3(0, 0.074, 0), body)
	_cyl(pen, 0.008, 0.004, Vector3(0, 0.03, 0), body)
	pen.visible = false
	return pen


func _lead(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


# --- Model ------------------------------------------------------------------------

func _build_model() -> void:
	# Everything but the tools and the yard comes from art/panel.py.
	var model: Node3D = (load("res://assets/panel/panel.glb") as PackedScene).instantiate()
	add_child(model)
	_main_handle = model.get_node("MainHandle")
	var main_label := _text(self, "MAIN  %d" % sim.main_rating, Vector3(0, 0.247, 0.0788), 24, Color(0.85, 0.85, 0.85))
	main_label.outline_size = 0
	_build_conduit()
	for b in sim.circuits:
		var hots: Array = []
		for pole: int in b.poles:
			hots.append({"landed": model.get_node("Hot%d_Landed" % pole), "freed": model.get_node("Hot%d_Freed" % pole),
					"burnt": model.get_node("Hot%d_Burnt" % pole)})
		_visuals[b.slot] = {"hots": hots}
		_build_breaker(b)
	_build_cover(model)
	_build_door(model)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0, FAR_VIEW)
	_cam.fov = 50.0
	_cam.near = 0.02
	# The yard behind the panel goes soft, like a camera focused on your hands.
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 1.9
	lens.dof_blur_far_transition = 2.5
	lens.dof_blur_amount = 0.14
	_cam.attributes = lens
	add_child(_cam)
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0, 0.3, 1.2)
	_lamp.rotation.x = -0.22
	_lamp.light_energy = 0.5
	_lamp.light_specular = 0.1       # no glare off the copper
	_lamp.spot_range = 3.0
	_lamp.spot_angle = 40.0
	_lamp.visible = false
	add_child(_lamp)
	_build_tools()
	var sign_label := Label3D.new()
	sign_label.text = "PANEL"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.0015
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(1.0, 0.7, 0.2)
	sign_label.position = Vector3(0, 0.55, 0.15)
	add_child(sign_label)


## The conduit from the meter: along the wall, up past the side of the panel,
## over the top and down into the service hub.
func _build_conduit() -> void:
	var m := to_local(meter_pos)
	var side := -1.0 if m.x < 0.0 else 1.0
	var past := side * (W / 2 + 0.06)
	var hub := Vector3(-0.02, H / 2 + 0.03, 0.05)
	var corners := [Vector3(m.x - side * 0.14, m.y - 0.1, 0.045), Vector3(past, m.y - 0.1, 0.045), Vector3(past, hub.y + 0.07, 0.045),
			Vector3(hub.x, hub.y + 0.07, 0.05), hub]
	var mi := MeshInstance3D.new()
	mi.mesh = _tube(_bent(corners, 0.06), 0.018, 16)
	mi.material_override = _m(Color(0.6, 0.62, 0.63), 0.8, 0.38)
	add_child(mi)


## A plug-on breaker from art/panel.py. It's modelled for the right-hand column,
## so the left-hand ones are mirrored.
func _build_breaker(b: Circuit) -> void:
	var slot: int = b.slot
	var poles: Array = b.poles
	var s := _side(slot)
	var root := Node3D.new()
	root.position.y = (_y(poles[0]) + _y(poles[-1])) / 2.0
	add_child(root)
	var file := "res://assets/panel/breaker_%dp.glb" % poles.size()
	var model: Node3D = (load(file) as PackedScene).instantiate()
	model.scale.x = s
	root.add_child(model)
	var state_text := _text(root, "ON", Vector3(s * HANDLE_X, 0, 0.0968), 18, Color(0.95, 0.95, 0.95))
	state_text.rotation.z = -PI / 2
	var label := _text(root, "", Vector3(s * 0.094, 0, 0.0707), 22, Color(0.92, 0.92, 0.92))
	var scorch := _box(root, Vector3(0.03, ROW * poles.size() - 0.007, 0.0012), Vector3(s * 0.094, 0, 0.0703), _m(Color(0.2, 0.1, 0.04), 0.0, 0.95))
	scorch.visible = false
	var v: Dictionary = _visuals[slot]
	v["root"] = root
	v["handle"] = model.get_node("Handle")
	v["state_text"] = state_text
	v["label"] = label
	v["scorch"] = scorch
	v["side"] = s


## The dead front and its screw come off together.
func _build_cover(model: Node3D) -> void:
	_cover = Node3D.new()
	add_child(_cover)
	model.get_node("DeadFront").reparent(_cover)
	var screw: MeshInstance3D = model.get_node("CoverScrew")
	screw.reparent(_cover)
	_screw_meshes.append(screw)
	for slot in range(1, 17):
		_text(_cover, str(slot), Vector3(_side(slot) * 0.126, _y(slot), 0.0975), 26, Color(0.12, 0.12, 0.12))


## Hinged on your side. The model's hinge is on its left, so it's mirrored when
## the hinge needs to be on the right. Once it's open you lift it off.
func _build_door(model: Node3D) -> void:
	_door = Node3D.new()
	_door.position = Vector3(-_corner * (W / 2 + 0.013), 0, DEPTH + 0.01)
	add_child(_door)
	var door: Node3D = model.get_node("Door")
	door.reparent(_door)
	door.position = Vector3.ZERO
	door.scale.x = _corner


func _m(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A round rod along the parent's Y axis.
func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## The corners joined by straight runs with a short bend at each corner, like real pipe or wire.
func _bent(corners: Array, bend: float) -> Array[Vector3]:
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


func _smooth(c: Array, per_span := 7) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := c.size()
	for i in n - 1:
		var p0: Vector3 = c[maxi(i - 1, 0)]
		var p1: Vector3 = c[i]
		var p2: Vector3 = c[i + 1]
		var p3: Vector3 = c[mini(i + 2, n - 1)]
		for k in per_span:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / per_span))
	out.append(c[n - 1])
	return out


func _tube(path: Array[Vector3], radius: float, sides := 7, radii := PackedFloat32Array()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var side := Vector3(0.31, 0.87, 0.38)
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		side = (side - t * side.dot(t)).normalized()
		var up := t.cross(side)
		for k in sides:
			var a := TAU * k / sides
			var n := side * cos(a) + up * sin(a)
			verts.append(path[i] + n * (radii[i] if not radii.is_empty() else radius))
			normals.append(n)
	for i in path.size() - 1:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			var c := a + sides
			var d := b + sides
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _text(parent: Node3D, text: String, pos: Vector3, size: int, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0005
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l


## Make the model match the electrics.
func _sync() -> void:
	_main_handle.position.y = 0.27 + (0.014 if sim.main_on else -0.014)
	for b in sim.circuits:
		var v: Dictionary = _visuals[b.slot]
		var s: float = v["side"]
		var offset := 0.0                # ON toward the centre, OFF away, tripped between
		if not b.breaker.tripped:
			offset = -0.012 if b.breaker.on else 0.012
		(v["root"] as Node3D).visible = b.breaker.present
		(v["handle"] as Node3D).position.x = HANDLE_X + offset       # inside the mirrored model
		(v["state_text"] as Label3D).position.x = s * (HANDLE_X + offset)
		(v["state_text"] as Label3D).text = "TRIP" if b.breaker.tripped else ("ON" if b.breaker.on else "OFF")
		(v["scorch"] as MeshInstance3D).visible = b.breaker.fault == Breaker.Fault.HOT
		(v["label"] as Label3D).text = "%d\n%dA" % [b.slot, b.breaker.rating]
		for hot: Dictionary in v["hots"]:
			(hot["landed"] as MeshInstance3D).visible = b.wire_landed
			(hot["freed"] as MeshInstance3D).visible = not b.wire_landed
			(hot["burnt"] as MeshInstance3D).visible = b.wire_landed and b.breaker.fault == Breaker.Fault.HOT


# --- Close-up screen --------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 4
	_ui.visible = false
	add_child(_ui)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_ui.add_child(_overlay)

	# The tool belt, bottom left.
	var belt := PanelContainer.new()
	belt.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	belt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	belt.offset_left = 14.0
	belt.offset_bottom = -14.0
	belt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	belt.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.08, 0.11, 0.93), 10, 8.0))
	_ui.add_child(belt)
	var slots := HBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_theme_constant_override("separation", 8)
	belt.add_child(slots)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		slots.add_child(_tool_slot(i, group))
	_tool_buttons[0].button_pressed = true

	# What to do next, and the buttons for the panel itself.
	var bar := VBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_bottom = -72.0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 8)
	_ui.add_child(bar)
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 22)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_hint_label.add_theme_constant_override("outline_size", 8)
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	bar.add_child(_hint_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_door_button = _ui_button(row, "Close door")
	_door_button.pressed.connect(_set_door.bind(false))
	_cover_button = _ui_button(row, "Refit cover")
	_cover_button.pressed.connect(_refit_cover)

	# Your notebook, Tab to get it out.
	_notes_panel = PanelContainer.new()
	_notes_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_notes_panel.offset_left = -520.0
	_notes_panel.offset_top = 80.0
	_notes_panel.offset_right = -20.0
	_notes_panel.offset_bottom = -110.0
	_notes_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.93, 0.82, 0.97)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(20)
	_notes_panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(_notes_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_notes_panel.add_child(col)
	_heading(col, "READINGS")
	_log = _ui_label(col, 20, Color(0.1, 0.12, 0.3))
	_heading(col, "CUSTOMER SAID")
	_notes = _ui_label(col, 18, Color(0.1, 0.12, 0.3))
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 80.0
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ui.add_child(_toast)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)


func _flat(bg: Color, radius: int, margin: float) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = bg
	f.set_corner_radius_all(radius)
	f.set_content_margin_all(margin)
	return f


## One square on the tool belt: its number, a little drawing of the tool, gold when picked.
func _tool_slot(i: int, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 88)
	b.tooltip_text = TOOL_NAMES[i]
	var idle := _flat(Color(0.12, 0.14, 0.18), 7, 4.0)
	var picked := _flat(Color(0.2, 0.17, 0.08), 7, 4.0)
	picked.set_border_width_all(3)
	picked.border_color = Color(0.98, 0.73, 0.16)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", idle)
	b.add_theme_stylebox_override("pressed", picked)
	b.add_theme_stylebox_override("hover_pressed", picked)
	b.pressed.connect(_select_tool.bind(i))
	var icon := Control.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_tool_icon.bind(icon, i))
	b.add_child(icon)
	var number := _ui_label(b, 16, Color(0.95, 0.95, 0.95))
	number.text = str(i + 1)
	number.position = Vector2(7, 3)
	_tool_buttons.append(b)
	return b


func _draw_tool_icon(c: Control, i: int) -> void:
	var o := Vector2(44, 48)
	match i:
		Tool.HAND:
			var glove := Color(0.55, 0.56, 0.6)
			c.draw_circle(o + Vector2(0, 12), 16.0, glove)
			for k in 4:
				c.draw_line(o + Vector2(-13 + k * 9, 4), o + Vector2(-13 + k * 9, -20), glove, 7.0, true)
			c.draw_line(o + Vector2(-13, 14), o + Vector2(-26, 2), glove, 7.0, true)
		Tool.DRIVER:
			c.draw_line(o + Vector2(-24, 24), o + Vector2(-6, 6), Color(0.95, 0.55, 0.08), 11.0, true)
			c.draw_line(o + Vector2(-6, 6), o + Vector2(24, -24), Color(0.8, 0.82, 0.85), 4.0, true)
		Tool.METER:
			ClampMeter.draw_icon(c, o)


func _ui_label(parent: Node, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l


func _heading(parent: Control, text: String) -> void:
	_ui_label(parent, 16, Color(0.7, 0.3, 0.05)).text = text


func _ui_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 20)
	parent.add_child(b)
	return b


## The hover ring and what you're pointing at.
func _draw_overlay() -> void:
	if _hover.is_empty():
		return
	var pos := _screen(_hover["pos"])
	var ring := minf(float(_hover.get("r", 24.0)), 18.0)
	_overlay.draw_arc(pos, ring, 0.0, TAU, 32, Color(1.0, 0.8, 0.2, 0.8), 2.0, true)
	Hud.draw_tag(_overlay, get_viewport().get_mouse_position() + Vector2(26, -10), _hover["label"])


func _screen(local: Vector3) -> Vector2:
	return _cam.unproject_position(to_global(local))


# --- Sound ------------------------------------------------------------------------

func _build_sound() -> void:
	_click = AudioStreamPlayer.new()
	_click.stream = _noise_burst(0.04, 0.5)
	add_child(_click)


func _snap() -> void:
	_click.pitch_scale = randf_range(0.9, 1.15)
	_click.play()


func _buzz() -> void:
	_click.pitch_scale = 0.25
	_click.play()


func _noise_burst(seconds: float, level: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var fade := 1.0 - float(i) / n
		data.encode_s16(i * 2, int(randf_range(-1.0, 1.0) * fade * fade * level * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
