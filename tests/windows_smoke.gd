extends SceneTree
## Run after editor import: godot --path . --script tests/windows_smoke.gd -- <video>
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func():
		push_error("Smoke test timed out")
		quit(1))
	call_deferred("run")

func run() -> void:
	check(PlatformPaths.browser_url("/tmp/a b#中文.html") == "file:///tmp/a%20b%23%E4%B8%AD%E6%96%87.html", "POSIX URL encoding")
	check(PlatformPaths.browser_url("C:/a b/test.html") == "file:///C:/a%20b/test.html", "Windows drive URL")
	check(PlatformPaths.browser_url("//server/share/a b.html") == "file://server/share/a%20b.html", "UNC URL")
	check(PlatformPaths.browser_url("https://example.com/a?q=1#x") == "https://example.com/a?q=1#x", "Network URL preserved")
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a test video after --")
		quit(1)
		return
	var scene = load("res://main.tscn").instantiate()
	scene.cef_enabled = false
	scene.cef_cache_path = "user://smoke/cef-%d" % OS.get_process_id()
	root.add_child(scene)
	while scene._startup_initializing:
		await process_frame
	var preview: PlayerSlot = scene._preview
	var output: PlayerSlot = scene._output
	check(preview.is_available() and output.is_available(), "Native MPV initializes")
	if not preview.is_available():
		quit(1)
		return
	# All test playback stays muted, including output.
	output.set_muted(true)
	preview.load_media(args[0], true)
	var playback_deadline := Time.get_ticks_msec() + 5000
	while (preview.elapsed <= 0.2 or preview.duration <= 2.0) and Time.get_ticks_msec() < playback_deadline:
		await process_frame
	check(preview.elapsed > 0.2 and preview.duration > 2, "Video time and duration advance")
	check(preview.mpv.get_texture() != null, "Video produces texture")
	check(preview.muted, "Preview remains muted")
	preview.toggle_play()
	preview.seek(3.0)
	await create_timer(0.6).timeout
	check(not preview.playing and absf(preview.elapsed - 3.0) < 0.25, "Paused seek lands at 3s")
	var saved := preview.elapsed
	await create_timer(0.4).timeout
	check(absf(preview.elapsed - saved) < 0.1, "Paused seek remains paused")
	output.load_media(args[0], false, preview.elapsed)
	scene._show_cast_window()
	await create_timer(0.8).timeout
	check(output.mpv.get_texture() != null and output.mpv.get_texture() == scene._cast_video_view.texture, "Output and cast share identical texture")
	check(absf(output.elapsed - preview.elapsed) < 0.3 and not output.playing, "Output receives paused position")
	preview.stop()
	check(output.media_path == args[0], "Preview stop does not affect output")
	output.set_looping(true)
	output.toggle_play()
	output.seek(output.duration - 0.4)
	await create_timer(0.9).timeout
	var loop_deadline := Time.get_ticks_msec() + 4000
	while output.elapsed >= 2.0 and Time.get_ticks_msec() < loop_deadline:
		await process_frame
	check(output.elapsed < 2.0, "Loop restarts at end of video (position=%s)" % output.elapsed)
	output.set_looping(false)
	var thumbnail := {}
	scene._thumbnailer.thumbnail_ready.connect(func(path, image): thumbnail[path] = image)
	scene._thumbnailer.enqueue([args[0]])
	await create_timer(2.0).timeout
	check(thumbnail.has(args[0]), "Background thumbnail capture succeeds")
	var media_panel: Control = scene.get_node("%QuadSplit/MediaDock")
	var output_controls: Control = scene._output_play_button.get_parent().get_parent()
	check(output_controls.get_global_rect().end.y <= media_panel.get_global_rect().position.y, "Player controls stay above media panel on Windows")
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color.CORNFLOWER_BLUE)
	img.save_png("user://screenplayer-smoke.png")
	output.load_static(ProjectSettings.globalize_path("user://screenplayer-smoke.png"))
	check(scene._cast_video_view.texture == output._video_view.texture, "Image cast shares texture")
	output.stop()
	check(not scene._cast_video_view.visible, "Stopping output hides cast picture")
	scene.queue_free()
	await process_frame
	print("SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
