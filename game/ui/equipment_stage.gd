extends PanelContainer

func _draw() -> void:
	# The sight lines on the fitting board leave the silhouette and slot art clear.
	var edge := Color("#495a4a")
	var brass := Color("#927858")
	var mid := size.x * 0.5
	var floor_y := size.y-9.0
	for side: float in [-1.0,1.0]:
		var origin := Vector2(7 if side>0 else size.x-7,7)
		draw_line(origin,origin+Vector2(side*15,0),brass,1.3,true)
		draw_line(origin,origin+Vector2(0,12),brass,1.3,true)
		draw_line(Vector2(mid+side*38,floor_y),Vector2(mid+side*74,floor_y),edge,1,true)
	var shadow := PackedVector2Array()
	for i in 40:
		var angle := TAU*i/40.0
		shadow.append(Vector2(mid+cos(angle)*36,floor_y-2+sin(angle)*3.5))
	draw_colored_polygon(shadow,Color("#172720"))
