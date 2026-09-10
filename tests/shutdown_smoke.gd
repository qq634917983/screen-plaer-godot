extends SceneTree
## 启动完整主场景后走统一关闭流程；进程能在外部超时前退出即通过。


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.cef_cache_path = "user://smoke/cef-shutdown-%d" % OS.get_process_id()
	root.add_child(scene)
	for i in range(6):
		await process_frame
	print("SHUTDOWN start_msec=", Time.get_ticks_msec())
	scene._request_app_quit()
