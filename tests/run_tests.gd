extends SceneTree
## Headless test runner. No addons: finds tests/unit/test_*.gd, runs every
## test_* method on a fresh instance, prints a summary, and exits non-zero on
## any failure or any test file that won't load. Tests may await (they run
## after the first frame, with the tree available via `tree`).
##
##   godot --headless --path . -s tests/run_tests.gd [-- name_filter]

const TEST_DIR := "res://tests/unit"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	var passed := 0
	var failed := 0
	var broken := 0
	for path in _test_files():
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("BROKEN  %s (failed to load or compile)" % path)
			broken += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_") or (filter != "" and not name.contains(filter) and not path.contains(filter)):
				continue
			var case: RefCounted = script.new()
			case.tree = self
			ClampMeter.dial = ClampMeter.Mode.OFF        # one meter, shared: don't let a test inherit the last one's dial
			await case.before_each()
			await case.call(name)
			case.after_each()
			var failures: Array[String] = case.failures
			if failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL    %s :: %s" % [path.get_file(), name])
				for f in failures:
					print("          - " + f)
	print("\n%d passed, %d failed, %d broken file(s)" % [passed, failed, broken])
	quit(0 if failed == 0 and broken == 0 and passed > 0 else 1)


func _test_files() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(TEST_DIR.path_join(f))
	out.sort()
	return out
