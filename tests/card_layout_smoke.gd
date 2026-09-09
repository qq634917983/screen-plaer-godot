extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(8):
		await process_frame

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	# Exercise the real layout without starting decoders or loading user projects.
	scene.set_script(null)
	root.add_child(scene)
	var flow: HFlowContainer = scene.get_node("%MediaGrid")
	var split: Control = scene.get_node("%QuadSplit")
	var cards: Array[Control] = []
	for i in range(8):
		var card: Control
		if i % 2 == 0:
			card = MediaItemCard.new()
			var media := MediaObject.new()
			media.path = "example-with-long-name.mp4"
			card.setup(media)
		else:
			card = PlaylistCard.new()
			card.setup(PlaylistObject.new())
		flow.add_child(card)
		cards.append(card)
	for width in MediaItemCard.CARD_WIDTHS:
		for card in cards:
			card.apply_size(width)
		await settle()
		var baseline: Array[Vector2] = []
		for card in cards:
			baseline.append(card.size)
		for window_size in [Vector2i(1152, 800), Vector2i(1920, 1080), Vector2i(1280, 900)]:
			root.size = window_size
			for ratio in [Vector2(0.55, 0.4), Vector2(0.75, 0.6)]:
				split.split_x_ratio = ratio.x
				split.split_y_ratio = ratio.y
				await settle()
				for i in cards.size():
					if not cards[i].size.is_equal_approx(baseline[i]):
						failures += 1
						push_error("Card changed: %s -> %s" % [baseline[i], cards[i].size])
					var scale := cards[i].get_global_transform_with_canvas().get_scale()
					if not scale.is_equal_approx(Vector2.ONE):
						failures += 1
						push_error("Card canvas scaled: %s" % scale)
				print("LAYOUT width=%s window=%s split=%s card=%s panel=%s" % [width, window_size, ratio, cards[0].size, flow.size])
	scene.queue_free()
	await process_frame
	print("LAYOUT failures=", failures)
	quit(0 if failures == 0 else 1)
