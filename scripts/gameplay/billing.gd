class_name Billing
extends RefCounted
## The job sheet: what the customer pays, what your mistakes cost, and the
## stars they give you. Pure arithmetic over the job and how the work went.


## The bottom line of a job.
class JobSheet:
	extends RefCounted
	var lines: Array[String] = []
	var total := 0
	var stars := 5


## How the work went, as far as the bill's concerned.
class Work:
	extends RefCounted
	var dead_tested := false     # proved it dead before touching it
	var thorough := false        # measured before and after
	var shocks := 0
	var arcs := 0
	## What the customer didn't like about how it was done, in their words:
	## a star off for each.
	var flaws: Array[String] = []


## `honest`: told them what it really was, or tried the panel scam.
## `pay_factor`: what your rating's worth (see Aftercare.pay_factor).
static func settle(job: ActiveJob, work: Work, honest: bool, tuning: JobTuning, pay_factor: float) -> JobSheet:
	var sheet := JobSheet.new()
	var lines := sheet.lines
	if honest:
		var labour := int((tuning.call_out + tuning.labour) * pay_factor)
		sheet.total = labour + job.parts_cost(tuning)
		lines.append("Call-out and labour: +$%d (your rating's worth x%.2f)" % [labour, pay_factor])
		lines.append("Parts: +$%d" % job.parts_cost(tuning))
	else:
		sheet.total = tuning.call_out
		sheet.stars -= 3
		lines.append("They saw through it and paid the call-out only: +$%d" % sheet.total)
	if job.no_wire_work():
		pass                         # nothing live was touched, so there was nothing to test dead
	elif work.dead_tested:
		sheet.total += tuning.safe_bonus
		lines.append("Tested dead before touching it: +$%d" % tuning.safe_bonus)
	else:
		sheet.stars -= 1
		lines.append("Never proved it was dead before working on it")
	if work.thorough and job.asked.size() >= 2:
		sheet.total += tuning.thorough_bonus
		lines.append("Asked questions, measured volts and amps: +$%d" % tuning.thorough_bonus)
	if work.shocks > 0:
		sheet.total -= work.shocks * tuning.shock_cost
		sheet.stars -= 2
		lines.append("Shocked %d time(s), first aid: -$%d" % [work.shocks, work.shocks * tuning.shock_cost])
	if work.arcs > 0:
		sheet.total -= work.arcs * tuning.arc_cost
		sheet.stars -= 2
		lines.append("Arc flash or dead short, %d time(s): -$%d" % [work.arcs, work.arcs * tuning.arc_cost])
	for flaw in work.flaws:
		sheet.stars -= 1
		lines.append(flaw)
	if job.wrong_parts > 0:
		sheet.stars -= 1
		lines.append("Wasted %d part(s) on the wrong repair" % job.wrong_parts)
	sheet.stars = clampi(sheet.stars, 1, 5)
	lines.push_front("%s   %d of 5 stars" % [job.address, sheet.stars])
	lines.append("Job total: $%d" % sheet.total)
	return sheet
