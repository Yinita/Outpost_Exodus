extends SceneTree
## File-layer tests: every write is isolated below res://work/save-store-test/.
## Run: Godot --headless --path . --script res://tests/test_save_store.gd

const Store = preload("res://scripts/campaign_save_store.gd")
const TEST_ROOT: String = "res://work/save-store-test"
const FOREIGN_TEMP: String = "foreign.tmp-owned-by-another-writer"

class FailSecondStage:
	extends "res://scripts/campaign_save_store.gd"
	var stage_count: int = 0

	func _stage(path: String, bytes: PackedByteArray, owned_temps: Array[String]) -> Error:
		stage_count += 1
		var result: Error = super._stage(path, bytes, owned_temps)
		return ERR_FILE_CANT_WRITE if result == OK and stage_count == 2 else result

class BlockLatePrimary:
	extends "res://scripts/campaign_save_store.gd"
	var stage_count: int = 0
	var primary_path: String = ""
	var preserved_path: String = ""
	var injection_ok: bool = false

	func _stage(path: String, bytes: PackedByteArray, owned_temps: Array[String]) -> Error:
		stage_count += 1
		var result: Error = super._stage(path, bytes, owned_temps)
		if result != OK or stage_count != 3:
			return result
		# Emulate another filesystem actor replacing the target after preflight.
		# The original bytes are moved intact within this isolated test directory.
		if DirAccess.rename_absolute(primary_path, preserved_path) != OK:
			return ERR_CANT_CREATE
		if DirAccess.make_dir_absolute(primary_path) != OK:
			return ERR_CANT_CREATE
		var marker: FileAccess = FileAccess.open(primary_path.path_join("keep.txt"), FileAccess.WRITE)
		if marker == null:
			return ERR_CANT_CREATE
		marker.store_string("late nonreplaceable destination")
		marker.flush()
		marker.close()
		injection_ok = true
		return OK

var checks: int = 0
var failures: Array[String] = []
var directory: String = ""
var store: Variant
var validation_calls: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var store_script: Script = Store
	if not store_script.can_instantiate():
		printerr("Save-store script did not compile")
		quit(1)
		return
	var allowed: String = ProjectSettings.globalize_path(TEST_ROOT).simplify_path()
	var project: String = ProjectSettings.globalize_path("res://").simplify_path()
	if not allowed.begins_with(project + "/work/save-store-test"):
		printerr("Refusing save-store tests outside the project-local isolation directory")
		quit(2)
		return
	directory = allowed.path_join("run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		printerr("Cannot create isolated save-store test directory")
		quit(2)
		return
	store = Store.new()
	_put_text(directory.path_join(FOREIGN_TEMP), "another writer's unfinished file")
	var cases: Array[Callable] = [
		_test_first_save_and_rotation,
		_test_corrupt_primary_preserves_backup,
		_test_rejected_validation_is_untouched,
		_test_quiet_bounded_reads,
		_test_nonreplaceable_destinations,
		_test_staging_permission_failure,
		_test_partial_stage_and_late_replace_failure,
		_test_independent_paths,
	]
	for test_case: Callable in cases:
		var previous_failures: int = failures.size()
		test_case.call()
		_assert_no_owned_temps()
		print("%s %s" % ["PASS" if previous_failures == failures.size() else "FAIL", test_case.get_method()])
	_check(_bytes(directory.path_join(FOREIGN_TEMP)).get_string_from_utf8() == "another writer's unfinished file", "cleanup never removes another writer's temporary file")
	_erase_tree(directory)
	_check(not DirAccess.dir_exists_absolute(directory), "isolated run directory can be fully cleaned")
	print("Save-store checks: %d; failures: %d" % [checks, failures.size()])
	for failure: String in failures:
		printerr(" - " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _data(generation: int) -> Dictionary:
	return {"schema": 1, "generation": generation, "payload": "峡谷补给 🚚 #%d" % generation}


func _valid(data: Dictionary) -> bool:
	validation_calls += 1
	return data.size() == 3 and _integer(data.get("schema")) and int(data["schema"]) == 1 and _integer(data.get("generation")) and int(data["generation"]) > 0 and data.get("payload") is String


func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


func _reject(_data_value: Dictionary) -> bool:
	validation_calls += 1
	return false


func _non_boolean(_data_value: Dictionary) -> String:
	return "true"


func _reject_encoded(_data_value: Dictionary) -> bool:
	validation_calls += 1
	return validation_calls == 1


func _validator() -> Callable:
	return Callable(self, "_valid")


func _put_text(path: String, text: String) -> void:
	_put_bytes(path, text.to_utf8_buffer())


func _put_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "test fixture opens only its isolated file")
	if file == null:
		return
	file.store_buffer(bytes)
	file.flush()
	_check(file.get_error() == OK, "test fixture bytes are written")
	file.close()


func _bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var result: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return result


func _generation(path: String) -> int:
	var result: Dictionary = store.read(path)
	if not bool(result["ok"]):
		return -1
	return int(Dictionary(result["data"]).get("generation", -1))


func _test_first_save_and_rotation() -> void:
	var path: String = directory.path_join("rotation.json")
	_check(store.write(path, _data(1), _validator()) == OK, "first save succeeds")
	_check(_generation(path) == 1, "first primary is readable")
	_check(_generation(path + ".bak") == 1, "first save also creates a valid backup")
	# Raw CRLF/indentation/UTF-8 content must survive backup rotation unchanged.
	var original: String = "\r\n{\r\n  \"schema\": 1, \"generation\": 1,\r\n  \"payload\": \"原始备份 🚚\"\r\n}\r\n"
	_put_text(path, original)
	_check(store.write(path, _data(2), _validator()) == OK, "second save succeeds")
	_check(_generation(path) == 2 and _generation(path + ".bak") == 1, "second save rotates the previous primary into backup")
	_check(_bytes(path + ".bak") == original.to_utf8_buffer(), "backup preserves original primary bytes, not a JSON reserialization")
	var second_primary: PackedByteArray = _bytes(path)
	_check(store.write(path, _data(3), _validator()) == OK, "third save succeeds")
	_check(_generation(path) == 3 and _generation(path + ".bak") == 2, "further saves rotate one generation rather than copying the new primary")
	_check(_bytes(path + ".bak") == second_primary, "second rotation also preserves exact old primary bytes")


func _test_corrupt_primary_preserves_backup() -> void:
	var path: String = directory.path_join("corruption.json")
	_check(store.write(path, _data(10), _validator()) == OK, "corruption fixture first save succeeds")
	_check(store.write(path, _data(11), _validator()) == OK, "corruption fixture has a distinct previous generation")
	var good_backup: PackedByteArray = _bytes(path + ".bak")
	_put_text(path, "{broken JSON")
	_check(not bool(store.read(path)["ok"]), "read reports corrupt primary without recovering automatically")
	_check(store.write(path, _data(12), _validator()) == OK, "saving after a corrupt primary can recover the primary path")
	_check(_generation(path) == 12 and _bytes(path + ".bak") == good_backup, "bad JSON primary cannot overwrite the previous good backup")
	_put_text(path, "{\"schema\":999,\"generation\":13,\"payload\":\"bad game schema\"}")
	_check(bool(store.read(path)["ok"]), "file reader leaves game-schema decisions to the caller")
	_check(store.write(path, _data(14), _validator()) == OK, "valid new data replaces a schema-invalid primary")
	_check(_bytes(path + ".bak") == good_backup, "syntactically valid but schema-invalid primary also cannot poison the backup")
	_put_text(path + ".bak", "[]")
	var old_primary: PackedByteArray = _bytes(path)
	_check(store.write(path, _data(15), _validator()) == OK, "a bad backup can be repaired from a valid old primary")
	_check(_bytes(path + ".bak") == old_primary and _generation(path + ".bak") == 14, "backup repair uses the last valid primary")
	_put_text(path, "{bad")
	_put_text(path + ".bak", "{also bad")
	_check(store.write(path, _data(16), _validator()) == OK, "no valid old files still permits a new validated save")
	_check(_generation(path) == 16 and _generation(path + ".bak") == 16, "two invalid files are replaced by a valid first recovery pair")


func _test_rejected_validation_is_untouched() -> void:
	var path: String = directory.path_join("rejected.json")
	_check(store.write(path, _data(20), _validator()) == OK, "validation fixture first save succeeds")
	_check(store.write(path, _data(21), _validator()) == OK, "validation fixture backup differs from primary")
	var primary: PackedByteArray = _bytes(path)
	var backup: PackedByteArray = _bytes(path + ".bak")
	validation_calls = 0
	_check(store.write(path, _data(22), Callable(self, "_reject")) != OK, "validator rejection fails the save")
	_check(validation_calls == 1, "new data is validated before inspecting or validating old files")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "validation rejection does not touch either original")
	_check(store.write(path, _data(22), Callable()) != OK, "invalid validator fails safely")
	_check(store.write(path, _data(22), Callable(self, "_non_boolean")) != OK, "truthy non-boolean validator results are refused")
	validation_calls = 0
	_check(store.write(path, _data(22), Callable(self, "_reject_encoded")) != OK, "encoded snapshot validation can reject before commit")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "all validation failures preserve primary and backup bytes")
	var oversized: Dictionary = _data(22)
	oversized["payload"] = "x".repeat(Store.MAX_SAVE_BYTES)
	_check(store.write(path, oversized, _validator()) != OK, "oversized writes are refused before staging")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "size rejection cannot alter known-good files")


func _test_quiet_bounded_reads() -> void:
	var missing: Dictionary = store.read(directory.path_join("missing.json"))
	_check(not bool(missing["ok"]) and missing["data"] is Dictionary and not String(missing["error"]).is_empty(), "missing read returns the documented error shape")
	var path: String = directory.path_join("read-cases.json")
	for malformed: String in ["", "{", "{\"a\":}", "[1,2,3]", "null", "\"a string\""]:
		_put_text(path, malformed)
		var result: Dictionary = store.read(path)
		_check(not bool(result["ok"]) and Dictionary(result["data"]).is_empty(), "bad JSON or a non-object root is refused quietly")
	var invalid_utf8: PackedByteArray = PackedByteArray([0x7b, 0x22, 0x78, 0x22, 0x3a, 0x22, 0xff, 0x22, 0x7d])
	_put_bytes(path, invalid_utf8)
	_check(not bool(store.read(path)["ok"]), "invalid UTF-8 is refused before a decoder can print an engine warning")
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(Store.MAX_SAVE_BYTES + 1)
	_put_bytes(path, oversized)
	_check(not bool(store.read(path)["ok"]), "over-limit file is refused before allocating/decoding its body")
	_put_text(path, "{}" + " ".repeat(Store.MAX_SAVE_BYTES - 2))
	_check(bool(store.read(path)["ok"]), "exactly eight MiB remains within the file limit")
	_put_bytes(path, PackedByteArray([0xef, 0xbb, 0xbf]) + "{\"备注\":\"幸存者 🚚\"}".to_utf8_buffer())
	var unicode_result: Dictionary = store.read(path)
	_check(bool(unicode_result["ok"]) and String(unicode_result["data"]["备注"]) == "幸存者 🚚", "valid BOM and multibyte UTF-8 are readable")
	_put_text(path, "{}")
	_check(bool(store.read(path)["ok"]), "file layer accepts an object without imposing the game schema")


func _test_nonreplaceable_destinations() -> void:
	var blocked_primary: String = directory.path_join("blocked-primary.json")
	_check(DirAccess.make_dir_absolute(blocked_primary) == OK, "create nonreplaceable primary directory")
	_put_text(blocked_primary.path_join("keep.txt"), "original directory contents")
	_put_text(blocked_primary + ".bak", JSON.stringify(_data(30)))
	var backup: PackedByteArray = _bytes(blocked_primary + ".bak")
	_check(store.write(blocked_primary, _data(31), _validator()) != OK, "a directory primary cannot be replaced as a save file")
	_check(_bytes(blocked_primary.path_join("keep.txt")).get_string_from_utf8() == "original directory contents", "failed primary replacement preserves the original directory contents")
	_check(_bytes(blocked_primary + ".bak") == backup, "failed primary replacement preserves the existing good backup")
	var blocked_backup: String = directory.path_join("blocked-backup.json")
	_put_text(blocked_backup, JSON.stringify(_data(32)))
	_check(DirAccess.make_dir_absolute(blocked_backup + ".bak") == OK, "create nonreplaceable backup directory")
	_put_text((blocked_backup + ".bak").path_join("keep.txt"), "original backup directory")
	var primary: PackedByteArray = _bytes(blocked_backup)
	_check(store.write(blocked_backup, _data(33), _validator()) != OK, "backup replacement failure refuses the transaction")
	_check(_bytes(blocked_backup) == primary, "backup failure never replaces the good primary first")
	_check(_bytes((blocked_backup + ".bak").path_join("keep.txt")).get_string_from_utf8() == "original backup directory", "backup failure leaves nonreplaceable target contents alone")
	var missing_parent: String = directory.path_join("does-not-exist/save.json")
	_check(store.write(missing_parent, _data(34), _validator()) != OK, "staging into an unavailable directory reports a normal error")
	_check(not FileAccess.file_exists(missing_parent), "failed staging does not invent a partial primary")


func _test_staging_permission_failure() -> void:
	if OS.has_feature("windows") or OS.get_environment("USER") == "root":
		print("SKIP Unix write-permission scenario on this platform/user")
		return
	var protected_directory: String = directory.path_join("read-only")
	_check(DirAccess.make_dir_absolute(protected_directory) == OK, "permission fixture directory is created")
	var path: String = protected_directory.path_join("save.json")
	_check(store.write(path, _data(40), _validator()) == OK, "permission fixture has a valid primary and backup")
	_check(store.write(path, _data(41), _validator()) == OK, "permission fixture has distinct generations")
	var primary: PackedByteArray = _bytes(path)
	var backup: PackedByteArray = _bytes(path + ".bak")
	var previous_permissions: int = FileAccess.get_unix_permissions(protected_directory)
	var permission_error: Error = FileAccess.set_unix_permissions(protected_directory, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_EXECUTE_OWNER)
	_check(permission_error == OK, "remove directory write access to force a real staging failure")
	var write_error: Error = store.write(path, _data(42), _validator())
	var restore_error: Error = FileAccess.set_unix_permissions(protected_directory, previous_permissions)
	_check(restore_error == OK, "restore fixture permissions before cleanup")
	_check(write_error != OK, "write-permission failure returns Error")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "real filesystem write failure preserves both known-good originals")


func _test_independent_paths() -> void:
	var manual: String = directory.path_join("manual.json")
	var automatic: String = directory.path_join("automatic.json")
	_check(store.write(manual, _data(50), _validator()) == OK, "manual path is saved")
	var manual_primary: PackedByteArray = _bytes(manual)
	var manual_backup: PackedByteArray = _bytes(manual + ".bak")
	_check(store.write(automatic, _data(60), _validator()) == OK, "automatic path first save succeeds")
	_check(store.write(automatic, _data(61), _validator()) == OK, "automatic path rotates independently")
	_check(_generation(automatic) == 61 and _generation(automatic + ".bak") == 60, "automatic path owns its own two generations")
	_check(_bytes(manual) == manual_primary and _bytes(manual + ".bak") == manual_backup, "automatic saves cannot alter manual files")


func _test_partial_stage_and_late_replace_failure() -> void:
	var path: String = directory.path_join("late-failure.json")
	_check(store.write(path, _data(70), _validator()) == OK, "late-failure fixture starts with two good generations")
	_check(store.write(path, _data(71), _validator()) == OK, "late-failure fixture primary differs from backup")
	var primary: PackedByteArray = _bytes(path)
	var backup: PackedByteArray = _bytes(path + ".bak")
	var stage_failure: Variant = FailSecondStage.new()
	_check(stage_failure.write(path, _data(72), _validator()) != OK, "a later staging failure propagates Error")
	_check(int(stage_failure.stage_count) == 2, "fault occurs after actual temporary files have been staged")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "partial staging failure preserves both good destinations")
	_assert_no_owned_temps()
	var replace_failure: Variant = BlockLatePrimary.new()
	replace_failure.primary_path = path
	replace_failure.preserved_path = path + ".original-preserved-by-test"
	_check(replace_failure.write(path, _data(73), _validator()) != OK, "late nonreplaceable primary returns Error after backup staging")
	_check(bool(replace_failure.injection_ok), "late replacement fault is actually injected after all three real stages")
	_check(_bytes(replace_failure.preserved_path) == primary, "failed commit does not alter preserved original primary bytes")
	_check(_bytes(path.path_join("keep.txt")).get_string_from_utf8() == "late nonreplaceable destination", "failed commit leaves the nonreplaceable target intact")
	_check(_bytes(path + ".bak") == backup, "primary commit failure rolls back the prior good backup rather than leaving it rotated")
	_assert_no_owned_temps()
	_erase_tree(path)
	_check(DirAccess.rename_absolute(replace_failure.preserved_path, path) == OK, "test restores its original primary path")
	_check(_bytes(path) == primary and _bytes(path + ".bak") == backup, "original file pair remains available after late failure")


func _assert_no_owned_temps() -> void:
	var unexpected: Array[String] = []
	_scan_temps(directory, unexpected)
	_check(unexpected.is_empty(), "all success/failure paths clean their own temporary files: " + str(unexpected))


func _scan_temps(path: String, found: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.contains(".tmp-") and file != FOREIGN_TEMP:
			found.append(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_scan_temps(path.path_join(child), found)


func _erase_tree(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
