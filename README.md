# Baugenossen — A City Built Together

**Baugenossen is a nonviolent, motion-controlled construction game: you work for a housing cooperative, and you design and build what the residents ask for, part by part, with a crane you steer with your body (or the keyboard).**

Every project is a problem, not a blueprint: a bench under a tree, a first home, a garden, a workshop.
Any design that solves it counts.
Your builder grows with the projects (attributes, skills, perks); karma is the residents' gratitude, not money.

See [DESIGN.md](DESIGN.md) for the design, [docs/DECISIONS.md](docs/DECISIONS.md) for where and why the implementation deviates from it, and [CONTRIBUTING.md](CONTRIBUTING.md) for how to run, test and develop the game.

**No network access.**
The game runs entirely on your computer and works offline.
The camera starts with the game; its pictures are processed locally, in memory, and are never saved nor sent anywhere.

## Status

The first vertical slice (DESIGN.md, milestones M0 to M4) is implemented with placeholder vector art:

* the construction model (grid, layers, placement, support, undo/redo, rooms, navigation),
* the four initial missions with their objectives, residents moving in, review and results,
* character creation, skills, backgrounds, traits, levels, karma, three working perks and a handful of advanced parts,
* saving and resuming, with backups and migration,
* the keyboard and mouse controls, and the body controls (calibration, smoothing, hand-lift gestures) on the RTMO and RTMPose models, and a hand cursor for the menus on the YOLOX hand detector.

The sound effects are cut from CC0 recordings, and the music is work songs and the old songs of the journeymen on their Wanderschaft.

The body controls are tested only with synthetic pose sequences so far, not yet with real players and cameras (see docs/DECISIONS.md).
The sprites will replace the vector drawings later.

## Controls

The game runs full screen and is played with the body: **the hook moves only when you move.** Calibrate once (main menu, "Calibrate the body controls"), then:

* lean left and right, raise and lower your torso to move the hook;
* lift and lower your right hand to place the part;
* lift and lower your left hand to open the catalogue, then point with the raised left hand and lower it to choose.

In the menus, raise a hand: a hand cursor follows it, sticks to the buttons, and clicks a button when you hold it there for two seconds (a ring fills around the button). The mouse works, too.

**Sound:** press **M** to switch the music off and on, and **S** to switch the sound effects off and on.

A helper next to the player may use the keyboard and the mouse, but never for the hook: Space or a click places · Tab opens the catalogue (the arrows choose there) · X removes · G moves a part · Q mirrors · C changes the colour (with the perk The Colourist) · Ctrl+Z / Ctrl+Y undo and redo · Enter reviews and hands over · P or Esc pauses · +/− and the wheel zoom · I/J/K/L or the middle mouse button pan · Home re-centres the body controls.

## License

Baugenossen is licensed under the [MIT License](LICENSE).
The third-party components (e.g., Godot Engine, ONNX Runtime and the pose models) keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
