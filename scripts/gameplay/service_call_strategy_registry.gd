class_name ServiceCallStrategyRegistry
extends RefCounted
## Maps definition data to reusable generation behavior without a central
## match statement over every call type.

var _strategies := {}


func _init() -> void:
	register("dead_receptacles", DeadReceptaclesStrategy.new())
	register("device_fault", DeviceFaultStrategy.new())
	var breaker := BreakerTripStrategy.new()
	register("breaker_trip", breaker)
	register("breaker_fault", breaker)      # open and hot breakers: same behaviour, clearer name in the data
	register("water_heater", WaterHeaterStrategy.new())
	register("install_device", InstallDeviceStrategy.new())
	register("on_arrival", OnArrivalStrategy.new())
	register("recessed_lights", RecessedLightsStrategy.new())


func register(id: String, strategy: ServiceCallGenerationStrategy) -> void:
	_strategies[id] = strategy


func resolve(id: String) -> ServiceCallGenerationStrategy:
	return _strategies.get(id)
