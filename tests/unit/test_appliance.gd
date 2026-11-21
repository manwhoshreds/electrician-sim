extends "res://tests/test_case.gd"
## Appliances move for access and put their real operating load on the panel.

const HVAC_SYSTEM := preload("res://scripts/hvac_system.gd")


func _appliance(panel: ElectricalPanel, name: String, slot: int) -> Appliance:
	var host := Node3D.new()
	add_node(host)
	var model := Node3D.new()
	host.add_child(model)
	var a := Appliance.new()
	a.node = model
	a.title = name
	a.appliance = name
	a.slot = slot
	a.sim = panel
	host.add_child(a)
	return a


func test_continuous_appliance_draws_only_while_on_and_powered() -> void:
	var panel := ElectricalPanel.new()
	var stove := _appliance(panel, "range", 1)
	stove._toggle_on(null)
	stove._process(0.0)
	near(panel.current("wire_1"), 18.6)
	panel.toggle(1)
	stove._process(0.0)
	near(panel.current("wire_1"), 0.0, "an open breaker stops the appliance")
	panel.toggle(1)
	stove._toggle_on(null)
	stove._process(0.0)
	near(panel.current("wire_1"), 0.0, "the appliance switch is off")


func test_timed_appliance_runs_then_stops() -> void:
	var panel := ElectricalPanel.new()
	var microwave := _appliance(panel, "microwave", 10)
	microwave._toggle_on(null)
	near(panel.current("wire_10"), 10.5)
	panel.tick(30.0)
	near(panel.current("wire_10"), 0.0)


func test_appliance_can_slide_out_and_back() -> void:
	var stove := _appliance(ElectricalPanel.new(), "range", 1)
	is_false(stove.pulled)
	stove._toggle_slide(null)
	is_true(stove.pulled)
	is_true(stove.prompt.contains("Push back"))
	stove._toggle_slide(null)
	is_false(stove.pulled)
	is_true(stove.prompt.contains("Slide out"))


func test_washer_and_240_volt_dryer_use_dedicated_circuits() -> void:
	var panel := ElectricalPanel.new()
	var washer := _appliance(panel, "washer", 14)
	washer._toggle_on(null)
	near(panel.current("wire_14"), 8.0)
	var dryer := _appliance(panel, "dryer", 2)
	dryer.voltage = 240
	dryer._toggle_on(null)
	near(panel.current("wire_2"), 22.0)
	panel.toggle(2)
	dryer._toggle_on(null)
	near(panel.current("wire_2"), 0.0, "dryer cannot run with its two-pole breaker open")


func test_central_air_runs_both_real_branch_circuits() -> void:
	var panel := ElectricalPanel.new()
	var hvac = HVAC_SYSTEM.new()
	hvac.sim = panel
	add_node(hvac)
	hvac._process(0.0)
	near(panel.current("wire_15"), 4.6, "indoor air handler")
	near(panel.current("wire_6"), 14.2, "outdoor condenser")
	hvac.cooling_on = false
	hvac._process(0.0)
	near(panel.current("wire_15"), 0.0)
	near(panel.current("wire_6"), 0.0)


func test_selected_floor_plan_has_laundry_and_second_bath_equipment() -> void:
	near(Town.HOUSE_PLAN_WIDTH, 12.192)
	near(Town.HOUSE_PLAN_DEPTH, 9.144, "30 feet, as drawn")
	var building := BuildingElectricalModel.residential("plan", ElectricalPanel.new(), false)
	eq(building.rooms["box_24"], "hall bathroom")
	eq(building.device("box_24").kind, "GFCI")
	eq(building.rooms["box_27"], "laundry")
	eq(building.device("box_27").slot, 14)
	eq(building.panel.circuit_at(14).name, "Laundry")


func test_imported_stove_sits_in_front_of_wall_and_fills_30_inch_opening() -> void:
	var house := HouseInterior.new()
	var placed := house._place_asset("res://assets/appliances/KA-F600_Stove_V1.glb", Vector3.ZERO,
			Vector3.RIGHT, Vector3(0.6, 0.88, 0.61), Vector3(0.762, 0.88, 0.66))
	var wrapper := placed["node"] as Node3D
	var model := placed["model"] as Node3D
	near(wrapper.position.x, 0.345, "whole stove moves clear of wall")
	near(model.scale.x, 0.762 / 0.6, "600 mm asset scales to exactly 762 mm")
	house.free()
