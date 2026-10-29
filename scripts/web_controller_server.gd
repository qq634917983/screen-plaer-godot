extends Node
## Small, single-request HTTP server for the built-in LAN controller.
## File browsing and API authorization are delegated to the owning app.
var _listener := TCPServer.new()
var _clients: Array[Dictionary] = []
var _handler: Callable
var _upload_authorizer: Callable
var _port := 8765
var _upload_dir := "user://web_uploads"
const MAX_CLIENTS := 48
const MAX_JSON_BODY := 1024 * 1024
const MAX_UPLOAD_BYTES := 2 * 1024 * 1024 * 1024

func start_server(port: int, handler: Callable) -> Error:
	if _listener.is_listening():
		stop_server()
	_port = port
	_handler = handler
	var err := _listener.listen(_port, "*")
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_upload_dir))
	set_process(true)
	AppLog.info("web", "server_started", {"port": _port})
	return OK

func stop_server() -> void:
	for client in _clients:
		_close_client(client)
	_clients.clear()
	_listener.stop()
	set_process(false)
	AppLog.info("web", "server_stopped", {"port": _port})

func set_upload_authorizer(callback: Callable) -> void:
	_upload_authorizer = callback

func is_running() -> bool:
	return _listener.is_listening()

func _process(_delta: float) -> void:
	if not _listener.is_listening():
		return
	var accepted := 0
	while _listener.is_connection_available() and _clients.size() < MAX_CLIENTS and accepted < 8:
		var peer := _listener.take_connection()
		if peer == null:
			break
		_clients.append({"peer": peer, "buffer": PackedByteArray(), "headers_done": false,
			"request": {}, "body": PackedByteArray(), "received": 0, "upload": null,
			"upload_path": "", "started": Time.get_ticks_msec()})
		accepted += 1
	var i := _clients.size() - 1
	while i >= 0:
		var client := _clients[i]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_close_client(client)
			_clients.remove_at(i)
			i -= 1
			continue
		if Time.get_ticks_msec() - int(client.started) > 120000:
			_send_error_and_close(client, 408, "Request timeout")
			_clients.remove_at(i)
			i -= 1
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var result := peer.get_data(available)
			if result[0] != OK:
				_close_client(client)
				_clients.remove_at(i)
				i -= 1
				continue
			var chunk: PackedByteArray = result[1]
			client.started = Time.get_ticks_msec()
			if not bool(client.headers_done):
				var buffer: PackedByteArray = client.buffer
				buffer.append_array(chunk)
				client.buffer = buffer
				var split_at := _find_header_end(buffer)
				if (split_at < 0 and buffer.size() > 16384) or split_at > 16384:
					_send_error_and_close(client, 413, "Request headers too large")
					_clients.remove_at(i)
					i -= 1
					continue
				if split_at >= 0:
					var header_bytes := buffer.slice(0, split_at)
					var remainder := buffer.slice(split_at + 4)
					var parsed := _parse_headers(header_bytes)
					if parsed.is_empty():
						_send_error_and_close(client, 400, "Bad request")
						_clients.remove_at(i)
						i -= 1
						continue
					client.request = parsed
					client.headers_done = true
					client.buffer = PackedByteArray()
					var length := int(parsed.headers.get("content-length", "0"))
					if str(parsed.headers.get("transfer-encoding", "")).to_lower().contains("chunked") or (str(parsed.method) == "POST" and not parsed.headers.has("content-length")):
						_send_error_and_close(client, 400, "Content-Length required; chunked encoding is not supported")
						_clients.remove_at(i)
						i -= 1
						continue
					if length < 0 or (length > MAX_JSON_BODY and not _is_upload(parsed)) or length > MAX_UPLOAD_BYTES:
						_send_error_and_close(client, 413, "Request body too large")
						_clients.remove_at(i)
						i -= 1
						continue
					if _is_upload(parsed):
						if not _upload_authorizer.is_valid() or not bool(_upload_authorizer.call(parsed)):
							_send_error_and_close(client, 401, "Unauthorized")
							_clients.remove_at(i)
							i -= 1
							continue
						var upload_name := "upload_%s_%s.part" % [str(Time.get_ticks_usec()), str(randi())]
						var upload_path := _upload_dir.path_join(upload_name)
						client.upload_path = upload_path
						client.upload = FileAccess.open(upload_path, FileAccess.WRITE)
						if client.upload == null:
							_send_error_and_close(client, 500, "Unable to create upload")
							_clients.remove_at(i)
							i -= 1
							continue
					if not remainder.is_empty():
						_consume_body(client, remainder, length)
			else:
				_consume_body(client, chunk, int(client.request.headers.get("content-length", "0")))
		if bool(client.headers_done):
			var length := int(client.request.headers.get("content-length", "0"))
			if int(client.received) >= length:
				_finish_request(client)
				_clients.remove_at(i)
		i -= 1

func _consume_body(client: Dictionary, chunk: PackedByteArray, expected: int) -> void:
	var remaining := maxi(expected - int(client.received), 0)
	var count := mini(chunk.size(), remaining)
	if count <= 0:
		return
	if _is_upload(client.request):
		var file: FileAccess = client.upload
		file.store_buffer(chunk.slice(0, count))
	else:
		var body: PackedByteArray = client.body
		body.append_array(chunk.slice(0, count))
		client.body = body
	client.received = int(client.received) + count

func _finish_request(client: Dictionary) -> void:
	if client.upload != null:
		var file: FileAccess = client.upload
		file.close()
		client.upload = null
	client.request.body = client.body
	if not str(client.upload_path).is_empty():
		client.request.upload_path = str(client.upload_path)
	var response: Dictionary
	if _handler.is_valid():
		response = _handler.call(client.request)
	else:
		response = _response(503, "Service unavailable")
	_send_response(client.peer, response)
	_close_client(client)

func _is_upload(request: Dictionary) -> bool:
	return str(request.get("method", "")) == "POST" and str(request.get("path", "")) == "/api/media/upload"

func _find_header_end(bytes: PackedByteArray) -> int:
	if bytes.size() < 4:
		return -1
	for i in range(bytes.size() - 3):
		if bytes[i] == 13 and bytes[i + 1] == 10 and bytes[i + 2] == 13 and bytes[i + 3] == 10:
			return i
	return -1

func _parse_headers(data: PackedByteArray) -> Dictionary:
	var lines := data.get_string_from_utf8().split("\r\n")
	if lines.is_empty():
		return {}
	var request_line := lines[0].split(" ", false, 2)
	if request_line.size() != 3:
		return {}
	var target := str(request_line[1])
	var query := {}
	var question := target.find("?")
	if question >= 0:
		for pair in target.substr(question + 1).split("&"):
			var equal := pair.find("=")
			var k := pair.substr(0, equal) if equal >= 0 else pair
			var v := pair.substr(equal + 1) if equal >= 0 else ""
			query[k.uri_decode()] = v.uri_decode()
		target = target.substr(0, question)
	var headers := {}
	for line in lines.slice(1):
		var colon := line.find(":")
		if colon > 0:
			headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	return {"method": str(request_line[0]).to_upper(), "target": target.uri_decode(), "path": target.uri_decode(), "query": query, "headers": headers, "body": PackedByteArray()}

func _send_response(peer: StreamPeerTCP, response: Dictionary) -> void:
	var status := int(response.get("status", 200))
	var body = response.get("body", "")
	var bytes: PackedByteArray
	if body is PackedByteArray:
		bytes = body
	else:
		bytes = str(body).to_utf8_buffer()
	var headers: Dictionary = response.get("headers", {})
	if not headers.has("Content-Type") and not headers.has("content-type"):
		headers["Content-Type"] = "application/json; charset=utf-8"
	headers["Content-Length"] = str(bytes.size())
	headers["Connection"] = "close"
	headers["Cache-Control"] = "no-store"
	var lines := ["HTTP/1.1 %d %s" % [status, _status_text(status)]]
	for key in headers:
		lines.append("%s: %s" % [str(key), str(headers[key])])
	lines.append("")
	lines.append("")
	var head := "\r\n".join(PackedStringArray(lines)).to_utf8_buffer()
	peer.put_data(head)
	if not bytes.is_empty():
		peer.put_data(bytes)

func _send_error_and_close(client: Dictionary, status: int, message: String) -> void:
	_send_response(client.peer, _response(status, message))
	_close_client(client)

func _close_client(client: Dictionary) -> void:
	if client.get("upload") != null:
		var file: FileAccess = client.upload
		file.close()
	var upload_path := str(client.get("upload_path", ""))
	if not upload_path.is_empty() and FileAccess.file_exists(upload_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(upload_path))
	var peer: StreamPeerTCP = client.peer
	if peer != null:
		peer.disconnect_from_host()

func _response(status: int, body: Variant, content_type := "application/json; charset=utf-8") -> Dictionary:
	return {"status": status, "headers": {"Content-Type": content_type}, "body": body}

func _status_text(status: int) -> String:
	return {200:"OK",201:"Created",204:"No Content",400:"Bad Request",401:"Unauthorized",403:"Forbidden",404:"Not Found",405:"Method Not Allowed",408:"Request Timeout",413:"Payload Too Large",500:"Internal Server Error",503:"Service Unavailable"}.get(status, "Response")
