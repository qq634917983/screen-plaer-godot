extends SceneTree
## Run in an isolated copy with a unique application/config/name (separate user://).
var failures := 0

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Cast smoke test timed out")
		quit(1))
	call_deferred("run")

func run() -> void:
	# Refuse to write test settings into the real player's user directory.
	if not str(ProjectSettings.get_setting("application/config/name")).begins_with("ScreenPlayerCastTest"):
		push_error("Use an isolated test project named ScreenPlayerCastTest...")
		quit(1)
		return
	# Each run starts clean inside the explicitly isolated test user directory.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProjectStore.SETTINGS_PATH))
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var settings: SettingsWindow = scene._settings_window
	settings.open()
	settings._pos_x_spin.get_line_edit().text = "120"
	settings._pos_y_spin.get_line_edit().text = "-1"
	settings._width_spin.get_line_edit().text = "640"
	settings._commit_window_settings()
	await create_timer(0.3).timeout
	check(ProjectStore.get_setting("cast_window", "pos_x", 0) == 120, "Apply commits unconfirmed text")
	check(scene._cast_window.size == Vector2i(640, 540), "Apply commits size")
	check(scene._cast_window.position.x == 120, "X moves while Y remains automatic")
	settings._pos_y_spin.get_line_edit().text = "160"
	settings._commit_window_settings()
	scene._show_cast_window()
	await create_timer(0.3).timeout
	check(scene._cast_window.position == Vector2i(120, 160), "Show preserves requested geometry")
	settings._pos_x_spin.get_line_edit().text = "190"
	settings._commit_window_settings()
	await create_timer(0.3).timeout
	check(scene._cast_window.position == Vector2i(190, 160), "Change X alone on visible window")
	settings._pos_y_spin.get_line_edit().text = "210"
	settings._commit_window_settings()
	await create_timer(0.3).timeout
	check(scene._cast_window.position == Vector2i(190, 210), "Change Y alone on visible window")
	var event := InputEventKey.new()
	event.keycode = KEY_P
	event.ctrl_pressed = true
	event.alt_pressed = true
	event.pressed = true
	check(SettingsWindow.get_hotkey("toggle_cast") == event.get_keycode_with_modifiers(), "Default Ctrl+Alt+P")
	scene._cast_window.window_input.emit(event)
	check(not scene._cast_window.visible, "Shortcut from cast window hides it")
	var plain := InputEventKey.new()
	plain.keycode = KEY_P
	plain.pressed = true
	scene._input(plain)
	check(not scene._cast_window.visible, "Plain P does not match modified shortcut")
	scene._input(event)
	check(scene._cast_window.visible, "Shortcut from main window restores cast")
	settings._capturing_action = "toggle_cast"
	var custom := InputEventKey.new()
	custom.keycode = KEY_H
	custom.ctrl_pressed = true
	custom.shift_pressed = true
	custom.pressed = true
	var modifier := InputEventKey.new()
	modifier.keycode = KEY_CTRL
	modifier.pressed = true
	settings._input(modifier)
	check(settings.is_capturing_hotkey(), "Modifier alone keeps combination capture active")
	settings._input(custom)
	check(settings._pending_hotkeys["toggle_cast"] == custom.get_keycode_with_modifiers(), "Custom combination is staged")
	settings._apply_changes()
	check(SettingsWindow.get_hotkey("toggle_cast") == custom.get_keycode_with_modifiers(), "Apply persists custom combination")
	scene._settings_window.window_input.emit(event)
	check(scene._cast_window.visible, "Old shortcut stops matching after customization")
	scene._settings_window.window_input.emit(custom)
	check(not scene._cast_window.visible, "Custom shortcut works from settings window")
	event.echo = true
	scene._input(event)
	check(not scene._cast_window.visible, "Key repeat does not toggle")
	scene.queue_free()
	await process_frame
	print("CAST SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
