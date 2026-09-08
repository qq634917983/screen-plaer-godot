class_name PlatformPaths
extends RefCounted
## 将 Godot/系统路径转换为浏览器 URL，保留网络 URL。
static func browser_url(path: String) -> String:
	if path.contains("://") and not path.begins_with("res://") and not path.begins_with("user://"):
		return path
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/")
	var encoded := ""
	for segment in absolute.split("/", true):
		if not encoded.is_empty():
			encoded += "/"
		encoded += segment.uri_encode()
	# split 的首个空段需要显式保留；Windows 盘符冒号不能编码。
	if absolute.begins_with("//"):
		return "file://" + encoded
	if absolute.begins_with("/"):
		return "file:///" + encoded
	if absolute.length() > 1 and absolute[1] == ":":
		encoded = encoded.replace("%3A", ":")
	return "file:///" + encoded
