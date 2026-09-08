extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Web smoke test timed out")
		quit(1))
	call_deferred("run")

func wait_for(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene._cef != null, "CEF initializes on macOS")
	if scene._cef == null:
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var html_path := "/tmp/screenplayer 网页 #1.html"
	var file := FileAccess.open(html_path, FileAccess.WRITE)
	file.store_string('<!doctype html><html><head><title>ready</title></head><body style="margin:0;background:#18354a;color:white"><button style="position:absolute;left:500px;top:300px;width:280px;height:120px" onclick="document.title=\'clicked\';document.body.style.background=\'#146633\'">ScreenPlayer Mac CEF</button></body></html>')
	file.close()
	var preview: PlayerSlot = scene._preview
	var output: PlayerSlot = scene._output
	preview.load_web(html_path)
	check(await wait_for(func(): return preview._browser != null and preview._browser.get_title() == "ready"), "Local HTML with Unicode/space/# loads")
	check(await wait_for(func(): return preview._video_view.texture != null), "CEF produces preview texture")
	await create_timer(0.8).timeout
	preview.get_frame_image().save_png("/tmp/screenplayer-web-preview.png")
	preview.web_points = [Vector2(0.5, 0.5)]
	preview.step_web(1)
	check(await wait_for(func(): return preview._browser.get_title() == "clicked"), "Web touchpoint executes native browser click")
	output.load_web(html_path)
	scene._show_cast_window()
	check(await wait_for(func(): return output._video_view.texture != null and scene._cast_video_view.texture == output._video_view.texture), "Web output/cast share texture")
	var converter: PptxConverter = scene._pptx_converter
	var conversion := {}
	converter.convert_done.connect(func(ok, path, pages): conversion["result"] = [ok, path, pages], CONNECT_ONE_SHOT)
	converter.convert("res://doc/test.pptx", "/tmp/screenplayer-ppt-%d.html" % OS.get_process_id())
	check(await wait_for(func(): return conversion.has("result"), 35.0), "PPT conversion completes within timeout")
	var result: Array = conversion.get("result", [false, "", 0])
	check(result[0] and result[2] > 1, "PPTX conversion succeeds")
	if result[0]:
		preview.load_slides(result[1], result[2])
		check(await wait_for(func(): return preview._browser.get_title().begins_with("pptx:{")), "Converted PPT cache loads")
		preview.goto_page(2)
		output.load_slides(result[1], result[2], preview.current_page)
		check(await wait_for(func(): return output._browser.get_title().begins_with("pptx:{")), "PPT output loads")
		await create_timer(0.5).timeout
		check(output.current_page == 2 and output._video_view.texture == scene._cast_video_view.texture, "PPT page and cast texture match")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/screenplayer-macos-ppt.png")
	preview.stop()
	output.stop()
	await create_timer(0.5).timeout
	scene.queue_free()
	await process_frame
	print("WEB SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
