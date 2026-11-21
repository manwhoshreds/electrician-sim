class_name WaterHeaterObjective
extends ServiceObjective
## Hot water again: both elements good and wired, the high-limit closed, the
## tank full with the cold on and the drain shut, power on, covers back on.
## However you got there.


func is_complete() -> bool:
	var h := building.water_heater
	return h.fixed() and h.buttoned_up()
