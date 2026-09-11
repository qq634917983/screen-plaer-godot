class_name ProjectStore
extends RefCounted
## 项目 / 应用设置持久化。
## 项目文件（*.splproj，ConfigFile 格式）：项目名 + 媒体库条目列表
## （media/items = 媒体对象字典数组，含路径与缩放/偏移属性；
## 另保留 media/paths 纯路径列表以兼容旧版）+ 播放列表
## （playlist/lists = PlaylistObject 字典数组：条目/时长/定时自动播放）；
## library/order 保存媒体与播放列表卡片的混排顺序。
## 应用设置（user://settings.cfg）：上次打开的项目路径。
##
## 项目缓存捆绑（Phase 9 起）：项目文件 X.splproj 的同级缓存目录 X_cache/，
## 内容：pptx/<md5>.html（PPT 转换结果）+ thumbs/<md5>.png（条目封面副本）。
## 保存/另存为时把全局缓存（user://pptx、user://thumbnails）同步进 X_cache/
## （缺失才复制，不删多余文件）；打开项目时优先从 X_cache/ 查找，
## 找不到回退全局目录（PPT 缓存两级都没有则由 PptxConverter 重转）。

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_PROJECT_PATH := "user://projects/default.splproj"
const DEFAULT_PROJECT_NAME := "默认项目"
const PROJECT_FILTER := "*.splproj ; ScreenPlayer 项目"
const GLOBAL_THUMB_DIR := "user://thumbnails"
const GLOBAL_PPTX_DIR := "user://pptx"


static func save_project(path: String, project_name: String, items: Array, playlists: Array = [], library_order: Array = []) -> Error:
	# ConfigFile.save 不自动建目录，先确保父目录存在
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var cfg := ConfigFile.new()
	cfg.set_value("project", "name", project_name)
	var dicts: Array = []
	var paths := PackedStringArray()
	for m: MediaObject in items:
		dicts.append(m.to_dict())
		paths.append(m.path)
	cfg.set_value("media", "paths", paths)  # 兼容旧版读取
	cfg.set_value("media", "items", dicts)
	var pl_dicts: Array = []
	for pl: PlaylistObject in playlists:
		pl_dicts.append(pl.to_dict())
	cfg.set_value("playlist", "lists", pl_dicts)
	cfg.set_value("library", "order", library_order)
	return cfg.save(path)


static func load_project(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	return {
		"name": str(cfg.get_value("project", "name", path.get_file().get_basename())),
		"media_paths": cfg.get_value("media", "paths", PackedStringArray()),
		"items": cfg.get_value("media", "items", []),
		"playlists": cfg.get_value("playlist", "lists", []),
		"library_order": cfg.get_value("library", "order", []),
	}


static func project_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func load_last_project_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value("app", "last_project", ""))


static func set_last_project_path(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其它设置项
	cfg.set_value("app", "last_project", path)
	cfg.save(SETTINGS_PATH)


static func get_setting(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default
	return cfg.get_value(section, key, default)


static func set_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其它设置项
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)


## 一次写入同一分区的多个设置，避免窗口连续保存宽高时重复读写配置文件。
static func set_settings(section: String, values: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 保留其它设置项
	for key in values:
		cfg.set_value(section, str(key), values[key])
	cfg.save(SETTINGS_PATH)


# ---------- 项目缓存目录（X_cache） ----------

## 项目文件 X.splproj → 同级缓存目录 X_cache/
static func cache_dir_for(project_path: String) -> String:
	return project_path.get_basename() + "_cache"


## 查找条目封面：项目缓存优先，回退全局 user://thumbnails；都没有返回 ""
static func find_cover(project_cache_dir: String, media_path: String) -> String:
	var name := media_path.md5_text() + ".png"
	if not project_cache_dir.is_empty():
		var p := project_cache_dir + "/thumbs/" + name
		if FileAccess.file_exists(p):
			return p
	var g := GLOBAL_THUMB_DIR + "/" + name
	return g if FileAccess.file_exists(g) else ""


## 查找 PPT 转换缓存：项目缓存优先，回退全局 user://pptx；都没有返回 ""
static func find_pptx_html(project_cache_dir: String, media_path: String) -> String:
	var name := media_path.md5_text() + ".html"
	if not project_cache_dir.is_empty():
		var p := project_cache_dir + "/pptx/" + name
		if FileAccess.file_exists(p):
			return p
	var g := GLOBAL_PPTX_DIR + "/" + name
	return g if FileAccess.file_exists(g) else ""


## 保存/另存为项目时调用：把当前项目条目的封面与 PPT 转换结果
## 从全局目录同步进 X_cache/（缺失才复制，不删多余文件）
static func sync_project_cache(project_path: String, items: Array) -> void:
	if project_path.is_empty():
		return
	var base := cache_dir_for(project_path)
	var pptx_dir := base + "/pptx"
	var thumb_dir := base + "/thumbs"
	for m: MediaObject in items:
		var md5 := m.path.md5_text()
		_copy_if_missing(GLOBAL_THUMB_DIR + "/" + md5 + ".png", thumb_dir)
		if m.type == MediaObject.Type.PPT:
			_copy_if_missing(GLOBAL_PPTX_DIR + "/" + md5 + ".html", pptx_dir)


static func _copy_if_missing(src: String, dst_dir: String) -> void:
	if not FileAccess.file_exists(src):
		return
	var dst := dst_dir + "/" + src.get_file()
	if FileAccess.file_exists(dst):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_dir))
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	if err != OK:
		push_warning("缓存同步失败（%s → %s）：%s" % [src, dst, error_string(err)])


## 「复制到项目目录」导入：把源文件真实复制进 X_cache/media/，
## 文件名带源路径 md5 前缀避免重名冲突（同源重复导入直接复用已有副本）。
## 返回复制后的路径；失败返回 ""。
static func copy_media_into_project(project_path: String, src_path: String) -> String:
	if project_path.is_empty():
		push_warning("项目尚未保存，无法复制媒体文件（请先保存/另存为项目）：" + src_path)
		return ""
	if not FileAccess.file_exists(src_path):
		push_warning("源文件不存在，无法复制：" + src_path)
		return ""
	var media_dir := cache_dir_for(project_path) + "/media"
	var dst := media_dir + "/" + src_path.md5_text().substr(0, 8) + "_" + src_path.get_file()
	if FileAccess.file_exists(dst):
		return dst  # 同一源文件此前已复制过
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(media_dir))
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src_path), ProjectSettings.globalize_path(dst))
	if err != OK:
		push_warning("媒体文件复制失败（%s → %s）：%s" % [src_path, dst, error_string(err)])
		return ""
	return dst
