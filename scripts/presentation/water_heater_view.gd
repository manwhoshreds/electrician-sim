class_name WaterHeaterView
extends Interactable
## The water heater in the laundry, and the close-up where you work on it.
## The electrics and the water are the WaterHeater (domain); this is the
## model (assets/water_heater, built by art/water_heater_covers.py), the
## camera, and your tools, turning clicks into its commands.
##
## Hand: the cold shut-off, the drain (a garden hose on it first, run outside;
##   right click takes the hose back off), the red reset, covers back on, a
##   new element in.
## Water on the floor (the drain open with no hose, an element out under
##   water) and it's a flood: `flooded` goes to ServiceCall, and they throw
##   you out.
## Screwdriver: cover screws off, element wires off and back on.
## Clamp meter: Q turns the dial. V~ and Ω: left click the red probe, right
##   click the black (ohms with the power off only). A~: clamp the supply wire
##   or an element's wire.
## Element wrench: the element out. Wait till the water's below it.
## The disconnect on the wall beside it (W from the top of the tank): Hand
##   opens its door and pulls the handle out (off) or pushes it back in (on).
## W / S: look at the next thing up or down the tank.

enum Tool { HAND, DRIVER, METER, WRENCH }

## The laundry's under water. ServiceCall deals with the customer.
signal flooded

const TOOL_NAMES := ["Hand", "Screwdriver", "Clamp meter", "Element wrench"]
const CLOSEUP_KEYS := [["LMB", "Use Tool"], ["RMB", "Black Probe"], ["Q", "Turn Dial"], ["W/S", "Look Up/Down"], ["R", "Leads Off"], ["Esc", "Step Back"]]
const POLES := WaterHeater.POLES
## What you look at, top to bottom, and the model node each is centred on.
const FOCUS: Array[String] = ["disconnect", "cold", "upper", "lower", "drain"]
const FOCUS_NODE := {"cold": "ColdWaterInlet_ShutoffValve", "upper": "UpperCompartment", "lower": "LowerCompartment", "drain": "DrainValve"}
## Meter points and the model node each one is on.
const POINT_NODE := {"l1": "UpperThermostat_ScrewL1", "l2": "UpperThermostat_ScrewL2", "u_a": "UpperElement_ScrewA",
	"u_b": "UpperElement_ScrewB", "lo_a": "LowerElement_ScrewA", "lo_b": "LowerElement_ScrewB"}
const POINT_NAME := {"l1": "L1 supply screw", "l2": "L2 supply screw", "u_a": "upper element screw", "u_b": "upper element screw (L2 side)",
	"lo_a": "lower element screw", "lo_b": "lower element screw (L2 side)", "tank": "bare tank (ground)",
	"dl1": "disconnect line lug L1 (from the panel)", "dl2": "disconnect line lug L2 (from the panel)"}

var heater: WaterHeater
var sim: ElectricalPanel
var model: Node3D
var inventory: Inventory
var job: ActiveJob
var van: Van
## What you did here, for the job card and the bill.
var work := WorkLog.new()
## Read each element with the ohmmeter, power off: "upper"/"lower" -> true.
var ohmed := {}
## New elements you put in, and ones that burnt out dry.
var fitted := 0
var dry_fires := 0

var _open := false
var _player: Node3D
var _tool := Tool.HAND
var _focus := "upper"
var _red := ""
var _black := ""
var _clamped := ""               # "supply", "upper" or "lower": the wire the jaws are round
var _hover := {}
var _zoom := 0.3
var _cam: Camera3D
var _hose_mesh: MeshInstance3D   # the garden hose off the drain, across the floor and away
var _element_home := {}          # "upper"/"lower" -> the element's transform, screwed in
var _animating := {}             # "upper"/"lower" -> true while it's being screwed in or out
var _streams := {}               # "upper", "lower", "drain" -> the water pouring out of it
var _puddle: MeshInstance3D
var _disc: Node3D                # the disconnect on the wall: box, door, pull-out handle
var _disc_door: Node3D
var _disc_handle: Node3D
var _disc_open := false          # its door
var _meter: ClampMeter           # in your other hand, bottom left of the view
var _lamp: SpotLight3D
var _ui: CanvasLayer
var _overlay: Control
var _tool_buttons: Array[Button] = []
var _hint: Label
var _readout: Label
var _toast: Label
var _toast_t := 0.0
var _flash: ColorRect


func _ready() -> void:
	super()
	prompt = "[E] Work on the water heater"
	on_use = open
	reach = 1.4
	facing = Vector3.BACK
	aim = Vector3(0, 0.9, 0.2)
	aim_radius = 0.32
	height_range = Vector2(-0.6, 0.6)
	_build_closeup()
	_build_ui()
	_refresh()


func _node(name: String) -> Node3D:
	return model.find_child(name, true, false) as Node3D


func _process(delta: float) -> void:
	heater.tick(delta)
	for e in heater.events:
		if e.begins_with("dry_fire"):
			dry_fires += 1
			if job != null:
				job.wrong_parts += 1
			_say("Pop, and a hiss. The %s element came on out of the water and burnt out." % e.get_slice(":", 1), 5.0)
		elif e == "flood":
			_say("Water's all over the floor and running under the washer.", 5.0)
			flooded.emit()
	heater.events.clear()
	if _hose_mesh != null:
		_hose_mesh.visible = heater.hose
	_show_water()
	if heater.amps() > 0.0:
		sim.demo["%d:water heater" % POLES[0]] = 1.0
	else:
		sim.demo.erase("%d:water heater" % POLES[0])
	if not _open:
		return
	_zoom = clampf(_zoom, 0.0, 1.0)
	var at := _focus_point()
	_cam.global_position = at + global_basis * Vector3(0.05, 0.02, lerpf(0.42, 0.22, _zoom))
	_cam.look_at(at, Vector3.UP)
	_hover = _pick_at(get_viewport().get_mouse_position())
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_hint.text = _hint_text()
	_readout.text = _readout_text()
	_meter.visible = _tool == Tool.METER or _red != "" or _black != "" or _clamped != ""
	_meter.show_reading(_lcd())
	_overlay.queue_redraw()


func _focus_point() -> Vector3:
	if _focus == "disconnect" and _disc != null:
		return _disc.global_position
	var n := _node(FOCUS_NODE.get(_focus, "UpperCompartment"))
	var p := n.global_position if n != null else global_position + Vector3(0, 1.0, 0)
	if _focus == "cold":
		p += Vector3(0, 0.36, 0)      # the valve body sits up its pipe
	return p


# --- In and out ------------------------------------------------------------------------

func open(p: Node3D) -> void:
	_player = p
	_open = true
	p.target = self
	p.hud.set_closeup(true, CLOSEUP_KEYS)
	_cam.make_current()
	_lamp.visible = true
	_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	_player.target = null
	_player.hud.set_closeup(false)
	_player.camera.make_current()
	_lamp.visible = false
	_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_red = ""
				_black = ""
				_clamped = ""
			KEY_Q:
				turn_dial(-1 if event.shift_pressed else 1)
			KEY_W:
				look(-1)
			KEY_S:
				look(1)
			_:
				var i: int = event.physical_keycode - KEY_1
				if i < 0 or i >= TOOL_NAMES.size():
					return
				select_tool(i as Tool)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom += 0.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.15
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var p := _pick_at(event.position)
			if not p.is_empty():
				click(p["kind"], p.get("what", ""), event.button_index == MOUSE_BUTTON_RIGHT)
		get_viewport().set_input_as_handled()


## Up (-1) or down (1) the tank.
func look(step: int) -> void:
	_focus = FOCUS[clampi(FOCUS.find(_focus) + step, 0, FOCUS.size() - 1)]


func select_tool(t: Tool) -> void:
	_tool = t
	_tool_buttons[t].button_pressed = true


## Click the meter's dial round. Whatever's hooked up reads on the new setting.
func turn_dial(step := 1) -> void:
	ClampMeter.turn(step)
	_say("Dial: %s" % ClampMeter.setting(), 1.5)
	_take_reading()


# --- What you can click -----------------------------------------------------------------

## The things you can click with the tool in your hand: {kind, what, pos (world), label}.
func picks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for which: String in WaterHeater.ELEMENTS:
		var cap := which.capitalize()
		var cover := _node("%sThermostatCover" % cap)
		var centre := _node("%sCompartment" % cap).global_position
		if heater.cover_on[which]:
			if _tool == Tool.DRIVER and cover != null:
				out.append({"kind": "cover_off", "what": which, "pos": _node("%sThermostatCover_ScrewTop" % cap).global_position,
					"label": "Cover screws: take the %s cover off" % which})
			continue
		match _tool:
			Tool.HAND:
				out.append({"kind": "cover_on", "what": which, "pos": centre + global_basis * Vector3(0.045, 0.045, 0.02),
					"label": "Put the %s cover back on" % which})
				if which == "upper":
					out.append({"kind": "reset", "pos": _node("UpperThermostat_Reset").global_position, "label": "Red RESET button (high-limit)"})
				if heater.element[which] == "out":
					out.append({"kind": "fit", "what": which, "pos": _element_pos(which), "label": "Screw a new element in"})
			Tool.DRIVER:
				out.append({"kind": "wires", "what": which, "pos": _node("%sElement_ScrewA" % cap).global_position,
					"label": "Element screws: %s" % ("take the wires off" if heater.wired[which] else "put the wires back on")})
			Tool.METER:
				if ClampMeter.dial == ClampMeter.Mode.VOLTS or ClampMeter.dial == ClampMeter.Mode.OHMS:
					for point: String in POINT_NODE:
						if WaterHeater.element_of(point) == which or (which == "upper" and point in ["l1", "l2"]):
							out.append({"kind": "probe", "what": point, "pos": _point_pos(point), "label": POINT_NAME[point]})
					out.append({"kind": "probe", "what": "tank", "pos": _tank_pos(which), "label": POINT_NAME["tank"]})
				elif ClampMeter.dial == ClampMeter.Mode.AMPS:
					if which == "upper":
						out.append({"kind": "clamp", "what": "supply", "pos": _point_pos("l1") + global_basis * Vector3(0, 0.02, 0),
							"label": ("Take the clamp off: " if _clamped == "supply" else "") + "L1 supply wire"})
					out.append({"kind": "clamp", "what": which, "pos": _point_pos("u_a" if which == "upper" else "lo_a") + global_basis * Vector3(-0.015, 0, 0),
						"label": ("Take the clamp off: " if _clamped == which else "") + "%s element's wire" % which.capitalize()})
			Tool.WRENCH:
				if heater.element[which] != "out":
					out.append({"kind": "unscrew", "what": which, "pos": _element_pos(which), "label": "Unscrew the %s element" % which})
	if _disc != null:
		var front := _disc.global_basis.z
		if _tool == Tool.HAND:
			if not _disc_open:
				out.append({"kind": "disc_door", "pos": _disc.global_position + front * 0.06, "label": "Water heater disconnect: open the door"})
			else:
				out.append({"kind": "pullout", "pos": _disc.global_position + front * 0.05 + _disc.global_basis.y * 0.03,
					"label": "Pull the handle out (heater off)" if heater.disconnect_in else "Push the handle back in (heater on)"})
				out.append({"kind": "disc_door", "pos": _disc_door.global_position + front * 0.02 + _disc.global_basis.y * -0.08,
					"label": "Close the disconnect door"})
		elif _tool == Tool.METER and _disc_open and not heater.disconnect_in and \
				(ClampMeter.dial == ClampMeter.Mode.VOLTS or ClampMeter.dial == ClampMeter.Mode.OHMS):
			for k: String in ["dl1", "dl2"]:
				out.append({"kind": "probe", "what": k, "pos": _point_pos(k), "label": POINT_NAME[k]})
	if _tool == Tool.HAND:
		var handle := _node("ColdWaterInlet_ShutoffHandle")
		if handle != null:
			out.append({"kind": "cold", "pos": _node("ColdWaterInlet_ShutoffValve").global_position + Vector3(0, 0.375, 0),
				"label": "Cold water shut-off: turn it %s" % ("off" if heater.cold_open else "on")})
		var drain_at := _node("DrainValve_Handle").global_position + global_basis * Vector3(0, 0, 0.055)
		if not heater.hose and not heater.drain_open and inventory != null and inventory.has("GardenHose"):
			out.append({"kind": "hose", "pos": drain_at, "label": "Drain valve: screw the garden hose on and run it outside"})
		elif heater.hose:
			out.append({"kind": "drain", "pos": drain_at, "label": "Drain valve: %s" % ("close it" if heater.drain_open else
					"open it (the hose runs outside)   right click: hose off")})
		else:
			out.append({"kind": "drain", "pos": drain_at, "label": "Drain valve: %s" % ("close it!" if heater.drain_open else
					"open it (no hose on it: straight onto the floor)")})
	return out


func _point_pos(point: String) -> Vector3:
	if point == "dl1" or point == "dl2":
		return _disc.global_transform * Vector3(-0.03 if point == "dl1" else 0.03, 0.07, 0.03)
	return _node(POINT_NODE[point]).global_position + global_basis * Vector3(0, 0, 0.003)


func _tank_pos(which: String) -> Vector3:
	return _node("%sCompartment" % which.capitalize()).global_position + global_basis * Vector3(0.045, -0.05, 0.002)


func _element_pos(which: String) -> Vector3:
	return _node("%sElement" % which.capitalize()).global_position + global_basis * Vector3(0, 0, 0.012)


func _pick_at(mouse: Vector2) -> Dictionary:
	var best := {}
	var best_d := 22.0
	for p: Dictionary in picks():
		if _cam.is_position_behind(p["pos"]):
			continue
		var d := _cam.unproject_position(p["pos"]).distance_to(mouse)
		if d < best_d:
			best = p
			best_d = d
	return best


## Does a click: `kind` and `what` as in picks(). `right`: the black probe.
func click(kind: String, what := "", right := false) -> void:
	match kind:
		"cover_off":
			heater.cover_on[what] = false
		"cover_on":
			heater.cover_on[what] = true
		"reset":
			if heater.eco_tripped:
				heater.reset_eco()
				work.worked_on = true
				_say("Click. The high-limit resets.")
			else:
				_say("It's not tripped.")
		"wires":
			if _live_screws(what):
				_shock()
				return
			heater.wired[what] = not heater.wired[what]
			work.worked_on = true
		"unscrew":
			if heater.wired[what]:
				_say("Take the wires off its screws first.")
			elif not heater.can_unscrew(what):
				heater.unscrew(what)           # under water: the tank comes out after it
				_animate_element(what, true)
				work.worked_on = true
				_say("Water blasts out of the hole! %s" % ("The cold's still on!" if heater.cold_open else "The tank's still full above it!"), 5.0)
			else:
				heater.unscrew(what)
				_animate_element(what, true)
				work.worked_on = true
				_say("Out it comes, with a splash of rusty water.")
		"fit":
			if not inventory.has("Element"):
				_say("No new element in your bag. Check the %s." % van.spec()["word"] if van != null else "You need a new element.")
				return
			heater.fit(what)
			_animate_element(what, false)
			inventory.use("Element")
			fitted += 1
			work.worked_on = true
			if job != null:
				job.final_device = "Element"
				if not (job.kind == "wh_%s" % what):
					job.wrong_parts += 1          # a good element replaced for nothing
			_say("New element in, gasket seated.")
		"disc_door":
			_disc_open = not _disc_open
			if _disc_door != null:
				create_tween().tween_property(_disc_door, "rotation:y", -1.9 if _disc_open else 0.0, 0.35) \
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		"pullout":
			heater.disconnect_in = not heater.disconnect_in
			_slide_pullout(heater.disconnect_in)
			_say("Handle out. The water heater's off, whatever the breaker says. Test it dead." if not heater.disconnect_in
					else "Handle back in. The heater's got power again.")
		"cold":
			heater.cold_open = not heater.cold_open
			_say("Cold water off. Nothing's going into the tank now." if not heater.cold_open else "Cold water back on. The tank fills from the street.")
		"hose":
			if inventory.use("GardenHose"):
				heater.hose = true
				_say("Hose on the drain, run across the floor and out the back door.")
		"drain":
			if right and heater.hose and not heater.drain_open:
				heater.hose = false
				inventory.carry("GardenHose")
				_say("Hose off the drain and coiled up in your bag.")
			else:
				heater.drain_open = not heater.drain_open
				if heater.drain_open and not heater.hose:
					_say("Water's pouring out onto the floor! Shut it!", 3.0)
				elif heater.drain_open:
					_say("Drain open. Down the hose and out in the yard." if not heater.cold_open else "Drain open, but the cold's still on: it'll just run through.")
		"probe":
			if right:
				_black = what
			else:
				_red = what
			_take_reading()
		"clamp":
			_clamped = "" if _clamped == what else what
	_refresh()


func _live_screws(which: String) -> bool:
	var pair := ["u_a", "u_b"] if which == "upper" else ["lo_a", "lo_b"]
	return heater.is_live(pair[0]) or heater.is_live(pair[1])


func _shock() -> void:
	if inventory != null and inventory.insulated_gloves:
		_say("That's live! Your rubber gloves took it. Breaker off first.", 4.0)
		return
	work.shocks += 1
	_fade_flash(Color(1.0, 1.0, 1.0, 1.0), 1.2)
	_say("ZAP! That's live. Breaker off at the panel, and test it dead first.", 4.0)


# --- The meter --------------------------------------------------------------------------

func _probes_live() -> bool:
	return heater.is_live(_red) or heater.is_live(_black)


func _take_reading() -> void:
	if _red == "" or _black == "" or ClampMeter.dial == ClampMeter.Mode.OFF or ClampMeter.dial == ClampMeter.Mode.AMPS:
		return
	if ClampMeter.dial == ClampMeter.Mode.OHMS:
		if _probes_live():
			return
		var which := WaterHeater.element_of(_red)
		if which != "" and which == WaterHeater.element_of(_black) and _red != _black:
			ohmed[which] = heater.ohms(_red, _black)
		return
	var v := heater.voltage(_red, _black)
	var hot := _red != "tank" or _black != "tank"
	if not hot:
		return
	if heater.powered() and v > 200.0:
		if not work.worked_on:
			work.measured_live = true
		elif heater.fixed():
			work.tested_after = true
	if not heater.powered() and v < 5.0 and (_red in ["l1", "l2"] or _black in ["l1", "l2"]):
		work.verified_dead = true


## Amps through the wire the jaws are round: the whole heater on the supply,
## or one element.
func _amps() -> float:
	if _clamped == "supply":
		return heater.amps()
	if _clamped != "":
		return WaterHeater.ELEMENT_AMPS if heater.heating(_clamped) else 0.0
	return 0.0


## What the meter says, in words, on whatever the dial's on.
func reading() -> String:
	match ClampMeter.dial:
		ClampMeter.Mode.OFF:
			return "it's off. Q turns the dial"
		ClampMeter.Mode.AMPS:
			return "clamp a wire" if _clamped == "" else "%.1f A" % _amps()
	if _red == "" or _black == "":
		return "place both probes"
	if ClampMeter.dial == ClampMeter.Mode.OHMS:
		if _probes_live():
			return "voltage on it! Ohms is for dead circuits"
		var r := heater.ohms(_red, _black)
		return "OL (open)" if r < 0.0 else "%.1f ohms" % r
	return "%.1f V" % heater.voltage(_red, _black)


## The digits on the meter's display.
func _lcd() -> String:
	match ClampMeter.dial:
		ClampMeter.Mode.AMPS:
			return "%.1f" % _amps()
		ClampMeter.Mode.VOLTS:
			return "%.1f" % (heater.voltage(_red, _black) if _red != "" and _black != "" else 0.0)
		ClampMeter.Mode.OHMS:
			if _red == "" or _black == "":
				return "OL"
			if _probes_live():
				return "----"
			var r := heater.ohms(_red, _black)
			return "OL" if r < 0.0 else "%.1f" % r
	return ""


# --- Showing it -------------------------------------------------------------------------

func _refresh() -> void:
	if model == null:
		return
	for which: String in WaterHeater.ELEMENTS:
		var cap := which.capitalize()
		var cover := _node("%sThermostatCover" % cap)
		if cover != null:
			cover.visible = heater.cover_on[which]
		var element := _node("%sElement" % cap)
		if element != null:
			element.visible = heater.element[which] != "out" or _animating.has(which)
		for tag in ["A", "B"]:
			var w := _node("%sElement_Wire%s" % [cap, tag])
			if w != null:
				w.visible = heater.wired[which]
	var handle := _node("ColdWaterInlet_ShutoffHandle")
	if handle != null:
		handle.rotation.y = 0.0 if heater.cold_open else PI / 2   # in line with the pipe is open
	var drain := _node("DrainValve_Handle")
	if drain != null:
		drain.rotation.z = PI / 2 if heater.drain_open else 0.0


func _hint_text() -> String:
	if inventory != null and inventory.has("Element") and (heater.element["upper"] == "out" or heater.element["lower"] == "out"):
		return "Hand (1): screw the new element in."
	if heater.buttoned_up():
		if work.worked_on and heater.fixed():
			return "Done. Go tell them the hot water's on its way."
		return "Screwdriver (2): take a cover off. W/S to look up and down the tank."
	if not work.measured_live and not work.worked_on and heater.powered():
		return "Clamp meter (3) on V~ (Q turns the dial): L1 to L2 for the supply, then across each element's two screws."
	for which: String in WaterHeater.ELEMENTS:
		if heater.element[which] == "out":
			return "Empty hole. Get a new element and Hand (1) screw it in."
	if heater.powered() and not work.worked_on:
		return "Kill the power: pull the disconnect on the wall (W from the top of the tank), or the breaker at the panel. Then test L1 to L2 dead."
	if not heater.powered() and heater.level < 1.0 and not heater.drain_open and heater.cold_open:
		return "Filling. Keep the power off till it's full, or the element burns out dry."
	var bad := ""                      # a burnt-out element you've found with the meter, still in
	for which: String in WaterHeater.ELEMENTS:
		if float(ohmed.get(which, 0.0)) < 0.0 and heater.element[which] != "out":
			bad = which
	if bad != "" and not heater.powered():
		if heater.can_unscrew(bad):
			return "Screwdriver (2): wires off the %s element first." % bad if heater.wired[bad] else "Wrench (4): unscrew the %s element." % bad
		if heater.cold_open:
			return "Shut the cold water off before it comes out: W to look up the tank, Hand on the blue handle."
		if not heater.hose:
			if inventory != null and inventory.has("GardenHose"):
				return "Garden hose on the drain: S down to the bottom, Hand on the drain valve. It runs outside."
			return "You'll need to drain it. There's a garden hose on the %s." % (van.spec()["word"] if van != null else "truck")
		if not heater.drain_open:
			return "Open the drain (Hand). The hose takes the water outside."
		return "Draining out to the yard. Wait till it's below the %s element (%d%% now)." % [bad, int(heater.level * 100)]
	if heater.drain_open and work.worked_on and heater.element["upper"] != "out" and heater.element["lower"] != "out":
		return "New element's in. Close the drain, then cold water back on to fill it."
	if heater.drain_open:
		return "Draining. Wrench (4) the element out once the water's below it."
	if not heater.powered() and work.worked_on and heater.element["upper"] != "out" and heater.element["lower"] != "out" \
			and heater.wired["upper"] and heater.wired["lower"] and heater.level >= 1.0:
		return "Full and wired. Power back on (disconnect handle in, breaker on), then check volts across the element."
	if not heater.powered():
		return "Clamp meter on Ω: across an element's two screws. A good one reads about 13 ohms."
	return "Covers back on when you're done."


func _readout_text() -> String:
	var parts: Array[String] = []
	if _tool == Tool.METER or (_red != "" and _black != "") or _clamped != "":
		parts.append("Meter (%s):  %s" % [ClampMeter.setting(), reading()])
	if heater.level < 1.0:
		parts.append("Tank: %d%% full%s" % [int(heater.level * 100), ", draining" if heater.drain_open else (", filling" if heater.cold_open else "")])
	if not heater.cold_open or heater.drain_open or heater.hose:
		parts.append("Cold water %s   Drain %s   %s" % ["on" if heater.cold_open else "OFF", "OPEN" if heater.drain_open else "shut",
				"Hose run outside" if heater.hose else "No hose"])
	return "\n".join(parts)


func _say(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_t = seconds


func _fade_flash(c: Color, seconds: float) -> void:
	_flash.color = c
	create_tween().tween_property(_flash, "color:a", 0.0, seconds)


func _build_closeup() -> void:
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.01
	add_child(_cam)
	_meter = ClampMeter.new()
	_meter.position = Vector3(-0.13, -0.11, -0.3)
	_meter.rotation = Vector3(0.1, 0.22, -0.1)
	_meter.scale = Vector3.ONE * 0.5
	_meter.visible = false
	_cam.add_child(_meter)
	_build_hose.call_deferred()
	_build_disconnect.call_deferred()
	_build_water.call_deferred()
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0.1, 1.6, 0.9)
	_lamp.light_energy = 0.6
	_lamp.spot_range = 3.0
	_lamp.spot_angle = 40.0
	_lamp.visible = false
	add_child(_lamp)
	_lamp.look_at_from_position(_lamp.position, Vector3(0, 0.8, 0), Vector3.UP)


# --- Things moving: the element, the water ---------------------------------------------------

## Straight out of the tank from this element, level with it.
func _outward(which: String) -> Vector3:
	var at: Vector3 = (_element_home[which] as Transform3D).origin
	var d := at - Vector3(global_position.x, at.y, global_position.z)
	return d.normalized() if d.length() > 0.001 else global_basis.z


## The element unscrewing: it turns and backs out of the tank, the long folded
## rod sliding out after it, then you set it down. `fitting` the other way: a
## new one goes in and screws home.
func _animate_element(which: String, out: bool) -> void:
	var element := _node("%sElement" % which.capitalize())
	if element == null or not _element_home.has(which):
		return
	var home: Transform3D = _element_home[which]
	var away := _outward(which)
	var turns := 5.0
	_animating[which] = true
	element.visible = true
	var tween := create_tween()
	tween.tween_method(func(f: float) -> void:
		var t := Transform3D(home.basis.rotated(away, f * turns * TAU), home.origin + away * f * (ELEMENT_ROD + 0.03))
		element.global_transform = t,
		0.0 if out else 1.0, 1.0 if out else 0.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if out:
		tween.tween_interval(0.5)
	tween.tween_callback(func() -> void:
		_animating.erase(which)
		element.global_transform = home
		_refresh())


## How long the heating rod is, from the head into the tank.
const ELEMENT_ROD := 0.3


## The part of each element you never see till it comes out: a copper loop
## from the head back into the water.
func _build_rods() -> void:
	for which: String in WaterHeater.ELEMENTS:
		var element := _node("%sElement" % which.capitalize())
		if element == null:
			continue
		_element_home[which] = element.global_transform
		var inward := -_outward(which)
		var side := inward.cross(Vector3.UP).normalized()
		var root := element.global_position
		var pts: Array[Vector3] = []
		for p: Vector3 in [root + side * 0.009, root + side * 0.009 + inward * (ELEMENT_ROD - 0.015),
				root + inward * ELEMENT_ROD, root - side * 0.009 + inward * (ELEMENT_ROD - 0.015), root - side * 0.009]:
			pts.append(element.to_local(p))
		var rod := MeshInstance3D.new()
		rod.mesh = BoxView._tube(BoxView._smooth(pts, 6), 0.0045, 8)
		var copper := StandardMaterial3D.new()
		copper.albedo_color = Color(0.72, 0.45, 0.3)
		copper.metallic = 0.8
		copper.roughness = 0.35
		rod.material_override = copper
		element.add_child(rod)


## Water: a stream out of each element's hole and the drain, and the puddle
## on the floor, all off till they're needed.
func _build_water() -> void:
	_build_rods()
	var drop := CapsuleMesh.new()          # a streak, lined up with where it's going: a stream
	drop.radius = 0.0035
	drop.height = 0.045
	drop.radial_segments = 6
	drop.rings = 2
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.6, 0.75, 0.9, 0.55)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.05
	wet.metallic_specular = 0.9
	drop.material = wet
	var spots := {"drain": null}
	for which: String in WaterHeater.ELEMENTS:
		if _element_home.has(which):
			spots[which] = (_element_home[which] as Transform3D).origin
	var valve := _node("DrainValve_Handle")
	if valve != null:
		spots["drain"] = valve.global_position + global_basis * Vector3(0, -0.01, 0.04)
	for key: String in spots:
		if spots[key] == null:
			continue
		var p := CPUParticles3D.new()
		p.top_level = true
		p.mesh = drop
		p.amount = 600
		p.lifetime = 0.9
		p.emitting = false
		p.spread = 5.0
		p.particle_flag_align_y = true
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.4
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.008
		add_child(p)
		p.global_position = spots[key]
		p.direction = _outward(key) if key != "drain" else global_basis.z
		_streams[key] = p
	_puddle = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.004
	disc.radial_segments = 40
	_puddle.mesh = disc
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = Color(0.22, 0.34, 0.48, 0.72)
	sheet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet.roughness = 0.0
	sheet.metallic = 0.5
	sheet.metallic_specular = 1.0
	_puddle.material_override = sheet
	_puddle.top_level = true
	_puddle.visible = false
	add_child(_puddle)
	# On the floor in front of the tank: the heater stands on it.
	_puddle.global_position = global_position + global_basis.z * 0.45 + Vector3(0, 0.005, 0)


## Where the water's coming out right now, and how big the puddle's got.
func _show_water() -> void:
	if _puddle == null:
		return
	for which: String in WaterHeater.ELEMENTS:
		if _streams.has(which):
			var s: CPUParticles3D = _streams[which]
			s.emitting = heater.pouring(which)
			s.initial_velocity_min = 2.4 if heater.cold_open else 0.9
			s.initial_velocity_max = 3.0 if heater.cold_open else 1.4
	if _streams.has("drain"):
		var d: CPUParticles3D = _streams["drain"]
		d.emitting = heater.drain_spilling()
		d.initial_velocity_min = 0.6
		d.initial_velocity_max = 0.9
	_puddle.visible = heater.spilled > 0.002
	var r := clampf(sqrt(heater.spilled / WaterHeater.FLOOD) * 0.9, 0.08, 1.6)
	_puddle.scale = Vector3(r, 1.0, r)


## The heater's disconnect: a grey box on the wall beside it, at shoulder
## height, with flex conduit over to the top of the heater. Inside, behind a
## hinged door, a pull-out handle across the lugs.
func _build_disconnect() -> void:
	var side := global_basis.x
	var back := -global_basis.z
	# Find the wall behind the heater; it goes on that, off to one side.
	var at := global_position + Vector3(0, 1.35, 0) + side * 0.5
	var q := PhysicsRayQueryParameters3D.create(at, at + back * 1.5)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var wall: Vector3 = hit["position"] if not hit.is_empty() else at + back * 0.32
	_disc = Node3D.new()
	add_child(_disc)
	_disc.global_transform = Transform3D(global_basis, wall + global_basis.z * 0.045)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.57, 0.58)
	grey.metallic = 0.4
	grey.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.75, 0.6, 0.35)
	copper.metallic = 0.8
	_part(_disc, Vector3(0.16, 0.24, 0.006), Vector3(0, 0, -0.042), grey)          # back
	for x in [-0.077, 0.077]:
		_part(_disc, Vector3(0.006, 0.24, 0.085), Vector3(x, 0, 0), grey)         # sides
	for y in [-0.117, 0.117]:
		_part(_disc, Vector3(0.16, 0.006, 0.085), Vector3(0, y, 0), grey)         # top and bottom
	for x in [-0.03, 0.03]:                                                         # line lugs, live from the panel
		_part(_disc, Vector3(0.016, 0.016, 0.012), Vector3(x, 0.07, 0.022), copper)
		_part(_disc, Vector3(0.016, 0.016, 0.012), Vector3(x, -0.07, 0.022), copper)
	# The pull-out: a black block bridging the lugs, with a grip to pull it by.
	_disc_handle = Node3D.new()
	_disc.add_child(_disc_handle)
	_part(_disc_handle, Vector3(0.1, 0.17, 0.03), Vector3(0, 0, 0.02), dark)
	_part(_disc_handle, Vector3(0.05, 0.022, 0.028), Vector3(0, 0.03, 0.048), dark)
	var label := Label3D.new()
	label.text = "ON"
	label.font_size = 40
	label.pixel_size = 0.0006
	label.modulate = Color(0.95, 0.85, 0.2)
	label.position = Vector3(0, -0.04, 0.036)
	_disc_handle.add_child(label)
	# The door, hinged on its left edge.
	_disc_door = Node3D.new()
	_disc_door.position = Vector3(-0.08, 0, 0.044)
	_disc.add_child(_disc_door)
	_part(_disc_door, Vector3(0.162, 0.242, 0.005), Vector3(0.081, 0, 0), grey)
	var sign := Label3D.new()
	sign.text = "WATER HEATER\n240 V DISCONNECT"
	sign.font_size = 28
	sign.pixel_size = 0.0005
	sign.modulate = Color(0.1, 0.1, 0.1)
	sign.position = Vector3(0.081, 0.06, 0.004)
	_disc_door.add_child(sign)
	# Flex conduit down and over to the top of the heater.
	var top := _node("UpperCompartment")
	var to := (top.global_position if top != null else global_position + Vector3(0, 1.2, 0)) + Vector3(0, 0.25, 0)
	var from := _disc.global_position + _disc.global_basis.y * -0.12
	var path: Array[Vector3] = []
	for p: Vector3 in [from, from + Vector3(0, -0.06, 0), from.lerp(to, 0.5) + Vector3(0, -0.05, 0), to + Vector3(0, 0.08, 0), to]:
		path.append(to_local(p))
	var flex := MeshInstance3D.new()
	flex.mesh = BoxView._tube(BoxView._smooth(path, 6), 0.011, 8)
	flex.material_override = grey
	add_child(flex)
	_disc_handle.visible = heater.disconnect_in


## The handle sliding off the lugs toward you and away (out), or back on and home (in).
func _slide_pullout(going_in: bool) -> void:
	if _disc_handle == null:
		return
	var t := create_tween()
	if going_in:
		_disc_handle.visible = true
		_disc_handle.position.z = 0.16
		t.tween_property(_disc_handle, "position:z", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		t.tween_property(_disc_handle, "position:z", 0.16, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void: _disc_handle.visible = heater.disconnect_in)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## The garden hose: off the drain, down to the floor and away across the room
## toward the door. Only there while it's on.
func _build_hose() -> void:
	var valve := _node("DrainValve_Handle")
	if valve == null:
		return
	var start := to_local(valve.global_position) + Vector3(0, 0, 0.05)
	var floor_y := 0.02
	var path: Array[Vector3] = [start, start + Vector3(0, -0.03, 0.08), Vector3(start.x, floor_y, start.z + 0.25),
			Vector3(start.x + 0.3, floor_y, start.z + 0.9), Vector3(start.x + 0.2, floor_y, start.z + 1.8)]
	_hose_mesh = MeshInstance3D.new()
	_hose_mesh.mesh = BoxView._tube(BoxView._smooth(path, 8), 0.011, 10)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.13, 0.5, 0.18)
	green.roughness = 0.55
	_hose_mesh.material_override = green
	_hose_mesh.visible = heater.hose
	add_child(_hose_mesh)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_ui.add_child(_flash)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_ui.add_child(_overlay)
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, 0)
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -86.0
	bar.add_theme_constant_override("separation", 6)
	_ui.add_child(bar)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, TOOL_NAMES[i]]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 64)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(select_tool.bind(i))
		bar.add_child(b)
		_tool_buttons.append(b)
	_tool_buttons[0].button_pressed = true
	_hint = _label(22, Color(1.0, 0.82, 0.35), Control.PRESET_CENTER_BOTTOM, -150.0)
	_readout = _label(22, Color(0.85, 1.0, 0.85), Control.PRESET_CENTER_TOP, 90.0)
	_toast = _label(30, Color(1, 1, 1), Control.PRESET_CENTER_TOP, 150.0)


func _label(size: int, c: Color, preset: int, offset: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y += offset
	_ui.add_child(l)
	return l


func _draw_overlay() -> void:
	for probe: Array in [[_red, Color(0.9, 0.1, 0.1)], [_black, Color(0.1, 0.1, 0.1)]]:
		if probe[0] != "" and _open:
			var pos: Vector3 = _tank_pos(_focus if _focus in WaterHeater.ELEMENTS else "upper") if probe[0] == "tank" else _point_pos(probe[0])
			if not _cam.is_position_behind(pos):
				_overlay.draw_circle(_cam.unproject_position(pos), 7.0, probe[1])
	if _hover.is_empty():
		return
	var at := _cam.unproject_position(_hover["pos"])
	_overlay.draw_arc(at, 13.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2), 2.5, true)
	var text: String = _hover["label"]
	Hud.draw_tag(_overlay, at + Vector2(24, 0), text)
