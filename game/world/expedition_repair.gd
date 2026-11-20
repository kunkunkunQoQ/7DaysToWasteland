extends Node3D

var session:Node
var id:String
var elapsed:=1.0
var restored:=false

func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<0.7 or not is_instance_valid(session): return
	elapsed=0
	var fixed:bool=session.progress.records.has("exp_"+id)
	if fixed==restored: return
	restored=fixed
	visible=fixed
	if fixed: set_process(false)
