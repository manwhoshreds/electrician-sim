extends SceneTree
## Headless playthrough: loads the real main scene and plays a run of jobs
## end to end, without input. Each job is dispatched by the game, its house
## runs for a few seconds (the panel ticks, the house reports its draw, the
## HUD card updates every frame), the hints and repair checks are read, and
## the job is closed out through Aftercare as if the customer had paid.
## Engine errors are printed by Godot; tests/run.sh fails on any of them.
##
##   godot --headless --path . --fixed-fps 60 -s tests/smoke/play_jobs.gd

const JOBS := 20
const SEED := 7
const TIME_SCALE := 8.0          # game seconds per real frame-second
const MAX_WAIT_FRAMES := 3000
# Loaded at run time: a -s script that names game classes in its own code is
# reported as leaking them at exit, so the reading-out lives in a helper.
const POKE := "res://tests/smoke/poke.gd"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveGame.enabled = false            # never touch a real save
	seed(SEED)
	Engine.time_scale = TIME_SCALE
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var service: Node = null
	for c in main.get_children():
		if c.get_class() == "Node" and c.has_method("start_job"):
			service = c
	var poke: GDScript = load(POKE)
	var kinds: Array[String] = []
	for i in JOBS:
		if not await _wait_for_job(service):
			print("SMOKE FAIL: job %d never dispatched" % (i + 1))
			quit(1)
			return
		var layout_problems: Array = service._inside.layout_violations()
		if not layout_problems.is_empty():
			print("SMOKE FAIL: invalid house layout: %s" % ", ".join(layout_problems))
			quit(1)
			return
		kinds.append("%s/%s" % [service.job.family, service.job.kind])
		for f in 30:                         # a few game seconds in the house
			await process_frame
		poke.call("all", service)
		service._finish()
		# Unfixed jobs breed callbacks; let only every fourth through, so the
		# run sees fresh panel and device jobs as well.
		if i % 4 != 3:
			service.aftercare._events.clear()
	print("Played %d jobs: %s" % [kinds.size(), ", ".join(kinds)])
	main.queue_free()
	await process_frame
	quit(0)


func _wait_for_job(service: Node) -> bool:
	for f in MAX_WAIT_FRAMES:
		if service._job_running:
			return true
		await process_frame
	return false
