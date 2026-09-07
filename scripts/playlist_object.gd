class_name PlaylistObject
extends RefCounted
## 播放列表：媒体库条目的有序组合。
## - items：{ path, duration }，duration 秒；0 = 视频/音频播到自然结束，
##   图片/网页/PPT 等无自然时长的媒体按 DEFAULT_ITEM_DURATION 秒计
## - duration：列表整体播放时间（秒）；0 = 播完一轮即停，
##   >0 = 循环整个列表直到播满该时长
## - 定时自动播放：auto_enabled + auto_start/auto_stop（"HH:MM"，支持跨午夜；
##   开启 == 关闭 视为全天）；由主窗口每秒检查，到时段自动起播/停止
## 随项目 *.splproj 持久化（playlist/lists 段）。

const DEFAULT_ITEM_DURATION := 10.0  # 无自然时长媒体的默认播放秒数

var name := "播放列表"
var items: Array[Dictionary] = []  # { "path": String, "duration": float }
var duration := 0.0
var auto_enabled := false
var auto_start := "08:00"
var auto_stop := "20:00"


func add_item(path: String, dur := 0.0) -> void:
	items.append({"path": path, "duration": dur})


func remove_item(index: int) -> void:
	if index >= 0 and index < items.size():
		items.remove_at(index)


func move_item(index: int, delta: int) -> void:
	var to := index + delta
	if index < 0 or index >= items.size() or to < 0 or to >= items.size():
		return
	var it: Dictionary = items[index]
	items.remove_at(index)
	items.insert(to, it)


## 列表一轮的估算时长（秒）；含"播完整个媒体"项时返回 -1（时长未知）
func estimated_round_duration() -> float:
	var total := 0.0
	for it in items:
		var d := float(it["duration"])
		if d <= 0.0:
			return -1.0
		total += d
	return total


## "HH:MM" → 当天分钟数；非法返回 -1
static func parse_hhmm(text: String) -> int:
	var p := text.strip_edges().split(":")
	if p.size() != 2:
		return -1
	if not p[0].is_valid_int() or not p[1].is_valid_int():
		return -1
	var h := p[0].to_int()
	var m := p[1].to_int()
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m


## 当前系统时刻是否处于自动播放时段（支持跨午夜：开启 > 关闭 = 跨天；
## 开启 == 关闭 = 全天）
func is_in_schedule_now() -> bool:
	var s := parse_hhmm(auto_start)
	var e := parse_hhmm(auto_stop)
	if s < 0 or e < 0:
		return false
	if s == e:
		return true
	var t := Time.get_time_dict_from_system()
	var now: int = t["hour"] * 60 + t["minute"]
	if s < e:
		return now >= s and now < e
	return now >= s or now < e


func to_dict() -> Dictionary:
	var item_dicts: Array = []
	for it in items:
		item_dicts.append({"path": str(it["path"]), "duration": float(it["duration"])})
	return {
		"name": name,
		"items": item_dicts,
		"duration": duration,
		"auto_enabled": auto_enabled,
		"auto_start": auto_start,
		"auto_stop": auto_stop,
	}


static func from_dict(d: Dictionary) -> PlaylistObject:
	var pl := PlaylistObject.new()
	pl.name = str(d.get("name", "播放列表"))
	for it in d.get("items", []):
		pl.add_item(str(it.get("path", "")), float(it.get("duration", 0.0)))
	pl.duration = float(d.get("duration", 0.0))
	pl.auto_enabled = bool(d.get("auto_enabled", false))
	pl.auto_start = str(d.get("auto_start", "08:00"))
	pl.auto_stop = str(d.get("auto_stop", "20:00"))
	return pl
