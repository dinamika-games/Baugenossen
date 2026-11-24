extends Node2D
## Build a mission's site with the crane (DESIGN.md, 2 and 3): pick a part in
## the catalogue, move the hook, see the snapped preview and why it is valid or
## not, place, remove, move, undo and redo, watch the checklist, review and
## submit. The keyboard and the mouse always work; the body controls join when
## the player chose them.
##
## The grid, the history and the mission are the truth; the view and the HUD
## only show them.

const KEY_SPEED := 8.0
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

var _context := Placement.Context.new()
var _raw_anchor := Vector2i(-9999, -9999)
var _preview_result: PlacementResult = null
var _autosave_at := -1.0
var _delta := 0.0
var _dwell := DwellSelector.new()
var _walk: ResidentWalk = null
var _revisit := false
var _tutorial: Dictionary = {}
var _hook_travel := 0.0
var _pause_reason := ""
var _dragging := false
var _pose_log: PoseLog = PoseLog.from_args(OS.get_cmdline_user_args())
@onready var _game: Node = get_node("/root/Game")
@onready var _settings: Node = get_node("/root/Settings")


func _ready() -> void:
    content = _game.content
    mission_id = _game.mission_id
    if _game.session.character == null or not content.missions.has(mission_id):
        _game.go("city_map")
        return
    mission = content.mission(mission_id)
    grid = _game.session.open_site(mission_id)
    var character: Character = _game.session.character
    _revisit = character.has_completed(mission_id)
    _context.capacity = Progression.crane_capacity(character)
    _context.unlocked = Progression.unlocked_parts(character, content)
    _context.offered = mission["available_catalogue_ids"]
    if mission.get("tutorial", false):
        _tutorial = {"select": false, "move": false, "place": false, "remove": false, "undo": false}

    dispatcher.command.connect(_on_command)
    dispatcher.state_changed.connect(func(_state: String) -> void: _refresh_status())
    pose.calibration = _settings.get_value("calibration")
    pose.dead_zone = float(_settings.get_value("dead_zone"))
    pose.sensitivity = float(_settings.get_value("sensitivity"))

    RenderingServer.set_default_clear_color(Color("bfe3f2"))
    view = SiteView.new()
    view.grid = grid
    view.high_contrast = bool(_settings.get_value("high_contrast"))
    view.show_guides = "golden_hands" in character.perks
    add_child(view)
    camera = Camera2D.new()
    add_child(camera)
    camera.make_current()
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = BuildHud.new()
    hud.offered = _context.offered
    layer.add_child(hud)
    hud.build(content, character, bool(_settings.get_value("high_contrast")))
    hud.action_requested.connect(func(action: String) -> void: dispatcher.dispatch(action))
    hud.part_clicked.connect(_on_part_clicked)
    hud.set_title(tr(mission["title_key"]))
    overlays = BuildOverlays.new()
    layer.add_child(overlays)
    overlays.build(bool(_settings.get_value("high_contrast")))
    overlays.action_requested.connect(_on_overlay_action)

    hook = Vector2(grid.width / 2.0, grid.height * 0.5)
    _fit_camera()
    _game.ensure_pose()
    if _pose_log != null:
        _pose_log.start("build_site", _log_settings(mission_id))
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.loop("ambience_birds", true, -18.0)
    _evaluate()
    _update_preview(true)
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
    var hook_before := hook
    _process_pose()
    if dispatcher.state == InputDispatcher.BUILD:
        var axis := InputActions.keyboard_axis()
        if axis != Vector2.ZERO:
            dispatcher.dispatch("move_hook", axis * KEY_SPEED)
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
            view.bubble = {
                "text": tr(mission["completion_dialogue_key"]),
                "position": _walk.walkers[0]["position"]
            }
        view.queue_redraw()
    if _autosave_at > 0.0 and Time.get_ticks_msec() / 1000.0 >= _autosave_at:
        _autosave_at = -1.0
        _game.session.save()


func _process_pose() -> void:
    if not _settings.body_controls() or not pose.calibration.has("h"):
        return
    var provider: PoseProvider = _game.pose_provider
    var frame := provider.latest_frame()
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
        _pause_reason = "PAUSE_TRACKING_LOST"
        dispatcher.dispatch("pause")
    if dispatcher.state == InputDispatcher.CATALOGUE:
        var entry := ""
        if pose.cursor.x >= 0.0:
            var rect := hud.catalogue_rect()
            entry = hud.entry_at(rect.position + pose.cursor * rect.size)
        hud.show_dwell(entry, _dwell.point(entry, provider.now()))
    _refresh_status()


## The settings which matter for reading a pose log.
func _log_settings(context: String) -> Dictionary:
    var result := {"context": context}
    for key in [
        "input_source", "gesture_mode", "camera_mirror", "sensitivity", "dead_zone", "calibration"
    ]:
        result[key] = _settings.get_value(key)
    return result


func _on_pose_event(event: String) -> void:
    match event:
        "gesture_started":
            if dispatcher.begin_gesture():
                _refresh_status()
        "gesture_cancelled":
            dispatcher.end_gesture()
        "confirm", "open_catalogue":
            if not dispatcher.end_gesture(event):
                dispatcher.dispatch(event)
        "catalogue_release":
            var chosen := _dwell.selected()
            _dwell.reset()
            hud.show_dwell("", 0.0)
            if chosen != "" and _context.unlocked.has(chosen):
                dispatcher.dispatch("select_part", chosen)
        "resume":
            dispatcher.dispatch("resume")


func _unhandled_input(event: InputEvent) -> void:
    if grid == null:
        return
    if event is InputEventMouseMotion:
        if _dragging:
            dispatcher.dispatch("pan_camera", -event.relative / camera.zoom)
        elif dispatcher.state == InputDispatcher.BUILD:
            var target := view.to_grid(view.get_local_mouse_position())
            if Rect2(Vector2(-1, -1), Vector2(grid.width + 2, grid.height + 2)).has_point(target):
                _set_hook(target)
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
    if dispatcher.state == InputDispatcher.CATALOGUE:
        for step in [["hook_up", -1], ["hook_down", 1]]:
            if event.is_action_pressed(step[0]):
                hud.next_category(step[1])
                hud.focus_catalogue(carried)
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
            "open_catalogue",
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


func _on_part_clicked(part_id: String) -> void:
    if not _context.unlocked.has(part_id):
        _show_locked(part_id)
        return
    if dispatcher.state == InputDispatcher.BUILD or dispatcher.state == InputDispatcher.CATALOGUE:
        dispatcher.dispatch("select_part", part_id)


func _show_locked(part_id: String) -> void:
    var definition := content.part(part_id)
    var missing := Progression.missing_requirements(
        definition.requirements, _game.session.character, content
    )
    var parts: Array[String] = []
    for requirement in missing:
        parts.append(_requirement_text(requirement))
    hud.set_message(
        (
            "🔒 "
            + tr("LOCKED_NEEDS").format(
                {"part": tr(definition.name_key), "needs": ", ".join(parts)}
            )
        ),
        Ui.INK
    )


func _requirement_text(requirement: Dictionary) -> String:
    var name := ""
    match str(requirement["type"]):
        "skill":
            name = tr(content.skills[requirement["id"]]["name_key"])
        "attribute":
            for attribute in content.attributes:
                if attribute["id"] == requirement["id"]:
                    name = tr(attribute["name_key"])
        "level":
            name = tr("SHEET_LEVEL")
        _:
            name = tr("SHEET_ANY_SKILL")
    return tr("REQUIREMENT_LINE").format(
        {"name": name, "minimum": requirement["minimum"], "current": requirement["current"]}
    )


func _on_command(action: String, argument: Variant) -> void:
    match action:
        "move_hook":
            var before := hook
            _set_hook(hook + Vector2(argument) * _delta)
            _hook_travel += before.distance_to(hook)
            if _hook_travel > 3.0:
                _tutorial_step("move")
        "confirm":
            _confirm()
        "cancel":
            moving_id = 0
            if mode != "place":
                mode = "place"
            hud.release_focus_all()
            overlays.hide_all()
            _update_preview(true)
        "open_catalogue":
            _sound("catalogue")
            if dispatcher.state == InputDispatcher.CATALOGUE:
                hud.focus_catalogue(carried)
            else:
                hud.release_focus_all()
        "select_part":
            carried = str(argument)
            mode = "place"
            moving_id = 0
            mirrored = false
            variant = 0
            hud.set_selected(carried)
            _sound("click")
            hud.release_focus_all()
            pose.rearm()
            _tutorial_step("select")
            _update_preview(true)
        "toggle_remove":
            mode = "place" if mode == "remove" else "remove"
            moving_id = 0
            _update_preview(true)
        "undo", "redo":
            var done := history.undo(grid) if action == "undo" else history.redo(grid)
            if done:
                _sound("undo", 1.0 if action == "undo" else 1.15)
                if action == "undo":
                    _tutorial_step("undo")
                _after_edit()
        "pause":
            _game.session.save()
            overlays.show_pause(_pause_reason, _settings.body_controls())
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
    hook = target.clamp(Vector2.ZERO, Vector2(grid.width, grid.height))
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
                    "✗ " + tr("ERROR_PROTECTED" if view.pointed != 0 else "ERROR_NOTHING_THERE"),
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
                _tutorial_step("place")
                _after_edit()


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
    _sound_loop("ambience_birds", false)


func _pick_for_move() -> void:
    var id := grid.pick_at(Vector2i(floori(hook.x), floori(hook.y)))
    if id == 0:
        hud.set_message("✗ " + tr("ERROR_NOTHING_THERE"), Ui.BAD_COLOUR)
        return
    var instance: PartInstance = grid.instances[id]
    if instance.protected:
        hud.set_message("✗ " + tr("ERROR_PROTECTED"), Ui.BAD_COLOUR)
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
    if "colourist" not in _game.session.character.perks:
        hud.set_message(tr("COLOUR_NEEDS_PERK"), Ui.INK)
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
    hud.set_checklist(report)
    var highlighted: Array = []
    for id in report.analysis.support.problem_ids():
        highlighted.append(id)
    view.highlighted = highlighted
    hud.set_history(history.can_undo(), history.can_redo(), mode == "remove")
    _refresh_tutorial()
    view.queue_redraw()


func _highlight_unmet() -> void:
    var highlighted: Array = []
    for result in report.mandatory:
        if not result["satisfied"]:
            highlighted.append_array(result["instances"])
    view.highlighted = highlighted
    view.queue_redraw()


## Snap the carried part to the nearest valid anchor near the hook, and show
## whether (and why not) it can be placed there.
func _update_preview(force: bool) -> void:
    view.remove_mode = mode == "remove"
    view.pointed = 0
    if mode == "remove":
        view.preview = {}
        view.pointed = grid.pick_at(Vector2i(floori(hook.x), floori(hook.y)))
        if view.pointed != 0:
            var definition := grid.definition_of(grid.instances[view.pointed])
            hud.set_message(
                "✓ " + tr("REMOVE_TARGET").format({"part": tr(definition.name_key)}), Ui.OK_COLOUR
            )
        else:
            hud.set_message(tr("REMOVE_HINT"), Ui.INK)
        view.queue_redraw()
        return
    var definition := content.part(carried)
    if definition == null:
        view.preview = {}
        hud.set_message(tr("HINT_OPEN_CATALOGUE"), Ui.INK)
        view.queue_redraw()
        return
    var raw := _raw_anchor_for(definition)
    if raw == _raw_anchor and not force:
        return
    _raw_anchor = raw
    var best := raw
    _preview_result = null
    var first: PlacementResult = null
    for offset in [
        Vector2i(0, 0),
        Vector2i(0, -1),
        Vector2i(-1, 0),
        Vector2i(1, 0),
        Vector2i(0, 1),
        Vector2i(-1, -1),
        Vector2i(1, -1),
        Vector2i(0, -2)
    ]:
        var candidate: Vector2i = raw + offset
        var result := Placement.validate(grid, definition, candidate, mirrored, _context, moving_id)
        if first == null:
            first = result
        if result.ok:
            best = candidate
            _preview_result = result
            break
    if _preview_result == null:
        _preview_result = first
    view.pointed = moving_id
    view.preview = {
        "definition": definition,
        "anchor": best,
        "mirrored": mirrored,
        "variant": variant,
        "ok": _preview_result.ok,
    }
    _show_preview_message(definition)
    view.queue_redraw()


## The anchor under the hook: the hook's tip is the middle of the part's
## bottom (or of the edge), so a part lands on the floor at the hook's height.
func _raw_anchor_for(definition: PartDef) -> Vector2i:
    var size := definition.footprint
    match definition.layer:
        "edge_v":
            return Vector2i(roundi(hook.x), roundi(hook.y))
        _:
            return Vector2i(roundi(hook.x - size.x / 2.0), roundi(hook.y))


func _show_preview_message(definition: PartDef) -> void:
    var name: String = tr(definition.name_key)
    if _preview_result.ok:
        var text := "✓ " + tr("PREVIEW_VALID").format({"part": name})
        if _preview_result.warning_key != "":
            text += "  ⚠ " + tr(_preview_result.warning_key)
        hud.set_message(text, Ui.OK_COLOUR)
    else:
        var params := _preview_result.params.duplicate()
        params["part"] = name
        hud.set_message("✗ " + tr(_preview_result.reason_key).format(params), Ui.BAD_COLOUR)


func _refresh_status() -> void:
    if hud == null:
        return
    var tool := ""
    match mode:
        "remove":
            tool = tr("TOOL_REMOVE")
        "move":
            tool = tr("TOOL_MOVE").format({"part": tr(content.part(carried).name_key)})
        _:
            tool = tr("TOOL_PLACE").format(
                {"part": tr(content.part(carried).name_key) if carried != "" else "—"}
            )
    hud.set_tool(tool)
    var source := tr("INPUT_KEYBOARD")
    if _settings.body_controls():
        var tracking := {"ok": "TRACKING_OK", "frozen": "TRACKING_FROZEN", "lost": "TRACKING_LOST"}
        source = tr("INPUT_BODY").format({"tracking": tr(tracking[pose.tracking])})
        if not pose.calibration.has("h"):
            source = tr("INPUT_BODY_UNCALIBRATED")
    hud.set_status("%s · %s" % [source, tr("STATE_" + dispatcher.state)])
    hud.set_history(history.can_undo(), history.can_redo(), mode == "remove")


func _tutorial_step(step: String) -> void:
    if _tutorial.has(step) and not _tutorial[step]:
        _tutorial[step] = true
        _refresh_tutorial()


func _refresh_tutorial() -> void:
    if _tutorial.is_empty():
        hud.set_tutorial("")
        return
    var lines: Array[String] = [tr("TUTORIAL_TITLE")]
    for step in ["select", "move", "place", "remove", "undo"]:
        lines.append(("✓ " if _tutorial[step] else "○ ") + tr("TUTORIAL_" + step.to_upper()))
    hud.set_tutorial("\n".join(lines))


func _recentre() -> void:
    var frame: Dictionary = _game.pose_provider.latest_frame()
    if frame.is_empty() or not pose.calibration.has("h"):
        return
    pose.calibration = PoseCalibration.recentre(pose.calibration, PoseMeasure.measure(frame))
    _settings.set_value("calibration", pose.calibration)
    pose.rearm()


func _on_overlay_action(action: String) -> void:
    match action:
        "resume":
            dispatcher.dispatch("resume")
        "recentre":
            _recentre()
        "calibrate":
            _game.session.save()
            _game.return_screen = "build_site"
            _game.go("calibration")
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
        tr("COMPLETE_THANKS").format(
            {"names": names, "thanks": tr(mission["completion_dialogue_key"])}
        )
    )
