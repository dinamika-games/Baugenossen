class_name PartArt
extends RefCounted
## Draw the parts, the residents and the crane as placeholder vector art, until
## the painted sprites arrive (DESIGN.md, 7). Each part is drawn in its
## footprint rectangle in screen space (y down); the drawing never decides
## anything about the game.
##
## When the sprites come, put them in assets/parts/<visual_id>.png and draw them
## here instead; the footprints stay the same.

const WOOD := [Color("b07a45"), Color("8f6a4e"), Color("c79a5b")]
const WOOD_DARK := Color("6b4a2c")
const STONE := [Color("9a9a92"), Color("b3a48c"), Color("8c96a0")]
const FABRIC := [Color("5b8fc7"), Color("c75b6b"), Color("6bab6b")]
const LEAF := Color("4f9a45")
const LEAF_DARK := Color("367a33")
const GLASS := Color(0.7, 0.88, 1.0, 0.85)
const OUTLINE := Color("3b2a1c")
const STEEL := Color("707b86")

## The palettes of the residents and the builder.
const SKINS := [
    Color("f5d0b0"),
    Color("e0ac83"),
    Color("c68863"),
    Color("a0663f"),
    Color("7a4a2b"),
    Color("5a3520")
]
const HAIRS := [Color("2b1d14"), Color("6b4423"), Color("c9a050"), Color("a33b20"), Color("d8d8d8")]
const CLOTHES := [
    Color("3f6fb5"),
    Color("b5523f"),
    Color("4f9a6b"),
    Color("c79a2b"),
    Color("7a4fa0"),
    Color("3f8f9a")
]


static func pick(palette: Array, index: int) -> Color:
    return palette[posmod(index, palette.size())]


## Draw the part into the rectangle (for edges: the thin rectangle along the
## edge). [param mirrored] flips asymmetric furniture.
static func draw_part(
    canvas: CanvasItem, visual_id: String, rect: Rect2, mirrored: bool, variant: int, alpha := 1.0
) -> void:
    var fade := Color(1, 1, 1, alpha)
    match visual_id:
        "floor_wood", "roof_flat":
            var colour := (
                pick(WOOD, variant)
                if visual_id == "floor_wood"
                else pick([Color("9a3b2e"), Color("5d6a74"), Color("7a5a3a")], variant)
            )
            canvas.draw_rect(rect, colour * fade)
            canvas.draw_rect(rect, OUTLINE * fade, false, 1.5)
        "wall_wood", "wall_short", "door_wood", "wall_stone":
            _draw_wall(canvas, visual_id, rect, variant, fade)
        "back_wall":
            canvas.draw_rect(
                rect, pick([Color("efe2c8"), Color("d8e4d0"), Color("e8d4d8")], variant) * fade
            )
            for i in range(1, int(rect.size.y / 16.0)):
                var y := rect.position.y + i * 16.0
                canvas.draw_line(
                    Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0, 0, 0, 0.06) * fade
                )
        "window_basic", "window_large":
            var inner := rect.grow(-4)
            canvas.draw_rect(rect, WOOD_DARK * fade)
            canvas.draw_rect(inner, GLASS * fade)
            canvas.draw_line(
                Vector2(inner.get_center().x, inner.position.y),
                Vector2(inner.get_center().x, inner.end.y),
                WOOD_DARK * fade,
                3
            )
            canvas.draw_line(
                Vector2(inner.position.x, inner.get_center().y),
                Vector2(inner.end.x, inner.get_center().y),
                WOOD_DARK * fade,
                3
            )
        "stairs_basic":
            _draw_stairs(canvas, rect, mirrored, fade)
        "ladder_basic":
            _draw_ladder(canvas, rect, fade)
        "beam_wood", "beam_steel":
            var colour := WOOD_DARK if visual_id == "beam_wood" else STEEL
            canvas.draw_rect(rect.grow_individual(0, -6, 0, 0), colour * fade)
            canvas.draw_rect(rect.grow_individual(0, -6, 0, 0), OUTLINE * fade, false, 1.5)
        _:
            _draw_furniture(canvas, visual_id, rect, mirrored, variant, fade)


static func _draw_wall(
    canvas: CanvasItem, visual_id: String, rect: Rect2, variant: int, fade: Color
) -> void:
    if visual_id == "door_wood":
        var door := rect.grow_individual(4, 0, 4, 0)
        canvas.draw_rect(door, pick(WOOD, variant).darkened(0.15) * fade)
        canvas.draw_rect(door, OUTLINE * fade, false, 1.5)
        canvas.draw_circle(
            Vector2(door.end.x - 3, door.get_center().y + 6), 2.0, Color("e0c060") * fade
        )
        return
    var colour := pick(STONE, variant) if visual_id == "wall_stone" else pick(WOOD, variant)
    canvas.draw_rect(rect, colour * fade)
    canvas.draw_rect(rect, OUTLINE * fade, false, 1.5)
    if visual_id == "wall_stone":
        for i in range(1, int(rect.size.y / 12.0)):
            var y := rect.position.y + i * 12.0
            canvas.draw_line(
                Vector2(rect.position.x, y), Vector2(rect.end.x, y), OUTLINE * fade, 1.0
            )


static func _draw_stairs(canvas: CanvasItem, rect: Rect2, mirrored: bool, fade: Color) -> void:
    var steps := 6
    var w := rect.size.x / steps
    var h := rect.size.y / steps
    for i in range(steps):
        var x := rect.position.x + (i * w if not mirrored else rect.size.x - (i + 1) * w)
        var step := Rect2(x, rect.end.y - (i + 1) * h, w, (i + 1) * h)
        canvas.draw_rect(step, pick(WOOD, 0).lightened(0.05 * (i % 2)) * fade)
        canvas.draw_line(step.position, Vector2(step.end.x, step.position.y), OUTLINE * fade, 2)


static func _draw_ladder(canvas: CanvasItem, rect: Rect2, fade: Color) -> void:
    var left := rect.position.x + rect.size.x * 0.2
    var right := rect.end.x - rect.size.x * 0.2
    canvas.draw_line(Vector2(left, rect.position.y), Vector2(left, rect.end.y), WOOD_DARK * fade, 3)
    canvas.draw_line(
        Vector2(right, rect.position.y), Vector2(right, rect.end.y), WOOD_DARK * fade, 3
    )
    var rungs := int(rect.size.y / 12.0)
    for i in range(1, rungs):
        var y := rect.position.y + i * rect.size.y / rungs
        canvas.draw_line(Vector2(left, y), Vector2(right, y), WOOD_DARK * fade, 2)


static func _flip(rect: Rect2, local: Rect2, mirrored: bool) -> Rect2:
    var result := Rect2(rect.position + local.position * rect.size, local.size * rect.size)
    if mirrored:
        result.position.x = (
            rect.position.x + rect.size.x - (result.position.x - rect.position.x) - result.size.x
        )
    return result


static func _draw_furniture(
    canvas: CanvasItem, visual_id: String, rect: Rect2, mirrored: bool, variant: int, fade: Color
) -> void:
    var wood := pick(WOOD, variant) * fade
    var fabric := pick(FABRIC, variant) * fade
    match visual_id:
        "bed_single":
            canvas.draw_rect(_flip(rect, Rect2(0, 0.55, 1, 0.3), mirrored), wood)
            canvas.draw_rect(_flip(rect, Rect2(0, 0.4, 0.92, 0.2), mirrored), fabric)
            canvas.draw_rect(
                _flip(rect, Rect2(0.04, 0.3, 0.22, 0.14), mirrored), Color.WHITE * fade
            )
            canvas.draw_rect(_flip(rect, Rect2(0, 0.15, 0.06, 0.85), mirrored), wood.darkened(0.2))
            canvas.draw_rect(_flip(rect, Rect2(0.94, 0.4, 0.06, 0.6), mirrored), wood.darkened(0.2))
        "table_basic":
            canvas.draw_rect(_flip(rect, Rect2(0, 0.45, 1, 0.1), false), wood)
            canvas.draw_rect(_flip(rect, Rect2(0.08, 0.55, 0.08, 0.45), false), wood.darkened(0.2))
            canvas.draw_rect(_flip(rect, Rect2(0.84, 0.55, 0.08, 0.45), false), wood.darkened(0.2))
        "chair_basic":
            canvas.draw_rect(_flip(rect, Rect2(0.1, 0.55, 0.8, 0.1), mirrored), wood)
            canvas.draw_rect(_flip(rect, Rect2(0.1, 0.1, 0.12, 0.9), mirrored), wood.darkened(0.2))
            canvas.draw_rect(
                _flip(rect, Rect2(0.78, 0.65, 0.12, 0.35), mirrored), wood.darkened(0.2)
            )
        "bench_basic", "sofa_basic":
            var seat := fabric if visual_id == "sofa_basic" else wood
            canvas.draw_rect(_flip(rect, Rect2(0, 0.5, 1, 0.15), mirrored), seat)
            canvas.draw_rect(_flip(rect, Rect2(0, 0.15, 1, 0.12), mirrored), seat.darkened(0.1))
            canvas.draw_rect(
                _flip(rect, Rect2(0.05, 0.27, 0.05, 0.73), mirrored), wood.darkened(0.25)
            )
            canvas.draw_rect(
                _flip(rect, Rect2(0.9, 0.27, 0.05, 0.73), mirrored), wood.darkened(0.25)
            )
        "sink_basic":
            canvas.draw_rect(_flip(rect, Rect2(0.05, 0.5, 0.9, 0.5), false), Color("dfe6ea") * fade)
            canvas.draw_rect(
                _flip(rect, Rect2(0.15, 0.4, 0.7, 0.12), false), Color("b8c6cf") * fade
            )
            canvas.draw_rect(_flip(rect, Rect2(0.45, 0.15, 0.08, 0.25), false), STEEL * fade)
        "toilet_basic":
            canvas.draw_rect(
                _flip(rect, Rect2(0.15, 0.6, 0.7, 0.4), mirrored), Color("f2f4f5") * fade
            )
            canvas.draw_rect(
                _flip(rect, Rect2(0.55, 0.2, 0.35, 0.45), mirrored), Color("e4e9ec") * fade
            )
        "stove_basic":
            canvas.draw_rect(_flip(rect, Rect2(0.05, 0.3, 0.9, 0.7), false), Color("d9d9d9") * fade)
            canvas.draw_rect(
                _flip(rect, Rect2(0.15, 0.5, 0.7, 0.35), false), Color("3a3a3a") * fade
            )
            canvas.draw_rect(
                _flip(rect, Rect2(0.1, 0.25, 0.3, 0.06), false), Color("4a4a4a") * fade
            )
            canvas.draw_rect(
                _flip(rect, Rect2(0.6, 0.25, 0.3, 0.06), false), Color("4a4a4a") * fade
            )
        "lamp_basic":
            canvas.draw_rect(_flip(rect, Rect2(0.45, 0.35, 0.1, 0.6), false), STEEL * fade)
            canvas.draw_rect(_flip(rect, Rect2(0.25, 0.9, 0.5, 0.1), false), STEEL * fade)
            var shade := _flip(rect, Rect2(0.15, 0.05, 0.7, 0.35), false)
            (
                canvas
                . draw_colored_polygon(
                    PackedVector2Array(
                        [
                            Vector2(shade.position.x + shade.size.x * 0.25, shade.position.y),
                            Vector2(shade.end.x - shade.size.x * 0.25, shade.position.y),
                            shade.end,
                            Vector2(shade.position.x, shade.end.y),
                        ]
                    ),
                    pick([Color("f2d16b"), Color("f29b6b"), Color("9bd1f2")], variant) * fade
                )
            )
        "flower_bed":
            canvas.draw_rect(_flip(rect, Rect2(0, 0.6, 1, 0.4), false), Color("7a5232") * fade)
            for i in range(5):
                var center := rect.position + Vector2((i + 0.5) / 5.0, 0.4) * rect.size
                canvas.draw_line(center, center + Vector2(0, rect.size.y * 0.25), LEAF * fade, 2)
                canvas.draw_circle(
                    center,
                    rect.size.y * 0.18,
                    pick([Color("e05a7a"), Color("f2c14b"), Color("9b6be0")], variant + i) * fade
                )
        "grass_patch":
            canvas.draw_rect(_flip(rect, Rect2(0, 0.75, 1, 0.25), false), LEAF * fade)
            for i in range(8):
                var x := rect.position.x + (i + 0.5) * rect.size.x / 8.0
                canvas.draw_line(
                    Vector2(x, rect.end.y - rect.size.y * 0.25),
                    Vector2(x + 2, rect.end.y - rect.size.y * 0.5),
                    LEAF_DARK * fade,
                    2
                )
        "tree_small", "tree_large":
            var trunk := _flip(rect, Rect2(0.42, 0.5, 0.16, 0.5), false)
            canvas.draw_rect(trunk, WOOD_DARK * fade)
            var crown := rect.position + Vector2(0.5, 0.33) * rect.size
            var radius := minf(rect.size.x * 0.48, rect.size.y * 0.33)
            canvas.draw_circle(crown, radius, LEAF_DARK * fade)
            canvas.draw_circle(
                crown + Vector2(-radius * 0.3, -radius * 0.2), radius * 0.7, LEAF * fade
            )
        _:
            canvas.draw_rect(rect, Color(0.8, 0.3, 0.8, 0.6) * fade)


## Draw a resident (or the builder) standing with the feet at [param feet].
static func draw_person(
    canvas: CanvasItem, feet: Vector2, cell: float, look: Dictionary, step := 0.0, alpha := 1.0
) -> void:
    var fade := Color(1, 1, 1, alpha)
    var height := cell * 2.6
    var swing := sin(step * TAU) * cell * 0.12
    var body := pick(CLOTHES, int(look.get("clothing", 0))) * fade
    var skin := pick(SKINS, int(look.get("skin", 0))) * fade
    var hair := pick(HAIRS, int(look.get("hair", 0))) * fade
    canvas.draw_line(
        feet + Vector2(-cell * 0.12 + swing, 0),
        feet + Vector2(-cell * 0.08, -height * 0.4),
        Color("33333a") * fade,
        cell * 0.14
    )
    canvas.draw_line(
        feet + Vector2(cell * 0.12 - swing, 0),
        feet + Vector2(cell * 0.08, -height * 0.4),
        Color("33333a") * fade,
        cell * 0.14
    )
    canvas.draw_rect(
        Rect2(feet + Vector2(-cell * 0.22, -height * 0.78), Vector2(cell * 0.44, height * 0.42)),
        body
    )
    var head := feet + Vector2(0, -height * 0.88)
    canvas.draw_circle(head, cell * 0.24, skin)
    canvas.draw_arc(head, cell * 0.25, PI, TAU, 12, hair, cell * 0.12)
