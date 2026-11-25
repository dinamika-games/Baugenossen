# Baugenossen — A City Built Together

**Baugenossen is a very simple, nonviolent construction game played with push-ups: you work for a housing cooperative, and you build what the residents ask for, seen from the side, with a crane you steer with your body: take a block from the yard, put it wherever you want, lift it again to put it elsewhere.**

Every project is a problem, not a blueprint: a bench under a tree, a first home, a garden, a workshop.
Any design that solves it counts.
Five blocks wait in the yard; when you take one, a new one comes in, and now and then the oldest one leaves (first in, first out), so the choice keeps changing.

See [DESIGN.md](DESIGN.md) for the design and [CONTRIBUTING.md](CONTRIBUTING.md) for how to run, test and develop the game.

**No network access.**
The game runs entirely on your computer and works offline.
The camera starts with the game; its pictures are processed locally, in memory, and are never saved nor sent anywhere.

## Status

The first vertical slice is implemented with placeholder vector art:

* the construction model (grid, layers, placement, support, undo/redo, rooms, navigation),
* the four initial missions with their objectives, residents moving in, review and results,
* the yard of five blocks (first in, first out), bringing the parts which the mission still needs more often,
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
* lower the empty hook onto a block in the yard (on the left) to grab it;
* carry it over the site and go down until it sits: it is put there (a ghost shows where it lands);
* lower the empty hook onto a placed block to lift it up again, and put it elsewhere, or throw it into the skip at the far left of the yard;
* when everything the residents need is there, a bell appears right of the site: lower the hook onto it to hand the building over.

Your hands stay on the floor while you build. There is no helper and no keyboard control: the keyboard only pauses (**P**), and **Esc** twice quits.

In the menus, raise a hand: a hand cursor follows it, sticks to the buttons, and clicks a button when you hold it there for two seconds (a ring fills around the button). The mouse works, too.

**Sound:** press **M** to switch the music off and on, and **S** to switch the sound effects off and on.

## License

Baugenossen is licensed under the [MIT License](LICENSE).
The third-party components (e.g., Godot Engine, ONNX Runtime and the pose models) keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
