class_name SiteAnalysis
extends RefCounted
## Analyse a site once after an edit, for the objectives and the residents: the
## support, the rooms, where people can walk from the entry, and which parts
## they can use (DESIGN.md, 5). Independent of the rendering and the input.

var grid: WorldGrid
var support: SupportEvaluator.Report
var rooms: RoomDetector.Result
var navigation: NavigationGraph
## The standing cells reachable from the entry, with their distances.
var reachable: Dictionary = {}
## The usable instances (as keys): one of their interaction cells is reachable.
var usable: Dictionary = {}
## The room of each instance which has a cell indoors (ID -> room ID).
var room_of_instance: Dictionary = {}


static func analyse(world: WorldGrid) -> SiteAnalysis:
    var analysis := SiteAnalysis.new()
    analysis.grid = world
    analysis.support = SupportEvaluator.evaluate(world)
    analysis.rooms = RoomDetector.detect(world)
    analysis.navigation = NavigationGraph.build(world)
    analysis.reachable = analysis.navigation.reachable_from(world.entry)
    for id in world.sorted_ids():
        var instance: PartInstance = world.instances[id]
        var definition := world.definition_of(instance)
        for offset in definition.interaction_offsets:
            var cell := instance.anchor + definition.mirror_offset(offset, instance.mirrored)
            if analysis.reachable.has(cell):
                analysis.usable[id] = true
                break
        for cell in world.cells_of(instance):
            if analysis.rooms.is_indoor(cell):
                analysis.room_of_instance[id] = analysis.rooms.room_at(cell)
                break
    return analysis


func is_usable(id: int) -> bool:
    return usable.has(id)


func is_indoors(id: int) -> bool:
    return room_of_instance.has(id)


func room_of(id: int) -> int:
    return int(room_of_instance.get(id, -1))


## Whether some cell of the room is reachable from the entry.
func room_accessible(room: RoomDetector.Room) -> bool:
    for cell in room.cells:
        if reachable.has(cell):
            return true
    return false


## The unique cells covered by grass and flower beds.
func green_cells() -> Array[Vector2i]:
    var cells := {}
    for id in grid.sorted_ids():
        var instance: PartInstance = grid.instances[id]
        var definition := grid.definition_of(instance)
        if not (definition.has_tag("green_area") or definition.has_tag("planted_area")):
            continue
        for dx in range(definition.footprint.x):
            cells[instance.anchor + Vector2i(dx, 0)] = true
    var result: Array[Vector2i] = []
    for cell in cells:
        result.append(cell)
    result.sort()
    return result


## The problems of the support (ID -> ERROR_* key).
func support_problems() -> Dictionary:
    return support.problems
