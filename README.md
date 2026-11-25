# Baugenossen — A City Built Together

**Baugenossen is a nonviolent construction puzzle game played with push-ups: you work for a housing cooperative, and every level is a puzzle. The level gives you the parts and a few conditions which must hold; you take the parts with a crane you steer with your body, seen from the side, put them wherever you want, and lift them again to put them elsewhere.**

Every level is a problem, not a blueprint: a bench under a tree, a first home, a garden, a workshop.
The conditions are relations (e.g., two beds in a closed room which one can reach), so every level has many solutions, and any design that fulfils them counts.

See [DESIGN.md](DESIGN.md) for the design and [CONTRIBUTING.md](CONTRIBUTING.md) for how to run, test and develop the game.

**No network access.**
The game runs entirely on your computer and works offline.
The camera starts with the game; its pictures are processed locally, in memory, and are never saved nor sent anywhere.

## Status

The first vertical slice is implemented with placeholder vector art:

* the construction model (grid, layers, placement, support, undo/redo, rooms, navigation),
* four puzzle levels with their conditions, residents moving in, and straight on to the next level,
* puzzle levels, each with its own set of parts in the yard (enough for many solutions),
* English and a first German translation (gettext, with plural and gender forms),
* saving and resuming, with backups and migration,
* the body controls (auto-calibration, smoothing, lean and dips from the shoulders and the elbows) on the RTMO and RTMPose models, and a hand cursor for the menus on the YOLOX hand detector.

The sound effects are cut from CC0 recordings, and the music is work songs and the old songs of the journeymen on their Wanderschaft.

The body controls are tested only with synthetic pose sequences so far, not yet with real players and cameras (see DESIGN.md, section 13).
The sprites will replace the vector drawings later.

## Controls

The game runs full screen and is played with the body: **the hook moves only when you move.** Go into your push-up position (or on your knees, hands on the floor) and hold still for a moment: the crane learns your posture by itself. Then:

* lean left and right to move the hook;
* go down and up to lower and raise the hook: straight arms hold it high, the bottom of a push-up brings it to the ground;
* lower the empty hook onto a part in the yard (on the left) to grab it;
* carry it over the site and go down until it sits: it is put there (a ghost shows where it lands);
* lower the empty hook onto a placed part to lift it up again, and put it elsewhere, or lower it onto the yard to give it back;
* when all the conditions hold, the puzzle is solved and the residents move in.

While the crane learns your posture, a turning spanner shows in the middle (the hook waits); it learns anew by itself when you move your hands.

Your hands stay on the floor while you build. There is no helper and no keyboard control: the keyboard only pauses (**P**), and **Esc** twice quits.

In the menus, raise a hand: a hand cursor follows it, sticks to the buttons, and clicks a button when you hold it there for two seconds (a ring fills around the button). The mouse works, too.

**Sound:** press **M** to switch the music off and on, and **S** to switch the sound effects off and on.

## License

Baugenossen is licensed under the [MIT License](LICENSE).
The third-party components (e.g., Godot Engine, ONNX Runtime and the pose models) keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
