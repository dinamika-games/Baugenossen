class_name Progress
extends RefCounted
## Hold the cooperative's progress (DESIGN.md, 4): which missions are completed
## and which wishes of the residents are fulfilled. There is no character to
## build: the game is the building.

var completed_missions: Array[String] = []
## The fulfilled wishes, as "mission:objective" (as keys).
var fulfilled_wishes: Dictionary = {}


func has_completed(mission_id: String) -> bool:
    return mission_id in completed_missions


func to_dict() -> Dictionary:
    var wishes: Array = fulfilled_wishes.keys()
    wishes.sort()
    return {"completed_missions": completed_missions.duplicate(), "fulfilled_wishes": wishes}


## Read the progress, keeping only the known missions; never null (a damaged
## record gives an empty progress, reported in [param problems]).
static func from_dict(data: Variant, content: ContentDb, problems: Array[String]) -> Progress:
    var progress := Progress.new()
    if not data is Dictionary:
        problems.append("the progress is not an object")
        return progress
    for id in data.get("completed_missions", []):
        if content.missions.has(str(id)) and str(id) not in progress.completed_missions:
            progress.completed_missions.append(str(id))
        else:
            problems.append("unknown mission %s" % id)
    for id in data.get("fulfilled_wishes", []):
        progress.fulfilled_wishes[str(id)] = true
    return progress
