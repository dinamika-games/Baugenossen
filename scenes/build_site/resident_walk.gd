class_name ResidentWalk
extends RefCounted
## Let the residents move in after a completion (DESIGN.md, 6): they come in at
## the entry, walk to the fixtures they can reach and use them. They never use
## a fixture they can not reach, and never obstruct the construction.

const SPEED := 3.0
## The tags the residents like to use, in order.
const FAVOURITES := [
    "sleep_capacity",
    "seat_capacity",
    "table",
    "cooking",
    "hygiene",
    "lighting",
    "tree",
    "planted_area"
]

var walkers: Array = []


static func start(
    grid: WorldGrid, analysis: SiteAnalysis, mission: Dictionary, content: ContentDb
) -> ResidentWalk:
    var walk := ResidentWalk.new()
    var taken := {}
    var index := 0
    for spawn in mission["npc_spawn_defs"]:
        var resident: Dictionary = content.residents[spawn["resident_id"]]
        var goal := walk._pick_goal(grid, analysis, taken, index)
        var path: Array[Vector2i] = [grid.entry]
        if goal != Vector2i(-1, -1):
            path = analysis.navigation.path(grid.entry, goal)
        var look := {
            "skin": resident.get("skin", 0),
            "hair": resident.get("hair", 0),
            "clothing": resident.get("clothing", 0),
        }
        var walker := {
            "look": look,
            "path": path,
            "progress": -float(index) * 0.8,
            "position": Vector2(grid.entry.x + 0.5, grid.entry.y),
            "step": 0.0,
        }
        walk.walkers.append(walker)
        index += 1
    return walk


func _pick_goal(grid: WorldGrid, analysis: SiteAnalysis, taken: Dictionary, index: int) -> Vector2i:
    for offset in range(FAVOURITES.size()):
        var tag: String = FAVOURITES[(index + offset) % FAVOURITES.size()]
        for id in grid.sorted_ids():
            if taken.has(id) or not analysis.is_usable(id):
                continue
            var instance: PartInstance = grid.instances[id]
            var definition := grid.definition_of(instance)
            if not definition.has_tag(tag):
                continue
            for cell_offset in definition.interaction_offsets:
                var cell := (
                    instance.anchor + definition.mirror_offset(cell_offset, instance.mirrored)
                )
                if analysis.reachable.has(cell):
                    taken[id] = true
                    return cell
    return Vector2i(-1, -1)


## Move everyone on; return whether all arrived.
func update(delta: float, reduced_motion: bool) -> bool:
    var arrived := true
    for walker in walkers:
        var path: Array[Vector2i] = walker["path"]
        var last := float(path.size() - 1)
        walker["progress"] = (
            last if reduced_motion else minf(last, float(walker["progress"]) + delta * SPEED)
        )
        var progress := maxf(0.0, float(walker["progress"]))
        var i := mini(int(progress), path.size() - 1)
        var j := mini(i + 1, path.size() - 1)
        var a := Vector2(path[i].x + 0.5, path[i].y)
        var b := Vector2(path[j].x + 0.5, path[j].y)
        walker["position"] = a.lerp(b, progress - float(i))
        walker["step"] = progress if progress < last else 0.0
        if float(walker["progress"]) < last:
            arrived = false
    return arrived
