class_name AsyncLogWriter
extends RefCounted
## Bounded producer/consumer logger. Only the writer thread touches log files.
enum Level { DEBUG, INFO, WARN, ERROR }
const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]
const MAX_STRING := 2048

var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _thread := Thread.new()
var _queue: Array[Dictionary] = []
var _started_once := false
var _accepting := false
var _stopping := false
var _wake_pending := false
var _level := Level.INFO
var _sequence := 0
var _dropped := 0
var _written := 0
var _io_error := ""
var _writer_id := -1
var _capacity := 4096
var _reserve := 128
var _max_bytes := 5 * 1024 * 1024
var _backups := 4
var _sessions := 10
var _root := ""
var _session := ""
var _started_usec := 0
var _url_query := RegEx.new()
var _home_dir := ""

func start(root_dir: String, level: int = Level.INFO, capacity := 4096,
		max_bytes := 5 * 1024 * 1024, backups := 4, sessions := 10) -> Error:
	if _started_once:
		return ERR_ALREADY_IN_USE
	_started_once = true
	_root = root_dir
	_level = clampi(level, Level.DEBUG, Level.ERROR)
	_capacity = maxi(capacity, 8)
	_reserve = mini(128, maxi(1, _capacity / 8))
	_max_bytes = maxi(max_bytes, 4096)
	_backups = maxi(backups, 1)
	_sessions = maxi(sessions, 1)
	_started_usec = Time.get_ticks_usec()
	_session = "screenplayer_%d_%d_%d" % [int(Time.get_unix_time_from_system() * 1000), OS.get_process_id(), _started_usec]
	_accepting = true
	var result := _thread.start(_run)
	if result != OK:
		_accepting = false
		_io_error = "thread_start: " + error_string(result)
	return result

func set_level(level: int) -> void:
	_mutex.lock()
	_level = clampi(level, Level.DEBUG, Level.ERROR)
	_mutex.unlock()

func is_enabled(level: int) -> bool:
	_mutex.lock()
	var enabled := _accepting and level >= _level and OS.get_thread_caller_id() != _writer_id
	_mutex.unlock()
	return enabled

func write(level: int, component: String, event: String, fields: Dictionary = {}) -> void:
	# Never recursively capture failures originating in the file writer itself.
	if not is_enabled(level):
		return
	# Snapshot caller-owned mutable data; never send Objects/Nodes across threads.
	var context: Dictionary = _snapshot(fields, 0, [64, 4096])
	_mutex.lock()
	if not _accepting:
		_mutex.unlock()
		return
	var limit := _capacity if level >= Level.WARN else _capacity - _reserve
	if _queue.size() >= limit:
		_dropped += 1
		_mutex.unlock()
		return
	_sequence += 1
	_queue.append({"unix_ms": int(Time.get_unix_time_from_system() * 1000),
		"elapsed_us": Time.get_ticks_usec() - _started_usec, "seq": _sequence,
		"level": LEVEL_NAMES[clampi(level, Level.DEBUG, Level.ERROR)],
		"component": component.left(128), "event": event.left(256), "fields": context})
	var notify := not _wake_pending and (_queue.size() >= 64 or level >= Level.WARN)
	if notify:
		_wake_pending = true
	_mutex.unlock()
	if notify:
		_wake.post()

func flush_async() -> void:
	_mutex.lock()
	var notify := _accepting and not _wake_pending and (not _queue.is_empty() or _dropped > 0)
	if notify:
		_wake_pending = true
	_mutex.unlock()
	if notify:
		_wake.post()

func stop() -> void:
	if not _thread.is_started():
		return
	_mutex.lock()
	_accepting = false
	_stopping = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()

func stats() -> Dictionary:
	_mutex.lock()
	var result := {"queued": _queue.size(), "dropped": _dropped, "written": _written,
		"io_error": _io_error, "accepting": _accepting, "level": _level,
		"session": _session, "directory": _root.path_join(_session)}
	_mutex.unlock()
	return result

func _snapshot(value: Variant, depth: int, budget: Array) -> Variant:
	budget[0] -= 1
	if depth > 3 or budget[0] <= 0:
		return "[depth limit]"
	if value is String or value is StringName:
		var text := str(value).left(mini(MAX_STRING, int(budget[1])))
		budget[1] -= text.length()
		return text
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if result.size() >= 24 or budget[0] <= 0:
				break
			var name := str(key).left(128)
			if name.to_lower() in ["password", "token", "access_token", "authorization", "cookie", "secret", "api_key"]:
				result[name] = "[redacted]"
			else:
				result[name] = _snapshot(value[key], depth + 1, budget)
		return result
	if value is Array or value is PackedStringArray:
		var result := []
		for item: Variant in value:
			if result.size() >= 16 or budget[0] <= 0:
				break
			result.append(_snapshot(item, depth + 1, budget))
		return result
	if value == null or value is bool or value is int or value is float:
		return value
	return "[unsupported value]"

func _fail(message: String) -> void:
	_mutex.lock()
	_io_error = message
	_accepting = false
	_dropped += _queue.size()
	_queue.clear()
	_mutex.unlock()

func _run() -> void:
	_mutex.lock()
	_writer_id = OS.get_thread_caller_id()
	_mutex.unlock()
	_home_dir = OS.get_environment("HOME" if OS.get_name() == "macOS" else "USERPROFILE")
	_url_query.compile("(https?://[^\\s\\\"?#]+)[?#][^\\s\\\"]*")
	var directory := _root.path_join(_session)
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		_fail("mkdir: " + error_string(err))
		return
	_prune_sessions()
	var path := directory.path_join("events.jsonl")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("open: " + error_string(FileAccess.get_open_error()))
		return
	var reported_drops := 0
	while true:
		_wake.wait()
		_mutex.lock()
		var batch := _queue
		_queue = []
		_wake_pending = false
		var stopping := _stopping
		var drops := _dropped
		_mutex.unlock()
		if drops > reported_drops:
			batch.append({"unix_ms": int(Time.get_unix_time_from_system() * 1000),
				"level": "WARN", "component": "logging", "event": "queue_overflow",
				"fields": {"dropped_total": drops, "dropped_since_last": drops - reported_drops}})
			reported_drops = drops
		var written := 0
		for record: Dictionary in batch:
			record["session"] = _session
			record["pid"] = OS.get_process_id()
			var unix_ms: int = record["unix_ms"]
			record["timestamp"] = Time.get_datetime_string_from_unix_time(unix_ms / 1000) + ".%03dZ" % (unix_ms % 1000)
			var line := JSON.stringify(_redact(record))
			var bytes := (line + "\n").to_utf8_buffer()
			if bytes.size() > mini(_max_bytes, 64 * 1024):
				record["fields"] = {"payload_truncated": true, "original_bytes": bytes.size()}
				bytes = (JSON.stringify(record) + "\n").to_utf8_buffer()
			if file.get_position() > 0 and file.get_position() + bytes.size() > _max_bytes:
				file.close()
				if not _rotate(path):
					_fail("rotate failed")
					return
				file = FileAccess.open(path, FileAccess.WRITE)
				if file == null:
					_fail("reopen: " + error_string(FileAccess.get_open_error()))
					return
			file.store_buffer(bytes)
			if file.get_error() != OK:
				_fail("write: " + error_string(file.get_error()))
				file.close()
				return
			written += 1
		file.flush()
		if file.get_error() != OK:
			_fail("flush: " + error_string(file.get_error()))
			file.close()
			return
		_mutex.lock()
		_written += written
		_mutex.unlock()
		if stopping:
			break
	file.close()

func _redact(value: Variant) -> Variant:
	if value is String:
		var text: String = value
		if not _home_dir.is_empty():
			text = text.replace(_home_dir, "~")
		return _url_query.sub(text, "$1?[redacted]", true)
	if value is Dictionary:
		for key: Variant in value:
			value[key] = _redact(value[key])
	elif value is Array:
		for i in value.size():
			value[i] = _redact(value[i])
	return value


func _rotate(path: String) -> bool:
	var oldest := path.get_base_dir().path_join("events.%d.jsonl" % _backups)
	if FileAccess.file_exists(oldest) and DirAccess.remove_absolute(oldest) != OK:
		return false
	for index in range(_backups - 1, 0, -1):
		var source := path.get_base_dir().path_join("events.%d.jsonl" % index)
		if FileAccess.file_exists(source):
			if DirAccess.rename_absolute(source, path.get_base_dir().path_join("events.%d.jsonl" % (index + 1))) != OK:
				return false
	return DirAccess.rename_absolute(path, path.get_base_dir().path_join("events.1.jsonl")) == OK

func _prune_sessions() -> void:
	var directories: Array[String] = []
	for name: String in DirAccess.get_directories_at(_root):
		var parts := name.split("_")
		if parts.size() == 4 and parts[0] == "screenplayer" and parts[1].is_valid_int() and parts[2].is_valid_int() and parts[3].is_valid_int():
			directories.append(name)
	directories.sort()
	var remove_count := maxi(0, directories.size() - _sessions)
	if remove_count == 0:
		return
	# Godot's is_process_running only reliably tracks its own child processes.
	# Enumerate once on the worker instead; conservatively skip cleanup on failure.
	var output: Array = []
	var live := {}
	var result := -1
	if OS.get_name() == "macOS":
		result = OS.execute("/bin/ps", ["-axo", "pid="], output)
		if result == 0:
			for line: String in str(output[0]).split("\n"):
				if line.strip_edges().is_valid_int():
					live[int(line.strip_edges())] = true
	elif OS.get_name() == "Windows":
		result = OS.execute("tasklist.exe", ["/FO", "CSV", "/NH"], output)
		if result == 0:
			var pid_pattern := RegEx.new()
			pid_pattern.compile('^"[^"]*","([0-9]+)"')
			for line: String in str(output[0]).split("\n"):
				var matched := pid_pattern.search(line)
				if matched != null:
					live[int(matched.get_string(1))] = true
	if result != 0 or live.is_empty():
		return
	for name: String in directories:
		if remove_count == 0:
			break
		if name == _session or live.has(int(name.split("_")[2])):
			continue
		var directory := _root.path_join(name)
		for filename: String in DirAccess.get_files_at(directory):
			if filename == "events.jsonl" or (filename.begins_with("events.") and filename.ends_with(".jsonl") and filename.trim_prefix("events.").trim_suffix(".jsonl").is_valid_int()):
				DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
		remove_count -= 1
