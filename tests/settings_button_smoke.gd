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

	# 再次点击：窗口已可见时只 grab_focus，不报错不重复居中
	button.pressed.emit()
	await process_frame
	check(scene._settings_window.visible, "SettingsWindow stays visible on second click")

	quit(1 if failures > 0 else 0)
