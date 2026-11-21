class_name PropertyRegistry
extends RefCounted
## Every property in town and its electrical installation, kept between
## visits and saved. A house's wiring exists here whether or not you've ever
## been inside: a fault dispatch puts in a house you haven't reached yet is
## still there after a save. Faults and changes live in the building model;
## calls only point at them.
##
## Houses you've worked at are also in Aftercare (it plays out the days after
## you leave); the two share the one ElectricalPanel per house.

## The town's properties: {address, two_story, business, ...}, in town order.
var properties: Array = []
var aftercare: Aftercare
var _models := {}                 # address -> BuildingElectricalModel


func _init(properties_: Array = [], aftercare_: Aftercare = null) -> void:
	properties = properties_
	aftercare = aftercare_


## The property with this address, or {}.
func property(address: String) -> Dictionary:
	for p: Dictionary in properties:
		if p["address"] == address:
			return p
	return {}


## Homes a residential call can go to: not businesses, and not your own house.
func residential() -> Array:
	return properties.filter(func(p: Dictionary) -> bool: return not p.get("business", false) and not p.get("home", false))


func property_type(p: Dictionary) -> String:
	return "commercial" if p.get("business", false) else "residential"


## The house's installation, built the first time it's asked for: from what
## Aftercare remembers of it if you've been, or as built.
func model_for(address: String) -> BuildingElectricalModel:
	if _models.has(address):
		return _models[address]
	var p := property(address)
	var panel: ElectricalPanel = aftercare.sim_for(address) if aftercare != null else null
	if panel == null:
		panel = ElectricalPanel.new()
	var m := BuildingElectricalModel.residential(address, panel, bool(p.get("two_story", false)))
	m.property_type = property_type(p)
	if aftercare != null:
		m.restore(aftercare.state_for(address))
	_models[address] = m
	return m


func has_model(address: String) -> bool:
	return _models.has(address)


func to_save() -> Dictionary:
	var out := {}
	for address: String in _models:
		out[address] = (_models[address] as BuildingElectricalModel).to_save()
	return out


## After Aftercare's loaded: the saved installations, sharing Aftercare's
## panel for houses it knows, so there's one panel per house.
func load_save(d: Dictionary) -> void:
	_models.clear()
	for address: String in d:
		var saved: Dictionary = d[address]
		var panel := ElectricalPanel.from_save(saved.get("panel", {}))
		if aftercare != null and aftercare.houses.has(address):
			aftercare.houses[address]["sim"] = panel
		_models[address] = BuildingElectricalModel.from_save(saved, panel)
