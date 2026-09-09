extends Control

func _ready():
	if not $CEF.initialize({"incognito": true, "locale": "zh-CN"}):
		push_error("CEF init failed: " + $CEF.get_error())
		return
	print("CEF version: ", $CEF.get_full_version())
	await get_tree().process_frame
	await get_tree().process_frame
	var url = "file://" + ProjectSettings.globalize_path("res://doc/test.html")
	print("Loading: ", url)
	var browser = $CEF.create_browser(url, $TextureRect, {
		"javascript": true,
		"webgl": true,
		"frame_rate": 30,
	})
	if browser == null:
		push_error("create_browser failed: " + $CEF.get_error())
		return
	print("Browser created: ", browser.name)
	browser.connect("on_page_loaded", func(u): print("PAGE_LOADED: ", u))
	browser.connect("on_page_failed_loading", func(u, c, m): print("PAGE_FAILED: ", u, " ", c, " ", m))
