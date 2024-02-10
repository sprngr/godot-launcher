extends Node

var version : String
var languages : Dictionary


func _ready():
	var version_output = []
	OS.execute("bash", ["-c", "git rev-parse --short HEAD"], true, version_output, true)
	version = version_output[0]
	print("System version: " + version)

	var languages_file = File.new()
	if languages_file.open(ProjectSettings.globalize_path("res://system/languages.json"), File.READ) == OK:
		languages = parse_json(languages_file.get_as_text())


func get_version() -> String:
	return version


func get_languages() -> Dictionary:
	return languages


func get_launcher() -> Launcher:
	return get_tree().current_scene as Launcher


func emit_event(name, arguments = []):
	return get_tree().current_scene.emit_event(name, arguments)
