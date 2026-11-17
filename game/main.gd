extends Node3D
## Fathom Reef: a cozy, fully immersive underwater reef full of cute fish (no passthrough).
## Controls: left stick swim, right stick turn (snap) / up-down, trigger sprinkle fish food,
## grip blow bubbles, A/X call the fish, B show/hide help, Y bring Claude's build-log board.
##
## Desktop test (no headset): godot-gpu --xr-mode off --path . -- --shots=<dir> [--icon]

const Fish := preload("res://fish.gd")
const Reef := preload("res://reef.gd")
const Sfx := preload("res://sfx.gd")
const Link := preload("res://link.gd")
const HANDS := ["left_hand", "right_hand"]
const TIP := Vector3(0, 0, -0.05)


class Hand:
	var ok := false
	var aim := Transform3D()      # aim pose (finger along -Z)
	var grip_xf := Transform3D()  # grip pose
	var tip := Vector3.ZERO
	var vel := Vector3.ZERO
	var grip := 0.0
	var trigger := 0.0
	var stick := Vector2.ZERO
	var ax := false
	var by := false
	var menu := false
	var prev_tip := Vector3.ZERO
	var prev_ax := false
	var prev_by := false
	var prev_menu := false
	var food_t := 0.0
	var bubble_t := 0.0
	var bubbles: CPUParticles3D


var xr: XRInterface
var origin: XROrigin3D
var camera: XRCamera3D
var fish: Fish
var reef: Reef
var sfx: Sfx
var link: Link
var hands: Array[Hand] = [Hand.new(), Hand.new()]
var pointers: Array[Node3D] = []
var title: Node3D
var help_t := 18.0
var turn_ready := true
var placed := false
var age := 0.0
var shots_dir := ""
var make_icon := false
var desktop_spin := true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a == "--icon":
			make_icon = true
	_start_xr()
	reef = Reef.new()
	add_child(reef)
	fish = Fish.new()
	add_child(fish)
	sfx = Sfx.new()
	add_child(sfx)
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	camera.near = 0.03
	camera.far = 60.0
	camera.position = Vector3(0, 1.6, 0)
	origin.add_child(camera)
	var snow := reef.make_snow()
	camera.add_child(snow)
	for i in 2:
		pointers.append(_make_hand())
		var b := reef.make_bubbles(60, 5.0)
		b.emitting = false
		b.initial_velocity_min = 0.3
		b.initial_velocity_max = 0.7
		b.direction = Vector3(0, 0.3, -1)
		b.spread = 25.0
		pointers[i].add_child(b)
		b.position = TIP
		hands[i].bubbles = b
	_make_title()
	link = Link.new()
	link.main = self
	add_child(link)
	link.place_board(head_transform())
	fish.ate.connect(func(p: Vector3) -> void: sfx.play("nom", p, -4.0))
	fish.nibbled.connect(_on_nibble)
	if xr == null:
		if shots_dir != "":
			desktop_spin = false
			_run_test()


func _start_xr() -> void:
	xr = XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var oxr := xr as OpenXRInterface
		if oxr != null:
			oxr.session_begun.connect(func() -> void:
				var rates: Array = oxr.get_available_display_refresh_rates()
				if rates.has(90.0):
					oxr.display_refresh_rate = 90.0)
	else:
		xr = null
		print("OpenXR not available: running in desktop mode")


func head_transform() -> Transform3D:
	return origin.global_transform * camera.transform


func _make_hand() -> Node3D:
	## A pink dragon paw with a pointing finger and a little claw, in aim-pose space.
	var n := Node3D.new()
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(1.0, 0.55, 0.75)
	pink.emission_enabled = true
	pink.emission = Color(0.25, 0.08, 0.15)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 0.97, 0.92)
	var finger := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.009
	cap.height = 0.085
	finger.mesh = cap
	finger.rotation.x = PI / 2
	finger.position = Vector3(0, 0, -0.012)
	finger.material_override = pink
	n.add_child(finger)
	var claw := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.006
	cone.height = 0.014
	claw.mesh = cone
	claw.rotation.x = -PI / 2
	claw.position = Vector3(0, 0.002, -0.054)
	claw.material_override = white
	n.add_child(claw)
	var palm := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.045
	sph.height = 0.07
	palm.mesh = sph
	palm.scale = Vector3(0.9, 0.55, 1.1)
	palm.position = Vector3(0, -0.018, 0.06)
	palm.material_override = pink
	n.add_child(palm)
	n.visible = false
	add_child(n)
	return n


func _make_title() -> void:
	title = Node3D.new()
	add_child(title)
	var big := Label3D.new()
	big.text = "Fathom Reef"
	big.font_size = 160
	big.pixel_size = 0.0015
	big.outline_size = 24
	big.modulate = Color(1.0, 0.85, 0.95)
	big.outline_modulate = Color(0.1, 0.2, 0.35)
	title.add_child(big)
	var small := Label3D.new()
	small.text = "left stick: swim   right stick: turn / up-down\ntrigger: fish food   grip: bubbles   A/X: call the fish\nhold a finger still and the curious ones come for a nibble\nB: hide this help   Y: Claude's build log"
	small.font_size = 48
	small.pixel_size = 0.0015
	small.outline_size = 10
	small.modulate = Color(0.85, 0.97, 1.0)
	small.outline_modulate = Color(0.05, 0.12, 0.2)
	small.position = Vector3(0, -0.25, 0)
	title.add_child(small)
	for l: Label3D in [big, small]:
		l.shaded = false
	_place_title()


func _place_title() -> void:
	var h := head_transform()
	var f := -h.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var p := h.origin + f * 2.2
	p.y = h.origin.y + 0.35
	title.global_position = p
	title.look_at(p + f, Vector3.UP)


# ---------------------------------------------------------------- input

static func _f(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


func _read_xr() -> void:
	for i in 2:
		var h := hands[i]
		h.ok = false
		var tr := XRServer.get_tracker(HANDS[i]) as XRPositionalTracker
		if tr == null:
			continue
		var have := false
		for pn in ["grip", "grip_pose", "default"]:
			var pose := tr.get_pose(pn)
			if pose != null and pose.has_tracking_data:
				h.grip_xf = origin.global_transform * pose.get_adjusted_transform()
				have = true
				break
		if not have:
			continue
		h.ok = true
		var ap := tr.get_pose("aim_pose")
		if ap == null:
			ap = tr.get_pose("aim")
		if ap != null and ap.has_tracking_data:
			h.aim = origin.global_transform * ap.get_adjusted_transform()
		else:
			h.aim = h.grip_xf * Transform3D(Basis(), Vector3(0, -0.03, -0.05))
		h.aim.basis = h.aim.basis.orthonormalized()
		h.tip = h.aim * TIP
		var ct := tr as XRControllerTracker
		if ct == null:
			continue
		h.grip = _f(ct.get_input("grip"))
		h.trigger = _f(ct.get_input("trigger"))
		var st: Variant = ct.get_input("primary")
		h.stick = st if st is Vector2 else Vector2.ZERO
		h.ax = _f(ct.get_input("ax_button")) > 0.5
		h.by = _f(ct.get_input("by_button")) > 0.5
		h.menu = _f(ct.get_input("menu_button")) > 0.5


func buzz(hand: int, amp := 0.4, secs := 0.05) -> void:
	if xr != null:
		xr.trigger_haptic_pulse("haptic", HANDS[hand], 0.0, amp, secs, 0.0)


func _on_nibble(hand: int, p: Vector3) -> void:
	sfx.play("boop", p, -2.0)
	buzz(hand, 0.35, 0.06)


func _process(dt: float) -> void:
	age += dt
	if xr != null:
		_read_xr()
		if not placed and age > 0.6 and camera.position.y > 0.25:
			placed = true
			_place_title()
			link.place_board(head_transform())
	elif desktop_spin and shots_dir == "":
		camera.rotation.y += dt * 0.08
	var L := hands[0]
	var R := hands[1]
	# swimming: left stick moves along the gaze (flattened), right stick snap-turns and rises/sinks
	var head := head_transform()
	var f := -head.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := f.cross(Vector3.UP)
	var mv := (f * L.stick.y + r * L.stick.x) * 1.3
	if absf(R.stick.y) > 0.4:
		mv.y = R.stick.y * 0.9
	var o := origin.position + mv * dt
	var hr := Vector2(o.x, o.z)
	if hr.length() > 11.0:
		hr = hr.normalized() * 11.0
	origin.position = Vector3(hr.x, clampf(o.y, 0.0, 5.0), hr.y)
	if absf(R.stick.x) > 0.7 and turn_ready:
		turn_ready = false
		var pivot := head_transform().origin
		var ang := -deg_to_rad(30.0) * signf(R.stick.x)
		var t := Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
		origin.global_transform = Transform3D(Basis(), pivot) * t * Transform3D(Basis(), -pivot) * origin.global_transform
	elif absf(R.stick.x) < 0.3:
		turn_ready = true
	# hands: food, bubbles, calling, menus
	var fish_hands: Array = []
	for i in 2:
		var h := hands[i]
		h.vel = (h.tip - h.prev_tip) / maxf(dt, 1e-3) if h.ok else Vector3.ZERO
		h.prev_tip = h.tip
		pointers[i].visible = h.ok
		if h.ok:
			pointers[i].global_transform = h.aim
		fish_hands.append({"ok": h.ok, "tip": h.tip, "vel": h.vel})
		h.food_t -= dt
		if h.ok and h.trigger > 0.6 and h.food_t <= 0.0:
			h.food_t = 0.18
			fish.drop_pellet(h.tip, -h.aim.basis.z * 0.25 + Vector3(randf_range(-0.05, 0.05), 0.05, randf_range(-0.05, 0.05)))
			sfx.play("plop", h.tip, -8.0)
		var blowing := h.ok and h.grip > 0.6
		h.bubbles.emitting = blowing
		h.bubble_t -= dt
		if blowing and h.bubble_t <= 0.0:
			h.bubble_t = randf_range(0.08, 0.2)
			sfx.play("bubble", h.tip, -10.0)
		if h.ax and not h.prev_ax:
			fish.call_fish(head.origin + f * 0.7 - Vector3(0, 0.2, 0))
			sfx.play("chime", h.tip, -4.0)
			buzz(i, 0.2, 0.1)
		if h.by and not h.prev_by:
			if i == 1:
				help_t = 0.0 if help_t > 0.0 else 30.0
				if help_t > 0.0:
					_place_title()
			else:
				link.place_board(head)
		h.prev_ax = h.ax
		h.prev_by = h.by
	help_t = maxf(help_t - dt, 0.0)
	title.visible = help_t > 0.0
	fish.step(dt, fish_hands, head.origin)


# ---------------------------------------------------------------- scripted desktop test

var checks: Array[String] = []


func _check(what: String, ok: bool) -> void:
	checks.append("%s %s" % ["PASS" if ok else "FAIL", what])
	print(checks[-1])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(secs: float) -> void:
	var t := age + secs
	while age < t:
		await get_tree().process_frame


func _fake_hand(h: Hand, tip: Vector3) -> void:
	h.ok = true
	h.aim = Transform3D(Basis(Vector3.RIGHT, -0.3), tip)
	h.aim.origin = tip - h.aim.basis * TIP
	h.tip = tip


func _shot(shot: String, cam_pos: Vector3, target: Vector3) -> Image:
	camera.global_position = cam_pos
	camera.look_at(target)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shots_dir)
	img.save_png(shots_dir.path_join(shot + ".png"))
	print("shot ", shot)
	return img


func _all_fish() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in fish.species:
		for p in s.pos:
			out.append(p)
	return out


func _near(p: Vector3, r: float) -> int:
	var n := 0
	for q in _all_fish():
		if q.distance_to(p) < r:
			n += 1
	return n


func _run_test() -> void:
	await _frames(5)
	_check("fish spawned (%d)" % fish.fish_count(), fish.fish_count() >= 100)
	var before := _all_fish()
	await _wait(1.5)
	var after := _all_fish()
	var moved := 0.0
	for i in before.size():
		moved += before[i].distance_to(after[i])
	moved /= before.size()
	_check("fish swim (mean %.2f m in 1.5 s)" % moved, moved > 0.1)
	var inside := true
	for p in after:
		if p.y < 0.0 or p.y > 6.0 or Vector2(p.x, p.z).length() > 13.0:
			inside = false
	_check("fish stay inside the reef", inside)
	# frame rate of the whole scene on this GPU
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await _wait(2.0)
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1)
	print("desktop FPS %.1f" % fps)
	await _shot("overview", Vector3(0, 1.6, 0), Vector3(0, 1.2, -6))
	await _shot("back", Vector3(0, 1.6, 0), Vector3(2, 1.0, 6))
	await _shot("up", Vector3(0, 1.3, 0), Vector3(0.5, 6, -2.5))
	# curious fish come to a still finger
	var R := hands[1]
	var tip := Vector3(0.25, 1.3, -0.5)
	_fake_hand(R, tip)
	R.prev_tip = tip
	var near0 := _near(tip, 0.6)
	await _wait(8.0)
	var near1 := _near(tip, 0.6)
	_check("curious fish visit a still finger (%d -> %d within 0.6 m)" % [near0, near1], near1 > near0 and near1 >= 2)
	await _shot("finger", Vector3(0.05, 1.45, 0.05), tip)
	# a fast swipe scares them
	for k in 12:
		_fake_hand(R, tip + Vector3(sin(k * 0.8) * 0.4, 0, 0))
		await _frames(1)
	await _wait(0.6)
	var near2 := _near(tip, 0.6)
	_check("a fast swipe scatters them (%d -> %d)" % [near1, near2], near2 < near1)
	R.ok = false
	# feeding
	var eaten := [0]
	fish.ate.connect(func(_p: Vector3) -> void: eaten[0] += 1)
	var food_at := Vector3(-0.3, 1.4, -0.8)
	for k in 10:
		fish.drop_pellet(food_at + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), Vector3.ZERO)
	await _wait(5.0)
	await _shot("feeding", Vector3(0.1, 1.55, 0.1), food_at - Vector3(0, 0.25, 0))
	await _wait(5.0)
	_check("fish eat the food (%d of 10 pellets)" % eaten[0], eaten[0] >= 5)
	# calling
	fish.call_fish(Vector3(0, 1.3, -0.8))
	await _wait(6.0)
	_check("A/X calls the fish (%d near)" % _near(Vector3(0, 1.3, -0.8), 1.0), _near(Vector3(0, 1.3, -0.8), 1.0) >= 8)
	# close-up of one of each species for a cuteness check
	for s in fish.species:
		var p: Vector3 = s.pos[0]
		var fw: Vector3 = s.fwd[0]
		var side := fw.cross(Vector3.UP).normalized()
		await _shot("cute_" + s.name, p + side * s.size * 3.2 - fw * s.size * 1.2 + Vector3(0, s.size * 0.4, 0), p)
	# link: log, eval and run a live script the same way Claude will from Termux
	var r: Dictionary = link._handle(JSON.stringify({"cmd": "log", "text": "hello from the test"}))
	_check("link log", r.ok and link.lines[-1].ends_with("hello from the test"))
	r = link._handle(JSON.stringify({"cmd": "eval", "expr": "fish.fish_count()"}))
	_check("link eval (%s)" % r.get("result", r.get("error")), r.ok and int(r.result) == fish.fish_count())
	var code := "extends Node3D\nvar main\nfunc _ready():\n\tvar m := MeshInstance3D.new()\n\tm.mesh = BoxMesh.new()\n\tadd_child(m)\n\tposition = Vector3(0, 1, -2)\n"
	r = link._run("test_cube", code, false)
	await _frames(2)
	var node := link.live_root.get_node_or_null("test_cube")
	_check("link run builds a live node", r.ok and node != null and node.get("main") == self)
	r = link._run("broken", "extends Node3D\nfunc _ready(:\n", false)
	_check("link rejects a broken script", not r.ok)
	if node:
		node.queue_free()
	link.add_line("all tests done")
	link.place_board(Transform3D(Basis(), Vector3(0, 1.6, 0)))
	await _shot("board", Vector3(-0.45, 1.6, 0.2), link.board.global_position)
	if make_icon:
		var s: Fish.Species = fish.species[0]
		var p: Vector3 = s.pos[0]
		var fw: Vector3 = s.fwd[0]
		var side := fw.cross(Vector3.UP).normalized()
		var img := await _shot("icon_src", p + side * s.size * 2.6 - fw * s.size * 0.8, p)
		var h := img.get_height()
		var ic := img.get_region(Rect2i((img.get_width() - h) / 2, 0, h, h))
		ic.resize(192, 192)
		ic.save_png(ProjectSettings.globalize_path("res://icon.png"))
		print("icon written")
	var fails := checks.filter(func(c: String) -> bool: return c.begins_with("FAIL")).size()
	print("RESULT: %d checks, %d failed" % [checks.size(), fails])
	get_tree().quit(1 if fails > 0 else 0)
