class_name CameraView
extends Control
## Show the player in the camera picture, mirrored, with the key points the
## pose model sees (green: sure, red: unsure), so that the player sees at once
## whether the camera follows them. The menus show it dimly behind the
## buttons; the build site shows it as an inset.
##
## Nothing is drawn while the camera does not run.

const BONES := [[5, 6], [5, 7], [7, 9], [6, 8], [8, 10], [5, 11], [6, 12], [11, 12], [0, 5], [0, 6]]

## How opaque the picture is.
var picture_alpha := 1.0
## Whether the picture covers the whole control (cropped), or fits in it.
var cover := false
var show_skeleton := true
## The guides (see [method PoseController.guides]): "shoulders", the middle of
## the shoulders in the picture as the player sees it, normalized; {} for
## none.
var guides: Dictionary = {}
## A frame around the view, hidden while the camera does not run.
var frame: Control = null
## Whether the view is hidden on purpose (e.g., the inset of the build site
## while the camera covers the whole screen behind a dialogue).
var suppressed := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
    if frame != null:
        var service := _service()
        frame.visible = service != null and service.IsRunning() and not suppressed
    queue_redraw()


func _service() -> Node:
    var vision := get_node_or_null("/root/Vision")
    return vision.service if vision != null else null


func _mirrored() -> bool:
    var settings := get_node_or_null("/root/Settings")
    return settings == null or bool(settings.get_value("camera_mirror"))


func _draw() -> void:
    var service := _service()
    if service == null or not service.IsRunning():
        return
    var texture: Texture2D = service.GetCameraTexture()
    if texture == null or texture.get_width() == 0:
        return
    var picture := Vector2(texture.get_width(), texture.get_height())
    var scale := (
        maxf(size.x / picture.x, size.y / picture.y)
        if cover
        else minf(size.x / picture.x, size.y / picture.y)
    )
    var drawn := picture * scale
    var rect := Rect2((size - drawn) / 2.0, drawn)
    var mirror := _mirrored()
    if mirror:
        draw_set_transform(Vector2(size.x, 0), 0, Vector2(-1, 1))
    draw_texture_rect(texture, rect, false, Color(1, 1, 1, picture_alpha))
    draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
    if show_skeleton:
        _draw_skeleton(service, rect, mirror)
    _draw_guides(rect)


## The middle of the shoulders as a yellow dot, so that the player sees that
## the camera follows them (no lines, no skeleton: they only clutter).
func _draw_guides(rect: Rect2) -> void:
    if guides.is_empty():
        return
    var at: Vector2 = guides["shoulders"]
    draw_circle(rect.position + at * rect.size, 8.0, Color(1.0, 0.8, 0.1))
    draw_arc(rect.position + at * rect.size, 8.0, 0.0, TAU, 16, Color.BLACK, 2.0)


func _draw_skeleton(service: Node, rect: Rect2, mirror: bool) -> void:
    var points: Array = service.GetKeypoints()
    var scores: Array = service.GetKeypointScores()
    if points.size() < 13:
        return
    var place := func(index: int) -> Vector2:
        var point: Vector2 = points[index]
        if mirror:
            point.x = 1.0 - point.x
        return rect.position + point * rect.size
    var alpha := clampf(picture_alpha * 1.5, 0.4, 1.0)
    for bone in BONES:
        if float(scores[bone[0]]) >= 0.3 and float(scores[bone[1]]) >= 0.3:
            draw_line(place.call(bone[0]), place.call(bone[1]), Color(0.2, 0.75, 0.3, alpha), 4.0)
    for index in [0, 5, 6, 7, 8, 9, 10, 11, 12]:
        var sure := float(scores[index]) >= 0.6
        var colour := Color(0.2, 0.75, 0.3, alpha) if sure else Color(0.85, 0.2, 0.15, alpha)
        draw_circle(place.call(index), 6.0, colour)
