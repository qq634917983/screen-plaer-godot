extends SceneTree
## 验证媒体/列表卡片统一平面三段式外观、排序编辑状态和混排顺序持久化。

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


func has_flat_outline(control: Control) -> bool:
	var style := control.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return false
	return style.get_border_width(SIDE_LEFT) == 0 \
		and style.get_border_width(SIDE_TOP) == 0 \
		and style.get_border_width(SIDE_RIGHT) == 0 \
		and style.get_border_width(SIDE_BOTTOM) == 0 \
		and style.corner_radius_top_left == 0 \
		and style.corner_radius_top_right == 0 \
		and style.corner_radius_bottom_left == 0 \
		and style.corner_radius_bottom_right == 0


func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Library order smoke test timed out")
		quit(1)
	)
	call_deferred("run")


func run() -> void:
	var previous_project := ProjectStore.load_last_project_path()
	var test_path := "user://tests/library-order-%d.splproj" % OS.get_process_id()
	var scene = load("res://main.tscn").instantiate()
	scene.cef_enabled = false
	root.add_child(scene)
	await settle()
	scene._clear_media_items()
	await process_frame
	scene._project_path = test_path
	scene._project_name = "排序测试"

	var first := MediaObject.create("https://example.com/first.html")
	var second := MediaObject.create("https://example.com/second.html")
	var playlist := PlaylistObject.new()
	playlist.name = "中间列表"
	scene._add_media_item(first)
	scene._add_media_item(second)
	scene._add_playlist(playlist)
	await settle()

	var cards: Array[Control] = scene._library_cards()
	check(cards.size() == 3, "Media and playlist cards share one reorderable grid")
	var media_card := cards[0] as MediaItemCard
	var playlist_card := cards[2] as PlaylistCard
	check(has_flat_outline(media_card) and has_flat_outline(playlist_card),
		"Cards have no border or rounded corners")
	check(media_card.get_node("CardSections/TitleSection") != null \
		and media_card.get_node("CardSections/PreviewSection") != null \
		and media_card.get_node("CardSections/ButtonsSection") != null,
		"Media card uses title/preview/buttons sections")
	check(playlist_card.get_node("CardSections/TitleSection") != null \
		and playlist_card.get_node("CardSections/PreviewSection") != null \
		and playlist_card.get_node("CardSections/ButtonsSection") != null,
		"Playlist card uses title/preview/buttons sections")
	var media_buttons: Control = media_card.get_node("CardSections/ButtonsSection")
	var playlist_buttons: Control = playlist_card.get_node("CardSections/ButtonsSection")
	print("BUTTON_HEIGHTS media=", media_buttons.size.y, " playlist=", playlist_buttons.size.y)
	check(absf(media_buttons.size.y - playlist_buttons.size.y) <= 1.0,
		"Playlist and media button areas have equal height")

	scene._order_edit_button.button_pressed = true
	await process_frame
	check(media_card.find_child("OrderControls", true, false).visible \
		and playlist_card.find_child("OrderControls", true, false).visible,
		"Edit order exposes move controls on every card")
	scene._move_library_card(playlist_card, -1)
	await settle()
	cards = scene._library_cards()
	check(cards[0] is MediaItemCard and cards[1] is PlaylistCard and cards[2] is MediaItemCard,
		"Playlist moves between media items")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.build"))
	var image := root.get_texture().get_image()
	var screenshot := ProjectSettings.globalize_path("res://.build/library_cards.png")
	check(image != null and image.save_png(screenshot) == OK, "Library card screenshot saved")
	print("SCREENSHOT=", screenshot)

	var saved := ProjectStore.load_project(test_path)
	var order: Array = saved.get("library_order", [])
	check(order.size() == 3 \
		and str(order[0].get("kind", "")) == "media" \
		and str(order[1].get("kind", "")) == "playlist" \
		and str(order[2].get("kind", "")) == "media",
		"Mixed library order is saved in the project")

	scene._load_project_from(test_path)
	await settle()
	cards = scene._library_cards()
	check(cards.size() == 3 and cards[0] is MediaItemCard \
		and cards[1] is PlaylistCard and cards[2] is MediaItemCard,
		"Mixed library order is restored after reopening")

	ProjectStore.set_last_project_path(previous_project)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	scene.queue_free()
	await process_frame
	print("LIBRARY_ORDER failures=", failures)
	quit(0 if failures == 0 else 1)
