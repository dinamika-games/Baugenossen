class_name InputActions
extends RefCounted
## Register the few keys of the game. The body plays (see DESIGN.md, 3.1); the
## keyboard only pauses (P), goes back or pauses (Escape; twice quits, see the
## Game autoload). S and M (the effects and the music) belong to the Sounds
## autoload.

const KEYS := {
    "cancel": [KEY_ESCAPE],
    "pause": [KEY_P],
}


static func ensure_registered() -> void:
    for action in KEYS:
        if InputMap.has_action(action):
            continue
        InputMap.add_action(action)
        for key in KEYS[action]:
            var event := InputEventKey.new()
            event.physical_keycode = key
            InputMap.action_add_event(action, event)
