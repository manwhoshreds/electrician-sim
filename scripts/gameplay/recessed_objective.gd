class_name RecessedObjective
extends ServiceObjective
## Their wafers: every one in its hole, wired right and lit off the old light's
## switch, and the old light gone, its box spliced through under a blank.


func is_complete() -> bool:
	return building.recessed_done()


func to_save() -> Dictionary:
	var saved := super()
	saved["recessed"] = true
	return saved
