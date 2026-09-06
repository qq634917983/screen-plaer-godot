class_name Thumbnailer
extends Node
## 后台视频封面截取：独立的 MPVPlayer 实例（静音、不上屏）逐个装载队列视频，
## 起播后 seek 到 capture_pos 秒抓帧。与预览/输出播放端互不影响。
## 注意：load 后 mpv 会补发上一文件的残留纹理和时间信号，因此必须等
## time_changed 落到目标位置附近、取当时的最新纹理，才是当前文件的帧。

signal thumbnail_ready(path: String, image: Image)
signal thumbnail_failed(path: String)

const PER_FILE_TIMEOUT := 4.0

var capture_pos := 1.0  # 封面截取位置（秒），由设置读取

var _mpv: Node
var _queue: Array[String] = []
var _current := ""
var _state := 0  # 0 空闲 / 1 等待当前文件起播 / 2 已 seek，等时间到位
var _timer := 0.0
var _target := 1.0
var _latest_tex: Texture2D
var _seek_retries := 0


func _ready() -> void:
	if not ClassDB.class_exists(&"MPVPlayer"):
		push_warning("MPVPlayer 未加载，封面截取不可用")
		return
	_mpv = ClassDB.instantiate(&"MPVPlayer")
	add_child(_mpv)
	if not _mpv.call("initialize"):
		push_warning("封面截取器 MPV 初始化失败")
		_mpv = null
		return
	_mpv.call("set_volume", "0")  # 抓帧不出声
	_mpv.connect("texture_updated", _on_texture_updated)
	_mpv.connect("time_changed", _on_time_changed)


func enqueue(paths: Array) -> void:
	for p in paths:
		if p != _current and not _queue.has(p):
			_queue.append(p)
	_kick()


func _kick() -> void:
	if _state != 0 or _queue.is_empty() or _mpv == null:
		return
	_current = _queue.pop_front()
	_state = 1
	_timer = 0.0
	_latest_tex = null
	_seek_retries = 0
	_mpv.call("load_file", ProjectSettings.globalize_path(_current), "", "")  # mpv 只认操作系统路径
	_mpv.call("pause")


func _process(delta: float) -> void:
	if _state == 0:
		return
	_timer += delta
	if _timer > PER_FILE_TIMEOUT:
		# 超时兜底：已 seek 过且有帧就用当前帧，否则放弃该文件
		_finish(_state == 2 and _latest_tex != null, _latest_tex)


func _do_seek() -> void:
	_mpv.call("set_time_pos", _target)
	_mpv.call("pause")  # set_time_pos 会强制解除暂停


func _on_time_changed(time_pos: float) -> void:
	if _state == 1:
		# 当前文件已真实起播，计算目标位置（超出时长的取末尾附近）并 seek
		_state = 2
		_target = capture_pos
		if _mpv.has_method("get_duration"):
			var dur := float(_mpv.call("get_duration"))
			if dur > 0.0:
				_target = minf(capture_pos, maxf(dur - 0.2, 0.0))
		_do_seek()
	elif _state == 2:
		if absf(time_pos - _target) <= 0.5:
			# 时间到位，此刻的最新纹理才是当前文件目标位置的帧
			_finish(_latest_tex != null, _latest_tex)
		elif _seek_retries < 3:
			# 首帧时 demuxer 可能未就绪导致 seek 丢失，重试
			_seek_retries += 1
			_do_seek()


func _on_texture_updated(tex: Texture2D) -> void:
	if _state == 2:
		_latest_tex = tex


func _finish(ok: bool, tex: Texture2D = null) -> void:
	var path := _current
	_current = ""
	_state = 0
	if _mpv != null:
		_mpv.call("stop")
	if ok and tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			# 等比缩放到 320x180 以内，保持原视频比例（竖屏视频不压扁）
			var scale := minf(320.0 / img.get_width(), 180.0 / img.get_height())
			if scale < 1.0:
				img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
			thumbnail_ready.emit(path, img)
			_kick()
			return
	thumbnail_failed.emit(path)
	_kick()
