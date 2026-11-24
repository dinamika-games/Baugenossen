class_name SupportEvaluator
extends RefCounted
## Check which parts are supported, with the simplified rules of DESIGN.md, 2.5.
##
## This is not an engineering simulation. A part is supported if a chain of
## supported parts carries it down to the ground:
## * "base" (furniture, plants), "stairs" and "ladder": every cell of the bottom
##   row stands on the ground, on a supported floor or roof, or on a beam;
## * "wall" (walls and doors): the base stands on the ground, on a supported
##   wall below, at a supported floor, or on a beam;
## * "beam": a cell of the bottom row stands on support, or an end is fixed to
##   a supported wall;
## * "span" (floors and roofs): a contiguous run of edges at one height is
##   anchored where it rests on top of a supported wall or on a beam. The edges
##   between the outermost anchors are supported (no span limit in the MVP), and
##   so are the edges overhanging up to [constant MAX_OVERHANG] cells beyond.
##   An edge which overhangs farther is connected, but not yet supported: the
##   player may build a span from one side, and must close it before submitting.
## * "none" (background, windows): needs no support.
##
## We grow the supported set from the ground until it stops changing, so a cycle
## of floating parts never supports itself.

const MAX_OVERHANG := 2


class Report:
    extends RefCounted
    ## The supported instance IDs (as keys).
    var supported: Dictionary = {}
    ## The floor and roof instances which overhang too far, but are connected.
    var overhang: Dictionary = {}
    ## The supported horizontal edges (as keys), on which parts can stand.
    var supported_edges: Dictionary = {}
    ## Why each problematic instance is not fine: an ERROR_* translation key.
    var problems: Dictionary = {}

    func is_supported(id: int) -> bool:
        return supported.has(id)

    func problem_ids() -> Array[int]:
        var ids: Array[int] = []
        for id in problems:
            ids.append(int(id))
        ids.sort()
        return ids


static func evaluate(grid: WorldGrid) -> Report:
    var report := Report.new()
    var ids := grid.sorted_ids()
    var changed := true
    while changed:
        changed = false
        for id in ids:
            if report.supported.has(id):
                continue
            var instance: PartInstance = grid.instances[id]
            var definition := grid.definition_of(instance)
            if definition.support_rule == "span":
                continue
            if _is_carried(grid, report, instance, definition):
                report.supported[id] = true
                changed = true
        if _update_spans(grid, report):
            changed = true

    for id in ids:
        var instance: PartInstance = grid.instances[id]
        var definition := grid.definition_of(instance)
        if report.overhang.has(id) and not report.supported.has(id):
            report.problems[id] = "ERROR_OVERHANG"
        elif not report.supported.has(id):
            report.problems[id] = "ERROR_UNSUPPORTED"
        elif definition.support_rule in ["stairs", "ladder"]:
            var top := (
                instance.anchor
                + definition.mirror_offset(definition.landings[1], instance.mirrored)
            )
            if not surface_supported(grid, report, top):
                report.problems[id] = "ERROR_TOP_LANDING"
    return report


## Whether something can stand on the bottom of the cell: the ground, a
## supported floor or roof, or a supported beam below.
static func surface_supported(grid: WorldGrid, report: Report, cell: Vector2i) -> bool:
    if cell.y == 0:
        return true
    if report.supported_edges.has(cell):
        return true
    var below := grid.instance_in(WorldGrid.SLOT_CELLS, cell + Vector2i(0, -1))
    return (
        below != null
        and report.supported.has(below.id)
        and grid.definition_of(below).support_rule == "beam"
    )


static func _is_carried(
    grid: WorldGrid, report: Report, instance: PartInstance, definition: PartDef
) -> bool:
    var anchor := instance.anchor
    match definition.support_rule:
        "none":
            return true
        "base", "stairs", "ladder":
            for dx in range(definition.footprint.x):
                if not surface_supported(grid, report, anchor + Vector2i(dx, 0)):
                    return false
            return true
        "beam":
            for dx in range(definition.footprint.x):
                if surface_supported(grid, report, anchor + Vector2i(dx, 0)):
                    return true
            return (
                _supported_in(grid, report, WorldGrid.SLOT_EDGE_V, anchor)
                or _supported_in(
                    grid,
                    report,
                    WorldGrid.SLOT_EDGE_V,
                    anchor + Vector2i(definition.footprint.x, 0)
                )
            )
        "wall":
            return _wall_base_carried(grid, report, anchor)
    return false


static func _wall_base_carried(grid: WorldGrid, report: Report, base: Vector2i) -> bool:
    if base.y == 0:
        return true
    if _supported_in(grid, report, WorldGrid.SLOT_EDGE_V, base + Vector2i(0, -1)):
        return true
    if report.supported_edges.has(base) or report.supported_edges.has(base + Vector2i(-1, 0)):
        return true
    for dx in [-1, 0]:
        var cell: Vector2i = base + Vector2i(dx, -1)
        var below := grid.instance_in(WorldGrid.SLOT_CELLS, cell)
        if (
            below != null
            and report.supported.has(below.id)
            and grid.definition_of(below).support_rule == "beam"
        ):
            return true
    return false


static func _supported_in(grid: WorldGrid, report: Report, map_name: String, key: Vector2i) -> bool:
    var id := grid.at(map_name, key)
    return id != 0 and report.supported.has(id)


## Whether the horizontal edge rests on top of a supported wall or a beam.
static func _edge_anchored(grid: WorldGrid, report: Report, edge: Vector2i) -> bool:
    var below_left := edge + Vector2i(0, -1)
    var below_right := edge + Vector2i(1, -1)
    if _supported_in(grid, report, WorldGrid.SLOT_EDGE_V, below_left):
        return true
    if _supported_in(grid, report, WorldGrid.SLOT_EDGE_V, below_right):
        return true
    var cell := grid.instance_in(WorldGrid.SLOT_CELLS, below_left)
    return (
        cell != null
        and report.supported.has(cell.id)
        and grid.definition_of(cell).support_rule == "beam"
    )


## Find the runs of horizontal edges and mark the supported ones; return
## whether anything new became supported.
static func _update_spans(grid: WorldGrid, report: Report) -> bool:
    var by_row: Dictionary = {}
    for key in grid._slots[WorldGrid.SLOT_EDGE_H]:
        var edge: Vector2i = key
        if not by_row.has(edge.y):
            by_row[edge.y] = []
        by_row[edge.y].append(edge.x)

    var changed := false
    var rows: Array = by_row.keys()
    rows.sort()
    for y in rows:
        var xs: Array = by_row[y]
        xs.sort()
        var start := 0
        while start < xs.size():
            var stop := start
            while stop + 1 < xs.size() and int(xs[stop + 1]) == int(xs[stop]) + 1:
                stop += 1
            if _mark_run(grid, report, int(y), xs.slice(start, stop + 1)):
                changed = true
            start = stop + 1
    return changed


static func _mark_run(grid: WorldGrid, report: Report, y: int, xs: Array) -> bool:
    var anchors: Array[int] = []
    for x in xs:
        if _edge_anchored(grid, report, Vector2i(int(x), y)):
            anchors.append(int(x))
    if anchors.is_empty():
        return false
    var low: int = anchors.min() - MAX_OVERHANG
    var high: int = anchors.max() + MAX_OVERHANG
    var changed := false
    var seen := {}
    for x in xs:
        var id := grid.at(WorldGrid.SLOT_EDGE_H, Vector2i(int(x), y))
        if seen.has(id):
            continue
        seen[id] = true
        if report.supported.has(id):
            continue
        var instance: PartInstance = grid.instances[id]
        var fine := true
        for edge in grid.slots_of(instance):
            if edge.x < low or edge.x > high:
                fine = false
        if fine:
            report.supported[id] = true
            report.overhang.erase(id)
            for edge in grid.slots_of(instance):
                report.supported_edges[edge] = true
            changed = true
        else:
            report.overhang[id] = true
    return changed
