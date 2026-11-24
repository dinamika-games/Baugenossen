# Notes for Claude Code

Read [DESIGN.md](DESIGN.md) (the design: keep it the single description of the game, update it when the design changes, and put the open questions in its section 13) and [CONTRIBUTING.md](CONTRIBUTING.md) (how to run and test).

* Godot 4.6.2 .NET: `export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64`.
* Before finishing: `venv/bin/python dev/continuous_integration/precommit.py --overwrite`. One Godot test: `$GODOT --headless --fixed-fps 60 --path . --script tests/godot/test_<name>.gd`.
* The rules live in pure `RefCounted` classes (`scenes/construction/`, `scenes/missions/`, `scenes/progression/`, `scenes/input/`, `scenes/session/`); the screens only show and forward. Never put game state into nodes.
* Content is data (`data/*.json`), validated by `ContentDb` at load; an unknown objective type must fail the load.
* Every visible text is a whole English sentence in `tr("...")` (one literal, named placeholders, `Grammar.format`), or an ID in `Texts.MESSAGES` shown with `Texts.of(id)`; content texts are English in `data/*.json`. Run `venv/bin/python dev/translations/extract.py` after changing texts (see CONTRIBUTING.md, "Translations").
* No inline lambdas spanning several lines inside call arguments: gdformat reflows them into code Godot can not parse; use a method.
* Tests write only into `user://tests/`; never touch the player's saves or settings.
