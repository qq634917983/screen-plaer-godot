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
@export var minimum_pane_height := 44:
	set(value):
		minimum_pane_height = maxi(0, value)
		queue_sort()

var _drag_mode := 0 # 0=无 1=竖条 2=横条 3=交叉点


func _get_minimum_size() -> Vector2:
	var mins := _pane_minimums()
	return Vector2(mins[0] + mins[1] + dragger_width, mins[2] + mins[3] + dragger_width)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _available_x() -> float:
	return maxf(0.0, size.x - dragger_width)


func _available_y() -> float:
	return maxf(0.0, size.y - dragger_width)


func _split_x_px() -> float:
	var mins := _pane_minimums()
	return _bounded_split(_available_x(), _available_x() * split_x_ratio, mins[0], mins[1])


func _split_y_px() -> float:
	var available := _available_y()
	var mins := _pane_minimums()
	return _bounded_split(available, available * split_y_ratio, mins[2], mins[3])


## 返回左列、右列、上排、下排的实际最小尺寸。
func _pane_minimums() -> Array[float]:
	var result: Array[float] = [0.0, 0.0, float(minimum_pane_height), float(minimum_pane_height)]
	for child in get_children():
		if not child is Control:
			continue
		var idx := QUADRANT_NAMES.find(child.name)
		if idx < 0:
			continue
		var minimum := (child as Control).get_combined_minimum_size()
		if idx == 0 or idx == 2:
			result[0] = maxf(result[0], minimum.x)
		else:
			result[1] = maxf(result[1], minimum.x)
		if idx == 0 or idx == 1:
			result[2] = maxf(result[2], minimum.y)
		else:
			result[3] = maxf(result[3], minimum.y)
	return result


func _bounded_split(available: float, desired: float, first_min: float, second_min: float) -> float:
	if available <= 0.0:
		return 0.0
	var total_min := first_min + second_min
	if total_min > available and total_min > 0.0:
		return available * first_min / total_min
	return clampf(desired, first_min, available - second_min)


func effective_split_y_ratio() -> float:
	return _split_y_px() / maxf(_available_y(), 1.0)


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
				var available_x := maxf(_available_x(), 1.0)
				var mins := _pane_minimums()
				var split_x := _bounded_split(available_x,
					event.position.x - dragger_width * 0.5, mins[0], mins[1])
				split_x_ratio = split_x / available_x
			if _drag_mode & 2:
				var available := maxf(_available_y(), 1.0)
				var mins := _pane_minimums()
				var split_y := _bounded_split(available,
					event.position.y - dragger_width * 0.5, mins[2], mins[3])
				split_y_ratio = split_y / available
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_zone(_hit_zone(event.position))
