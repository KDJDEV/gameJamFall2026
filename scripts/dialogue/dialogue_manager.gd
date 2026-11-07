class_name DialogueManager
extends Node

## Plays the dialogue sequences defined in data/dialogue.json. Sequences start when
## the game begins or when the draw pile reaches a card count, and play one at a time.
## Lines can also trigger table actions through events (see register_event).
signal sequence_started(sequence_id: String)
signal sequence_finished(sequence_id: String)
signal line_started(speaker_id: String, text: String)
signal event_finished(event_name: String)
## Emitted when a sequence marked "disable_play" starts (true) and when the last one ends (false).
signal play_lock_changed(locked: bool)

@export_file("*.json") var dialogue_file: String = "res://data/dialogue.json"
## The deck whose remaining cards drive the cards_left / cards_drawn triggers.
@export var draw_pile: CardPile
## When true, cards_drawn counts from the moment set_draw_baseline() is called
## (the dealer calls it once the hands are dealt) instead of from the first frame.
@export var draw_baseline_from_dealer: bool = true
@export var show_speaker_names: bool = true
@export_range(0.0, 0.3) var seconds_per_character: float = 0.055
@export_range(0.5, 10.0) var min_line_seconds: float = 2.0
@export_range(0.0, 3.0) var default_pause: float = 0.6

var _sequences: Array[Dictionary] = []
var _queued_or_played: Dictionary = {}
var _queue: Array[Dictionary] = []
var _running: bool = false
var _starting_cards: int = 0
var _baseline_ready: bool = false
var _box: DialogueBox
var _speakers: Dictionary = {}
var _fallback_voice: AudioStreamPlayer
var _event_handlers: Dictionary = {}
var _events_running: int = 0
var _play_locks: int = 0
var _round: int = 1

func _ready() -> void:
	_box = DialogueBox.new()
	add_child(_box)
	_fallback_voice = AudioStreamPlayer.new()
	add_child(_fallback_voice)
	_load_sequences()
	# Piles and speakers finish setting up on the first frame.
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("dialogue_speaker"):
		var speaker := node as DialogueSpeaker
		if speaker != null:
			_speakers[speaker.speaker_id] = speaker
	if draw_pile != null:
		_starting_cards = draw_pile.cards.size()
		_baseline_ready = not draw_baseline_from_dealer
		draw_pile.count_changed.connect(_on_pile_count_changed)
		_on_pile_count_changed(_starting_cards)
	for sequence in _sequences:
		var trigger: Dictionary = sequence.get("trigger", {})
		if trigger.get("type", "") == "start":
			_start_after_intro(sequence["id"], float(trigger.get("delay", 0.0)))

# Start triggers wait for the opening (the screen fading in) to finish before their own delay.
func _start_after_intro(sequence_id: String, delay: float) -> void:
	var intro := get_tree().get_first_node_in_group("intro_sequence") as IntroSequence
	if intro != null and not intro.is_finished:
		await intro.finished
	await get_tree().create_timer(delay).timeout
	play_sequence(sequence_id)

## Lets a dialogue line run game code: a line with "event": name calls this handler
## (a callable that may await). With "wait": true the line holds until it finishes.
func register_event(event_name: String, handler: Callable) -> void:
	_event_handlers[event_name] = handler

func set_draw_baseline() -> void:
	if draw_pile == null:
		return
	_starting_cards = draw_pile.cards.size()
	_baseline_ready = true
	_on_pile_count_changed(_starting_cards)

## Tells the manager which round the game is in; triggers with a "round" field only fire in it.
## Triggers are only checked when the deck count changes, so a deck that is already empty when
## a round begins does not fire a cards_left trigger by itself.
func set_round(round_number: int) -> void:
	_round = round_number

func play_sequence(sequence_id: String) -> void:
	var sequence := _find_sequence(sequence_id)
	if sequence.is_empty():
		push_warning("Dialogue sequence '%s' does not exist." % sequence_id)
		return
	_enqueue(sequence)

func _find_sequence(sequence_id: String) -> Dictionary:
	for sequence in _sequences:
		if sequence["id"] == sequence_id:
			return sequence
	return {}

func _load_sequences() -> void:
	var file := FileAccess.open(dialogue_file, FileAccess.READ)
	if file == null:
		push_error("Cannot open dialogue file %s" % dialogue_file)
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("Dialogue file %s is not valid JSON." % dialogue_file)
		return
	for sequence in data.get("sequences", []):
		if sequence is Dictionary and sequence.has("id") and sequence.has("lines"):
			_sequences.append(sequence)
		else:
			push_warning("Skipping a dialogue sequence without an id or lines.")

func _on_pile_count_changed(count: int) -> void:
	for sequence in _sequences:
		var trigger: Dictionary = sequence.get("trigger", {})
		var wanted_round := int(trigger.get("round", 0))
		if wanted_round != 0 and wanted_round != _round:
			continue
		var type: String = trigger.get("type", "")
		var value := int(trigger.get("value", 0))
		if type == "cards_left" and count <= value:
			_enqueue(sequence)
		elif type == "cards_drawn" and _baseline_ready and _starting_cards - count >= value:
			_enqueue(sequence)

func _enqueue(sequence: Dictionary) -> void:
	if _queued_or_played.has(sequence["id"]):
		return
	_queued_or_played[sequence["id"]] = true

	if sequence.get("interrupt", false):
		_queue.insert(_waiting_interrupts(), sequence)
	else:
		_queue.append(sequence)
	if not _running:
		_run_queue()

func _waiting_interrupts() -> int:
	var count := 0
	for queued in _queue:
		if queued.get("interrupt", false):
			count += 1
	return count

func _run_queue() -> void:
	_running = true
	while not _queue.is_empty():
		var sequence: Dictionary = _queue.pop_front()
		if not sequence.get("resumed", false):
			sequence_started.emit(sequence["id"])
		var remaining: Array = await _play_lines(sequence)
		await _wait_for_events()
		if remaining.is_empty():
			sequence_finished.emit(sequence["id"])
		else:
			var rest := sequence.duplicate()
			rest["lines"] = remaining
			rest["resumed"] = true
			_queue.insert(_waiting_interrupts(), rest)
	_running = false

func _play_lines(sequence: Dictionary, top_level: bool = true) -> Array:
	var locks_play: bool = sequence.get("disable_play", false)
	if locks_play:
		_play_locks += 1
		if _play_locks == 1:
			play_lock_changed.emit(true)
	var lines: Array = sequence["lines"]
	var remaining: Array = []
	for index in lines.size():
		var line: Dictionary = lines[index]
		if line.has("play_sequence"):
			var nested := _find_sequence(line["play_sequence"])
			if nested.is_empty():
				push_warning("Dialogue sequence '%s' does not exist." % line["play_sequence"])
			else:
				await _play_lines(nested, false)
		else:
			await _play_line(line)
		if top_level and not sequence.get("interrupt", false) and _waiting_interrupts() > 0 and index < lines.size() - 1:
			remaining = lines.slice(index + 1)
			break
	if locks_play:
		await _wait_for_events()
		_play_locks -= 1
		if _play_locks == 0:
			play_lock_changed.emit(false)
	return remaining

func _play_line(line: Dictionary) -> void:
	if line.get("text", "") == "":
		if line.has("event"):
			_run_event(line["event"])
		if line.get("wait", false):
			await _wait_for_events()
		return
	var speaker_id := StringName(line.get("speaker", ""))
	var text: String = line.get("text", "")
	var speaker: DialogueSpeaker = _speakers.get(speaker_id)
	var stream := _load_audio(line.get("audio", ""))
	var duration := float(line.get("duration", _estimate_duration(text, stream)))
	await get_tree().create_timer(float(line.get("delay", 0.0))).timeout
	if speaker != null:
		speaker.set_speaking(true)
		if stream != null:
			speaker.play_voice(stream)
	elif stream != null:
		_fallback_voice.stream = stream
		_fallback_voice.play()
	var shown := text
	if show_speaker_names and speaker != null and speaker.display_name != "":
		shown = "%s: %s" % [speaker.display_name, text]
	_box.show_line(shown)
	line_started.emit(String(speaker_id), text)
	if line.has("event"):
		_run_event(line["event"])
	await get_tree().create_timer(duration).timeout
	if line.get("wait", false):
		await _wait_for_events()
	_box.hide_line()
	if speaker != null:
		speaker.set_speaking(false)
	await get_tree().create_timer(float(line.get("pause", default_pause))).timeout

func _run_event(event_name: String) -> void:
	var handler: Callable = _event_handlers.get(event_name, Callable())
	if not handler.is_valid():
		push_warning("No handler registered for dialogue event '%s'." % event_name)
		return
	_events_running += 1
	await handler.call()
	_events_running -= 1
	event_finished.emit(event_name)

func _wait_for_events() -> void:
	while _events_running > 0:
		await event_finished

func _estimate_duration(text: String, stream: AudioStream) -> float:
	if stream != null:
		return stream.get_length() + 0.2
	return maxf(min_line_seconds, text.length() * seconds_per_character)

func _load_audio(path: String) -> AudioStream:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		push_warning("Dialogue audio not found: %s" % path)
		return null
	return load(path) as AudioStream
