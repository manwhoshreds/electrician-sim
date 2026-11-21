class_name WorkLog
extends RefCounted
## What you did at one panel or box on this job: the record the job card,
## the bill and the review are judged on. Written by the close-up where you
## did it; read by the job.

## Proved the hots dead with a meter before working on them.
var verified_dead := false
## Saw what it was doing before fixing it (a box).
var measured_live := false
## Tested it good with the power back on, after the work (a box).
var tested_after := false
## Took something apart, swapped a device, landed a wire (a box).
var worked_on := false
## Read the customer's circuit's voltage (the panel).
var measured_target := false
## Clamped the customer's circuit's wire (the panel).
var measured_amps := false
var shocks := 0
## Arc flashes and dead shorts.
var arcs := 0
