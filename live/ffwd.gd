extends Node3D
## Fast-forward panel for the robot gyms: poke 1x / 2x / 3x / 4x with a fingertip.
## Uses main.set_sim_speed(k): physics ticks k times as often with the SAME 1/90 s step, so the
## robots' physics is exactly as stable as at 1x; only the CPU work grows. If the headset can't
## keep up (under 72 FPS for 1.5 s) it steps down a level by itself so VR stays comfortable.
## The readout shows the speed actually reached (simulated seconds per real second).

const SPEEDS := [1.0, 2.0, 3.0, 4.0]
const BTN := Vector2(0.075, 0.055)

var main
var level := 0
var buttons: Array[MeshInstance3D] = []
var mats: Array[StandardMaterial3D] = []
var readout: Label3D
var press_cool := 0.0
var slow_t := 0.0
var settle := 0.0
var ticks := 0
var win_t := 0.0
var actual := 1.0


func _ready() -> void:
	_build()
	_place()
	_apply(0)


func _place() -> void:
	var head: Transform3D = main.head_transform() if main else Transform3D(Basis(), Vector3(0, 1.6, 0))
	var f := -head.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var right := f.cross(Vector3.UP)
	var p := head.origin + f * 0.5 + right * 0.4 + Vector3(0, -0.3, 0)
	# face the player, tilted back a little like a control desk
	global_transform = Transform3D(Basis.looking_at(f, Vector3.UP) * Basis(Vector3.RIGHT, -0.5), p)


func _build() -> void:
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.2, 0.012)
	back.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.06, 0.1, 0.16)
	bmat.emission_enabled = true
	bmat.emission = Color(0.02, 0.05, 0.08)
	back.material_override = bmat
	back.position.z = -0.012
	add_child(back)
	var title := Label3D.new()
	title.text = "ROBOT FAST-FORWARD"
	title.font_size = 36
	title.pixel_size = 0.0008
	title.outline_size = 0
	title.modulate = Color(1.0, 0.7, 0.85)
	title.shaded = false
	title.position = Vector3(0, 0.075, 0)
	add_child(title)
	for i in SPEEDS.size():
		var b := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(BTN.x, BTN.y, 0.018)
		b.mesh = m
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		b.material_override = mat
		b.position = Vector3(-0.135 + i * 0.09, 0.01, 0)
		add_child(b)
		var l := Label3D.new()
		l.text = "%d×" % int(SPEEDS[i])
		l.font_size = 48
		l.pixel_size = 0.0008
		l.outline_size = 0
		l.modulate = Color.WHITE
		l.shaded = false
		l.position = Vector3(0, 0, 0.0095)
		b.add_child(l)
		buttons.append(b)
		mats.append(mat)
	readout = Label3D.new()
	readout.font_size = 28
	readout.pixel_size = 0.0008
	readout.outline_size = 0
	readout.modulate = Color(0.85, 0.95, 1.0)
	readout.shaded = false
	readout.position = Vector3(0, -0.06, 0)
	add_child(readout)


func _apply(i: int) -> void:
	level = i
	if main and main.has_method("set_sim_speed"):
		main.set_sim_speed(SPEEDS[i])
	elif SPEEDS[i] != 1.0 and main:
		main.link.add_line("fast-forward needs the updated app (main.set_sim_speed)")
		level = 0
	settle = 3.0
	slow_t = 0.0
	for k in mats.size():
		var on := k == level
		mats[k].albedo_color = Color(1.0, 0.45, 0.7) if on else Color(0.2, 0.32, 0.42)
		mats[k].emission = Color(0.6, 0.15, 0.35) if on else Color(0.03, 0.06, 0.09)
		buttons[k].position.z = -0.006 if on else 0.0


func _physics_process(_dt: float) -> void:
	ticks += 1


func _process(scaled_dt: float) -> void:
	var dt := scaled_dt / Engine.time_scale
	press_cool = maxf(press_cool - dt, 0.0)
	settle = maxf(settle - dt, 0.0)
	# measured speed: physics ticks per real second / base tick rate
	win_t += dt
	if win_t >= 1.0:
		actual = ticks / win_t / 90.0
		ticks = 0
		win_t = 0.0
	var fps := Engine.get_frames_per_second()
	if level > 0 and settle <= 0.0 and fps < 72:
		slow_t += dt
		if slow_t > 1.5:
			if main:
				main.link.add_line("fast-forward: headset struggling at %d×, stepping down" % int(SPEEDS[level]))
			_apply(level - 1)
	else:
		slow_t = 0.0
	readout.text = "chosen %d×   actual %.1f×   %d FPS" % [int(SPEEDS[level]), actual, fps]
	if main == null:
		return
	# poke a button with either index fingertip
	var inv := global_transform.affine_inverse()
	for h in main.hands:
		if not h.ok or press_cool > 0.0:
			continue
		var lt: Vector3 = inv * h.tip
		for i in buttons.size():
			var c := buttons[i].position
			if absf(lt.x - c.x) < BTN.x * 0.5 and absf(lt.y - c.y) < BTN.y * 0.5 and lt.z < 0.012 and lt.z > -0.04:
				press_cool = 0.4
				if i != level:
					_apply(i)
					main.sfx.play("boop", h.tip, -4.0)
					main.link.add_line("fast-forward: %d×" % int(SPEEDS[i]))
				main.buzz(main.hands.find(h), 0.3, 0.04)
	# drift back if you swim away
	var head: Transform3D = main.head_transform()
	if global_position.distance_to(head.origin) > 4.0:
		_place()
