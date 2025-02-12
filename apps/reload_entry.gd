extends LauncherEntry

var thread : Thread
var debug = false


func get_label():
	match TranslationServer.get_locale():
		"it":
			return "Ricarica"
	return "Reload"


func exec():
	thread = Thread.new()
	System.emit_event("set_loading", [true])
	var result = thread.start(self, "_import_thread")
	return result


func _execution_terminated(result):
	thread.wait_to_finish()
	if result == OK:
		Engine.get_main_loop().quit()
	else:
		System.emit_event("notification", [tr("DEFAULT.RELOADING_FAILED"), "error"])
	System.emit_event("set_loading", [false])
	executed(result)


func _import_thread(data):
	var result = OS.execute("bash", ["-c", "~/godot-launcher/godot" + ("-debug" if debug else "") +" ~/godot-launcher/project.godot -q -v > /tmp/godot-importer.log 2>&1"], true)
	call_deferred("_execution_terminated", result)
