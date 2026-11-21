extends Node3D
## Sets up the world: sky and sun, the town, you, your truck, the HUD. Picks
## up the saved game if there is one, and saves between jobs and on quitting.
## Run with `-- --no-save` to leave the save file alone (headless checks), and
## `-- --job=recessed` (any file in data/jobs) to get only that kind of call.

## Where the sun is in the sky photo, so shadows agree with the clouds.
const SUN_DIRECTION := Vector3(-0.377, 0.741, 0.555)

var town: Town
var player: Player
var van: Van
var hud: Hud
## ` opens it: cheats for testing (CheatConsole).
var cheats: CheatConsole
var service: ServiceCall
var utility: PowerCompany
## Your phone: Tab on foot.
var phone: PhoneScreen
var _save := SaveGame.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # so Esc still works while the game is paused
	_setup_input()
	_setup_environment()
	town = Town.new()
	_add_pausable(town)
	hud = Hud.new()
	add_child(hud)
	hud.pause.resume_pressed.connect(_set_paused.bind(false))
	hud.pause.save_pressed.connect(_save_pressed)
	hud.pause.load_pressed.connect(_load_pressed)
	hud.pause.new_game_pressed.connect(_new_game_pressed)
	hud.pause.exit_pressed.connect(_exit_pressed)
	# The truck in your driveway at home, you standing next to it.
	van = Van.new()
	van.hud = hud
	_add_pausable(van)
	van.global_transform = town.home_spot
	player = Player.new()
	player.hud = hud
	_add_pausable(player)
	van.player = player
	player.global_position = town.home_start
	var to_truck := town.home_spot.origin - town.home_start
	player.rotation.y = atan2(-to_truck.x, -to_truck.z)   # looking at the truck
	service = ServiceCall.new()
	service.town = town
	service.player = player
	service.van = van
	service.hud = hud
	_add_pausable(service)
	day_night = DayNight.new()
	day_night.sky = _sky
	day_night.street_lamps = town.street_lamps
	day_night.clock = service.minutes
	_add_pausable(day_night)
	utility = PowerCompany.new()
	utility.town = town
	utility.player = player
	utility.service = service
	utility.hud = hud
	_add_pausable(utility)
	cheats = CheatConsole.new()
	cheats.main = self
	cheats.service = service
	cheats.player = player
	add_child(cheats)
	phone = PhoneScreen.new()
	phone.service = service
	phone.closed.connect(_put_phone_away)
	_add_pausable(phone)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_cmdline_user_args().has("--no-save"):
		SaveGame.enabled = false
	var welcome := "SPARKS & SONS ELECTRIC\nHome sweet home. It's not much, but the truck's in the driveway."
	if SaveGame.enabled:
		var data := _save.read()
		if not data.is_empty():
			SaveGame.apply(data, service, utility, town)
			welcome = "SPARKS & SONS ELECTRIC\nWelcome back. You've got $%d and the %s's in the driveway." % [service.wallet.money, van.spec()["word"]]
		elif _save.problem != "":
			welcome = "SPARKS & SONS ELECTRIC\nCouldn't load your save: %s.\nStarting fresh." % _save.problem
		service.checkpoint.connect(_autosave)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--job="):
			welcome += "\n" + only_calls(arg.trim_prefix("--job="))
	hud.show_message(welcome, 4.0)


## `-- --job=recessed`, or the cheat `job recessed`: dispatch only ever sends
## that kind of call (any file name in data/jobs; "any" for all of them again).
## Calls already waiting on the board are called off so the next one's yours.
## Callbacks on old work still come first.
func only_calls(kind: String) -> String:
	if kind == "any":
		service.call_generator.catalog = JobType.dispatchable()
		return "Dispatch is back to sending any kind of call."
	if not ResourceLoader.exists(JobType.DIR + kind + ".tres"):
		return "No such job as '%s'. Type jobs for the list." % kind
	service.call_generator.catalog = [JobType.of(kind)] as Array[JobType]
	for job in service.scheduler.board:
		if job.transition_to(ActiveJob.Status.CANCELLED):
			service.call_repository.update(job)
	service.scheduler.board.clear()
	var note := "  Finish the one you're on first." if service._job_running else ""
	return "Dispatch is only sending %s calls.%s" % [kind, note]


func _autosave() -> void:
	_save.write(SaveGame.capture(service, utility, town))


## Closing the window between jobs saves. Mid-job it doesn't: the save from
## just before that call came in is the one you'll pick up from.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and SaveGame.enabled and service != null and service.between_jobs():
		_autosave()


# --- The pause screen's buttons -------------------------------------------------------

func _save_pressed() -> void:
	if not SaveGame.enabled:
		hud.pause.notice("Saving is switched off for this run.")
	elif not service.between_jobs():
		hud.pause.notice("The game saves between jobs. Finish this call and it'll save.")
	elif _save.write(SaveGame.capture(service, utility, town)):
		hud.pause.notice("Game saved.")
	else:
		hud.pause.notice("Couldn't save: %s." % _save.problem)


func _load_pressed() -> void:
	if not SaveGame.enabled or not _save.exists():
		hud.pause.notice("There's no saved game yet.")
		return
	hud.pause.confirm("Load your last save? Anything you've done since it was saved is lost.", "Load it", _restart)


func _new_game_pressed() -> void:
	hud.pause.confirm("Start over? Your save will be deleted.", "Yes, start over", func() -> void:
		_save.delete()
		_restart())


## Between jobs it saves and quits. Mid-job it asks first: that call's progress goes.
func _exit_pressed() -> void:
	if service.between_jobs():
		if SaveGame.enabled:
			_autosave()
		get_tree().quit()
		return
	hud.pause.confirm("Quit now? You'll pick up from just before this call came in, and this call's progress is lost.",
			"Quit", get_tree().quit)


## The town starts over from the save file, or from scratch if there isn't one.
func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		if event.is_action_pressed("ui_cancel") and not hud.pause.close_overlay():
			_set_paused(false)
		return
	if player.target != null:   # talking or at a panel: the mouse belongs to them
		return
	if event.is_action_pressed("ui_cancel"):
		_set_paused(true)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		_get_phone_out()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_QUOTELEFT:
		cheats.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Tab: the phone out of your pocket. Not while you're driving.
func _get_phone_out() -> void:
	if player.driving != null:
		hud.show_toast("Eyes on the road. Get out of the truck to use your phone.")
		return
	player.target = phone
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_closeup(true, [["Tab", "Put Phone Away"], ["Esc", "Back"]])
	phone.open()


func _put_phone_away() -> void:
	if player.target == phone:
		player.target = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_closeup(false)


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	hud.set_paused(on, service.pause_summary() if on else null)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED


func _add_pausable(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(node)


var _sky: Sky3D
## The sky following the game clock.
var day_night: DayNight


## Sky3D (addons/sky_3d, MIT): an atmospheric sky with a sun, moon, stars and
## clouds. The game's clock sets its time of day (see DayNight); it doesn't run its own.
func _setup_environment() -> void:
	_sky = Sky3D.new()
	_sky.add_to_group("world_env")
	add_child(_sky)                       # it builds its own sky, sun, moon and environment here
	_sky.game_time_enabled = false        # our clock drives it
	_sky.tod.latitude = deg_to_rad(40.0)  # a mid-American town in early summer: up by 6, dark by 9
	_sky.tod.longitude = deg_to_rad(-90.0)
	_sky.tod.utc = -6.0
	_sky.tod.month = 6
	_sky.tod.day = 15
	var env := _sky.environment
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssil_enabled = true
	env.glow_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	if _sky.sun != null:
		_sky.sun.directional_shadow_max_distance = 180.0


func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("headlamp", KEY_L)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("sprint", KEY_SHIFT)
	_add_key("interact", KEY_E)
	_add_key("work", KEY_F)


func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)
