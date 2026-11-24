class_name InputDispatcher
extends RefCounted
## Turn the keyboard, the mouse and the body into the same semantic commands,
## and filter them by the input state (DESIGN.md, 3.1 and 3.4).
##
## The commands: "move_hook" (with a velocity), "select_part" (with an ID),
## "confirm", "cancel", "open_catalogue", "toggle_remove", "undo", "redo",
## "pause", "resume", "pan_camera", "zoom_camera", "submit_mission", and the
## build helpers "mirror_part", "colour_variant" and "move_part".
##
## Only BUILD accepts the movement and the construction commits; REVIEW is
## read-only until the player returns to editing. All sources go through
## [method dispatch], and at most one "confirm" passes per tick, so a keyboard
## and a gesture confirming at once place only one part.

signal command(action: String, argument: Variant)
signal state_changed(state: String)

const CALIBRATION := "CALIBRATION"
const BUILD := "BUILD"
const CATALOGUE := "CATALOGUE"
const GESTURE_PENDING := "GESTURE_PENDING"
const PAUSED := "PAUSED"
const REVIEW := "REVIEW"
const COMPLETE := "COMPLETE"

## The commands each state accepts.
const ACCEPTED := {
    BUILD:
    [
        "move_hook",
        "confirm",
        "cancel",
        "open_catalogue",
        "toggle_remove",
        "undo",
        "redo",
        "pause",
        "pan_camera",
        "zoom_camera",
        "submit_mission",
        "select_part",
        "mirror_part",
        "colour_variant",
        "move_part",
    ],
    CATALOGUE: ["select_part", "cancel", "open_catalogue", "pause", "pan_camera", "zoom_camera"],
    GESTURE_PENDING: ["cancel", "pause"],
    PAUSED: ["resume"],
    REVIEW: ["cancel", "resume", "submit_mission", "pause", "pan_camera", "zoom_camera"],
    COMPLETE: [],
    CALIBRATION: ["cancel", "pause"],
}

var state := BUILD
var _state_before_pause := BUILD
var _confirmed_this_tick := false


func set_state(new_state: String) -> void:
    if new_state == state:
        return
    state = new_state
    state_changed.emit(state)


## Start a new tick (call once per frame, before the sources dispatch).
func tick() -> void:
    _confirmed_this_tick = false


func accepts(action: String) -> bool:
    return action in ACCEPTED.get(state, [])


## Pass a command from any source; return whether it was accepted.
func dispatch(action: String, argument: Variant = null) -> bool:
    if not accepts(action):
        return false
    if action == "confirm":
        if _confirmed_this_tick:
            return false
        _confirmed_this_tick = true
    match action:
        "pause":
            _state_before_pause = state if state != GESTURE_PENDING else BUILD
            set_state(PAUSED)
        "resume":
            set_state(_state_before_pause if _state_before_pause != PAUSED else BUILD)
        "open_catalogue":
            set_state(CATALOGUE if state == BUILD else BUILD)
        "select_part":
            if state == CATALOGUE:
                set_state(BUILD)
        "cancel":
            if state in [CATALOGUE, GESTURE_PENDING, REVIEW]:
                set_state(BUILD)
        "submit_mission":
            if state == BUILD:
                set_state(REVIEW)
    command.emit(action, argument)
    return true


## Enter GESTURE_PENDING from BUILD while a hand lift is being recognized.
func begin_gesture() -> bool:
    if state != BUILD:
        return false
    set_state(GESTURE_PENDING)
    return true


## Leave GESTURE_PENDING; a recognized gesture dispatches its command in BUILD.
func end_gesture(action := "") -> bool:
    if state != GESTURE_PENDING:
        return false
    set_state(BUILD)
    if action != "":
        return dispatch(action)
    return false
