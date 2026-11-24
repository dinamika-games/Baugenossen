class_name PartIcon
extends Control
## Draw a block of the row: the part scaled into the box, its name, the
## selection, and for the oldest block how soon it leaves the row.

var definition: PartDef
var label := ""
var selected := false
## How far the oldest block is to leaving the row, in [0, 1] (-1: not the
## oldest).
var leaving := -1.0


func _draw() -> void:
    if definition == null:
        return
    var box := Rect2(Vector2(8, 6), size - Vector2(16, 40))
    var footprint := Vector2(maxi(definition.footprint.x, 1), maxi(definition.footprint.y, 1))
    var cell := minf(box.size.x / footprint.x, box.size.y / footprint.y)
    var drawn := footprint * cell
    match definition.layer:
        "edge_h":
            drawn = Vector2(definition.footprint.x * cell, 8)
        "edge_v":
            drawn = Vector2(8, definition.footprint.y * cell)
    var rect := Rect2(box.position + (box.size - drawn) / 2.0, drawn)
    PartArt.draw_part(self, definition.visual_id, rect, false, 0, 1.0)
    var font := ThemeDB.fallback_font
    draw_string(
        font, Vector2(4, size.y - 14), label, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 15, Ui.INK
    )
    if leaving >= 0.0:
        var bar := Rect2(Vector2(8, size.y - 8), Vector2((size.x - 16) * (1.0 - leaving), 4))
        draw_rect(bar, Ui.BAD_COLOUR)
    if selected:
        draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Ui.ACCENT, false, 6.0)
