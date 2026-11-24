#!/usr/bin/env python3

"""
Check the translations in translations/<language>.po.

Report per language how many messages are translated, how many are still to
be reviewed (fuzzy) and how many are missing; list them with --verbose.

Fail on errors which would break the game:

* a translation which drops, adds or misspells a placeholder (``{part}``),
* a word which agrees with a number (``{count|Sitz|Sitze}``) whose number
  the English message does not have,
* a choice for the builder's gender (``{builder|Baumeister|Baumeisterin}``,
  see scenes/languages/grammar.gd) without exactly two forms,
* a translation which is longer than the limit in its translator comment
  ("at most N characters").
"""

import argparse
import pathlib
import re
import sys
from typing import List

import polib

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import extract  # noqa: E402  # pylint: disable=wrong-import-position

PLACEHOLDER_RE = re.compile(r"\{([a-z_]+)\}")
AGREEMENT_RE = re.compile(r"\{([a-z_]+)\|[^{}]*\}")
BUILDER_RE = re.compile(r"\{builder\|([^{}]*)\}")
LIMIT_RE = re.compile(r"at most (\d+) characters")


def _where(entry: polib.POEntry) -> str:
    if entry.occurrences:
        path, line = entry.occurrences[0]
        return f"{path}:{line}" if line else path
    return "?"


def check(language: str, verbose: bool) -> List[str]:
    """Check one language and return the errors."""
    path = extract.TRANSLATIONS_DIR / f"{language}.po"
    if not path.exists():
        return [f"{path.relative_to(REPO_ROOT)} is missing; run dev/translations/extract.py"]

    po = polib.pofile(str(path))
    errors: List[str] = []
    missing: List[polib.POEntry] = []
    fuzzy: List[polib.POEntry] = []
    done = 0

    for entry in po:
        if entry.obsolete:
            continue
        if not entry.msgstr:
            missing.append(entry)
            continue
        if "fuzzy" in entry.flags:
            fuzzy.append(entry)
        else:
            done += 1

        expected = sorted(set(PLACEHOLDER_RE.findall(entry.msgid)))
        found = sorted(set(PLACEHOLDER_RE.findall(entry.msgstr)))
        for forms in BUILDER_RE.findall(entry.msgstr):
            if len(forms.split("|")) != 2:
                errors.append(
                    f"{language}: {_where(entry)}: the choice {{builder|{forms}}} needs exactly "
                    "two forms (constructor, constructrice)"
                )
        for agreed in AGREEMENT_RE.findall(entry.msgstr):
            if agreed != "builder" and agreed not in expected:
                errors.append(
                    f"{language}: {_where(entry)}: the word agrees with {{{agreed}}}, "
                    f"which {entry.msgid!r} does not have"
                )
        if expected != found:
            errors.append(
                f"{language}: {_where(entry)}: the placeholders {found} of the translation "
                f"do not match {expected} of {entry.msgid!r}"
            )

        limit = LIMIT_RE.search(entry.comment or "")
        shown = BUILDER_RE.sub(lambda m: max(m.group(1).split("|"), key=len), entry.msgstr)
        if limit and len(shown) > int(limit.group(1)):
            errors.append(
                f"{language}: {_where(entry)}: the translation is {len(shown)} characters "
                f"long, but at most {limit.group(1)} fit: {shown!r}"
            )

    total = done + len(fuzzy) + len(missing)
    print(
        f"{language}: {done}/{total} translated and reviewed, "
        f"{len(fuzzy)} to review (fuzzy), {len(missing)} missing"
    )
    if verbose:
        for title, entries in (("to review", fuzzy), ("missing", missing)):
            for entry in entries:
                print(f"  {title}: {_where(entry)}: {entry.msgid!r}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="List the open messages.")
    args = parser.parse_args()

    errors: List[str] = []
    for language in extract.LANGUAGES:
        errors.extend(check(language, args.verbose))

    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
