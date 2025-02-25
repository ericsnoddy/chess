class_name Debug extends Control

var properties : Array
@onready var container : VBoxContainer = $PanelContainer/VBoxContainer
# update time
const FPS_MS = 16

func _ready() -> void:
	Global.debug = self
	visible = false
	
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug"):
		visible = !visible
		get_viewport().set_input_as_handled()
		
func add_debug_property(id: StringName, value, time_in_frames) -> void:
	if properties.has(id):
		if Time.get_ticks_msec() / FPS_MS % time_in_frames == 0:
			var target := container.find_child(id, true, false) as Label
			target.text = id + ": " + str(value)
	else:
		var property := Label.new()
		container.add_child(property)
		property.name = id
		property.text = id + ": " + str(value)
		properties.append(property)
