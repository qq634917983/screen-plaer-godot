extends SceneTree
## 原生窗口回归：按钮打开设置，并恢复最小化或移出屏幕的设置窗口。

var failures := 0

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(1))
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.cef_enabled = false
	root.add_child(scene)
	while scene._startup_initializing:
		await process_frame
	var settings: Window = scene.get_node("%SettingsWindow")
	var button: Button = scene.get_node("%MenuSettings")
	button.pressed.emit()
	await process_frame
	check(settings.visible, "Settings button opens window")
	settings.mode = Window.MODE_MINIMIZED
	await create_timer(0.2).timeout
	button.pressed.emit()
	await create_timer(0.2).timeout
	check(settings.mode == Window.MODE_WINDOWED, "Settings button restores minimized window")
	settings.position = Vector2i(-30000, -30000)
	await process_frame
	button.pressed.emit()
	await process_frame
	var screen := DisplayServer.screen_get_usable_rect(root.current_screen)
	if DisplayServer.get_name() != "headless":
		check(screen.intersects(Rect2i(settings.position, settings.size)),
			"Settings button brings offscreen window back to main screen")
	settings.hide()
	button.pressed.emit()
	await process_frame
	check(settings.visible, "Settings button reopens closed window")
	quit(1 if failures else 0)
