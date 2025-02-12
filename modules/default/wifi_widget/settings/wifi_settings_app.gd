extends App

enum Operation { SCAN, CONNECT }
enum Encryption { OFF, ON }

class NetworkDetails extends Reference:
	var id : int
	var name : String
	var encryption  = Encryption.OFF
	var quality : int
	var password : String

var processing = false
var thread : Thread = null
var semaphore : Semaphore = null
var ssid_regex : RegEx
var encryption_regex : RegEx
var quality_regex: RegEx

var last_focused_hotspot : Control = null
var should_exit = false
var operation = null
var connecting_network : NetworkDetails = null
var connecting_hotspot : NetworkDetails = null

onready var hotspots_container = $ConstraintContainer/ScrollContainer/HotspotsContainer
onready var wifi_service = System.get_launcher().get_tagged_service("wifi")


func _ready():
	ssid_regex = RegEx.new()
	ssid_regex.compile("Essid:\\s+(.+)\\n")

	encryption_regex = RegEx.new()
	encryption_regex.compile("Encryption Method:\\s+(\\w*)\\n")

	quality_regex = RegEx.new()
	quality_regex.compile("Quality:\\s+(\\d*)\\n")

	semaphore = Semaphore.new()
	thread = Thread.new()
	thread.start(self, "_thread_function", null)
	pass


# Called when the App gains focus, setup the App here.
# Signals like window_mode_request and title_change_request are best called here.
func _focus():
	emit_signal("window_mode_request", false)
	emit_signal("title_change_request", tr("DEFAULT.WIFI_SETTINGS"))
	emit_signal("display_mode_request", Launcher.Mode.OPAQUE)
	System.emit_event("prompts", [
		[Desktop.Input.MOVE_V, tr("DEFAULT.PROMPT_NAVIGATION")],
		[Desktop.Input.A, tr("DEFAULT.PROMPT_SELECT"), Desktop.Input.Y, tr("DEFAULT.PROMPT_SCAN"), Desktop.Input.B, tr("DEFAULT.PROMPT_BACK")]
	])
	if last_focused_hotspot != null:
		last_focused_hotspot.grab_focus()


# Called when the App loses focus
func _unfocus():
	
	pass


# Called when the App is focuses and receives an input.
# Override this function instead of _input to receive global events.
func _app_input(event : InputEvent):
	if event.is_action_pressed("ui_cancel") and not processing:
		accept_event()
		System.get_launcher().app.back_app()
	if event.is_action_pressed("ui_button_y") and not processing:
		accept_event()
		_scan_hotspots()


func _hotspot_pressed(hotspot_details):
	if hotspot_details.encryption == Encryption.OFF:
		hotspot_details.password = ""
		_hotspot_connect_attempt(true, hotspot_details)
	else:
		var keyboard = Modules.get_component_from_settings("system/keyboard_app").resource.instance()
		keyboard.title = tr("DEFAULT.WIFI_PASSWORD")
		keyboard.connect("text_entered", self, "_password_entered", [hotspot_details])
		System.get_launcher().app.add_app(keyboard)


func _password_entered(confirmed, password : String, hotspot_details):
	if not confirmed:
		return
	hotspot_details.password = password
	_hotspot_connect_attempt(true, hotspot_details)


func _hotspot_connect_attempt(confirmed, hotspot_details):
	if not confirmed:
		return
	if wifi_service.connect_hotspot(hotspot_details) == OK:
		processing = true
		System.emit_event("set_loading", [true])
		wifi_service.connect("connection_attempted", self, "_connection_attempted", [], CONNECT_ONESHOT)
	operation = Operation.CONNECT
	connecting_hotspot = hotspot_details

	semaphore.post()


func _hotspot_focused(hotspot : Control):
	last_focused_hotspot = hotspot


func _scan_hotspots():
	if wifi_service.scan_hotspots() == OK:
		processing = true
		System.emit_event("set_loading", [true])
		wifi_service.connect("scan_completed", self, "_scan_completed", [], CONNECT_ONESHOT)
	operation = Operation.SCAN
	semaphore.post()


func _scan_completed(hotspots : Array):
	processing = false
	System.emit_event("set_loading", [false])
	
	for c in hotspots_container.get_children():
		hotspots_container.remove_child(c)
		c.queue_free()
	for n in hotspots:
		var button : Button = preload("hotspot_button.tscn").instance()
		hotspots_container.add_child(button)
		button.hotspot_name.text = n.name
		button.quality.text = str(n.quality) + "%"
		button.protection_icon.visible = n.encryption == Encryption.ON
	
	# Configure the entries
	var i = 0
	for c in hotspots_container.get_children():
		c.connect("pressed", self, "_hotspot_pressed", [hotspots[i]])
		c.connect("focus_entered", self, "_hotspot_focused", [c])
		c.focus_neighbour_left = c.get_path()
		c.focus_neighbour_right = c.get_path()
		if i > 0:
			c.focus_neighbour_top = hotspots_container.get_child(i - 1).get_path()
		else:
			c.focus_neighbour_top = c.get_path()
		if i < hotspots_container.get_child_count() - 1:
			c.focus_neighbour_bottom = hotspots_container.get_child(i + 1).get_path()
		else:
			c.focus_neighbour_bottom = c.get_path()
		i += 1
	
	if hotspots_container.get_child_count() > 0:
		hotspots_container.get_child(0).grab_focus()


func _connection_attempted(hotspot, result):
	processing = false
	System.emit_event("set_loading", [false])
	print("Connection attempted with result: " + str(result))
	
	if result == OK:
		System.emit_event("notification", [tr("DEFAULT.WIFI_CONNECTION_SUCCESS").format([hotspot.name]), "success"])
	else:
		System.emit_event("notification", [tr("DEFAULT.WIFI_CONNECTION_FAILED").format([hotspot.name]), "error"])
	connecting_network = null


func _thread_function(data):
	var output = []

	while not should_exit:
		semaphore.wait()
		if should_exit:
			return

		if operation == Operation.SCAN:
			# Scan wireless hotspots and list them
			OS.execute("bash", ["-c", "wicd-cli -ySl"], true, output, true)
			print("List network result: "+ str(output))

			var networks_amount = output[0].split("\n").size() - 2 if output.size() > 0 else 0
			print("Found " + str(networks_amount) + " networks")

			var networks_details = []
			for i in range(networks_amount):
				OS.execute("bash", ["-c", "wicd-cli --wireless -n " + str(i) + " -d"], true, output, true)
				print("Network "+str(i) + " details result: " + str(output))
				var name = ""
				var encryption_method = "Off"
				var quality = 0

				var output_string = output[0] if output.size() > 0 else ""
				print(output_string)

				var res : RegExMatch = ssid_regex.search(output_string)
				if res != null:
					name = res.get_string(1)
				res = encryption_regex.search(output_string)
				if res != null:
					encryption_method = res.get_string(1)
				res = quality_regex.search(output_string)
				if res != null:
					quality = int(res.get_string(1))

				var entry : NetworkDetails = NetworkDetails.new()
				entry.id = i
				entry.name = name
				entry.encryption = Encryption.ON if encryption_method != "Off" else Encryption.OFF
				entry.quality = quality
				entry.password = ""
				print("Adding entry: " + str(entry))
				networks_details.append(entry)

			print("Final result: " + str(networks_details))
			call_deferred("_scan_completed", networks_details)
		elif operation == Operation.CONNECT:
			var result = -1
			if connecting_network != null:
				if not connecting_network.password.empty():
					OS.execute("bash", ["-c", "wicd-cli -y -n " + str(connecting_network.id) + " -p apsk -s " +  connecting_network.password], true, output, true)
					print("Set password property: " + str(output))
				if connecting_network.id >= 0:
					result = OS.execute("bash", ["-c", "wicd-cli -y -n " + str(connecting_network.id) + " -c"], true, output, true)
					print("Connection attempt: " + str(output))

			call_deferred("_connection_attempted", connecting_hotspot, result)


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		should_exit = true
		semaphore.post()
		thread.wait_to_finish()


# Override this function to declare launcher-wide components dependencies
static func _get_dependencies():
	return [
		Component.depend(Component.Type.SERVICE, "wifi")
	]
