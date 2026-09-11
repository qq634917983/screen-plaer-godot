@tool
## 十字四分区容器：左上/右上/左下/右下四个面板，竖横两条分割条在中心交叉。
## 分割位置以比例存储，窗口缩放时按比例伸缩（放大窗口各分区按历史比例放大）；
## 拖拽竖条/横条/交叉点调整布局，拖拽结束发 ratios_changed 供持久化。
class_name QuadSplitContainer
extends Container

## 拖拽结束（或程序化设置）后发出，参数为当前分割比例
signal ratios_changed(x_ratio: float, y_ratio: float)

## 四个象限按子节点名字对位（找不到名字的子节点退回按声明顺序）
const QUADRANT_NAMES: Array[String] = ["PlayersSection", "UtilityPanel", "MediaPanel", "AudioPanel"]

@export var dragger_width: int = 10:
	set(value):
		dragger_width = value
		update_minimum_size()
		queue_sort()
@export_range(0.05, 0.95) var split_x_ratio: float = 0.72:
	set(value):
		split_x_ratio = value
		update_minimum_size()
		queue_sort()
@export_range(0.05, 0.95) var split_y_ratio: float = 0.5:
	set(value):
		split_y_ratio = value
		update_minimum_size()
		queue_sort()
## 第一列宽度、第一排高度的百分比约束；第二侧自动占用剩余空间。
## 控件实际最小尺寸仍具有更高优先级，防止标题和按钮被遮盖。
@export_range(5.0, 95.0, 1.0) var min_x_percent := 35.0:
	set(value):
		min_x_percent = clampf(value, 5.0, 95.0)
		update_minimum_size()
		queue_sort()
@export_range(5.0, 95.0, 1.0) var max_x_percent := 85.0:
	set(value):
		max_x_percent = clampf(value, 5.0, 95.0)
		update_minimum_size()
		queue_sort()
@export_range(5.0, 95.0, 1.0) var min_y_percent := 35.0:
	set(value):
		min_y_percent = clampf(value, 5.0, 95.0)
		update_minimum_size()
		queue_sort()
@export_range(5.0, 95.0, 1.0) var max_y_percent := 75.0:
	set(value):
		max_y_percent = clampf(value, 5.0, 95.0)
		update_minimum_size()
		queue_sort()

var _drag_mode := 0  # 0=无 1=竖条 2=横条 3=交叉点（两轴一起）


func _get_minimum_size() -> Vector2:
	var limits := _panel_minimums()
	return Vector2(limits.x + limits.y + dragger_width, limits.z + limits.w + dragger_width)


## 系统字体的字形高度不同，四象限不能小于实际控件最小尺寸。
## 否则 macOS 回退字体下，媒体面板会盖住上方播放器控制条。
func _panel_minimums() -> Vector4:
	var limits := Vector4.ZERO
	for child in get_children():
		if not child is Control or not child.visible:
			continue
		var idx := QUADRANT_NAMES.find(child.name)
		if idx == -1:
			idx = mini(child.get_index(), 3)
		var minimum: Vector2 = child.get_combined_minimum_size()
		var col := idx % 2
		var row := 2 + idx / 2
		limits[col] = maxf(limits[col], minimum.x)
		limits[row] = maxf(limits[row], minimum.y)
	return limits


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _split_x_px() -> float:
	var limits := _panel_minimums()
	var bounds := _axis_bounds(size.x, limits.x, limits.y, min_x_percent, max_x_percent)
	return clampf(size.x * split_x_ratio, bounds.x, bounds.y)


func _split_y_px() -> float:
	var limits := _panel_minimums()
	var bounds := _axis_bounds(size.y, limits.z, limits.w, min_y_percent, max_y_percent)
	return clampf(size.y * split_y_ratio, bounds.x, bounds.y)


## 把第一列/排的百分比范围换算为当前容器像素范围。
## 百分比与控件最小尺寸冲突时，优先保证两侧控件实际最小尺寸。
func _axis_bounds(total: float, min_a: float, min_b: float, min_percent: float, max_percent: float) -> Vector2:
	var available := maxf(0.0, total - dragger_width)
	var base_low := min_a
	var base_high := maxf(base_low, available - min_b)
	var low := maxf(base_low, available * min_percent / 100.0)
	var high := minf(base_high, available * max_percent / 100.0)
	if low > high:
		return Vector2(base_low, base_high)
	return Vector2(low, high)


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
			var limits := _panel_minimums()
			if _drag_mode & 1:
				var x_bounds := _axis_bounds(size.x, limits.x, limits.y, min_x_percent, max_x_percent)
				var px := clampf(event.position.x, x_bounds.x, x_bounds.y)
				split_x_ratio = px / maxf(size.x, 1.0)
			if _drag_mode & 2:
				var y_bounds := _axis_bounds(size.y, limits.z, limits.w, min_y_percent, max_y_percent)
				var py := clampf(event.position.y, y_bounds.x, y_bounds.y)
				split_y_ratio = py / maxf(size.y, 1.0)
			queue_sort()
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_zone(_hit_zone(event.position))
