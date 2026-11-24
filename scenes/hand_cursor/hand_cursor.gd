extends CanvasLayer
## Point and click with the raised hand on every screen (the autoload
## HandCursor), as in Steppe Rescue: the hand detector (YOLOX) finds the
## hands, the pose tells where the shoulders are, below which a hand rests and
## does not count. Every raised hand has its own cursor.
##
## A hand clicks a button by holding its cursor over it for
## [constant DWELL_SECONDS]: a ring fills around the button meanwhile. The
## cursor is calm and sticky, since hands are hard to hold still and the
## detections jitter: on a button, it is drawn towards the middle and leaves
## only when the hand moves clearly beyond the edge, and it glides instead of
## jumping. Held at the top or the bottom of a list, it scrolls the list.
##
## It works with the ordinary Godot buttons (a toggle button toggles), so the
## screens need nothing special; the mouse keeps working as always. The build
## site switches it off while the player builds (see [member enabled]), since
## the raised hands are the gestures of the crane there.

## The hand holds still this long to click.
const DWELL_SECONDS := 2.0

## The part of the mirrored camera picture, normalized, which maps onto the
## whole screen, so that the player reaches every corner without stretching.
## Its bottom follows the shoulders (see [method _follow_shoulders]).
const REACH := Rect2(0.15, 0.1, 0.7, 0.6)

## The bottom of the screen lies this far below the shoulders, normalized.
const BELOW_SHOULDERS := 0.04

## A hand lower than this below the bottom of the reach rests and does not count.
const BELOW_REACH := 0.08

const REACH_FOLLOW := 2.0

## A cursor on a button leaves it only when the hand is this far beyond its
## edge, in pixels, but at most this share of the smaller side of the button.
const STICKY_MARGIN := 36.0
const STICKY_MARGIN_SHARE := 0.35

## On a button, the cursor moves only this share of the way of the hand from
## the middle of the button, so that it stays well inside.
const STICKY_SHARE := 0.35

const GLIDE_SECONDS := 0.08

## The band at the top and the bottom of a scrolling list where the cursor
## scrolls it, as a share of its height, and how fast, in pixels a second.
const SCROLL_BAND := 0.15
const SCROLL_SPEED := 420.0

const THRESHOLD := 0.5
const LEFT_SHOULDER := 5
const RIGHT_SHOULDER := 6

## A hand is followed this long after the detector lost it, in seconds.
const GRACE_SECONDS := 0.3

## A hand moving further than this in one frame, normalized, is another hand.
const SAME_HAND := 0.25

const RADIUS := 26.0

## Whether the hands point on this screen; the build site turns it off while
## the player builds.
var enabled := true

## Where the cursors are, in the pixels of the screen.
var cursors: Array[Vector2] = []

## The points of the tests, which replace the hands when not empty.
var test_points: Array[Vector2] = []

var reach := REACH
var _hands: Array[Hand] = []
var _canvas: Control
var _dwell_button: BaseButton = null
var _dwell := 0.0
var _clicked := false


func _ready() -> void:
    layer = 100
    process_mode = Node.PROCESS_MODE_ALWAYS
    _canvas = Control.new()
    _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _canvas.draw.connect(_draw_cursors)
    add_child(_canvas)


func _service() -> Node:
    var vision := get_node_or_null("/root/Vision")
    return vision.service if vision != null else null


func _process(delta: float) -> void:
    var service := _service()
    var tracking: bool = enabled and service != null and service.IsRunning()
    if service != null:
        service.SetHandTracking(tracking)
    if not test_points.is_empty():
        cursors = test_points.duplicate()
    elif tracking:
        _follow_hands(service)
        _move_cursors(delta)
    else:
        _hands.clear()
        cursors.clear()
    if not enabled:
        cursors.clear()
    _update_dwell(delta)
    _scroll(delta)
    _canvas.queue_redraw()


func _move_cursors(delta: float) -> void:
    var screen := _canvas.get_viewport_rect().size
    cursors.clear()
    for hand in _hands:
        var target := ((hand.smoothed - reach.position) / reach.size * screen).clamp(
            Vector2.ZERO, screen
        )
        hand.cursor = target if hand.fresh else _glide(hand, target, delta)
        hand.fresh = false
        cursors.append(hand.cursor)


## The cursor glides towards its hand, and sticks to the button under it.
func _glide(hand: Hand, target: Vector2, delta: float) -> Vector2:
    var glide := 1.0 - exp(-delta / GLIDE_SECONDS)
    var button: BaseButton = null
    var stuck := hand.stuck
    if (
        is_instance_valid(stuck)
        and _clickable(stuck)
        and stuck.get_global_rect().grow(_margin_of(stuck)).has_point(target)
    ):
        button = stuck
    if button == null:
        button = button_at(target)
    hand.stuck = button
    if button == null:
        return hand.cursor.lerp(target, glide)
    var middle := button.get_global_rect().get_center()
    var wanted := middle + (target - middle) * STICKY_SHARE
    if not button.get_global_rect().has_point(wanted):
        wanted = middle
    return hand.cursor.lerp(wanted, glide)


func _margin_of(button: Control) -> float:
    return minf(STICKY_MARGIN, minf(button.size.x, button.size.y) * STICKY_MARGIN_SHARE)


## Whether the button can be clicked: visible, enabled, and not scrolled away.
func _clickable(button: BaseButton) -> bool:
    if not button.is_visible_in_tree() or button.disabled:
        return false
    var parent := button.get_parent()
    while parent != null:
        if parent is ScrollContainer:
            if not (parent as Control).get_global_rect().intersects(button.get_global_rect()):
                return false
        parent = parent.get_parent()
    return true


## The smallest clickable button under the point, or null.
func button_at(point: Vector2) -> BaseButton:
    var best: BaseButton = null
    for node in get_tree().root.find_children("*", "BaseButton", true, false):
        var button := node as BaseButton
        if not button.get_global_rect().has_point(point) or not _clickable(button):
            continue
        var clip := _scroll_of(button)
        if clip != null and not clip.get_global_rect().has_point(point):
            continue
        if best == null or button.size.x * button.size.y < best.size.x * best.size.y:
            best = button
    return best


func _scroll_of(control: Control) -> ScrollContainer:
    var parent := control.get_parent()
    while parent != null:
        if parent is ScrollContainer:
            return parent
        parent = parent.get_parent()
    return null


## Fill the ring of the button under a cursor, and click it when full. The
## hand must leave the button and come back to click it again.
func _update_dwell(delta: float) -> void:
    var button: BaseButton = null
    for point in cursors:
        button = button_at(point)
        if button != null:
            break
    if button != _dwell_button:
        _dwell_button = button
        _dwell = 0.0
        _clicked = false
    if button == null or _clicked:
        return
    _dwell += delta / DWELL_SECONDS
    if _dwell >= 1.0:
        _dwell = 0.0
        _clicked = true
        click(button)


## Click the button as the mouse would: a toggle button toggles.
static func click(button: BaseButton) -> void:
    if button.toggle_mode:
        button.button_pressed = not button.button_pressed
    else:
        button.pressed.emit()


## Scroll a list while a cursor holds at its top or bottom.
func _scroll(delta: float) -> void:
    for point in cursors:
        for node in get_tree().root.find_children("*", "ScrollContainer", true, false):
            var scroll := node as ScrollContainer
            if not scroll.is_visible_in_tree():
                continue
            var rect := scroll.get_global_rect()
            if not rect.has_point(point):
                continue
            var band := rect.size.y * SCROLL_BAND
            if point.y < rect.position.y + band:
                scroll.scroll_vertical -= int(SCROLL_SPEED * delta)
            elif point.y > rect.end.y - band:
                scroll.scroll_vertical += int(SCROLL_SPEED * delta)


## Let the bottom of the reach follow the shoulders, so that the hand reaches
## the bottom of the screen while it is still raised.
func _follow_shoulders(points: Array, scores: Array) -> void:
    var shoulders := 0.0
    var count := 0
    for i in [LEFT_SHOULDER, RIGHT_SHOULDER]:
        if float(scores[i]) >= THRESHOLD:
            shoulders += (points[i] as Vector2).y
            count += 1
    if count == 0:
        return
    var bottom := clampf(shoulders / count + BELOW_SHOULDERS, REACH.position.y + 0.25, 0.95)
    var step := minf(1.0, get_process_delta_time() * REACH_FOLLOW)
    reach.size.y = lerpf(reach.size.y, bottom - REACH.position.y, step)


## Follow the raised hands in the mirrored picture, normalized and smoothed;
## each found hand continues the nearest one followed before, if close.
func _follow_hands(service: Node) -> void:
    var keypoints: Array = service.GetKeypoints()
    var scores: Array = service.GetKeypointScores()
    if keypoints.size() > RIGHT_SHOULDER:
        _follow_shoulders(keypoints, scores)
    var lowest := reach.end.y + BELOW_REACH
    var now := Time.get_ticks_msec() / 1000.0
    var found: Array[Vector2] = []
    for hand in service.GetHands():
        # NOTE (mristin):
        # The player sees the screen as a mirror: their right hand goes right.
        var mirrored := Vector2(1.0 - hand.x, hand.y)
        if mirrored.y <= lowest:
            found.append(mirrored)
    var pairs := []
    for h in _hands.size():
        for f in found.size():
            var distance := _hands[h].raw.distance_to(found[f])
            if distance <= SAME_HAND:
                pairs.append([distance, h, f])
    pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
    var taken_hands := {}
    var taken_found := {}
    for pair in pairs:
        if taken_hands.has(pair[1]) or taken_found.has(pair[2]):
            continue
        taken_hands[pair[1]] = true
        taken_found[pair[2]] = true
        _hands[pair[1]].see(found[pair[2]], now)
    for f in found.size():
        if not taken_found.has(f):
            var born := Hand.new()
            born.see(found[f], now)
            _hands.append(born)
    var kept: Array[Hand] = []
    for hand in _hands:
        if now - hand.seen_at <= GRACE_SECONDS:
            kept.append(hand)
    _hands = kept


func _draw_cursors() -> void:
    if is_instance_valid(_dwell_button) and _dwell > 0.0:
        _draw_ring(_dwell_button.get_global_rect().grow(5.0), _dwell)
    for point in cursors:
        _draw_hand(point)


## A ring around the button, clockwise from the top left, filled to the share.
func _draw_ring(outer: Rect2, share: float) -> void:
    var corners := [
        outer.position,
        Vector2(outer.end.x, outer.position.y),
        outer.end,
        Vector2(outer.position.x, outer.end.y),
        outer.position,
    ]
    var reached := 2.0 * (outer.size.x + outer.size.y) * share
    for i in range(4):
        if reached <= 0.0:
            break
        var from: Vector2 = corners[i]
        var to: Vector2 = corners[i + 1]
        var side := from.distance_to(to)
        _canvas.draw_line(from, from.lerp(to, minf(1.0, reached / side)), Ui.ACCENT, 6.0)
        reached -= side


## An open hand: a palm and five fingers, outlined, big enough to see from afar.
func _draw_hand(at: Vector2) -> void:
    var skin := Color("f2c79b")
    var ink := Ui.INK
    var palm := Rect2(at + Vector2(-RADIUS * 0.55, -RADIUS * 0.1), Vector2(RADIUS * 1.1, RADIUS))
    var fingers := [
        [Vector2(-0.45, -0.1), Vector2(-0.55, -0.75)],
        [Vector2(-0.2, -0.1), Vector2(-0.22, -1.0)],
        [Vector2(0.05, -0.1), Vector2(0.06, -1.05)],
        [Vector2(0.3, -0.1), Vector2(0.36, -0.9)],
        [Vector2(0.55, 0.45), Vector2(0.95, 0.05)],
    ]
    for finger in fingers:
        var a: Vector2 = at + finger[0] * RADIUS
        var b: Vector2 = at + finger[1] * RADIUS
        _canvas.draw_line(a, b, ink, RADIUS * 0.42)
        _canvas.draw_line(a, b, skin, RADIUS * 0.28)
    _canvas.draw_rect(palm.grow(3.0), ink)
    _canvas.draw_rect(palm, skin)


## A raised hand which we follow, and its cursor.
class Hand:
    extends RefCounted
    var raw := Vector2.ZERO
    var smoothed := Vector2.ZERO
    var seen_at := 0.0
    var cursor := Vector2.ZERO
    var fresh := true
    var stuck: BaseButton = null
    var _x := OneEuro.new()
    var _y := OneEuro.new()

    func see(point: Vector2, now: float) -> void:
        raw = point
        seen_at = now
        smoothed = Vector2(_x.filter(point.x, now), _y.filter(point.y, now))


## Smooth a noisy signal with little lag: the faster it moves, the less we
## smooth (Casiez, Roussel and Vogel, "1€ Filter", CHI 2012), as in Steppe Rescue.
class OneEuro:
    extends RefCounted
    var min_cutoff := 1.2
    var beta := 4.0
    var derivative_cutoff := 1.0
    var _value := 0.0
    var _derivative := 0.0
    var _last := -1.0

    func filter(value: float, time: float) -> float:
        if _last < 0.0:
            _value = value
            _last = time
            return value
        var dt := time - _last
        if dt <= 0.000001:
            return _value
        _last = time
        var derivative := (value - _value) / dt
        _derivative += _alpha(derivative_cutoff, dt) * (derivative - _derivative)
        var cutoff := min_cutoff + beta * absf(_derivative)
        _value += _alpha(cutoff, dt) * (value - _value)
        return _value

    func _alpha(cutoff: float, dt: float) -> float:
        var tau := 1.0 / (TAU * cutoff)
        return 1.0 / (1.0 + tau / dt)
