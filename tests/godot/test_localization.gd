extends "res://tests/godot/godot_test.gd"
## Check the translations (DESIGN.md, 8): the languages are registered from
## translations/languages.json, the German translation is shown (also its
## fuzzy messages), the IDs of the messages are translated through Texts, the
## grammar fills the placeholders, agrees the words with the numbers and picks
## the forms for the builder's gender, and the IDs of the content never depend
## on the language. (dev/translations/extract.py --check and check.py, in the
## pre-commit checks, make sure that every message is in the .po files and that
## no translation breaks a placeholder.)


func _run() -> void:
    var languages: Node = root.get_node("Languages")
    check_equal(languages.codes(), ["en", "de"] as Array[String], "English and German")
    var content := ContentDb.get_default()
    var before := content.mission_order.duplicate()

    TranslationServer.set_locale("en")
    check_equal(tr("New game"), "New game", "English is the source")
    check_equal(Texts.of("ERROR_OVERLAP"), "Something is already there.", "a message by its ID")

    TranslationServer.set_locale("de")
    check_equal(languages.current(), "de", "German is chosen")
    check_equal(tr("New game"), "Neues Spiel", "the German translation shows, fuzzy or not")
    check_equal(Texts.of("ERROR_OVERLAP"), "Da ist schon etwas.", "and the messages by ID")
    check_equal(tr(content.part("bed_single").name), "Bett", "and the content")
    for id in Texts.MESSAGES:
        check(Texts.of(id).strip_edges() != "", "%s has a text" % id)

    var line := MissionText.line("Seats for {required} people ({current} of {required})", 1, 2)
    check_equal(line, "Sitzplätze für 2 (1 von 2)", "the placeholders are filled")
    check_equal(
        Grammar.format(
            "{count} {count|Sitz|Sitze}, {beds} {beds|Bett|Betten}", {"count": 1, "beds": 2}
        ),
        "1 Sitz, 2 Betten",
        "the words agree with the numbers"
    )
    Grammar.gender = "female"
    check_equal(Grammar.address("{builder|Baumeister|Baumeisterin}"), "Baumeisterin", "female")
    Grammar.gender = "male"
    check_equal(Grammar.address("{builder|Baumeister|Baumeisterin}"), "Baumeister", "male")
    Grammar.gender = ""
    check_equal(content.mission_order, before, "the IDs do not depend on the language")

    TranslationServer.set_locale("en")
    check_equal(Grammar.plural_index(1), 0, "one in English")
    check_equal(Grammar.plural_index(2), 1, "other in English")
    TranslationServer.set_locale("ru")
    check_equal(Grammar.plural_index(3), 1, "a few in Russian")
    check_equal(Grammar.plural_index(5), 2, "many in Russian")
    check_equal(Grammar.plural_index(21), 0, "21 is one in Russian")
    TranslationServer.set_locale("en")
    check_equal(
        Grammar.format("{count} {count|seat|seats}", {"count": 1}), "1 seat", "one seat in English"
    )
