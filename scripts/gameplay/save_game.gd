class_name SaveGame
extends RefCounted
## The save file: one JSON file in user://, written between jobs. Each piece
## of the game saves and loads its own part (to_save / load_save); this
## gathers them into one file and hands them back.
##
## It's written to a .tmp file and swapped in, so a crash mid-write leaves
## the last good save. A file that can't be read is moved aside to .bad,
## never deleted, and the game starts fresh.
##
## The file is plain JSON so it can be read and fixed by hand. Bump VERSION
## when the format changes in a way older files can't be loaded as.

const VERSION := 1
const PATH := "user://save.json"

## Off for tests and headless runs, so they never touch a real save.
static var enabled := true

var path := PATH
## Why the last read() came back empty, if it wasn't just "no save yet".
var problem := ""


func _init(path_ := PATH) -> void:
	path = path_


# --- Gathering and handing back --------------------------------------------------------

## Everything worth keeping, from the pieces that own it. Call between jobs.
static func capture(service: ServiceCall, utility: PowerCompany, town: Town) -> Dictionary:
	var meters := {}
	for h: Dictionary in town.houses:
		if h.has("meter_box"):
			var m: MeterBase = h["meter_box"]
			meters[m.address] = m.to_save()
	return {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(), "service": service.to_save(),
			"power_company": utility.to_save(), "meters": meters}


## Puts a saved game back into a freshly started one.
static func apply(data: Dictionary, service: ServiceCall, utility: PowerCompany, town: Town) -> void:
	service.load_save(data.get("service", {}))
	utility.load_save(data.get("power_company", {}))
	var meters: Dictionary = data.get("meters", {})
	for h: Dictionary in town.houses:
		if h.has("meter_box"):
			var m: MeterBase = h["meter_box"]
			if meters.has(m.address):
				m.load_save(meters[m.address])


# --- The file ----------------------------------------------------------------------------

func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp")


## Writes the file. False (and `problem` says why) if it couldn't.
func write(data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		problem = "couldn't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
		push_warning("Save failed: " + problem)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_global(path))
	var err := DirAccess.rename_absolute(_global(tmp), _global(path))
	if err != OK:
		problem = "couldn't move the new save into place (%s)" % error_string(err)
		push_warning("Save failed: " + problem)
		return false
	problem = ""
	return true


## The saved game, or {} if there isn't one (or it couldn't be read: see `problem`).
func read() -> Dictionary:
	problem = ""
	var from := path
	if not FileAccess.file_exists(path):
		if not FileAccess.file_exists(path + ".tmp"):
			return {}
		from = path + ".tmp"          # crashed between writing and swapping in: the new one's whole
	var json := JSON.new()                # not JSON.parse_string: that prints an engine error on a bad file
	if json.parse(FileAccess.get_file_as_string(from)) != OK or not json.data is Dictionary:
		return _set_aside(from, "the save file is damaged")
	var data: Dictionary = json.data
	var version := int(data.get("version", 0))
	if version != VERSION:
		return _set_aside(from, "the save file is from a different version (%d, this game reads %d)" % [version, VERSION])
	return data


## Deletes the save, for a new game.
func delete() -> void:
	for p in [path, path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(_global(p))


func _set_aside(from: String, why: String) -> Dictionary:
	problem = why + "; it's been kept as %s" % (path + ".bad")
	push_warning("Save not loaded: " + problem)
	if FileAccess.file_exists(path + ".bad"):
		DirAccess.remove_absolute(_global(path + ".bad"))
	DirAccess.rename_absolute(_global(from), _global(path + ".bad"))
	return {}


static func _global(p: String) -> String:
	return ProjectSettings.globalize_path(p)
