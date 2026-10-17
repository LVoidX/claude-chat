extends Node3D
## Small co-op: F3 opens a panel to HOST a game (UDP port 7777) or JOIN a friend by address. Everyone walks the same
## meadow and sees each other (a simple figure with a name above it). Friends can TALK to the characters too: Enter beside
## one opens a line to type; it goes to the host, whose chat window (Claude, on the host's plan) has the character answer,
## and the answer's speech bubbles come back to the friends (observe/recv_cmd). Otherwise only positions are shared: quests, fights, items
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
var sky_in := 0.0  # the host sends its time of day and weather every few seconds, so everyone shares one sky
var my_name := "Wanderer"
var typed := ""  # what a joined friend is typing to the character beside them
var say_box: Label
var say_to := ""


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
		mp.connected_to_server.connect(func(): W.show_notice("Connected! Press Enter beside a character to talk to them.", 6.0))
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
	var skin := Color("#e8b896").darkened(rng.randf_range(0.0, 0.3))
	var limbs := []  # [left leg, right leg, left arm, right arm] pivots: they swing as the friend walks
	for side in [-1, 1]:  # legs hang from the hips
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.1, 0.82, 0)
		node.add_child(leg)
		W.box(leg, Vector3(0, -0.37, 0), Vector3(0.13, 0.74, 0.14), Color("#4a3d30"))  # hose
		W.box(leg, Vector3(0, -0.78, -0.03), Vector3(0.15, 0.1, 0.22), Color("#2b2119"))  # shoes
		limbs.append(leg)
	W.box(node, Vector3(0, 1.14, 0), Vector3(0.42, 0.62, 0.26), tunic)  # tunic
	W.box(node, Vector3(0, 0.86, 0), Vector3(0.44, 0.08, 0.28), Color("#3b2a1e"))  # belt
	W.box(node, Vector3(0, 0.86, -0.151), Vector3(0.07, 0.05, 0.018), Color("#c9a24a"))  # buckle
	W.box(node, Vector3(0, 1.43, 0), Vector3(0.44, 0.05, 0.28), tunic.darkened(0.25))  # collar
	for side in [-1, 1]:  # arms hang from the shoulders
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.27, 1.4, 0)
		node.add_child(arm)
		W.box(arm, Vector3(0, -0.26, 0), Vector3(0.12, 0.52, 0.13), tunic.darkened(0.08))  # sleeve
		W.box(arm, Vector3(0, -0.56, 0), Vector3(0.1, 0.1, 0.1), skin)  # hand
		limbs.append(arm)
	W.box(node, Vector3(0, 1.66, 0), Vector3(0.26, 0.28, 0.26), skin)  # head
	for side in [-1, 1]:
		W.box(node, Vector3(side * 0.06, 1.69, -0.131), Vector3(0.04, 0.035, 0.01), Color("#1d1814"))  # eyes
	W.box(node, Vector3(0, 1.83, 0.01), Vector3(0.3, 0.09, 0.3), tunic.darkened(0.35))  # cap
	W.box(node, Vector3(0, 1.79, -0.16), Vector3(0.3, 0.03, 0.07), tunic.darkened(0.35))  # its brim
	var blade = W.prop("sword_iron", limbs[3], Vector3(0, -0.56, -0.04))  # their sword, in the right hand, pointing forward
	if blade == null:
		blade = W.box(limbs[3], Vector3(0, -0.56, -0.45), Vector3(0.05, 0.02, 0.8), Color("#b9c0c6"))
	else:
		blade.rotation.x = -PI / 2.0
	blade.visible = false
	var label := Label3D.new()
	label.text = "Friend"
	label.pixel_size = 0.005
	label.position = Vector3(0, 2.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 8
	label.no_depth_test = true
	node.add_child(label)
	peers[id] = {"node": node, "target": W.player.global_position, "yaw": 0.0, "label": label, "limbs": limbs, "phase": 0.0,
		"blade": blade, "swing": 0.0}


## Everyone tells everyone where they are (unreliable: a lost packet is simply replaced by the next).
@rpc("any_peer", "unreliable")
func recv_pos(pos: Vector3, yaw: float, who: String, held := false, swinging := 0.0) -> void:
	var id := get_tree().get_multiplayer().get_remote_sender_id()
	if not peers.has(id):
		add_peer(id)
	var p: Dictionary = peers[id]
	p.target = pos
	p.yaw = yaw
	if Time.get_ticks_msec() > int(p.get("chat_until", 0)):
		p.label.text = who
	p.blade.visible = held
	p.swing = maxf(float(p.get("swing", 0.0)), swinging)


func _process(delta: float) -> void:
	if not online():
		return
	sky_in -= delta
	if sky_in <= 0.0 and get_tree().get_multiplayer().is_server():
		sky_in = 3.0
		var weather = ctx.parts.get("weather")
		rpc("recv_sky", float(ctx.state.get("time", 12.0)), weather != null and float(weather.want) > 0.5)
	send_in -= delta
	if send_in <= 0.0:
		send_in = 1.0 / SEND_HZ
		var hotbar = ctx.parts.get("hotbar")
		var held: bool = hotbar != null and hotbar.held()
		rpc("recv_pos", W.player.global_position, W.player.rotation.y, my_name, held, float(hotbar.swing) if hotbar else 0.0)
	for id in peers:
		var p: Dictionary = peers[id]
		var node: Node3D = p.node
		var before := node.global_position
		node.global_position = node.global_position.lerp(p.target, minf(delta * 12.0, 1.0))
		var speed := Vector2(node.global_position.x - before.x, node.global_position.z - before.z).length() / maxf(delta, 0.001)
		p.phase += delta * clampf(speed, 0.0, 7.0) * 2.2  # a stride per ~2.8 m
		var swing := sin(p.phase) * 0.6 * clampf(speed / 2.0, 0.0, 1.0)
		var limbs: Array = p.limbs
		limbs[0].rotation.x = swing
		limbs[1].rotation.x = -swing
		limbs[2].rotation.x = -swing * 0.7  # arms swing against the legs
		limbs[3].rotation.x = swing * 0.7
		if p.blade.visible:  # sword out: the arm is raised forward, and a swing chops it down
			p.swing = maxf(float(p.swing) - delta * 3.0, 0.0)
			var chop: float = sin(clampf(1.0 - p.swing, 0.0, 1.0) * PI) if p.swing > 0.0 else 0.0
			limbs[3].rotation.x = 0.9 + chop * 1.4 - (1.0 - chop) * 0.0
		node.rotation.y = lerp_angle(node.rotation.y, p.yaw, minf(delta * 10.0, 1.0))
	if status and open:
		status.text = status_text()


## What the characters can see: friends standing near them (so Barnaby knows who else is at the fire).
func seen_from(from: Vector3, _viewer: Node) -> Array:
	var out := []
	for id in peers:
		var p: Dictionary = peers[id]
		var node: Node3D = p.node
		if node.global_position.distance_to(from) < 25.0:
			out.append("%s, a friend travelling with the wanderer, is %s" % [p.label.text, W.where(from, node.global_position)])
	return out


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
	var name_box := LineEdit.new()  # what the others see over your head (and what the characters hear you called)
	name_box.placeholder_text = "Your name"
	name_box.text = my_name
	name_box.max_length = 20
	name_box.text_changed.connect(func(v: String):
		my_name = v.strip_edges() if v.strip_edges() != "" else "Wanderer"
		ctx.state["net_name"] = my_name)
	box.add_child(name_box)
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


## Typing to a character (a friend who joined; the host just talks as usual). While the box is open every key comes here.
func open_say() -> void:
	say_to = str(W.near_who)
	typed = ""
	if say_box == null:
		say_box = Label.new()
		say_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		say_box.position = Vector2(-300, -170)
		say_box.custom_minimum_size = Vector2(600, 0)
		say_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		say_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		say_box.add_theme_font_size_override("font_size", 18)
		say_box.add_theme_color_override("font_outline_color", Color.BLACK)
		say_box.add_theme_constant_override("outline_size", 6)
		layer.add_child(say_box)
	say_box.visible = true
	ctx["typing"] = self
	show_typed()


func show_typed() -> void:
	say_box.text = ("Say to them:  " if say_to != "" else "Say to your friends:  ") + typed + "_      (Enter sends, Esc cancels)"


func close_say() -> void:
	if ctx.get("typing") == self:
		ctx.erase("typing")
	if say_box:
		say_box.visible = false


@rpc("any_peer", "reliable")
func friend_say(who: String, text: String, from_name: String) -> void:
	if not get_tree().get_multiplayer().is_server():
		return
	W.show_notice("%s: \"%s\"" % [from_name, text], 5.0)
	W.send({"t": "friend_say", "who": who, "text": text, "name": from_name})  # the chat window has the character answer


## On the host: characters' speech from the chat window goes on to the friends, so they see it too.
func observe(c: Dictionary) -> void:
	if online() and get_tree().get_multiplayer().is_server() and str(c.get("cmd", "")) in ["say_start", "say_end", "say", "npc_state"]:
		rpc("recv_cmd", c)


@rpc("authority", "unreliable")
func recv_sky(hour: float, raining: bool) -> void:
	var now := float(ctx.state.get("time", hour))
	var gap := fposmod(hour - now + 12.0, 24.0) - 12.0  # (the short way round midnight)
	if absf(gap) > 0.05:
		ctx.state["time"] = hour  # (base.gd moves the sun from state["time"])
	var weather = ctx.parts.get("weather")
	if weather and (float(weather.want) > 0.5) != raining:
		weather.set_rain(raining)
		ctx.state["rain_until"] = INF if raining else -1.0  # the host decides when it stops, not this copy's own clock
		ctx.state["dry_until"] = INF if not raining else -1.0


@rpc("any_peer", "reliable")
func recv_chat(from_name: String, text: String) -> void:
	W.show_notice("%s: %s" % [from_name, text], 6.0)
	var id := get_tree().get_multiplayer().get_remote_sender_id()
	if peers.has(id):  # and over their head for a few seconds
		var p: Dictionary = peers[id]
		p.label.text = "%s: \"%s\"" % [from_name, text.substr(0, 60)]
		p.chat_until = Time.get_ticks_msec() + 6000  # (recv_pos puts the plain name back after this)


@rpc("authority", "reliable")
func recv_cmd(c: Dictionary) -> void:
	W.handle(c)  # the friend's own copy of that character shows the bubble


func key(event: InputEventKey) -> void:
	if ctx.get("typing") == self:
		match event.keycode:
			KEY_ESCAPE:
				close_say()
			KEY_ENTER, KEY_KP_ENTER:
				if typed.strip_edges() != "" and say_to != "":
					rpc_id(1, "friend_say", say_to, typed.strip_edges(), my_name)
				elif typed.strip_edges() != "":  # player chat: everyone sees it, over your head and as a notice
					rpc("recv_chat", my_name, typed.strip_edges())
					W.show_notice("You: " + typed.strip_edges(), 5.0)
				close_say()
			KEY_BACKSPACE:
				typed = typed.substr(0, maxi(typed.length() - 1, 0))
				show_typed()
			_:
				if event.unicode >= 32 and typed.length() < 200:
					typed += char(event.unicode)
					show_typed()
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and online() and not open:
		open_say()
		if get_tree().get_multiplayer().is_server():
			say_to = ""  # (the host talks to characters by voice; Enter is for the friends)
			show_typed()
		return
	if event.keycode == KEY_F3 or (event.keycode == KEY_ESCAPE and open):
		toggle() if event.keycode == KEY_F3 else close()
