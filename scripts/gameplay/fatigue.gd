class_name Fatigue
extends RefCounted
## How much you've got left in you today. It runs down while you're awake and
## comes back with a night's sleep. Tired, you can turn in early; exhausted,
## you slow down; empty, you pass out where you stand.

var tuning: SleepTuning
## 100 rested, 0 out cold.
var energy := 100.0
## How fast you tire, of the usual: good boots make it less.
var drain := 1.0


func _init(tuning_: SleepTuning = null) -> void:
	tuning = tuning_ if tuning_ != null else SleepTuning.new()


## A stretch of game minutes awake. Returns what you've just become, if it
## changed: "tired", "exhausted", "out", or "".
func tick(minutes: float) -> String:
	var before := state()
	energy = maxf(energy - minutes / (tuning.awake_hours * 60.0) * 100.0 * drain, 0.0)
	var now := state()
	return now if now != before else ""


## "rested", "tired", "exhausted" or "out".
func state() -> String:
	if energy <= 0.0:
		return "out"
	if energy < tuning.exhausted_below:
		return "exhausted"
	if energy < tuning.tired_below:
		return "tired"
	return "rested"


## For the HUD, by the clock: "Tired", "Exhausted"; nothing when you're fine.
func words() -> String:
	return {"tired": "Tired", "exhausted": "Exhausted", "out": "Exhausted"}.get(state(), "")


## How fast you move, of your usual pace.
func speed_factor() -> float:
	return tuning.exhausted_speed if state() == "exhausted" or state() == "out" else 1.0


## Can you go to bed at this time of day? From bedtime till the early hours, or whenever you're tired.
func can_sleep(minutes: float) -> bool:
	var hour := fmod(minutes, 1440.0) / 60.0
	return hour >= tuning.bedtime_hour or hour < tuning.wake_hour or state() != "rested"


## The next time it's `hour` o'clock after `minutes`.
static func next_time(minutes: float, hour: float) -> float:
	var day := floorf(minutes / 1440.0)
	var t := day * 1440.0 + hour * 60.0
	return t if t > minutes else t + 1440.0


func rest() -> void:
	energy = 100.0


func to_save() -> Dictionary:
	return {"energy": energy}


func load_save(d: Dictionary) -> void:
	energy = float(d.get("energy", 100.0))
