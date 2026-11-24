# Contributing

## Overview

The game is made with [Godot] 4.6 (.NET), in GDScript and C#, like the other Dinamika games.

* **The construction model** (`scenes/construction/`) is pure GDScript without nodes: `WorldGrid` (the parts and their slots: cells, edges, background), `PartDef` and `PartInstance`, `Placement` (validation: offer, unlocks, mass, geometry, support), `EditCommand` and `CommandHistory` (atomic edits, undo/redo), `SupportEvaluator`, `RoomDetector` and `NavigationGraph`.
* **The missions** (`scenes/missions/`): `Objectives` (validation and the predicates), `SiteAnalysis` (support, rooms and reachability once per edit), `MissionEvaluator` and `MissionText`.
* **The character** (`scenes/progression/`): `Character` and `Progression` (attributes, skills, levels, karma, perks, unlocks, practice, rewards once).
* **The saves** (`scenes/session/`): `SaveRepository` (atomic JSON with backup and migration), `GameSession` (the character and every mission's site), and the `Game` autoload, which holds them for the screens.
* **The input** (`scenes/input/`): `InputDispatcher` (the semantic commands and the input states), `InputActions` (the keyboard), and the body controls: `PoseProvider` (with `VisionPoseProvider` and `SyntheticPoseProvider`), `PoseMeasure`, `PoseCalibration`, `PoseController` (smoothing, dead zone, velocity, freezing, hand-lift gestures) and `DwellSelector`.
* **The vision** (`scenes/vision/`, C#), taken over from Drunken Vikings: `VisionService` runs the camera and `PoseFollower` (RTMO finds the builder, RTMPose-t follows them) on a background thread. The core (`scenes/vision/core/`) does not depend on Godot and is unit-tested with plain .NET in `tests/Baugenossen.Tests/`.
* **The content** is data: `data/parts.json`, `skills.json`, `backgrounds.json`, `traits.json`, `perks.json`, `sites.json`, `residents.json` and `missions.json`, loaded and validated by `ContentDb` (`scenes/content/`).
* **The screens**: `main_menu/`, `character_creation/`, `city_map/`, `build_site/` (`SiteView` draws, `BuildHud` and `BuildOverlays` show, `build_site.gd` decides), `character_sheet/`, `mission_results/`, `settings/` and `calibration/`. `scenes/art/part_art.gd` draws every part as placeholder vector art; `scenes/ui/ui.gd` builds the interface.

[Godot]: https://godotengine.org

## Setting up

You need [Git LFS] (the ONNX models are in LFS), the .NET 8 SDK, the **.NET** build of Godot 4.6.2 and Python 3.10+.

```
git lfs install
git lfs pull
export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64
python3 -m venv venv && touch venv/.gdignore
venv/bin/pip install -r dev/requirements.txt
dotnet build Baugenossen.sln
$GODOT --headless --path . --import
$GODOT --path .
```

**Do not skip the `.gdignore`!** Godot would otherwise try to import the virtual environment.

[Git LFS]: https://git-lfs.com

## Running

`$GODOT --path .` starts at the main menu. The options after `--`:

* `--no-camera`: forbid the camera (then the hook can not move),
* `--synthetic-pose`: a made-up body, standing still, instead of the camera, to try the plumbing,
* `--saves=user://other_saves` and `--settings=user://other.cfg`: keep the saves and the calibration elsewhere,
* `--mute`: start without sound, `--no-music`: without the music (M switches the music, S the effects anytime),
* `--high-contrast`, `--reduced-motion`, `--no-mirror`, `--sensitivity=<0.25 to 2>`, `--dead-zone=<0.05 to 0.4>`: there is no settings screen, so these are chosen here,
* `--windowed` (of Godot, before `--`): run in a window instead of full screen,
* `--log-pose` or `--log-pose=<lines a second>` (10 by default): log the body pose (see below).

## The pose log

To find the bugs of the body controls without recording any pictures (a recording is too heavy for the disk), start the game with `-- --log-pose`.
On the build site and in the calibration, the game then writes lines starting with `POSE ` with one JSON object each: the key points (as the camera sees them, normalized, with their confidence), the measures (`h`, `v`, the lifts, the shoulder width), the smoothed signal, the velocity of the hook, the phases of the hand gestures, the input state and the events (gestures, calibration steps), the events always at once.
They go to the standard output and to Godot's log file (`~/.local/share/godot/app_userdata/Baugenossen/logs/godot.log` on Linux). Then:

```
python3 dev/pose/analyze_pose_log.py godot.log --csv pose.csv
```

prints, for each screen, the sample rate, the stale frames, the joints with low confidence, the time frozen and lost, the gestures started, completed and cancelled (many cancelled ones hint at false triggers), any hook movement while a gesture pends (a bug), the range of each measure against the calibration and the jumps of key points; the CSV has every sample for a plot.
Log only with the player's consent; the log has no pictures, but it is a record of their movements.

The camera starts with the game (not in headless runs). The hook moves only with the body: calibrate once from the main menu ("Calibrate the body controls"); the calibration is kept in `user://settings.cfg`. The keyboard and the mouse help with everything else, never with the hook. In the menus, the hand cursor (`scenes/hand_cursor/`, the autoload `HandCursor`, from Steppe Rescue) follows a raised hand, found by the hand detector (YOLOX) of the vision, sticks to the buttons and clicks them after two seconds; it works with every ordinary Godot button, and the screens use big ◀/▶ choosers (`Chooser`) instead of drop-down lists, which a hand can not open.

## Checks before a pull request

```
venv/bin/python dev/continuous_integration/precommit.py --overwrite
```

This formats (gdformat, `dotnet format`, black), lints (gdlint), runs the .NET tests, builds the C# part, imports the project, type-checks every GDScript and runs the Godot tests (`tests/godot/test_*.gd`). Without `--overwrite`, it only checks the formatting.

The Godot tests:

* `test_construction.gd`: edges, footprints, layers, atomic placement, support chains and floating cycles, overhangs, undo/redo, protected parts, windows, moves, mass and locks, serialization;
* `test_missions.gd`: rooms and doors, roof gaps, stairs, green area, distinct-room matching, unknown objective types, and every initial mission with several valid layouts (`sample_builds.gd`) and the failures of DESIGN.md, 11, M2;
* `test_progression.gd`: the creation budget, the skill formula, backgrounds and traits, caps, levels, rewards once, perks, unlocks per background, practice;
* `test_persistence.gd`: roundtrip, incomplete sites, backup after corruption, unknown versions, migration, invalid values, no duplicate rewards after a restart;
* `test_input.gd`: synthetic pose sequences: calibration, neutral, the axes, one gesture is one placement, tracking loss, reacquisition, the catalogue, concurrent confirms, dwell;
* `test_body_loop.gd`: plays the tutorial with a synthetic body (leaning, rising, hand lifts), and checks that neither the keys nor the mouse move the hook; `test_hand_cursor.gd`: the dwell clicks, toggles, disabled and scrolled-away buttons, and scrolling;
* `test_screens.gd`: starts every screen; `test_localization.gd`: the translation coverage.

Run one with `$GODOT --headless --fixed-fps 60 --path . --script tests/godot/test_missions.gd`. The tests write only into `user://tests/`.

## Screenshots

To review the screens and the placeholder art without playing (needs a display, or `xvfb-run`):

```
xvfb-run -a $GODOT --path . --audio-driver Dummy --resolution 1280x720 \
    --script dev/screenshots/take_screenshots.gd -- /tmp/shots
```

## Sounds and music

The effects are cut from CC0 recordings on Freesound, listed in `dev/sounds/sources.json` (the recording, its author, and the cut in seconds); a loop is cross-faded at its seam. The music is listed in `dev/music/sources.json`: CC0 and public-domain MIDI files from Wikimedia Commons, rendered with our own synthesized instruments (no sound font). The `.ogg` files (and the `.mid` files) are in the repository; you need this only to change them (sox with Vorbis, e.g., `apt install sox libsox-fmt-all`, and NumPy from `dev/requirements.txt`):

```
venv/bin/python dev/sounds/cut_sounds.py [name ...]
venv/bin/python dev/music/fetch_music.py [slug ...]
venv/bin/python dev/music/render_music.py [slug ...]
```

Both scripts check on the page that each source is still under its license. List every new sound and song in THIRD_PARTY_NOTICES.md. `scenes/sound/sounds.gd` (the autoload `Sounds`) plays `assets/sounds/<name>.ogg` and shuffles the songs of `assets/music/`; a missing file is skipped.

## Content

* **A part**: add it to `data/parts.json` (the layer, the footprint, the tags, the support rule, the requirements for advanced parts), its name and description to `translations/translations.csv`, and its drawing to `PartArt.draw_part` (by `visual_id`).
* **A mission**: add it to `data/missions.json` with only implemented objective types (see `Objectives.TYPES`), its texts to the translations, and at least two sample solutions and the failures to `tests/godot/sample_builds.gd` and `test_missions.gd` before making it selectable (DESIGN.md, 5.4).
* **The sprites** will replace the vector drawings: draw `assets/parts/<visual_id>.png` in `PartArt.draw_part` and keep the footprints. Record the provenance in THIRD_PARTY_NOTICES.md.

## Translations

English is the source language. Every visible text is a key in `translations/translations.csv` (`keys,en`), looked up with `tr("KEY")`, with named placeholders (`tr("KEY").format({"name": value})`). Never glue a sentence together from pieces, and never use a text as an ID. To add a language, add a column and its code to `Settings.LOCALES`.

## Commit messages

We follow Chris Beams' [guidelines on commit messages](https://chris.beams.io/posts/git-commit/).
