extends SceneTree
## Records tests/golden/box_scenarios.json from the CURRENT code. Run it only
## against the code whose behaviour is the reference.
##   godot --headless --path . -s tests/tools/capture_box_golden.gd

const SCENARIOS := "res://tests/support/box_scenarios.gd"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var lib: Node3D = (load(HouseInterior.LIBRARY) as PackedScene).instantiate()
	var scenarios: GDScript = load(SCENARIOS)
	var s: RefCounted = scenarios.new(root, lib)
	var t := Time.get_ticks_msec()
	var data: Dictionary = s.capture()
	var f := FileAccess.open(scenarios.GOLDEN, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()
	lib.free()
	print("Wrote %d scenarios to %s in %d ms" % [data.size(), scenarios.GOLDEN, Time.get_ticks_msec() - t])
	quit()
