class_name SleepTuning
extends Resource
## Days and nights: how long you can keep going, and when you can turn in.
## The game uses res://data/sleep_tuning.tres: open it in the inspector and
## drag the sliders. Times are hours on the clock (13.5 is 1:30 PM). When the
## sun's up is Sky3D's business (main.gd sets where on Earth the town is).

@export_group("Energy")
## Game hours from fully rested to running on empty.
@export_range(4.0, 40.0, 0.5) var awake_hours := 17.0
## Below this you're tired: the HUD says so.
@export_range(0, 100, 1, "suffix:%") var tired_below := 30.0
## Below this you're exhausted: you slow down.
@export_range(0, 100, 1, "suffix:%") var exhausted_below := 10.0
## How fast you move when you're exhausted, of your usual pace.
@export_range(0.2, 1.0, 0.05) var exhausted_speed := 0.6

@export_group("Sleep")
## You can go to bed from this hour (or any time you're tired).
@export_range(0.0, 24.0, 0.25) var bedtime_hour := 20.0
## When you wake after a night's sleep.
@export_range(0.0, 24.0, 0.25) var wake_hour := 7.0
## When you come round after passing out: late.
@export_range(0.0, 24.0, 0.25) var passed_out_wake_hour := 10.0
