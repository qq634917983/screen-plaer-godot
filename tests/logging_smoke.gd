extends SceneTree
const Writer = preload("res://scripts/async_log_writer.gd")
var failures := 0
var test_root := ""

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func records(directory: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for name: String in DirAccess.get_files_at(directory):
		if not name.ends_with(".jsonl"):
			continue
		var file := FileAccess.open(directory.path_join(name), FileAccess.READ)
		while file.get_position() < file.get_length():
			var line := file.get_line()
			var value: Variant = JSON.parse_string(line)
			if value is Dictionary:
				result.append(value)
			else:
				check(false, "Every line is valid JSON")
	return result

func produce(writer: RefCounted, count: int, producer: int) -> void:
	for i in count:
		writer.write(Writer.Level.INFO, "concurrency", "event", {"producer": producer, "index": i})

func run() -> void:
	test_root = OS.get_cache_dir().path_join("screenplayer-log-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var writer := Writer.new()
	check(writer.start(test_root, Writer.Level.INFO, 8192, 8 * 1024 * 1024) == OK, "Writer thread starts")
	writer.write(Writer.Level.DEBUG, "test", "filtered")
	var fields := {"text": "中文\nline\t\"quote\"", "url": "https://example.com/video?token=hidden\"end", "password": "sensitive"}
	writer.write(Writer.Level.INFO, "test", "snapshot", fields)
	fields["text"] = "changed later"
	var workers: Array[Thread] = []
	var start := Time.get_ticks_usec()
	for index in 4:
		var thread := Thread.new()
		thread.start(produce.bind(writer, 1000, index))
		workers.append(thread)
	for thread: Thread in workers:
		thread.wait_to_finish()
	var enqueue_usec := Time.get_ticks_usec() - start
	writer.write(Writer.Level.ERROR, "test", "shutdown_tail")
	writer.stop()
	check(writer.start(test_root) == ERR_ALREADY_IN_USE, "A stopped writer cannot accidentally restart with stale state")
	var data := records(writer.stats()["directory"])
	check(data.size() == 4002, "Concurrent producers + shutdown drain lose no accepted events")
	var sequence := 0
	var snapshot_ok := false
	var tail_ok := false
	var filtered := false
	for record: Dictionary in data:
		if int(record["seq"]) <= sequence:
			check(false, "Sequence order")
		sequence = int(record["seq"])
		filtered = filtered or record["event"] == "filtered"
		tail_ok = tail_ok or record["event"] == "shutdown_tail"
		if record["event"] == "snapshot":
			snapshot_ok = record["fields"]["text"] == "中文\nline\t\"quote\"" and record["fields"]["password"] == "[redacted]" and not str(record["fields"]["url"]).contains("hidden")
	check(snapshot_ok, "Snapshot, escaping, and sensitive-field/URL redaction")
	check(tail_ok and not filtered, "Level filter and final shutdown event")
	print("BENCH four_producers=4000 enqueue_us=", enqueue_usec, " average_us=", enqueue_usec / 4000.0)

	var benchmark := Writer.new()
	benchmark.start(test_root, Writer.Level.INFO, 8192, 8 * 1024 * 1024)
	var durations: Array[int] = []
	for i in 4000:
		var tick := Time.get_ticks_usec()
		benchmark.write(Writer.Level.INFO, "benchmark", "single_producer", {"i": i})
		durations.append(Time.get_ticks_usec() - tick)
	durations.sort()
	var filter_start := Time.get_ticks_usec()
	for i in 4000:
		benchmark.write(Writer.Level.DEBUG, "benchmark", "filtered")
	var filtered_usec := Time.get_ticks_usec() - filter_start
	benchmark.stop()
	check(benchmark.stats()["dropped"] == 0, "Single-producer benchmark loses no events")
	print("BENCH single_producer=4000 median_us=", durations[2000], " p95_us=", durations[3800],
		" p99_us=", durations[3960], " filtered_average_us=", filtered_usec / 4000.0)

	var overflow := Writer.new()
	overflow.start(test_root, Writer.Level.DEBUG, 8)
	for i in 8:
		overflow.write(Writer.Level.INFO, "test", "normal", {"i": i})
	overflow.write(Writer.Level.ERROR, "test", "reserved_error")
	overflow.stop()
	var overflow_data := records(overflow.stats()["directory"])
	var high := false
	var loss := false
	for record: Dictionary in overflow_data:
		high = high or record["event"] == "reserved_error"
		loss = loss or record["event"] == "queue_overflow"
	check(overflow.stats()["dropped"] >= 1 and high and loss, "Bounded queue reserves error capacity and reports overload")

	var rotating := Writer.new()
	rotating.start(test_root, Writer.Level.INFO, 4096, 4096, 2)
	for i in 300:
		rotating.write(Writer.Level.INFO, "test", "rotation", {"i": i, "padding": "x".repeat(200)})
	rotating.stop()
	var directory: String = rotating.stats()["directory"]
	var names := DirAccess.get_files_at(directory)
	check(names.size() == 3, "Rotation retains current file plus two backups")
	var size_ok := true
	for name: String in names:
		var file := FileAccess.open(directory.path_join(name), FileAccess.READ)
		size_ok = size_ok and file.get_length() <= 4096
	check(size_ok and not records(directory).is_empty(), "Rotated files respect size and remain parseable")

	var blocker := test_root.path_join("not-a-directory")
	FileAccess.open(blocker, FileAccess.WRITE).close()
	var broken := Writer.new()
	broken.start(blocker.path_join("logs"))
	broken.write(Writer.Level.ERROR, "test", "disk_unavailable")
	broken.stop()
	check(not str(broken.stats()["io_error"]).is_empty() and not broken.stats()["accepting"], "Unwritable destination disables writer without blocking caller")

	# Only inactive session directories may be pruned; unrelated files are untouched.
	var retention_root := test_root.path_join("retention")
	for i in 4:
		var stale := retention_root.path_join("screenplayer_100000000000%d_2147483000_%d" % [i, i])
		DirAccess.make_dir_recursive_absolute(stale)
		FileAccess.open(stale.path_join("events.jsonl"), FileAccess.WRITE).close()
	var retained := Writer.new()
	retained.start(retention_root, Writer.Level.INFO, 8, 4096, 2, 2)
	retained.write(Writer.Level.INFO, "test", "retention")
	retained.stop()
	check(DirAccess.get_directories_at(retention_root).size() == 2, "Retention prunes old inactive sessions")

	push_warning("screenplayer-test-engine-capture")
	var app_log := root.get_node("LogService")
	app_log._writer.flush_async()
	await create_timer(0.5).timeout
	var engine_seen := false
	for record: Dictionary in records(app_log.stats()["directory"]):
		engine_seen = engine_seen or (record["component"] == "engine" and str(record["fields"].get("message", "")).contains("screenplayer-test-engine-capture"))
	check(engine_seen, "Official Logger captures engine warnings with source location")
	print("LOGGING SMOKE failures=", failures, " test_root=", test_root)
	quit(0 if failures == 0 else 1)
