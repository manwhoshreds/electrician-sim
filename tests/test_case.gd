extends RefCounted
## Base for headless tests. A test file extends this by path and defines
## methods named test_*; the runner makes a fresh instance for each one.
## Assertions record failures and carry on, so one test reports every
## broken expectation, not just the first.

var failures: Array[String] = []
var tree: SceneTree
var _nodes: Array[Node] = []


func before_each() -> void:
	pass


## Frees every node the test put in the tree with add_node().
func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


## Puts a node in the scene tree (so _ready runs) and frees it after the test.
func add_node(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % [_prefix(message), var_to_str(expected), var_to_str(actual)])


func near(actual: float, expected: float, message := "", tolerance := 0.001) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%sexpected %.4f, got %.4f" % [_prefix(message), expected, actual])


func is_true(value: bool, message := "") -> void:
	if not value:
		failures.append("%sexpected true" % _prefix(message))


func is_false(value: bool, message := "") -> void:
	if value:
		failures.append("%sexpected false" % _prefix(message))


static func _prefix(message: String) -> String:
	return message + ": " if message != "" else ""
