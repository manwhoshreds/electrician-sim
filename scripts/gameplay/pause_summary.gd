class_name PauseSummary
extends RefCounted
## Everything the pause screen shows, read out of the game at the moment you
## pause (ServiceCall.pause_summary()). The screen only displays it.

# --- The top bar ---------------------------------------------------------------------
var day_text := ""               # "Tue, Day 3"
var time_text := ""              # "10:24 AM"
var money := 0

# --- The business ----------------------------------------------------------------------
var rating := 5.0
var review_count := 0
var active_calls := 0
var total_earned := 0
var week_earned := 0
## Newest first. Each {name, stars, text, address, about, day}.
var reviews: Array[Dictionary] = []
## True between jobs: the only time there's nothing half-done to lose.
var can_save := true

# --- The job you're on (has_job false between calls) ---------------------------------------
var has_job := false
var job_title := ""              # "Okafor Residence"
var address := ""
var home_type := ""              # "Single-family home, one story"
var status := ""                 # "IN PROGRESS", "WARRANTY CALLBACK"
var complaint := ""              # what they said, or the dispatch line before you've met
var job_type := ""               # "Troubleshooting / Repair", "Installation"...
var payout := 0
## [[text, done], ...]
var objectives: Array = []
## Things known about it so far: [[text, highlight], ...]
var details: Array = []
## Slot -> circuit name, for the panel directory.
var directory: Array[String] = []

# --- The truck ------------------------------------------------------------------------------
var vehicle_word := "truck"
var load_used := 0
var capacity := 0
## [[part name, how many], ...]
var stock: Array = []
var in_hand := ""                # "20 A breaker", "GFCI receptacle", or ""
var account := ""                # the supply house account, in a line
