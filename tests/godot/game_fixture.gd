extends RefCounted
## Point the Game and Settings autoloads at a temporary directory, so that the
## screen tests never touch the player's saves and settings.

var directory := ""


func _init(tree: SceneTree, name: String) -> void:
    directory = "user://tests/%s_%d" % [name, Time.get_ticks_usec()]
    DirAccess.make_dir_recursive_absolute(directory)
    var settings: Node = tree.root.get_node("Settings")
    settings.path = directory.path_join("settings.cfg")
    settings.load_settings()
    var game: Node = tree.root.get_node("Game")
    game.session = GameSession.new(game.content, SaveRepository.new(directory.path_join("saves")))
