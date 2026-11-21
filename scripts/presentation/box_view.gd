class_name BoxView
extends Interactable
## An outlet in its box in the wall, and the close-up where you work on it.
## The origin is the middle of the box opening on the wall face, +Z out of the wall.
## Models come from art/interior.py.
##
## Devices that go in a box: a duplex receptacle, a GFCI, the 240 V range
## receptacle behind the stove, a light switch or dimmer, and a ceiling light
## fixture (its box faces down, and its canopy comes down hanging by the leads).
## A fixture's hot comes from its switch's load wire, so a light needs both.
##
## The electrics (what's live, what's shorted, whether it's fixed) are the
## box's ElectricalDevice. This is the 3D box, the close-up, and your hands:
## it shows the device and turns clicks into its commands.
##
## Real work, real consequences: plate off, device out, test it dead, wires off
## the screws, new device in, hots on brass, white on silver, bare on green.
## Get it wrong and the tester says so, or the breaker trips when it comes on.
##
## Hand: pull the device out, push it back, take it out, put a new one in, pick
##   up a wire and land it, plate back on, GFCI test/reset.
## Screwdriver: plate screws, the screws into the box, terminal screws. Left click
##   loosens a wire off its screw, right click snugs a screw up.
## Clamp meter: Q turns the dial. On V~ or Ω, left click the red probe, right
##   click the black. (Amps you clamp at the panel.)
## Plug tester: plug it into a 120 V outlet and read the lights.
## Strippers: cut a burnt end off a wire and strip it fresh.

enum Tool { HAND, DRIVER, METER, TESTER, STRIP }

const TOOL_NAMES := ["Hand", "Screwdriver", "Clamp meter", "Plug tester", "Strippers"]
const CLOSEUP_KEYS := [["LMB", "Use Tool"], ["RMB", "Black Probe / Tighten"], ["Q", "Turn Dial"], ["R", "Leads Off"], ["Scroll", "Lean In"], ["Esc", "Step Back"]]
const PULLED := 0.085            # how far the device comes out of the box

## Where everything is on each kind of device's model. What the device is
## electrically is its DeviceSpec.
const SPEC := {
	"Receptacle": {
		"terms": {"brass_top": Vector3(0.0198, 0.018, -0.014), "brass_bottom": Vector3(0.0198, -0.021, -0.014),
			"silver_top": Vector3(-0.0198, 0.018, -0.014), "silver_bottom": Vector3(-0.0198, -0.021, -0.014),
			"green": Vector3(0.0, -0.0545, 0.0035), "back_hot": Vector3(0.008, -0.03, -0.032), "back_neutral": Vector3(-0.008, -0.03, -0.032)},
		"face": {"hot": Vector3(0.007, 0.0245, 0.0108), "neutral": Vector3(-0.007, 0.0245, 0.0108), "ground": Vector3(0, 0.0115, 0.0108)},
		"models": ["Duplex"], "plate": "DuplexPlate", "plate_screws": [0.0], "mount": 0.0417, "box_scale": Vector3.ONE,
		"scorch": Vector3(0.006, 0.026, 0.0105),
	},
	"GFCI": {
		"terms": {"line_brass": Vector3(0.0235, 0.018, -0.016), "line_silver": Vector3(-0.0235, 0.018, -0.016),
			"load_brass": Vector3(0.0235, -0.018, -0.016), "load_silver": Vector3(-0.0235, -0.018, -0.016), "green": Vector3(0.0, -0.0545, 0.0035)},
		"face": {"hot": Vector3(0.007, 0.021, 0.0108), "neutral": Vector3(-0.007, 0.021, 0.0108), "ground": Vector3(0, 0.03, 0.0108)},
		"models": ["GFCIDevice", "GFCITest", "GFCIReset"], "plate": "DecoraPlate", "plate_screws": [0.0455, -0.0455], "mount": 0.0417,
		"box_scale": Vector3.ONE, "scorch": Vector3(0.006, 0.022, 0.0105),
	},
	"Range": {
		"terms": {"x_lug": Vector3(0.037, 0.015, -0.02), "y_lug": Vector3(-0.037, 0.015, -0.02),
			"w_lug": Vector3(-0.037, -0.02, -0.02), "g_lug": Vector3(0.037, -0.02, -0.02)},
		"face": {"x": Vector3(0.012, 0.009, 0.0118), "y": Vector3(-0.012, 0.009, 0.0118), "neutral": Vector3(0, -0.012, 0.0118), "ground": Vector3(0, 0.022, 0.0118)},
		"models": ["RangeDevice"], "plate": "RangePlate", "plate_screws": [0.045, -0.045], "mount": 0.06,
		"box_scale": Vector3(1.45, 1.35, 1.0), "scorch": Vector3(0.012, 0.009, 0.0118),
	},
	"Switch": {
		"terms": {"s_top": Vector3(0.0185, 0.018, -0.012), "s_bottom": Vector3(0.0185, -0.018, -0.012), "green": Vector3(0.0, -0.0545, 0.0035)},
		"face": {}, "models": ["SwitchDevice", "SwitchLever"], "plate": "SwitchPlate", "plate_screws": [0.0302, -0.0302], "mount": 0.0417,
		"box_scale": Vector3.ONE, "scorch": Vector3(0.0, 0.0, 0.005),
	},
	"Dimmer": {
		"terms": {"s_top": Vector3(0.022, 0.018, -0.014), "s_bottom": Vector3(0.022, -0.018, -0.014), "green": Vector3(0.0, -0.0545, 0.0035)},
		"face": {}, "models": ["DimmerDevice"], "plate": "DecoraPlate", "plate_screws": [0.0455, -0.0455], "mount": 0.0417,
		"box_scale": Vector3.ONE, "scorch": Vector3(0.0, 0.0, 0.01),
	},
	"ThreeWay": {
		"terms": {"trav_a": Vector3(0.0185, 0.018, -0.012), "trav_b": Vector3(-0.0185, 0.018, -0.012), "common": Vector3(0.0185, -0.018, -0.012),
			"green": Vector3(0.0, -0.0545, 0.0035)},
		"face": {}, "models": ["ThreeWayDevice", "SwitchLever"], "plate": "SwitchPlate", "plate_screws": [0.0302, -0.0302], "mount": 0.0417,
		"box_scale": Vector3.ONE, "scorch": Vector3(0.0, 0.0, 0.005),
	},
	"Fan": {
		"terms": {"nut_black": Vector3(0.03, 0.015, -0.04), "nut_white": Vector3(-0.03, 0.015, -0.04), "f_ground": Vector3(0.0, -0.045, -0.003)},
		"face": {}, "models": ["FanBody", "FanBlades"], "plate": "FanGlass", "plate_screws": [], "mount": 0.06,
		"box_scale": Vector3(1.7, 1.0, 0.8), "scorch": Vector3(0.0, 0.0, 0.3), "pulled": 0.15,
	},
	"JBox": {
		"terms": {"nut_hot": Vector3(0.022, 0.01, 0.031), "nut_neutral": Vector3(-0.022, 0.01, 0.031), "nut_ground": Vector3(0.0, 0.01, 0.031)},
		"face": {}, "models": ["JBoxNuts"], "plate": "JBoxCover", "plate_screws": [0.045, -0.045], "mount": 0.0,
		"box_model": "JBoxCan", "box_scale": Vector3.ONE, "scorch": Vector3(0.022, 0.01, 0.04),
		"pulled": 0.07, "rest": -0.05,
	},
	"Smoke": {
		"terms": {}, "face": {}, "models": ["SmokeDetector", "SmokeLED"], "plate": "", "plate_screws": [], "mount": 0.0,
		"box_model": "DeviceBox", "box_scale": Vector3(1.7, 1.0, 0.8), "scorch": Vector3.ZERO, "pulled": 0.066,
	},
	"Fixture": {
		"terms": {"nut_black": Vector3(0.03, 0.015, -0.04), "nut_white": Vector3(-0.03, 0.015, -0.04), "f_ground": Vector3(0.0, -0.045, -0.003)},
		"face": {}, "models": ["FixtureCanopy", "FixtureBulb"], "plate": "FixtureShade", "plate_screws": [], "mount": 0.075,
		"box_scale": Vector3(1.7, 1.0, 0.8), "scorch": Vector3(0.0, 0.0, 0.056), "pulled": 0.15,
	},
	# A wafer's in its own 6" hole, no box: its little junction box rides on
	# top of it, and the leads land in there. Models: RecessedModels.
	"Wafer": {
		"terms": {"nut_black": Vector3(0.042, 0.016, -0.03), "nut_white": Vector3(0.042, -0.016, -0.03), "f_ground": Vector3(0.042, 0.0, -0.046)},
		"face": {}, "models": ["WaferTrim", "WaferLens", "WaferJBox"], "plate": "", "plate_screws": [], "mount": 0.0,
		"box_model": "", "box_scale": Vector3.ONE, "scorch": Vector3(0.0, 0.0, 0.012), "pulled": 0.2,
	},
	# The old light's box, spliced through and closed with a round blank.
	"Blank": {
		"terms": {"nut_black": Vector3(0.022, 0.01, 0.031), "nut_white": Vector3(-0.022, 0.01, 0.031), "f_ground": Vector3(0.0, -0.02, 0.031)},
		"face": {}, "models": ["BlankNuts"], "plate": "BlankCover", "plate_screws": [0.04, -0.04], "mount": 0.0,
		"box_scale": Vector3(1.7, 1.0, 0.8), "scorch": Vector3(0.022, 0.01, 0.04), "pulled": 0.07, "rest": -0.05,
	},
}
const TERM_NAME := {"brass_top": "top brass screw", "brass_bottom": "bottom brass screw", "silver_top": "top silver screw",
	"silver_bottom": "bottom silver screw", "green": "green ground screw", "back_hot": "backstab hole (brass side)",
	"back_neutral": "backstab hole (silver side)", "line_brass": "LINE brass screw", "line_silver": "LINE silver screw",
	"load_brass": "LOAD brass screw", "load_silver": "LOAD silver screw", "x_lug": "X lug (brass)", "y_lug": "Y lug (brass)",
	"w_lug": "W lug (silver, neutral)", "g_lug": "green ground lug", "s_top": "top brass screw", "s_bottom": "bottom brass screw",
	"nut_hot": "wire nut on the blacks", "nut_neutral": "wire nut on the whites", "nut_ground": "green wire nut on the grounds",
	"trav_a": "brass traveler screw (right)", "trav_b": "brass traveler screw (left)", "common": "dark COMMON screw",
	"nut_black": "wire nut on the black lead", "nut_white": "wire nut on the white lead", "f_ground": "green ground screw"}
const WIRE_NAME := {"hot": "black", "neutral": "white", "ground": "bare copper", "x": "black", "y": "red", "line": "black (line)", "load": "red (up to the light)",
	"t1": "red traveler", "t2": "white traveler (taped black)",
	"hot_out": "black going on", "neutral_out": "white going on", "ground_out": "bare going on"}
const WIRE_COLOUR := {"hot": Color(0.02, 0.02, 0.022), "x": Color(0.02, 0.02, 0.022), "y": Color(0.5, 0.03, 0.02),
	"neutral": Color(0.85, 0.85, 0.82), "ground": Color(0.8, 0.45, 0.25), "line": Color(0.02, 0.02, 0.022), "load": Color(0.5, 0.03, 0.02),
	"t1": Color(0.5, 0.03, 0.02), "t2": Color(0.8, 0.8, 0.77),
	"hot_out": Color(0.02, 0.02, 0.022), "neutral_out": Color(0.85, 0.85, 0.82), "ground_out": Color(0.8, 0.45, 0.25)}
const WIRE_IN := {"hot": Vector3(-0.007, 0.034, -0.06), "neutral": Vector3(0.0, 0.034, -0.06), "ground": Vector3(0.007, 0.034, -0.06),
	"x": Vector3(0.016, 0.034, -0.06), "y": Vector3(-0.016, 0.034, -0.06), "line": Vector3(-0.007, 0.034, -0.06), "load": Vector3(-0.007, 0.034, -0.06),
	"t1": Vector3(0.0, 0.034, -0.06), "t2": Vector3(0.012, 0.034, -0.06),
	"hot_out": Vector3(0.012, -0.04, -0.045), "neutral_out": Vector3(0.0, -0.04, -0.045), "ground_out": Vector3(-0.012, -0.04, -0.045)}
const DANGLE_OUT := {"hot": Vector3(0.04, 0.006, 0.075), "neutral": Vector3(-0.04, 0.006, 0.075), "ground": Vector3(0.0, -0.07, 0.065),
	"x": Vector3(0.055, 0.02, 0.075), "y": Vector3(-0.055, 0.02, 0.075), "line": Vector3(0.045, 0.02, 0.075), "load": Vector3(0.045, -0.015, 0.075),
	"t1": Vector3(0.045, 0.045, 0.07), "t2": Vector3(-0.045, 0.045, 0.07),
	"hot_out": Vector3(0.05, -0.04, 0.07), "neutral_out": Vector3(-0.05, -0.04, 0.07), "ground_out": Vector3(0.0, -0.07, 0.06)}
const DANGLE_IN := {"hot": Vector3(0.012, 0.0, -0.02), "neutral": Vector3(-0.012, 0.0, -0.02), "ground": Vector3(0.0, -0.02, -0.02),
	"x": Vector3(0.02, 0.0, -0.025), "y": Vector3(-0.02, 0.0, -0.025), "line": Vector3(0.012, 0.01, -0.02), "load": Vector3(0.012, -0.01, -0.02),
	"t1": Vector3(0.012, 0.0, -0.025), "t2": Vector3(-0.012, 0.0, -0.025),
	"hot_out": Vector3(0.015, -0.02, -0.03), "neutral_out": Vector3(-0.015, -0.02, -0.03), "ground_out": Vector3(0.0, -0.025, -0.03)}
const TESTER_LEGEND := "Tester: both yellow = correct   middle yellow = open ground   left yellow = open neutral   middle + red = hot/neutral reversed   none = no power"

var lib: Node3D                  # the interior models, lent by HouseInterior
var smoke_lib: Node3D            # the smoke detector's models (assets/smoke_detector), lent by HouseInterior
var clutter: Array[Node3D] = []  # appliances in front of it, moved aside while you work
## The electrics of the box. Everything about what's in it lives here.
var device: ElectricalDevice
## What you carry, the job you're on, and the vehicle the parts are in.
var inventory: Inventory
var job: ActiveJob
var van: Van
var room := ""
var glow_mat: StandardMaterial3D # for a light fixture: the glass and bulb, lit by the house
var _chirp_t := 10.0
var _alarm_t := 0.0
var _beeper: AudioStreamPlayer3D
var _led_mat: StandardMaterial3D
## A low battery or an old detector chirps this often (seconds): real ones are
## every 30 to 60, which is a long time to stand in a hallway.
const CHIRP_EVERY := 12.0
## Chirps so far (for tests: you can't hear a headless run).
var chirps := 0
var _flash_t := 0.0
var _date: Label3D
var _blades: Node3D
var tester_in := false
## What you did here: tested it, worked on it, got shocked.
var work := WorkLog.new()

var _device_pick := 0          # which fitting device from the bag is up next
var _open := false
var _player: Node3D
var _tool := Tool.HAND
var _meter: ClampMeter
var _held := ""
var _red := ""
var _black := ""
var _hover := {}
var _zoom := 0.3
var _cam: Camera3D
var _lamp: SpotLight3D
var _box_model: Node3D
var _dev: Node3D
var _dev_model: Node3D
var _scorch: MeshInstance3D
var _plate: Node3D
var _wire_meshes := {}
var _burnt_meshes := {}
var _tester: Node3D
var _leds: Array[StandardMaterial3D] = []
var _hand: HandRig
var _hand_pose := ""
var _sleeve: MeshInstance3D
var _driver: Node3D
var _strippers: Node3D
var _pens := {}                  # "red"/"black" -> pen
var _ui: CanvasLayer
var _overlay: Control
var _tool_buttons: Array[Button] = []
var _hint: Label
var _readout: Label
var _toast: Label
var _toast_t := 0.0
var _flash: ColorRect
var _click: AudioStreamPlayer
# A smoke detector's harness, plugged into its back (the box and splices are built once).
var _harness: Node3D


func _ready() -> void:
	super()
	reach = 1.2
	facing = Vector3.BACK
	aim_radius = {"ceiling": 0.15, "smoke": 0.1, "jbox": 0.12, "240": 0.1}.get(device.family, 0.08)
	match device.family:
		"switch":
			prompt = "[E] Flip the switch" if device.kind != "Dimmer" else "[E] Dimmer on/off"
			alt_prompt = "[F] Work on it"
			on_use = flip
			on_alt = open
			reach = 1.1
		"smoke":
			prompt = "[E] Smoke detector (on a ladder)"
			on_use = open
			reach = 1.0
			height_range = Vector2(-4.0, -1.5)
			work.verified_dead = true       # a plug-in harness: nothing bare to touch
			_chirp_t = randf_range(1.0, 6.0)   # the first one soon after you get there
			_beeper = AudioStreamPlayer3D.new()
			_beeper.position = Vector3(0, 0, 0.05)
			_beeper.unit_size = 10.0
			_beeper.max_db = 12.0
			add_child(_beeper)
		"jbox":
			prompt = "[E] Junction box"
			on_use = open
			reach = 1.3
			height_range = Vector2(-0.6, 0.8)
		"ceiling":
			prompt = "[E] Wire the wafer light (on a ladder)" if device.original == "Wafer" else "[E] Work on the light (on a ladder)"
			on_use = open
			reach = 0.9
			height_range = Vector2(-4.0, -1.5)    # from the floor below, not from the attic
		_:
			prompt = "[E] Work on the %s" % ("range outlet" if device.family == "240" else "%s outlet" % room)
			on_use = open
	if device.family != "ceiling" and device.family != "jbox" and device.family != "smoke":
		height_range = Vector2(-2.5, 0.6)      # from the room, not through the ceiling from the attic
	if _spec().get("box_model", "DeviceBox") != "":
		_box_model = lib.get_node(_spec().get("box_model", "DeviceBox")).duplicate()
		_box_model.scale = _spec()["box_scale"]
		add_child(_box_model)
	_build_device()
	if device.family == "smoke" and smoke_lib != null:
		_build_smoke_box()
	_plate = Node3D.new()
	add_child(_plate)
	_build_wires()
	_build_tester()
	_build_closeup()
	_build_hand()
	_build_ui()
	_refresh()


## Everything about how the box was left, so the house remembers it next visit.
func snapshot() -> Dictionary:
	return device.snapshot()


func restore(d: Dictionary) -> void:
	device.restore(d)
	_refresh()


## A fault for a job.
func set_fault(fault: String) -> void:
	device.set_fault(fault)
	_refresh()


## The switch on the wall, flipped by hand from the room.
func flip(_p: Node3D = null) -> void:
	if not device.flip():
		return
	if not work.worked_on:
		work.measured_live = true
	_snap()
	_refresh()


func note_working() -> void:
	if work.worked_on and device.repair_state() == "ok":
		work.tested_after = true


func _process(delta: float) -> void:
	if device.family == "smoke":
		_smoke_tick(delta)
	if _blades != null and device.lamp_volts() > 100.0 and not device.pulled_out:
		_blades.rotation.z += delta * 7.0
	# A short you wired with the power off goes bang when the breaker comes back on.
	if device.poll_short():
		_bang("BANG. Dead short. The breaker tripped.")
	if tester_in:
		var lights := device.tester_lights()
		for i in 3:
			_leds[i].emission_energy_multiplier = 8.0 if lights[i] else 0.0
	if not _open:
		return
	_zoom = clampf(_zoom, 0.0, 1.0)
	# Further back for the stove outlet, and well back from a fixture hanging off the ceiling.
	var spread := {"240": 1.3, "ceiling": 2.2}.get(device.family, 1.0) as float
	var back := lerpf(0.36, 0.2, _zoom) * spread + _dev_offset().z
	_cam.position = (Vector3(0.07, 0.035, 0.0).lerp(Vector3(0.04, 0.02, 0.0), _zoom)) * spread + Vector3(0, 0, back)
	var aim := _dev_offset().z * 0.35
	if device.original == "Wafer":
		# Up the ladder beside the hole, looking at the wafer hanging on its leads.
		_cam.position = Vector3(lerpf(0.42, 0.24, _zoom), 0.08, 0.1 + _dev_offset().z * 0.7)
		aim = _dev_offset().z * 0.75 if device.pulled_out else 0.02
	elif device.family == "ceiling":
		# Off to the side and below, looking into the gap between the ceiling and the canopy.
		_cam.position = Vector3(lerpf(0.42, 0.26, _zoom), 0.06, 0.12 + _dev_offset().z * 0.35)
		aim = 0.045 if device.pulled_out else 0.03
	elif device.family == "smoke":
		# Up the ladder, beside it. Twisted off, it hangs down on its harness:
		# follow it down, so the battery door and the harness are in view.
		var hang := _dev_offset().z
		_cam.position = Vector3(lerpf(0.42, 0.26, _zoom), 0.06, 0.12 + hang * 0.85)
		aim = 0.03 + hang * 0.8
	_cam.look_at(to_global(Vector3(0, 0, aim)), Vector3.UP if device.family == "ceiling" or device.family == "smoke" else global_basis.y)
	_hover = _pick_at(get_viewport().get_mouse_position())
	_pose_hand(delta)
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_hint.text = _hint_text()
	_readout.text = _readout_text()
	_overlay.queue_redraw()


# --- Smoke detectors ---------------------------------------------------------------------

func _smoke_tick(delta: float) -> void:
	_flash_t -= delta
	if _led_mat != null:
		# Green when it's got power; a red flash with every chirp.
		var flashing := _flash_t > 0.0
		_led_mat.emission = Color(1.0, 0.08, 0.05) if flashing else Color(0.2, 1.0, 0.3)
		_led_mat.emission_energy_multiplier = 6.0 if flashing else (2.0 if device.power_led() else 0.0)
	if _alarm_t > 0.0:
		_alarm_t -= delta
		return
	_chirp_t -= delta
	if _chirp_t <= 0.0:
		_chirp_t = CHIRP_EVERY
		if device.chirping():
			chirp()


## One chirp: short, high and loud, from the detector itself, so you can
## walk toward it. Its light flashes red with it.
func chirp() -> void:
	chirps += 1
	_flash_t = 0.35
	_beeper.stream = _tone(0.13, 3300.0, 1)
	_beeper.volume_db = 10.0
	_beeper.play()


## Interconnected: when one goes off, they all do.
func alarm() -> void:
	if device.kind == "" or not device.plugged:
		return
	_alarm_t = 3.0
	_beeper.stream = _tone(2.8, 3100.0, 6)
	_beeper.volume_db = 8.0
	_beeper.play()


func _smoke_picks(out: Array[Dictionary]) -> void:
	var at := _dev_offset()
	if not device.pulled_out:
		if device.kind != "":
			out.append({"kind": "smoke_test", "pos": Vector3(0, 0, 0.047), "label": "Press and hold the test button"})
			out.append({"kind": "twist", "pos": Vector3(0.055, 0, 0.03), "label": "Twist it off its base"})
		return
	if device.kind != "":
		out.append({"kind": "door", "pos": at + Vector3(-0.045, 0, 0.02), "label": "Close the battery door" if device.door_open else "Open the battery door"})
		if device.door_open:
			if device.battery_in:
				out.append({"kind": "battery_out", "pos": at + Vector3(-0.03, 0.02, 0.02), "label": "Pull the old 9 V out"})
			else:
				var holding: bool = inventory.has("Battery9V")
				out.append({"kind": "battery_in", "pos": at + Vector3(-0.03, 0.02, 0.02),
						"label": "Put in the 9 V you're holding" if holding else "Empty battery slot. Get a 9 V from the truck."})
	var harness := _plug_pos()
	if device.plugged:
		out.append({"kind": "harness", "pos": harness, "label": "Unplug the harness"})
		if device.kind != "" and not device.door_open:
			out.append({"kind": "twist", "pos": at + Vector3(0.055, 0, 0.03), "label": "Twist it back onto its base"})
	elif device.kind != "":
		out.append({"kind": "take_away", "pos": at + Vector3(0, 0, 0.03), "label": "Take the old detector down"})
		out.append({"kind": "harness", "pos": harness, "label": "Plug the harness back in"})
	else:
		var new_one: bool = inventory.has("Smoke")
		out.append({"kind": "harness", "pos": harness, "label": "Plug in the new detector you're holding" if new_one else "Nothing on the harness. Get a new detector from the truck."})


## Up in the ceiling behind the detector, like any light: a blue box, the
## mounting base, and the house's black, white and red (the interconnect to
## the other detectors) spliced in wire nuts to the harness's pigtails. The
## harness plugs into the back of the detector; twisted off, the detector
## hangs as far as the pigtails reach. Models: assets/smoke_detector (the
## owner's art/smoke_detector.blend).
func _build_smoke_box() -> void:
	add_child(smoke_lib.get_node("SmokeBase").duplicate())
	_harness = smoke_lib.get_node("SmokeHarness").duplicate()
	add_child(_harness)
	var nut_mat := _mat(Color(0.95, 0.78, 0.05), 0.4)
	var colours := [Color(0.02, 0.02, 0.022), Color(0.86, 0.86, 0.83), Color(0.6, 0.04, 0.03)]
	var hang := Vector3(0, 0, SPEC["Smoke"]["pulled"])
	for i in 3:
		# Each pigtail's stripped end, with the detector hanging: a nut on it, fanned out a little.
		var tip: Vector3 = hang + (smoke_lib.get_node("SmokeHarnessEnd%d" % i) as Node3D).position
		var lean := (i - 1) * 0.45
		var along := Vector3(sin(lean), 0, -cos(lean))         # up into the box, leaning out
		var nut := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0022
		cone.bottom_radius = 0.0038
		cone.height = 0.016
		cone.radial_segments = 10
		nut.mesh = cone
		nut.material_override = nut_mat
		var top := tip + along * 0.016
		_place_nut(nut, tip - along * 0.002, top)
		add_child(nut)
		# The house's wire, from its cable at the back of the box down into the nut.
		var house := _mat(colours[i], 0.4)
		var from := Vector3(-0.02 + 0.02 * i, 0.03, -0.048)
		add_child(_wire_segment(from, from.lerp(top, 0.5) + Vector3(0, -0.006, 0), 0.0019, house))
		add_child(_wire_segment(from.lerp(top, 0.5) + Vector3(0, -0.006, 0), top, 0.0019, house))
	var copper := _mat(Color(0.8, 0.45, 0.25), 0.3, 1.0)
	add_child(_wire_segment(Vector3(0.03, -0.02, -0.05), Vector3(0.034, -0.026, -0.012), 0.0014, copper))   # the ground, folded back in the box
	add_child(_wire_segment(Vector3(0.034, -0.026, -0.012), Vector3(0.02, -0.032, -0.03), 0.0014, copper))


## Puts a nut's mesh (a cylinder along its own +Y) from its open end to its tip.
static func _place_nut(mi: MeshInstance3D, mouth: Vector3, tip: Vector3) -> void:
	var up := (tip - mouth).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (mouth + tip) / 2.0)


## Where the harness's plug is: in the back of the detector, or, unplugged,
## hanging off its pigtails where the detector was.
func _plug_pos() -> Vector3:
	if device.plugged and device.kind != "":
		return _dev_offset()
	return Vector3(0, 0, SPEC["Smoke"]["pulled"])


func _refresh_smoke_box() -> void:
	if _harness == null:
		return
	_harness.position = _plug_pos()
	# Folded up in the box behind it while it's on its base.
	_harness.visible = device.pulled_out or not device.plugged or device.kind == ""


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _wire_segment(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	_place_segment(mi, a, b)
	return mi


## Stretches a unit-high cylinder from a to b.
static func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := maxf(d.length(), 0.0001)
	var up := d / length
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(side, up * length, side.cross(up)), (a + b) / 2.0)


func _smoke_click(kind_clicked: String) -> void:
	match kind_clicked:
		"smoke_test":
			if device.chirping() or not device.plugged:
				_beeper.stream = _tone(0.07, 3200.0, 1)
				_beeper.play()
				_say("Just a weak chirp. That won't wake anybody up.")
			else:
				get_parent().sound_alarms()
				if work.worked_on:
					work.tested_after = true
				_say("WEEEP WEEEP WEEEP. Every detector in the house went off with it.")
		"twist":
			device.twist()
			if device.pulled_out and not work.worked_on:
				work.measured_live = true
			_snap()
		"door":
			device.toggle_battery_door()
			_snap()
		"battery_out":
			device.remove_battery()
			work.worked_on = true
			_say("Old battery out.")
		"battery_in":
			if not inventory.use("Battery9V"):
				_say("No 9 V in your bag.")
				return
			device.insert_battery()
			work.worked_on = true
			_say("Fresh 9 V in." + (" It's still past its date, though." if device.expired() else ""))
		"harness":
			if device.plugged:
				device.unplug_harness()
			elif device.kind == "":
				if not inventory.use("Smoke"):
					_say("No new detector in your bag.")
					return
				device.fit_new_detector()
				work.worked_on = true
				job.device_used("Smoke", device)
				_say("New detector on the harness. Dated %d." % device.made)
			else:
				device.plug_harness()
			_snap()
		"take_away":
			device.take_down_detector()
			work.worked_on = true
			_say("Old detector down. The back says MFD %d." % device.made)


static func _tone(seconds: float, hz: float, pulses: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var on := pulses == 1 or fmod(t * pulses / seconds, 1.0) < 0.6
		data.encode_s16(i * 2, int(sin(TAU * hz * t) * (0.55 if on else 0.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# --- Close-up ---------------------------------------------------------------------------

func open(p: Node3D) -> void:
	_player = p
	_open = true
	p.target = self
	p.hud.set_closeup(true, CLOSEUP_KEYS)
	_cam.make_current()
	for n in clutter:
		n.visible = false
	_lamp.visible = true
	_ui.visible = true
	_show_hands(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	_held = ""
	_player.target = null
	_player.hud.set_closeup(false)
	_player.camera.make_current()
	for n in clutter:
		n.visible = true
	_lamp.visible = false
	_ui.visible = false
	_show_hands(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			_red = ""
			_black = ""
			_refresh()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_Q:
			turn_dial(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < TOOL_NAMES.size():
			_select_tool(i)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom += 0.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.15
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var p := _pick_at(event.position)
			if not p.is_empty():
				_click_on(p, event.button_index)
			get_viewport().set_input_as_handled()


## Click the meter's dial round. Probes already down read on the new setting.
func turn_dial(step := 1) -> void:
	ClampMeter.turn(step)
	_snap()
	_say("Dial: %s" % ClampMeter.setting(), 1.5)
	_take_voltage()


func _select_tool(t: int) -> void:
	_tool = t as Tool
	_tool_buttons[t].button_pressed = true
	if _tool != Tool.TESTER:
		tester_in = false
	_refresh()


# --- What you can click -----------------------------------------------------------------

func _spec() -> Dictionary:
	return SPEC[device.kind if device.kind != "" else device.plate_kind]


func _dev_offset() -> Vector3:
	return Vector3(0, 0, _spec().get("pulled", PULLED) if device.pulled_out else _spec().get("rest", 0.0))


func _term_pos(t: String) -> Vector3:
	return SPEC[device.kind]["terms"][t] + _dev_offset()


func _wire_end(w: String) -> Vector3:
	if device.wires[w] != "" and device.kind != "":
		var end := _term_pos(device.wires[w])
		if ElectricalDevice.LOOSE_WIRE.get(device.condition, "") == w:
			end += Vector3(-0.004, 0, 0)     # backed half out from under the screw
		return end
	return (DANGLE_OUT if device.pulled_out or device.kind == "" else DANGLE_IN)[w]


func _mount_pos(i: int) -> Vector3:
	var y: float = _spec()["mount"]
	return Vector3(0, y if i == 0 else -y, 0.0035)


func _plate_screw_pos(i: int) -> Vector3:
	return Vector3(0, SPEC[device.plate_kind]["plate_screws"][i], 0.008)


func _pick_at(mouse: Vector2) -> Dictionary:
	var best := {}
	var best_d := 18.0
	for p: Dictionary in _picks():
		var world := to_global(p["pos"])
		if _cam.is_position_behind(world):
			continue
		var d := _cam.unproject_position(world).distance_to(mouse)
		if d < best_d:
			best = p
			best_d = d
	return best


func _picks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var center := _dev_offset() + Vector3(0, 0, 0.012)
	if device.family == "smoke":
		_smoke_picks(out)                # all by hand, whatever tool you're holding
		return out
	match _tool:
		Tool.HAND:
			if device.kind == "GFCI" and not device.pulled_out:
				out.append({"kind": "test", "pos": Vector3(-0.0065, 0, 0.0125), "label": "TEST button"})
				out.append({"kind": "reset", "pos": Vector3(0.0065, 0, 0.0125), "label": "RESET button"})
			if device.family == "switch" and device.kind != "" and not device.pulled_out:
				var verb := "Flip it" if device.kind == "ThreeWay" else "Flip it %s" % ("off" if device.switch_on else "on")
				out.append({"kind": "flip", "pos": Vector3(-0.004 if device.kind == "Dimmer" else 0.0, 0.004, 0.012), "label": verb})
				if device.kind == "Dimmer":
					out.append({"kind": "slide", "pos": Vector3(0.009, 0.008, 0.012), "label": "Slide it (at %d%%)" % int(device.dim * 100)})
			if device.kind == "Wafer" and device.plate_on:
				out.append({"kind": "shade_off", "pos": Vector3(0, 0, 0.012), "label": "Pull the wafer down out of the hole"})
			elif device.family == "ceiling" and device.plate_on and device.plate_kind != "Blank":
				out.append({"kind": "shade_off", "pos": Vector3(0, 0, 0.09), "label": "Take the glass shade off"})
			if device.plate_on:
				return out
			if device.kind == "":
				var carrying := device_choice()
				var others := "  (right click: something else from your bag)" if _fitting().size() > 1 else ""
				out.append({"kind": "install", "pos": Vector3(0, 0, 0.01),
						"label": ("Put the new %s in%s" % [DeviceSpec.of(carrying).word, others]) if carrying != "" else "Empty box. Nothing in your bag fits it."})
			elif device.pulled_out:
				var free := device.wires.values().all(func(t: String) -> bool: return t == "")
				if device.family == "jbox":
					out.append({"kind": "push", "pos": center + Vector3(0, -0.03, -0.02), "label": "Fold the splices back into the box"})
				elif device.kind == "Wafer":
					out.append({"kind": "push", "pos": center + Vector3(0, -0.03, 0),
							"label": "Push it up into the hole (the spring clips snap)"})
				else:
					out.append({"kind": "remove" if free else "push", "pos": center + Vector3(0, -0.01, 0),
							"label": "Take the old %s out" % device.spec().word if free else ("Fold the splices up into the box" if device.kind == "Blank" else "Push it back into the box")})
			elif device.family == "jbox":
				out.append({"kind": "pull", "pos": center + Vector3(0, 0.0, 0.03), "label": "Pull the splices out of the box"})
				if work.worked_on:
					out.append({"kind": "plate", "pos": center + Vector3(0, 0.035, 0.03), "label": "Put the cover back on"})
			elif not device.mount_screws.has(true):
				out.append({"kind": "pull", "pos": center, "label": "Pull it out of the box"})
				if device.mount_screws.is_empty():   # nothing to screw it in with: the cover goes straight on
					out.append({"kind": "plate", "pos": center + Vector3(0, 0.03, 0.02), "label": "Put the blank cover on"})
			elif device.mounted:
				out.append({"kind": "plate", "pos": center + Vector3(0, 0.03, 0),
						"label": "Put the glass shade back on" if device.family == "ceiling" else "Put the cover plate back on"})
			for w: String in device.wires:
				if device.wires[w] == "" and w != _held:
					out.append({"kind": "grab", "wire": w, "pos": _wire_end(w),
							"label": "Pick up the %s wire%s" % [WIRE_NAME[w], " (burnt end)" if device.burnt[w] else ""]})
			if _held != "" and device.kind != "" and device.pulled_out:
				_add_terminals(out, "land")
		Tool.DRIVER:
			if device.plate_on:
				for i in device.plate_screws.size():
					if device.plate_screws[i]:
						out.append({"kind": "plate_screw", "i": i, "pos": _plate_screw_pos(i), "label": "Cover plate screw"})
			elif device.kind != "" and not device.pulled_out:
				for i in device.mount_screws.size():
					out.append({"kind": "mount", "i": i, "pos": _mount_pos(i),
							"label": "Unscrew it from the box" if device.mount_screws[i] else "Screw it to the box"})
			elif device.kind != "" and device.pulled_out:
				_add_terminals(out, "land" if _held != "" else "loosen")
		Tool.METER:
			if ClampMeter.dial != ClampMeter.Mode.VOLTS and ClampMeter.dial != ClampMeter.Mode.OHMS:
				return out
			if device.kind != "" and not device.pulled_out:
				for pin: String in _spec()["face"]:
					var label := "Ground hole" if pin == "ground" else ("%s slot" % pin.to_upper() if device.family == "240" else "Outlet %s slot" % pin)
					out.append({"kind": "probe", "id": "face_" + pin, "pos": _spec()["face"][pin], "label": label})
			if device.pulled_out or device.kind == "":
				for w: String in device.wires:
					if device.wires[w] == "":
						out.append({"kind": "probe", "id": "wire_" + w, "pos": _wire_end(w), "label": "End of the %s wire" % WIRE_NAME[w]})
				if device.kind != "":
					for t: String in SPEC[device.kind]["terms"]:
						if not t.begins_with("back"):
							out.append({"kind": "probe", "id": "term_" + t, "pos": _term_pos(t), "label": TERM_NAME[t].capitalize()})
		Tool.TESTER:
			if device.kind != "" and not device.pulled_out and device.family == "120":
				out.append({"kind": "tester", "pos": _spec()["face"]["hot"] - Vector3(0.007, 0, 0),
						"label": "Unplug the tester" if tester_in else "Plug the tester in"})
		Tool.STRIP:
			for w: String in device.wires:
				if device.wires[w] == "":
					out.append({"kind": "strip", "wire": w, "pos": _wire_end(w),
							"label": "Cut off the burnt end of the %s and strip it" % WIRE_NAME[w] if device.burnt[w] else "Strip a fresh end on the %s" % WIRE_NAME[w]})
	for p in out:
		if p["kind"] == "probe" and (p["id"] == _red or p["id"] == _black):
			p["label"] = "Take the probe off: " + p["label"]
	return out


func _add_terminals(out: Array[Dictionary], verb: String) -> void:
	for t: String in SPEC[device.kind]["terms"]:
		var on := ""
		for w: String in device.wires:
			if device.wires[w] == t:
				on = w
		var label := ""
		if verb == "land":
			if t.begins_with("back"):
				continue
			label = "Land the %s wire on the %s" % [WIRE_NAME[_held], TERM_NAME[t]]
		elif on == "":
			continue
		elif t.begins_with("back"):
			label = "Pull the %s wire out of the %s" % [WIRE_NAME[on], TERM_NAME[t]]
		else:
			if device.family == "jbox":
				label = "%s: twist it off the %s (right click: twist it tight)" % [TERM_NAME[t].capitalize(), WIRE_NAME[on]]
			else:
				label = "%s: loosen it to take the %s off (right click: snug it up)" % [TERM_NAME[t].capitalize(), WIRE_NAME[on]]
		out.append({"kind": verb, "term": t, "wire": on, "pos": _term_pos(t), "label": label})


# --- Doing things -------------------------------------------------------------------------

func _click_on(p: Dictionary, button: int) -> void:
	if device.family == "smoke":
		_smoke_click(p["kind"])
		_refresh()
		return
	match p["kind"]:
		"plate_screw":
			var off := device.remove_plate_screw(p["i"])
			_snap()
			if off:
				_say("Plate's off.")
		"plate":
			device.refit_plate()
			_say("Plate's back on.")
		"mount":
			device.toggle_mount_screw(p["i"])
			_snap()
		"pull":
			device.pull_out()
			_snap()
		"push":
			device.push_in()
			_snap()
			if device.kind == "Wafer":
				device.refit_plate()
				_say("Snap. The spring clips have it tight to the drywall.")
		"remove":
			_say("Old %s out%s." % [device.spec().word, ", and it's device.burnt black behind the face" if device.condition == "scorched" else ""])
			device.remove_device()
			work.worked_on = true
			_snap()
		"install":
			if button == MOUSE_BUTTON_RIGHT:
				_device_pick += 1         # the next thing in the bag that fits
			else:
				_install()
		"grab":
			if _live_bare(p["wire"]):
				return
			_held = p["wire"]
		"land":
			if _held == "" or _live_bare(_held):
				return
			var shorted := device.land(_held, p["term"])
			work.worked_on = true
			_held = ""
			_snap()
			if shorted:
				_bang("BANG. You landed a live wire on the wrong screw. Breaker's tripped.")
		"loosen":
			var w: String = p["wire"]
			if _live_bare(w):
				return
			if button == MOUSE_BUTTON_RIGHT:
				_tighten(w)
			else:
				device.loosen(w)
				work.worked_on = true
				_snap()
				_say("The %s wire's off." % WIRE_NAME[w])
		"strip":
			var w: String = p["wire"]
			if _live_bare(w):
				return
			if device.strip(w):
				work.worked_on = true
				_say("Burnt end's off. Clean copper now.")
			else:
				_say("It's already a clean end.")
			_snap()
		"flip":
			flip()
		"slide":
			device.slide_dimmer()
			_snap()
			_say("Slid to %d%%." % int(device.dim * 100))
		"shade_off":
			device.remove_shade()
			_snap()
			if device.kind == "Wafer":
				device.pull_out()
				_say("Down it comes, hanging on its leads.")
			else:
				_say("Shade's off.")
		"test":
			if device.test_gfci():
				_snap()
				_say("Click. Tripped.")
		"reset":
			_reset_gfci()
		"probe":
			var id: String = p["id"]
			if id == _red and button == MOUSE_BUTTON_LEFT:
				_red = ""
			elif id == _black and button == MOUSE_BUTTON_RIGHT:
				_black = ""
			elif button == MOUSE_BUTTON_RIGHT or (_red != "" and _black == ""):
				_black = id
			else:
				_red = id
			_take_voltage()
		"tester":
			tester_in = not tester_in
			if tester_in:
				_note_test()
	_refresh()


## Devices in your bag that would go in this box: the kind it was built for first.
func _fitting() -> Array[String]:
	var out: Array[String] = []
	for kind in inventory.bag_devices():
		var s := DeviceSpec.of(kind)
		if s.family == DeviceSpec.of(device.original).family and (kind == "ThreeWay") == (device.original == "ThreeWay"):
			out.append(kind)
	out.sort_custom(func(a: String, b: String) -> bool: return a == device.original and b != device.original)
	return out


## Which device from your bag goes in next, "" if nothing fits. Right click on
## the empty box steps through what fits.
func device_choice() -> String:
	var fits := _fitting()
	if fits.is_empty():
		# Nothing fits: offer what you've got anyway, so you're told why it won't go.
		var any := inventory.bag_devices()
		return any[0] if not any.is_empty() else ""
	return fits[posmod(_device_pick, fits.size())]


func _install() -> void:
	var carrying := device_choice()
	match device.install(carrying):
		"nothing":
			_say("Nothing in your bag fits this box. Get one from the truck.")
		"not_a_device":
			_say("That doesn't go in a box.")
		"three_way_mismatch":
			_say("This box needs a 3-way switch." if device.original == "ThreeWay" else "A 3-way switch won't work here. This is a single-pole box.")
		"wrong_family":
			_say("A %s won't go on this circuit." % DeviceSpec.of(carrying).word)
		"wafer_mismatch":
			_say("Only a wafer goes in this hole." if device.original == "Wafer" else "A wafer goes in its own hole. This box gets a blank cover once it's spliced through.")
		_:
			work.worked_on = true
			inventory.use(carrying)
			job.device_used(device.kind, device)
			_say("New %s in your hand. Land the device.wires on it." % DeviceSpec.of(device.kind).word)


func _tighten(w: String) -> void:
	_snap()
	if device.tighten(w):
		work.worked_on = true
		_say("That one was loose. It's tight now.")
	else:
		_say("Already tight.")


func _reset_gfci() -> void:
	match device.reset_gfci():
		"bad":
			_say("Click... it won't latch. This GFCI's done.")
		"no_line":
			_say("It won't reset. There's no power on its LINE screws.")
		"reset":
			_snap()
			_say("Reset. It holds.")


## Touching a hot conductor that's live.
func _live_bare(w: String) -> bool:
	if device.live_bare(w):
		if inventory != null and inventory.insulated_gloves:
			_buzz()
			_say("That %s wire's live! Your rubber gloves took it. Kill the breaker first." % WIRE_NAME[w], 4.0)
			return true
		work.shocks += 1
		_fade_flash(Color(0.75, 0.85, 1.0, 0.85), 0.5)
		_buzz()
		_say("ZAP! That %s wire's live. Kill the breaker first." % WIRE_NAME[w], 4.0)
		return true
	return false


## A dead short: the device has already tripped the breaker. This is the bang.
func _bang(text: String) -> void:
	work.arcs += 1
	_fade_flash(Color(1.0, 0.95, 0.8, 1.0), 1.0)
	_buzz()
	_say(text, 4.0)


func _volts() -> float:
	return device.voltage(_red, _black)


## Volts across the probes, noted for the job. Only on V~: on any other
## setting the meter isn't reading volts.
func _take_voltage() -> void:
	if _red == "" or _black == "" or ClampMeter.dial != ClampMeter.Mode.VOLTS:
		return
	var v := _volts()
	var hot := device.is_hot_point(_red) or device.is_hot_point(_black)
	if hot and (v > 60.0 or not work.worked_on):   # a dead reading before you start still counts as checking it
		_note_test()
	if hot and v < 5.0 and not device.any_live():
		work.verified_dead = true


func _note_test() -> void:
	if not work.worked_on:
		work.measured_live = true
	elif device.repair_state() == "ok":
		work.tested_after = true


# --- Words on screen -----------------------------------------------------------------------

func _hint_text() -> String:
	if device.family == "smoke":
		# The circles on screen are where you can click.
		if device.kind == "":
			if inventory.has("Smoke"):
				return "Hand (1): click the white harness plug to put the new detector on it."
			return "Old one's down. Get a new detector from the %s, or the supply house." % van.spec()["word"]
		if not device.pulled_out:
			if work.worked_on:
				if not device.power_led():
					return "It's back up, but its green light's off: no power. Breaker back on at the panel."
				return "Done. Go tell the customer." if work.tested_after and not device.chirping() else "Hand (1): press the test button in the middle."
			return "Hand (1): click its edge to twist it off its base and look at the back, or the middle to press test."
		if not device.expired() and not device.battery_low and device.battery_in and not work.worked_on:
			# What you'd see with it in your hands: in date, battery fine. It isn't this one.
			return "MFD %d, and the battery's fine. This one's good: twist it back on and listen for which one's chirping." % device.made
		if device.expired():
			if device.plugged:
				return "MFD %d: that's over %d years old. Unplug the white harness plug from the back of it." % [device.made, ElectricalDevice.SMOKE_LIFE]
			return "Hand (1): take the old detector down."
		if not device.door_open and (device.battery_low or not device.battery_in):
			return "Hand (1): open the battery door."
		if device.door_open and device.battery_in and device.battery_low:
			return "Hand (1): pull the old 9 V out."
		if device.door_open and not device.battery_in:
			return "Hand (1): put the new 9 V in." if inventory.has("Battery9V") else "Get a 9 V battery from the %s." % van.spec()["word"]
		if device.door_open:
			return "Hand (1): close the battery door."
		return "Hand (1): twist it back onto its base."
	if _held != "":
		if device.family == "ceiling":
			return "Holding the %s wire. Click a nut to land it: blacks together, whites together, bare on the ground." % WIRE_NAME[_held]
		return "Holding the %s wire. Click a screw to land it: hots on brass, white on silver, bare on green." % WIRE_NAME[_held]
	var splice := _splice_hint()
	if splice != "":
		return splice
	if device.kind == "":
		if device_choice() != "":
			return "Empty box. Hand (1): put up the new %s from your bag." % DeviceSpec.of(device_choice()).word
		return "Empty box. Go get the new one: the customer's, or from your %s, or buy it at the supply house downtown." % van.spec()["word"]
	if device.plate_on and device.family == "ceiling" and not work.worked_on:
		return "Flip the switch to see what it does, then Hand: take the glass shade off."
	if device.plate_on:
		if work.worked_on and work.tested_after:
			return "Done. Go tell the customer it's fixed."
		if not work.measured_live and not work.worked_on:
			if device.family == "switch":
				return "Flip it and watch the light first."
			if device.family == "jbox":
				return "Screwdriver (2): the two cover screws."
			return "Clamp meter (3) on V~%s: see what it's doing first." % ("" if device.family == "240" else " or plug tester (4)")
		if work.worked_on and (device.family == "switch" or device.family == "ceiling"):
			return "Breaker on, then flip the switch on and see the light come on."
		if work.worked_on:
			return "Breaker on, then test it: %s" % ("X to Y should read 240, each one to W 120." if device.family == "240" else "plug tester, both yellow lights.")
		return "Screwdriver (2): cover plate screws."
	if device.family == "jbox" and not device.pulled_out:
		return "Hand (1): cover back on." if work.worked_on else "Hand (1): pull the splices out where you can see them."
	if not device.pulled_out and device.mounted:
		return "Hand (1): put the cover plate back on." if work.worked_on else "Screwdriver: the two screws holding it in the box."
	if not device.pulled_out:
		return "Hand: pull it out of the box." if not work.worked_on else "Screwdriver: screw it to the box."
	if device.any_live() and not work.verified_dead:
		return "Breaker off at the panel, then test it dead with the meter: %s." % ("each wire to the bare ground" if device.family == "switch" else "each hot to the white")
	for w: String in device.wires:
		if device.burnt[w] and device.wires[w] == "":
			return "Strippers (5): cut the burnt end off the %s before it goes back on." % WIRE_NAME[w]
	var free := device.wires.values().filter(func(t: String) -> bool: return t == "").size()
	if free == device.wires.size():
		return "Hand: take the old one out."
	if free > 0:
		return "Hand: pick up a wire, then click the screw it goes on."
	if device.kind == "GFCI" and device.gfci_tripped:
		return "Push it in and screw it down. It'll need a RESET once the power's on."
	return "Hand: push it back into the box. Screwdriver right click snugs a screw up."


## On recessed work: what's next at a wafer, or at the old light's box.
func _splice_hint() -> String:
	if device.kind == "Wafer":
		if device.plate_on:
			return "It's in. Switch on and look for light." if device.lamp_volts() < 100.0 else "Lit. On to the next one."
		var free := device.wires.values().filter(func(t: String) -> bool: return t == "").size()
		if device.any_live() and not work.verified_dead:
			return "That cable's live. Breaker off, then test it dead with the meter."
		if free > 0:
			return "Hand: black to the black lead, white to the white, bare to the green ground.%s" % (" Both cables go on: the one in, and the one going on." if device.wires.has("hot_out") else "")
		return "Hand: push it up into the hole. The spring clips grab the drywall."
	if device.wires.has("hot_out") and device.family == "ceiling" and device.kind == "" :
		return "Old light's down. Put the blank cover on from your bag: the splices go on it." if inventory.has("Blank") else "Old light's down. You'll need a blank cover from the %s for this box." % (van.spec()["word"] if van != null else "truck")
	if device.kind == "Blank" and device.pulled_out:
		var free := device.wires.values().filter(func(t: String) -> bool: return t == "").size()
		if free > 0:
			return "Splice it through: the switch leg's black with the new black, whites together, grounds together."
		return "Hand: fold the splices up into the box, then the blank cover on."
	return ""


func _readout_text() -> String:
	var parts: Array[String] = []
	if _tool == Tool.METER or (_red != "" and _black != ""):
		parts.append("Meter (%s):  %s" % [ClampMeter.setting(), _reading()])
	if device.family == "120" and (tester_in or _tool == Tool.TESTER):
		parts.append(TESTER_LEGEND)
	return "\n".join(parts)


## What the meter says, in words, on whatever the dial's on.
func _reading() -> String:
	match ClampMeter.dial:
		ClampMeter.Mode.OFF:
			return "it's off. Q turns the dial"
		ClampMeter.Mode.AMPS:
			return "nothing to clamp in here. Clamp the circuit at the panel"
	if _red == "" or _black == "":
		return "place both probes"
	if ClampMeter.dial == ClampMeter.Mode.OHMS:
		return "voltage on it! Ohms is for dead circuits" if _probes_live() else "OL (open)"
	return "%.1f V" % _volts()


## The digits on the meter's display.
func _lcd() -> String:
	var both := _red != "" and _black != ""
	match ClampMeter.dial:
		ClampMeter.Mode.VOLTS:
			return "%.1f" % (_volts() if both else 0.0)
		ClampMeter.Mode.OHMS:
			return "----" if both and _probes_live() else "OL"
		ClampMeter.Mode.AMPS:
			return "0.0"
	return ""


func _probes_live() -> bool:
	return device.any_live() and (device.is_hot_point(_red) or device.is_hot_point(_black) or _volts() > 5.0)


func _say(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_t = seconds


func _fade_flash(c: Color, seconds: float) -> void:
	_flash.color = c
	create_tween().tween_property(_flash, "color:a", 0.0, seconds)


# --- Your hands --------------------------------------------------------------------------------

## The hand comes in from the lower right with whatever tool you've got.
func _pose_hand(_delta: float) -> void:
	var at := _cursor_point()
	if not _hover.is_empty():
		at = _hover["pos"]
	var forward := Vector3(-0.82, 0.42, -0.38).normalized()   # in from the right, not at your face
	var dorsal := Vector3(0.15, 0.3, 1.0)
	dorsal = (dorsal - forward * dorsal.dot(forward)).normalized()
	var hand_basis := Basis(dorsal.cross(-forward), dorsal, -forward)
	# Tools lie back along the arm, not pointed at your eye.
	var tool_basis := Basis(Quaternion(Vector3.UP, (-forward * 0.85 + dorsal * 0.25).normalized()))
	var volt := _tool == Tool.METER and (ClampMeter.dial == ClampMeter.Mode.VOLTS or ClampMeter.dial == ClampMeter.Mode.OHMS)
	_meter.visible = _tool == Tool.METER or _red != "" or _black != ""
	_meter.show_reading(_lcd())
	var pen_in_hand := "black" if _red != "" and _black == "" else "red"
	for colour: String in _pens:
		var placed := _red if colour == "red" else _black
		var pen: Node3D = _pens[colour]
		pen.visible = placed != "" or (volt and colour == pen_in_hand)
		if placed != "":
			pen.position = _probe_pos(placed)
			pen.basis = Basis(Quaternion(Vector3.UP, Vector3(0.35 if colour == "red" else -0.35, -0.3, 1.0).normalized()))
		else:
			pen.position = at
			pen.basis = tool_basis
	_driver.visible = _tool == Tool.DRIVER
	_strippers.visible = _tool == Tool.STRIP
	for tool: Node3D in [_driver, _strippers]:
		tool.position = at
		tool.basis = tool_basis
	var holding := _tool != Tool.HAND and _tool != Tool.TESTER
	var pose := "pinch" if holding or _held != "" else "point"
	if _tool == Tool.STRIP:
		pose = "wrap"
	if pose != _hand_pose:
		_hand_pose = pose
		_hand.set_pose(pose)
	var goal := at + Vector3.BACK * 0.004
	var anchor := _hand.joint("index-finger-tip")
	if holding:
		goal = at + tool_basis.y * (0.07 if _tool == Tool.STRIP else 0.06)
		anchor = (_hand.joint("index-finger-tip") + _hand.joint("thumb-tip")) / 2.0
	elif _held != "":
		anchor = (_hand.joint("index-finger-tip") + _hand.joint("thumb-tip")) / 2.0
	var wrist := goal - hand_basis * anchor
	_hand.transform = Transform3D(hand_basis, wrist)
	_sleeve.mesh = _tube(_smooth([wrist + forward * 0.01, wrist - forward * 0.08, wrist - forward * 0.3]), 0.04, 14)


## Where the mouse is, on the face of the device.
func _cursor_point() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var from := to_local(_cam.project_ray_origin(mouse))
	var dir := (global_basis.inverse() * _cam.project_ray_normal(mouse)).normalized()
	var z := _dev_offset().z + 0.012
	if absf(dir.z) < 0.001:
		return Vector3(0, 0, z)
	return from + dir * ((z - from.z) / dir.z)


func _show_hands(on: bool) -> void:
	_hand.visible = on
	_sleeve.visible = on
	_meter.visible = on and (_tool == Tool.METER or _red != "" or _black != "")
	if not on:
		for n: Node3D in [_driver, _strippers]:
			n.visible = false
		for colour: String in _pens:
			(_pens[colour] as Node3D).visible = (_red if colour == "red" else _black) != ""


func _build_hand() -> void:
	_hand = HandRig.new()
	_hand.material = HandRig.skin_material()
	add_child(_hand)
	_sleeve = MeshInstance3D.new()
	_sleeve.material_override = Surfaces.photo("denim_fabric", 0.25, Color(0.6, 0.7, 0.95), false)
	add_child(_sleeve)
	_driver = Node3D.new()
	add_child(_driver)
	_rod(_driver, 0.0028, 0.08, 0.04, _flat(Color(0.75, 0.76, 0.78), 0.9))
	_rod(_driver, 0.011, 0.09, 0.125, _flat(Color(0.9, 0.55, 0.08), 0.0))
	_strippers = lib.get_node("Strippers").duplicate()
	add_child(_strippers)
	for colour: String in ["red", "black"]:
		var pen := Node3D.new()
		add_child(pen)
		_rod(pen, 0.0012, 0.02, 0.01, _flat(Color(0.8, 0.8, 0.82), 0.95))
		_rod(pen, 0.0048, 0.09, 0.065, _flat(Color(0.8, 0.08, 0.06) if colour == "red" else Color(0.07, 0.07, 0.08), 0.0))
		_pens[colour] = pen
	_show_hands(false)


## A rod along the parent's Y axis, from `centre - h/2` to `centre + h/2`.
func _rod(parent: Node3D, r: float, h: float, centre: float, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position.y = centre
	parent.add_child(mi)


func _flat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.4
	return m


# --- Model ------------------------------------------------------------------------------------

func _build_device() -> void:
	_dev = Node3D.new()
	add_child(_dev)
	_scorch = MeshInstance3D.new()
	var blob := SphereMesh.new()
	blob.radius = 0.012
	blob.height = 0.004
	_scorch.mesh = blob
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.06, 0.02)
	mat.roughness = 0.95
	_scorch.material_override = mat
	_scorch.scale = Vector3(1.0, 1.4, 1.0)
	_dev.add_child(_scorch)


## The device has new wires (a cable added to feed a new outlet): build them.
func wiring_changed() -> void:
	for w: String in _wire_meshes:
		(_wire_meshes[w] as Node).queue_free()
		(_burnt_meshes[w] as Node).queue_free()
	_wire_meshes.clear()
	_burnt_meshes.clear()
	_build_wires()
	_refresh()


func _build_wires() -> void:
	var cooked := StandardMaterial3D.new()
	cooked.albedo_color = Color(0.1, 0.05, 0.02)
	cooked.roughness = 0.95
	for w: String in device.wires:
		var m := StandardMaterial3D.new()
		m.albedo_color = WIRE_COLOUR[w]
		m.roughness = 0.35
		if w == "ground":
			m.metallic = 1.0
		var mi := MeshInstance3D.new()
		mi.material_override = m
		add_child(mi)
		_wire_meshes[w] = mi
		var end := MeshInstance3D.new()
		end.material_override = cooked
		add_child(end)
		_burnt_meshes[w] = end


func _build_tester() -> void:
	_tester = Node3D.new()
	add_child(_tester)
	_tester.add_child(lib.get_node("PlugTester").duplicate())
	var colours := [Color(1.0, 0.7, 0.1), Color(1.0, 0.7, 0.1), Color(1.0, 0.1, 0.05)]
	for i in 3:
		var led: MeshInstance3D = lib.get_node("TesterLED%d" % (i + 1)).duplicate()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.07, 0.06)
		m.emission_enabled = true
		m.emission = colours[i]
		led.material_override = m
		_tester.add_child(led)
		_leds.append(m)


## Makes the model match the state.
func _refresh() -> void:
	if _dev_model != null:
		_dev_model.queue_free()
		_dev_model = null
	_blades = null
	if device.kind != "":
		_dev_model = Node3D.new()
		_dev.add_child(_dev_model)
		for n: String in SPEC[device.kind]["models"]:
			var model: Node3D = (smoke_lib if n.begins_with("Smoke") and smoke_lib != null else lib).get_node(n).duplicate()
			_dev_model.add_child(model)
			if n == "SmokeLED":
				_led_mat = StandardMaterial3D.new()
				_led_mat.albedo_color = Color(0.05, 0.1, 0.05)
				_led_mat.emission_enabled = true
				_led_mat.emission = Color(0.2, 1.0, 0.3)
				(model as MeshInstance3D).material_override = _led_mat
			if n == "SwitchLever" and not device.switch_on:
				model.scale.y = -1.0          # lever down
			if (n == "FixtureBulb" or n == "WaferLens") and glow_mat != null:
				(model as MeshInstance3D).material_override = glow_mat
			if n == "FanBlades":
				_blades = model
		_scorch.position = SPEC[device.kind]["scorch"]
	_dev.position = _dev_offset()
	_refresh_smoke_box()
	_scorch.visible = device.condition == "scorched" and device.kind != ""
	if device.family == "smoke" and device.kind != "":
		_date = Label3D.new()
		_date.text = "MFD %d\nREPLACE BY %d\n%s" % [device.made, device.made + ElectricalDevice.SMOKE_LIFE, "BATTERY DOOR OPEN" if device.door_open else ""]
		_date.font_size = 40
		_date.pixel_size = 0.0004
		_date.modulate = Color(0.1, 0.1, 0.1)
		_date.outline_size = 0
		_date.position = Vector3(0, -0.071, 0.024)
		_date.rotation = Vector3(PI / 2, 0, 0)
		_date.visible = device.pulled_out
		_dev_model.add_child(_date)
	for c in _plate.get_children():
		c.queue_free()
	if device.plate_on and SPEC[device.plate_kind]["plate"] != "":
		var plate: Node3D = lib.get_node(SPEC[device.plate_kind]["plate"]).duplicate()
		if (device.plate_kind == "Fixture" or device.plate_kind == "Fan") and glow_mat != null:
			(plate as MeshInstance3D).material_override = glow_mat
		_plate.add_child(plate)
		for i in device.plate_screws.size():
			if device.plate_screws[i]:
				var screw: Node3D = lib.get_node("PlateScrew").duplicate()
				screw.position = Vector3(0, _plate_screw_pos(i).y, 0)
				_plate.add_child(screw)
	var open_box := not device.plate_on or device.kind == ""
	for w: String in _wire_meshes:
		var path := _wire_path(w)
		var r := (0.0018 if w == "ground" else 0.0029) if device.family == "240" else (0.0009 if w == "ground" else 0.0016)
		(_wire_meshes[w] as MeshInstance3D).mesh = _tube(path, r)
		(_wire_meshes[w] as MeshInstance3D).visible = open_box
		var cooked: MeshInstance3D = _burnt_meshes[w]
		cooked.visible = device.burnt[w] and open_box
		if cooked.visible:
			cooked.mesh = _tube(path.slice(path.size() - 4), r * 1.25)
	_tester.visible = tester_in and device.kind != ""
	if device.kind != "" and device.family == "120":
		_tester.position = _spec()["face"]["hot"] + Vector3(-0.007, -0.006, 0.0)


func _probe_pos(id: String) -> Vector3:
	if id.begins_with("face_"):
		return _spec()["face"].get(id.substr(5), Vector3.ZERO) if device.kind != "" else Vector3.ZERO
	if id.begins_with("wire_"):
		return _wire_end(id.substr(5))
	return _term_pos(id.substr(5)) if device.kind != "" and SPEC[device.kind]["terms"].has(id.substr(5)) else Vector3.ZERO


func _wire_path(w: String) -> Array[Vector3]:
	var start: Vector3 = WIRE_IN[w] * Vector3(1, (_spec()["box_scale"] as Vector3).y, 1)
	var end := _wire_end(w)
	var side := signf(end.x) if absf(end.x) > 0.002 else (0.0 if w == "ground" else 1.0)
	var mid := start.lerp(end, 0.5) + Vector3(side * 0.012, 0.012, 0.0)
	var lead := end + Vector3(side * 0.012, 0.004, 0.0)
	return _smooth([start, start + Vector3(0, -0.004, 0.02), mid, lead, end])


static func _smooth(c: Array, per_span := 6) -> Array[Vector3]:
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


static func _tube(path: Array[Vector3], radius: float, sides := 8) -> ArrayMesh:
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
			verts.append(path[i] + n * radius)
			normals.append(n)
	for i in path.size() - 1:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			indices.append_array(PackedInt32Array([a, a + sides, b, b, a + sides, b + sides]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_closeup() -> void:
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.01
	add_child(_cam)
	_meter = ClampMeter.new()          # in your other hand, bottom left
	_meter.position = Vector3(-0.13, -0.11, -0.3)
	_meter.rotation = Vector3(0.1, 0.22, -0.1)
	_meter.scale = Vector3.ONE * 0.5
	_meter.visible = false
	_cam.add_child(_meter)
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0.05, 0.12, 0.4)
	_lamp.light_energy = 0.25
	_lamp.light_specular = 0.1
	_lamp.spot_range = 1.0
	_lamp.spot_angle = 30.0
	_lamp.visible = false
	add_child(_lamp)
	_lamp.basis = Basis.looking_at(-_lamp.position, Vector3.UP)
	_click = AudioStreamPlayer.new()
	_click.stream = MeterBase._burst(0.04, 0.5, 0.0)
	add_child(_click)


func _snap() -> void:
	_click.pitch_scale = randf_range(0.9, 1.2)
	_click.play()


func _buzz() -> void:
	_click.pitch_scale = 0.25
	_click.play()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_ui.add_child(_flash)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		b.custom_minimum_size = Vector2(140, 64)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_select_tool.bind(i))
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
	# Every spot you can click with the tool in your hand, so you can see where they are.
	for p: Dictionary in _picks():
		var w := to_global(p["pos"])
		if not _cam.is_position_behind(w):
			_overlay.draw_arc(_cam.unproject_position(w), 7.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.3, 0.75), 2.0, true)
	if _hover.is_empty():
		return
	var at := _cam.unproject_position(to_global(_hover["pos"]))
	_overlay.draw_arc(at, 13.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2), 2.5, true)
	var text: String = _hover["label"]
	Hud.draw_tag(_overlay, at + Vector2(24, 0), text)
