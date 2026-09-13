class_name WebThumbnailer
extends Node
## HTML 封面后台抓取器：复用全局 CEF，但使用独立的离屏浏览器和 1280×720
## 纹理，不占用预览/输出播放器。页面加载后稍等动态内容稳定，再截取当前帧。

signal thumbnail_ready(path: String, image: Image)
signal thumbnail_failed(path: String)

const VIEWPORT_SIZE := Vector2i(1280, 720)
const SETTLE_SECONDS := 0.8
const TIMEOUT_SECONDS := 10.0

var _cef: Node
var _target: TextureRect
var _browser: Node
var _queue: Array[String] = []
var _current := ""
var _elapsed := 0.0
var _loaded_elapsed := -1.0


func _ready() -> void:
	_target = TextureRect.new()
	_target.name = "WebThumbnailTarget"
	_target.position = Vector2(-10000, -10000)
	_target.size = VIEWPORT_SIZE
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_target)
	set_process(false)


func setup(cef: Node) -> void:
	_cef = cef
	_kick()


func enqueue(paths: Array) -> void:
	for value in paths:
		var path := str(value)
		if not path.is_empty() and path != _current and not _queue.has(path):
			_queue.append(path)
	_kick()


func prepare_shutdown() -> void:
	_queue.clear()
	_close_browser()
	set_process(false)


func _kick() -> void:
	if _browser != null or _queue.is_empty() or _cef == null or not is_instance_valid(_cef):
		return
	_current = _queue.pop_front()
	_elapsed = 0.0
	_loaded_elapsed = -1.0
	_browser = _cef.create_browser(PlatformPaths.browser_url(_current), _target, {"frame_rate": 15})
	if _browser == null:
		_finish(false)
		return
	_browser.set_muted(true)
	_browser.resize(VIEWPORT_SIZE)
	_browser.connect("on_page_loaded", _on_page_loaded)
	set_process(true)


func _process(delta: float) -> void:
	if _browser == null:
		return
	_elapsed += delta
	if _loaded_elapsed >= 0.0 and _elapsed - _loaded_elapsed >= SETTLE_SECONDS:
		var tex: Texture2D = _browser.get_texture()
		if tex != null:
			var image := tex.get_image()
			if image != null and not image.is_empty():
				_finish(true, image)
				return
	if _elapsed >= TIMEOUT_SECONDS:
		_finish(false)


func _on_page_loaded(_http_code: int, browser: Node) -> void:
	if browser == _browser:
		_loaded_elapsed = _elapsed


func _close_browser() -> void:
	if _browser != null and is_instance_valid(_browser):
		_browser.close()
		_browser.queue_free()
	_browser = null


func _finish(ok: bool, image: Image = null) -> void:
	var path := _current
	_current = ""
	_close_browser()
	if ok and image != null:
		thumbnail_ready.emit(path, image)
	else:
		thumbnail_failed.emit(path)
	if _queue.is_empty():
		set_process(false)
	else:
		call_deferred("_kick")
