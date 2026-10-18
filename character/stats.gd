extends Label

func _process(_delta: float) -> void:
	var fps = Engine.get_frames_per_second()
	var ms = 1000.0 / maxf(1.0, float(fps))
	text = """FPS: %d
Frame Time: %.2f ms
""" % [fps, ms]
