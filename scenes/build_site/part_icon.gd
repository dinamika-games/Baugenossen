class_name PartIcon
extends Control
## Draw a part as a catalogue entry: the part scaled into the box, its name,
## a lock if it is not unlocked yet, the selection and the dwell progress of
## the pointing hand.

var definition: PartDef
var label := ""
var locked := false
var selected := false
## The dwell progress in [0, 1] (0 hides it).
var dwell := 0.0


func _draw() -> void:
    var box := Rect2(Vector2(8, 6), size - Vector2(16, 34))
    var footprint := Vector2(maxi(definition.footprint.x, 1), maxi(definition.footprint.y, 1))
    var cell := minf(box.size.x / footprint.x, box.size.y / footprint.y)
    var drawn := footprint * cell
    match definition.layer:
        "edge_h":
            drawn = Vector2(definition.footprint.x * cell, 8)
        "edge_v":
            drawn = Vector2(8, definition.footprint.y * cell)
    var rect := Rect2(box.position + (box.size - drawn) / 2.0, drawn)
    PartArt.draw_part(self, definition.visual_id, rect, false, 0, 0.45 if locked else 1.0)
    var font := ThemeDB.fallback_font
    draw_string(
        font, Vector2(4, size.y - 8), label, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 13, Ui.INK
    )
    if locked:
        draw_string(font, Vector2(size.x - 24, 22), "🔒", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Ui.INK)
    if selected:
        draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Ui.ACCENT, false, 4.0)
    if dwell > 0.0:
        draw_arc(
            size / 2.0,
            minf(size.x, size.y) / 2.0 - 6,
            -PI / 2,
            -PI / 2 + TAU * dwell,
            32,
            Ui.ACCENT,
            6.0
        )
