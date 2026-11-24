class_name SiteView
extends Node2D
## Draw a site as a side-view cutaway (DESIGN.md, 2.1 and 7): the sky, the
## ground, the parts, the preview of the carried part, the crane, the
## highlights, the alignment guides and the residents. Grid y grows upwards;
## the screen y grows downwards, so the cell (x, y) is drawn at
## (x, height - 1 - y). The view never changes the grid.

const CELL := 32.0
const GROUND_DEPTH := 3.0
## The draw order of the layers (back to front).
const LAYER_ORDER := ["background", "window", "volume", "decor", "surface", "edge_v", "edge_h"]

var grid: WorldGrid
## The hook in cells (grid coordinates, y up).
var hook := Vector2(4, 8)
## What the hook carries: {"definition": PartDef, "anchor": Vector2i,
## "mirrored": bool, "variant": int, "ok": bool}, or {}.
var preview: Dictionary = {}
var remove_mode := false
## The instance the remove or move tool points at (0 for none).
var pointed := 0
## The instances and cells to highlight (unmet objectives, problems).
var highlighted: Array = []
var show_guides := false
var high_contrast := false
## The residents: Array of {"look", "position" (cells, float), "step"}.
var residents: Array = []
## A speech bubble: {"text": String, "position": Vector2 (cells)} or {}.
var bubble: Dictionary = {}


func site_size() -> Vector2:
    return Vector2(grid.width, grid.height) * CELL


## The screen position of a grid point (cells, y up).
func to_screen(point: Vector2) -> Vector2:
    return Vector2(point.x * CELL, (grid.height - point.y) * CELL)


## The grid point (cells, y up) of a screen position.
func to_grid(screen: Vector2) -> Vector2:
    return Vector2(screen.x / CELL, grid.height - screen.y / CELL)


func part_rect(definition: PartDef, anchor: Vector2i) -> Rect2:
    var size := definition.footprint
    match definition.layer:
        "edge_h":
            return Rect2(anchor.x * CELL, (grid.height - anchor.y) * CELL - 4.0, size.x * CELL, 8.0)
        "edge_v":
            return Rect2(
                anchor.x * CELL - 4.0, (grid.height - anchor.y - size.y) * CELL, 8.0, size.y * CELL
            )
        _:
            return Rect2(
                anchor.x * CELL,
                (grid.height - anchor.y - size.y) * CELL,
                size.x * CELL,
                size.y * CELL
            )


func _draw() -> void:
    if grid == null:
        return
    var size := site_size()
    draw_rect(Rect2(Vector2(-4000, size.y), Vector2(size.x + 8000, 4000)), Color("8b6a45"))
    draw_rect(Rect2(Vector2(-4000, size.y), Vector2(size.x + 8000, 6)), Color("5f9a3f"))
    _draw_grid_lines(size)
    var by_layer := {}
    for id in grid.sorted_ids():
        var instance: PartInstance = grid.instances[id]
        var layer := grid.definition_of(instance).layer
        if not by_layer.has(layer):
            by_layer[layer] = []
        by_layer[layer].append(instance)
    for layer in LAYER_ORDER:
        for instance in by_layer.get(layer, []):
            var definition := grid.definition_of(instance)
            var alpha := (
                0.35
                if instance.id == pointed and not remove_mode and not preview.is_empty()
                else 1.0
            )
            PartArt.draw_part(
                self,
                definition.visual_id,
                part_rect(definition, instance.anchor),
                instance.mirrored,
                instance.colour_variant,
                alpha
            )
    _draw_entry()
    _draw_highlights()
    if show_guides:
        _draw_guides(size)
    _draw_preview()
    _draw_crane(size)
    for resident in residents:
        PartArt.draw_person(
            self, to_screen(resident["position"]), CELL, resident["look"], float(resident["step"])
        )
    _draw_bubble()


func _draw_grid_lines(size: Vector2) -> void:
    var colour := Color(1, 1, 1, 0.25 if not high_contrast else 0.5)
    for x in range(grid.width + 1):
        draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, size.y), colour, 1.0)
    for y in range(grid.height + 1):
        draw_line(Vector2(0, y * CELL), Vector2(size.x, y * CELL), colour, 1.0)
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.3, 0.4, 0.6), false, 2.0)


func _draw_entry() -> void:
    var feet := to_screen(Vector2(grid.entry.x + 0.5, grid.entry.y))
    draw_colored_polygon(
        PackedVector2Array(
            [feet + Vector2(-10, -40), feet + Vector2(10, -32), feet + Vector2(-10, -24)]
        ),
        Color("2f7a3a")
    )
    draw_line(feet + Vector2(-10, 0), feet + Vector2(-10, -40), Color("3b2a1c"), 2)


func _draw_highlights() -> void:
    var colour := Color(0.85, 0.15, 0.1, 0.9)
    for item in highlighted:
        if item is int and grid.instances.has(item):
            var instance: PartInstance = grid.instances[item]
            var rect := part_rect(grid.definition_of(instance), instance.anchor).grow(4)
            draw_rect(rect, colour, false, 4.0 if not high_contrast else 6.0)
            draw_string(
                ThemeDB.fallback_font,
                rect.position + Vector2(2, -4),
                "!",
                HORIZONTAL_ALIGNMENT_LEFT,
                -1,
                24,
                colour
            )
        elif item is Vector2i:
            var cell: Vector2i = item
            draw_rect(
                Rect2(cell.x * CELL, (grid.height - 1 - cell.y) * CELL, CELL, CELL),
                Color(0.85, 0.15, 0.1, 0.3)
            )


func _draw_guides(size: Vector2) -> void:
    if preview.is_empty():
        return
    var rect := part_rect(preview["definition"], preview["anchor"])
    var colour := Color("d4a017")
    for x in [rect.position.x, rect.end.x]:
        draw_dashed_line(Vector2(x, 0), Vector2(x, size.y), colour, 1.5, 8.0)
    for y in [rect.position.y, rect.end.y]:
        draw_dashed_line(Vector2(0, y), Vector2(size.x, y), colour, 1.5, 8.0)
    var anchor: Vector2i = preview["anchor"]
    draw_string(
        ThemeDB.fallback_font,
        rect.position + Vector2(0, -8),
        "x %d, y %d" % [anchor.x, anchor.y],
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        18,
        colour
    )


func _draw_preview() -> void:
    var hook_screen := to_screen(hook)
    if preview.is_empty():
        return
    var definition: PartDef = preview["definition"]
    var rect := part_rect(definition, preview["anchor"])
    var ok := bool(preview["ok"])
    PartArt.draw_part(
        self, definition.visual_id, rect, bool(preview["mirrored"]), int(preview["variant"]), 0.6
    )
    var colour := Color("2f9a3a") if ok else Color("d0342c")
    draw_rect(rect.grow(3), colour, false, 3.0 if not high_contrast else 5.0)
    # NOTE (mristin):
    # The valid state shows as a symbol, too, not only as a colour.
    var mark := "✓" if ok else "✗"
    draw_string(
        ThemeDB.fallback_font,
        rect.position + Vector2(rect.size.x + 6, 20),
        mark,
        HORIZONTAL_ALIGNMENT_LEFT,
        -1,
        26,
        colour
    )
    draw_circle(hook_screen, 3.0, Color(0.2, 0.2, 0.2, 0.6))


func _draw_crane(size: Vector2) -> void:
    var mast_x := size.x + CELL * 1.5
    var jib_y := -CELL * 2.0
    var steel := Color("e0a030")
    var dark := Color("3a3a3a")
    draw_rect(Rect2(mast_x - 8, jib_y, 16, size.y - jib_y), steel)
    for i in range(int((size.y - jib_y) / 24.0)):
        var y := jib_y + i * 24.0
        draw_line(Vector2(mast_x - 8, y), Vector2(mast_x + 8, y + 24), dark, 1.5)
    draw_rect(Rect2(-CELL, jib_y - 10, mast_x + CELL * 3.0, 14), steel)
    draw_rect(Rect2(mast_x + CELL, jib_y - 10, CELL * 1.5, 34), dark)
    var hook_screen := to_screen(hook)
    if not preview.is_empty():
        # NOTE (mristin):
        # The hook's tip is the bottom of the carried part; the claw holds it
        # at its top.
        var carried := part_rect(preview["definition"], preview["anchor"])
        hook_screen = Vector2(hook_screen.x, minf(hook_screen.y, carried.position.y) - 6.0)
    var trolley := Vector2(hook_screen.x, jib_y + 4)
    draw_rect(Rect2(trolley + Vector2(-14, -2), Vector2(28, 12)), dark)
    draw_line(trolley + Vector2(0, 10), hook_screen, dark, 2.0)
    var claw := Color("d0342c") if remove_mode else dark
    draw_arc(hook_screen + Vector2(0, 8), 8.0, 0.0, PI, 10, claw, 3.0)
    draw_circle(hook_screen, 4.0, claw)
    if remove_mode and pointed != 0 and grid.instances.has(pointed):
        var instance: PartInstance = grid.instances[pointed]
        var rect := part_rect(grid.definition_of(instance), instance.anchor).grow(4)
        draw_rect(rect, Color("d0342c"), false, 4.0)
        draw_line(rect.position, rect.end, Color("d0342c"), 3.0)
        draw_line(
            Vector2(rect.position.x, rect.end.y),
            Vector2(rect.end.x, rect.position.y),
            Color("d0342c"),
            3.0
        )


func _draw_bubble() -> void:
    if bubble.is_empty():
        return
    var font := ThemeDB.fallback_font
    var text := str(bubble["text"])
    var width := 360.0
    var lines := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, 18)
    var anchor := to_screen(bubble["position"]) + Vector2(-width / 2.0, -CELL * 3.6 - lines.y)
    var box := Rect2(anchor - Vector2(10, 22), Vector2(width + 20, lines.y + 20))
    draw_rect(box, Color.WHITE)
    draw_rect(box, Color("3b2a1c"), false, 2.0)
    draw_multiline_string(
        font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, width, 18, -1, Color("3b2a1c")
    )
