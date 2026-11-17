extends Node3D
## Live link: a tiny local server (127.0.0.1:34960, this device only) that lets Claude, running
## in Termux on the same headset, build into the running app while you are inside it.
## One JSON object per line in each direction:
##   {"cmd":"log","text":"..."}               add a line to the build-log board
##   {"cmd":"run","name":"x","code":"..."}    compile a GDScript (extends Node/Node3D) and add it
##                                            as live node "x" (replacing an old "x"); it is saved
##                                            and comes back on the next launch
##   {"cmd":"rm","name":"x"} / {"cmd":"list"}
##   {"cmd":"eval","expr":"..."}              evaluate an expression on the main node
##   {"cmd":"pose"}                           head position / forward direction
##   {"cmd":"shot"}                           base64 PNG of what the headset shows
## A live script may declare `var main` to be handed the main node (fish, reef, sfx, hands...).

const PORT := 34960
const LIVE_DIR := "user://live"
const LINES := 16

var main: Node
var server := TCPServer.new()
var peers: Array[StreamPeerTCP] = []
var bufs: Array[PackedByteArray] = []
var live_root: Node3D
var lines: Array[String] = []
var board: Node3D
var text: Label3D
var dot: MeshInstance3D
var dot_mat: StandardMaterial3D
var last_msg := -100.0
var clock := 0.0
var shot_waiters: Array[StreamPeerTCP] = []


func _ready() -> void:
	live_root = Node3D.new()
	live_root.name = "Live"
	main.add_child.call_deferred(live_root)
	_make_board()
	var err := server.listen(PORT, "127.0.0.1")
	add_line("link %s on 127.0.0.1:%d" % ["listening" if err == OK else "FAILED (%d)" % err, PORT])
	_restore.call_deferred()


func _make_board() -> void:
	board = Node3D.new()
	add_child(board)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.72)
	bg.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.02, 0.05, 0.1, 0.78)
	m.disable_fog = true
	bg.material_override = m
	board.add_child(bg)
	var title := Label3D.new()
	title.text = "Claude's build log"
	title.font_size = 44
	title.pixel_size = 0.001
	title.outline_size = 0
	title.modulate = Color(1.0, 0.7, 0.85)
	title.position = Vector3(-0.46, 0.31, 0.002)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.fixed_size = false
	title.no_depth_test = false
	board.add_child(title)
	dot = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.012
	s.height = 0.024
	dot.mesh = s
	dot_mat = StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(0.3, 0.3, 0.35)
	dot.material_override = dot_mat
	dot.position = Vector3(0.45, 0.31, 0.01)
	board.add_child(dot)
	text = Label3D.new()
	text.font_size = 26
	text.pixel_size = 0.001
	text.outline_size = 0
	text.width = 900
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.position = Vector3(-0.46, 0.26, 0.002)
	text.modulate = Color(0.85, 0.95, 1.0)
	for l: Label3D in [title, text]:
		l.shaded = false
		l.double_sided = false
	board.add_child(text)


func place_board(head: Transform3D) -> void:
	## Puts the board ahead and to the left of the player, facing them.
	var f := -head.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var right := f.cross(Vector3.UP)
	var p := head.origin + f * 1.3 - right * 0.9
	p.y = head.origin.y - 0.1
	board.global_position = p
	var look := head.origin
	look.y = p.y
	board.look_at(p + (p - look), Vector3.UP)


func add_line(s: String) -> void:
	var t := Time.get_time_dict_from_system()
	lines.append("[%02d:%02d] %s" % [t.hour, t.minute, s])
	while lines.size() > LINES:
		lines.remove_at(0)
	if text:
		text.text = "\n".join(lines)
	print("link: ", s)


func _process(dt: float) -> void:
	clock += dt
	while server.is_listening() and server.is_connection_available():
		peers.append(server.take_connection())
		bufs.append(PackedByteArray())
	for i in range(peers.size() - 1, -1, -1):
		var p := peers[i]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peers.remove_at(i)
			bufs.remove_at(i)
			continue
		var n := p.get_available_bytes()
		if n > 0:
			var got := p.get_partial_data(n)
			if got[0] == OK:
				bufs[i].append_array(got[1])
		while true:
			var nl := bufs[i].find(10)
			if nl < 0:
				break
			var line := bufs[i].slice(0, nl).get_string_from_utf8()
			bufs[i] = bufs[i].slice(nl + 1)
			last_msg = clock
			var reply: Dictionary = _handle(line)
			if reply.has("_shot"):
				shot_waiters.append(p)
				if shot_waiters.size() == 1:
					RenderingServer.frame_post_draw.connect(_take_shot, CONNECT_ONE_SHOT)
			else:
				_send(p, reply)
	var active := clock - last_msg < 2.0
	dot_mat.albedo_color = Color(0.4, 1.0, 0.6) * (0.7 + 0.3 * sin(clock * 8.0)) if active \
			else Color(0.3, 0.3, 0.35)


func _handle(line: String) -> Dictionary:
	var msg: Variant = JSON.parse_string(line)
	if not msg is Dictionary:
		return {"ok": false, "error": "bad json"}
	var cmd: String = msg.get("cmd", "")
	match cmd:
		"log":
			add_line(str(msg.get("text", "")))
			return {"ok": true}
		"run":
			return _run(str(msg.get("name", "live")), str(msg.get("code", "")), true)
		"rm":
			var nm := str(msg.get("name", ""))
			var old := live_root.get_node_or_null(nm)
			if old:
				old.queue_free()
			DirAccess.remove_absolute(LIVE_DIR.path_join(nm + ".gd"))
			add_line("removed " + nm)
			return {"ok": old != null}
		"list":
			var names: Array[String] = []
			for c in live_root.get_children():
				names.append(String(c.name))
			return {"ok": true, "live": names, "fps": Engine.get_frames_per_second()}
		"eval":
			var e := Expression.new()
			if e.parse(str(msg.get("expr", ""))) != OK:
				return {"ok": false, "error": e.get_error_text()}
			var r: Variant = e.execute([], main)
			if e.has_execute_failed():
				return {"ok": false, "error": e.get_error_text()}
			return {"ok": true, "result": var_to_str(r)}
		"pose":
			var h: Transform3D = main.head_transform()
			return {"ok": true, "head": var_to_str(h.origin), "forward": var_to_str(-h.basis.z)}
		"shot":
			return {"_shot": true}
	return {"ok": false, "error": "unknown cmd " + cmd}


func _send(p: StreamPeerTCP, reply: Dictionary) -> void:
	if p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		p.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var reply := {"ok": false, "error": "no image"}
	if img != null:
		if img.get_width() > 960:
			img.resize(960, int(960.0 * img.get_height() / img.get_width()))
		reply = {"ok": true, "png": Marshalls.raw_to_base64(img.save_png_to_buffer())}
	for p in shot_waiters:
		_send(p, reply)
	shot_waiters.clear()


func _run(nm: String, code: String, save: bool) -> Dictionary:
	if not nm.is_valid_filename() or nm.is_empty():
		return {"ok": false, "error": "bad name"}
	var sc := GDScript.new()
	sc.source_code = code
	var err := sc.reload()
	if err != OK:
		add_line("! %s did not compile (error %d)" % [nm, err])
		return {"ok": false, "error": "compile error %d (check-only it in Termux first)" % err}
	var obj: Variant = sc.new()
	if not obj is Node:
		return {"ok": false, "error": "script must extend Node or Node3D"}
	var node: Node = obj
	var old := live_root.get_node_or_null(nm)
	if old:
		live_root.remove_child(old)
		old.queue_free()
	node.name = nm
	if "main" in node:
		node.set("main", main)
	live_root.add_child(node)
	if save:
		DirAccess.make_dir_recursive_absolute(LIVE_DIR)
		var f := FileAccess.open(LIVE_DIR.path_join(nm + ".gd"), FileAccess.WRITE)
		if f:
			f.store_string(code)
	return {"ok": true}


func _restore() -> void:
	## Live nodes built in an earlier session come back on launch.
	var d := DirAccess.open(LIVE_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var r := _run(f.get_basename(), FileAccess.get_file_as_string(LIVE_DIR.path_join(f)), false)
			add_line("restored %s%s" % [f.get_basename(), "" if r.ok else " (failed)"])
