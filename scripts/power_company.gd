class_name PowerCompany
extends Node
## Cedar Valley Power. Every meter in town is theirs. Call them before you pull
## one and it's a reseal fee on your bill. Pull one without calling and the
## meter reports it: a crew turns up, runs you down, and sorts you out
## personally. You wake up on the lawn with the meter back in and a fine.

const NAME := "CEDAR VALLEY POWER"
const RESEAL_FEE := 45
const TAMPER_FINE := 750
const CREW_DELAY := 25.0         # seconds after the pull before they turn up
const RUN_SPEED := 5.2           # a bit slower than you sprint
const REACH := 1.2               # close enough to swing
const GIVE_UP_DISTANCE := 70.0   # drive off and they follow your tracks

var town: Town
var player: Player
var service: ServiceCall
var hud: Hud

var _cleared := {}               # address -> true once you've called it in
var _coming: MeterBase = null    # the meter you pulled, while they're on the way
var _lineman: Customer = null
var _beating := false
var _overlay: ColorRect
var _caption: Label
var _hit_sound: AudioStreamPlayer


func _ready() -> void:
	for h: Dictionary in town.houses:
		if h.has("meter_box"):
			var meter: MeterBase = h["meter_box"]
			meter.company = self
			meter.pulled.connect(_on_pulled)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0, 0, 0, 0)
	layer.add_child(_overlay)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	_caption.modulate.a = 0.0
	layer.add_child(_caption)
	_hit_sound = AudioStreamPlayer.new()
	_hit_sound.stream = MeterBase._burst(0.22, 1.0, 55.0)
	add_child(_hit_sound)


func _process(delta: float) -> void:
	if _lineman == null or _beating:
		return
	var to_you := player.global_position - _lineman.global_position
	to_you.y = 0.0
	# Drive off and they'll be waiting when you get out.
	if player.driving == null and to_you.length() > GIVE_UP_DISTANCE:
		_lineman.global_position = player.global_position - to_you.normalized() * 25.0
		_lineman.global_position.y = 0.0
		return
	var stop := 2.6 if player.driving != null else REACH
	if to_you.length() > stop:
		_lineman.global_position += to_you.normalized() * minf(RUN_SPEED * delta, to_you.length() - stop)
		_lineman.rotation.y = atan2(to_you.x, to_you.z)
	elif player.driving == null:
		_beat_down()


# --- At the meter -------------------------------------------------------------------

## Which houses you've called in a disconnect for, for the save file.
func to_save() -> Dictionary:
	return {"called_in": _cleared.keys()}


func load_save(d: Dictionary) -> void:
	_cleared.clear()
	for address: String in d.get("called_in", []):
		_cleared[address] = true


func is_cleared(meter: MeterBase) -> bool:
	return _cleared.has(meter.address)


## The phone call: logged, cleared, reseal fee on your bill.
func call_for(meter: MeterBase) -> String:
	if is_cleared(meter):
		return "You've already called this one in. You're cleared to pull it."
	_cleared[meter.address] = true
	service.wallet.pay(RESEAL_FEE)
	return "%s: \"Disconnect at %s, logged under your license. Go ahead and pull it. Reseal's $%d, it's on your bill.\"" % [NAME, meter.address, RESEAL_FEE]


func _on_pulled(meter: MeterBase) -> void:
	if is_cleared(meter) or _coming != null or _lineman != null:
		return
	# The meter's radio reports the outage and the tamper. Someone's on the way.
	_coming = meter
	get_tree().create_timer(CREW_DELAY, false).timeout.connect(_send_crew)


# --- The crew -------------------------------------------------------------------------

func _send_crew() -> void:
	_lineman = Customer.new()
	_lineman.person_name = "Lineman"
	_lineman.waving = false
	_lineman.active = false
	_lineman.player = player
	add_child(_lineman)
	_lineman.global_position = _coming.street
	_dress(_lineman)
	hud.show_message("%s\nA crew just pulled up at %s. They don't look happy." % [NAME, _coming.address], 5.0)
	service.send_text(NAME.capitalize(), "Our crew is at %s. Someone pulled the meter without calling us." % _coming.address)


## Hard hat and a hi-vis vest over whatever the customer model put on him.
func _dress(man: Node3D) -> void:
	var vest := StandardMaterial3D.new()
	vest.albedo_color = Color(0.85, 0.95, 0.1)
	vest.emission_enabled = true
	vest.emission = Color(0.4, 0.45, 0.0)
	var hat := StandardMaterial3D.new()
	hat.albedo_color = Color(0.95, 0.95, 0.92)
	hat.roughness = 0.3
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.85, 0.8)
	stripe.metallic = 0.8
	stripe.roughness = 0.2
	_blob(man, Vector3(0.47, 0.5, 0.29), Vector3(0, 1.24, 0), vest)
	_blob(man, Vector3(0.48, 0.035, 0.3), Vector3(0, 1.12, 0), stripe)
	_blob(man, Vector3(0.48, 0.035, 0.3), Vector3(0, 1.3, 0), stripe)
	_blob(man, Vector3(0.27, 0.15, 0.3), Vector3(0, 1.8, -0.01), hat)
	_blob(man, Vector3(0.32, 0.03, 0.36), Vector3(0, 1.75, 0.01), hat)


func _blob(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	mi.material_override = mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)


func _beat_down() -> void:
	_beating = true
	if player.target != null and player.target.has_method("close") and not player.target is DialogueBox:
		player.target.close()        # out of whatever close-up you were in
	elif player.target != null:
		_ui_close()
	player.target = _lineman          # you're not going anywhere
	hud.show_message("\"You pulled MY meter?\"", 2.0)
	await get_tree().create_timer(1.3, false).timeout
	for i in 3:
		_hit(i)
		await get_tree().create_timer(0.5, false).timeout
	var dark := create_tween()
	dark.tween_property(_overlay, "color", Color(0, 0, 0, 1), 0.6)
	await dark.finished
	# Out cold while they put it all back.
	var meter := _coming
	meter.restore()
	service.wallet.pay(TAMPER_FINE)
	_lineman.queue_free()
	_lineman = null
	_coming = null
	var lawn := meter.to_global(Vector3(0.8, meter.ground, 2.4))
	player.global_position = lawn
	var back := meter.global_position - lawn
	player.rotation.y = atan2(-back.x, -back.z)
	player.head.rotation.x = 0.0
	_caption.text = "You wake up on the lawn.\n\nCedar Valley Power put the meter back in, sealed it,\nand left you a bill: $%d tampering fine.\n\nNext time, call first." % TAMPER_FINE
	var words := create_tween()
	words.tween_property(_caption, "modulate:a", 1.0, 0.5)
	await get_tree().create_timer(4.5, false).timeout
	var wake := create_tween()
	wake.tween_property(_caption, "modulate:a", 0.0, 0.5)
	wake.parallel().tween_property(_overlay, "color", Color(0, 0, 0, 0), 1.2)
	await wake.finished
	player.target = null
	_beating = false


## A punch: the view snaps sideways, a white flash, a thud.
func _hit(i: int) -> void:
	_hit_sound.pitch_scale = randf_range(0.8, 1.1)
	_hit_sound.play()
	var cam := player.camera
	var side := -1.0 if i % 2 == 0 else 1.0
	cam.rotation.z = side * 0.35
	cam.h_offset = side * 0.12
	cam.v_offset = -0.05 * i
	var t := create_tween()
	t.tween_property(cam, "rotation:z", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC)
	t.parallel().tween_property(cam, "h_offset", 0.0, 0.35)
	t.parallel().tween_property(cam, "v_offset", 0.0, 0.35)
	_overlay.color = Color(1, 0.95, 0.9, 0.7)
	var flash := create_tween()
	flash.tween_property(_overlay, "color", Color(0.4, 0, 0, 0.15 * (i + 1)), 0.3)


func _ui_open() -> void:
	player.target = service.dialogue
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ui_close() -> void:
	service.dialogue.close()
	player.target = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
