extends SceneTree
## 验证主音量及媒体 item 的纵向调音台、条目音量持久化和实际合成音量。

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


func wait_for_startup(scene: Node) -> void:
	for _i in 60:
		if not scene._startup_initializing:
			return
		await process_frame


func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Audio mixer smoke test timed out")
		quit(1)
	)
	call_deferred("run")


func run() -> void:
	var previous_project := ProjectStore.load_last_project_path()
	var previous_master: Variant = ProjectStore.get_setting("audio", "output_volume", 100)
	var previous_enabled: Variant = ProjectStore.get_setting("audio", "output", true)
	var test_path := "user://tests/audio-mixer-%d.splproj" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	check(ProjectStore.save_project(test_path, "调音台测试", []) == OK, "Create isolated mixer project")
	ProjectStore.set_last_project_path(test_path)
	ProjectStore.set_setting("audio", "output_volume", 80)
	ProjectStore.set_setting("audio", "output", true)

	var scene = load("res://main.tscn").instantiate()
	scene.cef_enabled = false
	root.add_child(scene)
	await wait_for_startup(scene)
	check(not scene._startup_initializing, "Main scene startup completes before mixer checks")
	scene._clear_media_items()
	scene._project_path = test_path

	var video := MediaObject.create("res://tests/mixer-video.mp4")
	var audio := MediaObject.create("res://tests/mixer-audio.mp3")
	var image := MediaObject.create("res://tests/mixer-image.png")
	scene._add_media_item(video)
	scene._add_media_item(audio)
	scene._add_media_item(image)
	await settle()

	var channels: HBoxContainer = scene.get_node("%AudioChannels")
	check(channels.get_child_count() == 3, "Mixer contains master plus video/audio media items")
	var master_header := scene.get_node("%AudioMasterHeader") as PanelContainer
	var master_title := scene.find_child("AudioMasterLabel", true, false) as Label
	check(master_header != null and master_title != null and not master_title.text.is_empty(),
		"Master controller has its own title bar")
	check(scene._audio_item_controls.has(video) and scene._audio_item_controls.has(audio),
		"Every audio-capable media item has mixer controls")
	check(not scene._audio_item_controls.has(image), "Silent image item is omitted from mixer")
	for media: MediaObject in [video, audio]:
		var controls: Dictionary = scene._audio_item_controls[media]
		check(controls["slider"] is VSlider and controls["mute"] is Button
			and controls["header"] is PanelContainer and controls["title"] is Label
			and not (controls["title"] as Label).text.is_empty(),
			media.display_name() + " has a title bar, vertical volume and mute controls")
		var slider := controls["slider"] as VSlider
		var item := controls["item"] as PanelContainer
		check(absf(slider.get_global_rect().get_center().x - item.get_global_rect().get_center().x) <= 1.0,
			media.display_name() + " volume slider is horizontally centered")
		var channel_header_style := (controls["header"] as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		var master_header_style := master_header.get_theme_stylebox("panel") as StyleBoxFlat
		check(channel_header_style != null and master_header_style != null
			and channel_header_style.bg_color == master_header_style.bg_color,
			media.display_name() + " title bar matches the master controller")

	var video_slider := scene._audio_item_controls[video]["slider"] as VSlider
	video_slider.value = 37
	await settle()
	check(video.volume == 37, "Media slider updates its item volume")
	scene._output_media = video
	scene._apply_output_volume()
	check(scene._output.volume == 30, "Master and item volume combine before output")
	scene._on_media_mixer_mute_pressed(video)
	check(video.muted and scene._output.muted, "Media mixer mute applies to the active output item")

	var saved := ProjectStore.load_project(test_path)
	var saved_items: Array = saved.get("items", [])
	check(not saved_items.is_empty() and int(saved_items[0].get("volume", -1)) == 37
		and bool(saved_items[0].get("muted", false)), "Item volume and mute persist in the project")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
	var screenshot := ProjectSettings.globalize_path("res://.build/audio_mixer.png")
	check(root.get_texture().get_image().save_png(screenshot) == OK, "Audio mixer screenshot saved")
	print("SCREENSHOT=", screenshot)

	scene.queue_free()
	await process_frame
	ProjectStore.set_setting("audio", "output_volume", previous_master)
	ProjectStore.set_setting("audio", "output", previous_enabled)
	ProjectStore.set_last_project_path(previous_project)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	print("AUDIO_MIXER failures=", failures)
	quit(0 if failures == 0 else 1)
