extends SceneTree
## 验证资源管理器拖放添加、去重、项目落盘和主窗口宽高持久化。

var failures := 0
var _settings_existed := false
var _settings_backup := PackedByteArray()
var _original_window_size := Vector2i.ZERO


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var settings_path := ProjectSettings.globalize_path(ProjectStore.SETTINGS_PATH)
	_settings_existed = FileAccess.file_exists(settings_path)
	if _settings_existed:
		_settings_backup = FileAccess.get_file_as_bytes(settings_path)
	_original_window_size = root.size
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Drop/window persistence smoke test timed out")
		_restore_settings()
		quit(1)
	)
	call_deferred("run")


func run() -> void:
	var stamp := str(OS.get_process_id())
	var project_path := "user://tests/drop-window-%s.splproj" % stamp
	var image_path := "user://tests/drop-window-%s.png" % stamp
	var ignored_path := "user://tests/drop-window-%s.txt" % stamp
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var image := Image.create(32, 18, false, Image.FORMAT_RGB8)
	image.fill(Color.CORNFLOWER_BLUE)
	check(image.save_png(image_path) == OK, "Create temporary dragged image")
	var ignored := FileAccess.open(ignored_path, FileAccess.WRITE)
	ignored.store_string("unsupported")
	ignored.close()
	check(ProjectStore.save_project(project_path, "拖放测试", []) == OK, "Create isolated project")
	ProjectStore.set_last_project_path(project_path)
	ProjectStore.set_setting("media", "copy_to_project", false)

	var scene = load("res://main.tscn").instantiate()
	scene.cef_enabled = false
	scene.cef_cache_path = "user://tests/cef-%s" % stamp
	root.add_child(scene)
	while scene._startup_initializing:
		await process_frame
	root.files_dropped.emit(PackedStringArray([ProjectSettings.globalize_path(image_path), ProjectSettings.globalize_path(ignored_path)]))
	await process_frame
	check(scene._media_items.size() == 1, "Drop adds supported media and ignores unsupported file")
	if scene._media_items.size() == 1:
		check(scene._media_items[0].type == MediaObject.Type.IMAGE, "Dropped item keeps detected media type")
	root.files_dropped.emit(PackedStringArray([ProjectSettings.globalize_path(image_path)]))
	await process_frame
	check(scene._media_items.size() == 1, "Dropping the same file does not create a duplicate item")
	var saved := ProjectStore.load_project(project_path)
	check((saved.get("items", []) as Array).size() == 1, "Dropped item is saved to the current project")

	var usable := DisplayServer.screen_get_usable_rect(root.current_screen).size
	var target := Vector2i(mini(1100, usable.x), mini(650, usable.y))
	target.x = maxi(target.x, 1024)
	target.y = maxi(target.y, 600)
	# 用户上次窗口尺寸可能恰好就是默认测试值；改用另一档以确保触发 size_changed。
	if root.size == target:
		target = Vector2i(1024, 600)
		if root.size == target:
			target = Vector2i(mini(1080, usable.x), mini(630, usable.y))
	root.size = target
	await create_timer(0.5).timeout
	check(int(ProjectStore.get_setting("main_window", "width", 0)) == target.x, "Main window width is saved")
	check(int(ProjectStore.get_setting("main_window", "height", 0)) == target.y, "Main window height is saved")
	root.size = Vector2i(1024, 600)
	scene._restore_main_window_size()
	check(root.size == target, "Saved main window width and height are restored")

	scene.queue_free()
	await process_frame
	root.size = _original_window_size
	_restore_settings()
	for path in [project_path, image_path, ignored_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("DROP_WINDOW_SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)


func _restore_settings() -> void:
	var settings_path := ProjectSettings.globalize_path(ProjectStore.SETTINGS_PATH)
	if _settings_existed:
		var file := FileAccess.open(settings_path, FileAccess.WRITE)
		file.store_buffer(_settings_backup)
		file.close()
	elif FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
