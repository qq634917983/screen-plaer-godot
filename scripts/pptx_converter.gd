class_name PptxConverter
extends Node
## PPTX → 自包含 HTML 转换管理器（Phase 9）。
## 用全局 GdCEF 开一个隐藏浏览器加载 res://pptx_renderer/player.html，
## 页面就绪后把 pptx 文件内容以 base64 注入（CEF file:// 页面不能 XHR 读
## 其他本地文件），页面内 worker 转换完成后标题变为 "pptx:{页数}"，
## 轮询到标题即 request_html_content() 把自包含 HTML 写盘为缓存。
## 一次只转一个，多余请求排队；已有缓存的路径直接回调成功。
## 缓存分两级：全局 user://pptx/<md5>.html（写穿后备）与项目 X_cache/pptx/
## （保存项目时由 ProjectStore 同步，打开项目时优先查找，见 project_store.gd）。

signal convert_done(ok: bool, out_path: String, page_count: int)

const PLAYER_PAGE := "res://pptx_renderer/player.html"
const PLAYER_PAGE_USER_DIR := "user://pptx_renderer"
const VIEWPORT_SIZE := Vector2(1280, 720)
const POLL_INTERVAL := 0.5  # 标题轮询间隔（秒）
const CONVERT_TIMEOUT := 30.0  # 转换整体超时（秒）


## 播放器壳的 file:// URL。导出包里 res:// 在 pck 内，CEF 读不到，
## 首次运行把 pptx_renderer 解包到 user:// 再用（编辑器/导出行为一致）
static func player_page_url() -> String:
	if not FileAccess.file_exists(PLAYER_PAGE_USER_DIR + "/player.html"):
		_copy_dir("res://pptx_renderer", PLAYER_PAGE_USER_DIR)
	return PlatformPaths.browser_url(PLAYER_PAGE_USER_DIR + "/player.html")


static func _copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst))
	var d := DirAccess.open(src)
	if d == null:
		push_error("pptx_renderer 源目录不存在：" + src)
		return
	d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		if name != "." and name != ".." and not name.ends_with(".import"):
			if d.current_is_dir():
				_copy_dir(src + "/" + name, dst + "/" + name)
			else:
				DirAccess.copy_absolute(src + "/" + name, dst + "/" + name)
		name = d.get_next()
	d.list_dir_end()

var _cef: Node  # 全局 GDCEF 节点（main.gd 注入），无 gdcef 时转换不可用
var _queue: Array[String] = []
var _out_paths := {}  # pptx 路径 -> 输出 html 路径（排队时记录）
var _current := ""
var _out_path := ""
var _browser: Node  # GdBrowserView
var _view: TextureRect  # 隐藏渲染目标（不进场景显示树）
var _state := 0  # 0 空闲 / 1 等播放器页加载 / 2 等转换完成（轮询标题）/ 3 等 HTML 序列化
var _page_count := 0
var _poll := 0.0
var _elapsed := 0.0


func setup(cef: Node) -> void:
	_cef = cef


func prepare_shutdown() -> void:
	set_process(false)
	_queue.clear()
	_out_paths.clear()
	if _browser != null and is_instance_valid(_browser):
		_browser.close()
		_browser.queue_free()
	_browser = null
	if _view != null and is_instance_valid(_view):
		_view.free()
	_view = null
	_state = 0


static func global_cache_dir() -> String:
	return "user://pptx"


static func cache_file_name(pptx_path: String) -> String:
	return pptx_path.md5_text() + ".html"


## 全局后备缓存路径（项目缓存之外的写穿位置）
static func global_cache_path(pptx_path: String) -> String:
	return global_cache_dir() + "/" + cache_file_name(pptx_path)


## 请求转换。out_html_path 为空时写到全局缓存目录。
## 目标文件已存在时不重复转换，延迟一帧直接回调成功（page_count=0 表示未知，
## 调用方应优先用 MediaObject.page_count / 页面标题）。
func convert(pptx_path: String, out_html_path := "") -> void:
	if out_html_path.is_empty():
		out_html_path = global_cache_path(pptx_path)
	if FileAccess.file_exists(out_html_path):
		convert_done.emit.call_deferred(true, out_html_path, 0)
		return
	if _cef == null:
		convert_done.emit.call_deferred(false, out_html_path, 0)
		return
	if _current == pptx_path or _queue.has(pptx_path):
		return  # 已在转换/队列中
	_queue.append(pptx_path)
	_out_paths[pptx_path] = out_html_path
	_kick()


func is_converting(pptx_path: String) -> bool:
	return _current == pptx_path or _queue.has(pptx_path)


func _kick() -> void:
	if _state != 0 or _queue.is_empty():
		return
	_current = _queue.pop_front()
	AppLog.info("pptx", "conversion_started", AppLog.media_ref(_current))
	_out_path = _out_paths.get(_current, global_cache_path(_current))
	_out_paths.erase(_current)
	_page_count = 0
	_elapsed = 0.0
	_poll = 0.0
	_view = TextureRect.new()  # 不进显示树，仅作 CEF 离屏渲染目标
	var url := player_page_url()
	_browser = _cef.create_browser(url, _view, {"frame_rate": 30})
	if _browser == null:
		push_warning("PPT 转换浏览器创建失败：" + _cef.get_error())
		_finish(false)
		return
	_browser.resize(VIEWPORT_SIZE)
	_browser.set_muted(true)
	_browser.connect("on_page_loaded", _on_page_loaded)
	_browser.connect("on_page_failed_loading", _on_page_failed_loading)
	_browser.connect("on_html_content_requested", _on_html_content_requested)
	_state = 1


func _process(delta: float) -> void:
	if _state == 0:
		return
	_elapsed += delta
	if _elapsed >= CONVERT_TIMEOUT:
		push_warning("PPT 转换超时：" + _current)
		_finish(false)
		return
	if _state != 2:
		return
	_poll += delta
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0
	# 页面转换完成时会把标题置为 pptx:{页数}；失败置为 pptx:error
	var title: String = _browser.get_title()
	if title.begins_with("pptx:{"):
		_page_count = int(title.trim_prefix("pptx:{").trim_suffix("}"))
		_browser.request_html_content()
		_state = 3
	elif title == "pptx:error":
		push_warning("PPT 转换失败（页面报错）：" + _current)
		_finish(false)


func _on_page_loaded(http_code: int, browser: Node) -> void:
	# gdcef 的 on_page_loaded 参数为 (http_code, browser)，不带 URL
	if _state != 1 or browser != _browser:
		return
	if http_code >= 400:
		push_warning("PPT 播放器页加载失败（HTTP %d）" % http_code)
		_finish(false)
		return
	var f := FileAccess.open(_current, FileAccess.READ)
	if f == null:
		push_warning("PPT 文件无法读取：" + _current)
		_finish(false)
		return
	var b64 := Marshalls.raw_to_base64(f.get_buffer(f.get_length()))
	# base64 字母表无引号/反斜杠，可直接嵌入 JS 字符串字面量
	_browser.execute_javascript("window.loadPptxBase64(\"" + b64 + "\")")
	_state = 2


func _on_page_failed_loading(err_code: int, err_msg: String, browser: Node) -> void:
	if _state != 1 or browser != _browser:
		return
	push_warning("PPT 播放器页加载失败（%d）：%s" % [err_code, err_msg])
	_finish(false)


func _on_html_content_requested(html: String, _browser_node: Node) -> void:
	if _state != 3:
		return
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_path.get_base_dir()))
	if err != OK:
		push_error("PPT 缓存目录创建失败（%s）：%s" % [_out_path.get_base_dir(), error_string(err)])
		_finish(false)
		return
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		push_error("PPT 缓存写盘失败：" + _out_path)
		_finish(false)
		return
	f.store_string(html)
	f.close()
	_finish(true)


func _finish(ok: bool) -> void:
	AppLog.info("pptx", "conversion_finished", {"ok": ok, "resource": AppLog.media_ref(_current), "pages": _page_count, "seconds": _elapsed})
	var out := _out_path
	var pages := _page_count if ok else 0
	if _browser != null:
		if is_instance_valid(_browser):
			_browser.close()
			_browser.queue_free()
		_browser = null
	if _view != null:
		_view.free()  # 未入树，需手动释放
		_view = null
	_current = ""
	_out_path = ""
	_state = 0
	convert_done.emit(ok, out, pages)
	_kick()
