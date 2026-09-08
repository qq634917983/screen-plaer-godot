## 十字四分区容器：左上/右上/左下/右下四个面板，竖横两条分割条在中心交叉。
## 分割位置以比例存储，窗口缩放时按比例伸缩（放大窗口各分区按历史比例放大）；
## 拖拽竖条/横条/交叉点调整布局，拖拽结束发 ratios_changed 供持久化。
class_name QuadSplitContainer
extends Container

## 拖拽结束（或程序化设置）后发出，参数为当前分割比例
signal ratios_changed(x_ratio: float, y_ratio: float)

## 四个象限按子节点名字对位（找不到名字的子节点退回按声明顺序）
const QUADRANT_NAMES: Array[String] = ["PlayersSection", "UtilityPanel", "MediaPanel", "AudioPanel"]

@export var dragger_width: int = 10
@export_range(0.05, 0.95) var split_x_ratio: float = 0.72
@export_range(0.05, 0.95) var split_y_ratio: float = 0.5
@export var min_left := 420.0
@export var min_right := 220.0
@export var min_top := 260.0
@export var min_bottom := 180.0

var _drag_mode := 0  # 0=无 1=竖条 2=横条 3=交叉点（两轴一起）


func _get_minimum_size() -> Vector2:
	return Vector2(min_left + min_right + dragger_width, min_top + min_bottom + dragger_width)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _split_x_px() -> float:
	return clampf(size.x * split_x_ratio, min_left, maxf(min_left, size.x - dragger_width - min_right))


func _split_y_px() -> float:
	return clampf(size.y * split_y_ratio, min_top, maxf(min_top, size.y - dragger_width - min_bottom))


func _sort_children() -> void:
	var sx := _split_x_px()
	var sy := _split_y_px()
	var g := float(dragger_width)
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, sx, sy),
		Rect2(sx + g, 0.0, size.x - sx - g, sy),
		Rect2(0.0, sy + g, sx, size.y - sy - g),
		Rect2(sx + g, sy + g, size.x - sx - g, size.y - sy - g),
	]
	for child in get_children():
		if child is Control:
			var idx := QUADRANT_NAMES.find(child.name)
			if idx == -1:
				idx = mini(child.get_index(), 3)
			fit_child_in_rect(child, rects[idx])


func _hit_zone(pos: Vector2) -> int:
	var half := dragger_width * 0.5
	var in_v := absf(pos.x - (_split_x_px() + half)) <= half
	var in_h := absf(pos.y - (_split_y_px() + half)) <= half
	return (1 if in_v else 0) | (2 if in_h else 0)


func _cursor_for_zone(zone: int) -> CursorShape:
	match zone:
		1:
			return CURSOR_HSIZE
		2:
			return CURSOR_VSIZE
		3:
			return CURSOR_MOVE
	return CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
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
				var px := clampf(event.position.x, min_left, maxf(min_left, size.x - dragger_width - min_right))
				split_x_ratio = px / maxf(size.x, 1.0)
			if _drag_mode & 2:
				var py := clampf(event.position.y, min_top, maxf(min_top, size.y - dragger_width - min_bottom))
				split_y_ratio = py / maxf(size.y, 1.0)
			queue_sort()
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_zone(_hit_zone(event.position))
