class_name Progression
extends RefCounted
## Apply the rules of the cooperative's progress (DESIGN.md, 4): a mission
## opens when its prerequisites are completed; completing it records it and
## the wishes fulfilled with it, each once.


## Whether the mission is open: its prerequisites completed.
static func mission_available(progress: Progress, mission: Dictionary) -> bool:
    for prerequisite in mission["prerequisite_ids"]:
        if not progress.has_completed(str(prerequisite)):
            return false
    return true


## Complete a mission: record it (once) and every satisfied optional wish
## (once). Return a summary for the results: {"first": bool, "wishes": the IDs
## of the wishes fulfilled now for the first time}.
static func complete_mission(
    progress: Progress, mission: Dictionary, report: MissionEvaluator.Report
) -> Dictionary:
    var summary := {"first": false, "wishes": []}
    if not report.can_submit():
        return summary
    var mission_id := str(mission["id"])
    summary["first"] = not progress.has_completed(mission_id)
    if summary["first"]:
        progress.completed_missions.append(mission_id)
    for result in report.optional:
        var key := "%s:%s" % [mission_id, result["id"]]
        if result["satisfied"] and not progress.fulfilled_wishes.has(key):
            progress.fulfilled_wishes[key] = true
            summary["wishes"].append(str(result["id"]))
    return summary
