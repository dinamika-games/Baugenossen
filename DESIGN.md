# Baugenossen — A City Built Together

**Game design and implementation specification, v0.1**  
**Audience:** Claude Code and human contributors  
**Language:** English (including source identifiers, content and documentation)  
**Target:** Godot 4.x, GDScript, desktop, open-source project

## 0. Instructions for the implementation agent

Read this entire document before implementing. Inspect the existing repository, project settings, dependencies and available pose-tracking code before changing anything. Preserve established conventions and working integrations. If starting from an empty repository, use the architecture below. Implement milestones in order, keeping the project playable and tests passing after each milestone. Do not silently invent additional game systems. Record deviations and unresolved questions in `docs/DECISIONS.md`. Use placeholder vector/rectangle art until the core mechanics work. Do not require a webcam for development or tests. Do not claim tests passed unless actually run. The numbers in this specification are initial balancing defaults, not empirically validated values.

## 1. Vision and non-negotiable requirements

Baugenossen is a nonviolent, mission-based, motion-controlled 2D construction sandbox RPG. It combines a cross-sectional view of buildings, the freedom to construct them element by element, and the character development of a classic role-playing game. The player works for a housing cooperative. Future residents and community members request useful things: houses, parks, bridges, schools, workshops, gardens and public spaces. The player designs and constructs them, rather than buying a predefined building. Residents have secure ownership or collective control through the cooperative; buildings are never speculative assets, sold for profit or used to extract rent in the game. Karma is gratitude and trust, not money.

Design source: [Dinamika Games Manifesto](https://github.com/dinamika-games), consulted 2026-11-24. Apply its emphasis on movement, cooperation, nonviolent challenges, open-ended rules and sessions that are easy to stop. No ads, loot boxes, streak pressure, leaderboards, competitive scoring or monetization. No combat. No city management simulation (taxes, zoning, rent, traffic, elections, stock market). The city grows through completed projects, not passive economic optimization.

### Core loop

1. Create a builder character; choose attributes, background and optional traits.
2. Accept a construction request from named residents.
3. Inspect the site, requirements, optional wishes and available parts.
4. Select a component (wall, floor, furniture, etc.) from a catalogue.
5. Operate a crane using body movement, preview a grid-snapped position, and place the component.
6. Repeat, remove or rearrange components freely; inspect live objective feedback.
7. Submit the construction when mandatory objectives are satisfied.
8. Watch residents use the result; receive XP, karma and any skill progression.
9. Allocate earned skill points/perks and select a new project. Stop or save at any point.

Every mission specifies a problem, not a blueprint. No image matching or scoring against a canonical layout. At least two meaningfully different valid designs should be possible for each ordinary mission. Tutorials may suggest one design but should not require it unless teaching a single action.

## 2. Presentation and construction model

### 2.1 World

Use a true 2D orthographic side elevation/cutaway, not isometric or 3D. Interior rooms and inhabitants are visible like a dollhouse. X increases rightwards, grid Y increases upwards; rendering converts Y to Godot's downward screen coordinates. Each grid cell is initially 32 px, representing roughly half a metre; a standard storey is 6 cells high. MVP site is 40×24 cells above a flat ground row at y=0. Coordinates outside the grid are invalid. Camera pan and zoom must not affect saved geometry. Future sites support terrain, underground and water via explicit cell properties, not a new coordinate system.

Show crane mast, horizontal trolley, cable and hook. The hook carries a ghost of the currently selected part. The crane is a visual representation of input, not a physical simulation: no swinging load, inertia, collisions while transporting or punishment for dropping a block. Default crane reach covers the whole site; character upgrades expand load capacity, not essential accessibility.

### 2.2 Grid layers and components

Distinguish occupancy from boundaries. Use cell-centred volumes for furniture and obstacles, horizontal edges for floors/ceilings, vertical edges for walls and doors, and a separate background layer for back walls and windows. Use integer grid coordinates for authoritative state. An edge is canonical: H(x,y) separates (x,y-1) and (x,y); V(x,y) separates (x-1,y) and (x,y). A segment spanning N cells occupies N consecutive edges. Ground is an implicit support surface H(x,0). Floor at y=k supports objects whose bottom is y=k. No two parts may occupy the same exclusive slot; different layers can coexist. A window in the background does not block movement. A door occupies vertical boundary slots, is weather-sealing when closed and traversable when opened. Stairs occupy reserved cells and add a traversal link between landings. Roofs use horizontal or stepped boundary segments in MVP; curved geometry later.

Component definition fields: stable `id`, `name_key`, `description_key`, `category_id`, `layer`, `footprint`, `edge_offsets`, `blocked_cells`, `support_points`, `interaction_offsets`, `tags`, `mass`, `material_id`, `requirements` (skill/attribute/perk), `visual_id`, `allowed_transforms`. Instance: unique ID, definition ID, anchor (x,y), transform, optional colour variant. Do not serialize translated names or scene node pointers. All coordinates derived from definitions. Horizontal mirroring only for asymmetric furniture in MVP; no arbitrary rotation. Keep definitions data-driven.

### 2.3 Initial catalogue

All listed basic pieces are available to every character, regardless of stats, to guarantee a solvable tutorial. Dimensions in cells/edge units; weights are abstract units.

| ID | Slot / size | Mass | Tags / effect |
|---|---|---:|---|
| floor_wood | H × 2 | 2 | floor, walkable, weather_seal |
| wall_wood | V × 6 | 3 | wall, structural, weather_seal |
| wall_short | V × 2 | 1 | wall, structural, weather_seal |
| roof_flat | H × 2 | 2 | roof, weather_seal |
| door_wood | V × 4 | 2 | door, weather_seal, traversable |
| back_wall | background 2×6 | 1 | enclosure_visual |
| window_basic | background 2×2 | 1 | daylight; replaces background in its footprint |
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

For window replacement implement an explicit atomic replacement command, or reject conflicts with a clear instruction to remove background first. In MVP furnishings use reserved footprint for placement; walking collision uses `blocked_cells` separately so tables, chairs and beds can be approached. Decorative overlays must never accidentally block navigation. Roof, floor and walls may be assembled from multiple segments. Advanced catalogue is unlocked by skills below; use placeholder art and definitions only when the corresponding mechanics exist.

### 2.4 Placement and editing

Catalogue selection sets `carried_part_id`. Hook moves continuously but preview snaps to nearest valid grid anchor. Green outline for valid, red outline plus localized reason for invalid (out of bounds, overlap, unsupported, locked, protected, overweight). A confirm action commits one atomic command; invalid confirm leaves the world unchanged. Keep selected part for repeated placements. No resource loss for mistakes. Remove tool selects an instance; moving is an atomic remove/place transaction. Undo/redo includes additions, removals, replacements and moves, with a bounded history of 100 commands. New edit after undo clears redo. Initial site objects may be marked protected. Do not allow deleting terrain, protected items or mission boundaries. Design may be unfinished; missing enclosing walls are allowed during construction.

### 2.5 Simplified structural rules

Not an engineering simulator. For MVP validate all new non-background parts have a support chain to terrain or existing anchored structural parts; furniture rests on floor/ground, walls rest on support at their base, floors/roofs attach to supporting walls or beams (allow basic overhang of 2 cells). Stairs need both landings before mission submission; allow placement with lower support while building. Recompute support graph after any edit; do not auto-collapse anything or injure residents. Removing a supporting part may leave a warning and an unsupported design; submission is blocked until fixed. A cycle of floating elements is not support. Later add material-specific spans (wood 6, stone 8, steel 12 cells as game abstractions) and load checks. Explain every invalid result to the player.

## 3. Body controls and input architecture

### 3.1 Unified semantic actions

All inputs emit the same normalized commands, regardless of backend: `move_hook(Vector2)`, `select_part(id)`, `confirm`, `cancel`, `open_catalogue`, `toggle_remove`, `undo`, `redo`, `pause`, `resume`, `pan_camera`, `zoom_camera`, `submit_mission`. Do not couple game rules to pose estimation. Keyboard/mouse fallback is complete and available permanently, not a debug-only mode.

| Action | Keyboard/mouse | Proposed body input |
|---|---|---|
| Hook horizontal velocity | A/D or left/right | Shift torso weight left/right |
| Hook vertical velocity | W/S or up/down | Raise/lower torso relative to calibrated neutral |
| Place selected component | Space / confirm button | Deliberate right-hand lift and return |
| Open catalogue | Tab | Deliberate left-hand lift |
| Navigate catalogue | Mouse/arrows | Raised left hand as cursor (optional) |
| Select catalogue item | Click/Enter | Dwell on item, then return hand; no simultaneous hand lifts |
| Cancel | Escape | Cancel target dwell or keyboard/helper |
| Remove/undo/redo | X / Ctrl+Z / Ctrl+Y | Catalogue tools (or helper) |
| Pause | P / Escape menu | Rest posture or tracking lost; accessible pause button |

Control mapping is a proposed implementation choice, subject to testing. Never require lifting both hands in a push-up position. Never infer body weight or true force from camera images; use calibrated visual proxies. Offer keyboard, supported plank, knees-down and seated gesture modes. Do not make real physical strength, speed or endurance affect XP, karma or RPG attributes. No mandatory hold durations, timed punishments or exercise streaks.

### 3.2 Pose provider

Interface `PoseProvider`: `start()`, `stop()`, `latest_frame()`; frame includes monotonic timestamp, image dimensions, keypoints with confidence (shoulders, elbows, wrists, hips at minimum), optional model-provided visibility, mirror flag. Reuse Dinamika Games pose pipeline if available; inspect its API/license/platform support first. Otherwise add an adapter to a suitable local estimator only after keyboard slice is stable. Never fabricate tracking results. Use local processing; do not upload or store camera frames by default. Explicit consent before opening camera; close on exit. Handle missing camera/permissions/model gracefully.

### 3.3 Calibration and signals

Camera angle is empirical: begin with front-oblique position where wrists, shoulders, elbows and hips are visible. Guide user to adjust framing. Collect neutral supported posture, comfortable left/right lean and comfortable raised/lowered positions; user may skip physical actions and use fallback. Horizontal proxy = shoulder midpoint relative to wrist midpoint, normalized by calibrated shoulder width and sign adjusted for mirroring. Vertical proxy = calibrated combination of elbow angle and shoulder-to-wrist projected distance (choose most reliable during test; never assume image vertical equals body height). Normalize using user-specific positive/negative extrema. Apply EMA smoothing (alpha 0.2 at 30 Hz, time-adjusted), dead zone 0.15, clamp to [-1,1]. Hook velocity = sign(s) * max(0,(abs(s)-0.15)/0.85)^1.5 * max_speed; initial max_speed 10 cells/s. Zero in neutral; clamp world position. Recenter calibration from explicit action, not continuously while user leans.

Hand lift detector uses calibrated wrist displacement relative to shoulders plus elbow/visibility checks; threshold and hysteresis configurable. Initial gesture qualification 200 ms, return to neutral 150 ms, cooldown 350 ms. These are debounce defaults, not exercise targets. Detect one event per lift; no repeats from held hand. Freeze hook during gesture recognition to prevent placement drift; capture target and validate on commit. In catalogue mode freeze crane; map active hand position to UI coordinates with calibration, dwell 650 ms, visible dwell progress; returning hand completes selection, then require stable neutral before resuming movement. Confidence below 0.6 for required joints or frames older than 250 ms: freeze immediately; after 500 ms show paused tracking overlay. Reacquisition requires stable neutral and explicit resume; never trigger queued placement. Prefer conservative false-negative behavior.

### 3.4 Input state machine

States: `CALIBRATION`, `BUILD`, `CATALOGUE`, `GESTURE_PENDING`, `PAUSED`, `REVIEW`, `COMPLETE`. Only BUILD accepts movement and construction commits; REVIEW is read-only until edit/resume. Pause cancels pending gesture, freezes hook and dwell, preserves project. Catalogue selection returns to BUILD after neutral rearm. Handle keyboard and gesture events through a single dispatcher; simultaneous confirms in one tick produce at most one command. A helper can use mouse to browse parts while the active player controls crane; later formalize local cooperation without requiring a second camera.

## 4. Character creation and RPG rules

The avatar is a fictional builder, independent of the real player's fitness. Choose name, pronouns (optional), appearance (skin/hair/clothing palettes), background, attributes and up to two optional traits. No attribute has a penalty tied to real body shape or age. Character creation can be reset before first mission.

### 4.1 BUILDER attributes

Seven integer attributes, each 1–10, total 40 at creation. Default B=6,U=6,I=6,L=5,D=6,E=6,R=5. No permanent class restrictions.

| ID | Name | Effect |
|---|---|---|
| B | Brawn | Crane capacity = 4 + B abstract mass units |
| U | Understanding | Base technical skills and technical unlocks |
| I | Ingenuity | Base design skills and inventive perks |
| L | Leadership | Base cooperative skills; optional helper/module capabilities later |
| D | Dexterity | Base craft skills and advanced placement tools |
| E | Empathy | Base community/interior skills; reveals optional preferences |
| R | Resilience | Base practical skills and advanced tool capabilities; no forced real-world endurance |

All basic parts mass ≤4, so every legal build can use them. Do not degrade basic control responsiveness for low Dexterity. No hidden stamina meter that forces physical exertion; Resilience is an RPG prerequisite, not a fitness score. Every five character levels grant one attribute point, maximum 10 per attribute; store earned points until spent.

### 4.2 Skills

Skill range 0–100. Initial skill = clamp(5 + 2*A + 2*B + background bonus + trait modifiers, 0,100), where A/B are the two indicated attributes. Store initial base and earned investment separately; attribute increase raises related skill base by 2, capped at 100, without destroying invested points. Skill IDs are stable snake_case.

| Skill | Attributes | Example unlocks at 40 / 60 / 80 |
|---|---|---|
| Crane operation | D,B | alignment guides / group lifting / heavy modules |
| Masonry | B,U | stone walls / arches / large masonry spans |
| Carpentry | D,U | timber frames / wooden bridges / engineered timber |
| Architecture | I,U | shaped roofs / module templates / custom assemblies |
| Structural engineering | U,I | support overlay / cantilevers / long-span structures |
| Electrical engineering | U,D | lights variants / elevators / solar systems |
| Plumbing | U,D | showers / irrigation / water reuse |
| Landscaping | I,E | mature trees / ponds / terraced gardens |
| Metalworking | B,D | steel beams / trusses / large steel spans |
| Glassworking | I,D | large windows / glass roofs / glazed facades |
| Interior design | I,E | furniture sets / flexible interiors / custom finishes |
| Restoration | R,D | repair tools / heritage elements / adaptive reuse |
| Recycling | R,U | reclaimed parts / material recovery / reusable assemblies |
| Fine arts | I,D | murals / mosaics / custom ornaments |
| Ecology | U,E | habitats / green roofs / wetland systems |
| Community engagement | E,L | extra wishes / cooperative assistance / community commissions |

Skill ranks: Novice 0–19; Apprentice 20–39; Journeyman 40–59; Craftsperson 60–79; Expert 80–99; Master 100. Each skill unlock is an explicit requirement on a component/tool/perk, never a hard-coded string comparison. Universal catalogue is exempt. Unlocks expand creativity, not basic mission solvability. Locked entries visible with explanation and preview. Use 10 discretionary skill points per new character level; 1 point = 1 skill unit. No investment beyond cap. Do not silently spend points. Skill practice: on first completion of a mission, award +1 to each of up to three craft skills with the most qualifying unique final components (minimum 3 distinct instances); stable skill-ID tie break. Never award points for repeated place/remove, undo/redo or idling. Editing completed missions grants no repeat XP or practice. MVP may omit practice until progression phase; if omitted label it as not implemented.

### 4.3 Backgrounds

| Background | Initial bonuses | Character flavour |
|---|---|---|
| Apprentice | +5 all skills | Generalist; +2 discretionary points per level |
| Carpenter | +20 Carpentry, +10 Restoration | Timber and furniture |
| Architect | +20 Architecture, +10 Interior design | Creative layouts |
| Engineer | +20 Structural engineering, +10 Metalworking | Bridges and towers |
| Gardener | +20 Landscaping, +10 Ecology | Parks and gardens |
| Artist | +20 Fine arts, +10 Interior design | Colour and ornament |
| Bricklayer | +20 Masonry, +10 Structural engineering | Stone and brick |
| Electrician | +20 Electrical engineering, +10 Crane operation | Technical systems |
| Plumber | +20 Plumbing, +10 Recycling | Water systems |
| Mechanic | +20 Crane operation, +10 Metalworking | Machinery |
| Restorer | +20 Restoration, +10 Recycling | Existing structures |

Backgrounds provide bonuses and flavour, not exclusive items: any character can eventually unlock anything by meeting requirements. Apprentice is deliberately generous; revisit balance in playtesting.

### 4.4 Optional traits

Select zero, one or two. Apply additively at creation; clamp final skill value. Traits affect fictional capabilities only. Initial implemented traits: Traditionalist (+15 Carpentry, +15 Masonry, -10 Electrical engineering); Modernist (+15 Metalworking, +15 Glassworking, -10 Carpentry); Naturalist (+20 Ecology, -10 Metalworking); Specialist (+20 selected skill, -5 all others). Additional future traits: Perfectionist (+20% XP from optional objectives, -10% base mission XP); Autodidact (+1 extra practice point on qualifying missions, -10 initial discretionary points, only enable when initial point budget exists). Do not present unimplemented traits as selectable.

### 4.5 XP, levels, karma

Start level 1, XP 0, karma 0. Cumulative XP needed for level L = 100*(L-1)*L/2. Example: level 2=100, level 3=300, level 4=600, level 5=1000. Process multiple level-ups if a reward crosses several thresholds. Grant 10 skill points (12 Apprentice) at each level gained; 1 perk token at each multiple of 3; 1 attribute point at each multiple of 5. No max level initially. Rank labels at thresholds: 1 Apprentice, 5 Journeyman, 10 Craftsperson, 15 Builder, 20 Master Builder, 30 City Builder, 40 Grandmaster, 50 Living Legend. Rank is cosmetic.

Karma is non-spendable trust. Reputation thresholds: 0 Newcomer; 100 Helping Hand; 500 Trusted Neighbour; 1500 Pillar of the Community; 5000 Community Builder; 15000 Living Legend. Mandatory completion grants fixed XP and karma; each fulfilled optional wish adds its own fixed reward. No negative karma for abandoning or editing. Reward claims keyed by mission ID and objective ID; atomic save prevents duplication. A completed mission may be revisited; first-time optional wishes can grant their karma/XP once, but do not repeat base reward or practice. Optional goals never block the next mandatory mission unless explicitly stated. All early missions unlock via prerequisite completion, not a narrow character build.

### 4.6 Perks

Perks cost one token, are unique, and require the following. Implement only when the effect exists. No token is consumed on invalid purchase.

| ID / Name | Requirement | Effect |
|---|---|---|
| golden_hands / Golden Hands | D≥7 | Additional alignment guides and snap preview options |
| green_thumb / Green Thumb | Landscaping≥40 | Rare plant catalogue |
| master_of_arches / Master of Arches | Masonry≥50 | Wide arches |
| nothing_goes_to_waste / Nothing Goes to Waste | Recycling≥40 | Full material recovery when finite material missions exist |
| prefabricator / The Prefabricator | Architecture≥50 | Save connected selections as reusable modules |
| tree_whisperer / The Tree Whisperer | Ecology≥60 | Tree-integrated building parts |
| vertical_dreamer / Vertical Dreamer | Structural engineering≥60 | Advanced high-rise components |
| light_bringer / Light Bringer | Glassworking≥50 | Large glass structures |
| living_roofs / Living Roofs | Ecology≥40 | Roof gardens |
| underground_pioneer / Underground Pioneer | Structural engineering≥40 | Underground components (where site permits) |
| colourist / The Colourist | Fine arts≥40 | Custom colour palette |
| second_life / Second Life | Restoration≥60 | Heritage repair components |
| master_crane_operator / Master Crane Operator | Crane operation≥70 | Lift existing connected groups as a transaction |
| people_first / People First | E≥8 | Reveal additional optional personal wishes |
| jack_of_all_trades / Jack of All Trades | Level≥10 | +5 all skills, once |
| mentor / Mentor | Any skill=100 | +10% XP on related future missions |

The MVP does not need all 16 perks; implement Golden Hands (guide overlay), Colourist (palette variants), and Jack of All Trades (progression logic) first. A hidden or disabled future perk must not consume tokens. Module creation later validates every contained component and support on placement; modules do not bypass skill or mass constraints. Module placement is one undoable transaction.

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
- Future: `daylight`, `wheelchair_access`, `material_budget`, `water_clearance`, `habitat`, `heritage_preservation`. Do not activate missions until all their predicates are implemented.

Mission definition: `id`, `title_key`, `brief_key`, `site_id`, `requester_ids`, `prerequisite_ids`, `min_karma` (default 0), `available_catalogue_ids` (optional restrictions), `mandatory_objectives`, `optional_objectives`, `base_xp`, `base_karma`, `completion_dialogue_key`, `npc_spawn_defs`. Objectives have stable IDs, predicate parameters, text keys and optional reward values. Invalid or unknown predicate type fails content loading with a developer diagnostic, never silently passes.

### 5.3 Initial missions (MVP)

All initial tasks use only universal parts. Explicit completion button, enabled once valid. No time limit. Site geometry may be reused between missions, but each site has separate saved state.

**M01 — A Place to Sit** (tutorial; 20 XP, 20 karma). A neighbour wants a pleasant spot to rest. Flat 20×12 site. Mandatory: 1 reachable bench (2 seats), 1 tree, 2 cells of green area, no unsupported parts. Optional: 2 flower beds (+5 XP, +5 karma). Teach catalogue, hook movement, preview, place, remove and undo. This is a suggested small tutorial, not a mandatory blueprint.

**M02 — The First Home** (100 XP, 100 karma; after M01). Two residents need a weatherproof home. Site 40×24. Mandatory: at least one accessible enclosed room of ≥24 cells; two reachable beds inside enclosed rooms; one reachable table and two seats, stove, sink and toilet, all inside accessible enclosed rooms; no unsupported components. Optional: two distinct sleeping rooms (+20 XP, +20 karma), two windows facing enclosed cells (+10/+10), outdoor bench and four green cells (+10/+10). No requirement for separate kitchens/bathrooms in this simplified first mission. A single-storey house and a two-storey house with stairs should both be valid. Starting entry is at left ground edge; ground is walkable unless blocked. Ensure enough plot space for both designs. Residents move in after submission and use reachable fixtures.

**M03 — A Garden for Everyone** (100 XP, 100 karma; after M02). Mandatory: 4 accessible seats, 12 unique green cells, 2 trees, reachable garden zone; optional 4 flower beds (+20/+20), seating in two separate zones (+10/+10). Different seating and planting layouts accepted. Do not require ponds until available.

**M04 — The Neighbourhood Workshop** (150 XP, 120 karma; after M03). Mandatory: 2 distinct reachable enclosed rooms ≥18 cells each, each with a table, seat and lamp; no unsupported parts. Optional garden/bench (+20/+20). Use existing furniture definitions; later add workbenches.

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

Residents are fictional NPCs with stable IDs, name keys, appearance, preferences and dialogue. Request cards describe the people and the practical problem in plain English. Optional wishes are always inspectable once revealed; Empathy/Community engagement may expose extra wishes but never hide mandatory requirements. MVP uses simple authored dialogue, no generative AI. Upon completion, spawn residents at entry, navigate to usable fixtures, play idle/use animations, and display a short thank-you. NPCs never permanently obstruct construction. If a saved project becomes invalid after editing, show its current unmet requirements; allow recovery without losing historical karma. Do not animate NPCs using invalid unreachable fixtures. No injury simulation.

Persistent city map: initially a simple illustrated list/map of projects (available, in progress, completed, needs repair). All sites persist. Later show a continuous side-scrolling city if useful, but do not require it for MVP. Site revisits support editing. Character progression and claimed rewards are global; site geometry, undo session and camera are local. Session end: after a mission show results and explicit options to save and exit, revisit or choose another project. No automatically starting the next mission. Pause any time.

Local cooperation: first version permits a second person to handle catalogue or planning using mouse while builder operates the crane, with one shared project. Later add explicit architect/operator roles, turn taking and optional role swapping. No individual competitive scoring. Do not require networking or multiple webcams.

## 7. Interface and art direction

- Main menu: New game, Continue, Settings, Credits, Quit.
- Character creation: name and avatar, seven attributes with remaining points, background, traits, derived skills preview; validate exactly 40 attribute points before continue.
- Site selection: request, difficulty/estimated number of placements (not a fitness target), requirements and rewards.
- Build HUD: site viewport, crane, selected part/ghost, bottom catalogue with category tabs (Structure, Access, Furniture, Utilities, Nature, Recreation, Tools), left/right mission checklist, pause and undo. Show a clear tracking status and current input mode.
- Review: mandatory/optional objectives, highlight unmet locations, return to editing or complete. No submission if invalid.
- Results: resident response, earned XP/karma, level changes, unspent points, save/exit.
- Character sheet: attributes, skills, background, traits, perks, next-level XP, karma/reputation. Explain all locked unlocks.
- Settings: input source, calibration, camera mirror, sensitivity/dead zone, sound/music, zoom/UI scale, language, reduced motion, high contrast. Always keep fallback controls usable.

Art: warm hand-drawn 2D cutaway, readable silhouettes, visible residents and interiors. Side-view perspective consistent across parts. Use separate transparent sprites and grid footprint metadata; no baked English text into assets. Placeholder assets are acceptable for initial development. Valid/invalid state must be indicated by icon/text as well as colour. UI must scale to 1280×720 and larger without overlapping the site or hiding pause. Keep catalogue navigable with large targets and dwell. Music and effects optional; no stressful timer sounds. Use original or compatibly licensed assets and record provenance.

## 8. Localization

English is the canonical source language. All text visible to players uses Godot `tr()` or equivalent translation lookup. Use stable keys such as `ATTR_BRAWN`, `SKILL_CARPENTRY`, `ITEM_FLOOR_WOOD`, `MISSION_FIRST_HOME_BRIEF`, `ERROR_UNSUPPORTED`, `OBJECTIVE_TAG_COUNT`. Store content in language-neutral JSON and translations in UTF-8 CSV (`keys,en` initially). No German-only names except brand Baugenossen; English subtitle A City Built Together. Support locale selection even if English is the only shipped locale. Use parameterized format placeholders, not concatenated sentences. Plural handling for quantities; test long translations/pseudo-localization and Unicode player names. Never use display text as ID. Store locale separately from game data.

## 9. Suggested technical architecture

Godot 4.x stable version compatible with existing repository; pin exact version in README after inspection. GDScript typed where practical. Separate pure game model from nodes. Do not introduce a database, cloud service or mandatory external runtime. Prefer built-in Godot facilities; if using ONNX/native extension, document platform/version and graceful fallback. Target desktop Windows, Linux and macOS; verify actual platform support rather than promise it.

```text
project.godot
README.md
CLAUDE.md
docs/BAUGENOSSEN_SPEC.md
docs/DECISIONS.md
scenes/
  main_menu.tscn
  character_creation.tscn
  city_map.tscn
  build_site.tscn
  character_sheet.tscn
  mission_results.tscn
scripts/
  domain/          # grid, part definitions, placement, commands, support, rooms, navigation
  progression/     # character, attributes, skills, traits, perks, rewards
  missions/        # mission records, predicates, evaluator, lifecycle
  input/           # semantic dispatcher, keyboard, pose adapter, calibration, gestures
  presentation/    # crane, camera, renderers, UI, NPCs
  persistence/     # save schema, validation, migration
content/
  parts.json
  skills.json
  backgrounds.json
  traits.json
  perks.json
  missions.json
  sites.json
  residents.json
  translations.csv
assets/
tests/
```

Suggested domain API (names illustrative): `WorldGrid.can_place(def_id, anchor, transform) -> PlacementResult`; `WorldGrid.apply(command) -> Result`; `CommandHistory.execute/undo/redo`; `SupportEvaluator.evaluate(world) -> SupportReport`; `RoomDetector.detect(world) -> Array[Room]`; `NavigationGraph.build(world, mobility_mode)`; `MissionEvaluator.evaluate(mission, world) -> MissionReport`; `Progression.award_once(reward_id, xp, karma)`; `UnlockEvaluator.is_unlocked(requirements, character)`; `SaveRepository.load/save`. UI observes domain change signals and renders snapshots. Scene nodes never own authoritative grid, mission or progression state. Deterministic iteration order when ties matter. Validate all content IDs and references at startup. Use stable IDs rather than engine instance IDs in saves.

Example mission fragment (illustrative JSON shape; implement validators):

```json
{
  "id": "first_home",
  "title_key": "MISSION_FIRST_HOME",
  "brief_key": "MISSION_FIRST_HOME_BRIEF",
  "site_id": "flat_40_24",
  "prerequisite_ids": ["place_to_sit"],
  "base_xp": 100,
  "base_karma": 100,
  "mandatory_objectives": [
    {"id": "beds", "type": "usable_tag_count", "tag": "sleep_capacity", "minimum": 2, "indoors": true},
    {"id": "room", "type": "enclosed_room_count", "minimum": 1, "minimum_area": 24, "accessible": true}
  ],
  "optional_objectives": [
    {"id": "green_space", "type": "green_area", "minimum_cells": 4, "xp": 10, "karma": 10}
  ]
}
```

The fragment is not the full mission; implement all M02 predicates listed in section 5.3.

## 10. Persistence and integrity

Save to `user://` JSON with schema version and revision. Store character base attributes, background, traits, invested skills, earned unspent points/tokens, perks, XP, karma, claimed reward IDs, completed mission IDs, site instances and settings. Keep derived stats reproducible. Validate all IDs, coordinates, data types and caps on load. Unknown version: preserve original file, show informative error, do not overwrite. Migrate old versions explicitly. Use temp file then replacement/rename, keep last known-good backup and verify errors. Reward and mission-completion update in same saved snapshot; if saving fails retain pending in-memory transaction and report, not duplicate. Autosave after valid committed edits (debounced) and progression changes, on pause and explicit quit; no camera frames or telemetry. Save incomplete missions. Undo need not persist across restart, clearly document that choice. Use tests with temporary directories.

## 11. Implementation milestones and acceptance criteria

### M0 — Bootstrap
Inspect repo, select engine version, establish code layout, input actions, placeholder art, README with run/test commands. Headless boot succeeds. Add test harness (existing project harness or lightweight GDScript runner exiting nonzero on failure). Keep project offline runnable.

### M1 — Keyboard playable construction
Implement grid layers, catalogue, hook preview, placement, removal, move, undo/redo, support checking, camera and HUD. Universal parts only. Acceptance: place at least 10 different part types, build a two-storey cutaway, reject overlap and bounds violations without mutation, undo and redo, navigate catalogue and pause without webcam. Render deterministic part positions. No mission reward yet.

### M2 — First complete mission loop
Implement room detection, navigation, objective engine, M01 and M02, basic residents, review and results, persistence. Acceptance: two distinct M02 layouts (single-storey and multi-storey) pass; an open roof, inaccessible bed and unsupported roof fail with specific feedback. Completing M01 unlocks M02; both persist after restart; no duplicate reward when resubmitted. Player can quit from results or mid-build.

### M3 — RPG
Implement character creation, backgrounds, initial skills, traits, XP, karma, level-up and spend interfaces, unlock predicates, first functional perks. Add M03/M04 and a handful of actual advanced variants. Acceptance: two legal character builds have different initial unlocked advanced parts yet both complete every initial mission. Validate attribute budget, skill caps, perk prerequisites, tokens, multiple level-ups, reward idempotency. All claimed effects actually work. Keep future perks disabled until implemented.

### M4 — Motion controls
Inspect and integrate existing pose provider or implement suitable adapter. Add calibration, smoothing, input state machine, gesture recognition and accessible fallbacks. Use synthetic pose sequences before webcam testing. Acceptance: hold neutral with no motion, left/right and raise/lower move intended axes, one gesture produces exactly one placement, loss of tracking freezes within stale-frame threshold, reacquisition cannot auto-place, catalogue cannot accidentally place, keyboard remains functional. Test real camera positioning across users/devices; record measured false-trigger rates and tuning decisions. Do not assume gesture approach works before real-world trials.

### M5 — Polish and expanded campaign
Improve original art, animation, accessibility, localization and content. Add at least one new construction mechanic and associated objective tests before its mission. Optional local co-op roles. Validate platform exports and document actual supported cameras/OS versions. End each session with explicit stopping point.

## 12. Required tests

Unit tests: edge canonicalization; coordinate transforms; multi-cell footprint; compatible layers; invalid placement atomicity; support chain vs floating cycle; remove support warning; undo/redo roundtrip and branching; protected instances; window replacement; stair links; closed-door room seal vs navigation; roof gaps; separate regions; accessible fixtures; no double-count in distinct-room matching; green area unique coverage; objective unknown-type rejection; locked part check; attribute allocation; skill formula; skill/attribute caps; level thresholds; background and trait modifiers; perk prerequisites; practice award once; reward idempotency; save roundtrip/migration/corruption fallback; localization key coverage.

Integration tests: M01 complete from clean state; M02 two valid layouts and invalid variations; save/reload incomplete site; resume complete mission without duplicate rewards; change locale without altering IDs; keyboard-only full loop; synthetic pose sequence (neutral, lean, lift, hold, return, tracking drop, resume); concurrent keyboard/pose confirm deduplicated. Content test validates all active missions are solvable using allowed capabilities and sample layouts. Test expected values, not just absence of crashes.

Manual tests: camera setup, different body proportions and lighting, mirrored feed, reduced-range posture, seated/fallback mode, rest/pause, input latency, no unintended crane movement when selecting, long UI translations, readability, resident paths, large builds. Prefer comfort over maximum exercise intensity. Record what has and has not been tested.

## 13. Out of scope and open decisions

Not required: real structural engineering, material economics, fluid/heat/electrical simulations, procedurally generated quests, multiplayer networking, 3D building depth, real-money economy, combat, generative NPC dialogue, competitive fitness metrics. Parks are represented as side-view walkable landscapes, not top-down plans. Real-world weight shift is only a pose proxy; camera angle, vertical signal and hand gestures need prototyping. Initial skill balance, perks, mission rewards, grid dimensions and art are design proposals. The initial tutorial is deliberately a small park feature rather than a house to teach placement; change if playtests favour a house-first tutorial. Persistent sites use separate scenes first. The choice of Godot/GDScript follows existing Dinamika project patterns but must be confirmed against the actual repository. No implementation or camera testing has been performed by the author of this specification.

## 14. Definition of first release

A user can create a distinct builder, complete at least four creative construction tasks with keyboard or calibrated motion controls, save and resume, observe residents use the projects, receive unique rewards and unlock genuinely new construction options. The player can stop comfortably at any time. Each mandatory mission has multiple solutions and no dependency on real-world physical performance or a specific character specialization. All UI text is English and localizable. Project runs without network and fails gracefully without camera.
