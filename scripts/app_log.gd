class_name AppLog
extends Node
## Official Godot Logger adapter plus asynchronous structured application events.
const Writer = preload("res://scripts/async_log_writer.gd")
const LOG_ROOT := "user://logs"
static var _writer := Writer.new()
var _sink: EngineSink
var _flush_elapsed := 0.0
var _heartbeat_elapsed := 0.0

class EngineSink extends Logger:
	var writer: RefCounted
	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		writer.write(Writer.Level.WARN if error_type == Logger.ERROR_TYPE_WARNING else Writer.Level.ERROR,
			"engine", "runtime_error", {"function": function, "file": file,
			"line": line, "code": code, "message": code if rationale.is_empty() else rationale, "type": error_type})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var level := int(ProjectStore.get_setting("logging", "level", Writer.Level.INFO))
	var result := _writer.start(ProjectSettings.globalize_path(LOG_ROOT), level)
	if result != OK:
		printerr("Log writer unavailable: ", error_string(result))
		return
	_sink = EngineSink.new()
	_sink.writer = _writer
	OS.add_logger(_sink)
	info("app", "session_started", {"version": ProjectSettings.get_setting("application/config/version", ""),
		"godot": Engine.get_version_info().get("string", ""), "os": OS.get_name(),
		"architecture": Engine.get_architecture_name(), "debug_build": OS.is_debug_build(),
		"level": Writer.LEVEL_NAMES[clampi(level, 0, 3)]})

func _process(delta: float) -> void:
	_flush_elapsed += delta
	_heartbeat_elapsed += delta
	if _flush_elapsed >= 0.5:
		_flush_elapsed = 0.0
		_writer.flush_async()
	if _heartbeat_elapsed >= 30.0:
		_heartbeat_elapsed = 0.0
		info("app", "health", {"fps": Engine.get_frames_per_second(),
			"memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"queue": _writer.stats()})

func _exit_tree() -> void:
	info("app", "session_stopped")
	if _sink != null:
		OS.remove_logger(_sink)
		_sink = null
	_writer.stop()

static func debug(component: String, event: String, fields: Dictionary = {}) -> void:
	_writer.write(Writer.Level.DEBUG, component, event, fields)

static func info(component: String, event: String, fields: Dictionary = {}) -> void:
	_writer.write(Writer.Level.INFO, component, event, fields)

static func warn(component: String, event: String, fields: Dictionary = {}) -> void:
	_writer.write(Writer.Level.WARN, component, event, fields)

static func error(component: String, event: String, fields: Dictionary = {}) -> void:
	_writer.write(Writer.Level.ERROR, component, event, fields)

static func set_level(level: int) -> void:
	_writer.set_level(level)
	_writer.write(Writer.Level.INFO, "logging", "level_changed", {"level": Writer.LEVEL_NAMES[clampi(level, 0, 3)]})

static func stats() -> Dictionary:
	return _writer.stats()

static func open_folder() -> void:
	var result := OS.shell_open(ProjectSettings.globalize_path(LOG_ROOT))
	if result != OK:
		warn("logging", "open_folder_failed", {"error": error_string(result)})

static func media_ref(path: String) -> Dictionary:
	# Correlate a resource without leaking full filesystem paths or URL credentials.
	return {"name": path.get_file().split("?")[0].split("#")[0], "id": path.sha256_text().left(12)}
