class_name Grammar
extends RefCounted

## Fill the placeholders of a translated sentence with the right grammatical
## forms (see DESIGN.md, 8, and CONTRIBUTING.md, "Translations").
##
## * A placeholder: [code]{name}[/code] is replaced by the value of the
##   argument "name"; a string value is translated (a name of a part, of a
##   resident...), a list of them is joined with commas, a number is shown.
## * A word which agrees with a number: [code]{count|seat|seats}[/code] picks
##   the form for the number of [code]{count}[/code] by the plural rule of the
##   language (English and German: one, other; Russian and Croatian: one, few,
##   many; French counts zero as one).
## * A word which depends on the builder's gender:
##   [code]{builder|Baumeister|Baumeisterin}[/code] picks the first form for a
##   constructor and the second for a constructrice. The choice is made when
##   the message is translated (see [AddressedTranslation]), so it works in
##   every text, not only in those with placeholders.

## The gender of the builder, or empty for the first form.
static var gender := ""

static var _builder_choice := RegEx.create_from_string("\\{builder\\|([^{}]*)\\}")

static var _placeholder := RegEx.create_from_string("\\{([a-z_]+)(\\|[^{}]*)?\\}")


## The text with its placeholders filled (see the class description).
static func format(text: String, args: Dictionary) -> String:
    text = address(text)
    var result := ""
    var at := 0
    for found in _placeholder.search_all(text):
        result += text.substr(at, found.get_start() - at)
        at = found.get_end()
        var key := found.get_string(1)
        if not args.has(key):
            result += found.get_string()
            continue
        result += _fill(args[key], found.get_string(2))
    return result + text.substr(at)


static func _fill(value: Variant, how: String) -> String:
    if how.begins_with("|"):
        var forms := how.substr(1).split("|")
        return forms[mini(plural_index(int(value)), forms.size() - 1)]
    if value is Array:
        var names: Array[String] = []
        for each in value:
            names.append(_fill(each, how))
        return ", ".join(names)
    if not value is String:
        return str(value)
    return String(TranslationServer.translate(value))


## Replace every [code]{builder|...}[/code] choice with the form for the
## builder's gender.
static func address(text: String) -> String:
    if not "{builder|" in text:
        return text
    var result := ""
    var at := 0
    for found in _builder_choice.search_all(text):
        result += text.substr(at, found.get_start() - at)
        at = found.get_end()
        var forms := found.get_string(1).split("|")
        var index := 1 if builder_gender() == "female" else 0
        result += forms[mini(index, forms.size() - 1)]
    return result + text.substr(at)


## The gender of the builder: the one set (e.g., in a test), else "male" (the
## first form). The game has no character, so its texts use the first form.
static func builder_gender() -> String:
    return gender if gender != "" else "male"


## Which form of a word goes with the number in the current language: 0 for
## one, 1 for a few (Russian and Croatian: 2 to 4) or for the other numbers,
## 2 for many.
static func plural_index(count: int) -> int:
    var language := TranslationServer.get_locale().left(2)
    if language == "fr":
        return 0 if absi(count) <= 1 else 1
    if language in ["ru", "hr", "sr", "bs", "uk", "pl", "cs"]:
        var last := absi(count) % 10
        var last_two := absi(count) % 100
        if last == 1 and last_two != 11:
            return 0
        if last >= 2 and last <= 4 and (last_two < 12 or last_two > 14):
            return 1
        return 2
    return 0 if count == 1 else 1
