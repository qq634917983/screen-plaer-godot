@tool
## 预览 / 转场 / 输出三栏自由分割容器。两条边界按窗口宽度比例保存。
class_name TripleSplitContainer
extends Container

signal ratios_changed(left_ratio: float, right_ratio: float)

const PANEL_NAMES: Array[String] = ["PreviewDock", "TransitionDock", "OutputDock"]

@export var dragger_width := 8:
	set(value):
		dragger_width = maxi(2, value)
		update_minimum_size()
		queue_sort()
@export_range(0.0, 1.0, 0.001) var left_ratio := 0.43:
	set(value):
		left_ratio = clampf(value, 0.0, right_ratio)
		queue_sort()
@export_range(0.0, 1.0, 0.001) var right_ratio := 0.57:
	set(value):
		right_ratio = clampf(value, left_ratio, 1.0)
		queue_sort()

var _drag_boundary := 0


func _get_minimum_size() -> Vector2:
	return Vector2(dragger_width * 2, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _available_width() -> float:
	return maxf(0.0, size.x - dragger_width * 2.0)


func _left_px() -> float:
	return _available_width() * left_ratio


func _right_px() -> float:
	return _available_width() * right_ratio


func _sort_children() -> void:
	var left := _left_px()
	var right := _right_px()
	var g := float(dragger_width)
	var rects: Array[Rect2] = [
		Rect2(0, 0, left, size.y),
		Rect2(left + g, 0, maxf(0.0, right - left), size.y),
		Rect2(right + g * 2.0, 0, maxf(0.0, size.x - right - g * 2.0), size.y),
	]
	for child in get_children():
		if child is Control:
			var idx := PANEL_NAMES.find(child.name)
			if idx == -1:
				idx = mini(child.get_index(), 2)
			child.position = rects[idx].position
			child.size = rects[idx].size
	queue_redraw()


func _draw() -> void:
	var divider := Color(0.10, 0.12, 0.15, 1.0)
	draw_rect(Rect2(_left_px(), 0, dragger_width, size.y), divider)
	draw_rect(Rect2(_right_px() + dragger_width, 0, dragger_width, size.y), divider)


func _boundary_at(pos: Vector2) -> int:
	var half := dragger_width * 0.5
	if absf(pos.x - (_left_px() + half)) <= half:
		return 1
	if absf(pos.x - (_right_px() + dragger_width * 1.5)) <= half:
		return 2
	return 0


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_boundary = _boundary_at(event.position)
			if _drag_boundary != 0:
				mouse_default_cursor_shape = CURSOR_HSIZE
				accept_event()
		elif _drag_boundary != 0:
			_drag_boundary = 0
			mouse_default_cursor_shape = CURSOR_ARROW
			ratios_changed.emit(left_ratio, right_ratio)
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag_boundary != 0:
			if _drag_boundary == 1:
				var ratio := clampf((event.position.x - dragger_width * 0.5) / maxf(_available_width(), 1.0), 0.0, 1.0)
				left_ratio = minf(ratio, right_ratio)
			else:
				var ratio := clampf((event.position.x - dragger_width * 1.5) / maxf(_available_width(), 1.0), 0.0, 1.0)
				right_ratio = maxf(ratio, left_ratio)
			accept_event()
		else:
			mouse_default_cursor_shape = CURSOR_HSIZE if _boundary_at(event.position) else CURSOR_ARROW
