class_name CircuitObjective
extends ServiceObjective
## A required outcome for a branch circuit: correctly protected, landed, on,
## free of faults and overloads, with power restored at the panel.

var slot := 0


func is_complete() -> bool:
	return building.panel.bus_live() and building.panel.circuit_at(slot).healthy()


func to_save() -> Dictionary:
	var saved := super()
	saved["slot"] = slot
	return saved
