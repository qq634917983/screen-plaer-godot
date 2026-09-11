@tool
## 可自由折叠的十字四分区容器。分割位置用窗口比例保存，缩放窗口时布局同比变化。
class_name QuadSplitContainer
extends Container

signal ratios_changed(x_ratio: float, y_ratio: float)

const QUADRANT_NAMES: Array[String] = ["PlayersSection", "UtilityDock", "MediaDock", "AudioDock"]

@export var dragger_width := 10:
	set(value):
		dragger_width = maxi(2, value)
		update_minimum_size()
		queue_sort()
@export_range(0.0, 1.0, 0.001) var split_x_ratio := 0.72:
	set(value):
		split_x_ratio = clampf(value, 0.0, 1.0)
		queue_sort()
@export_range(0.0, 1.0, 0.001) var split_y_ratio := 0.5:
	set(value):
		split_y_ratio = clampf(value, 0.0, 1.0)
		queue_sort()

var _drag_mode := 0 # 0=无 1=竖条 2=横条 3=交叉点


func _get_minimum_size() -> Vector2:
	return Vector2(dragger_width, dragger_width)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _available_x() -> float:
	return maxf(0.0, size.x - dragger_width)


func _available_y() -> float:
	return maxf(0.0, size.y - dragger_width)


func _split_x_px() -> float:
	return _available_x() * split_x_ratio


func _split_y_px() -> float:
	return _available_y() * split_y_ratio


func _sort_children() -> void:
	var sx := _split_x_px()
	var sy := _split_y_px()
	var g := float(dragger_width)
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, sx, sy),
		Rect2(sx + g, 0.0, maxf(0.0, size.x - sx - g), sy),
		Rect2(0.0, sy + g, sx, maxf(0.0, size.y - sy - g)),
		Rect2(sx + g, sy + g, maxf(0.0, size.x - sx - g), maxf(0.0, size.y - sy - g)),
	]
	for child in get_children():
		if child is Control:
			var idx := QUADRANT_NAMES.find(child.name)
			if idx == -1:
				idx = mini(child.get_index(), 3)
			child.position = rects[idx].position
			child.size = rects[idx].size
	queue_redraw()


func _draw() -> void:
	var divider := Color(0.10, 0.12, 0.15, 1.0)
	draw_rect(Rect2(_split_x_px(), 0, dragger_width, size.y), divider)
	draw_rect(Rect2(0, _split_y_px(), size.x, dragger_width), divider)


func _hit_zone(pos: Vector2) -> int:
	var half := dragger_width * 0.5
	var in_v := absf(pos.x - (_split_x_px() + half)) <= half
	var in_h := absf(pos.y - (_split_y_px() + half)) <= half
	return (1 if in_v else 0) | (2 if in_h else 0)


func _cursor_for_zone(zone: int) -> CursorShape:
	match zone:
		1: return CURSOR_HSIZE
		2: return CURSOR_VSIZE
		3: return CURSOR_MOVE
	return CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_mode = _hit_zone(event.position)
			if _drag_mode != 0:
				mouse_default_cursor_shape = _cursor_for_zone(_drag_mode)
				accept_event()
		elif _drag_mode != 0:
			_drag_mode = 0
			mouse_default_cursor_shape = CURSOR_ARROW
			ratios_changed.emit(split_x_ratio, split_y_ratio)
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag_mode != 0:
			if _drag_mode & 1:
				split_x_ratio = clampf((event.position.x - dragger_width * 0.5) / maxf(_available_x(), 1.0), 0.0, 1.0)
			if _drag_mode & 2:
				split_y_ratio = clampf((event.position.y - dragger_width * 0.5) / maxf(_available_y(), 1.0), 0.0, 1.0)
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_zone(_hit_zone(event.position))
