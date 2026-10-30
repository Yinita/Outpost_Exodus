extends RefCounted
## Quiet, schema-independent JSON storage with bounded reads and atomic renames.
## The caller owns game/schema validation. No automatic backup recovery occurs.

const MAX_SAVE_BYTES: int = 8 * 1024 * 1024

var _temporary_serial: int = 0


func read(path: String) -> Dictionary:
	var result: Dictionary = _read_raw(path)
	return {
		"ok": bool(result["ok"]),
		"data": Dictionary(result["data"]),
		"error": String(result["error"])
	}


func write(path: String, data: Dictionary, validator: Callable) -> Error:
	# Validation happens before opening or creating any filesystem object.
	if not validator.is_valid():
		return ERR_INVALID_PARAMETER
	if not _validate(data, validator):
		return ERR_INVALID_DATA
	var serialized: String = JSON.stringify(data, "\t", true, true)
	var new_bytes: PackedByteArray = serialized.to_utf8_buffer()
	if new_bytes.size() > MAX_SAVE_BYTES:
		return ERR_INVALID_DATA
	var encoded: Dictionary = _decode(new_bytes)
	if not bool(encoded["ok"]) or not _validate(encoded["data"], validator):
		return ERR_INVALID_DATA
	var primary: String = _absolute_path(path)
	if primary.is_empty():
		return ERR_FILE_BAD_PATH
	var backup: String = primary + ".bak"
	# A directory is never a replaceable save file. Refuse it before staging.
	if DirAccess.dir_exists_absolute(primary):
		return ERR_FILE_CANT_WRITE
	var old_primary: Dictionary = _read_raw(primary)
	var primary_valid: bool = bool(old_primary["ok"]) and _validate(old_primary["data"], validator)
	var old_backup: Dictionary = _read_raw(backup)
	var backup_valid: bool = bool(old_backup["ok"]) and _validate(old_backup["data"], validator)
	var replace_backup: bool = primary_valid or not backup_valid
	var backup_bytes: PackedByteArray = PackedByteArray()
	if primary_valid:
		# Preserve the exact old bytes, including whitespace and UTF-8 encoding.
		backup_bytes = old_primary["raw"]
	elif not backup_valid:
		# First save, or no trustworthy recovery file: create a valid first backup.
		backup_bytes = new_bytes
	# If primary is corrupt and backup is valid, never touch that backup.
	if replace_backup and DirAccess.dir_exists_absolute(backup):
		return ERR_FILE_CANT_WRITE
	var owned_temps: Array[String] = []
	var new_primary: String = _temporary_path(primary, "new")
	if new_primary.is_empty():
		return ERR_CANT_CREATE
	var result: Error = _stage(new_primary, new_bytes, owned_temps)
	if result != OK:
		_cleanup(owned_temps)
		return result
	var new_backup: String = ""
	var rollback_backup: String = ""
	if replace_backup:
		new_backup = _temporary_path(backup, "new")
		if new_backup.is_empty():
			_cleanup(owned_temps)
			return ERR_CANT_CREATE
		result = _stage(new_backup, backup_bytes, owned_temps)
		if result != OK:
			_cleanup(owned_temps)
			return result
		if backup_valid:
			rollback_backup = _temporary_path(backup, "previous")
			if rollback_backup.is_empty():
				_cleanup(owned_temps)
				return ERR_CANT_CREATE
			result = _stage(rollback_backup, old_backup["raw"], owned_temps)
			if result != OK:
				_cleanup(owned_temps)
				return result
		# Commit recovery data first: a crash never creates an empty-primary gap,
		# and the next rename is an atomic replacement of the primary path.
		result = DirAccess.rename_absolute(new_backup, backup)
		if result != OK:
			_cleanup(owned_temps)
			return result
	result = DirAccess.rename_absolute(new_primary, primary)
	if result != OK:
		if not rollback_backup.is_empty():
			# Normal replacement failures restore the previous good backup too.
			# If the OS also refuses rollback, the currently installed backup is
			# still validated recovery data, never a partial/corrupt primary copy.
			DirAccess.rename_absolute(rollback_backup, backup)
		_cleanup(owned_temps)
		return result
	_cleanup(owned_temps)
	return OK


func _validate(data: Dictionary, validator: Callable) -> bool:
	var result: Variant = validator.call(data)
	return result is bool and bool(result)


func _absolute_path(path: String) -> String:
	if path.is_empty() or path.get_file().is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _read_raw(path: String) -> Dictionary:
	var absolute: String = _absolute_path(path)
	if absolute.is_empty():
		return _failure("存档路径无效。")
	var file: FileAccess = FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return _failure("无法打开存档文件（错误%d）。" % int(FileAccess.get_open_error()))
	var length: int = file.get_length()
	if length > MAX_SAVE_BYTES:
		file.close()
		return _failure("存档超过8 MiB大小限制。")
	var raw: PackedByteArray = file.get_buffer(length)
	var error: Error = file.get_error()
	file.close()
	if raw.size() != length or (error != OK and error != ERR_FILE_EOF):
		return _failure("存档文件未能完整读取。")
	return _decode(raw)


func _decode(raw: PackedByteArray) -> Dictionary:
	if raw.size() > MAX_SAVE_BYTES:
		return _failure("存档超过8 MiB大小限制。")
	# Validate before get_string_from_utf8(), whose decoder can print warnings
	# for malformed input. Broken user files should remain ordinary UI errors.
	if not _valid_utf8(raw):
		return _failure("存档不是有效的UTF-8文本。")
	var text: String = raw.get_string_from_utf8()
	if not text.is_empty() and text.unicode_at(0) == 0xfeff:
		text = text.substr(1)
	var parser: JSON = JSON.new()
	var parsed: Error = parser.parse(text)
	if parsed != OK:
		return _failure("存档JSON格式错误（第%d行）。" % int(parser.get_error_line()))
	var value: Variant = parser.data
	if not value is Dictionary:
		return _failure("存档顶层必须是JSON对象。")
	return {"ok": true, "data": value, "error": "", "raw": raw}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message, "raw": PackedByteArray()}


func _temporary_path(destination: String, role: String) -> String:
	for attempt: int in range(32):
		_temporary_serial += 1
		var candidate: String = "%s.tmp-%d-%d-%d-%s" % [destination, OS.get_process_id(), Time.get_ticks_usec(), _temporary_serial, role]
		if not FileAccess.file_exists(candidate) and not DirAccess.dir_exists_absolute(candidate):
			return candidate
	return ""


func _stage(path: String, bytes: PackedByteArray, owned_temps: Array[String]) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	owned_temps.append(path)
	file.store_buffer(bytes)
	var error: Error = file.get_error()
	if error == OK:
		file.flush()
		error = file.get_error()
	file.close()
	if error != OK:
		return error
	# Verify staged bytes before either known-good destination can be replaced.
	var check: FileAccess = FileAccess.open(path, FileAccess.READ)
	if check == null:
		return FileAccess.get_open_error()
	if check.get_length() != bytes.size():
		check.close()
		return ERR_FILE_CANT_WRITE
	var actual: PackedByteArray = check.get_buffer(bytes.size())
	error = check.get_error()
	check.close()
	if actual != bytes or (error != OK and error != ERR_FILE_EOF):
		return ERR_FILE_CANT_WRITE
	return OK


func _cleanup(owned_temps: Array[String]) -> void:
	for path: String in owned_temps:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _valid_utf8(bytes: PackedByteArray) -> bool:
	var cursor: int = 0
	while cursor < bytes.size():
		var first: int = bytes[cursor]
		if first <= 0x7f:
			cursor += 1
			continue
		var continuation: int = 0
		if first >= 0xc2 and first <= 0xdf:
			continuation = 1
		elif first >= 0xe0 and first <= 0xef:
			continuation = 2
		elif first >= 0xf0 and first <= 0xf4:
			continuation = 3
		else:
			return false
		if cursor + continuation >= bytes.size():
			return false
		var second: int = bytes[cursor + 1]
		if (first == 0xe0 and second < 0xa0) or (first == 0xed and second >= 0xa0) or (first == 0xf0 and second < 0x90) or (first == 0xf4 and second > 0x8f):
			return false
		for offset: int in range(1, continuation + 1):
			var next: int = bytes[cursor + offset]
			if next < 0x80 or next > 0xbf:
				return false
		cursor += continuation + 1
	return true
