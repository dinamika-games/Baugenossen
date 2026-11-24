# Contributing

## Overview

The game is made with [Godot] 4.6 (.NET), in GDScript and C#, like the other Dinamika games.

* **The construction model** (`scenes/construction/`) is pure GDScript without nodes: `WorldGrid` (the parts and their slots: cells, edges, background), `PartDef` and `PartInstance`, `Placement` (validation: offer, mass, geometry, support), `EditCommand` and `CommandHistory` (atomic edits, undo/redo), `SupportEvaluator`, `RoomDetector`, `NavigationGraph`, and `BlockQueue` (the row of five blocks, first in, first out).
* **The missions** (`scenes/missions/`): `Objectives` (validation and the predicates), `SiteAnalysis` (support, rooms and reachability once per edit), `MissionEvaluator` and `MissionText`.
* **The progress** (`scenes/progression/`): `Progress` (the completed missions and wishes) and `Progression` (missions open in order, completions count once).
* **The saves** (`scenes/session/`): `SaveRepository` (atomic JSON with backup and migration), `GameSession` (the progress and every mission's site), and the `Game` autoload, which holds them for the screens.
* **The input** (`scenes/input/`): `InputDispatcher` (the semantic commands and the input states), `InputActions` (the keyboard), and the body controls: `PoseProvider` (with `VisionPoseProvider` and `SyntheticPoseProvider`), `PoseMeasure`, `PoseCalibration`, `PoseController` (smoothing, dead zone, velocity, freezing, short and full dips, hand lifts, which the build site switches off) and `DwellSelector`.
* **The vision** (`scenes/vision/`, C#), taken over from Drunken Vikings: `VisionService` runs the camera and `PoseFollower` (RTMO finds the builder, RTMPose-t follows them) on a background thread. The core (`scenes/vision/core/`) does not depend on Godot and is unit-tested with plain .NET in `tests/Baugenossen.Tests/`.
* **The content** is data: `data/parts.json`, `sites.json`, `residents.json` and `missions.json`, with their texts in English, loaded and validated by `ContentDb` (`scenes/content/`).
* **The screens**: `main_menu/`, `city_map/`, `build_site/` (`SiteView` draws, `BuildHud` and `BuildOverlays` show, `build_site.gd` decides), `mission_results/` and `settings/` (the settings store, no screen). `scenes/art/part_art.gd` draws every part as placeholder vector art; `scenes/ui/ui.gd` builds the interface.

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
* `--synthetic-pose`: a made-up body in the push-up position, holding still, instead of the camera, to try the plumbing,
* `--saves=user://other_saves` and `--settings=user://other.cfg`: keep the saves and the settings elsewhere,
* `--mute`: start without sound, `--no-music`: without the music (M switches the music, S the effects anytime),
* `--high-contrast`, `--reduced-motion`, `--no-mirror`, `--sensitivity=<0.25 to 2>`, `--dead-zone=<0.05 to 0.4>`: there is no settings screen, so these are chosen here,
* `--windowed` (of Godot, before `--`): run in a window instead of full screen,
* `--log-pose` or `--log-pose=<lines a second>` (10 by default): log the body pose (see below).

## The pose log

To find the bugs of the body controls without recording any pictures (a recording is too heavy for the disk), start the game with `-- --log-pose`.
On the build site (also while the crane learns the posture), the game then writes lines starting with `POSE ` with one JSON object each: the key points (as the camera sees them, normalized, with their confidence), the measures (`h`, `v`, the lifts, the shoulder width), the smoothed signal, the velocity of the hook, the phases of the hand gestures, the input state and the events (gestures, calibration steps), the events always at once.
They go to the standard output and to Godot's log file (`~/.local/share/godot/app_userdata/Baugenossen/logs/godot.log` on Linux). Then:

```
python3 dev/pose/analyze_pose_log.py godot.log --csv pose.csv
```

prints, for each screen, the sample rate, the stale frames, the joints with low confidence, the time frozen and lost, the gestures started, completed and cancelled (many cancelled ones hint at false triggers), any hook movement while a gesture pends (a bug), the range of each measure against the calibration and the jumps of key points; the CSV has every sample for a plot.
Log only with the player's consent; the log has no pictures, but it is a record of their movements.

The camera starts with the game (not in headless runs). The hook moves only with the body, which calibrates itself on every build site (`AutoCalibration`): the player holds still in the push-up position for a moment. The keyboard and the mouse help with everything else, never with the hook. In the menus, the hand cursor (`scenes/hand_cursor/`, the autoload `HandCursor`, from Steppe Rescue) follows a raised hand, found by the hand detector (YOLOX) of the vision, sticks to the buttons and clicks them after two seconds; it works with every ordinary Godot button, and the screens use big ◀/▶ choosers (`Chooser`) instead of drop-down lists, which a hand can not open.

## Checks before a pull request

```
venv/bin/python dev/continuous_integration/precommit.py --overwrite
```

This formats (gdformat, `dotnet format`, black), lints (gdlint), runs the .NET tests, builds the C# part, imports the project, type-checks every GDScript and runs the Godot tests (`tests/godot/test_*.gd`). Without `--overwrite`, it only checks the formatting.

The Godot tests:

* `test_construction.gd`: edges, footprints, layers, atomic placement, support chains and floating cycles, overhangs, undo/redo, protected parts, windows, moves, mass, serialization;
* `test_missions.gd`: rooms and doors, roof gaps, stairs, green area, distinct-room matching, unknown objective types, and every initial mission with several valid layouts (`sample_builds.gd`) and the failures of DESIGN.md, 11, M2;
* `test_progression.gd`: missions open in order, every mission solvable, completions once, the row of blocks (take, first in first out, offered and wanted parts);
* `test_persistence.gd`: roundtrip, incomplete sites, backup after corruption, unknown versions, migration, invalid values, a completion counts once after a restart;
* `test_input.gd`: synthetic pose sequences: calibration, neutral, the lean, a short dip is the next block and a push-up one placement, tracking loss, reacquisition, the catalogue, concurrent confirms, dwell;
* `test_body_loop.gd`: plays the tutorial with a synthetic body (short dips pick the blocks, leaning, push-ups place), and checks that neither the keys nor the mouse move the hook; `test_hand_cursor.gd`: the dwell clicks, toggles, disabled and scrolled-away buttons, and scrolling;
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

* **A part**: add it to `data/parts.json` (the layer, the footprint, the tags, the support rule, the requirements for advanced parts), its name and description in English (run `dev/translations/extract.py` afterwards), and its drawing to `PartArt.draw_part` (by `visual_id`).
* **A mission**: add it to `data/missions.json` with only implemented objective types (see `Objectives.TYPES`), its texts in English (run `dev/translations/extract.py` afterwards), and at least two sample solutions and the failures to `tests/godot/sample_builds.gd` and `test_missions.gd` before making it selectable (DESIGN.md, 5.4).
* **The sprites** will replace the vector drawings: draw `assets/parts/<visual_id>.png` in `PartArt.draw_part` and keep the footprints. Record the provenance in THIRD_PARTY_NOTICES.md.

## Translations

The game is written in English and translated with gettext: `translations/<code>.po` for every language of `translations/languages.json` (German so far).

* **In the code,** every text a player sees goes through `tr("...")` with the whole sentence and named placeholders, filled by `Grammar.format(tr("Remove {part}: press Space or click."), {"part": name})`. Never glue a sentence together from pieces, and keep the literal in one piece (the extraction reads it from the code). A comment `# TRANSLATORS: ...` right above the call reaches the translators, e.g., `# TRANSLATORS: a button, at most 20 characters` (the check enforces the limit).
* **Messages with an ID** (the reasons of the placement, the hints, the messages of the saves, the ranks, the input states) live in `Texts.MESSAGES` (`scenes/languages/texts.gd`) and are shown with `Texts.of(id)`; the long texts live there, too.
* **The content** in `data/*.json` holds English texts in the fields `name`, `description`, `title`, `brief`, `thanks` and `text`, translated when shown (`tr(definition.name)`).
* **Collect the messages** after changing texts:

  ```
  venv/bin/python dev/translations/extract.py
  ```

  This updates `translations/messages.pot` and merges it into every `.po` file, keeping the existing translations.
* **Numbers and gender:** a translation may agree a word with a number, `{count} {count|Sitz|Sitze}` (by the plural rule of the language, see `Grammar.plural_index`), and follow the builder's gender, `{builder|Baumeister|Baumeisterin}` (constructor, constructrice); see `scenes/languages/grammar.gd`.
* **Translate** the `.po` files with any PO editor (e.g., Poedit). A new translation stays marked *fuzzy* until a native speaker reviewed it in the game; the game shows it anyway. Review with `$GODOT --path . -- --lang=de`.
* **Add a language** with one entry in `translations/languages.json` (its code and its name in itself), run `extract.py`, set the `Plural-Forms` header of the new `.po` file, and add its plural rule to `Grammar.plural_index` if it is not "one and other".
* **Check** the placeholders and the coverage (`--verbose` lists the open messages):

  ```
  venv/bin/python dev/translations/check.py --verbose
  ```

The pre-commit checks run both: they fail if the translation files are out of date or a translation breaks a placeholder.

## Commit messages

We follow Chris Beams' [guidelines on commit messages](https://chris.beams.io/posts/git-commit/).
