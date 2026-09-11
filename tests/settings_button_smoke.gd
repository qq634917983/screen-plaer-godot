extends SceneTree
## 无头冒烟：main.tscn 可解析、MenuSettings 是 Button、pressed 信号已接线、
## 模拟点击后 SettingsWindow 可见。用法：
## godot --headless --path . --script tests/settings_button_smoke.gd

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: " + message)


func _initialize() -> void:
	create_timer(20.0).timeout.connect(func():
		push_error("Smoke test timed out")
		quit(1))
	call_deferred("run")


func run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	check(packed != null, "main.tscn loads")
	if packed == null:
		quit(1)
		return
	var scene = packed.instantiate()
	scene.cef_enabled = false
	scene.cef_cache_path = "user://smoke/cef-settings-button-%d" % OS.get_process_id()
	root.add_child(scene)
	await process_frame

	var button: Button = scene.get_node("%MenuSettings")
	check(button is Button, "MenuSettings is a plain Button")
	check(not (button is MenuButton), "MenuSettings no longer opens a popup menu")
	check(scene._settings_window is SettingsWindow, "SettingsWindow node present")
	check(not scene._settings_window.visible, "SettingsWindow hidden before click")

	# 模拟点击：pressed 信号驱动主逻辑弹出设置窗口
	button.pressed.emit()
	await process_frame
	check(scene._settings_window.visible, "SettingsWindow visible right after click")
	var cast_background: ColorRect = scene.get_node("%CastWindow/CastBackground")
	check(cast_background.color == Color.BLACK, "Cast window has an opaque black idle background")

	var apply_button: Button = scene._settings_window.find_child("ApplyButton", true, false)
	var ok_button: Button = scene._settings_window.find_child("OkButton", true, false)
	check(apply_button != null and ok_button != null, "Settings window has Apply and OK buttons")
	check(scene._settings_window.find_child("界面布局", true, false) != null,
		"Settings window has custom layout tab")
	for layout_button in ["SaveLayoutButton", "RestoreLayoutButton", "SetDefaultLayoutButton",
		"RestoreDefaultLayoutButton", "ExportLayoutButton", "ImportLayoutButton"]:
		check(scene._settings_window.find_child(layout_button, true, false) is Button,
			"Layout tab has " + layout_button)
	var help_tab: Node = scene._settings_window.find_child("帮助", true, false)
	var help_content: Node = scene._settings_window.find_child("HelpContent", true, false)
	check(help_tab != null and help_content != null,
		"Settings window centralizes main UI guidance in Help tab")
	var settings_tabs := scene._settings_window.find_child("SettingsTabs", true, false) as TabContainer
	settings_tabs.current_tab = settings_tabs.get_tab_count() - 1
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
	if DisplayServer.get_name() != "headless":
		var help_screenshot := ProjectSettings.globalize_path("res://.build/settings_help.png")
		check(scene._settings_window.get_texture().get_image().save_png(help_screenshot) == OK,
			"Settings Help screenshot saved")
		print("HELP_SCREENSHOT=", help_screenshot)
	var old_width := int(ProjectStore.get_setting("cast_window", "width", 960))
	var draft_width := 970 if old_width != 970 else 980
	scene._settings_window._width_spin.value = draft_width
	check(int(ProjectStore.get_setting("cast_window", "width", 960)) == old_width,
		"Editing a setting does not save before Apply or OK")
	apply_button.pressed.emit()
	await process_frame
	check(scene._settings_window.visible, "Apply keeps SettingsWindow open")
	check(int(ProjectStore.get_setting("cast_window", "width", 960)) == draft_width,
		"Apply saves settings")
	var confirmed_width := draft_width + 10
	scene._settings_window._width_spin.value = confirmed_width
	ok_button.pressed.emit()
	await process_frame
	check(not scene._settings_window.visible, "OK closes SettingsWindow")
	check(int(ProjectStore.get_setting("cast_window", "width", 960)) == confirmed_width,
		"OK saves settings before closing")
	ProjectStore.set_setting("cast_window", "width", old_width)

	var old_saved: Variant = ProjectStore.get_setting("ui", "saved_layout", {})
	var old_default: Variant = ProjectStore.get_setting("ui", "default_layout", {})
	var old_current: Dictionary = scene.get_current_layout()
	scene._apply_layout({"split_x": 0.31, "split_y": 0.42, "player_left": 0.22, "player_right": 0.73})
	scene._on_layout_command_requested("save", "")
	scene._apply_layout({"split_x": 0.8, "split_y": 0.8, "player_left": 0.4, "player_right": 0.6})
	scene._on_layout_command_requested("restore_saved", "")
	check(is_equal_approx(scene._quad_split.split_x_ratio, 0.31)
		and is_equal_approx(scene._players_split.left_ratio, 0.22),
		"Saved layout restores outer and player split ratios")
	scene._on_layout_command_requested("set_default", "")
	scene._apply_layout({"split_x": 0.6, "split_y": 0.6, "player_left": 0.3, "player_right": 0.7})
	scene._on_layout_command_requested("restore_default", "")
	check(is_equal_approx(scene._quad_split.split_x_ratio, 0.31)
		and is_equal_approx(scene._players_split.right_ratio, 0.73),
		"Custom default layout can be restored")
	var layout_path := ProjectSettings.globalize_path("res://.build/layout-test.spllayout")
	DirAccess.make_dir_recursive_absolute(layout_path.get_base_dir())
	scene._on_layout_command_requested("export", layout_path)
	check(FileAccess.file_exists(layout_path), "Layout exports to a portable file")
	scene._apply_layout({"split_x": 0.7, "split_y": 0.7, "player_left": 0.45, "player_right": 0.55})
	scene._on_layout_command_requested("import", layout_path)
	check(is_equal_approx(scene._quad_split.split_x_ratio, 0.31)
		and is_equal_approx(scene._players_split.right_ratio, 0.73),
		"Exported layout imports and applies")
	ProjectStore.set_setting("ui", "saved_layout", old_saved)
	ProjectStore.set_setting("ui", "default_layout", old_default)
	scene._apply_layout(old_current)

	# 再次点击：窗口已可见时只 grab_focus，不报错不重复居中
	button.pressed.emit()
	await process_frame
	check(scene._settings_window.visible, "SettingsWindow stays visible on second click")

	quit(1 if failures > 0 else 0)
