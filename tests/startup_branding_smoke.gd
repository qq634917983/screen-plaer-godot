extends SceneTree
## 验证应用图标、Godot 启动画面和主场景加载进度层。

var failures := 0


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func settle() -> void:
	for _i in 6:
		await process_frame


func _initialize() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		push_error("Startup branding smoke test timed out")
		quit(1)
	)
	call_deferred("run")


func run() -> void:
	check(ProjectSettings.get_setting("application/config/icon") == "res://assets/app_icon.png",
		"Project uses the new ScreenPlayer icon")
	check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/app_icon_256.png",
		"Godot boot splash uses the ScreenPlayer icon")
	check(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", 0)) >= 400,
		"Godot boot splash remains visible long enough to register")
	check(FileAccess.file_exists("res://assets/app_icon.ico"),
		"Windows multi-size application icon exists")

	var icon_image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/app_icon.png"))
	check(icon_image != null and icon_image.get_size() == Vector2i(1024, 1024),
		"Application icon has the expected high-resolution size")
	if icon_image != null:
		check(icon_image.get_pixel(0, 0).a < 0.1 and icon_image.get_pixel(512, 512).a > 0.9,
			"Application icon has a transparent exterior and opaque artwork")

	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_script(null)
	root.add_child(scene)
	root.size = Vector2i(1152, 648)
	await settle()
	var overlay := scene.find_child("StartupOverlay", true, false) as ColorRect
	var icon := scene.find_child("StartupIcon", true, false) as TextureRect
	var progress := scene.find_child("StartupProgress", true, false) as ProgressBar
	var stage := scene.find_child("StartupStage", true, false) as Label
	check(overlay != null and icon != null and progress != null and stage != null,
		"Startup overlay contains icon, progress bar and stage label")
	if overlay != null and icon != null and progress != null and stage != null:
		check(not overlay.visible, "Startup overlay stays hidden in the scene until initialization starts")
		check(icon.texture != null and icon.custom_minimum_size.x >= 180.0,
			"Startup overlay displays a prominent application icon")
		check(not progress.show_percentage and progress.max_value == 100.0,
			"Startup progress bar uses the complete 0-100 range without text overlap")
		overlay.visible = true
		await settle()
		var texture := root.get_texture()
		if DisplayServer.get_name() != "headless" and texture != null:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
			var screenshot := ProjectSettings.globalize_path("res://.build/startup_screen.png")
			check(texture.get_image().save_png(screenshot) == OK, "Startup screen screenshot saved")
			print("SCREENSHOT=", screenshot)

	scene.queue_free()
	await process_frame
	print("STARTUP_BRANDING failures=", failures)
	quit(0 if failures == 0 else 1)
