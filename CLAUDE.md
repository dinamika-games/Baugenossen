# Notes for Claude Code

Read [DESIGN.md](DESIGN.md) (the specification), [docs/DECISIONS.md](docs/DECISIONS.md) (the deviations; record new ones there) and [CONTRIBUTING.md](CONTRIBUTING.md) (how to run and test).

* Godot 4.6.2 .NET: `export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64`.
* Before finishing: `venv/bin/python dev/continuous_integration/precommit.py --overwrite`. One Godot test: `$GODOT --headless --fixed-fps 60 --path . --script tests/godot/test_<name>.gd`.
* The rules live in pure `RefCounted` classes (`scenes/construction/`, `scenes/missions/`, `scenes/progression/`, `scenes/input/`, `scenes/session/`); the screens only show and forward. Never put game state into nodes.
* Content is data (`data/*.json`), validated by `ContentDb` at load; an unknown objective type must fail the load.
* Every visible text goes through `tr("KEY")` with a key in `translations/translations.csv`; `tests/godot/test_localization.gd` checks the coverage. Use named placeholders, never glue sentences.
* No inline lambdas spanning several lines inside call arguments: gdformat reflows them into code Godot can not parse; use a method.
* Tests write only into `user://tests/`; never touch the player's saves or settings.
