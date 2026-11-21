extends SceneTree
## Records the golden output the characterization tests compare against.
## Run it ONLY against code whose behaviour you mean to be the reference,
## never to make a failing test pass after a refactor.
##
##   godot --headless --path . -s tests/tools/capture_golden.gd

const Scenarios := preload("res://tests/support/aftercare_scenarios.gd")


func _init() -> void:
	var f := FileAccess.open(Scenarios.GOLDEN, FileAccess.WRITE)
	f.store_string(JSON.stringify(Scenarios.capture(), "\t", false))
	f.close()
	print("Wrote ", Scenarios.GOLDEN)
	quit()
