#!/usr/bin/env python3

"""
Collect the translatable messages of the game into translations/messages.pot,
and update the translations (translations/<language>.po) with them.

The messages come from:

* the ``tr("...")`` and ``tr("...", "context")`` calls in the GDScripts of
  scenes/; a comment line starting with ``# TRANSLATORS:`` right above a call
  is passed on to the translators;
* the table of the messages with an ID, ``Texts.MESSAGES`` in
  scenes/languages/texts.gd (the ID becomes the context of the message, so
  that the translators see what it is);
* the text fields of the content in data/*.json (the names, the descriptions,
  the titles, the briefs, the thanks and the objectives).

The existing translations are kept. A new message gets an empty translation,
and a message which is not used any more is marked as obsolete. With --check,
nothing is written and the script fails if the files are out of date.
"""

import argparse
import json
import pathlib
import re
import sys
from typing import Dict, List, Optional, Tuple

import polib

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

TRANSLATIONS_DIR = REPO_ROOT / "translations"

SOURCE_LANGUAGE = "en"


def _read_languages() -> List[str]:
    """Read the codes of the languages besides the source language (English)."""
    path = TRANSLATIONS_DIR / "languages.json"
    codes = [language["code"] for language in json.loads(path.read_text(encoding="utf-8"))]
    return [code for code in codes if code != SOURCE_LANGUAGE]


#: The languages besides English, from translations/languages.json, which lists
#: every language of the game. A new language needs only a new entry there; this
#: script then creates its .po file.
LANGUAGES = _read_languages()

_STRING = r'"((?:[^"\\]|\\.)*)"'

TR_RE = re.compile(r"\btr\(\s*" + _STRING + r"(?:\s*,\s*" + _STRING + r")?\s*\)", re.DOTALL)

#: An entry of Texts.MESSAGES: "ID": "English text",
TEXTS_RE = re.compile(r'^\s*"([A-Z0-9_]+)":\s*' + _STRING + r",?\s*$", re.MULTILINE)

TEXTS_PATH = REPO_ROOT / "scenes" / "languages" / "texts.gd"

TRANSLATORS_RE = re.compile(r"#\s*TRANSLATORS:\s*(.*)$")

#: The translatable fields of the content in data/*.json, and what they are.
DATA_FIELDS = {
    "name": "a name (of a part, a category, an attribute, a perk, a site, a resident or a zone)",
    "description": "what a part, an attribute or a perk does, one short sentence",
    "title": "the title of a project, a few words",
    "brief": "the problem of the residents, two short sentences",
    "thanks": "what the residents say after moving in, one or two short sentences",
    "text": "an objective; {current} and {required} are numbers",
}

#: The fields of data/*.json which are not translated even though named so
#: (the first names of the builders are names).
SKIPPED_FILES = {"names.json"}

#: (context, message id)
Key = Tuple[str, str]


def _unescape(text: str) -> str:
    return text.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def _add(
    entries: Dict[Key, polib.POEntry],
    msgid: str,
    context: str,
    relative: str,
    comment: Optional[str],
) -> None:
    key = (context, msgid)
    entry = entries.get(key)
    if entry is None:
        entry = polib.POEntry(msgid=msgid, msgstr="")
        if context:
            entry.msgctxt = context
        entries[key] = entry
    # NOTE (mristin):
    # We record only the file, not the line, so that the translation files do
    # not change whenever the code moves.
    if (relative, "") not in entry.occurrences:
        entry.occurrences.append((relative, ""))
    if comment and comment not in (entry.comment or ""):
        entry.comment = (entry.comment + "\n" if entry.comment else "") + comment


def _collect_scripts(entries: Dict[Key, polib.POEntry]) -> None:
    for path in sorted((REPO_ROOT / "scenes").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(REPO_ROOT).as_posix()
        lines = text.splitlines()
        for match in TR_RE.finditer(text):
            msgid = _unescape(match.group(1))
            if msgid == "":
                continue
            context = _unescape(match.group(2)) if match.group(2) is not None else ""
            line = text.count("\n", 0, match.start()) + 1
            comment = None
            for previous in reversed(lines[: line - 1]):
                translators = TRANSLATORS_RE.search(previous.strip())
                if translators:
                    comment = translators.group(1)
                    break
                if previous.strip() and not previous.strip().startswith("#"):
                    break
            _add(entries, msgid, context, relative, comment)


def _collect_texts(entries: Dict[Key, polib.POEntry]) -> None:
    text = TEXTS_PATH.read_text(encoding="utf-8")
    relative = TEXTS_PATH.relative_to(REPO_ROOT).as_posix()
    for match in TEXTS_RE.finditer(text):
        _add(entries, _unescape(match.group(2)), "", relative, f"message {match.group(1)}")


def _collect_data_value(
    entries: Dict[Key, polib.POEntry], value: object, relative: str, field: str = ""
) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            _collect_data_value(entries, item, relative, key)
    elif isinstance(value, list):
        for item in value:
            _collect_data_value(entries, item, relative, field)
    elif isinstance(value, str) and field in DATA_FIELDS and value != "":
        _add(entries, value, "", relative, DATA_FIELDS[field])


def collect_messages() -> Dict[Key, polib.POEntry]:
    """Collect the messages of the scripts, the texts and the data, in a stable order."""
    entries: Dict[Key, polib.POEntry] = {}
    _collect_scripts(entries)
    _collect_texts(entries)
    for path in sorted((REPO_ROOT / "data").glob("*.json")):
        if path.name in SKIPPED_FILES:
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        _collect_data_value(entries, data, path.relative_to(REPO_ROOT).as_posix())
    return entries


def _key(entry: polib.POEntry) -> Key:
    return (entry.msgctxt or "", entry.msgid)


def make_template(entries: Dict[Key, polib.POEntry]) -> polib.POFile:
    template = polib.POFile(wrapwidth=100)
    template.metadata = {
        "Project-Id-Version": "Baugenossen",
        "MIME-Version": "1.0",
        "Content-Type": "text/plain; charset=UTF-8",
        "Content-Transfer-Encoding": "8bit",
    }
    for entry in entries.values():
        template.append(entry)
    return template


def merge(template: polib.POFile, existing: Optional[polib.POFile], language: str) -> polib.POFile:
    """Make the translation of the template, keeping the existing translations."""
    old: Dict[Key, polib.POEntry] = {}
    if existing is not None:
        old = {_key(entry): entry for entry in existing}

    result = polib.POFile(wrapwidth=100)
    result.metadata = dict(template.metadata)
    result.metadata["Language"] = language
    if existing is not None:
        for name in ("Last-Translator", "Language-Team", "Plural-Forms"):
            if name in existing.metadata:
                result.metadata[name] = existing.metadata[name]

    used = set()
    for entry in template:
        merged = polib.POEntry(
            msgid=entry.msgid,
            msgctxt=entry.msgctxt,
            msgstr="",
            occurrences=list(entry.occurrences),
            comment=entry.comment,
        )
        previous = old.get(_key(entry))
        if previous is not None:
            used.add(_key(entry))
            merged.msgstr = previous.msgstr
            merged.flags = [flag for flag in previous.flags if flag != "obsolete"]
            merged.tcomment = previous.tcomment
        result.append(merged)

    # NOTE (mristin):
    # We keep the unused translations as obsolete, so that a message which comes
    # back does not have to be translated again.
    for key, previous in old.items():
        if key not in used and previous.msgstr:
            previous.obsolete = True
            result.append(previous)

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write anything; fail if the translation files are out of date.",
    )
    args = parser.parse_args()

    template = make_template(collect_messages())

    outputs: List[Tuple[pathlib.Path, str]] = [(TRANSLATIONS_DIR / "messages.pot", str(template))]
    for language in LANGUAGES:
        path = TRANSLATIONS_DIR / f"{language}.po"
        existing = polib.pofile(str(path), wrapwidth=100) if path.exists() else None
        outputs.append((path, str(merge(template, existing, language))))

    stale = [path for path, text in outputs if not path.exists() or path.read_text("utf-8") != text]
    if args.check:
        for path in stale:
            print(
                f"{path.relative_to(REPO_ROOT)} is out of date; run dev/translations/extract.py",
                file=sys.stderr,
            )
        return 1 if stale else 0

    TRANSLATIONS_DIR.mkdir(exist_ok=True)
    for path, text in outputs:
        if path in stale:
            path.write_text(text, encoding="utf-8")
            print(f"Wrote {path.relative_to(REPO_ROOT)}")
    print(f"{len(template)} message(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
