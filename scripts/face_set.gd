class_name FaceSet
extends Resource

## The face textures of one character. Every pose has an open and a blinking version.
## "Down" is looking at their cards and "forward" is looking up (the head does the turning).
enum Pose { DOWN, FORWARD }

@export var down_open: Texture2D = preload("res://Assets/textures/faces/face_down_open.png")
@export var down_blink: Texture2D = preload("res://Assets/textures/faces/face_down_blink.png")
@export var forward_open: Texture2D = preload("res://Assets/textures/faces/face_forward_open.png")
@export var forward_blink: Texture2D = preload("res://Assets/textures/faces/face_forward_blink.png")

func get_texture(pose: Pose, blinking: bool) -> Texture2D:
	if pose == Pose.FORWARD:
		return forward_blink if blinking else forward_open
	return down_blink if blinking else down_open
