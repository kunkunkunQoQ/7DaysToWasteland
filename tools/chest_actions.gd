extends RefCounted

# Exercise the two explicit player actions in older scenarios that need chest contents.
static func take_all(s:WastelandSession,body:StaticBody3D)->void:
	var original:=s.player.global_position
	s.player.global_position=body.global_position+Vector3.BACK
	var key:String=body.get_meta("key")
	s._open_loot(body)
	s.apply_ui_command("chest_all",[key])
	s.apply_ui_command("chest_close",[key])
	s.player.global_position=original
