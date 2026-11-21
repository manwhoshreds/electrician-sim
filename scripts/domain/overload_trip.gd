class_name OverloadTrip
extends RefCounted
## A breaker that tripped because too much was running on its circuit, not
## because anything's broken: what was on, and how much it pulled.

var slot := 0
## Amps on the circuit when it let go.
var amps := 0.0
## The breaker's rating.
var rating := 0
## What the customer (or you) had running on it: "toaster", "kettle"...
var appliances: Array[String] = []


## "the toaster and the kettle together", "the microwave".
func what_was_running() -> String:
	var named := appliances.map(func(a: String) -> String: return "the " + a)
	if named.size() == 1:
		return named[0]
	return " and ".join(named) + " together"
