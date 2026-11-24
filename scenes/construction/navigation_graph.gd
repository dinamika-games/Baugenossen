class_name NavigationGraph
extends RefCounted
## Find where people can stand and walk on a site (DESIGN.md, 5.1).
##
## A standing cell has a walkable surface below (the ground or a floor), and
## [constant CLEARANCE] free cells upwards: no blocking part (see
## [member PartDef.blocked_cells]) and no floor or roof in between. Neighbouring
## standing cells are linked unless a wall stands between them; doors let
## people through. Stairs and ladders link their two landings. The doors
## always seal against the weather (see [RoomDetector]), but people walk
## through them.
##
## With the mobility "wheelchair", ladders and stairs do not link anything
## (ramps and elevators come later).

const CLEARANCE := 3

var grid: WorldGrid
var mobility := "walk"
## The extra links of the stairs and the ladders: cell -> Array[Vector2i].
var _links: Dictionary = {}
var _blocked: Dictionary = {}


static func build(world: WorldGrid, mode := "walk") -> NavigationGraph:
    var graph := NavigationGraph.new()
    graph.grid = world
    graph.mobility = mode
    for id in world.sorted_ids():
        var instance: PartInstance = world.instances[id]
        var definition := world.definition_of(instance)
        for offset in definition.blocked_cells:
            var cell := instance.anchor + definition.mirror_offset(offset, instance.mirrored)
            graph._blocked[cell] = true
    if mode == "walk":
        for id in world.sorted_ids():
            var instance: PartInstance = world.instances[id]
            var definition := world.definition_of(instance)
            if definition.landings.size() != 2:
                continue
            var bottom := (
                instance.anchor
                + definition.mirror_offset(definition.landings[0], instance.mirrored)
            )
            var top := (
                instance.anchor
                + definition.mirror_offset(definition.landings[1], instance.mirrored)
            )
            graph._link(bottom, top)
            graph._link(top, bottom)
    return graph


func _link(from: Vector2i, to: Vector2i) -> void:
    if not _links.has(from):
        _links[from] = []
    _links[from].append(to)


func is_standing(cell: Vector2i) -> bool:
    if not grid.cell_in_bounds(cell):
        return false
    if cell.y > 0:
        var floor_part := grid.instance_in(WorldGrid.SLOT_EDGE_H, cell)
        if floor_part == null or not grid.definition_of(floor_part).has_tag("walkable"):
            return false
    for dy in range(CLEARANCE):
        var above := cell + Vector2i(0, dy)
        if above.y >= grid.height:
            break
        if _blocked.has(above):
            return false
        if dy > 0 and grid.at(WorldGrid.SLOT_EDGE_H, above) != 0:
            return false
    return true


## Whether a wall stands between the cell and its right neighbour, at the
## height of a person.
func wall_between(cell: Vector2i, right: bool) -> bool:
    var line := cell.x + 1 if right else cell.x
    for dy in range(CLEARANCE):
        var edge := Vector2i(line, cell.y + dy)
        var instance := grid.instance_in(WorldGrid.SLOT_EDGE_V, edge)
        if instance != null and not grid.definition_of(instance).has_tag("traversable"):
            return true
    return false


func neighbours(cell: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for right in [true, false]:
        var next := cell + (Vector2i(1, 0) if right else Vector2i(-1, 0))
        if is_standing(next) and not wall_between(cell, right):
            result.append(next)
    for target in _links.get(cell, []):
        if is_standing(target):
            result.append(target)
    return result


## The standing cells reachable from the start (breadth-first), with their
## distances; empty if the start is not a standing cell.
func reachable_from(start: Vector2i) -> Dictionary:
    return reachable_from_many([start])


## The standing cells reachable from any of the starts, with their distances.
func reachable_from_many(starts: Array[Vector2i]) -> Dictionary:
    var distances := {}
    var queue: Array[Vector2i] = []
    for start in starts:
        if is_standing(start) and not distances.has(start):
            distances[start] = 0
            queue.append(start)
    var head := 0
    while head < queue.size():
        var cell: Vector2i = queue[head]
        head += 1
        for next in neighbours(cell):
            if not distances.has(next):
                distances[next] = int(distances[cell]) + 1
                queue.append(next)
    return distances


## The shortest path of standing cells from the start to the goal; empty if
## there is none.
func path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
    var previous := {start: start}
    var queue: Array[Vector2i] = [start]
    var head := 0
    if not is_standing(start):
        return []
    while head < queue.size():
        var cell: Vector2i = queue[head]
        head += 1
        if cell == goal:
            break
        for next in neighbours(cell):
            if not previous.has(next):
                previous[next] = cell
                queue.append(next)
    if not previous.has(goal):
        return []
    var result: Array[Vector2i] = [goal]
    while result[0] != start:
        result.push_front(previous[result[0]])
    return result
