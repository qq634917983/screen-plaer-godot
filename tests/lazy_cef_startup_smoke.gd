extends SceneTree
## 验证主界面启动不再初始化 CEF，并且首次网页请求能完成一次延迟初始化。

var failures := 0


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Lazy CEF startup smoke test timed out")
		quit(1)
	)
	call_deferred("run")


func wait_for(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	var stamp := str(OS.get_process_id())
	scene.cef_cache_path = "user://smoke/lazy-cef-" + stamp
	root.add_child(scene)
	while scene._startup_initializing:
		await process_frame

	check(scene._cef == null, "Normal startup leaves CEF unloaded")
	check(scene._preview.web_cef == null and scene._output.web_cef == null,
		"Player slots do not receive a browser before first use")
	check(scene._pptx_converter._cef == null,
		"PPT converter is created cheaply without starting CEF")

	var html_path := "user://smoke/lazy-web-%s.html" % stamp
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://smoke"))
	var html_file := FileAccess.open(html_path, FileAccess.WRITE)
	html_file.store_string("<!doctype html><html><head><title>cover-ready</title></head><body style='margin:0;background:#17466b;color:white'><h1>ScreenPlayer Web Cover</h1></body></html>")
	html_file.close()
	scene._project_path = "user://smoke/lazy-cover-%s.splproj" % stamp
	scene._project_cache_dir = ProjectStore.cache_dir_for(scene._project_path)
	var image_path := "user://smoke/lazy-image-%s.png" % stamp
	var image := Image.create(64, 36, false, Image.FORMAT_RGB8)
	image.fill(Color.CORNFLOWER_BLUE)
	image.save_png(image_path)
	var audio_path := "user://smoke/lazy-audio-%s.mp3" % stamp
	var audio_file := FileAccess.open(audio_path, FileAccess.WRITE)
	audio_file.store_buffer(PackedByteArray([0]))
	audio_file.close()
	scene._add_media_item(MediaObject.create(image_path), false)
	scene._add_media_item(MediaObject.create(audio_path), false)
	check(FileAccess.file_exists(scene._project_cache_dir + "/thumbs/" + image_path.md5_text() + ".png"),
		"Image cover is stored in the project thumbnail cache")
	check(FileAccess.file_exists(scene._project_cache_dir + "/thumbs/" + audio_path.md5_text() + ".png"),
		"Audio fallback cover is stored in the project thumbnail cache")
	var started := Time.get_ticks_msec()
	var web_media := MediaObject.create(html_path)
	scene._add_media_item(web_media, false)
	scene._load_preview(web_media)
	var initialized := await wait_for(func() -> bool: return scene._cef != null)
	print("LAZY_CEF_TEST_INIT_MS=%d" % (Time.get_ticks_msec() - started))
	check(initialized and scene._cef != null, "First web use initializes CEF")
	check(scene._preview.web_cef == scene._cef and scene._output.web_cef == scene._cef,
		"Preview and output share the delayed CEF instance")
	check(scene._pptx_converter._cef == scene._cef,
		"Delayed CEF instance is injected into the PPT converter")
	check(await wait_for(func() -> bool:
		return scene._preview._browser != null and scene._preview._video_view.texture != null
	), "Original web request resumes and produces a preview frame")
	var project_cover: String = str(scene._project_cache_dir) + "/thumbs/" + html_path.md5_text() + ".png"
	check(await wait_for(func() -> bool: return FileAccess.file_exists(project_cover)),
		"HTML background screenshot is stored in the project thumbnail cache")
	var web_cover := Image.load_from_file(project_cover)
	check(web_cover != null and web_cover.get_size() == Vector2i(320, 180)
		and web_cover.get_pixel(160, 90).b > 0.25,
		"HTML cover contains the rendered 16:9 webpage instead of a placeholder")

	scene.queue_free()
	await process_frame
	print("LAZY_CEF_STARTUP failures=", failures)
	quit(0 if failures == 0 else 1)
