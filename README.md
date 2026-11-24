# Baugenossen — A City Built Together

**Baugenossen is a very simple, nonviolent construction game played with push-ups: you work for a housing cooperative, five blocks wait in a row, and you pick the one you want and put it where you want with a crane you steer with your body.**

Every project is a problem, not a blueprint: a bench under a tree, a first home, a garden, a workshop.
Any design that solves it counts.
When a block is placed, a new one comes into the row; now and then the oldest block leaves it (first in, first out), so the choice keeps changing.

See [DESIGN.md](DESIGN.md) for the design and [CONTRIBUTING.md](CONTRIBUTING.md) for how to run, test and develop the game.

**No network access.**
The game runs entirely on your computer and works offline.
The camera starts with the game; its pictures are processed locally, in memory, and are never saved nor sent anywhere.

## Status

The first vertical slice is implemented with placeholder vector art:

* the construction model (grid, layers, placement, support, undo/redo, rooms, navigation),
* the four initial missions with their objectives, residents moving in, review and results,
* the row of five blocks (first in, first out), bringing the parts which the mission still needs more often,
* English and a first German translation (gettext, with plural and gender forms),
* saving and resuming, with backups and migration,
* the keyboard and mouse controls, and the body controls (auto-calibration, smoothing, lean and dips from the shoulders and the elbows) on the RTMO and RTMPose models, and a hand cursor for the menus on the YOLOX hand detector.

The sound effects are cut from CC0 recordings, and the music is work songs and the old songs of the journeymen on their Wanderschaft.

The body controls are tested only with synthetic pose sequences so far, not yet with real players and cameras (see DESIGN.md, section 13).
The sprites will replace the vector drawings later.

## Controls

The game runs full screen and is played with the body: **the hook moves only when you move.** Go into your push-up position (or on your knees, hands on the floor) and hold still for a moment: the crane learns your posture by itself. Then:

* a half push-up (down a little, and back up) picks the next block of the row;
* lean left and right to move the hook; the block drops and shows where it lands;
* do a push-up to place it.

Your hands stay on the floor while you build.

In the menus, raise a hand: a hand cursor follows it, sticks to the buttons, and clicks a button when you hold it there for two seconds (a ring fills around the button). The mouse works, too.

**Sound:** press **M** to switch the music off and on, and **S** to switch the sound effects off and on.

A helper next to the player may use the keyboard and the mouse, but never for the hook: Space or a click places · Up/Down or a click on a block of the row choose the block · X removes · G moves a part · Q mirrors · C changes the colour · Ctrl+Z / Ctrl+Y undo and redo · Enter reviews and hands over · P pauses, Esc twice quits · +/− and the wheel zoom · I/J/K/L or the middle mouse button pan · Home learns the posture again.

## License

Baugenossen is licensed under the [MIT License](LICENSE).
The third-party components (e.g., Godot Engine, ONNX Runtime and the pose models) keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
