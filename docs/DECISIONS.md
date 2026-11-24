# Decisions and open questions

This records where the implementation deviates from [DESIGN.md](../DESIGN.md), the choices the design left open, and what is still untested (DESIGN.md, 0).

## The project

* **Engine and layout.** Godot 4.6.2 (.NET), GDScript for the game and C# for the vision, like the other Dinamika games (Drunken Vikings, Jump 'n' Mine, Steppe Rescue, Bird Dog). We follow their layout instead of the one suggested in DESIGN.md, 9: the code lives by feature in `scenes/<feature>/` (the pure model in `scenes/construction/`, `scenes/missions/`, `scenes/progression/`, `scenes/input/`, `scenes/session/`; the screens next to it), the content in `data/*.json`, the translations in `translations/`, the tests in `tests/godot/` (Godot) and `tests/Baugenossen.Tests/` (.NET). The specification stays at `DESIGN.md` in the root, as in the other games, rather than `docs/BAUGENOSSEN_SPEC.md`.
* **Checks.** `dev/continuous_integration/precommit.py` (from Jump 'n' Mine) formats, lints, runs the .NET and Godot tests, builds, imports and type-checks; the CI runs it.
* **Packaging** (export presets, the publish workflow) is not set up yet; copy it from the other games when the first release nears.

## The pose

* **The models.** We reuse the vision of Drunken Vikings: RTMO-t finds the person, RTMPose-t (COCO 17 key points, Body7) follows them, through ONNX Runtime 1.19.2 in C# on a background thread (`scenes/vision/`). It gives the shoulders, elbows, wrists and hips which DESIGN.md, 3.2 asks for. We dropped its rowing signals, the hand detector (YOLOX) and the recording.
* **The camera starts with the game, and there is no settings screen** (the decision of the game's designer, as in the other Dinamika games). This replaces the explicit camera consent of DESIGN.md, 3.2. The pictures still stay in memory and are never saved nor sent. The few choices left are command-line options (see CONTRIBUTING.md); the calibration is remembered in `user://settings.cfg`.
* **Only the body moves the hook** (the decision of the game's designer: the player must move). This replaces the permanent keyboard fallback of DESIGN.md, 3.1 for the hook; the keyboard and the mouse remain helpers for everything else (placing, the catalogue, undo, pause), e.g., for a helper next to the player. Without a camera or a calibration, the build site asks for them. The tests drive a synthetic body instead (DESIGN.md, 0: no webcam needed for the tests).
* **The menus are clicked with the hand**, as in Steppe Rescue: the hand detector (YOLOX-Body-Head-Hand) finds the raised hands, a cursor follows each, sticks to the buttons, and clicks after holding still for 2 s (`HandCursor.DWELL_SECONDS`; Steppe Rescue uses 3 s). The detector runs only while a screen shows the cursor; the build site switches it off while building, since the raised hands are the gestures of the crane there.
* **Full screen** by default (`--windowed` for a window).
* **Sound keys:** M switches the music, S the sound effects (so S no longer moves anything).
* **The hand lift counts relative to the other hand.** DESIGN.md, 3.3 asks for the wrist displacement relative to the shoulders; but raising or lowering the torso (the vertical control) moves both wrists relative to the shoulders, which looked like a lift. So a lift is the difference of the two wrists' calibrated lifts; both hands raised together count as "both lifted" and do nothing.
* **The vertical proxy** is 0.5 × the shoulder-to-wrist vertical distance + 0.5 × the mean elbow angle / 90°, both in the player's shoulder widths, normalized between the calibrated extremes (`PoseMeasure.ELBOW_WEIGHT`). DESIGN.md asks to choose the most reliable during the tests: **to be tuned with real players.**
* **Resuming after a tracking loss** works with the keyboard, the pause button, or, after holding the neutral posture for 0.5 s, a lift and return of the right hand, which then only resumes and never places.
* **The catalogue cursor** maps the raised left wrist's offset from the left shoulder (±2 shoulder widths across, ±1.5 up and down) onto the row of catalogue entries.
* **The pose log.** `-- --log-pose[=<lines a second>]` logs the pose and what the controls make of it as JSON lines (only numbers, no pictures), on the build site and in the calibration; `dev/pose/analyze_pose_log.py` summarizes them (tracking losses, low-confidence joints, gestures started vs. completed, hook movement during a pending gesture, key point jumps) and writes a CSV. We log instead of recording, since a recording of the frames is too heavy for the disk, and the log finds most bugs.
* **Untested with real players.** The calibration, the thresholds and the gestures are tested with synthetic pose sequences only (`tests/godot/test_input.gd`). Nothing about the camera position, the false-trigger rates, the lighting or the body proportions has been measured yet (DESIGN.md, 11, M4).

## The construction

* **The hook's tip is the bottom-centre of the carried part** (of an edge part: its first edge): a part lands on the floor at the hook's height, which makes placing on floors easy. The preview snaps to the nearest valid anchor within one cell (two cells down).
* **Windows overlay the back wall.** DESIGN.md, 2.3 offers an atomic replacement or a rejection. Since a 2 × 2 window can not replace a part of a 2 × 6 back wall without a filler part, windows live in their own background slot (`window`) over the back wall, conflicting only with other windows. Removing a window shows the back wall again.
* **Floors and roofs.** A contiguous run of floor or roof edges at one height is anchored where it rests on a supported wall or beam; the edges between the outermost anchors are supported (no span limit in the MVP), and up to 2 cells beyond (the overhang). Farther edges are "connected but overhanging": the player may build a span from one side (placing is allowed, with a warning), but nothing can stand on them and the submission is blocked until the span is closed.
* **An edge may not cut through a volume** (a wall through a bed, a floor through stairs), and a volume may not be placed around an existing edge.
* **Stairs** are 6 × 6 cells; their landings are the bottom-left cell and the cell one storey up above their last column (mirrored: the other way round). People walk past stairs; the top landing needs a floor (warning while building, blocking the submission). Ladders link their foot to the cell one storey up.
* **Walking collision.** No furniture blocks walking in the MVP (`blocked_cells` are empty), so people walk past tables and beds in the cutaway and use them from their bottom row; beams block their cells. Decorations never block.
* **Doors** are 4 cells high; a wall with a door is a door plus a short wall of 2 above it.
* **The undo history is not saved**: it starts empty whenever a site is opened (DESIGN.md, 10 allows this).

## The missions

* **Objective parameters.** `usable_tag_count` has, besides `tag`, `minimum` and `zone`: `indoors`, `outdoors`, `reachable` (default true; false for trees, flowers and windows) and `count_instances` (count parts instead of summing capacities like `seat_capacity:2`).
* **`all_of`** is a composite objective, added for the wishes which combine two conditions (e.g., "an outdoor bench and four green cells").
* **"Windows facing enclosed cells"** counts windows with a cell inside a room.
* **A Place to Sit** asks for seats for two (a bench or two chairs), not for a bench: a problem, not a blueprint.
* **Each objective has its own text key** per mission (`OBJ_<MISSION>_<ID>`), since the same ID means different things in different missions.
* **`preserve_instances`** refers to the IDs of the site's protected initial parts, which are numbered 1, 2, … in the order of `initial_instances`. No current mission uses it.
* **"Needs repair"**: a completed mission whose site was edited into an invalid state shows as needing repair; nothing is taken back.

## The character

* **Implemented perks:** Golden Hands (alignment guides and coordinates of the preview), The Colourist (colour variants with C) and Jack of All Trades (+5 to every skill). The other perks are listed, but can not be taken ("coming later"), and use no token.
* **Implemented traits:** Traditionalist, Modernist, Naturalist and Specialist. Perfectionist and Autodidact are not selectable.
* **Advanced parts** (one per skill line, each with a real effect in the existing mechanics): stone wall (Masonry 40), large window (Glassworking 40), large tree (Landscaping 40), sofa for three (Interior design 40), steel beam of 6 (Metalworking 40). A Bricklayer and a Gardener thus start with different advanced parts, and both complete every mission with the basic parts.
* **Practice** is implemented (DESIGN.md, 4.2): each part has a `craft_skill`.

## The interface

* **Sound and music.** M switches the music off and on, S the effects. The effects are cut from CC0 recordings on Freesound (`dev/sounds/`), the music is rendered from CC0 and public-domain MIDI files on Wikimedia Commons (`dev/music/`) with our own synthesized instruments, so no sound font is needed. The music is work songs and the songs of the journeymen on their Wanderschaft (the years of travel of the craftsmen, from master to master), plus two rags. The cut points of the effects were chosen from their loudness envelopes, not by ear: **listen to them and adjust `dev/sounds/sources.json`.** Nothing sounds like an alarm or a timer (DESIGN.md, 7); the invalid placement is a soft knock.
* **Plurals.** The English texts are written so that they need no plural forms; `Ui.plural` (KEY_ONE / KEY_OTHER) is ready for the first one that does.
* **The city map** is a list of the projects (DESIGN.md, 6 allows a list first).
* **Local cooperation**: a helper can click the catalogue with the mouse while the builder steers the crane with the body; nothing else yet.
* **Art.** Every picture is a placeholder vector drawing (`scenes/art/part_art.gd`). The sprites will come later (made with an image generator, as in the other games); they replace the drawings per `visual_id` without changing the footprints.

## Open questions

* The camera position and the gesture thresholds need trials with children and adults, in the plank, kneeling and seated postures.
* The vertical control may be easier as a rise of the hips instead of the torso, depending on the camera angle.
* The balance (rewards, skills, unlock thresholds) is untested.
* The exports for Windows and macOS are untested (and not set up).
