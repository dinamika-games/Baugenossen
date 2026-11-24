extends "res://tests/godot/godot_test.gd"
## Check the hand cursor: holding still over a button clicks it after the
## dwell, once until the hand leaves; a toggle button toggles; a disabled one
## and one scrolled out of view are not clicked; at the bottom of a list, the
## list scrolls; and it does nothing while switched off (the build site).

const STEP := 1.0 / 60.0

var cursor: Node
var clicks := 0


func _run() -> void:
    cursor = root.get_node("HandCursor")
    var screen := Control.new()
    screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(screen)
    var button := Ui.button("Go", func() -> void: clicks += 1, 200)
    button.position = Vector2(100, 100)
    screen.add_child(button)
    var toggle := CheckBox.new()
    toggle.text = "Toggle"
    toggle.position = Vector2(400, 100)
    toggle.size = Vector2(200, 52)
    screen.add_child(toggle)
    var off := Ui.button("Off", func() -> void: clicks += 100, 200)
    off.position = Vector2(700, 100)
    off.disabled = true
    screen.add_child(off)
    await _frames(3)

    var middle := button.get_global_rect().get_center()
    _point(middle)
    await _seconds(1.0)
    check_equal(clicks, 0, "half the dwell does not click")
    await _seconds(1.2)
    check_equal(clicks, 1, "the whole dwell clicks")
    await _seconds(3.0)
    check_equal(clicks, 1, "holding on clicks only once")
    _point(Vector2(5, 5))
    await _seconds(0.2)
    _point(middle)
    await _seconds(2.2)
    check_equal(clicks, 2, "leaving and coming back clicks again")
    check(
        cursor.button_at(middle + Vector2(0, 20)) == button, "the button is found under the point"
    )

    _point(toggle.get_global_rect().get_center())
    await _seconds(2.2)
    check(toggle.button_pressed, "a toggle button toggles")
    _point(off.get_global_rect().get_center())
    await _seconds(2.2)
    check_equal(clicks, 2, "a disabled button is not clicked")

    var scroll := ScrollContainer.new()
    scroll.position = Vector2(100, 300)
    scroll.size = Vector2(300, 200)
    screen.add_child(scroll)
    var column := Ui.vbox()
    scroll.add_child(column)
    var hidden: Button = null
    for i in range(20):
        hidden = Ui.button("Row %d" % i, func() -> void: clicks += 1000, 260)
        column.add_child(hidden)
    await _frames(3)
    check(cursor.button_at(Vector2(150, 600)) == null, "a button scrolled out of view is not found")
    _point(Vector2(250, 490))
    await _seconds(1.0)
    check(scroll.scroll_vertical > 0, "the list scrolls at its bottom")

    cursor.enabled = false
    _point(middle)
    await _seconds(2.5)
    check_equal(clicks % 1000, 2, "nothing clicks while the cursor is off")
    cursor.enabled = true
    cursor.test_points = [] as Array[Vector2]
    screen.queue_free()


func _point(at: Vector2) -> void:
    cursor.test_points = [at] as Array[Vector2]


func _seconds(seconds: float) -> void:
    await _frames(int(seconds / STEP))


func _frames(count: int) -> void:
    for i in range(count):
        await process_frame
