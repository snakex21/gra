class_name ArenaArtBuild
extends RefCounted
## A queue of small render-only jobs. One job can span several physics ticks.
var jobs: Array[Callable] = []
var cursor := 0
var max_step_usec := 0

func step(budget_usec := 2000, max_units := 4) -> bool:
	var began := Time.get_ticks_usec()
	var units := 0
	while cursor < jobs.size() and units < max_units:
		if bool(jobs[cursor].call()):
			cursor += 1
		units += 1
		if Time.get_ticks_usec() - began >= budget_usec:
			break
	max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - began)
	return cursor >= jobs.size()

func add(action: Callable) -> void:
	jobs.append(func() -> bool:
		action.call()
		return true)
