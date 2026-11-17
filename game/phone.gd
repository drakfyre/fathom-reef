extends Node3D
## Phone version ("Reef Gym"): the reef, both robot gyms (classic + new rules), fast-forward,
## and the neural-network book as a swipeable two-page reader. No VR.
## Touch: one finger orbits, pinch zooms, two fingers pan. Exported with the "phone" feature,
## which makes this the main scene and turns OpenXR off (see project.godot overrides).

const Fish := preload("res://fish.gd")
const Reef := preload("res://reef.gd")
const Sfx := preload("res://sfx.gd")
const Robots := preload("res://phone/robots.gd")
const BookScript := preload("res://phone/book.gd")
const BASE_TICKS := 90
const Timeline := preload("res://phone/timeline.gd")
# the PC trainer build (feature "trainer") gets higher speeds and accepts the headset over the LAN
var trainer := OS.has_feature("trainer") or OS.get_environment("REEF_TRAINER") == "1"
var SPEEDS: Array = [1.0, 2.0, 4.0, 8.0, 16.0] if trainer else [1.0, 2.0, 3.0, 4.0, 6.0]
const SAVES := ["user://robots.json", "user://robots_v2.json"]


const Link := preload("res://link.gd")
var link: Link
var log_label: Label
var log_seen := ""
var fish: Fish
var reef: Reef
var sfx: Sfx
var hands: Array = []
var camera: Camera3D
var yaw := 0.0
var pitch := -0.35
var dist := 14.0
var focus := Vector3(0, 1.2, -7.0)
var focus_goal := Vector3(0, 1.2, -7.0)
var touches := {}
var level := 0
var speed_btns: Array[Button] = []
var readout: Label
var settle := 0.0
var slow_t := 0.0
var ticks := 0
var win_t := 0.0
var actual := 1.0
# book reader
var book_layer: Control
var book_pages: Array[Control] = []
var book_spread := 0
var book_content: Array = []
var swipe_from := Vector2.ZERO
var shots_dir := ""
var start_panel: Control
var confirm: ConfirmationDialog
var tl_bar: VBoxContainer
var tl_species_btn: Button
var tl_gym_btn: Button
var code_label: Label
var test_continue := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a == "--continue":
			test_continue = true
	reef = Reef.new()
	add_child(reef)
	fish = Fish.new()
	add_child(fish)
	sfx = Sfx.new()
	add_child(sfx)
	camera = Camera3D.new()
	camera.far = 80.0
	add_child(camera)
	camera.add_child(reef.make_snow())
	# the same live link as the headset (127.0.0.1:34960 on the phone; reach it with adb forward).
	# Its 3D board is hidden; the lines show in the log panel instead.
	# The gym and timeline scripts ship inside the app. Older copies that the live link saved in
	# user://live (e.g. during a training sync) would be restored over them and can be out of step
	# with the timeline, so they are removed first. Training data (user://robots*.json) is kept.
	for nm in ["robots", "robots_v2", "timeline"]:
		DirAccess.remove_absolute("user://live/%s.gd" % nm)
	link = Link.new()
	link.main = self
	add_child(link)
	link.board.visible = false
	_build_ui()
	await get_tree().process_frame   # the link adds its Live root and restores saved live scripts
	await get_tree().process_frame
	_update_camera(1.0)
	if shots_dir != "":
		_choose(test_continue)
		_run_test()
	elif link.live_root.get_node_or_null("robots") != null or _has_saves():
		_start_gyms()
	else:
		_show_start()


func _has_saves() -> bool:
	for p in SAVES:
		if FileAccess.file_exists(p):
			return true
	return false


func _start_gyms() -> void:
	for nm in ["robots", "robots_v2"]:
		if link.live_root.get_node_or_null(nm) == null:
			var g = Robots.new()
			g.name = nm
			g.main = self
			link.live_root.add_child(g)
	if link.live_root.get_node_or_null("timeline") == null:
		var t = Timeline.new()
		t.name = "timeline"
		t.main = self
		link.live_root.add_child(t)


func _seed_info() -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://phone/seed_robots.json")) \
			if FileAccess.file_exists("res://phone/seed_robots.json") else null
	if not d is Dictionary or not d.has("spider"):
		return ""
	return "spider generation %d, humanoid %d" % [int(d.spider.gen), int(d.humanoid.gen)]


func _show_start() -> void:
	start_panel.visible = true


func _choose(cont: bool) -> void:
	if start_panel:
		start_panel.visible = false
	if cont:
		for p in SAVES:
			var src: String = "res://phone/seed_" + p.get_file()
			if FileAccess.file_exists(src):
				var f := FileAccess.open(p, FileAccess.WRITE)
				f.store_string(FileAccess.get_file_as_string(src))
				f.close()
		link.add_line("Continuing Fathom's training (%s)." % _seed_info())
	else:
		link.add_line("Starting from zero: every brain begins as random numbers.")
	_start_gyms()


func _reset() -> void:
	## Back to the start screen: removes the gyms, the timeline and all training on this device.
	_apply_speed(0)
	for nm in ["robots", "robots_v2", "timeline"]:
		var n := link.live_root.get_node_or_null(nm)
		if n:
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for p in SAVES:
		for ext in ["", ".bak", ".tmp"]:
			DirAccess.remove_absolute(p + ext)
	for nm in ["robots", "robots_v2", "timeline"]:
		DirAccess.remove_absolute("user://live/%s.gd" % nm)
	tl_bar.visible = false
	link.add_line("Training reset.")
	_show_start()


func head_transform() -> Transform3D:
	## The gyms place themselves relative to this (the spot a VR player would stand on).
	return Transform3D(Basis(), Vector3(0, 1.6, 0))


func buzz(_hand: int, _amp := 0.0, _secs := 0.0) -> void:
	pass


func set_sim_speed(k: float) -> void:
	## Same trick as the headset: time AND physics tick rate scale together, so every physics
	## step stays 1/90 s and the robots are exactly as stable as at 1x.
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(round(BASE_TICKS * k))
	Engine.max_physics_steps_per_frame = maxi(4, int(ceil(k)) + 2)
	for n in find_children("*", "CPUParticles3D", true, false):
		(n as CPUParticles3D).speed_scale = 1.0 / k


# ---------------------------------------------------------------- UI

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var top := HBoxContainer.new()
	top.position = Vector2(24, 20)
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	var title := Label.new()
	title.text = "Reef Gym  "
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.9))
	top.add_child(title)
	for i in SPEEDS.size():
		var b := _btn("%d×" % int(SPEEDS[i]), _apply_speed.bind(i))
		b.toggle_mode = true
		top.add_child(b)
		speed_btns.append(b)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 26)
	top.add_child(readout)
	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.position = Vector2(-250, 20)
	side.add_theme_constant_override("separation", 10)
	root.add_child(side)
	side.add_child(_btn("Book", _open_book))
	side.add_child(_btn("Classic", func() -> void: _look_at_gym(0)))
	side.add_child(_btn("Both", func() -> void: _look_at_gym(-1)))
	side.add_child(_btn("New rules", func() -> void: _look_at_gym(1)))
	side.add_child(_btn("Timeline", _look_at_timeline))
	side.add_child(_btn("Restart", func() -> void: confirm.popup_centered()))
	for c in side.get_children():
		(c as Button).custom_minimum_size = Vector2(220, 72)
	var log_bg := PanelContainer.new()
	log_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_bg.position = Vector2(20, -230)
	log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_bg)
	var log_label := Label.new()
	log_label.add_theme_font_size_override("font_size", 22)
	log_label.custom_minimum_size = Vector2(900, 200)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_bg.add_child(log_label)
	self.log_label = log_label
	link.add_line("Drag to orbit, pinch to zoom, two fingers to pan.")
	_build_book(root)
	_build_start(root)
	_build_timeline_bar(root)
	confirm = ConfirmationDialog.new()
	confirm.title = "Restart training?"
	confirm.dialog_text = "This deletes all training on this device and goes back to the start screen."
	confirm.ok_button_text = "Restart"
	confirm.confirmed.connect(_reset)
	root.add_child(confirm)
	if trainer:
		code_label = Label.new()
		code_label.add_theme_font_size_override("font_size", 24)
		code_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		code_label.position = Vector2(24, 104)
		root.add_child(code_label)
		var ips: Array[String] = []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
				ips.append(a)
		code_label.text = "Trainer link: %s port %d   code %s" % [", ".join(ips), link.PORT, link.token] \
				if link.server.is_listening() else "Trainer link closed"
	_apply_speed(0)


func _build_start(root: Control) -> void:
	# full-screen dimmer (blocks the camera and buttons) with the choice centred on it
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.06, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	root.add_child(dim)
	start_panel = dim
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var h := Label.new()
	h.text = "Reef Gym"
	h.add_theme_font_size_override("font_size", 48)
	h.add_theme_color_override("font_color", Color(1.0, 0.75, 0.9))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)
	var t := Label.new()
	t.text = "Robots with tiny neural networks learn to walk by evolution.\nHow do you want to start?"
	t.add_theme_font_size_override("font_size", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var a := _btn("Watch them learn from zero", _choose.bind(false))
	a.custom_minimum_size = Vector2(760, 84)
	box.add_child(a)
	var info := _seed_info()
	if info != "":
		var b := _btn("Continue Fathom's training (%s)" % info, _choose.bind(true))
		b.custom_minimum_size = Vector2(760, 84)
		b.add_theme_font_size_override("font_size", 26)
		box.add_child(b)


func _build_timeline_bar(root: Control) -> void:
	tl_bar = VBoxContainer.new()
	tl_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tl_bar.position = Vector2(-250, 532)
	tl_bar.add_theme_constant_override("separation", 10)
	tl_bar.visible = false
	root.add_child(tl_bar)
	tl_species_btn = _btn("Spider", _toggle_tl_species)
	tl_species_btn.custom_minimum_size = Vector2(220, 64)
	tl_bar.add_child(tl_species_btn)
	tl_gym_btn = _btn("Classic", _toggle_tl_gym)
	tl_gym_btn.custom_minimum_size = Vector2(220, 64)
	tl_bar.add_child(tl_gym_btn)


func _timeline() -> Node:
	return link.live_root.get_node_or_null("timeline")


func _look_at_timeline() -> void:
	var t = _timeline()
	if t == null or t.arena == null:
		return
	focus_goal = t.arena.global_position + Vector3(0, 0.4, 0)
	dist = 9.0
	yaw = 0.0
	pitch = -0.35
	tl_bar.visible = true


func _toggle_tl_species() -> void:
	var t = _timeline()
	if t:
		t.set_view(t.gym_name, "humanoid" if t.species_name == "spider" else "spider")
		tl_species_btn.text = t.species_name.capitalize()


func _toggle_tl_gym() -> void:
	var t = _timeline()
	if t:
		t.set_view("robots_v2" if t.gym_name == "robots" else "robots", t.species_name)
		tl_gym_btn.text = "New rules" if t.gym_name == "robots_v2" else "Classic"


func _apply_speed(i: int) -> void:
	level = i
	set_sim_speed(SPEEDS[i])
	settle = 3.0
	slow_t = 0.0
	for k in speed_btns.size():
		speed_btns[k].set_pressed_no_signal(k == i)


func _look_at_gym(which: int) -> void:
	tl_bar.visible = false
	if which < 0:
		focus_goal = Vector3(0, 1.2, -7.0)
		dist = 14.0
	else:
		var g = link.live_root.get_node_or_null(["robots", "robots_v2"][which])
		if g == null:
			return
		focus_goal = g.arena.global_position + Vector3(0, 0.4, 0)
		dist = 8.0
	yaw = 0.0
	pitch = -0.35


# ---------------------------------------------------------------- book reader

func _build_book(root: Control) -> void:
	var b = BookScript.new()
	book_content = b.CONTENT.duplicate(true)
	b.free()
	book_layer = Control.new()
	book_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	book_layer.visible = false
	root.add_child(book_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.06, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_book_input)
	book_layer.add_child(dim)
	for i in 2:
		var p = BookScript.PageDraw.new()
		p.font = ThemeDB.fallback_font
		p.size = Vector2(640, 832)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		book_layer.add_child(p)
		book_pages.append(p)
	var close := _btn("Close", func() -> void: book_layer.visible = false)
	close.position = Vector2(24, 24)
	book_layer.add_child(close)
	var prev := _btn("<", func() -> void: _turn(-1))
	prev.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	prev.position = Vector2(16, -36)
	book_layer.add_child(prev)
	var next := _btn(">", func() -> void: _turn(1))
	next.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	next.position = Vector2(-126, -36)
	book_layer.add_child(next)


func _open_book() -> void:
	book_layer.visible = true
	_show_spread()


func _turn(d: int) -> void:
	var max_spread := (book_content.size() + 1) / 2
	var s := clampi(book_spread + d, 0, max_spread)
	if s == book_spread:
		return
	book_spread = s
	_show_spread()
	for p in book_pages:
		p.modulate.a = 0.0
		create_tween().tween_property(p, "modulate:a", 1.0, 0.25)


func _page_setup(p, idx: int) -> void:
	## Spread 0 = cover on the left, page 1 on the right; then pages two at a time.
	if idx < 0:
		p.kind = "cover"
		p.page = {}
	elif idx >= book_content.size():
		p.kind = "plain"
		p.page = {}
	else:
		p.kind = "page"
		p.page = book_content[idx]
		p.number = idx + 1
	p.queue_redraw()


func _show_spread() -> void:
	_page_setup(book_pages[0], 2 * book_spread - 1)
	_page_setup(book_pages[1], 2 * book_spread)
	var vs := get_viewport().get_visible_rect().size
	var s := minf((vs.y - 40.0) / 832.0, (vs.x - 300.0) / 1280.0)
	var w := 640.0 * s
	var x0 := (vs.x - 2.0 * w) * 0.5
	for i in 2:
		var p: Control = book_pages[i]
		p.scale = Vector2(s, s)
		p.position = Vector2(x0 + i * w, (vs.y - 832.0 * s) * 0.5)


func _book_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		if e.pressed:
			swipe_from = e.position
		else:
			var dx: float = e.position.x - swipe_from.x
			if absf(dx) > 80.0:
				_turn(-1 if dx > 0.0 else 1)
			elif absf(dx) < 10.0:
				_turn(1 if e.position.x > get_viewport().get_visible_rect().size.x * 0.5 else -1)


# ---------------------------------------------------------------- camera + loop

func _unhandled_input(e: InputEvent) -> void:
	if book_layer.visible:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
		else:
			touches.erase(e.index)
	elif e is InputEventScreenDrag:
		var before := touches.duplicate()
		touches[e.index] = e.position
		if touches.size() == 1:
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -1.4, 0.3)
		elif touches.size() == 2 and before.size() == 2:
			var ks := touches.keys()
			var d0: float = (before[ks[0]] as Vector2).distance_to(before[ks[1]])
			var d1: float = (touches[ks[0]] as Vector2).distance_to(touches[ks[1]])
			if d1 > 1.0:
				dist = clampf(dist * d0 / d1, 1.5, 40.0)
			var basis := camera.global_basis
			var pan: Vector3 = (-basis.x * e.relative.x + basis.y * e.relative.y) * dist * 0.0006
			focus_goal += pan
			focus += pan
	elif not OS.has_feature("mobile"):
		# desktop testing with a mouse
		if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			yaw -= e.relative.x * 0.006
			pitch = clampf(pitch - e.relative.y * 0.004, -1.4, 0.3)
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(dist * 0.9, 1.5)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(dist * 1.1, 40.0)


func _update_camera(k: float) -> void:
	focus = focus.lerp(focus_goal, k)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var p := focus + b * Vector3(0, 0, dist)
	p.y = maxf(p.y, 0.3)
	camera.global_position = p
	camera.look_at(focus)


func _physics_process(_dt: float) -> void:
	ticks += 1


func _process(scaled_dt: float) -> void:
	var dt := scaled_dt / Engine.time_scale
	_update_camera(clampf(dt * 4.0, 0.0, 1.0))
	fish.step(dt, hands, camera.global_position)
	settle = maxf(settle - dt, 0.0)
	win_t += dt
	if win_t >= 1.0:
		actual = ticks / win_t / BASE_TICKS
		ticks = 0
		win_t = 0.0
	# the link keeps only its last 16 lines, so watch the newest line rather than the count
	var newest: String = link.lines[-1] if not link.lines.is_empty() else ""
	if newest != log_seen:
		log_seen = newest
		log_label.text = "\n".join(link.lines.slice(-5))
	var fps := Engine.get_frames_per_second()
	if level > 0 and settle <= 0.0 and fps < (15 if trainer else 40):
		slow_t += dt
		if slow_t > 2.0:
			link.add_line("Phone can't keep up at %d×, stepping down" % int(SPEEDS[level]))
			_apply_speed(level - 1)
	else:
		slow_t = 0.0
	readout.text = "  actual %.1f×  %d FPS" % [actual, fps]


# ---------------------------------------------------------------- desktop screenshot check

func _shot(nm: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(nm + ".png"))
	print("shot ", nm)


func _run_test() -> void:
	for i in 90:
		await get_tree().process_frame
	var g = link.live_root.get_node("robots")
	print("start gens: classic spider %d, new spider %d" % [g.species.spider.gen, link.live_root.get_node("robots_v2").species.spider.gen])
	await _shot("phone_both")
	# fake a few champion snapshots so the timeline has something to show right away
	for sp in ["spider", "humanoid"]:
		var s = g.species[sp]
		s.timeline.clear()
		for k in 5:
			s.timeline.append({"gen": 1 + k * 10, "fit": 0.1 * k, "g": Array(s.genomes[k % s.genomes.size()])})
	_look_at_timeline()
	var t = _timeline()
	t.set_view("robots", "spider")
	for i in 120:
		await get_tree().process_frame
	print("timeline robots: ", t.robots.size(), " board: ", t.board.text.get_slice("\n", 0))
	await _shot("timeline_spider")
	_toggle_tl_species()
	for i in 120:
		await get_tree().process_frame
	print("timeline robots: ", t.robots.size(), " (", t.species_name, ")")
	await _shot("timeline_humanoid")
	_open_book()
	_turn(1)
	await get_tree().create_timer(0.5 * Engine.time_scale).timeout
	await _shot("phone_book")
	book_layer.visible = false
	await _reset()
	await get_tree().process_frame
	print("after reset: saves left %s, gyms %s, start screen %s" % [_has_saves(), link.live_root.get_node_or_null("robots") != null, start_panel.visible])
	await get_tree().create_timer(0.3 * Engine.time_scale).timeout
	await _shot("start_screen")
	get_tree().quit()
