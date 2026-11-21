extends SceneTree
## Records tests/golden/service_scenarios.json from the CURRENT code. Run it
## only against the code whose behaviour is the reference.
##   godot --headless --path . -s tests/tools/capture_service_golden.gd

# Loaded at run time, not preloaded: a preloaded script with an inner class
# extending a game class is reported as leaked when a -s script quits.
const SCENARIOS := "res://tests/support/service_scenarios.gd"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var t := Time.get_ticks_msec()
	var scenarios: GDScript = load(SCENARIOS)
	var data: Dictionary = scenarios.new(self).capture()
	var f := FileAccess.open(scenarios.GOLDEN, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()
	print("Wrote %d entries to %s in %d ms" % [data.size(), scenarios.GOLDEN, Time.get_ticks_msec() - t])
	await process_frame
	quit()
