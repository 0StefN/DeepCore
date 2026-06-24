extends Node

func _ready() -> void:
	GameManager.start_game("Ma Corp")
	get_tree().change_scene_to_file.call_deferred("res://scenes/UI/BiddingUI.tscn")
