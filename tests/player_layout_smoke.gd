extends SceneTree
## 验证播放器固定栏、黑色可变画布、16:9 画面和六区域自由布局。

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


func has_no_border(style: StyleBoxFlat) -> bool:
	return style != null \
		and style.border_width_left == 0 \
		and style.border_width_top == 0 \
		and style.border_width_right == 0 \
		and style.border_width_bottom == 0


func color_difference(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


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
		var title_style := title_bar.get_theme_stylebox("panel") as StyleBoxFlat
		var window_style := (scene as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		check(title_style != null and window_style != null
			and color_difference(title_style.bg_color, window_style.bg_color) > 0.08,
			"Window title bar has a distinct blue-gray background")

	var transition_content := scene.find_child("TransitionContent", true, false) as Control
	var quick_switch := scene.find_child("QuickSwitch", true, false) as Button
	check(transition_content != null and quick_switch != null, "Transition quick switch exists")
	if transition_content != null and quick_switch != null:
		check(quick_switch.text == "快速切换" and not quick_switch.text.contains("→")
			and not quick_switch.text.contains("\n"),
			"Quick switch uses a single-line label without an arrow")
		var side_gap := quick_switch.get_global_rect().position.x - transition_content.get_global_rect().position.x
		check(quick_switch.size.x >= 90.0 and quick_switch.size.y <= 36.0
			and side_gap >= 15.0
			and transition_content.get_global_rect().end.x - quick_switch.get_global_rect().end.x >= 15.0,
			"Quick switch is short and keeps left/right margins")
		check(quick_switch.get_global_rect().position.y
			- transition_content.get_global_rect().position.y <= 26.0,
			"Quick switch sits near the top of the transition content")

	for button_name in ["PreviewPlay", "PreviewStop", "OutputPlay", "OutputStop", "OutputMute"]:
		var player_button := scene.find_child(button_name, true, false) as Button
		var normal_style := player_button.get_theme_stylebox("normal") as StyleBoxFlat if player_button != null else null
		check(player_button != null and has_no_border(normal_style),
			button_name + " has no rectangular outline")

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
	split.split_x_ratio = 0.1
	await settle()
	var split_available_x := split.size.x - split.dragger_width
	check(absf(players.size.x - split_available_x * 0.1) <= 2.0,
		"First column can shrink freely without the old minimum limit")
	split.split_x_ratio = 0.9
	await settle()
	check(absf(players.size.x - split_available_x * 0.9) <= 2.0,
		"First column can expand freely without the old maximum limit")
	root.size = Vector2i(1200, 800)
	await settle()
	split_available_x = split.size.x - split.dragger_width
	check(absf(players.size.x - split_available_x * 0.9) <= 2.0,
		"Outer split stays proportional when the window resizes")
	root.size = Vector2i(1440, 900)
	await settle()
	split.split_y_ratio = 0.1
	await settle()
	var split_available_y := split.size.y - split.dragger_width
	check(absf(players.size.y - split_available_y * 0.1) <= 2.0,
		"First row can shrink freely without the old minimum limit")
	split.split_y_ratio = 1.0
	await settle()
	var audio_dock := scene.find_child("AudioDock", true, false) as Control
	var protected_audio_header := scene.find_child("AudioHeaderCard", true, false) as Control
	check(audio_dock != null and protected_audio_header != null
		and audio_dock.size.y >= 44.0
		and rect_contains(audio_dock.get_global_rect(), protected_audio_header.get_global_rect()),
		"Bottom audio title bar stays fully visible at the vertical drag limit")
	split.split_y_ratio = 0.0
	await settle()
	var utility_dock := scene.find_child("UtilityDock", true, false) as Control
	var protected_utility_header := scene.find_child("UtilityHeaderCard", true, false) as Control
	check(utility_dock != null and protected_utility_header != null
		and utility_dock.size.y >= 44.0
		and rect_contains(utility_dock.get_global_rect(), protected_utility_header.get_global_rect()),
		"Top title bars stay fully visible at the vertical drag limit")
	split.split_x_ratio = 0.72
	split.split_y_ratio = 0.5
	await settle()
	var player_split := players as TripleSplitContainer
	var preview_panel := scene.find_child("PreviewDock", true, false) as Control
	var transition_panel := scene.find_child("TransitionDock", true, false) as Control
	var output_panel := scene.find_child("OutputDock", true, false) as Control
	check(player_split != null and preview_panel != null and transition_panel != null and output_panel != null,
		"Preview, transition and output are three independently sized panels")
	if player_split != null:
		player_split.right_ratio = 0.8
		player_split.left_ratio = 0.2
		await settle()
		var player_available := player_split.size.x - player_split.dragger_width * 2
		check(absf(preview_panel.size.x - player_available * 0.2) <= 2.0,
			"Preview panel follows its own draggable ratio")
		check(absf(transition_panel.size.x - player_available * 0.6) <= 2.0,
			"Transition panel follows both draggable boundaries")
		check(output_panel.size.x <= player_available * 0.25,
			"Output panel follows its own draggable ratio down to its control minimum")
		player_split.right_ratio = 0.57
		player_split.left_ratio = 0.43
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
	var audio_master_header := scene.find_child("AudioMasterHeader", true, false) as PanelContainer
	var audio_master_title := scene.find_child("AudioMasterLabel", true, false) as Label
	var audio_master_slider := scene.find_child("AudioMasterSlider", true, false) as VSlider
	var audio_master_mute := scene.find_child("AudioMasterMute", true, false) as Button
	check(audio_master_item != null and audio_master_slider != null and audio_master_mute != null
		and audio_master_item.is_ancestor_of(audio_master_slider)
		and audio_master_item.is_ancestor_of(audio_master_mute),
		"Audio mixer master item has a vertical volume slider and mute control")
	check(audio_master_header != null and audio_master_title != null
		and audio_master_header.is_ancestor_of(audio_master_title)
		and not audio_master_title.text.is_empty(),
		"Audio mixer master controller has a dedicated title bar")
	check(absf(audio_master_slider.get_global_rect().get_center().x
		- audio_master_item.get_global_rect().get_center().x) <= 1.0,
		"Master volume slider is horizontally centered in its item")
	check(scene.find_child("AudioDesc", true, false) == null,
		"Audio mixer has no redundant description label")
	check(scene.find_child("MediaDesc", true, false) == null
		and scene.find_child("UtilityDesc", true, false) == null,
		"Main UI has no inline media or utility description labels")
	var media_panel := scene.find_child("MediaPanel", true, false) as PanelContainer
	var media_header := scene.find_child("MediaHeader", true, false) as PanelContainer
	var media_scroll := scene.find_child("MediaScroll", true, false) as ScrollContainer
	var media_panel_style := media_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var media_header_style := media_header.get_theme_stylebox("panel") as StyleBoxFlat
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
	var player_outer_style := (scene.find_child("PreviewPlayer", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var player_header_style := (scene.find_child("PreviewHeader", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var player_content_style := (scene.find_child("PreviewScreenRow", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var utility_outer_style := utility_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var utility_header_style := utility_header.get_theme_stylebox("panel") as StyleBoxFlat
	var utility_content_style := utility_content.get_theme_stylebox("panel") as StyleBoxFlat
	var audio_outer_style := audio_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var audio_header_style := audio_header.get_theme_stylebox("panel") as StyleBoxFlat
	var audio_content_style := audio_content.get_theme_stylebox("panel") as StyleBoxFlat
	check(player_outer_style.border_width_left == 0 and player_outer_style.border_width_top == 0
		and player_outer_style.border_width_right == 0 and player_outer_style.border_width_bottom == 0,
		"Preview and output player shells are borderless")
	check(media_panel_style.bg_color == player_outer_style.bg_color
		and utility_outer_style.bg_color == player_outer_style.bg_color
		and audio_outer_style.bg_color == player_outer_style.bg_color,
		"Media, utility and audio outer cards use the player card color")
	check(media_header_style.bg_color == player_header_style.bg_color
		and utility_header_style.bg_color == player_header_style.bg_color
		and audio_header_style.bg_color == player_header_style.bg_color,
		"All workspace title bars use the player header color")
	var transition_header := scene.find_child("TransitionHeader", true, false) as PanelContainer
	check(absf(media_header.size.y - 40.0) <= 1.0
		and absf(utility_header.size.y - 40.0) <= 1.0
		and absf(audio_header.size.y - 40.0) <= 1.0
		and transition_header != null and absf(transition_header.size.y - 40.0) <= 1.0
		and absf((scene.find_child("PreviewHeader", true, false) as Control).size.y - 40.0) <= 1.0
		and absf((scene.find_child("OutputHeader", true, false) as Control).size.y - 40.0) <= 1.0,
		"All six workspace title bars share the same height")
	check(media_scroll_style.bg_color == player_content_style.bg_color
		and utility_content_style.bg_color == player_content_style.bg_color
		and audio_content_style.bg_color == player_content_style.bg_color,
		"All workspace content areas use the player content color")
	var transition_outer_style := (scene.find_child("TransitionPanel", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	check(transition_outer_style.border_width_left == 2 and transition_outer_style.border_width_top == 2
		and transition_outer_style.border_width_right == 2 and transition_outer_style.border_width_bottom == 2
		and media_panel_style.border_width_left == 2 and media_panel_style.border_width_top == 2
		and utility_outer_style.border_width_left == 2 and utility_outer_style.border_width_top == 2
		and audio_outer_style.border_width_left == 2 and audio_outer_style.border_width_top == 2,
		"Transition, media, utility and audio cards have a 2px outer border")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
	var root_texture := root.get_texture()
	if DisplayServer.get_name() != "headless" and root_texture != null:
		var screenshot := ProjectSettings.globalize_path("res://.build/player_layout.png")
		check(root_texture.get_image().save_png(screenshot) == OK, "Player layout screenshot saved")
		print("SCREENSHOT=", screenshot)
	var settings: SettingsWindow = scene.get_node("%SettingsWindow")
	settings.open()
	var tabs := settings.find_child("SettingsTabs", true, false) as TabContainer
	if tabs != null:
		tabs.current_tab = 2
	await settle()
	var settings_texture := settings.get_texture()
	if DisplayServer.get_name() != "headless" and settings_texture != null:
		var settings_screenshot := ProjectSettings.globalize_path("res://.build/layout_settings.png")
		check(settings_texture.get_image().save_png(settings_screenshot) == OK, "Layout settings screenshot saved")
		print("SETTINGS_SCREENSHOT=", settings_screenshot)
	settings.hide()
	scene.queue_free()
	await process_frame
	print("PLAYER_LAYOUT failures=", failures)
	quit(0 if failures == 0 else 1)
