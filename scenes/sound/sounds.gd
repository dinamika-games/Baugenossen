extends Node
## Play the sound effects and the music (the autoload Sounds).
##
## The effects are cut from CC0 recordings on Freesound into
## [code]assets/sounds/<name>.ogg[/code] (see dev/sounds/sources.json); the
## music is rendered from public-domain and CC0 MIDI files of work songs and
## journeymen's songs into [code]assets/music/<slug>.ogg[/code] (see
## dev/music/sources.json). A missing file is skipped silently, so the game
## runs without them.
##
## Play an effect with [code]Sounds.play("place_wood")[/code], keep a loop going
## with [code]Sounds.loop("crane", true)[/code]. The music plays the songs one
## after another in a shuffled order, quietly under the effects; nothing in it
## is a timer or an alarm. The settings switch the effects and the music off;
## M mutes everything, and so does [code]-- --mute[/code] at the start.

const SOUNDS_DIR := "res://assets/sounds"
const MUSIC_DIR := "res://assets/music"

## How many effects play at the same time at most.
const VOICES := 8
const EFFECTS_DB := -4.0
const MUSIC_DB := -14.0
## The pause between two songs, in seconds.
const MUSIC_GAP := 2.0

var muted := false

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _loops: Dictionary = {}
var _streams: Dictionary = {}
var _music: AudioStreamPlayer
var _playlist: Array[String] = []
var _gap := -1.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # NOTE (mristin):
    # Headless (the tests, the servers), nobody hears anything, and streams
    # still playing when a test quits would show as leaks.
    muted = "--mute" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless"
    for i in range(VOICES):
        var player := AudioStreamPlayer.new()
        player.volume_db = EFFECTS_DB
        add_child(player)
        _players.append(player)
    _music = AudioStreamPlayer.new()
    _music.volume_db = MUSIC_DB
    _music.finished.connect(func() -> void: _gap = MUSIC_GAP)
    add_child(_music)
    var settings := get_node_or_null("/root/Settings")
    if settings != null:
        settings.changed.connect(_apply_settings)
    _apply_settings()


func _exit_tree() -> void:
    for player in _players:
        player.stop()
        player.stream = null
    for name in _loops:
        _loops[name].stop()
        _loops[name].stream = null
    _music.stop()
    _music.stream = null
    _streams.clear()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_M:
            muted = not muted
            _apply_settings()


func _process(delta: float) -> void:
    if _gap >= 0.0:
        _gap -= delta
        if _gap < 0.0:
            _play_next_song()


func _setting(key: String) -> bool:
    var settings := get_node_or_null("/root/Settings")
    return settings == null or bool(settings.get_value(key))


func effects_on() -> bool:
    return not muted and _setting("sound")


func music_on() -> bool:
    return not muted and _setting("music")


func _apply_settings() -> void:
    if not effects_on():
        for player in _players:
            player.stop()
        for name in _loops:
            _loops[name].stop()
    if music_on():
        if not _music.playing and _gap < 0.0:
            _play_next_song()
    else:
        _music.stop()
        _gap = -1.0


func _stream(path: String) -> AudioStream:
    if not _streams.has(path):
        _streams[path] = load(path) if ResourceLoader.exists(path) else null
    return _streams[path]


## Play the effect once; [param pitch] varies it a little (e.g., 0.95 to 1.05).
func play(name: String, pitch := 1.0) -> void:
    if not effects_on():
        return
    var stream := _stream("%s/%s.ogg" % [SOUNDS_DIR, name])
    if stream == null:
        return
    var player := _players[_next_player]
    _next_player = (_next_player + 1) % _players.size()
    player.stream = stream
    player.pitch_scale = pitch
    player.play()


## Start or stop a looping effect (e.g., the crane's motor while it moves).
func loop(name: String, on: bool, volume_db := EFFECTS_DB - 6.0) -> void:
    if not _loops.has(name):
        var stream := _stream("%s/%s.ogg" % [SOUNDS_DIR, name])
        if stream == null:
            return
        if stream is AudioStreamOggVorbis:
            stream.loop = true
        var player := AudioStreamPlayer.new()
        player.stream = stream
        player.volume_db = volume_db
        add_child(player)
        _loops[name] = player
    var looping: AudioStreamPlayer = _loops[name]
    if on and effects_on() and not looping.playing:
        looping.play()
    elif not on and looping.playing:
        looping.stop()


## The songs found in assets/music/.
func songs() -> Array[String]:
    var found: Array[String] = []
    for file in ResourceLoader.list_directory(MUSIC_DIR):
        if file.ends_with(".ogg"):
            found.append(MUSIC_DIR.path_join(file))
    found.sort()
    return found


func _play_next_song() -> void:
    _gap = -1.0
    if not music_on():
        return
    if _playlist.is_empty():
        _playlist = songs()
        _playlist.shuffle()
    if _playlist.is_empty():
        return
    var stream := _stream(_playlist.pop_front())
    if stream is AudioStreamOggVorbis:
        stream.loop = false
    _music.stream = stream
    _music.play()
