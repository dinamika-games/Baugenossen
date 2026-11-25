class_name SpannerIcon
extends Control
## Draw a spanner which turns a little to and fro, as the sign that the crane
## is calibrating (the hook waits meanwhile).

var _time := 0.0


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


func _draw() -> void:
    var centre := size / 2.0
    var length := minf(size.x, size.y) * 0.8
    draw_set_transform(centre, -PI / 4.0 + sin(_time * 3.0) * 0.35, Vector2.ONE)
    var steel := Color("6b7480")
    var handle := length * 0.16
    draw_rect(Rect2(Vector2(-handle / 2.0, -length * 0.1), Vector2(handle, length * 0.55)), steel)
    var head := Vector2(0, -length * 0.25)
    draw_circle(head, length * 0.2, steel)
    # NOTE (mristin):
    # The open jaw of the spanner: a notch in the head.
    draw_rect(
        Rect2(head + Vector2(-length * 0.07, -length * 0.24), Vector2(length * 0.14, length * 0.2)),
        Ui.PAPER
    )
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
