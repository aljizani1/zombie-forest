# عقدة ترسم نفسها بدالة وحدة (مرة وحدة، والـ Godot يحفظ الرسم لحد ما نطلب queue_redraw)
extends Node2D

var fn: Callable


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
