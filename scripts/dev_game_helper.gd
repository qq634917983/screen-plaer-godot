extends Node
## 编辑器调试构建才加载 Godot AI 游戏助手；Release 不创建日志捕获器或逐帧探针。


func _ready() -> void:
	if not OS.is_debug_build():
		return
	var helper_script := load("res://addons/godot_ai/runtime/game_helper.gd")
	if helper_script == null:
		return
	var helper: Node = helper_script.new()
	helper.name = "GameHelper"
	add_child(helper)
