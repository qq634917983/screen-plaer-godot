class_name MediaObject
extends RefCounted
## 媒体库条目模型：一个条目对应一个媒体对象。
## 类型由扩展名推断（视频/音频/图片/网页/PPT）；变换属性（缩放比例、
## 水平/垂直偏移）在条目设置窗口中编辑，播放端渲染画面时生效。
## 图片自 Phase 7 起可播放（静态纹理通路），网页自 Phase 8 起可播放
## （CEF 浏览器内核）；PPT 自 Phase 9 起可播放（PptxConverter 预转
## 自包含 HTML，经 CEF 播放，page_count 记录页数，0 = 未知）。

enum Type { VIDEO, AUDIO, IMAGE, HTML, PPT, OTHER }

const VIDEO_EXTS := ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "ts", "wmv"]
const AUDIO_EXTS := ["mp3", "wav", "ogg", "flac", "aac", "m4a", "wma", "opus"]
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tga"]
const HTML_EXTS := ["html", "htm"]
const PPT_EXTS := ["ppt", "pptx"]

var path := ""
var type := Type.VIDEO
var scale := 1.0  # 缩放比例（1.0 = 原始大小）
var offset_x := 0.0  # 水平偏移（像素）
var offset_y := 0.0  # 垂直偏移（像素）
var page_count := 0  # PPT 页数（0 = 未知，仅 Type.PPT 有意义）
var origin_path := ""  # 「复制到项目目录」导入时的原始路径（空 = 未复制）
var loop := false  # 条目级循环（推送到输出端时生效）
var muted := false  # 条目级静音（推送到输出端时生效，与全局声音开关为或关系）
var volume := 100  # 条目级音量（0-100，与主音量相乘后应用到输出端）
var touch_points: Array[Vector2] = []  # 网页触点序列（归一化 0-1 坐标，相对 1280×720 视口；输出端 ← → 逐步模拟点击）


static func create(media_path: String) -> MediaObject:
	var m := MediaObject.new()
	m.path = media_path
	m.type = detect_type(media_path)
	return m


static func detect_type(media_path: String) -> Type:
	var ext := media_path.get_extension().to_lower()
	if ext in VIDEO_EXTS:
		return Type.VIDEO
	if ext in AUDIO_EXTS:
		return Type.AUDIO
	if ext in IMAGE_EXTS:
		return Type.IMAGE
	if ext in HTML_EXTS:
		return Type.HTML
	if ext in PPT_EXTS:
		return Type.PPT
	return Type.OTHER


static func type_label(t: Type) -> String:
	match t:
		Type.VIDEO: return "视频"
		Type.AUDIO: return "音频"
		Type.IMAGE: return "图片"
		Type.HTML: return "网页"
		Type.PPT: return "PPT"
	return "其他"


## 无封面时的占位字形（Segoe UI Symbol / 纯文本，避免 emoji 字体混用）
static func type_glyph(t: Type) -> String:
	match t:
		Type.VIDEO: return "▶"
		Type.AUDIO: return "♪"
		Type.IMAGE: return "图"
		Type.HTML: return "</>"
		Type.PPT: return "P"
	return "？"


func display_name() -> String:
	return path.get_file()


## mpv 可直接播放视频和音频；图片走静态纹理通路（Phase 7 起）；
## 网页走 CEF 浏览器内核（Phase 8 起）；PPT 走 PptxConverter 预转
## HTML + CEF 播放（Phase 9 起，未转换时先排队转换）
func is_playable() -> bool:
	return type != Type.OTHER


## 网页 URL（http/https）无本地文件概念；user:// 等是本地路径不算远程
func is_remote() -> bool:
	return path.begins_with("http://") or path.begins_with("https://")


## 本地文件是否还在磁盘上（源文件被移动/删除后为 false；网页 URL 恒为 true）
func exists() -> bool:
	return is_remote() or FileAccess.file_exists(path)


func offset() -> Vector2:
	return Vector2(offset_x, offset_y)


func to_dict() -> Dictionary:
	var pts: Array = []
	for p in touch_points:
		pts.append([p.x, p.y])
	return {
		"path": path,
		"scale": scale,
		"offset_x": offset_x,
		"offset_y": offset_y,
		"page_count": page_count,
		"origin_path": origin_path,
		"loop": loop,
		"muted": muted,
		"volume": volume,
		"touch_points": pts,
	}


static func from_dict(d: Dictionary) -> MediaObject:
	var m := MediaObject.create(str(d.get("path", "")))
	m.scale = float(d.get("scale", 1.0))
	m.offset_x = float(d.get("offset_x", 0.0))
	m.offset_y = float(d.get("offset_y", 0.0))
	m.page_count = int(d.get("page_count", 0))  # 旧格式无此字段
	m.origin_path = str(d.get("origin_path", ""))  # 旧格式无此字段
	m.loop = bool(d.get("loop", false))  # 旧格式无此字段
	m.muted = bool(d.get("muted", false))  # 旧格式无此字段
	m.volume = clampi(int(d.get("volume", 100)), 0, 100)  # 旧格式默认满音量
	for p in d.get("touch_points", []):  # 旧格式无此字段
		if p is Array and p.size() >= 2:
			m.touch_points.append(Vector2(float(p[0]), float(p[1])))
	return m
