class_name BusinessStats
extends RefCounted
## Running totals for the business: what every job has brought in, all time
## and this game week. A week is seven game days on the clock.

const MINUTES_PER_WEEK := 1440 * 7

var total_earned := 0
var week := 0                    # which game week week_earned is for
var week_earned := 0


## A job sheet's total (can be negative), at this point on the game clock.
func record(amount: int, clock_minutes: float) -> void:
	total_earned += amount
	var now := int(clock_minutes / MINUTES_PER_WEEK)
	if now != week:
		week = now
		week_earned = 0
	week_earned += amount


## This week's takings, as of now (nothing yet if a new week's started).
func this_week(clock_minutes: float) -> int:
	return week_earned if int(clock_minutes / MINUTES_PER_WEEK) == week else 0


func to_save() -> Dictionary:
	return {"total_earned": total_earned, "week": week, "week_earned": week_earned}


func load_save(d: Dictionary) -> void:
	total_earned = int(d.get("total_earned", 0))
	week = int(d.get("week", 0))
	week_earned = int(d.get("week_earned", 0))
