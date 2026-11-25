# Baugenossen — A City Built Together

**Game design and implementation specification, v0.2**  
**Audience:** Claude Code and human contributors  
**Language:** English (including source identifiers, content and documentation)  
**Target:** Godot 4.x, GDScript, desktop, open-source project

## 0. Instructions for the implementation agent

Read this entire document before implementing. Inspect the existing repository, project settings, dependencies and available pose-tracking code before changing anything. Preserve established conventions and working integrations. If starting from an empty repository, use the architecture below. Implement milestones in order, keeping the project playable and tests passing after each milestone. Do not silently invent additional game systems. Keep this document the single description of the game: when the design changes, change it here, and record the open questions in section 13. Use placeholder vector/rectangle art until the core mechanics work. Do not require a webcam for the tests: they drive a synthetic body. Do not claim tests passed unless actually run. The numbers in this specification are initial balancing defaults, not empirically validated values.

## 1. Vision and non-negotiable requirements

Baugenossen is a nonviolent, mission-based, motion-controlled 2D construction game, played with push-ups. It is very simple: the buildings are seen from the side, the blocks wait in a yard on the left, and the player takes the one they want with a crane and puts it wherever they want on the site, and lifts it again to put it elsewhere. There is no character to build and no RPG: the game is the building. The player works for a housing cooperative. Future residents and community members request useful things: houses, parks, bridges, schools, workshops, gardens and public spaces. The player designs and constructs them, rather than buying a predefined building. Residents have secure ownership or collective control through the cooperative; buildings are never speculative assets, sold for profit or used to extract rent in the game.

Design source: [Dinamika Games Manifesto](https://github.com/dinamika-games), consulted 2026-11-24. Apply its emphasis on movement, cooperation, nonviolent challenges, open-ended rules and sessions that are easy to stop. No ads, loot boxes, streak pressure, leaderboards, competitive scoring or monetization. No combat. No city management simulation (taxes, zoning, rent, traffic, elections, stock market). The city grows through completed projects, not passive economic optimization.

### Core loop

1. Accept a construction request from named residents.
2. Inspect the site and the checklist (the needs and the optional wishes).
3. Move the crane's hook by leaning, and raise and lower it with the body: straight arms hold it high, the deeper the push-up, the lower the hook.
4. Lower the empty hook onto a block in the yard to grab it; carry it over the site and lower it until it sits on something: it is put there. A new block comes into the yard; now and then the oldest block leaves it (first in, first out).
5. Repeat; lower the empty hook onto a placed block to lift it up again, and put it down elsewhere or throw it into the skip; inspect live objective feedback.
6. Hand the construction over: once the mandatory objectives are satisfied, a bell appears right of the site; lower the hook onto it.
7. Watch residents use the result, and select a new project. Stop or save at any point.

Every mission specifies a problem, not a blueprint. No image matching or scoring against a canonical layout. At least two meaningfully different valid designs should be possible for each ordinary mission. Tutorials may suggest one design but should not require it unless teaching a single action.

## 2. Presentation and construction model

### 2.1 World

Use a true 2D orthographic side elevation/cutaway, not isometric or 3D. Interior rooms and inhabitants are visible like a dollhouse. X increases rightwards, grid Y increases upwards; rendering converts Y to Godot's downward screen coordinates. Each grid cell is initially 32 px, representing roughly half a metre; a standard storey is 6 cells high. MVP site is 40×24 cells above a flat ground row at y=0. Coordinates outside the grid are invalid. Camera pan and zoom must not affect saved geometry. Future sites support terrain, underground and water via explicit cell properties, not a new coordinate system.

Show crane mast, horizontal trolley, cable and hook. The hook moves sideways and up and down; the carried block hangs under it, and a ghost shows where it would land. The crane is a visual representation of input, not a physical simulation: no swinging load, inertia, collisions while transporting or punishment for dropping a block. Default crane reach covers the whole site; character upgrades expand load capacity, not essential accessibility.

### 2.2 Grid layers and components

Distinguish occupancy from boundaries. Use cell-centred volumes for furniture and obstacles, horizontal edges for floors/ceilings, vertical edges for walls and doors, and a separate background layer for back walls and windows. Use integer grid coordinates for authoritative state. An edge is canonical: H(x,y) separates (x,y-1) and (x,y); V(x,y) separates (x-1,y) and (x,y). A segment spanning N cells occupies N consecutive edges. Ground is an implicit support surface H(x,0). Floor at y=k supports objects whose bottom is y=k. No two parts may occupy the same exclusive slot; different layers can coexist. A window in the background does not block movement. A door occupies vertical boundary slots, is weather-sealing when closed and traversable when opened. Stairs occupy reserved cells and add a traversal link between landings. Roofs use horizontal or stepped boundary segments in MVP; curved geometry later.

Component definition fields: stable `id`, `name`, `description` (English, translated when shown), `category_id`, `layer`, `footprint`, `edge_offsets`, `blocked_cells`, `support_points`, `interaction_offsets`, `tags`, `mass`, `material_id`, `requirements` (skill/attribute/perk), `visual_id`, `allowed_transforms`. Instance: unique ID, definition ID, anchor (x,y), transform, optional colour variant. Do not serialize translated names or scene node pointers. All coordinates derived from definitions. Horizontal mirroring only for asymmetric furniture in MVP; no arbitrary rotation. Keep definitions data-driven.

### 2.3 Initial catalogue

All listed pieces are available from the start (a mission may offer only some of them). Dimensions in cells/edge units; weights are abstract units.

| ID | Slot / size | Mass | Tags / effect |
|---|---|---:|---|
| floor_wood | H × 2 | 2 | floor, walkable, weather_seal |
| wall_wood | V × 6 | 3 | wall, structural, weather_seal |
| wall_short | V × 2 | 1 | wall, structural, weather_seal |
| roof_flat | H × 2 | 2 | roof, weather_seal |
| door_wood | V × 4 | 2 | door, weather_seal, traversable |
| back_wall | background 2×6 | 1 | enclosure_visual |
| window_basic | window 2×2 | 1 | daylight; over the back wall |
| stairs_basic | volume 6×6 | 3 | traversal, two landing anchors |
| bed_single | volume 3×2 | 1 | sleep_capacity:1 |
| table_basic | volume 2×2 | 1 | table |
| chair_basic | volume 1×2 | 1 | seat_capacity:1 |
| sink_basic | volume 2×2 | 1 | hygiene |
| toilet_basic | volume 1×2 | 1 | toilet |
| stove_basic | volume 2×2 | 1 | cooking |
| lamp_basic | decor 1×1 | 1 | lighting |
| bench_basic | volume 3×2 | 1 | seat_capacity:2 |
| flower_bed | decor 2×1 | 1 | planted_area |
| tree_small | decor 3×5 | 1 | tree, shade |
| grass_patch | surface decor 2×1 | 1 | green_area |
| ladder_basic | traversal 1×6 | 1 | vertical_access |
| beam_wood | structural volume 4×1 | 3 | support |

Windows live in their own slot (`window`) over the back wall and conflict only with other windows: a 2×2 window can not replace a part of a 2×6 back wall without a filler part. Removing a window shows the back wall again. In MVP furnishings use reserved footprint for placement; walking collision uses `blocked_cells` separately so tables, chairs and beds can be approached. Decorative overlays must never accidentally block navigation; in the MVP no furniture blocks walking either (people walk past tables and beds in the cutaway and use them from their bottom row), only beams. A door is 4 cells high; a wall with a door is a door plus a short wall of 2 above it. An edge may not cut through a volume (a wall through a bed, a floor through stairs), nor a volume be placed around an existing edge. Stairs are 6×6 cells; their landings are the bottom-left cell and the cell one storey up above their last column (mirrored: the other way round); ladders link their foot to the cell one storey up. Roof, floor and walls may be assembled from multiple segments. Advanced parts are unlocked by attributes (section 4.1): stone wall and steel beam (Strength 7), large tree (Hands 7), large window (Ideas 7), sofa for three (Heart 7); each uses mechanics which exist. The art is placeholder vector drawings per `visual_id` until the painted sprites replace them, with the same footprints.

### 2.4 Placement and editing

**The yard** (`BlockQueue`): five blocks wait on the ground in a yard left of the site, oldest first, each in a place of 3 cells, with a skip at the far left. Grabbing a block takes it from the yard, the others move up, and a new block comes in at the end. Every 15 s the oldest block leaves and a new one comes in (first in, first out; not while the hook is over the yard), so that the choice changes while the player builds, a little like falling-block games, but with a bigger choice and no hurry: nothing is lost and nothing fails when a block leaves. The new blocks are drawn at random from the parts which the mission offers: the structure more often, and 4 times more often the parts with the tags which the unmet objectives ask for (a home gets its stove before long).

**The hook** (as in a tower crane, the hook only touches): its height follows the body (see section 3.3), but it never goes below what is under it. When the player brings it down onto what is under it (within 0.3 cells), it acts once, and acts again only after rising 1.5 cells: the empty hook grabs a block of the yard, or lifts the top part of the column under it up again (to put it elsewhere); the hook with a block puts it down where it lands, or throws it into the skip; the empty hook rings the bell (right of the site, only once the needs are met), which hands the building over. There is no other tool: no review screen, no separate remove, move, undo, mirror or colour.

Where a carried block lands: in the column under the hook, from the top down, the first height where it can stand (furniture on a floor, a wall on a support...), or it stops on a part in its way. Back walls and windows need no support; they fall until they stand on the ground, a floor or a part, and a window keeps a sill of one cell. The hook can go down only to that height, and the block is put there when the hook reaches it.

### 2.5 Simplified structural rules

Not an engineering simulator. For MVP validate all new non-background parts have a support chain to terrain or existing anchored structural parts; furniture rests on floor/ground, walls rest on support at their base, floors/roofs attach to supporting walls or beams (allow basic overhang of 2 cells): a contiguous run of floor or roof edges at one height is anchored where it rests on top of a supported wall or on a beam; the edges between the outermost anchors are supported (no span limit in the MVP), and up to 2 cells beyond. Farther edges are connected but overhanging: the player may build a span from one side (placing is allowed, with a warning), but nothing can stand on them and the submission is blocked until the span is closed. Stairs need both landings before mission submission; allow placement with lower support while building. Recompute support graph after any edit; do not auto-collapse anything or injure residents. Removing a supporting part may leave a warning and an unsupported design; submission is blocked until fixed. A cycle of floating elements is not support. Later add material-specific spans (wood 6, stone 8, steel 12 cells as game abstractions) and load checks. Explain every invalid result to the player.

## 3. Body controls and input architecture

### 3.1 Unified semantic actions

All inputs emit the same normalized commands, regardless of backend: `move_hook(Vector2)`, `next_block`, `previous_block`, `confirm`, `cancel`, `pause`, `resume` (the dispatcher keeps a few older commands, e.g., `open_catalogue`, for its tests). Do not couple game rules to pose estimation.

**The player plays with push-ups only: leaning moves the hook sideways, the height of the body is the height of the hook.** The hands stay on the floor while building. **There is no helper:** the keyboard only pauses, and the mouse does nothing on the build site. Without a camera, the build site says so.

| Action | Body | Keyboard |
|---|---|---|
| Hook horizontal velocity | Lean the torso left/right over the arms | — |
| Hook height | The height of the body: straight arms = top, the bottom of a push-up = the ground | — |
| Grab a block / lift a part up / put it down / throw it away / hand over | Lower the hook onto it (the yard, a part, the landing, the skip, the bell) | — |
| Pause | Tracking lost (e.g., getting up) | P / Escape |
| Resume | A push-up after holding the posture | P / Escape |
| Menus | The hand cursor (section 7) | — (the mouse works) |
| Music / sound effects | — | M / S |
| Quit | — | Escape twice within 2 s |

Control mapping is a proposed implementation choice, subject to testing. Never require lifting a hand in the push-up position. Never infer body weight or true force from camera images; use calibrated visual proxies. The player plays in the push-up position: a supported plank, or, easier, on the knees with the hands on the floor; never standing or seated. Do not make real physical strength, speed or endurance affect the game. No mandatory hold durations, timed punishments or exercise streaks.

### 3.2 Pose provider

Interface `PoseProvider`: `start()`, `stop()`, `latest_frame()`; frame includes monotonic timestamp, image dimensions, keypoints with confidence (shoulders, elbows, wrists, hips at minimum), mirror flag. The vision runs locally in C# through ONNX Runtime on background threads: RTMO-t finds the person, RTMPose-t (17 COCO key points) follows them, and the hand detector YOLOX-Body-Head-Hand finds the raised hands for the hand cursor of the menus (it runs only while a screen shows the cursor). Never fabricate tracking results. The camera starts with the game (not in headless runs; `--no-camera` forbids it); its pictures stay in memory and are never saved, recorded or sent. Handle a missing camera, permission or model gracefully. A synthetic provider (a made-up body) drives the tests.

**The pose log.** With `-- --log-pose[=<lines a second>]`, the build site logs the pose (also while it calibrates itself) and what the controls make of it as JSON lines (the key points with their confidence, the measures, the smoothed signal, the hook velocity, the gesture phases, the input state and the events; numbers only, never pictures). `dev/pose/analyze_pose_log.py` summarizes a log (tracking losses, low-confidence joints, gestures started vs. completed, hook movement while a gesture is pending, key point jumps) and writes a CSV. We log instead of recording frames, which are too heavy for the disk; the log finds most bugs.

### 3.3 Calibration and signals

Camera angle is empirical: the camera in front of the player, a bit to the side, seeing the shoulders and the elbows (and, deep in a push-up, still the elbows: the first pose logs showed them at the bottom edge). The camera does not see the hands on the floor (they are at the bottom edge of the picture or below it), so the controls rest on the shoulders and the elbows only:

- **Lean** = the shoulder midpoint relative to the elbow midpoint, horizontally, in shoulder widths, sign adjusted for mirroring (about ±0.25 when leaning, in the logs).
- **Dip** = how far the lower elbow is below the shoulders, in shoulder widths: about 0.8 with straight arms, down to 0.2–0.5 in a push-up (the lower elbow, so that a lifted arm does not look like a dip). It is measured against a baseline of the straight arms which follows the player's posture (up over 1.5 s; down over 8 s, and only in the upper half), since the straight-arm posture drifts while playing. **The height of the hook** is one minus the dip, over a range of 0.3 shoulder widths, and the hook reaches the ground at 0.7 of that range already, so that the player need not do the full push-up every time (0.4 without slack was too deep: in the second pose log, several push-ups ended at 0.52 instead of 0.36, and the hook stayed 1 to 3 cells above the blocks); a 1€ filter smooths it (cutoff 0.8 Hz, beta 2): straight arms put the hook at the top of the site (one cell above it), the bottom of a push-up on the ground; it follows at most 30 cells a second. The hook keeps moving sideways while the player is low. A lean lowers the shoulders a little, too (0.2–0.3 of the range), which lowers the hook a little. A full dip (0.75 of the range) still resumes a pause.
- **Lifts** = each elbow's height relative to its shoulder, relative to the other elbow (a lifted arm lifts its elbow; the body's own movement lifts both alike).
- A key point counts from confidence 0.4 (the logs showed well-placed shoulders at 0.5); an unsure elbow is mirrored from the other one across the shoulders.

**There is no calibration screen: the body controls calibrate themselves.** On every visit of a build site, the hook waits until the camera sees the player holding still for 2 s in the push-up position (or on the knees); the median posture becomes neutral, the lean gets a range of ±0.25 shoulder widths to full speed, and the dip a range of 0.3. These come from the first pose logs; tune them with more. "Learn my posture again" (in the pause) calibrates anew. Smooth the lean with a 1€ filter (cutoff 0.8 Hz, beta 1.5; calm at rest, quick when moving), dead zone 0.15, clamp to [-1,1]. Hook velocity = sign(s) * max(0,(abs(s)-0.15)/0.85)^1.5 * max_speed; initial max_speed 10 cells/s. Zero in neutral; the hook stands still during a lift. Recentre the calibration only on an explicit action, never continuously while the player leans. `dev/pose/replay_pose_log.gd` replays a pose log through the controls, to tune them on real movements.

Hand lift detector: threshold and hysteresis configurable (0.6 and 0.3 shoulder widths). Initial gesture qualification 200 ms, return to neutral 150 ms, cooldown 350 ms; no dip counts while a hand is lifted. These are debounce defaults, not exercise targets. Detect one event per lift; no repeats from held hand. Freeze hook during gesture recognition to prevent placement drift; capture target and validate on commit. In catalogue mode freeze crane; map active hand position to UI coordinates with calibration, dwell 650 ms, visible dwell progress; returning hand completes selection, then require stable neutral before resuming movement. A required joint below confidence 0.4 or frames older than 250 ms: freeze immediately; after 500 ms show paused tracking overlay. Reacquisition requires stable neutral and explicit resume (the pause button, P, or, after 0.5 s of neutral, a full dip, which then only resumes); never trigger queued placement. In the catalogue, the raised hand's offset from its shoulder (the wrist, which comes into the picture when raised, else the elbow; ±2 shoulder widths across, ±1.5 up and down) points at the entries. Prefer conservative false-negative behavior.

### 3.4 Input state machine

States: `CALIBRATION`, `BUILD`, `CATALOGUE`, `GESTURE_PENDING`, `PAUSED`, `REVIEW`, `COMPLETE`. Only BUILD accepts movement and construction commits; REVIEW is read-only until edit/resume. Pause cancels pending gesture, freezes hook and dwell, preserves project. The catalogue state is left from the first versions, for the tests of the hand gestures; the build site does not use it. Handle keyboard and gesture events through a single dispatcher; simultaneous confirms in one tick produce at most one command. A helper can click a block of the row while the active player controls the crane; later formalize local cooperation without requiring a second camera.

## 4. Progress

There is no character, no XP, no karma, no levels, no attributes and no perks: the first versions had them, and they made the game too complicated for a game played with push-ups. The cooperative's progress is the completed missions and the fulfilled wishes (`Progress`, saved). A mission opens when its prerequisites are completed. A completed mission may be revisited and edited; its completion counts once. Every part is available from the start; a mission may offer only some of them (the tutorial: the bench, chairs, trees, grass and flowers).

## 5. Mission evaluation

Use deterministic predicates over the construction model. Each objective returns `satisfied`, `current`, `required`, a localization key for feedback and optional highlighted cells/instances. Mandatory predicates must all pass to submit. Optional predicates never make an otherwise valid project fail. Update after edits, not every render frame. Keep evaluation independent of the renderer, pose input and NPC animation.

### 5.1 Rooms and paths

Flood-fill the cell grid from exterior sentinel cells through absent boundary edges. Treat closed doors as sealed for weather evaluation, but traversable for pathfinding. Indoor cells are those unreachable from exterior; connected enclosed regions separated by walls/closed doors are rooms. Background windows are visual/daylight elements, not weather openings in this abstract 2D model. Ground seals bottom boundaries. For room requirements count only usable cells and fixture instances inside their room. A basic room has at least 12 enclosed cells, enough vertical clearance for a 3-cell-tall avatar, and an entrance. Assign room types from actual contents rather than requiring a room label. Distinct-room objectives use distinct region IDs. An apartment is a connected collection of rooms with independent exterior access; implement apartment-specific separation rules before adding multi-apartment missions.

Build a navigation graph of walkable standing cells with floor support, clearance and no blocking occupancy. Add horizontal edges between adjacent standing positions except across non-door walls; add explicit stair/ladder links between landings. Door traversal links respect clearance. Fixtures expose at least one adjacent interaction position. Spawn entry is defined by mission. Reachability is breadth-first search from entry. A usable fixture must have an accessible interaction position. For wheelchair objectives use a separate graph excluding ladders/stairs and including ramps/elevators when implemented. Do not conflate geometric room enclosure with walkability. Test doors in both graphs.

### 5.2 Objective types

- `usable_tag_count(tag, minimum, zone?)`: count reachable tagged fixtures or capacity, as specified by the tag.
- `enclosed_room_count(minimum, minimum_area)`.
- `room_with_tags(tags, minimum_count)`; each candidate room must contain all requested usable tags.
- `distinct_rooms_with_tags(requirements[])`: use matching so one room cannot count twice.
- `reachable_zone(zone_id)` and `connected_zones(a,b,mode)`.
- `green_area(minimum_cells)`; count unique planted ground cells, not stacked decorations.
- `preserve_instances(ids)`; protected starting components unchanged.
- `max_height(cells)`, `forbidden_occupancy(zone_id)`, `no_unsupported_parts()`.
- `all_of(objectives[])`: a composite, for the wishes which combine conditions (e.g., an outdoor bench and four green cells).
- Future: `daylight`, `wheelchair_access`, `material_budget`, `water_clearance`, `habitat`, `heritage_preservation`. Do not activate missions until all their predicates are implemented.

`usable_tag_count` takes, besides `tag`, `minimum` and `zone`: `indoors`, `outdoors`, `reachable` (default true; false for trees, flowers and windows) and `count_instances` (count parts instead of summing capacities like `seat_capacity:2`). \"Windows facing enclosed cells\" counts windows with a cell inside a room. `preserve_instances` refers to the IDs of the site's protected initial parts, numbered 1, 2, … in the order of the site's `initial_instances`. Each objective has its own text key per mission (`OBJ_<MISSION>_<ID>`), since the same ID means different things in different missions.

Mission definition: `id`, `title_key`, `brief_key`, `site_id`, `requester_ids`, `prerequisite_ids`, `available_catalogue_ids` (optional restrictions: the parts which the row of blocks offers), `mandatory_objectives`, `optional_objectives`, `completion_dialogue_key`, `npc_spawn_defs`. Objectives have stable IDs, predicate parameters and text keys. Invalid or unknown predicate type fails content loading with a developer diagnostic, never silently passes.

### 5.3 Initial missions (MVP)

All initial tasks use only universal parts. Explicit completion button, enabled once valid. No time limit. Site geometry may be reused between missions, but each site has separate saved state.

**M01 — A Place to Sit** (tutorial). A neighbour wants a pleasant spot to rest. Flat 20×12 site. Mandatory: reachable seats for 2 (a bench or two chairs), 1 tree, 2 cells of green area, no unsupported parts. Optional: 2 flower beds (+5 XP, +5 karma). Teach catalogue, hook movement, preview, place, remove and undo. This is a suggested small tutorial, not a mandatory blueprint.

**M02 — The First Home** (after M01). Two residents need a weatherproof home. Site 40×24. Mandatory: at least one accessible enclosed room of ≥24 cells; two reachable beds inside enclosed rooms; one reachable table and two seats, stove, sink and toilet, all inside accessible enclosed rooms; no unsupported components. Optional: two distinct sleeping rooms, two windows facing enclosed cells, outdoor bench and four green cells. No requirement for separate kitchens/bathrooms in this simplified first mission. A single-storey house and a two-storey house with stairs should both be valid. Starting entry is at left ground edge; ground is walkable unless blocked. Ensure enough plot space for both designs. Residents move in after submission and use reachable fixtures.

**M03 — A Garden for Everyone** (after M02). Mandatory: 4 accessible seats, 12 unique green cells, 2 trees, reachable garden zone; optional 4 flower beds (+20/+20), seating in two separate zones. Different seating and planting layouts accepted. Do not require ponds until available.

**M04 — The Neighbourhood Workshop** (after M03). Mandatory: 2 distinct reachable enclosed rooms ≥18 cells each, each with a table, seat and lamp; no unsupported parts. Optional garden/bench (+20/+20). Use existing furniture definitions; later add workbenches.

### 5.4 Campaign backlog (not part of first vertical slice)

| Mission | Core requirement | Creative constraint / alternative |
|---|---|---|
| Three Families | Three independent dwellings | Terrace, tower or row houses |
| Grandma's Home | Accessible bed, bath, kitchen | Level layout or ramp/elevator |
| The Treehouse | Habitable room near protected tree | Support from ground or permitted tree mounts |
| The River Crossing | Join opposite banks | Keep navigation channel clear |
| The Kindergarten | Play, rest, toilets, outdoor access | Separate or mixed activity spaces |
| The School | Three classrooms, shared recreation | Vertical or horizontal arrangement |
| The Library | Reading seats and shelves | Quiet and social spaces |
| The Skatepark | Connected recreational surfaces | Design ramp and rail arrangements |
| The Hill | Build on sloped terrain | Terraces or elevated structures |
| The Old Factory | Reuse existing shell | Preserve marked walls |
| The Community Hall | 20 seats, accessible interior | Timber, masonry or steel |
| The Market | Six reachable stalls | Covered or outdoor layout |
| The Rooftop Forest | Green space above existing building | Respect support constraints |
| The Public Bath | Pools and changing rooms | Water connectivity |
| The Mountain Refuge | Shelter on difficult terrain | Small footprint, accessible paths |
| The Floating Village | Homes above water | Floating supports and bridges |
| The Animal Sanctuary | Separate suitable habitats | Safe circulation, plants and water |
| The Amphitheatre | Seating and performance area | Sloped or stepped site |
| The Botanical Garden | Multiple habitats | Greenhouses and open spaces |
| The Vertical Village | 30 residents on narrow site | Efficient shared infrastructure |

For each future mission create actual content records, objective tests and at least two sample solutions before making it selectable. Prefer mission variety over artificially increasing block count.

## 6. Residents, rewards and persistent world

Residents are fictional NPCs with stable IDs, name keys, appearance, preferences and dialogue. Request cards describe the people and the practical problem in plain English. Optional wishes are always inspectable once revealed; Wishes never hide mandatory requirements. MVP uses simple authored dialogue, no generative AI. Upon completion, spawn residents at entry, navigate to usable fixtures, play idle/use animations, and display a short thank-you. NPCs never permanently obstruct construction. If a saved project becomes invalid after editing, show its current unmet requirements; allow recovery without losing the completion. Do not animate NPCs using invalid unreachable fixtures. No injury simulation.

Persistent city map: a list of the projects (locked, available, in progress, completed, needs repair: a completed site edited into an invalid state; nothing is taken back). All sites persist. Later show a continuous side-scrolling city if useful, but do not require it for MVP. Site revisits support editing. The progress is global; site geometry, undo session and camera are local. Session end: after a mission show results and explicit options to save and exit, revisit or choose another project. No automatically starting the next mission. Pause any time.

Local cooperation: none in the first version (there is no helper; one player plays with the body). Later maybe turn taking. No individual competitive scoring. Do not require networking or multiple webcams.

## 7. Interface and art direction

- The game runs full screen (`--windowed` for a window). There is no settings screen: the camera starts with the game, M switches the music, S the sound effects, Escape twice within 2 s quits, and the rest is chosen on the command line (`--high-contrast`, `--reduced-motion`, `--no-mirror`, `--sensitivity=`, `--dead-zone=`, `--mute`, `--no-music`). The calibration is remembered.
- **The hand cursor.** In the menus, a raised hand moves a cursor (the hand detector finds it; the shoulders tell where a resting hand is, which does not count). The cursor sits on the middle of the hand where the player sees it in the mirrored camera picture behind the menu (1:1, the picture covers the screen), not on the wrist. The cursor glides, sticks to the button under it (drawn towards its middle, leaving only beyond its edge), and clicks after the hand holds still for 2 s while a ring fills around the button; it clicks once until the hand leaves. No screen scrolls: everything fits on one screen of 1280×720, in every language (a test checks it). Choices are big ◀/▶ choosers, never drop-down lists, which a hand can not open. The build site switches the cursor off while building: the hands stay on the floor there.
- **The player sees themselves**: the mirrored camera picture dimly behind every menu (without the skeleton: only the hands count there), and as an inset on the build site with the key points (green: sure, red: unsure) and the limits as lines: vertical, where the middle of the shoulders (an orange dot) starts moving the hook and reaches its full speed; horizontal, where the shoulders hold the hook at the top (▲) and bring it to the ground (▼). The inset moves out of the hook's way (top left, or left of the checklist).
- Main menu: big signboard buttons (a cream board in a wooden frame with nail heads; the main one orange; they grow a little under the mouse): Continue, New game, Credits, Quit.
- New game goes straight to the city map. City map: the projects as compact cards on one screen (title, state, residents, problem); the needs and the wishes are on the build site's checklist.
- The dialogues keep their buttons far apart (48 px in a row, 24 px in a column), so that the hand cursor never takes the neighbour.
- Build HUD: the site from the side, following the hook sideways, with the yard on the left and the bell on the right, the crane with the carried block and the ghost where it lands, the camera inset, the message of what the hook would do at the bottom, the mission checklist on the right, and an always visible pause button. Show a clear tracking status and current input state.
- No review screen: the checklist shows the needs all the time, and the bell appears when they are met.
- Results: resident response and the wishes fulfilled; then another project, back to the site, or save and exit. Nothing starts automatically.

Art: warm hand-drawn 2D cutaway, readable silhouettes, visible residents and interiors. Side-view perspective consistent across parts. Use separate transparent sprites and grid footprint metadata; no baked English text into assets. Placeholder vector art is used until the sprites arrive. Valid/invalid state must be indicated by icon/text as well as colour. UI must scale to 1280×720 and larger without overlapping the site or hiding pause.

Sound: CC0 effects cut from recordings on Freesound (`dev/sounds/sources.json`), and music rendered from CC0 and public-domain MIDI files on Wikimedia Commons with instruments synthesized in code (`dev/music/sources.json`): work songs and the songs of the journeymen on their Wanderschaft, plus two rags. No stressful timer sounds; an invalid placement is a soft knock. Record the provenance of every asset in THIRD_PARTY_NOTICES.md.

## 8. Localization

English is the source language; the translations use gettext, as the other texts of the game: every visible text in the code is a whole English sentence in `tr("...")`, with named placeholders (`{part}`), never glued together from pieces and never used as an ID. The content (`data/*.json`) holds its texts in English (`name`, `description`, `title`, `brief`, `thanks`, `text`), translated when shown. The messages which the game passes around by an ID (the reasons of the placement, the hints, the messages of the saves, the ranks, the input states) keep their stable IDs and get their English texts from one table, `Texts.MESSAGES`.

`dev/translations/extract.py` collects all of them into `translations/messages.pot` and merges it into `translations/<code>.po` for every language listed in `translations/languages.json` (the only place to add a language); `dev/translations/check.py` fails on a translation which breaks a placeholder, and reports what is still to review. A new translation stays marked fuzzy until a native speaker reviewed it in the game; the game shows it anyway. The language is chosen on the main menu (or `--lang=<code>`) and remembered apart from the game data. German is the first translation.

The grammar (`Grammar`) fills the placeholders and lets a translation:

- agree a word with a number: `{count|Sitz|Sitze}` picks the form by the plural rule of the language (one/other; one/few/many for Slavic languages; French counts zero as one);
- follow the builder's gender: `{builder|Baumeister|Baumeisterin}` picks the form for a constructor or a constructrice, in every text.

No German-only names except the brand Baugenossen; English subtitle A City Built Together. Test long translations and Unicode player names.

## 9. Technical architecture

Godot 4.6.2 (.NET): GDScript for the game, C# for the vision. GDScript typed where practical. Separate pure game model from nodes. Do not introduce a database, cloud service or mandatory external runtime. Prefer built-in Godot facilities; if using ONNX/native extension, document platform/version and graceful fallback. Target desktop Windows, Linux and macOS; verify actual platform support rather than promise it.

```text
project.godot, Baugenossen.csproj, Baugenossen.sln
README.md, CONTRIBUTING.md, CLAUDE.md, DESIGN.md, THIRD_PARTY_NOTICES.md
data/                     # parts, missions, sites, residents (JSON, English texts)
translations/             # languages.json, messages.pot, <code>.po (gettext)
scenes/
  construction/           # grid, part definitions, placement, commands, support, rooms, navigation, the yard of blocks
  missions/               # objectives, site analysis, evaluator, texts
  progression/            # the cooperative's progress and its rules
  languages/              # languages, grammar, the texts with an ID
  input/                  # dispatcher, the keys (pause), pose providers, measures, auto-calibration, controller, pose log
  session/                # save repository, game session, the Game autoload
  vision/                 # C#: camera, RTMO, RTMPose, YOLOX (core/ without Godot)
  hand_cursor/, sound/, settings/, content/, art/, ui/
  main_menu/, city_map/, build_site/, mission_results/
assets/                   # sounds/ and music/
dev/                      # pre-commit checks, sound and music pipelines, pose log analysis, screenshots
tests/godot/              # Godot tests (headless)
tests/Baugenossen.Tests/  # .NET tests of the vision core
```

Suggested domain API (names illustrative): `WorldGrid.can_place(def_id, anchor, transform) -> PlacementResult`; `WorldGrid.apply(command) -> Result`; `CommandHistory.execute/undo/redo`; `SupportEvaluator.evaluate(world) -> SupportReport`; `RoomDetector.detect(world) -> Array[Room]`; `NavigationGraph.build(world, mobility_mode)`; `MissionEvaluator.evaluate(mission, world) -> MissionReport`; `Progression.complete_mission(progress, mission, report)`; `BlockQueue.take/advance`; `SaveRepository.load/save`. UI observes domain change signals and renders snapshots. Scene nodes never own authoritative grid, mission or progression state. Deterministic iteration order when ties matter. Validate all content IDs and references at startup. Use stable IDs rather than engine instance IDs in saves.

Example mission fragment (illustrative JSON shape; implement validators):

```json
{
  "id": "first_home",
  "title_key": "MISSION_FIRST_HOME",
  "brief_key": "MISSION_FIRST_HOME_BRIEF",
  "site_id": "flat_40_24",
  "prerequisite_ids": ["place_to_sit"],
  "mandatory_objectives": [
    {"id": "beds", "type": "usable_tag_count", "tag": "sleep_capacity", "minimum": 2, "indoors": true},
    {"id": "room", "type": "enclosed_room_count", "minimum": 1, "minimum_area": 24, "accessible": true}
  ],
  "optional_objectives": [
    {"id": "green_space", "type": "green_area", "minimum_cells": 4}
  ]
}
```

The fragment is not the full mission; implement all M02 predicates listed in section 5.3.

## 10. Persistence and integrity

Save to `user://` JSON with schema version and revision. Store the completed mission IDs, the fulfilled wishes and the site instances (schema version 2; versions 0 and 1 had a character, whose completed missions migrate). Keep derived stats reproducible. Validate all IDs, coordinates, data types and caps on load. Unknown version: preserve original file, show informative error, do not overwrite. Migrate old versions explicitly. Use temp file then replacement/rename, keep last known-good backup and verify errors. The mission completion and its site are saved in the same snapshot; if saving fails retain it in memory and report. Autosave after valid committed edits (debounced) and progression changes, on pause and explicit quit; no camera frames or telemetry. Save incomplete missions. Undo need not persist across restart, clearly document that choice. Use tests with temporary directories.

## 11. Implementation milestones and acceptance criteria

### M0 — Bootstrap
Inspect repo, select engine version, establish code layout, input actions, placeholder art, README with run/test commands. Headless boot succeeds. Add test harness (existing project harness or lightweight GDScript runner exiting nonzero on failure). Keep project offline runnable.

### M1 — Playable construction
Implement grid layers, catalogue, hook preview, placement, removal, move, undo/redo, support checking, camera and HUD. Universal parts only. Acceptance: place at least 10 different part types, build a two-storey cutaway, reject overlap and bounds violations without mutation, undo and redo, navigate catalogue and pause; the tests need no webcam. Render deterministic part positions. No mission reward yet.

### M2 — First complete mission loop
Implement room detection, navigation, objective engine, M01 and M02, basic residents, review and results, persistence. Acceptance: two distinct M02 layouts (single-storey and multi-storey) pass; an open roof, inaccessible bed and unsupported roof fail with specific feedback. Completing M01 unlocks M02; both persist after restart; no duplicate reward when resubmitted. Player can quit from results or mid-build.

### M3 — Simplification
The first versions had a character (attributes, perks, XP, karma, levels) and a catalogue opened by lifting a hand; both were removed in favour of the yard of five blocks and the push-ups only (section 4). A row of blocks picked with short dips and a drop-and-place with push-ups followed, and were replaced by the crane seen from the side, whose hook follows the height of the body. Old saves migrate: their completed missions stay.

### M4 — Motion controls
Inspect and integrate existing pose provider or implement suitable adapter. Add calibration, smoothing, input state machine, gesture recognition and accessible fallbacks. Use synthetic pose sequences before webcam testing. Acceptance: hold neutral with no motion, left/right move the hook, the body's height sets the hook's height, lowering the hook onto something acts exactly once, loss of tracking freezes within stale-frame threshold, reacquisition cannot auto-place, the keyboard and the mouse never move the hook. Test real camera positioning across users/devices; record measured false-trigger rates and tuning decisions. Do not assume gesture approach works before real-world trials.

### M5 — Polish and expanded campaign
Improve original art, animation, accessibility, localization and content. Add at least one new construction mechanic and associated objective tests before its mission. Optional local co-op roles. Validate platform exports and document actual supported cameras/OS versions. End each session with explicit stopping point.

## 12. Required tests

Unit tests: edge canonicalization; coordinate transforms; multi-cell footprint; compatible layers; invalid placement atomicity; support chain vs floating cycle; remove support warning; undo/redo roundtrip and branching; protected instances; window replacement; stair links; closed-door room seal vs navigation; roof gaps; separate regions; accessible fixtures; no double-count in distinct-room matching; green area unique coverage; objective unknown-type rejection; the yard of blocks (take, first in first out, offered and wanted parts); completion counted once; save roundtrip/migration/corruption fallback; localization key coverage.

Integration tests: M01 complete from clean state; M02 two valid layouts and invalid variations; save/reload incomplete site; resume complete mission without counting it twice; change locale without altering IDs; keyboard-only full loop; synthetic pose sequence (neutral, lean, going down and up: grab, put down, lift again, skip, bell; tracking drop, resume); concurrent keyboard/pose confirm deduplicated. Content test validates all active missions are solvable using allowed capabilities and sample layouts. Test expected values, not just absence of crashes.

Manual tests: camera setup, different body proportions and lighting, mirrored feed, reduced-range posture, the plank and the knees, rest/pause, input latency, no unintended crane movement when selecting, long UI translations, readability, resident paths, large builds. Prefer comfort over maximum exercise intensity. Record what has and has not been tested.

## 13. Out of scope and open decisions

Not required: real structural engineering, material economics, fluid/heat/electrical simulations, procedurally generated quests, multiplayer networking, 3D building depth, real-money economy, combat, generative NPC dialogue, competitive fitness metrics. Parks are represented as side-view walkable landscapes, not top-down plans. Real-world weight shift is only a pose proxy; camera angle, vertical signal and hand gestures need prototyping. The row (5 blocks, 15 s, the weights), grid dimensions and art are design proposals. The initial tutorial is deliberately a small park feature rather than a house to teach placement; change if playtests favour a house-first tutorial. Persistent sites use separate scenes first. The choice of Godot/GDScript follows existing Dinamika project patterns but must be confirmed against the actual repository. No implementation or camera testing has been performed by the author of this specification.

Open questions:

- The camera position, the gesture thresholds and the dwell of the hand cursor need trials with children and adults, in the plank and on the knees; nothing about false triggers, lighting or body proportions has been measured yet. The calibration, the thresholds and the gestures are tested with synthetic pose sequences only.
- How long a block may wait in the yard (15 s), the range of the height control (0.3 shoulder widths from the top to the ground), the touch (0.3 cells) and the re-arm (1.5 cells) need trials; also whether the random yard ever blocks a mission for too long (the wanted parts come 4 times more often).
- The cut points of the sound effects were chosen from their loudness envelopes, not by ear.
- Packaging (export presets, the publish workflow) is not set up; the exports for Windows and macOS are untested.


## 14. Definition of first release

A user can complete at least four creative construction tasks with push-ups only, save and resume, and observe residents use the projects. The player can stop comfortably at any time. Each mandatory mission has multiple solutions and no dependency on real-world physical performance. All UI text is English and localizable. Project runs without network and fails gracefully without camera.
