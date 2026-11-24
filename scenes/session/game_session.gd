class_name GameSession
extends RefCounted
## Hold the game in progress: the cooperative's progress and the state of
## every mission's site, and save them together (DESIGN.md, 6 and 10).
##
## Each mission has its own site, saved even when incomplete. The undo history
## and the camera are local to the open site and not saved. The completion of a
## mission is saved in the same snapshot as its site; if the save fails, it
## stays in memory and is retried.

signal saved
signal save_failed(message_key: String)

var content: ContentDb
var repository: SaveRepository
var progress: Progress = null
## mission ID -> {"site": Dictionary (see WorldGrid.to_dict), "status": String}
var missions: Dictionary = {}
var revision := 0
## Whether there are changes in memory which are not saved yet.
var dirty := false
var load_message := ""


func _init(db: ContentDb, repo: SaveRepository) -> void:
    content = db
    repository = repo


func has_save() -> bool:
    return repository.exists()


func new_game() -> void:
    progress = Progress.new()
    missions = {}
    revision = 0
    if repository.locked:
        repository.set_aside()
    dirty = true


## Load the save; return whether a game was loaded.
func continue_game() -> bool:
    var loaded := repository.load_save()
    load_message = repository.last_message
    if loaded["status"] not in ["ok", "recovered"]:
        return false
    var data: Dictionary = loaded["data"]
    var problems: Array[String] = []
    progress = Progress.from_dict(data.get("progress", {}), content, problems)
    for problem in problems:
        push_warning("Save: " + problem)
    missions = {}
    var saved_missions: Variant = data.get("missions", {})
    if saved_missions is Dictionary:
        for id in saved_missions:
            var record: Variant = saved_missions[id]
            if content.missions.has(str(id)) and record is Dictionary:
                missions[str(id)] = {
                    "site": record.get("site", {}) if record.get("site") is Dictionary else {},
                    "status": str(record.get("status", "in_progress")),
                }
    revision = int(data.get("revision", 0))
    dirty = false
    return true


func to_dict() -> Dictionary:
    return {
        "revision": revision,
        "progress": progress.to_dict() if progress != null else null,
        "missions": missions.duplicate(true),
    }


## Save everything; return whether it worked. On failure the changes stay in
## memory (dirty) for the next try.
func save() -> bool:
    if progress == null:
        return false
    revision += 1
    var error := repository.save(to_dict())
    if error != OK:
        revision -= 1
        dirty = true
        save_failed.emit(repository.last_message)
        return false
    dirty = false
    saved.emit()
    return true


## The grid of the mission's site, with its saved parts.
func open_site(mission_id: String) -> WorldGrid:
    var mission := content.mission(mission_id)
    var grid := WorldGrid.from_site(content, content.site(str(mission["site_id"])))
    if missions.has(mission_id):
        var problems := grid.load_dict(missions[mission_id]["site"])
        for problem in problems:
            push_warning("Site %s: %s" % [mission_id, problem])
    return grid


## Keep the parts of the site in memory (the caller saves, debounced).
func store_site(mission_id: String, grid: WorldGrid) -> void:
    var status := "in_progress"
    if missions.has(mission_id):
        status = str(missions[mission_id]["status"])
    missions[mission_id] = {"site": grid.to_dict(), "status": status}
    dirty = true


## Status of a mission for the city map: "locked", "available", "in_progress",
## "completed" or "needs_repair" (completed, but no longer valid after edits).
func mission_status(mission_id: String) -> String:
    var mission := content.mission(mission_id)
    if progress == null or not Progression.mission_available(progress, mission):
        return "locked"
    if progress.has_completed(mission_id):
        if missions.has(mission_id):
            var report := MissionEvaluator.evaluate(mission, open_site(mission_id))
            if not report.can_submit():
                return "needs_repair"
        return "completed"
    if (
        missions.has(mission_id)
        and not missions[mission_id]["site"].get("instances", []).is_empty()
    ):
        return "in_progress"
    return "available"


## Submit the mission: record its completion (once) and save it with the
## site in one snapshot. Return the summary of
## [method Progression.complete_mission], with "saved": whether it was saved.
func submit(mission_id: String, grid: WorldGrid) -> Dictionary:
    var mission := content.mission(mission_id)
    var report := MissionEvaluator.evaluate(mission, grid)
    if not report.can_submit():
        return {"submitted": false}
    store_site(mission_id, grid)
    var summary := Progression.complete_mission(progress, mission, report)
    missions[mission_id]["status"] = "completed"
    summary["submitted"] = true
    summary["saved"] = save()
    return summary
