class_name RoomDetector
extends RefCounted
## Find the enclosed rooms of a site (DESIGN.md, 5.1).
##
## We flood the cells from the outside of the site through every boundary
## without a weather-sealing part. The closed doors seal; the windows are in
## the background and do not open anything; the ground seals the bottom. The
## cells which the flood does not reach are indoors, and each connected region
## of them is a room. Whether people can walk there is up to the
## [NavigationGraph].

const DIRECTIONS: Array[Vector2i] = [
    Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


class Room:
    extends RefCounted
    var id := 0
    var cells: Array[Vector2i] = []

    func area() -> int:
        return cells.size()


class Result:
    extends RefCounted
    var rooms: Array[Room] = []
    ## The room ID of each indoor cell (Vector2i -> int).
    var room_of: Dictionary = {}

    func is_indoor(cell: Vector2i) -> bool:
        return room_of.has(cell)

    func room_at(cell: Vector2i) -> int:
        return int(room_of.get(cell, -1))


## Whether the boundary between the cell and its neighbour in the direction is
## sealed against the weather.
static func sealed(grid: WorldGrid, cell: Vector2i, direction: Vector2i) -> bool:
    var map_name := WorldGrid.SLOT_EDGE_V
    var edge := cell
    match direction:
        Vector2i.RIGHT:
            edge = cell + Vector2i(1, 0)
        Vector2i.LEFT:
            edge = cell
        Vector2i(0, 1):
            map_name = WorldGrid.SLOT_EDGE_H
            edge = cell + Vector2i(0, 1)
        Vector2i(0, -1):
            if cell.y == 0:
                return true
            map_name = WorldGrid.SLOT_EDGE_H
            edge = cell
    var instance := grid.instance_in(map_name, edge)
    return instance != null and grid.definition_of(instance).has_tag("weather_seal")


static func detect(grid: WorldGrid) -> Result:
    var outside := {}
    var queue: Array[Vector2i] = []
    for y in range(grid.height):
        for x in range(grid.width):
            var cell := Vector2i(x, y)
            for direction in DIRECTIONS:
                var neighbour := cell + direction
                if (
                    not grid.cell_in_bounds(neighbour)
                    and neighbour.y >= 0
                    and not sealed(grid, cell, direction)
                ):
                    outside[cell] = true
                    queue.append(cell)
                    break
    _flood(grid, queue, outside)

    var result := Result.new()
    for y in range(grid.height):
        for x in range(grid.width):
            var cell := Vector2i(x, y)
            if outside.has(cell) or result.room_of.has(cell):
                continue
            var room := Room.new()
            room.id = result.rooms.size()
            var region := {cell: true}
            _flood(grid, [cell], region)
            for key in region:
                room.cells.append(key)
                result.room_of[key] = room.id
            room.cells.sort()
            result.rooms.append(room)
    return result


static func _flood(grid: WorldGrid, start: Array[Vector2i], reached: Dictionary) -> void:
    var queue := start.duplicate()
    var head := 0
    while head < queue.size():
        var cell: Vector2i = queue[head]
        head += 1
        for direction in DIRECTIONS:
            var neighbour := cell + direction
            if not grid.cell_in_bounds(neighbour) or reached.has(neighbour):
                continue
            if sealed(grid, cell, direction):
                continue
            reached[neighbour] = true
            queue.append(neighbour)
