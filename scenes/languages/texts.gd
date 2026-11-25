# gdlint: disable=max-line-length
class_name Texts
extends RefCounted
## Show the messages which the game passes around by an ID: the reasons of the
## placement (ERROR_*), the hints of the objectives (HINT_*), the messages of
## the saves (SAVE_*), the ranks, the reputations, the input states and the
## like. The IDs never change with the language; [method of] translates the
## English text of the ID (see dev/translations/extract.py, which collects the
## texts of this table).

const MESSAGES := {
    "ERROR_NO_LANDING": "Nothing to land on below the hook: move it over the ground or a floor.",
    "PAUSE_BODY_RESUME_HINT": "To go on, hold your posture, then do a push-up, or press P.",
    "CREDITS_TEXT":
    "Baugenossen is made by Dinamika Games and its contributors, under the MIT License.\n\nMade with Godot Engine. The body tracking uses RTMO and RTMPose by OpenMMLab (Apache License 2.0) through ONNX Runtime (MIT); the camera runs only on this computer and nothing is recorded or sent.\n\nThe pictures are placeholder drawings made in code. See THIRD_PARTY_NOTICES.md for all the licenses.",
    "AUTO_CALIBRATING":
    "Go into your push-up position (or on your knees, hands on the floor) and hold still for a moment: the crane learns your posture.",
    "AUTO_RECALIBRATING":
    "Your elbows moved away: hold still in your push-up position, and the crane learns your posture anew.",
    "AUTO_CALIBRATING_NOT_SEEN":
    "Move into the camera picture, so that it sees your shoulders and elbows.",
    "CITY_CONTINUE": "Continue building",
    "CITY_REPLAY": "Play again",
    "CITY_START": "Start",
    "CREATE_LOOK_CLOTHING": "Clothes",
    "CREATE_LOOK_HAIR": "Hair",
    "CREATE_LOOK_SKIN": "Skin",
    "ERROR_CANNOT_MIRROR": "{part} can not be mirrored.",
    "ERROR_CROSSES_PART": "It would cut through another part.",
    "ERROR_NOTHING_THERE": "There is nothing to pick here.",
    "ERROR_NOT_OFFERED": "This project does not use {part}.",
    "ERROR_OUT_OF_BOUNDS": "{part} does not fit on the site here.",
    "ERROR_OVERHANG": "overhangs more than 2 cells; finish it with a wall or a beam below.",
    "ERROR_OVERLAP": "Something is already there.",
    "ERROR_OVERWEIGHT": "{part} weighs {mass}; your crane lifts {capacity}.",
    "ERROR_PROTECTED": "This part belongs to the site and stays.",
    "ERROR_TOP_LANDING": "the stairs need a floor at their top landing.",
    "ERROR_UNKNOWN_PART": "Unknown part.",
    "ERROR_UNSUPPORTED": "{part} needs support: put it on the ground, a floor, a wall or a beam.",
    "HINT_DISTINCT_ROOMS": "each needs a room of its own",
    "HINT_NOT_INDOORS": "it must be inside a closed room",
    "HINT_NO_ROOM": "no closed room yet: close every wall and the roof",
    "HINT_ROOM_MISSING_THINGS": "a room still lacks something",
    "HINT_ROOM_NO_ENTRANCE": "the room has no way in",
    "HINT_ROOM_TOO_SMALL": "the room is too small",
    "HINT_TOO_HIGH": "the construction is too high",
    "HINT_UNREACHABLE": "nobody can reach it: add a door, stairs or a way",
    "HINT_ZONES_NOT_CONNECTED": "the places are not connected",
    "HINT_ZONE_MUST_STAY_FREE": "this place must stay free",
    "HINT_ZONE_UNREACHABLE": "nobody can get there yet",
    "NEEDS_BODY_TITLE": "The crane listens to your body",
    "NEEDS_CAMERA":
    "The hook moves only when you move, and the camera does not work. Connect a camera and allow it.",
    "PAUSE_RECENTRE": "Learn my posture again",
    "PAUSE_RESUME": "Resume",
    "PAUSE_SAVE_AND_LEAVE": "Save and go to the projects",
    "PAUSE_SAVE_AND_QUIT": "Save and quit",
    "PAUSE_TRACKING_LOST": "The camera lost sight of you, so everything stopped. Take your time.",
    "REVIEW_BACK": "Back to building",
    "REVIEW_COMPLETE": "Hand over to the residents",
    "REVIEW_RESUBMIT": "Hand over again",
    "SAVE_ERROR_CORRUPT":
    "The save is damaged and no backup could be read. It is kept as it is; a new game sets it aside.",
    "SAVE_ERROR_LOCKED": "The save on disk can not be overwritten (see the message when loading).",
    "SAVE_ERROR_UNKNOWN_VERSION":
    "The save comes from a newer version of the game; it is left untouched.",
    "SAVE_ERROR_VERIFY":
    "Saving failed: the written file could not be read back. Your progress is still here; try again.",
    "SAVE_ERROR_WRITE": "Saving failed. Your progress is still here; try again.",
    "SAVE_RECOVERED_FROM_BACKUP": "The last save was damaged, so the one before it was loaded.",
    "STATE_BUILD": "building",
    "STATE_CALIBRATION": "calibrating",
    "STATE_CATALOGUE": "catalogue",
    "STATE_COMPLETE": "complete",
    "STATE_GESTURE_PENDING": "gesture…",
    "STATE_PAUSED": "paused",
    "STATE_REVIEW": "review",
    "STATUS_AVAILABLE": "open",
    "STATUS_COMPLETED": "completed",
    "STATUS_IN_PROGRESS": "in progress",
    "STATUS_LOCKED": "not yet open",
    "TRACKING_FROZEN": "hold on…",
    "TRACKING_LOST": "tracking lost",
    "TRACKING_OK": "tracking",
}


## The translated text of the ID, or the ID itself if it is unknown.
static func of(id: String) -> String:
    if not MESSAGES.has(id):
        push_warning("Unknown message ID %s" % id)
        return id
    return TranslationServer.translate(MESSAGES[id])
