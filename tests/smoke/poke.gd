extends RefCounted
## Reads everything a job's views and checks compute from the electrics, so
## the playthrough exercises them. Used by play_jobs.gd.


## Read everything the job's views and checks compute from the electrics.
static func all(service: ServiceCall) -> void:
	service._card()
	service._defects()
	service._violations_now()
	service._callback_fixed()
	var panel := service._panel
	panel._sync()
	panel._hint()
	for t in PanelView.Tool.values():
		panel._tool = t
		panel._picks()
	var heater := service._inside.heater_view
	heater._hint_text()
	heater._readout_text()
	for t in WaterHeaterView.Tool.values():
		heater._tool = t
		heater.picks()
	if service.job.family == "panel":
		service._sim.check_repair(service.job.target)
	elif service.job.family == "heater":
		service._inside.heater.fixed()
	elif service.job.family == "install":
		service.job.outcomes_complete()
	elif service.job.kind != "callback":
		service._device_state()
	if service._box != null:
		service._box.device.repair_state()
		service._box._hint_text()
