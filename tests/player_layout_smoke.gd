extends SceneTree
## 验证播放器固定栏、黑色可变画布、16:9 画面和四分区最大/最小边界。

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


func rect_contains(outer: Rect2, inner: Rect2, tolerance := 1.0) -> bool:
	return inner.position.x >= outer.position.x - tolerance \
		and inner.position.y >= outer.position.y - tolerance \
		and inner.end.x <= outer.end.x + tolerance \
		and inner.end.y <= outer.end.y + tolerance


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

	var fixed_heights := {}
	var content_heights := {}
	var title_bar: Control = scene.find_child("TitleBar", true, false)
	var menu_bar: Control = scene.find_child("MenuBar", true, false)
	check(title_bar != null and menu_bar != null, "Window title and menu bars exist")
	if title_bar != null and menu_bar != null:
		fixed_heights["TitleBar"] = title_bar.size.y
		fixed_heights["MenuBar"] = menu_bar.size.y

	for prefix in ["Preview", "Output"]:
		var player: Control = scene.find_child(prefix + "Player", true, false)
		var header: Control = scene.find_child(prefix + "Header", true, false)
		var content: Control = scene.find_child(prefix + "ScreenRow", true, false)
		var screen: Control = scene.find_child(prefix + "Screen", true, false)
		var controls: Control = scene.find_child(prefix + "Controls", true, false)
		check(player != null and header != null and content != null and screen != null and controls != null,
			prefix + " player has header/content/control sections")
		if player == null or header == null or content == null or screen == null or controls == null:
			continue
		check(header.get_global_rect().end.y <= content.get_global_rect().position.y + 1.0 \
			and content.get_global_rect().end.y <= controls.get_global_rect().position.y + 1.0,
			prefix + " sections are ordered header/content/controls")
		check(absf(content.size.x - player.size.x) <= 3.0,
			prefix + " black canvas matches parent width")
		check(absf(header.size.x - player.size.x) <= 3.0 and absf(controls.size.x - player.size.x) <= 3.0,
			prefix + " header and controls match parent width")
		check(rect_contains(content.get_global_rect(), screen.get_global_rect()),
			prefix + " video stays inside black canvas")
		check(screen.size.y > 0.0 and absf(screen.size.x / screen.size.y - 16.0 / 9.0) < 0.02,
			prefix + " video keeps 16:9 aspect ratio")
		fixed_heights[prefix + "Header"] = header.size.y
		fixed_heights[prefix + "Controls"] = controls.size.y
		content_heights[prefix] = content.size.y

	root.size = Vector2i(1440, 1080)
	await settle()
	if title_bar != null and menu_bar != null:
		check(absf(title_bar.size.y - float(fixed_heights["TitleBar"])) <= 1.0,
			"Window title bar height stays fixed while resizing")
		check(absf(menu_bar.size.y - float(fixed_heights["MenuBar"])) <= 1.0,
			"Menu bar height stays fixed while resizing")
	for prefix in ["Preview", "Output"]:
		var header: Control = scene.find_child(prefix + "Header", true, false)
		var content: Control = scene.find_child(prefix + "ScreenRow", true, false)
		var screen: Control = scene.find_child(prefix + "Screen", true, false)
		var controls: Control = scene.find_child(prefix + "Controls", true, false)
		if header == null or content == null or screen == null or controls == null:
			continue
		check(absf(header.size.y - float(fixed_heights[prefix + "Header"])) <= 1.0,
			prefix + " header height stays fixed while resizing")
		check(absf(controls.size.y - float(fixed_heights[prefix + "Controls"])) <= 1.0,
			prefix + " controls height stays fixed while resizing")
		check(absf(content.size.y - float(content_heights[prefix])) > 10.0,
			prefix + " black canvas absorbs height changes")
		check(rect_contains(content.get_global_rect(), screen.get_global_rect()),
			prefix + " resized video stays inside black canvas")

	root.size = Vector2i(1100, 650)
	await settle()
	if title_bar != null and menu_bar != null:
		check(absf(title_bar.size.y - float(fixed_heights["TitleBar"])) <= 1.0 \
			and absf(menu_bar.size.y - float(fixed_heights["MenuBar"])) <= 1.0,
			"Window bars stay fixed at compact window height")
	for prefix in ["Preview", "Output"]:
		var header: Control = scene.find_child(prefix + "Header", true, false)
		var content: Control = scene.find_child(prefix + "ScreenRow", true, false)
		var screen: Control = scene.find_child(prefix + "Screen", true, false)
		var controls: Control = scene.find_child(prefix + "Controls", true, false)
		if header == null or content == null or screen == null or controls == null:
			continue
		check(absf(header.size.y - float(fixed_heights[prefix + "Header"])) <= 1.0 \
			and absf(controls.size.y - float(fixed_heights[prefix + "Controls"])) <= 1.0,
			prefix + " bars stay fixed at compact window height")
		check(rect_contains(content.get_global_rect(), screen.get_global_rect()),
			prefix + " compact video stays inside black canvas")

	root.size = Vector2i(1440, 900)
	await settle()

	var split: QuadSplitContainer = scene.get_node("%QuadSplit")
	var players: Control = scene.find_child("PlayersSection", true, false)
	split.max_x_percent = 50
	split.split_x_ratio = 0.9
	await settle()
	var split_available_x := split.size.x - split.dragger_width
	check(players.size.x <= split_available_x * 0.5 + 1.0, "First column maximum percentage is enforced")
	root.size = Vector2i(1200, 800)
	await settle()
	split_available_x = split.size.x - split.dragger_width
	check(players.size.x <= split_available_x * 0.5 + 1.0,
		"Percentage limit is recalculated after window resize")
	root.size = Vector2i(1440, 900)
	await settle()
	split_available_x = split.size.x - split.dragger_width
	split.max_x_percent = 85
	split.min_x_percent = 60
	split.split_x_ratio = 0.05
	await settle()
	check(players.size.x >= split_available_x * 0.6 - 1.0, "First column minimum percentage is enforced")
	split.min_x_percent = 35
	split.max_y_percent = 55
	split.split_y_ratio = 0.9
	await settle()
	var split_available_y := split.size.y - split.dragger_width
	check(players.size.y <= split_available_y * 0.55 + 1.0, "First row maximum percentage is enforced")
	split.max_y_percent = 75
	split.min_y_percent = 45
	split.split_y_ratio = 0.05
	await settle()
	check(players.size.y >= split_available_y * 0.45 - 1.0, "First row minimum percentage is enforced")
	split.min_y_percent = 35
	split.split_x_ratio = 0.72
	split.split_y_ratio = 0.5
	await settle()
	var utility_panel := scene.find_child("UtilityPanel", true, false) as PanelContainer
	var utility_header := scene.find_child("UtilityHeaderCard", true, false) as PanelContainer
	var utility_content := scene.find_child("UtilityContentCard", true, false) as PanelContainer
	check(utility_panel != null and utility_header != null and utility_content != null
		and utility_header.get_parent() == utility_content.get_parent()
		and utility_header.get_parent().get_theme_constant("separation") == 0,
		"Utility title and content form one bordered card")
	var audio_panel := scene.find_child("AudioPanel", true, false) as PanelContainer
	var audio_header := scene.find_child("AudioHeaderCard", true, false) as PanelContainer
	var audio_content := scene.find_child("AudioContentCard", true, false) as PanelContainer
	check(audio_panel != null and audio_header != null and audio_content != null
		and audio_header.get_parent() == audio_content.get_parent()
		and audio_header.get_parent().get_theme_constant("separation") == 0,
		"Audio title and content form one bordered card")
	var audio_master_item := scene.find_child("AudioMasterItem", true, false) as PanelContainer
	var audio_master_slider := scene.find_child("AudioMasterSlider", true, false) as VSlider
	var audio_master_mute := scene.find_child("AudioMasterMute", true, false) as Button
	check(audio_master_item != null and audio_master_slider != null and audio_master_mute != null
		and audio_master_item.is_ancestor_of(audio_master_slider)
		and audio_master_item.is_ancestor_of(audio_master_mute),
		"Audio mixer master item has a vertical volume slider and mute control")
	check(absf(audio_master_slider.get_global_rect().get_center().x
		- audio_master_item.get_global_rect().get_center().x) <= 1.0,
		"Master volume slider is horizontally centered in its item")
	check(scene.find_child("AudioDesc", true, false) == null,
		"Audio mixer has no redundant description label")
	var media_panel := scene.find_child("MediaPanel", true, false) as PanelContainer
	var media_scroll := scene.find_child("MediaScroll", true, false) as ScrollContainer
	var media_panel_style := media_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var media_scroll_style := media_scroll.get_theme_stylebox("panel") as StyleBoxFlat
	check(media_panel_style != null and media_scroll_style != null
		and media_panel_style.corner_radius_top_left == 0
		and media_panel_style.corner_radius_top_right == 0
		and media_panel_style.corner_radius_bottom_left == 0
		and media_panel_style.corner_radius_bottom_right == 0
		and media_scroll_style.corner_radius_top_left == 0
		and media_scroll_style.corner_radius_top_right == 0
		and media_scroll_style.corner_radius_bottom_left == 0
		and media_scroll_style.corner_radius_bottom_right == 0,
		"Media library panel and scroll area use square corners")
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
