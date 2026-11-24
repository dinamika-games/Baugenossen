class_name SaveRepository
extends RefCounted
## Save and load the game as JSON in a directory of user:// (DESIGN.md, 10).
##
## A save is written to a temporary file, read back and checked, the previous
## save is kept as the backup (the last known good), and only then the
## temporary file replaces the save. A corrupt save falls back to the backup.
## A save of an unknown (newer) version is never overwritten: the repository
## locks itself and reports it. Old versions are migrated explicitly.

const SCHEMA_VERSION := 1
const FILE_NAME := "baugenossen_save.json"

var directory := "user://saves"
## Set when the save on disk must not be overwritten (an unknown version).
var locked := false
var last_message := ""


func _init(dir := "user://saves") -> void:
    directory = dir


func path() -> String:
    return directory.path_join(FILE_NAME)


func backup_path() -> String:
    return path() + ".bak"


func exists() -> bool:
    return FileAccess.file_exists(path()) or FileAccess.file_exists(backup_path())


## Write the data atomically; return OK or the error (and keep the old save).
func save(data: Dictionary) -> Error:
    if locked:
        last_message = "SAVE_ERROR_LOCKED"
        return ERR_FILE_CANT_WRITE
    var record := data.duplicate(true)
    record["schema_version"] = SCHEMA_VERSION
    var temporary := path() + ".tmp"
    var error := _write_verified(temporary, JSON.stringify(record, "  ", true))
    if error == OK:
        error = _keep_backup()
    if error == OK:
        error = DirAccess.rename_absolute(temporary, path())
    if error != OK:
        if last_message == "":
            last_message = "SAVE_ERROR_WRITE"
        return error
    return OK


## Write the text and read it back; OK if it parses.
func _write_verified(file_path: String, text: String) -> Error:
    last_message = ""
    var error := DirAccess.make_dir_recursive_absolute(directory)
    if error != OK:
        return error
    var file := FileAccess.open(file_path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(text)
    file.close()
    if Json.parse(FileAccess.get_file_as_string(file_path)) == null:
        last_message = "SAVE_ERROR_VERIFY"
        DirAccess.remove_absolute(file_path)
        return ERR_FILE_CORRUPT
    return OK


## Keep the current save, if it is readable, as the last known good backup.
func _keep_backup() -> Error:
    if not FileAccess.file_exists(path()):
        return OK
    if not Json.parse(FileAccess.get_file_as_string(path())) is Dictionary:
        return OK
    DirAccess.remove_absolute(backup_path())
    return DirAccess.rename_absolute(path(), backup_path())


## Load the save: {"status": "ok" | "missing" | "recovered" | "corrupt" |
## "unknown_version", "data": Dictionary}. "recovered" means the save was
## damaged and the backup was loaded instead.
func load_save() -> Dictionary:
    locked = false
    if not exists():
        return {"status": "missing", "data": {}}
    var main := _read(path())
    if main["status"] == "unknown_version":
        locked = true
        last_message = "SAVE_ERROR_UNKNOWN_VERSION"
        return main
    if main["status"] == "ok":
        return main
    var backup := _read(backup_path())
    if backup["status"] == "ok":
        last_message = "SAVE_RECOVERED_FROM_BACKUP"
        backup["status"] = "recovered"
        return backup
    if backup["status"] == "unknown_version":
        locked = true
        last_message = "SAVE_ERROR_UNKNOWN_VERSION"
        return backup
    # NOTE (mristin):
    # We keep the damaged file for the player and never overwrite it.
    locked = true
    last_message = "SAVE_ERROR_CORRUPT"
    return {"status": "corrupt", "data": {}}


func _read(file_path: String) -> Dictionary:
    if not FileAccess.file_exists(file_path):
        return {"status": "missing", "data": {}}
    var parsed: Variant = Json.parse(FileAccess.get_file_as_string(file_path))
    if not parsed is Dictionary:
        return {"status": "corrupt", "data": {}}
    var data: Dictionary = parsed
    var version := int(data.get("schema_version", 0))
    if version > SCHEMA_VERSION or version < 0:
        return {"status": "unknown_version", "data": {}, "version": version}
    return {"status": "ok", "data": migrate(data)}


## Move a damaged or unknown save aside (keeping it for the player), so that a
## new game can be saved; return the new name of the file, or "".
func set_aside() -> String:
    var stamp := str(Time.get_unix_time_from_system()).replace(".", "_")
    var kept := ""
    for file_path in [path(), backup_path()]:
        if FileAccess.file_exists(file_path):
            var target: String = file_path + ".kept_" + stamp
            if DirAccess.rename_absolute(file_path, target) == OK and kept == "":
                kept = target
    locked = false
    return kept


## Bring an old save up to [constant SCHEMA_VERSION], one version at a time.
static func migrate(data: Dictionary) -> Dictionary:
    var record := data.duplicate(true)
    var version := int(record.get("schema_version", 0))
    if version == 0:
        # NOTE (mristin):
        # Version 0 (the prototype) called the character "builder" and kept the
        # sites by their site ID instead of the mission ID.
        if record.has("builder") and not record.has("character"):
            record["character"] = record["builder"]
            record.erase("builder")
        if record.has("sites") and not record.has("missions"):
            record["missions"] = {}
            for key in record["sites"]:
                record["missions"][key] = {"site": record["sites"][key], "status": "in_progress"}
            record.erase("sites")
        version = 1
    record["schema_version"] = version
    return record
