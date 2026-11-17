extends Node3D
## Robot gym: dog-sized four-legged spider tanks and 1.7 m humanoids on a floating test stage.
## Each robot is driven by its own small neural network:
##   inputs  = joint angles + joint speeds + body tilt + body speed + height + a rhythm clock
##   hidden  = 16 tanh neurons
##   outputs = one target angle per joint (motors chase them)
## They learn by evolution: a whole generation tries to walk to the right; the best networks are
## kept, copied with small random changes (mutations), and the next generation tries again.
## Progress is saved, so training carries on next time the reef starts.

const SAVE := "user://robots.json"
const STAGE := 3        # 1 = stage + robots standing still, 2 = random networks, 3 = evolution on
const HIDDEN := 16
const START_X := -3.6
const ANGLE_SIGN := -1.0 # flips motor direction if the physics engine measures angles the other way

var main
var arena: Node3D
var species := {}
var floor_mat: ShaderMaterial
var board: Label3D
var chart: MeshInstance3D
var chart_mesh: ImmediateMesh
var rng := RandomNumberGenerator.new()
var tick := 0


class Joint:
	var parent: RigidBody3D
	var child: RigidBody3D
	var j: Generic6DOFJoint3D
	var ap: Vector3   # hinge axis in parent space
	var rp: Vector3   # reference direction in parent space
	var rc: Vector3   # same direction in child space at rest
	var lo := -0.5
	var hi := 0.5
	var target := 0.0
	var force := 10.0

	func angle() -> float:
		var pb := parent.global_basis
		var a := pb * ap
		var p := pb * rp
		var c := child.global_basis * rc
		return atan2(a.dot(p.cross(c)), p.dot(c))

	func speed() -> float:
		return (child.angular_velocity - parent.angular_velocity).dot(parent.global_basis * ap)


class Robot:
	var root: Node3D
	var trunk: RigidBody3D
	var joints: Array = []
	var genome := PackedFloat32Array()
	var start := Vector3.ZERO
	var fitness := 0.0
	var alive := true
	var upright := 0.0
	var phase := 0.0
	var lane_z := 0.0


class Species:
	var name := ""
	var pop := 6
	var episode := 10.0
	var clock_hz := 1.5
	var lanes: Array = []
	var robots: Array = []
	var genomes: Array = []      # PackedFloat32Array per member
	var gen := 0
	var t := 0.0
	var record := -999.0
	var record_genome := PackedFloat32Array()
	var history: Array = []       # best distance of every generation (whole run)
	var scores: Array = []        # every robot's distance, every generation
	var trained := 0.0            # seconds of training so far
	var n_in := 0
	var n_out := 0
	var fall_h := 0.0
	var color := Color.WHITE


# ---------------------------------------------------------------- setup

func _ready() -> void:
	rng.randomize()
	var head: Transform3D = main.head_transform() if main else Transform3D(Basis(), Vector3(0, 1.6, 0))
	var f := -head.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	arena = Node3D.new()
	add_child(arena)
	# +X of the arena = the player's right (the way robots walk), -Z = away from the player
	var right := f.cross(Vector3.UP)
	var c := head.origin + f * 6.0
	arena.global_transform = Transform3D(Basis(right, Vector3.UP, -f), Vector3(c.x, 0.9, c.z))
	_build_stage()
	var sp := Species.new()
	sp.name = "spider"
	sp.pop = 6
	sp.episode = 12.0
	sp.clock_hz = 1.6
	sp.fall_h = 0.12
	sp.color = Color(0.45, 0.9, 1.0)
	for k in sp.pop:
		sp.lanes.append(3.4 - k * 0.8)
	species["spider"] = sp
	var hu := Species.new()
	hu.name = "humanoid"
	hu.pop = 5
	hu.episode = 8.0
	hu.clock_hz = 1.0
	hu.fall_h = 0.55
	hu.color = Color(1.0, 0.6, 0.85)
	for k in hu.pop:
		hu.lanes.append(-1.4 - k * 0.85)
	species["humanoid"] = hu
	_load()
	for s: Species in species.values():
		_spawn_generation(s)


func _mat(col: Color, glow := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	m.metallic = 0.3
	m.emission_enabled = true
	m.emission = col * glow
	return m


func _build_stage() -> void:
	var size := Vector3(9.0, 0.2, 9.0)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	sb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = Vector3(0, -0.1, -0.5)
	arena.add_child(sb)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 g = abs(fract(lp.xz * 2.0) - 0.5);
	float line = smoothstep(0.46, 0.49, max(g.x, g.y));
	float start = 1.0 - smoothstep(0.0, 0.04, abs(lp.x + 3.6));
	float edge = smoothstep(4.35, 4.48, max(abs(lp.x), abs(lp.z)));
	vec3 base = vec3(0.05, 0.09, 0.14);
	ALBEDO = base;
	ROUGHNESS = 0.6;
	EMISSION = vec3(0.1, 0.45, 0.6) * line * 0.6 + vec3(1.0, 0.5, 0.75) * (start + edge) * 0.9;
}"""
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = sh
	mi.material_override = floor_mat
	sb.add_child(mi)
	board = Label3D.new()
	board.font_size = 64
	board.pixel_size = 0.004
	board.outline_size = 12
	board.modulate = Color(0.9, 0.97, 1.0)
	board.outline_modulate = Color(0.03, 0.08, 0.15)
	board.shaded = false
	board.position = Vector3(0, 3.6, -5.2)
	board.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arena.add_child(board)
	chart_mesh = ImmediateMesh.new()
	chart = MeshInstance3D.new()
	chart.mesh = chart_mesh
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.vertex_color_use_as_albedo = true
	chart.material_override = cm
	chart.position = Vector3(-2.0, 1.6, -5.2)
	arena.add_child(chart)


# ---------------------------------------------------------------- bodies

func _seg(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _body(r: Robot, xf: Transform3D, shape: Shape3D, mesh: Mesh, mass: float, mat: Material) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.can_sleep = false
	b.collision_layer = 2
	b.collision_mask = 1
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	b.transform = xf
	r.root.add_child(b)
	return b


func _capsule(r: Robot, a: Vector3, b: Vector3, radius: float, mass: float, mat: Material) -> RigidBody3D:
	var h := a.distance_to(b) + radius * 2.0
	var s := CapsuleShape3D.new()
	s.radius = radius
	s.height = h
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = h
	m.radial_segments = 10
	m.rings = 3
	return _body(r, _seg(a, b), s, m, mass, mat)


func _box(r: Robot, center: Vector3, size: Vector3, mass: float, mat: Material) -> RigidBody3D:
	var s := BoxShape3D.new()
	s.size = size
	var m := BoxMesh.new()
	m.size = size
	return _body(r, Transform3D(Basis(), center), s, m, mass, mat)


func _joint(r: Robot, parent: RigidBody3D, child: RigidBody3D, at: Vector3, axis: Vector3, lo: float, hi: float,
		force: float) -> void:
	## A one-axis hinge (Generic6DOF with only angular X free) at `at` (robot space) around `axis`.
	var x := axis.normalized()
	var y := x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var jb := Basis(x, y, z)
	var j := Generic6DOFJoint3D.new()
	j.transform = Transform3D(jb, at)
	r.root.add_child(j)
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lo)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, hi)
	for ax in [1, 2]:
		var setf := j.set_flag_y if ax == 1 else j.set_flag_z
		var setp := j.set_param_y if ax == 1 else j.set_param_z
		setf.call(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		setp.call(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		setp.call(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, force)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
	var jj := Joint.new()
	jj.parent = parent
	jj.child = child
	jj.j = j
	jj.lo = lo
	jj.hi = hi
	jj.force = force
	var wb := r.root.global_basis * jb
	jj.ap = parent.global_basis.inverse() * wb.x
	jj.rp = parent.global_basis.inverse() * wb.y
	jj.rc = child.global_basis.inverse() * wb.y
	r.joints.append(jj)


func _make_spider(r: Robot, col: Color) -> void:
	## Dog-sized spider tank: armoured body with a little turret, four legs, two joints each.
	var hull := _mat(col.darkened(0.35), 0.1)
	var leg := _mat(Color(0.8, 0.85, 0.9), 0.1)
	var y0 := 0.3
	r.trunk = _box(r, Vector3(0, y0, 0), Vector3(0.5, 0.14, 0.36), 4.0, hull)
	var tur := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.09
	tm.bottom_radius = 0.12
	tm.height = 0.08
	tur.mesh = tm
	tur.position = Vector3(0, 0.11, 0)
	tur.material_override = _mat(col, 0.3)
	r.trunk.add_child(tur)
	var gun := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.018
	gm.bottom_radius = 0.022
	gm.height = 0.24
	gun.mesh = gm
	gun.rotation.z = -PI / 2
	gun.position = Vector3(0.14, 0.12, 0)
	gun.material_override = leg
	r.trunk.add_child(gun)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.03
	em.height = 0.06
	eye.mesh = em
	eye.position = Vector3(0.25, 0.0, 0)
	eye.material_override = _mat(Color(1.0, 0.4, 0.7), 2.0)
	r.trunk.add_child(eye)
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			var hip := Vector3(0.2 * sx, y0, 0.17 * sz)
			var knee := hip + Vector3(0.05 * sx, 0.03, 0.17 * sz)
			var foot := knee + Vector3(0.03 * sx, -0.3, 0.09 * sz)
			var upper := _capsule(r, hip, knee, 0.025, 0.35, leg)
			var lower := _capsule(r, knee, foot + Vector3(0, 0.03, 0), 0.022, 0.3, leg)
			_joint(r, r.trunk, upper, hip, Vector3.UP, -0.6, 0.6, 12.0)
			_joint(r, upper, lower, knee, Vector3(1, 0, 0), -0.7, 0.7, 12.0)


func _make_humanoid(r: Robot, col: Color) -> void:
	## 1.7 m humanoid: trunk + head, hip roll/pitch, knee, ankle, and swinging arms (10 joints).
	var skin := _mat(col.darkened(0.2), 0.12)
	var limb := _mat(Color(0.85, 0.88, 0.95), 0.08)
	var hip_y := 0.92
	r.trunk = _box(r, Vector3(0, 1.22, 0), Vector3(0.22, 0.6, 0.36), 18.0, skin)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.24
	head.mesh = hm
	head.position = Vector3(0, 0.44, 0)
	head.material_override = skin
	r.trunk.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.04, 0.05, 0.16)
	visor.mesh = vm
	visor.position = Vector3(0.1, 0.45, 0)
	visor.material_override = _mat(Color(0.4, 1.0, 0.9), 2.0)
	r.trunk.add_child(visor)
	for sz: float in [1.0, -1.0]:
		var hip := Vector3(0, hip_y, 0.1 * sz)
		var hipb := _box(r, hip, Vector3(0.08, 0.08, 0.08), 1.0, limb)
		_joint(r, r.trunk, hipb, hip, Vector3(1, 0, 0), -0.35, 0.35, 160.0)
		var knee := Vector3(0, 0.5, 0.1 * sz)
		var ankle := Vector3(0, 0.08, 0.1 * sz)
		var thigh := _capsule(r, hip - Vector3(0, 0.04, 0), knee, 0.06, 5.0, skin)
		_joint(r, hipb, thigh, hip, Vector3(0, 0, 1), -0.6, 1.3, 180.0)
		var shin := _capsule(r, knee, ankle, 0.05, 3.5, limb)
		_joint(r, thigh, shin, knee, Vector3(0, 0, 1), -1.6, 0.05, 160.0)
		var foot := _box(r, Vector3(0.05, 0.03, 0.1 * sz), Vector3(0.24, 0.06, 0.11), 1.2, skin)
		_joint(r, shin, foot, ankle, Vector3(0, 0, 1), -0.6, 0.6, 90.0)
		var sh := Vector3(0, 1.48, 0.23 * sz)
		var arm := _capsule(r, sh, sh + Vector3(0, -0.55, 0.02 * sz), 0.045, 2.5, limb)
		_joint(r, r.trunk, arm, sh, Vector3(0, 0, 1), -1.3, 1.3, 50.0)


func _spawn_generation(s: Species) -> void:
	for r: Robot in s.robots:
		r.root.queue_free()
	s.robots.clear()
	s.t = 0.0
	for i in s.pop:
		var r := Robot.new()
		r.root = Node3D.new()
		arena.add_child(r.root)
		r.lane_z = s.lanes[i]
		r.root.position = Vector3(START_X, 0.0, r.lane_z)
		var col := s.color
		if i == 0 and s.gen > 0:
			col = Color(1.0, 0.85, 0.3)   # last generation's champion
		if s.name == "spider":
			_make_spider(r, col)
		else:
			_make_humanoid(r, col)
		r.start = arena.global_transform.affine_inverse() * r.trunk.global_position
		r.phase = 0.0
		s.n_out = r.joints.size()
		s.n_in = r.joints.size() * 2 + 9
		if s.genomes.size() <= i or s.genomes[i].size() != _gsize(s):
			s.genomes.resize(maxi(s.genomes.size(), i + 1))
			s.genomes[i] = _random_genome(s)
		r.genome = s.genomes[i]
		s.robots.append(r)
	_update_board()


# ---------------------------------------------------------------- the neural network

func _gsize(s: Species) -> int:
	return (s.n_in + 1) * HIDDEN + (HIDDEN + 1) * s.n_out


func _random_genome(s: Species) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(_gsize(s))
	for i in g.size():
		g[i] = rng.randfn(0.0, 0.5)
	return g


func _forward(s: Species, g: PackedFloat32Array, x: PackedFloat32Array) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(HIDDEN)
	var k := 0
	for j in HIDDEN:
		var a := 0.0
		for i in s.n_in:
			a += g[k] * x[i]
			k += 1
		a += g[k]
		k += 1
		h[j] = tanh(a)
	var out := PackedFloat32Array()
	out.resize(s.n_out)
	for o in s.n_out:
		var a := 0.0
		for j in HIDDEN:
			a += g[k] * h[j]
			k += 1
		a += g[k]
		k += 1
		out[o] = tanh(a)
	return out


func _sense(s: Species, r: Robot) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	for jj: Joint in r.joints:
		x.append(jj.angle())
		x.append(clampf(jj.speed() * 0.1, -2.0, 2.0))
	var inv := arena.global_basis.inverse()
	var up := inv * r.trunk.global_basis.y
	var v := inv * r.trunk.linear_velocity
	var h := (arena.global_transform.affine_inverse() * r.trunk.global_position).y
	x.append_array([up.x, up.y, up.z, v.x * 0.5, v.y * 0.5, v.z * 0.5, h - r.start.y,
			sin(r.phase), cos(r.phase)])
	return x


# ---------------------------------------------------------------- running and evolving

func _physics_process(dt: float) -> void:
	tick += 1
	for s: Species in species.values():
		s.t += dt
		for r: Robot in s.robots:
			if not is_instance_valid(r.trunk):
				continue
			r.phase += dt * TAU * s.clock_hz
			var lp := arena.global_transform.affine_inverse() * r.trunk.global_position
			var up := (arena.global_basis.inverse() * r.trunk.global_basis.y).y
			if r.alive:
				if lp.y < s.fall_h or up < 0.25:
					r.alive = false   # fell over: its score is frozen here
				else:
					r.upright += dt
					r.fitness = (lp.x - r.start.x) - absf(lp.z - r.lane_z) * 0.3 + r.upright / s.episode * 0.5
			if STAGE >= 2 and r.alive and tick % 3 == 0:
				var out := _forward(s, r.genome, _sense(s, r))
				for k in r.joints.size():
					var jj: Joint = r.joints[k]
					jj.target = lerpf(jj.lo, jj.hi, out[k] * 0.5 + 0.5)
			for jj: Joint in r.joints:
				var goal := jj.target if r.alive else 0.0
				var vel := clampf((goal - jj.angle()) * 10.0, -7.0, 7.0) * ANGLE_SIGN
				jj.j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, vel)
		if STAGE >= 2 and s.t >= s.episode:
			_evolve(s)


func _evolve(s: Species) -> void:
	var order: Array = range(s.pop)
	order.sort_custom(func(a: int, b: int) -> bool: return s.robots[a].fitness > s.robots[b].fitness)
	var best: Robot = s.robots[order[0]]
	s.history.append(best.fitness)
	var all: Array = []
	for r: Robot in s.robots:
		all.append(snappedf(r.fitness, 0.001))
	s.scores.append(all)
	s.trained += s.t
	if best.fitness > s.record:
		s.record = best.fitness
		s.record_genome = best.genome.duplicate()
	if main:
		main.link.add_line("%s gen %d: best %.2f m  (record %.2f m)" % [s.name, s.gen + 1, best.fitness, s.record])
	var parents: Array = []
	for k in maxi(2, s.pop / 2):
		parents.append(s.robots[order[k]].genome)
	var next: Array = []
	next.append(best.genome.duplicate())                       # the champion stays as it is
	if s.record_genome.size() == best.genome.size() and STAGE >= 3:
		next.append(_mutate(s.record_genome, 0.05))           # and the all-time best, nudged
	while next.size() < s.pop:
		var a: PackedFloat32Array = parents[rng.randi() % parents.size()]
		var b: PackedFloat32Array = parents[rng.randi() % parents.size()]
		var child := a.duplicate()
		if rng.randf() < 0.5:
			var cut := rng.randi() % child.size()
			for i in range(cut, child.size()):
				child[i] = b[i]
		next.append(_mutate(child, 0.15 if STAGE >= 3 else 0.5))
	s.genomes = next
	s.gen += 1
	_save()
	_spawn_generation(s)


func _mutate(g: PackedFloat32Array, sigma: float) -> PackedFloat32Array:
	var c := g.duplicate()
	for i in c.size():
		if rng.randf() < 0.3:
			c[i] += rng.randfn(0.0, sigma)
	return c


# ---------------------------------------------------------------- scoreboard + saving

func _update_board() -> void:
	var lines: Array[String] = ["ROBOT GYM  -  learning to walk right  ->"]
	for s: Species in species.values():
		var last: float = s.history[-1] if not s.history.is_empty() else 0.0
		lines.append("%s x%d   generation %d   last best %.2f m   record %.2f m" %
				[s.name.capitalize(), s.pop, s.gen, last, maxf(s.record, 0.0)])
	board.text = "\n".join(lines)
	chart_mesh.clear_surfaces()
	chart_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	chart_mesh.surface_set_color(Color(0.5, 0.6, 0.7))
	chart_mesh.surface_add_vertex(Vector3(0, 0, 0))
	chart_mesh.surface_add_vertex(Vector3(4, 0, 0))
	chart_mesh.surface_add_vertex(Vector3(0, 0, 0))
	chart_mesh.surface_add_vertex(Vector3(0, 1.2, 0))
	for s: Species in species.values():
		var hist: Array = s.history.slice(-60)
		chart_mesh.surface_set_color(s.color)
		for i in range(1, hist.size()):
			var a := Vector3((i - 1) / 59.0 * 4.0, clampf(hist[i - 1], 0.0, 6.0) / 6.0 * 1.2, 0)
			var b := Vector3(i / 59.0 * 4.0, clampf(hist[i], 0.0, 6.0) / 6.0 * 1.2, 0)
			chart_mesh.surface_add_vertex(a)
			chart_mesh.surface_add_vertex(b)
	chart_mesh.surface_end()


func _save() -> void:
	## Everything needed to carry on later: every network's weights (the whole current generation,
	## plus the all-time best), and the full history. Written to a temp file first, then swapped
	## in, with the previous save kept as a .bak, so a crash mid-write can't lose the training.
	var d := {"format": 2, "saved": Time.get_datetime_string_from_system(), "hidden": HIDDEN}
	for s: Species in species.values():
		var gs: Array = []
		for g: PackedFloat32Array in s.genomes:
			gs.append(Array(g))
		d[s.name] = {"gen": s.gen, "record": s.record, "history": s.history, "scores": s.scores,
				"trained_s": s.trained, "inputs": s.n_in, "outputs": s.n_out, "genomes": gs,
				"record_genome": Array(s.record_genome)}
	var f := FileAccess.open(SAVE + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "", false, true))
	f.close()
	if FileAccess.file_exists(SAVE):
		DirAccess.rename_absolute(SAVE, SAVE + ".bak")
	DirAccess.rename_absolute(SAVE + ".tmp", SAVE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not species.is_empty():
			_save()


func _load() -> void:
	for path in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				_apply(d)
				if main:
					main.link.add_line("robots: resumed training from %s" % path.get_file())
				return


func _apply(d: Dictionary) -> void:
	if int(d.get("hidden", HIDDEN)) != HIDDEN:
		return   # a different network shape: start fresh
	for nm: String in d:
		if not species.has(nm) or not d[nm] is Dictionary:
			continue
		var s: Species = species[nm]
		var e: Dictionary = d[nm]
		s.gen = int(e.get("gen", 0))
		s.record = float(e.get("record", -999.0))
		s.history = e.get("history", [])
		s.scores = e.get("scores", [])
		s.trained = float(e.get("trained_s", 0.0))
		s.record_genome = PackedFloat32Array(e.get("record_genome", []))
		for g: Array in e.get("genomes", []):
			s.genomes.append(PackedFloat32Array(g))
