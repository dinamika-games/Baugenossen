extends Node2D
## Build a mission's site with the crane, seen from the side (DESIGN.md, 2
## and 3). The blocks wait in the yard left of the site (see [BlockQueue]),
## with a skip for the blocks not wanted. The player leans to move the hook
## sideways, and the height of their body is the height of the hook: straight
## arms hold it at the top, the bottom of a push-up brings it to the ground.
## Lowered onto a block, the empty hook grabs it (in the yard, or a placed one,
## to put it elsewhere); lowered until its block sits on something, the hook
## puts the block there. Once the needs are met, a bell right of the site
## hands the building over when the hook rings it. Only the body plays; the
## keyboard only pauses. Without a camera, the site asks for it.
##
## The grid, the history and the mission are the truth; the view and the HUD
## only show them.

const AUTOSAVE_DELAY := 2.0
## The yard: each place is this wide, in cells; the blocks stand this high.
const SLOT_WIDTH := 3.0
const ITEM_TOP := 2.0
const SKIP_TOP := 1.0
## The hook acts when it is this close above what is below it, in cells.
const TOUCH := 0.3
## After an action, the hook must rise this far before the next one.
const REARM := 1.5
## How fast the hook follows the body up and down, in cells a second.
const HOOK_SPEED_Y := 30.0
## The top of the hook's way lies this far above the site.
const ABOVE_SITE := 1.0

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

## The part the hook carries ("" for the empty hook), and how.
var carried := ""
var mirrored := false
var variant := 0
## The hook in cells (x along the site, y up from the ground).
var hook := Vector2(4, 8)
var report: MissionEvaluator.Report
## The blocks in the yard.
var queue: BlockQueue
## What the hook would touch below it now: {"kind": "yard" (with "index"),
## "part" (with "id"), "bell", "skip", "place" or "blocked" (with "anchor" and
## "result"), or "none"}.
var touch: Dictionary = {"kind": "none"}
## The lowest the hook can go where it is.
var hook_floor := 0.0

var _context := Placement.Context.new()
## After an action, the hook acts again only once it rose above this height.
var _rearm_y := -INF
var _armed := true
var _autosave_at := -1.0
var _delta := 0.0
var _walk: ResidentWalk = null
var _revisit := false
var _tutorial: Dictionary = {}
var _hook_travel := 0.0
var _pause_reason := ""
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
        _tutorial = {"move": false, "grab": false, "place": false}

    dispatcher.command.connect(_on_command)
    dispatcher.state_changed.connect(func(_state: String) -> void: _refresh_status())
    # NOTE (mristin):
    # Every visit calibrates anew: the player may be on the knees today and
    # in the plank tomorrow.
    pose.calibration = {}
    pose.dead_zone = float(_settings.get_value("dead_zone"))
    pose.sensitivity = float(_settings.get_value("sensitivity"))
    pose.hand_gestures = false
    pose.height_control = true

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
    hud.set_title(tr(mission["title"]))
    overlays = BuildOverlays.new()
    layer.add_child(overlays)
    overlays.build(bool(_settings.get_value("high_contrast")))
    overlays.action_requested.connect(_on_overlay_action)

    hook = Vector2(grid.width / 2.0, top_height())
    _fit_camera()
    _game.ensure_pose()
    if _pose_log != null:
        _pose_log.start("build_site", _log_settings(mission_id))
    var sounds := get_node_or_null("/root/Sounds")
    if sounds != null:
        sounds.loop("ambience_birds", true, -18.0)
    _evaluate()
    _update_touch()
    _show_hook()
    _refresh_status()
    get_viewport().size_changed.connect(_fit_camera)


## Fit the height of the site (with the crane's jib and a strip of ground) to
## the screen; sideways, the camera follows the hook (see [method _follow_hook]).
func _fit_camera() -> void:
    var viewport := get_viewport_rect().size
    var available := viewport - Vector2(340, 64 + 64)
    var top := -SiteView.CELL * 3.0
    var bottom := view.site_size().y + SiteView.CELL * 1.5
    var zoom := clampf(available.y / (bottom - top), 0.2, 2.0)
    camera.zoom = Vector2(zoom, zoom)
    camera.position = Vector2(
        view.to_screen(hook).x + 340 / 2.0 / zoom, (top + bottom) / 2.0 + (64 - 64) / 2.0 / zoom
    )


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
    _show_hook()
    _sound_loop("crane", hook.distance_to(hook_before) > 0.001)
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


## Let the yard move on while the player builds: now and then the oldest block
## leaves and a new one comes (first in, first out), but not while the hook is
## over the yard.
func _advance_queue(delta: float) -> void:
    if dispatcher.state != InputDispatcher.BUILD or not pose.calibration.has("h"):
        return
    if yard_place(hook.x) >= 0:
        return
    if queue.advance(delta):
        view.queue_redraw()


## Whether the bell hands over: the needs of the mission are met.
func can_hand_over() -> bool:
    return report != null and report.can_submit()


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
        fields["height"] = snappedf(pose.height, 0.01)
        fields["floor"] = snappedf(hook_floor, 0.01)
        fields["carried"] = carried
        fields["touch"] = touch["kind"]
        fields["armed"] = _armed
        _pose_log.sample(provider.now(), frame, fields, output["events"])
    if dispatcher.state == InputDispatcher.BUILD:
        _move_hook(Vector2(output["velocity"]).x * _delta, pose.height * top_height())
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
    # NOTE (mristin):
    # The dips do not place: the height of the hook does. A full dip only
    # resumes a pause.
    if event == "resume":
        dispatcher.dispatch("resume")


## The keyboard only pauses (P or Escape): the body plays.
func _unhandled_input(event: InputEvent) -> void:
    if grid == null:
        return
    if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
        dispatcher.dispatch("resume" if dispatcher.state == InputDispatcher.PAUSED else "pause")
        get_viewport().set_input_as_handled()


func _on_command(action: String, argument: Variant) -> void:
    match action:
        "cancel":
            hud.release_focus_all()
            overlays.hide_all()
        "pause":
            _game.session.save()
            if _waiting == "":
                overlays.show_pause(_pause_reason, _game.body_ready())
            _pause_reason = ""
        "resume":
            overlays.hide_all()
            pose.rearm()
        "zoom_camera":
            camera.zoom = (camera.zoom * float(argument)).clamp(Vector2(0.25, 0.25), Vector2(3, 3))
        "pan_camera":
            camera.position += Vector2(argument) / camera.zoom.x
    _refresh_status()


## The highest point of the hook's way.
func top_height() -> float:
    return grid.height + ABOVE_SITE


## The left edge of the yard: the skip, then the places of the blocks.
func yard_left() -> float:
    return -SLOT_WIDTH * (BlockQueue.SIZE + 1) - 1.0


## The place of the yard under x: 0 for the skip, 1 to [constant BlockQueue.SIZE]
## for the blocks, -1 outside the yard.
func yard_place(x: float) -> int:
    var index := floori((x - yard_left()) / SLOT_WIDTH)
    return index if index >= 0 and index <= BlockQueue.SIZE else -1


## The left edge of the bell, right of the site (the crane's mast is between).
func bell_left() -> float:
    return grid.width + 3.0


func over_bell(x: float) -> bool:
    return x >= bell_left() and x < bell_left() + 2.0


## How far the carried block hangs below the hook (its height).
func hang() -> float:
    var definition := content.part(carried)
    if definition == null or definition.layer == "edge_h":
        return 0.0
    return float(definition.footprint.y)


## Move the hook: sideways by [param dx], and towards the height
## [param target_y], but never below what is under it. Lowered onto what is
## under it, the hook acts (see [method _act]).
func _move_hook(dx: float, target_y: float) -> void:
    var before := hook
    hook.x = clampf(hook.x + dx, yard_left(), bell_left() + 2.0)
    _update_touch()
    hook.y = maxf(move_toward(hook.y, target_y, HOOK_SPEED_Y * _delta), hook_floor)
    if hook.y >= _rearm_y:
        _armed = true
    if (
        _armed
        and hook.y <= hook_floor + TOUCH
        and target_y <= hook_floor + TOUCH
        and touch["kind"] != "none"
    ):
        _act()
        _update_touch()
        hook.y = maxf(hook.y, hook_floor)
        _rearm_y = hook_floor + REARM
        _armed = false
    _hook_travel += absf(hook.x - before.x)
    if _hook_travel > 3.0:
        _tutorial_step("move")
    _follow_hook()


## Find what is under the hook, and how low the hook can go there.
func _update_touch() -> void:
    touch = {"kind": "none"}
    hook_floor = hang()
    var place := yard_place(hook.x)
    if place == 0:
        hook_floor = SKIP_TOP + hang()
        if carried != "":
            touch = {"kind": "skip"}
    elif place > 0:
        hook_floor = ITEM_TOP + hang()
        if carried == "" and place - 1 < queue.slots.size():
            touch = {"kind": "yard", "index": place - 1}
    elif over_bell(hook.x):
        if can_hand_over():
            hook_floor = ITEM_TOP + hang()
            if carried == "":
                touch = {"kind": "bell"}
    elif hook.x >= 0.0 and hook.x <= grid.width:
        if carried == "":
            var column := column_parts()
            if not column.is_empty():
                hook_floor = float(grid.top_of(grid.instances[column[0]]))
                touch = {"kind": "part", "id": column[0]}
        else:
            _find_landing()


## Drop the carried block in the column under the hook, from the top: it lands
## at the first height where it can stand, or stops on what is in its way.
func _find_landing() -> void:
    var definition := content.part(carried)
    var x := _column_anchor_x(definition)
    for y in range(grid.height, -1, -1):
        var anchor := Vector2i(x, y)
        var result := Placement.validate(grid, definition, anchor, mirrored, _context)
        if result.ok and rests(definition, anchor):
            hook_floor = y + hang()
            touch = {"kind": "place", "anchor": anchor, "result": result}
            return
        if result.reason_key == "ERROR_OVERLAP":
            var above := Vector2i(x, mini(y + 1, grid.height))
            hook_floor = above.y + hang()
            touch = {"kind": "blocked", "anchor": above, "result": result}
            return
    touch = {
        "kind": "blocked",
        "anchor": Vector2i(x, 0),
        "result": PlacementResult.invalid("ERROR_NO_LANDING")
    }


## Whether the part would rest at the anchor. The parts with a support rule
## rest where they are valid; the others (back walls, windows) fall until they
## stand on the ground, a floor or a part, and a window keeps a sill of one
## cell above it.
func rests(definition: PartDef, anchor: Vector2i) -> bool:
    if definition.support_rule != "none":
        return true
    var y := anchor.y - (1 if definition.layer == "window" else 0)
    if y < 0:
        return false
    if y == 0:
        return true
    for column in range(anchor.x, anchor.x + maxi(definition.footprint.x, 1)):
        for found in [
            grid.at(WorldGrid.SLOT_EDGE_H, Vector2i(column, y)),
            grid.at(WorldGrid.SLOT_CELLS, Vector2i(column, y - 1)),
            grid.at(WorldGrid.SLOT_BACKGROUND, Vector2i(column, y - 1)),
        ]:
            if found != 0:
                return true
    return false


## Do what the hook was lowered onto: grab a block of the yard, lift a placed
## part, put the carried block down, throw it into the skip, or ring the bell.
func _act() -> void:
    match touch["kind"]:
        "yard":
            carried = queue.take(int(touch["index"]))
            mirrored = false
            variant = 0
            _sound("click")
            _tutorial_step("grab")
        "part":
            var instance: PartInstance = grid.instances[int(touch["id"])]
            var command := Placement.remove_command(grid, instance.id)
            if command == null or not history.execute(command, grid):
                _sound("invalid")
                return
            carried = instance.definition_id
            mirrored = instance.mirrored
            variant = instance.colour_variant
            _sound("remove", randf_range(0.95, 1.05))
            _tutorial_step("grab")
            _after_edit()
        "place":
            var definition := content.part(carried)
            var command := Placement.place_command(
                grid, definition, touch["anchor"], mirrored, variant, _context
            )
            if command == null or not history.execute(command, grid):
                _sound("invalid")
                return
            _sound(_place_sound(definition), randf_range(0.95, 1.05))
            carried = ""
            _tutorial_step("place")
            _after_edit()
        "skip":
            carried = ""
            _sound("remove", 0.8)
        "bell":
            _submit()
        "blocked":
            _sound("invalid")


## Show the hook, what it carries, where it would land, and what it would do.
func _show_hook() -> void:
    view.hook = hook
    hud.camera_view.guides = pose.guides()
    var hook_screen := get_viewport().get_canvas_transform() * view.to_screen(hook)
    hud.avoid(hook_screen)
    if carried != "":
        var hanging := (
            get_viewport().get_canvas_transform() * view.to_screen(hook - Vector2(0, hang()))
        )
        hud.avoid(hanging)
    view.yard = queue.slots
    view.yard_left = yard_left()
    view.slot_width = SLOT_WIDTH
    view.item_top = ITEM_TOP
    view.bell_left = bell_left() if can_hand_over() else NAN
    view.carried = (
        {}
        if carried == ""
        else {"definition": content.part(carried), "mirrored": mirrored, "variant": variant}
    )
    view.preview = {}
    view.remove_mode = touch["kind"] == "part"
    view.pointed = int(touch.get("id", 0))
    view.yard_pointed = int(touch.get("index", -1))
    if touch["kind"] in ["place", "blocked"]:
        view.preview = {
            "definition": content.part(carried),
            "anchor": touch["anchor"],
            "mirrored": mirrored,
            "variant": variant,
            "ok": touch["kind"] == "place",
        }
    _show_message()
    view.queue_redraw()


func _show_message() -> void:
    var name := tr(content.part(carried).name) if carried != "" else ""
    match touch["kind"]:
        "yard":
            var part := content.part(queue.slots[int(touch["index"])])
            hud.set_message(
                Grammar.format(tr("Go down to grab {part}."), {"part": tr(part.name)}), Ui.INK
            )
        "part":
            var part := grid.definition_of(grid.instances[int(touch["id"])])
            hud.set_message(
                Grammar.format(tr("Go down to lift {part} up again."), {"part": tr(part.name)}),
                Ui.INK
            )
        "bell":
            hud.set_message(
                tr("Everything is ready: go down to ring the bell and hand it over."), Ui.OK_COLOUR
            )
        "skip":
            hud.set_message(
                Grammar.format(tr("Go down to throw {part} into the skip."), {"part": name}), Ui.INK
            )
        "place":
            var result: PlacementResult = touch["result"]
            var text := (
                "✓ "
                + Grammar.format(tr("{part} lands here: go down to put it there."), {"part": name})
            )
            if result.warning_key != "":
                text += "  ⚠ " + Texts.of(result.warning_key)
            hud.set_message(text, Ui.OK_COLOUR)
        "blocked":
            var result: PlacementResult = touch["result"]
            var params := result.params.duplicate()
            params["part"] = name
            hud.set_message(
                "✗ " + Grammar.format(Texts.of(result.reason_key), params), Ui.BAD_COLOUR
            )
        _:
            if carried == "":
                hud.set_message(
                    tr("Lean over a block in the yard on the left, then go down to grab it."),
                    Ui.INK
                )
            else:
                hud.set_message(
                    Grammar.format(
                        tr("Carry {part} over the site, then go down to put it there."),
                        {"part": name}
                    ),
                    Ui.INK
                )


func _follow_hook() -> void:
    var screen := get_viewport().get_canvas_transform() * view.to_screen(hook)
    var size := get_viewport_rect().size
    var margin := Rect2(Vector2(160, 0), Vector2(size.x - 160 - 360 - 160, size.y))
    if not margin.has_point(screen):
        var shift := screen - screen.clamp(margin.position, margin.end)
        camera.position += shift / camera.zoom.x


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


func _after_edit() -> void:
    _game.session.store_site(mission_id, grid)
    _autosave_at = Time.get_ticks_msec() / 1000.0 + AUTOSAVE_DELAY
    _evaluate()


func _evaluate() -> void:
    report = MissionEvaluator.evaluate(mission, grid)
    queue.wanted_tags = wanted_tags(mission, report)
    hud.set_checklist(report)
    var highlighted: Array = []
    for id in report.analysis.support.problem_ids():
        highlighted.append(id)
    view.highlighted = highlighted
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


## The anchor column of the part under the hook.
func _column_anchor_x(definition: PartDef) -> int:
    if definition.layer == "edge_v":
        return roundi(hook.x)
    return roundi(hook.x - definition.footprint.x / 2.0)


## The parts in the column under the hook, from the top down (the empty hook
## lifts the first).
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


func _refresh_status() -> void:
    if hud == null:
        return
    hud.set_tool(
        (
            Grammar.format(tr("Carrying: {part}"), {"part": tr(content.part(carried).name)})
            if carried != ""
            else tr("The empty hook")
        )
    )
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


func _tutorial_step(step: String) -> void:
    if _tutorial.has(step) and not _tutorial[step]:
        _tutorial[step] = true
        _refresh_tutorial()


func _refresh_tutorial() -> void:
    if _tutorial.is_empty():
        hud.set_tutorial("")
        return
    var lines: Array[String] = [Texts.of("TUTORIAL_TITLE")]
    for step in ["move", "grab", "place"]:
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
        # NOTE (mristin):
        # The player has just held still in the posture: that was the
        # neutral, so the hook follows at once (the pose logs showed players
        # leaning right away, and the hook waiting for 20 s).
        pose.needs_neutral = false
        events.append("auto_calibrated")
        _refresh_status()
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
    carried = ""
    view.preview = {}
    view.highlighted = []
    _walk = ResidentWalk.start(grid, report.analysis, mission, content)
    _sound("cheer")
    var names := MissionText.requesters(mission, content)
    overlays.show_completion(
        Grammar.format(tr("{names}: “{thanks}”"), {"names": names, "thanks": tr(mission["thanks"])})
    )
