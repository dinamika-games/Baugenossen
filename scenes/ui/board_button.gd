class_name BoardButton
extends Button
## Be a big button of the main menu: a cream signboard in a wooden frame with
## nail heads at the corners, like the boards on a building site; the main
## button of a screen is warm orange. Hovered by the mouse, it grows a little.
## The hand cursor clicks it like any button.
##
## Drawn in code until the painted sprites arrive.

const WOOD := Color("8a5a2b")
const WOOD_LIGHT := Color("b07a45")
const CREAM := Color("f6e7c8")
const ORANGE := Color("d9772e")
const NAIL := Color("4a4a4f")
const GROW := 1.04

var primary := false


static func create(label: String, action: Callable, is_primary := false) -> BoardButton:
    var button := BoardButton.new()
    button.text = label
    button.primary = is_primary
    button.custom_minimum_size = Vector2(460, 72)
    button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    button.add_theme_font_size_override("font_size", 30)
    var ink := Color.WHITE if is_primary else Ui.INK
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        button.add_theme_color_override(state, ink)
    button.add_theme_color_override("font_disabled_color", Color(Ui.INK, 0.35))
    var face := ORANGE if is_primary else CREAM
    button.add_theme_stylebox_override("normal", _board(face))
    button.add_theme_stylebox_override("hover", _board(face.lightened(0.12)))
    button.add_theme_stylebox_override("pressed", _board(face.darkened(0.12)))
    button.add_theme_stylebox_override("disabled", _board(face.lerp(Color("d8d0c0"), 0.6)))
    button.add_theme_stylebox_override("focus", _focus())
    button.pressed.connect(action)
    button.pressed.connect(Ui._click.bind(button))
    button.mouse_entered.connect(button._grow.bind(true))
    button.mouse_exited.connect(button._grow.bind(false))
    button.resized.connect(func() -> void: button.pivot_offset = button.size / 2.0)
    return button


static func _board(face: Color) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = face
    box.border_color = WOOD
    box.set_border_width_all(9)
    box.set_corner_radius_all(10)
    box.shadow_color = Color(0, 0, 0, 0.3)
    box.shadow_size = 6
    box.shadow_offset = Vector2(0, 4)
    box.content_margin_left = 28
    box.content_margin_right = 28
    box.content_margin_top = 10
    box.content_margin_bottom = 10
    return box


static func _focus() -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.draw_center = false
    box.border_color = Color("f2c14b")
    box.set_border_width_all(4)
    box.set_corner_radius_all(14)
    box.expand_margin_left = 6
    box.expand_margin_right = 6
    box.expand_margin_top = 6
    box.expand_margin_bottom = 6
    return box


func _grow(on: bool) -> void:
    if disabled:
        return
    scale = Vector2.ONE * (GROW if on else 1.0)


func _draw() -> void:
    # NOTE (mristin):
    # The grain of the frame and a nail head in every corner.
    var frame := Rect2(Vector2.ZERO, size)
    draw_line(frame.position + Vector2(14, 3), Vector2(frame.end.x - 14, 3), WOOD_LIGHT, 2.0)
    draw_line(
        Vector2(14, frame.end.y - 4), Vector2(frame.end.x - 14, frame.end.y - 4), WOOD_LIGHT, 2.0
    )
    for corner in [
        Vector2(4.5, 4.5),
        Vector2(size.x - 4.5, 4.5),
        Vector2(4.5, size.y - 4.5),
        Vector2(size.x - 4.5, size.y - 4.5),
    ]:
        draw_circle(corner, 3.2, NAIL)
        draw_circle(corner + Vector2(-0.8, -0.8), 1.2, Color(1, 1, 1, 0.6))
