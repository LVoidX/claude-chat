extends Node3D
## Small co-op: F3 opens a panel to HOST a game (UDP port 7777) or JOIN a friend by address. Everyone walks the same
## meadow and sees each other (a simple figure with a name above it). Only positions are shared: quests, fights, items
## and the story stay each player's own. Command line for testing: -- --host   or   -- --join=127.0.0.1
## Needs the same project version on both PCs. The host must be reachable: forward UDP 7777 on the router, or both
## install Tailscale / ZeroTier and use the host's address from there.

const PORT := 7777
const SEND_HZ := 15.0

var ctx: Dictionary
var W
var layer: CanvasLayer
var panel: PanelContainer
var status: Label
var address: LineEdit
var open := false
var peers := {}  # peer id -> {node, target, yaw, name}
var send_in := 0.0
var my_name := "Wanderer"


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	layer = CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	my_name = str(ctx.state.get("net_name", "Wanderer"))
	var mp := get_tree().get_multiplayer()
	if not mp.peer_connected.is_connected(on_peer_connected):
		mp.peer_connected.connect(on_peer_connected)
		mp.peer_disconnected.connect(on_peer_gone)
		mp.connected_to_server.connect(func(): W.show_notice("Connected. You can see each other now.", 4.0))
		mp.connection_failed.connect(func(): W.show_notice("Could not connect to that address.", 4.0))
		mp.server_disconnected.connect(func():
			W.show_notice("The host left the game.", 4.0)
			clear_peers())
	for a in OS.get_cmdline_user_args():
		if a == "--host":
			host()
		elif a.begins_with("--join="):
			join(a.substr(7))


func online() -> bool:
	var mp := get_tree().get_multiplayer()
	return mp.has_multiplayer_peer() and mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 4)
	if err != OK:
		W.show_notice("Could not host on port %d (already in use?)." % PORT, 4.0)
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	W.show_notice("Hosting on UDP port %d. Friends join with your address." % PORT, 5.0)


func join(addr: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr.strip_edges(), PORT)
	if err != OK:
		W.show_notice("That address does not work.", 4.0)
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	W.show_notice("Connecting to %s ..." % addr, 3.0)


func leave() -> void:
	var mp := get_tree().get_multiplayer()
	if mp.has_multiplayer_peer():
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null
	clear_peers()


func clear_peers() -> void:
	for id in peers:
		peers[id].node.queue_free()
	peers.clear()


func _exit_tree() -> void:
	leave()


func on_peer_connected(id: int) -> void:
	W.show_notice("A friend joined the game.", 3.0)
	add_peer(id)


func on_peer_gone(id: int) -> void:
	if peers.has(id):
		peers[id].node.queue_free()
		peers.erase(id)
		W.show_notice("A friend left.", 3.0)


func add_peer(id: int) -> void:
	if peers.has(id):
		return
	var node := Node3D.new()
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var tunic := Color.from_hsv(rng.randf(), 0.45, 0.55)
	W.box(node, Vector3(0, 1.2, 0), Vector3(0.5, 0.62, 0.28), tunic)  # torso
	W.box(node, Vector3(0, 1.62, 0), Vector3(0.26, 0.28, 0.26), Color("#e0b894"))  # head
	W.box(node, Vector3(0, 1.8, 0), Vector3(0.3, 0.1, 0.3), tunic.darkened(0.3))  # cap
	for side in [-1, 1]:
		W.box(node, Vector3(side * 0.12, 0.45, 0), Vector3(0.18, 0.9, 0.2), Color("#4a3a2a"))  # legs
		W.box(node, Vector3(side * 0.32, 1.2, 0), Vector3(0.14, 0.58, 0.16), tunic.lightened(0.05))  # arms
	var label := Label3D.new()
	label.text = "Friend"
	label.pixel_size = 0.005
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 8
	label.no_depth_test = true
	node.add_child(label)
	peers[id] = {"node": node, "target": W.player.global_position, "yaw": 0.0, "label": label}


## Everyone tells everyone where they are (unreliable: a lost packet is simply replaced by the next).
@rpc("any_peer", "unreliable")
func recv_pos(pos: Vector3, yaw: float, who: String) -> void:
	var id := get_tree().get_multiplayer().get_remote_sender_id()
	if not peers.has(id):
		add_peer(id)
	var p: Dictionary = peers[id]
	p.target = pos
	p.yaw = yaw
	p.label.text = who


func _process(delta: float) -> void:
	if not online():
		return
	send_in -= delta
	if send_in <= 0.0:
		send_in = 1.0 / SEND_HZ
		rpc("recv_pos", W.player.global_position, W.player.rotation.y, my_name)
	for id in peers:
		var p: Dictionary = peers[id]
		var node: Node3D = p.node
		node.global_position = node.global_position.lerp(p.target, minf(delta * 12.0, 1.0))
		node.rotation.y = lerp_angle(node.rotation.y, p.yaw, minf(delta * 10.0, 1.0))
	if status and open:
		status.text = status_text()


func status_text() -> String:
	var mp := get_tree().get_multiplayer()
	if not mp.has_multiplayer_peer():
		return "Not in a game."
	if mp.is_server():
		return "Hosting on UDP port %d. Friends here: %d" % [PORT, peers.size()]
	return "Joined a game. Friends here: %d" % peers.size()


func toggle() -> void:
	if open:
		close()
		return
	var rpg = ctx.parts.get("rpg")
	if rpg == null:
		return
	open = true
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	panel.position = Vector2(-220, -140)
	panel.add_theme_stylebox_override("panel", rpg.style(Color(0.1, 0.07, 0.04, 0.96), Color("#c9a24a"), 2, 8))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(rpg.label("PLAY WITH A FRIEND", 20, Color("#ffd24d")))
	status = rpg.label(status_text(), 14, Color("#d8c8aa"))
	box.add_child(status)
	box.add_child(rpg.button("Host a game (port %d)" % PORT, host))
	address = LineEdit.new()
	address.placeholder_text = "Friend's address, e.g. 100.64.1.2"
	address.text = str(ctx.state.get("net_last", ""))
	box.add_child(address)
	box.add_child(rpg.button("Join that address", func():
		ctx.state["net_last"] = address.text
		join(address.text)))
	box.add_child(rpg.button("Leave the game", leave))
	box.add_child(rpg.button("Close (F3 or Esc)", close))
	ctx["ui_open"] = true  # (so a click does not grab the mouse back, world.gd)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	open = false
	if panel:
		panel.queue_free()
		panel = null
	W.save_state.call_deferred()
	ctx["ui_open"] = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_F3 or (event.keycode == KEY_ESCAPE and open):
		toggle() if event.keycode == KEY_F3 else close()
