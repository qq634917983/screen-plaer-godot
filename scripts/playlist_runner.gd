class_name PlaylistRunner
extends Node
## 播放列表执行器：把列表条目依次推送到输出端播放。
## 计时用墙钟（Time.get_ticks_msec），与帧源类型无关——静态/网页/PPT 没有
## 播放进度，视频/音频的"播完"也没有 end-file 事件可靠判定，统一墙钟最稳：
## - 条目时长 > 0：播满该秒数（= 距下一条的间隔）
## - 条目时长 = 0：视频/音频等输出端拿到真实时长后按"进度到尾 或
##   墙钟超过时长+2s 兜底"计一次；图片/网页/PPT 按 DEFAULT_ITEM_DURATION
## - 条目 count > 1：同一项连续重播（重新加载），播够次数才切下一条
## - 列表 duration > 0：播完一轮回到第一条循环，直到播满列表总时长
## 外部干预（手动推送/快速切换/输出停止）自动让出：输出端媒体路径与当前
## 条目不一致即静默停止（PPT 后台转换期间除外——经 is_pending 查询）。

signal started(playlist: PlaylistObject)
signal item_started(playlist: PlaylistObject, index: int)
signal stopped(playlist: PlaylistObject, reason: String)  # finished | manual

var playlist: PlaylistObject  # 正在执行的列表（null = 空闲）
var item_index := -1

var _slot: PlayerSlot
var _load_item: Callable   # func(path: String) -> bool：加载到输出端，false = 无法播放
var _is_pending: Callable  # func(path: String) -> bool：该路径正在后台转换中（PPT）
var _item_clock_started := false
var _item_start_msec := 0
var _list_start_msec := 0
var _item_repeat := 0  # 当前条目已播放次数（播够 count 才切下一条）


func setup(slot: PlayerSlot, load_item: Callable, is_pending: Callable) -> void:
	_slot = slot
	_load_item = load_item
	_is_pending = is_pending


func is_active() -> bool:
	return playlist != null


func start(pl: PlaylistObject) -> bool:
	if pl == null or pl.items.is_empty():
		return false
	playlist = pl
	item_index = -1
	_list_start_msec = Time.get_ticks_msec()
	AppLog.info("playlist", "started", {"name": pl.name, "items": pl.items.size()})
	started.emit(pl)
	_advance(0)
	var ok := playlist != null  # 全部条目不可播时 _advance 已自行停止
	return ok


func stop(reason := "manual") -> void:
	if playlist == null:
		return
	var pl := playlist
	playlist = null
	item_index = -1
	_item_repeat = 0
	AppLog.info("playlist", "stopped", {"name": pl.name, "reason": reason})
	stopped.emit(pl, reason)


func _process(_delta: float) -> void:
	if playlist == null:
		return
	var path := _current_path()
	if _is_pending.call(path):
		return  # PPT 后台转换中，等待起播
	if _slot.media_path != path:
		if not _item_clock_started and _slot.media_path.is_empty():
			return  # 加载途中（首帧未至）
		stop("manual")  # 输出端被外部接管/停止，让出
		return
	var now := Time.get_ticks_msec()
	if not _item_clock_started:
		# 条目真正上屏才开始计时；列表模式禁用单条循环（否则视频永远播不完）
		_item_clock_started = true
		_item_start_msec = now
		_slot.set_looping(false)
		AppLog.info("playlist", "item_started", {"index": item_index, "resource": AppLog.media_ref(path)})
		item_started.emit(playlist, item_index)
		return
	# 列表总时长：播满即停（判定先于条目推进，末尾项不拖尾）
	if playlist.duration > 0.0 and now - _list_start_msec >= int(playlist.duration * 1000.0):
		stop("finished")
		return
	var item_dur := float(playlist.items[item_index]["duration"])
	if item_dur > 0.0:
		if now - _item_start_msec >= int(item_dur * 1000.0):
			_advance(0)
		return
	# 时长 0：视频/音频播到自然结束；无自然时长的媒体按默认秒数
	if _slot.duration > 0.0:
		if _slot.elapsed >= _slot.duration - 0.3:
			_advance(0)
		elif now - _item_start_msec >= int((_slot.duration + 2.0) * 1000.0):
			_advance(0)  # 墙钟兜底：time_changed 停发/卡住也能推进
	elif _slot.source_kind != PlayerSlot.SourceKind.MPV:
		if now - _item_start_msec >= int(PlaylistObject.DEFAULT_ITEM_DURATION * 1000.0):
			_advance(0)


func _current_path() -> String:
	if playlist == null or item_index < 0 or item_index >= playlist.items.size():
		return ""
	return str(playlist.items[item_index]["path"])


## 推进：当前条目播够 count 次才切下一条（重播 = 重新加载同一条目）；
## depth 防止全部条目不可播时无限递归（一轮最多 total_plays 次加载尝试）
func _advance(depth: int) -> void:
	if playlist == null:
		return
	if depth > playlist.total_plays():
		stop("finished")  # 全部条目都无法播放
		return
	if item_index >= 0:
		_item_repeat += 1
		if _item_repeat < PlaylistObject.item_count(playlist.items[item_index]):
			_item_clock_started = false
			if not _load_item.call(_current_path()):
				_advance(depth + 1)
			return
		_item_repeat = 0
	item_index += 1
	var now := Time.get_ticks_msec()
	if item_index >= playlist.items.size():
		# 一轮播完：列表设了总时长且未播满则循环，否则结束
		if playlist.duration > 0.0 and now - _list_start_msec < int(playlist.duration * 1000.0):
			item_index = 0
			_item_repeat = 0
		else:
			stop("finished")
			return
	_item_clock_started = false
	if not _load_item.call(_current_path()):
		_advance(depth + 1)  # 条目丢失/不可播：跳过
