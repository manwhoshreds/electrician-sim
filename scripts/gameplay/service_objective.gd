class_name ServiceObjective
extends RefCounted
## A required outcome checked against the real electrical installation.

var description := ""
var equipment_ids: Array[String] = []
var building: BuildingElectricalModel


func is_complete() -> bool:
	for id in equipment_ids:
		var d := building.device(id)
		if d == null or d.repair_state() != "ok" or d.face_volts() < 100.0:
			return false
	return true


func to_save() -> Dictionary:
	return {"description": description, "equipment_ids": equipment_ids.duplicate(), "complete": is_complete()}
