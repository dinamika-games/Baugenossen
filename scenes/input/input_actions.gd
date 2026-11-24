class_name InputActions
extends RefCounted
## Register the keyboard and mouse fallback (DESIGN.md, 3.1). It is always
## available, not only for debugging.

const KEYS := {
    "hook_left": [KEY_A, KEY_LEFT],
    "hook_right": [KEY_D, KEY_RIGHT],
    "hook_up": [KEY_W, KEY_UP],
    "hook_down": [KEY_S, KEY_DOWN],
    "confirm": [KEY_SPACE],
    "cancel": [KEY_ESCAPE],
    "open_catalogue": [KEY_TAB],
    "toggle_remove": [KEY_X],
    "pause": [KEY_P],
    "submit_mission": [KEY_ENTER],
    "mirror_part": [KEY_Q],
    "colour_variant": [KEY_C],
    "move_part": [KEY_G],
    "zoom_in": [KEY_EQUAL, KEY_KP_ADD],
    "zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
    "pan_left": [KEY_J],
    "pan_right": [KEY_L],
    "pan_up": [KEY_I],
    "pan_down": [KEY_K],
    "recenter": [KEY_HOME],
}

## The actions with Ctrl: undo with Ctrl+Z, redo with Ctrl+Y and Ctrl+Shift+Z.
const CTRL_KEYS := {"undo": [KEY_Z], "redo": [KEY_Y]}


static func ensure_registered() -> void:
    for action in KEYS:
        if InputMap.has_action(action):
            continue
        InputMap.add_action(action)
        for key in KEYS[action]:
            var event := InputEventKey.new()
            event.physical_keycode = key
            InputMap.action_add_event(action, event)
    for action in CTRL_KEYS:
        if InputMap.has_action(action):
            continue
        InputMap.add_action(action)
        for key in CTRL_KEYS[action]:
            var event := InputEventKey.new()
            event.physical_keycode = key
            event.ctrl_pressed = true
            InputMap.action_add_event(action, event)
    var redo := InputEventKey.new()
    redo.physical_keycode = KEY_Z
    redo.ctrl_pressed = true
    redo.shift_pressed = true
    InputMap.action_add_event("redo", redo)


## The keyboard's hook direction in [-1, 1]^2 (x right, y up in the grid).
static func keyboard_axis() -> Vector2:
    return Vector2(
        Input.get_action_strength("hook_right") - Input.get_action_strength("hook_left"),
        Input.get_action_strength("hook_up") - Input.get_action_strength("hook_down")
    )


## The keyboard's camera pan direction in [-1, 1]^2 (screen directions).
static func pan_axis() -> Vector2:
    return Vector2(
        Input.get_action_strength("pan_right") - Input.get_action_strength("pan_left"),
        Input.get_action_strength("pan_down") - Input.get_action_strength("pan_up")
    )
