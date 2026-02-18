extends CanvasLayer

const ERROR_LABEL: PackedScene = preload("res://scenes/ui/error_overlay/error_label.tscn")

@onready var kick_dialog: AcceptDialog = $KickDialog
@onready var error_container: VBoxContainer = $ErrorContainer

func popup_kick_dialog(reason: String) -> void:
	kick_dialog.popup()
	kick_dialog.dialog_text = "Reason: " + reason

func spawn_error(error: String) -> void:
	var error_instance: Label = ERROR_LABEL.instantiate() as Label
	error_container.add_child(error_instance)
	error_instance.text = error
