class_name MissionText
extends RefCounted
## Turn the missions and the objective results into the player's text, with
## whole translated sentences and named placeholders (DESIGN.md, 8; see
## [Grammar] for the plural and gender forms).


## The required amount of an objective, before any evaluation.
static func required_of(objective: Dictionary) -> int:
    for key in ["minimum", "minimum_cells", "minimum_count", "cells"]:
        if objective.has(key):
            return int(objective[key])
    if objective.has("requirements"):
        return objective["requirements"].size()
    if objective.has("objectives"):
        return objective["objectives"].size()
    return 1


## The line of an objective: its text with the required (and current) amount.
static func line(text_key: String, current: int, required: int) -> String:
    return Grammar.format(
        TranslationServer.translate(text_key), {"current": current, "required": required}
    )


## The line of a result; more than required shows as the required amount.
static func result_line(result: Dictionary) -> String:
    var required := int(result["required"])
    var current := int(result["current"])
    if required > 0:
        current = mini(current, required)
    return line(str(result["text"]), current, required)


## The names of the residents who ask, joined.
static func requesters(mission: Dictionary, content: ContentDb) -> String:
    var names: Array[String] = []
    for id in mission["requester_ids"]:
        names.append(TranslationServer.translate(content.residents[id]["name"]))
    return ", ".join(names)
