class_name PlayerSlot
extends Node
## 封装一个播放端：帧源（MPV 解码 / 静态纹理）+ TextureRect 显示 + 播放状态。
## 预览 / 输出两个播放端共用；投屏窗口不持有实例，通过 frame_updated 共享输出端纹理。
##
## 帧源模型（Phase 7 起）：视频/音频走 MPV 解码（MPVPlayer），图片等无需解码的
## 媒体走静态纹理通路（load_static）——两者最终都把纹理发进 frame_updated，
## 因此投屏窗口对帧源类型无感知。后续网页/PPT 帧源（WebSource/SlideSource）
## 遵循同一接口接入。
##
## 完整版内核 API 注意（自编译 godot_mpv）：
## - load_file 需 3 参：load_file(path, headers, yt_dlp_path)
## - set_volume / set_repeat_file / set_playback_speed 参数均为 String
## - set_time_pos(double) 会强制解除暂停，暂停状态下 seek 后需重新 pause
## - time_changed(float) 信号由内核驱动（time-pos 属性观察），elapsed 为真实进度

signal state_changed  # load / play / pause / stop / seek 后发出
signal frame_updated(texture)  # 帧源产出新画面（投屏窗口借此共享输出端纹理）
signal touch_edit_clicked(pos_norm: Vector2, button_index: int)  # 触点编辑模式下画面被点击（归一化坐标）

## 帧源类型：NONE = 空；MPV = 视频/音频经 mpv 解码；STATIC = 静态纹理（图片等）；
## WEB = 网页经 CEF 离屏渲染（gdcef，浏览器视口固定参考分辨率，
## 纹理由 TextureRect 随窗口缩放，行为与视频一致）；
## SLIDE = PPT 转换出的自包含 HTML 经 CEF 播放（Phase 9），
## 与 WEB 共用浏览器通路，seek 语义为跳页
enum SourceKind { NONE, MPV, STATIC, WEB, SLIDE }

## 网页帧源的固定渲染分辨率：不随窗口改变，窗口缩放由 TextureRect
## （KEEP_ASPECT_CENTERED）完成，保证小窗口下页面完整可见
const WEB_VIEWPORT_SIZE := Vector2(1280, 720)

var mpv: Node  # MPVPlayer（GDExtension 类），未安装扩展时为 null
var web_cef: Node  # GDCEF 管理节点（全局唯一，由 main.gd 注入），无 gdcef 时为 null
var media_path := ""
var source_kind := SourceKind.NONE
var playing := false
var looping := false
var muted := false
var volume := 100
var rate := 1.0
var elapsed := 0.0  # 由 time_changed 信号驱动的真实播放进度
var duration := 0.0  # 媒体总时长（秒），首个 time_changed 时从内核读取，0 = 未知
var page_count := 0  # SLIDE 帧源页数（0 = 未知，加载后经页面标题轮询补全）
var current_page := 0  # SLIDE 帧源当前页（0 基）

var _video_view: TextureRect
var _placeholder: Control
var _browser: Node  # GdBrowserView（WEB 帧源）
var _awaiting_first_frame := false
var _pending_seek := -1.0  # 首帧到达后要跳转的位置（load_file 前 seek 会被忽略）
var _seek_retries := 0  # 首帧时 demuxer 可能未就绪导致 seek 丢失，用 time_changed 校验重试
var _view_scale := 1.0  # 画面缩放（来自媒体对象属性）
var _view_offset := Vector2.ZERO  # 画面平移（来自媒体对象属性）

var touch_edit_mode := false  # 触点编辑模式：点击画面不转发浏览器，改为上报归一化坐标
var web_points: Array[Vector2] = []  # 当前 WEB 媒体的触点序列（归一化坐标，与 MediaObject.touch_points 共享引用）
var web_step := -1  # 触进步数（-1 = 尚未触达任何点）


func setup(video_view: TextureRect, placeholder: Control = null) -> void:
	_video_view = video_view
	_placeholder = placeholder
	_video_view.resized.connect(_apply_view_transform)
	_video_view.gui_input.connect(_on_view_gui_input)
	if not ClassDB.class_exists(&"MPVPlayer"):
		push_warning("MPVPlayer GDExtension 未加载，视频播放不可用")
		return
	mpv = ClassDB.instantiate(&"MPVPlayer") as Node
	add_child(mpv)
	if not mpv.call("initialize"):
		push_error("MPVPlayer 初始化失败")
		mpv.queue_free()
		mpv = null
		return
	mpv.connect("texture_updated", _on_texture_updated)
	if mpv.has_signal("time_changed"):
		mpv.connect("time_changed", _on_time_changed)


func is_available() -> bool:
	return mpv != null


## autoplay=false 时装载后立即暂停（load_file 本身会自动起播）。
## seek_pos >= 0 时首帧到达后跳转到该进度。
func load_media(path: String, autoplay := true, seek_pos := -1.0) -> void:
	if mpv == null:
		push_warning("MPVPlayer 不可用，无法播放：" + path)
		return
	# 本地文件先验存在性：库里可能残留已被移动/删除的条目，
	# 直接丢给 mpv 只会报 "error code: -13"，排查困难
	if not (path.begins_with("http://") or path.begins_with("https://")) and not FileAccess.file_exists(path):
		push_warning("文件不存在，无法播放：" + path)
		media_path = ""
		source_kind = SourceKind.NONE
		playing = false
		if _video_view != null:
			_video_view.visible = false
		if _placeholder != null:
			_placeholder.visible = true
			if "text" in _placeholder:
				_placeholder.text = "文件不存在：\n" + path
		state_changed.emit()
		return
	media_path = path
	source_kind = SourceKind.MPV
	elapsed = 0.0
	duration = 0.0
	_awaiting_first_frame = true
	_pending_seek = seek_pos
	_seek_retries = 0
	_close_browser()  # 切换帧源：关闭网页浏览器
	# mpv 只认操作系统路径：user://res:// 虚拟路径需先 globalize
	_apply_volume()  # 装载前应用静音，避免预览首段音频漏出
	mpv.call("load_file", ProjectSettings.globalize_path(path), "", "")
	if autoplay:
		mpv.call("play")
	else:
		mpv.call("pause")
	playing = autoplay
	if _video_view != null:
		_video_view.visible = true
	if _placeholder != null:
		_placeholder.visible = false
	if looping and mpv.has_method("set_repeat_file"):
		mpv.call("set_repeat_file", "inf")
	if muted:
		_apply_volume()
	if rate != 1.0:
		mpv.call("set_playback_speed", str(rate))
	state_changed.emit()


## 静态纹理帧源通路：图片等无需解码的媒体直接读图显示（不经 mpv）。
## 与 mpv 通路共用显示与 frame_updated 信号，投屏窗口对帧源类型无感知。
func load_static(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("图片加载失败：" + path)
		return
	if mpv != null and source_kind == SourceKind.MPV:
		mpv.call("stop")  # 停掉上一媒体，避免残留帧/声音
	_close_browser()  # 切换帧源：关闭网页浏览器
	media_path = path
	source_kind = SourceKind.STATIC
	playing = true  # 静态媒体一经加载即视为"显示中"
	elapsed = 0.0
	duration = 0.0
	_awaiting_first_frame = false
	_pending_seek = -1.0
	var tex := ImageTexture.create_from_image(img)
	if _video_view != null:
		_video_view.texture = tex
		_video_view.visible = true
	if _placeholder != null:
		_placeholder.visible = false
	frame_updated.emit(tex)
	state_changed.emit()


## 网页帧源通路：CEF（gdcef）离屏渲染真实网页。浏览器视口固定为参考
## 分辨率（WEB_VIEWPORT_SIZE），窗口缩放由 TextureRect 完成——与视频同模型，
## 小窗口下页面等比缩小但完整可见；投屏窗口持有同一纹理引用即自动跟随。
func load_web(path: String) -> void:
	var url := PlatformPaths.browser_url(path)
	if not _start_browser(url, SourceKind.WEB):
		return
	media_path = path
	_after_source_loaded()


## PPT 幻灯片帧源通路（Phase 9）：加载 PptxConverter 预转的自包含 HTML，
## 与 WEB 共用 CEF 浏览器通路（固定视口 / frame_updated 转发 / 静音规则），
## 区别只在导航语义：无播放/暂停，seek = 跳页（gotoSlide）。
## page_count 由 MediaObject 提供（0 = 未知，加载后轮询页面标题补全）；
## start_page 为起始页（0 基，快速切换时对齐预览端页码）；
## source_path 为原始 pptx 路径（媒体身份/高亮匹配用），空则用 html_path。
func load_slides(html_path: String, p_page_count := 0, start_page := 0, source_path := "") -> void:
	var url := PlatformPaths.browser_url(html_path)
	if not _start_browser(url, SourceKind.SLIDE):
		return
	media_path = source_path if not source_path.is_empty() else html_path
	page_count = maxi(p_page_count, 0)
	current_page = clampi(start_page, 0, maxi(page_count - 1, 0))
	_browser.connect("on_page_loaded", _on_slide_page_loaded)
	_after_source_loaded()


## 切换帧源到 CEF 浏览器（WEB / SLIDE 共用）：停旧媒体、建浏览器、接信号。
## 成功返回 true；失败时帧源复位为 NONE。
func _start_browser(url: String, kind: int) -> bool:
	if web_cef == null:
		push_warning("浏览器内核（gdcef）不可用，无法播放：" + url)
		return false
	if mpv != null and source_kind == SourceKind.MPV:
		mpv.call("stop")
	_close_browser()
	source_kind = kind
	playing = true  # 网页/幻灯片一经加载即视为"显示中"（无播放/暂停语义）
	elapsed = 0.0
	duration = 0.0
	page_count = 0
	current_page = 0
	web_step = -1
	web_points = []
	_awaiting_first_frame = false
	_pending_seek = -1.0
	_browser = web_cef.create_browser(url, _video_view, {"frame_rate": 30})
	if _browser == null:
		push_warning("浏览器创建失败：" + web_cef.get_error())
		media_path = ""
		source_kind = SourceKind.NONE
		return false
	if muted:
		_browser.set_muted(true)
	_browser.resize(WEB_VIEWPORT_SIZE)
	_browser.connect("on_browser_paint", _on_browser_paint)
	return true


func _after_source_loaded() -> void:
	if _video_view != null:
		_video_view.visible = true
	if _placeholder != null:
		_placeholder.visible = false
	state_changed.emit()


## 幻灯片页面加载完成：跳到起始页；页数未知时轮询标题补全
## （缓存 HTML 的导航脚本会把标题置为 pptx:{页数}）
## gdcef 的 on_page_loaded 参数为 (http_code, browser)，不带 URL
func _on_slide_page_loaded(_http_code: int, browser: Node) -> void:
	if source_kind != SourceKind.SLIDE or browser != _browser:
		return
	if current_page > 0:
		_browser.execute_javascript("window.gotoSlide(%d)" % current_page)
	if page_count <= 0:
		_slide_title_poll = TITLE_POLL_TIMEOUT


const TITLE_POLL_TIMEOUT := 5.0  # SLIDE 页数标题轮询上限（秒）
var _slide_title_poll := 0.0  # >0 时表示正在为 SLIDE 帧源轮询页面标题


func _process(delta: float) -> void:
	if _slide_title_poll <= 0.0:
		return
	_slide_title_poll -= delta
	if _browser == null or not is_instance_valid(_browser) or source_kind != SourceKind.SLIDE:
		_slide_title_poll = 0.0
		return
	var title: String = _browser.get_title()
	if title.begins_with("pptx:{"):
		page_count = int(title.trim_prefix("pptx:{").trim_suffix("}"))
		current_page = clampi(current_page, 0, maxi(page_count - 1, 0))
		_slide_title_poll = 0.0
		state_changed.emit()
	elif _slide_title_poll <= 0.0:
		_slide_title_poll = 0.0  # 超时放弃，页数保持未知


func _close_browser() -> void:
	if _browser == null:
		return
	if is_instance_valid(_browser):
		_browser.close()
		_browser.queue_free()
	_browser = null


## 退出前主动停解码并关闭浏览器，让全局 CEF shutdown 不必再等待活动页面。
func prepare_shutdown() -> void:
	set_process(false)
	_slide_title_poll = 0.0
	if mpv != null and is_instance_valid(mpv):
		mpv.call("stop")
	_close_browser()


func _on_browser_paint(browser: Node) -> void:
	if browser != _browser or (source_kind != SourceKind.WEB and source_kind != SourceKind.SLIDE):
		return
	# 浏览器纹理原地更新；重复 emit 同一对象，保证 resize 后投屏端拿到最新纹理
	frame_updated.emit(browser.get_texture())


## 网页交互：显示区鼠标事件转发给浏览器。显示区坐标先按 KEEP_ASPECT_CENTERED
## 的纹理摆放矩形换算回固定视口（WEB_VIEWPORT_SIZE）坐标——浏览器的渲染
## 分辨率与窗口解耦，窗口缩放/条目缩放都不影响命中精度
func _web_to_browser_pos(pos: Vector2) -> Vector2i:
	var vs: Vector2 = _video_view.size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return Vector2i(pos)
	var s := minf(vs.x / WEB_VIEWPORT_SIZE.x, vs.y / WEB_VIEWPORT_SIZE.y)
	var drawn := WEB_VIEWPORT_SIZE * s
	var origin := (vs - drawn) / 2.0  # 居中摆放的左上偏移
	var p := (pos - origin) / s
	return Vector2i(int(clampf(p.x, 0.0, WEB_VIEWPORT_SIZE.x - 1.0)),
		int(clampf(p.y, 0.0, WEB_VIEWPORT_SIZE.y - 1.0)))


func _on_view_gui_input(event: InputEvent) -> void:
	if source_kind != SourceKind.WEB or _browser == null or not is_instance_valid(_browser):
		return
	# 触点编辑模式：点击不转发浏览器，左键上报加点 / 右键上报删点
	if touch_edit_mode:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			touch_edit_clicked.emit(Vector2(_web_to_browser_pos(mb.position)) / WEB_VIEWPORT_SIZE, mb.button_index)
			_video_view.accept_event()
		return
	if event is InputEventMouseMotion:
		var mp := _web_to_browser_pos(event.position)
		_browser.set_mouse_moved(mp.x, mp.y)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.pressed: _browser.set_mouse_wheel_vertical(40, false, false, false)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed: _browser.set_mouse_wheel_vertical(-40, false, false, false)
			return
		var bp := _web_to_browser_pos(event.position)
		_browser.set_mouse_moved(bp.x, bp.y)  # 点击前先同步光标位置
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed: _browser.set_mouse_left_down()
				else: _browser.set_mouse_left_up()
			MOUSE_BUTTON_RIGHT:
				if event.pressed: _browser.set_mouse_right_down()
				else: _browser.set_mouse_right_up()
			MOUSE_BUTTON_MIDDLE:
				if event.pressed: _browser.set_mouse_middle_down()
				else: _browser.set_mouse_middle_up()


func toggle_play() -> void:
	if media_path.is_empty() or source_kind != SourceKind.MPV:
		return  # 静态/网页媒体没有播放/暂停语义
	if mpv == null:
		return
	if playing:
		mpv.call("pause")
	else:
		mpv.call("play")
	playing = not playing
	state_changed.emit()


func stop() -> void:
	if media_path.is_empty():
		return
	if mpv != null and source_kind == SourceKind.MPV:
		mpv.call("stop")
	if source_kind == SourceKind.WEB or source_kind == SourceKind.SLIDE:
		_close_browser()
	playing = false
	media_path = ""
	source_kind = SourceKind.NONE
	elapsed = 0.0
	duration = 0.0
	page_count = 0
	current_page = 0
	web_step = -1
	web_points = []
	_slide_title_poll = 0.0
	_awaiting_first_frame = false
	_pending_seek = -1.0
	if _video_view != null:
		_video_view.visible = false
	if _placeholder != null:
		_placeholder.visible = true
	state_changed.emit()


func seek(pos: float) -> void:
	if source_kind == SourceKind.SLIDE:
		goto_page(int(pos))  # 幻灯片帧源：seek 语义 = 跳页
		return
	if mpv == null or media_path.is_empty() or source_kind != SourceKind.MPV:
		return
	if not mpv.has_method("set_time_pos"):
		return
	if _awaiting_first_frame:
		_pending_seek = pos
		return
	mpv.call("set_time_pos", pos)
	elapsed = pos
	if not playing:
		# set_time_pos 会强制解除暂停，恢复暂停状态
		mpv.call("pause")
	state_changed.emit()


## 跳页（仅 SLIDE 帧源）：页面内导航由 player.html 的 gotoSlide 完成，
## current_page 为本端权威页码（推送输出端时随状态一起走）
func goto_page(n: int) -> void:
	if source_kind != SourceKind.SLIDE:
		return
	if page_count > 0:
		n = clampi(n, 0, page_count - 1)
	else:
		n = maxi(n, 0)
	current_page = n
	if _browser != null and is_instance_valid(_browser):
		_browser.execute_javascript("window.gotoSlide(%d)" % n)
	state_changed.emit()


func next_page() -> void:
	goto_page(current_page + 1)


func prev_page() -> void:
	goto_page(current_page - 1)


## 网页触点触进（d=+1 下一个 / -1 上一个）：像 PPT 翻页一样按顺序把
## 触点序列模拟点击进浏览器（先移动光标到触点，再按下/抬起左键）
func step_web(d: int) -> void:
	if source_kind != SourceKind.WEB or web_points.is_empty():
		return
	if _browser == null or not is_instance_valid(_browser):
		return
	web_step = clampi(web_step + d, 0, web_points.size() - 1)
	var bp := Vector2i(web_points[web_step] * WEB_VIEWPORT_SIZE)
	_browser.set_mouse_moved(bp.x, bp.y)
	_browser.set_mouse_left_down()
	_browser.set_mouse_left_up()
	state_changed.emit()


## 抓取当前帧画面（WEB/SLIDE 浏览器纹理），用于 PPT 封面等；不可用时返回 null
func get_frame_image() -> Image:
	if _browser != null and is_instance_valid(_browser):
		var tex: Texture2D = _browser.get_texture()
		if tex != null:
			return tex.get_image()
	return null


func set_looping(enabled: bool) -> void:
	looping = enabled
	if mpv != null and mpv.has_method("set_repeat_file"):
		mpv.call("set_repeat_file", "inf" if looping else "no")


func set_volume(value: int) -> void:
	volume = clampi(value, 0, 200)
	if not muted:
		_apply_volume()


func set_muted(m: bool) -> void:
	muted = m
	_apply_volume()


func set_rate(speed: float) -> void:
	rate = clampf(speed, 0.25, 4.0)
	if mpv != null and mpv.has_method("set_playback_speed"):
		mpv.call("set_playback_speed", str(rate))


## 应用媒体对象的画面变换（缩放比例 + 水平/垂直偏移，以画面中心为基准）
func set_view_transform(s: float, offset: Vector2) -> void:
	_view_scale = maxf(s, 0.01)
	_view_offset = offset
	_apply_view_transform()


func _apply_view_transform() -> void:
	if _video_view == null:
		return
	_video_view.pivot_offset = _video_view.size / 2.0
	_video_view.scale = Vector2.ONE * _view_scale
	_video_view.position = _view_offset
	# 网页帧源不在此 resize：浏览器视口固定（WEB_VIEWPORT_SIZE），
	# 窗口/条目缩放全由 TextureRect 完成，与视频同一模型


func _apply_volume() -> void:
	if mpv != null and mpv.has_method("set_volume"):
		mpv.call("set_volume", "0" if muted else str(volume))
	if _browser != null and is_instance_valid(_browser):
		_browser.set_muted(muted)


func get_state() -> Dictionary:
	# 音量/静音是各端独立配置（设置窗口），不属于推送状态
	return {
		"media_path": media_path,
		"playing": playing,
		"time_pos": elapsed,
		"loop": looping,
		"rate": rate,
		"page": current_page,  # SLIDE 帧源当前页（其他帧源恒为 0）
	}


func _on_texture_updated(texture: Texture2D) -> void:
	if source_kind != SourceKind.MPV:
		return  # 静态帧源显示期间忽略 mpv 残留帧
	if _awaiting_first_frame:
		_awaiting_first_frame = false
		if _pending_seek >= 0.0:
			seek(_pending_seek)  # 此时 seek 可能因 demuxer 未就绪而丢失，time_changed 里会校验重试
	if _video_view != null:
		_video_view.texture = texture
	frame_updated.emit(texture)


func _on_time_changed(time_pos: float) -> void:
	if source_kind != SourceKind.MPV:
		return
	elapsed = time_pos
	if duration <= 0.0 and mpv.has_method("get_duration"):
		duration = float(mpv.call("get_duration"))
	if _pending_seek < 0.0:
		return
	if absf(time_pos - _pending_seek) <= 0.15:
		_pending_seek = -1.0  # seek 已生效
	elif _seek_retries < 5:
		_seek_retries += 1
		var target := _pending_seek
		mpv.call("set_time_pos", target)
		elapsed = target
		if not playing:
			mpv.call("pause")  # set_time_pos 会强制解除暂停
	else:
		_pending_seek = -1.0  # 放弃重试
