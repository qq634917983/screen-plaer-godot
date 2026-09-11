extends SceneTree
## 验证播放器三段式结构、内容同宽和四分区最大/最小边界。

var failures := 0


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func settle() -> void:
	for _i in 8:
		await process_frame


func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Player layout smoke test timed out")
		quit(1)
	)
	call_deferred("run")


func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	# 只测真实场景布局，不启动媒体解码和用户项目。
	scene.set_script(null)
	root.add_child(scene)
	root.size = Vector2i(1440, 900)
	await settle()

	for prefix in ["Preview", "Output"]:
		var player: Control = scene.find_child(prefix + "Player", true, false)
		var header: Control = scene.find_child(prefix + "Header", true, false)
		var screen: Control = scene.find_child(prefix + "Screen", true, false)
		var controls: Control = scene.find_child(prefix + "Controls", true, false)
		check(player != null and header != null and screen != null and controls != null,
			prefix + " player has header/content/control sections")
		if player == null or header == null or screen == null or controls == null:
			continue
		check(header.position.y < screen.position.y and screen.position.y < controls.position.y,
			prefix + " sections are ordered header/content/controls")
		check(absf(screen.size.x - player.size.x) <= 3.0,
			prefix + " video content matches parent width")
		check(absf(header.size.x - player.size.x) <= 3.0 and absf(controls.size.x - player.size.x) <= 3.0,
			prefix + " header and controls match parent width")

	var split: QuadSplitContainer = scene.get_node("%QuadSplit")
	var players: Control = scene.find_child("PlayersSection", true, false)
	split.max_left = 700
	split.split_x_ratio = 0.9
	await settle()
	check(players.size.x <= 701.0, "Left column maximum width is enforced")
	split.max_left = 0
	split.max_right = 300
	split.split_x_ratio = 0.05
	await settle()
	var utility: Control = scene.find_child("UtilityPanel", true, false)
	check(utility.size.x <= 301.0, "Right column maximum width is enforced")
	split.max_right = 0
	split.max_top = 420
	split.split_y_ratio = 0.9
	await settle()
	check(players.size.y <= 421.0, "Top row maximum height is enforced")
	split.max_top = 0
	split.max_bottom = 320
	split.split_y_ratio = 0.05
	await settle()
	var media: Control = scene.find_child("MediaPanel", true, false)
	check(media.size.y <= 321.0, "Bottom row maximum height is enforced")
	split.max_bottom = 0
	split.split_x_ratio = 0.72
	split.split_y_ratio = 0.5
	await settle()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
	var image := root.get_texture().get_image()
	var screenshot := ProjectSettings.globalize_path("res://.build/player_layout.png")
	check(image.save_png(screenshot) == OK, "Player layout screenshot saved")
	print("SCREENSHOT=", screenshot)
	var settings: SettingsWindow = scene.get_node("%SettingsWindow")
	settings.open()
	var tabs := settings.find_child("SettingsTabs", true, false) as TabContainer
	if tabs != null:
		tabs.current_tab = 2
	await settle()
	var settings_image := settings.get_texture().get_image()
	var settings_screenshot := ProjectSettings.globalize_path("res://.build/layout_settings.png")
	check(settings_image.save_png(settings_screenshot) == OK, "Layout settings screenshot saved")
	print("SETTINGS_SCREENSHOT=", settings_screenshot)
	settings.hide()
	scene.queue_free()
	await process_frame
	print("PLAYER_LAYOUT failures=", failures)
	quit(0 if failures == 0 else 1)
