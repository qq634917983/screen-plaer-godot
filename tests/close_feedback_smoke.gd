extends SceneTree

var failures := 0


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var bar := preload("res://scripts/title_bar.gd").new()
	root.add_child(bar)
	await process_frame
	var button: Button = bar.find_child("CloseButton", true, false)
	check(button != null, "Close button is available")
	var emitted := [false]
	bar.close_requested.connect(func() -> void: emitted[0] = true)
	button.pressed.emit()
	await process_frame
	check(button.disabled and button.text == "…", "Close click shows immediate busy feedback")
	check("正在关闭" in bar._title_label.text, "Title reports closing state")
	check(not emitted[0], "Quit request waits for feedback animation")
	await create_timer(0.2).timeout
	check(emitted[0], "Quit request emits after animation")
	check(button.scale.is_equal_approx(Vector2.ONE), "Close button animation settles cleanly")
	bar.queue_free()
	await process_frame
	print("CLOSE FEEDBACK failures=", failures)
	quit(0 if failures == 0 else 1)
