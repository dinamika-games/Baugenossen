extends Node2D
## Build a mission's site with the crane (DESIGN.md, 2 and 3): five blocks
## wait in a row (see [BlockQueue]); the player picks one with a short dip,
## leans to move the hook, sees where the block lands, and places it with a
## push-up. Only the body plays: the hook, the choice and the placing. The
## keyboard and the mouse of a helper do the rest (undo, remove, review,
## pause), never the hook; without a camera, the site asks for it.
##
## The grid, the history and the mission are the truth; the view and the HUD
## only show them.

const AUTOSAVE_DELAY := 2.0
const PAN_SPEED := 700.0

var content: ContentDb
var mission: Dictionary
var mission_id := ""
var grid: WorldGrid
var history := CommandHistory.new()
var dispatcher := InputDispatcher.new()
var pose := PoseController.new()
var view: SiteView
var camera: Camera2D
var hud: BuildHud
var overlays: BuildOverlays

## The part the hook carries, and how.
var carried := ""
var mirrored := false
var variant := 0
## "place", "remove" or "move".
var mode := "place"
var moving_id := 0
var hook := Vector2(4, 8)
var report: MissionEvaluator.Report
## The row of blocks to choose from, and the chosen one.
var queue: BlockQueue
var slot := 0

var _context := Placement.Context.new()
var _preview_key := Vector3i(-9999, -9999, 0)
var _preview_result: PlacementResult = null
var _autosave_at := -1.0
var _delta := 0.0
var _walk: ResidentWalk = null
var _revisit := false
var _tutorial: Dictionary = {}
var _hook_travel := 0.0
var _pause_reason := ""
var _dragging := false
## Whether the body was tracked in this visit: only then a loss pauses.
var _body_seen := false
## What the site waits for before the hook can move: "" or "camera".
var _waiting := ""
## Calibrates the body controls by itself while the player holds still.
var _auto_calibration := AutoCalibration.new()
var _pose_log: PoseLog = PoseLog.from_args(OS.get_cmdline_user_args())
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    content = _game.content
    mission_id = _game.mission_id
    if _game.session.progress == null or not content.missions.has(mission_id):
        _game.go("city_map")
        return
    mission = content.mission(mission_id)
    grid = _game.session.open_site(mission_id)
    _revisit = _game.session.progress.has_completed(mission_id)
    _context.offered = mission["available_catalogue_ids"]
    queue = BlockQueue.new(content, _context.offered)
    if mission.get("tutorial", false):
        _tutorial = {"select": false, "move": false, "place": false}

    dispatcher.command.connect(_on_command)
    dispatcher.state_changed.connect(func(_state: String) -> void: _refresh_status())
    # NOTE (mristin):
    # Every visit calibrates anew: the player may be on the knees today and
    # in the plank tomorrow.
    pose.calibration = {}
    pose.dead_zone = float(_settings.get_value("dead_zone"))
    pose.sensitivity = float(_settings.get_value("sensitivity"))
    pose.hand_gestures = false

    RenderingServer.set_default_clear_color(Color("bfe3f2"))
    view = SiteView.new()
    view.grid = grid
    view.high_contrast = bool(_settings.get_value("high_contrast"))
    view.show_guides = true
    add_child(view)
    camera = Camera2D.new()
    add_child(camera)
    camera.make_current()
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = BuildHud.new()
    layer.add_child(hud)
    hud.build(content, bool(_settings.get_value("high_contrast")))
    hud.action_requested.connect(func(action: String) -> void: dispatcher.dispatch(action))
    hud.slot_clicked.connect(func(index: int) -> void: dispatcher.dispatch("select_slot", index))
    hud.set_title(tr(mission["title"]))
    overlays = BuildOverlays.new()
    layer.add_child(overlays)
    overlays.build(bool(_settings.get_value("high_contrast")))
    overlays.action_requested.connect(_on_overlay_action)

    hook = Vector2(grid.width / 2.0, grid.height)
    _fit_camera()
    _game.ensure_pose()
    if _pose_log != null:
        _pose_log.start("build_site", _log_settings(mission_id))
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.loop("ambience_birds", true, -18.0)
    _evaluate()
    _choose_slot(0)
    _refresh_status()
    get_viewport().size_changed.connect(_fit_camera)


func _fit_camera() -> void:
    var viewport := get_viewport_rect().size
    var available := viewport - Vector2(340, 64 + 176)
    var site := view.site_size() + Vector2(SiteView.CELL * 4, SiteView.CELL * 6)
    var zoom := clampf(minf(available.x / site.x, available.y / site.y), 0.3, 2.0)
    camera.zoom = Vector2(zoom, zoom)
    var centre := view.site_size() / 2.0 + Vector2(SiteView.CELL, -SiteView.CELL)
    camera.position = centre + Vector2(340 / 2.0, (176 - 64) / 2.0) / zoom


func _process(delta: float) -> void:
    if grid == null:
        return
    _delta = delta
    dispatcher.tick()
    if dispatcher.state == InputDispatcher.BUILD and get_viewport().gui_get_focus_owner() != null:
        # NOTE (mristin):
        # A clicked button keeps the focus, and would take Space from the
        # placing; while building, nothing in the HUD holds the focus.
        hud.release_focus_all()
    var hand_cursor := get_node_or_null("/root/HandCursor")
    if hand_cursor != null:
        # NOTE (mristin):
        # While building, the raised hands are the gestures of the crane.
        hand_cursor.enabled = (
            dispatcher.state
            in [InputDispatcher.PAUSED, InputDispatcher.REVIEW, InputDispatcher.COMPLETE]
        )
    var hook_before := hook
    _check_body()
    _process_pose()
    _advance_queue(delta)
    _sound_loop("crane", hook.distance_to(hook_before) > 0.001)
    var pan := InputActions.pan_axis()
    if pan != Vector2.ZERO:
        dispatcher.dispatch("pan_camera", pan * PAN_SPEED * delta)
    if _walk != null:
        var arrived := _walk.update(delta, bool(_settings.get_value("reduced_motion")))
        view.residents.clear()
        for walker in _walk.walkers:
            view.residents.append(walker)
        if arrived and view.bubble.is_empty() and not _walk.walkers.is_empty():
            view.bubble = {"text": tr(mission["thanks"]), "position": _walk.walkers[0]["position"]}
        view.queue_redraw()
    if _autosave_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _autosave_at:
        _autosave_at = -1.0
        _game.session.save()


## Let the row of blocks move on while the player builds: the oldest block
## leaves now and then (first in, first out).
func _advance_queue(delta: float) -> void:
    if dispatcher.state != InputDispatcher.BUILD or not pose.calibration.has("h"):
        return
    if queue.advance(delta):
        # NOTE (mristin):
        # The chosen block moves one place to the front with the row; if it
        # was the oldest, it left, and the new oldest is chosen.
        _choose_slot(maxi(slot - 1, 0))
    hud.set_queue(queue.slots, slot, queue.progress)


## Choose the block of the row, if the hook carries a new block.
func _choose_slot(index: int) -> void:
    slot = posmod(index, queue.slots.size())
    if mode == "place" and moving_id == 0:
        carried = queue.slots[slot]
        mirrored = false
        variant = 0
    hud.set_queue(queue.slots, slot, queue.progress)
    _update_preview(true)


## Ask for the camera while the body can not move the hook.
func _check_body() -> void:
    if dispatcher.state == InputDispatcher.COMPLETE:
        return
    var provider: PoseProvider = _game.pose_provider
    var waiting := ""
    if provider.status() in ["off", "failed"]:
        waiting = "camera"
    if waiting == _waiting:
        return
    _waiting = waiting
    if waiting == "":
        if dispatcher.state == InputDispatcher.PAUSED:
            dispatcher.dispatch("resume")
        return
    if dispatcher.state != InputDispatcher.PAUSED:
        dispatcher.dispatch("pause")
    overlays.show_needs_body(waiting, provider.status_message())


func _process_pose() -> void:
    if _game.pose_provider.status() != "running":
        return
    var provider: PoseProvider = _game.pose_provider
    var frame := provider.latest_frame()
    if not pose.calibration.has("h"):
        _auto_calibrate(provider, frame)
        return
    var state_before := dispatcher.state
    var output := pose.update(frame, provider.now(), dispatcher.state)
    for event in output["events"]:
        _on_pose_event(event)
    if _pose_log != null:
        var fields := PoseLog.controller_fields(pose, output["velocity"])
        fields["screen"] = "build_site"
        fields["state"] = state_before
        fields["state_after"] = dispatcher.state
        fields["hook"] = [snappedf(hook.x, 0.01), snappedf(hook.y, 0.01)]
        _pose_log.sample(provider.now(), frame, fields, output["events"])
    if dispatcher.state == InputDispatcher.BUILD and output["velocity"] != Vector2.ZERO:
        dispatcher.dispatch("move_hook", output["velocity"])
    if (
        pose.tracking == "lost"
        and (
            dispatcher.state
            in [InputDispatcher.BUILD, InputDispatcher.CATALOGUE, InputDispatcher.GESTURE_PENDING]
        )
    ):
        if _body_seen:
            _pause_reason = "PAUSE_TRACKING_LOST"
            dispatcher.dispatch("pause")
    if pose.tracking == "ok":
        _body_seen = true
    _refresh_status()


## The settings which matter for reading a pose log.
func _log_settings(context: String) -> Dictionary:
    var result := {"context": context}
    for key in ["camera_mirror", "sensitivity", "dead_zone"]:
        result[key] = _settings.get_value(key)
    return result


func _on_pose_event(event: String) -> void:
    match event:
        "gesture_started":
            if dispatcher.begin_gesture():
                _refresh_status()
        "gesture_cancelled":
            dispatcher.end_gesture()
        "level":
            dispatcher.dispatch("next_block")
        "confirm":
            if not dispatcher.end_gesture(event):
                dispatcher.dispatch(event)
        "resume":
            dispatcher.dispatch("resume")


func _unhandled_input(event: InputEvent) -> void:
    if grid == null:
        return
    if event is InputEventMouseMotion:
        if _dragging:
            dispatcher.dispatch("pan_camera", -event.relative / camera.zoom)
        return
    if event is InputEventMouseButton and event.pressed:
        match event.button_index:
            MOUSE_BUTTON_LEFT:
                dispatcher.dispatch("confirm")
            MOUSE_BUTTON_RIGHT:
                _on_cancel_key()
            MOUSE_BUTTON_WHEEL_UP:
                dispatcher.dispatch("zoom_camera", 1.1)
            MOUSE_BUTTON_WHEEL_DOWN:
                dispatcher.dispatch("zoom_camera", 1.0 / 1.1)
            MOUSE_BUTTON_MIDDLE:
                _dragging = true
        return
    if (
        event is InputEventMouseButton
        and not event.pressed
        and event.button_index == MOUSE_BUTTON_MIDDLE
    ):
        _dragging = false
        return
    _handle_key(event)


func _handle_key(event: InputEvent) -> void:
    if dispatcher.state == InputDispatcher.BUILD:
        for step in [["catalogue_previous", "previous_block"], ["catalogue_next", "next_block"]]:
            if event.is_action_pressed(step[0]):
                dispatcher.dispatch(step[1])
                get_viewport().set_input_as_handled()
                return
    if event.is_action_pressed("undo", false, true):
        dispatcher.dispatch("undo")
    elif event.is_action_pressed("redo", false, true):
        dispatcher.dispatch("redo")
    elif event.is_action_pressed("cancel"):
        _on_cancel_key()
    else:
        for action in [
            "confirm",
            "toggle_remove",
            "submit_mission",
            "mirror_part",
            "colour_variant",
            "move_part"
        ]:
            if event.is_action_pressed(action, false, true):
                dispatcher.dispatch(action)
                get_viewport().set_input_as_handled()
                return
        if event.is_action_pressed("pause"):
            dispatcher.dispatch("resume" if dispatcher.state == InputDispatcher.PAUSED else "pause")
        elif event.is_action_pressed("zoom_in"):
            dispatcher.dispatch("zoom_camera", 1.2)
        elif event.is_action_pressed("zoom_out"):
            dispatcher.dispatch("zoom_camera", 1.0 / 1.2)
        elif event.is_action_pressed("recenter"):
            _recentre()
        else:
            return
    get_viewport().set_input_as_handled()


func _on_cancel_key() -> void:
    match dispatcher.state:
        InputDispatcher.PAUSED:
            dispatcher.dispatch("resume")
        InputDispatcher.BUILD:
            if mode != "place" or moving_id != 0:
                dispatcher.dispatch("cancel")
            else:
                dispatcher.dispatch("pause")
        _:
            dispatcher.dispatch("cancel")


func _on_command(action: String, argument: Variant) -> void:
    match action:
        "move_hook":
            var before := hook
            # NOTE (mristin):
            # The hook moves only sideways; the part drops onto a level.
            _set_hook(Vector2(hook.x + Vector2(argument).x * _delta, grid.height))
            _hook_travel += before.distance_to(hook)
            if _hook_travel > 3.0:
                _tutorial_step("move")
        "confirm":
            _confirm()
        "next_block", "previous_block", "select_slot":
            var index := slot + (1 if action == "next_block" else -1)
            if action == "select_slot":
                index = int(argument)
            mode = "place"
            moving_id = 0
            _choose_slot(index)
            _sound("click")
            _tutorial_step("select")
        "cancel":
            moving_id = 0
            if mode != "place":
                mode = "place"
            hud.release_focus_all()
            overlays.hide_all()
            _choose_slot(slot)
        "toggle_remove":
            mode = "place" if mode == "remove" else "remove"
            moving_id = 0
            _choose_slot(slot)
        "undo", "redo":
            var done := history.undo(grid) if action == "undo" else history.redo(grid)
            if done:
                _sound("undo", 1.0 if action == "undo" else 1.15)
                if action == "undo":
                    _tutorial_step("undo")
                _after_edit()
        "pause":
            _game.session.save()
            if _waiting == "":
                overlays.show_pause(_pause_reason, _game.body_ready())
            _pause_reason = ""
        "resume":
            overlays.hide_all()
            pose.rearm()
        "submit_mission":
            _evaluate()
            overlays.show_review(report, _revisit)
            _highlight_unmet()
        "mirror_part":
            var definition := content.part(carried)
            if definition != null and definition.can_mirror():
                mirrored = not mirrored
                _update_preview(true)
        "colour_variant":
            _cycle_colour()
        "move_part":
            _pick_for_move()
        "zoom_camera":
            camera.zoom = (camera.zoom * float(argument)).clamp(Vector2(0.25, 0.25), Vector2(3, 3))
        "pan_camera":
            camera.position += Vector2(argument) / camera.zoom.x
    _refresh_status()


func _set_hook(target: Vector2) -> void:
    hook = Vector2(clampf(target.x, 0.0, grid.width), grid.height)
    view.hook = hook
    _update_preview(false)
    _follow_hook()


func _follow_hook() -> void:
    var screen := get_viewport().get_canvas_transform() * view.to_screen(hook)
    var size := get_viewport_rect().size
    var margin := Rect2(Vector2(80, 100), size - Vector2(80 + 360, 100 + 220))
    if not margin.has_point(screen):
        var shift := screen - screen.clamp(margin.position, margin.end)
        camera.position += shift / camera.zoom.x


func _confirm() -> void:
    match mode:
        "remove":
            var command := Placement.remove_command(grid, view.pointed)
            if command == null:
                hud.set_message(
                    (
                        "✗ "
                        + Texts.of(
                            "ERROR_PROTECTED" if view.pointed != 0 else "ERROR_NOTHING_THERE"
                        )
                    ),
                    Ui.BAD_COLOUR
                )
                _sound("invalid")
                return
            if history.execute(command, grid):
                _sound("remove", randf_range(0.95, 1.05))
                _tutorial_step("remove")
                _after_edit()
        _:
            if _preview_result == null or not _preview_result.ok:
                _sound("invalid")
                return
            var anchor: Vector2i = view.preview["anchor"]
            var command: EditCommand
            if moving_id != 0:
                command = Placement.move_command(grid, moving_id, anchor, mirrored, _context)
            else:
                command = Placement.place_command(
                    grid, content.part(carried), anchor, mirrored, variant, _context
                )
            if history.execute(command, grid):
                _sound(_place_sound(content.part(carried)), randf_range(0.95, 1.05))
                if moving_id != 0:
                    moving_id = 0
                    mode = "place"
                else:
                    # NOTE (mristin):
                    # The placed block leaves the row; a new one comes at
                    # the end, and the chosen place now holds the next block.
                    queue.take(slot)
                _tutorial_step("place")
                _after_edit()
                _choose_slot(slot)


## The effect of placing a part: by its material and kind.
static func _place_sound(definition: PartDef) -> String:
    if definition.category_id == "nature":
        return "place_plant"
    match definition.material_id:
        "stone":
            return "place_stone"
        "steel", "glass":
            return "place_metal"
    return "place_wood"


func _sound(name: String, pitch := 1.0) -> void:
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.play(name, pitch)


func _sound_loop(name: String, on: bool) -> void:
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.loop(name, on)


func _exit_tree() -> void:
    _sound_loop("crane", false)
    var hand_cursor := get_node_or_null("/root/HandCursor")
    if hand_cursor != null:
        hand_cursor.enabled = true
    _sound_loop("ambience_birds", false)


func _pick_for_move() -> void:
    var column := column_parts()
    var id := column[0] if not column.is_empty() else 0
    if id == 0:
        hud.set_message("✗ " + Texts.of("ERROR_NOTHING_THERE"), Ui.BAD_COLOUR)
        return
    var instance: PartInstance = grid.instances[id]
    if instance.protected:
        hud.set_message("✗ " + Texts.of("ERROR_PROTECTED"), Ui.BAD_COLOUR)
        return
    moving_id = id
    mode = "move"
    carried = instance.definition_id
    mirrored = instance.mirrored
    variant = instance.colour_variant
    _update_preview(true)


func _cycle_colour() -> void:
    var definition := content.part(carried)
    if definition == null:
        return
    variant = (variant + 1) % definition.colour_variants
    _update_preview(true)


func _after_edit() -> void:
    _game.session.store_site(mission_id, grid)
    _autosave_at = Time.get_ticks_msec() / 1000.0 + AUTOSAVE_DELAY
    _evaluate()
    _update_preview(true)


func _evaluate() -> void:
    report = MissionEvaluator.evaluate(mission, grid)
    queue.wanted_tags = wanted_tags(mission, report)
    hud.set_checklist(report)
    var highlighted: Array = []
    for id in report.analysis.support.problem_ids():
        highlighted.append(id)
    view.highlighted = highlighted
    hud.set_history(history.can_undo(), history.can_redo(), mode == "remove")
    _refresh_tutorial()
    view.queue_redraw()


## The tags which the unmet objectives of the mission ask for (as keys), so
## that the row brings their parts more often.
static func wanted_tags(of_mission: Dictionary, of_report: MissionEvaluator.Report) -> Dictionary:
    var unmet := {}
    for result in of_report.mandatory + of_report.optional:
        if not result["satisfied"]:
            unmet[str(result["id"])] = true
    var tags := {}
    for objective in of_mission["mandatory_objectives"] + of_mission["optional_objectives"]:
        if unmet.has(str(objective["id"])):
            _collect_tags(objective, tags)
    return tags


static func _collect_tags(objective: Dictionary, tags: Dictionary) -> void:
    if objective.has("tag"):
        tags[str(objective["tag"])] = true
    for tag in objective.get("tags", []):
        tags[str(tag)] = true
    for nested in objective.get("requirements", []) + objective.get("objectives", []):
        if nested is Dictionary:
            _collect_tags(nested, tags)


func _highlight_unmet() -> void:
    var highlighted: Array = []
    for result in report.mandatory:
        if not result["satisfied"]:
            highlighted.append_array(result["instances"])
    view.highlighted = highlighted
    view.queue_redraw()


## Drop the carried block from the hook: it lands at the first height, from
## the top down, at which it can be placed in the column under the hook. The
## preview shows where, with why it is valid or not. The remove tool points at
## the top part of the column the same way.
func _update_preview(force: bool) -> void:
    view.remove_mode = mode == "remove"
    view.pointed = 0
    if mode == "remove":
        view.preview = {}
        var column := column_parts()
        if not column.is_empty():
            view.pointed = column[0]
            var pointed := grid.definition_of(grid.instances[view.pointed])
            hud.set_message(
                (
                    "✓ "
                    + Grammar.format(
                        tr("Remove {part}: dip down, or press Space."), {"part": tr(pointed.name)}
                    )
                ),
                Ui.OK_COLOUR
            )
        else:
            hud.set_message(tr("Move the hook over a part to remove it."), Ui.INK)
        view.queue_redraw()
        return
    var definition := content.part(carried)
    if definition == null:
        view.preview = {}
        hud.set_message(
            tr("Choose a block in the row below: a short dip takes the next one."), Ui.INK
        )
        view.queue_redraw()
        return
    var x := _column_anchor_x(definition)
    var key := Vector3i(x, slot, moving_id)
    if key == _preview_key and not force:
        return
    _preview_key = key
    var levels := landing_levels(definition, x)
    var anchor := Vector2i(x, grid.height - maxi(definition.footprint.y, 1))
    if levels.is_empty():
        _preview_result = Placement.validate(
            grid, definition, anchor, mirrored, _context, moving_id
        )
        if _preview_result.reason_key not in ["ERROR_NOT_OFFERED", "ERROR_OVERWEIGHT"]:
            _preview_result = PlacementResult.invalid("ERROR_NO_LANDING")
    else:
        anchor = levels[0]
        _preview_result = Placement.validate(
            grid, definition, anchor, mirrored, _context, moving_id
        )
    view.pointed = moving_id
    view.preview = {
        "definition": definition,
        "anchor": anchor,
        "mirrored": mirrored,
        "variant": variant,
        "ok": _preview_result.ok,
    }
    _show_preview_message(definition)
    view.queue_redraw()


## The anchor column of the part under the hook.
func _column_anchor_x(definition: PartDef) -> int:
    if definition.layer == "edge_v":
        return roundi(hook.x)
    return roundi(hook.x - definition.footprint.x / 2.0)


## The anchor at which the part lands in the column: the first, from the top
## down, at which it can be placed; empty if there is none.
func landing_levels(definition: PartDef, x: int) -> Array[Vector2i]:
    var levels: Array[Vector2i] = []
    for y in range(grid.height, -1, -1):
        var anchor := Vector2i(x, y)
        if Placement.validate(grid, definition, anchor, mirrored, _context, moving_id).ok:
            levels.append(anchor)
            break
    return levels


## The parts in the column under the hook, from the top down (for the remove
## and the move tool).
func column_parts() -> Array[int]:
    var x := floori(hook.x)
    var found: Array[int] = []
    for id in grid.sorted_ids():
        var instance: PartInstance = grid.instances[id]
        if instance.protected:
            continue
        var vertical := grid.definition_of(instance).layer == "edge_v"
        for slot in grid.slots_of(instance):
            if slot.x == x or (vertical and slot.x == x + 1):
                found.append(id)
                break
    found.sort_custom(_higher)
    return found


func _higher(a: int, b: int) -> bool:
    return grid.top_of(grid.instances[a]) > grid.top_of(grid.instances[b])


func _show_preview_message(definition: PartDef) -> void:
    var name: String = tr(definition.name)
    if _preview_result.ok:
        var text := (
            "✓ "
            + Grammar.format(tr("{part} lands here: do a push-up to place it."), {"part": name})
        )
        if _preview_result.warning_key != "":
            text += "  ⚠ " + Texts.of(_preview_result.warning_key)
        hud.set_message(text, Ui.OK_COLOUR)
    else:
        var params := _preview_result.params.duplicate()
        params["part"] = name
        hud.set_message(
            "✗ " + Grammar.format(Texts.of(_preview_result.reason_key), params), Ui.BAD_COLOUR
        )


func _refresh_status() -> void:
    if hud == null:
        return
    var tool := ""
    match mode:
        "remove":
            tool = tr("Removing")
        "move":
            tool = Grammar.format(tr("Moving: {part}"), {"part": tr(content.part(carried).name)})
        _:
            tool = Grammar.format(
                tr("Carrying: {part}"),
                {"part": tr(content.part(carried).name) if carried != "" else "—"}
            )
    hud.set_tool(tool)
    var tracking := {"ok": "TRACKING_OK", "frozen": "TRACKING_FROZEN", "lost": "TRACKING_LOST"}
    var source := Grammar.format(
        tr("Body: {tracking}"), {"tracking": Texts.of(tracking[pose.tracking])}
    )
    match _game.pose_provider.status():
        "starting":
            source = tr("Starting the camera…")
        "off", "failed":
            source = tr("No camera")
    if not pose.calibration.has("h") and _game.pose_provider.status() == "running":
        source = tr("Body: hold still…")
    hud.set_status("%s · %s" % [source, Texts.of("STATE_" + dispatcher.state)])
    hud.set_history(history.can_undo(), history.can_redo(), mode == "remove")


func _tutorial_step(step: String) -> void:
    if _tutorial.has(step) and not _tutorial[step]:
        _tutorial[step] = true
        _refresh_tutorial()


func _refresh_tutorial() -> void:
    if _tutorial.is_empty():
        hud.set_tutorial("")
        return
    var lines: Array[String] = [Texts.of("TUTORIAL_TITLE")]
    for step in ["select", "move", "place"]:
        lines.append(("✓ " if _tutorial[step] else "○ ") + Texts.of("TUTORIAL_" + step.to_upper()))
    hud.set_tutorial("\n".join(lines))


## Calibrate anew: the next posture the player holds still becomes neutral.
func _recentre() -> void:
    pose.calibration = {}
    _auto_calibration.reset()
    _body_seen = false
    pose.rearm()


## Learn the neutral posture while the player holds still; the hook waits.
func _auto_calibrate(provider: PoseProvider, frame: Dictionary) -> void:
    var measures := {}
    var fresh := not frame.is_empty() and provider.now() - float(frame["timestamp"]) <= 0.25
    if fresh and PoseMeasure.confident(frame, pose.min_confidence):
        measures = PoseMeasure.measure(frame)
    var calibration := _auto_calibration.feed(measures, provider.now())
    hud.set_message(
        Texts.of("AUTO_CALIBRATING" if not measures.is_empty() else "AUTO_CALIBRATING_NOT_SEEN"),
        Ui.INK
    )
    var events: Array = []
    if not calibration.is_empty():
        pose.calibration = calibration
        pose.rearm()
        events.append("auto_calibrated")
        _refresh_status()
        _update_preview(true)
    if _pose_log != null:
        var fields := {"screen": "build_site", "state": dispatcher.state, "tracking": "calibrating"}
        fields["feedback"] = _auto_calibration.feedback
        var logged := {}
        for key in ["unit", "h", "v", "lift_left", "lift_right"]:
            if measures.has(key):
                logged[key] = snappedf(float(measures[key]), 0.001)
        fields["m"] = logged
        if not calibration.is_empty():
            fields["calibration"] = calibration
        _pose_log.sample(provider.now(), frame, fields, events)


func _on_overlay_action(action: String) -> void:
    match action:
        "resume":
            dispatcher.dispatch("resume")
        "recentre":
            _recentre()
        "leave":
            _game.session.store_site(mission_id, grid)
            _game.session.save()
            _game.go("city_map")
        "quit":
            _game.session.store_site(mission_id, grid)
            _game.quit()
        "cancel":
            dispatcher.dispatch("cancel")
            _evaluate()
        "complete":
            _submit()
        "results":
            _game.go("mission_results")


func _submit() -> void:
    var summary: Dictionary = _game.session.submit(mission_id, grid)
    if not summary.get("submitted", false):
        return
    _game.last_summary = summary
    dispatcher.set_state(InputDispatcher.COMPLETE)
    overlays.hide_all()
    view.preview = {}
    view.highlighted = []
    _walk = ResidentWalk.start(grid, report.analysis, mission, content)
    _sound("cheer")
    var names := MissionText.requesters(mission, content)
    overlays.show_completion(
        Grammar.format(tr("{names}: “{thanks}”"), {"names": names, "thanks": tr(mission["thanks"])})
    )
