class_name InstallObjective
extends ServiceObjective
## The new outlet they asked for: in, correctly wired, with power at its face,
## and the outlet it's fed from left right too (its new cable landed properly,
## plate back on). Which outlet you fed it from is up to you.

var install_id := ""


func is_complete() -> bool:
	if not building.roughed_in(install_id):
		return false
	var d := building.device(install_id)
	var source := building.device(building.installs[install_id]["source"])
	return d.repair_state() == "ok" and d.face_volts() > 100.0 and source.repair_state() == "ok" \
			and building.panel.circuit_at(d.slot).healthy()


func to_save() -> Dictionary:
	var saved := super()
	saved["install_id"] = install_id
	return saved
