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
	scene.cef_cache_path = "user://smoke/lazy-cef-%d" % OS.get_process_id()
	root.add_child(scene)
	while scene._startup_initializing:
		await process_frame

	check(scene._cef == null, "Normal startup leaves CEF unloaded")
	check(scene._preview.web_cef == null and scene._output.web_cef == null,
		"Player slots do not receive a browser before first use")
	check(scene._pptx_converter._cef == null,
		"PPT converter is created cheaply without starting CEF")

	var started := Time.get_ticks_msec()
	var web_media := MediaObject.create("res://doc/test.html")
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

	scene.queue_free()
	await process_frame
	print("LAZY_CEF_STARTUP failures=", failures)
	quit(0 if failures == 0 else 1)
