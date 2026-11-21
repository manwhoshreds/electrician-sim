extends "res://tests/test_case.gd"
## The City Folks: every one loads, stands with its arms at its sides, waves,
## walks a real stride, and sits with its feet on the floor.


func _at(c: CharacterModel, bone: String) -> Vector3:
	return c.to_local(c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(bone)).origin)


func _person(which: int) -> CharacterModel:
	var c := CharacterModel.new()
	add_node(c)
	c.setup(which)
	return c


func test_every_one_stands_arms_down() -> void:
	for which in CharacterModel.MODELS.size():
		var c := _person(which)
		var hand := _at(c, "hand.l")
		check(hand.y < 1.1 and absf(hand.x) < 0.32, "model %d: hand by their side, at %s" % [which, hand])
		check(_at(c, "foot.l").y < 0.12, "model %d: on their feet" % which)


func test_waving_raises_the_right_hand_over_the_head() -> void:
	var c := _person(0)
	c.waving = true
	c._apply()
	is_true(_at(c, "hand.r").y > _at(c, "head.x").y)
	is_true(_at(c, "hand.l").y < 1.1, "the other one stays down")


func test_walking_the_feet_take_turns() -> void:
	var c := _person(1)
	c.walking = 1.0
	c._phase = PI / 2
	c._apply()
	var ahead := _at(c, "foot.l").z - _at(c, "foot.r").z
	c._phase = 3 * PI / 2
	c._apply()
	var then := _at(c, "foot.l").z - _at(c, "foot.r").z
	is_true(ahead > 0.4 and then < -0.4, "a stride each way: %.2f then %.2f" % [ahead, then])


func test_sitting_knees_forward_feet_down() -> void:
	var c := _person(2)
	c.sitting = true
	c._apply()
	is_true(_at(c, "leg_stretch.l").z > 0.3, "knees out in front")
	near(_at(c, "foot.l").y - Customer.SIT_DROP, 0.04, "feet on the floor once they're down in the seat", 0.08)
