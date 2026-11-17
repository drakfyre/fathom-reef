extends Node3D
## Cute procedural fish. One MultiMesh per species (one draw call each), simple flocking on the
## CPU, tail wiggle in the vertex shader. Fish come to look at a still hand, nibble fingertips,
## scatter from a fast hand and chase food pellets.

signal ate(pos: Vector3)
signal nibbled(hand: int, pos: Vector3)

const BOUND_R := 10.0
const Y_MIN := 0.35
const Y_MAX := 5.0

const SHADER := """shader_type spatial;
render_mode cull_disabled;
varying vec3 col;
// COLOR.a = 1: tinted part (INSTANCE_CUSTOM.rgb * COLOR.r, whitened by COLOR.g)
// COLOR.a = 0: fixed colour (eyes, stripes).  INSTANCE_CUSTOM.a = swim phase.  UV.x = fin flap.
void vertex() {
	float ph = INSTANCE_CUSTOM.a;
	float k = smoothstep(-0.25, 0.85, VERTEX.z);
	VERTEX.x += sin(ph - VERTEX.z * 6.0) * 0.12 * k * k + sin(ph) * 0.015;
	VERTEX.y += UV.x * sin(ph * 0.7) * 0.25 * abs(VERTEX.x);
	vec3 tinted = mix(INSTANCE_CUSTOM.rgb * COLOR.r, vec3(1.0), COLOR.g);
	col = mix(COLOR.rgb, tinted, COLOR.a);
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * 0.22 + vec3(0.3, 0.7, 0.9) * rim * 0.3;
}
"""


class Species:
	var name := ""
	var count := 0
	var size := 0.2          # body length (m)
	var speed := 0.4         # cruise speed (m/s)
	var school := 1.0        # how tightly they flock
	var spread := 2.0        # how far individuals roam from the group target
	var tints: Array[Color] = []
	var mmi: MultiMeshInstance3D
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var fwd := PackedVector3Array()
	var off := PackedVector3Array()    # personal offset from the group target
	var phase := PackedFloat32Array()
	var scl := PackedFloat32Array()
	var tint := PackedColorArray()
	var curious := PackedByteArray()
	var cool := PackedFloat32Array()   # nibble / eat cooldown
	var target := Vector3.ZERO
	var target_t := 0.0


var species: Array[Species] = []
var mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var pellets: Array[Dictionary] = []   # {node, vel, age}
var pellet_mesh: SphereMesh
var pellet_mat: StandardMaterial3D
var call_t := 0.0                     # >0 while the player is calling the fish
var call_point := Vector3.ZERO
var frame := 0


func _ready() -> void:
	rng.seed = 7
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	pellet_mesh = SphereMesh.new()
	pellet_mesh.radius = 0.009
	pellet_mesh.height = 0.018
	pellet_mesh.radial_segments = 6
	pellet_mesh.rings = 3
	pellet_mat = StandardMaterial3D.new()
	pellet_mat.albedo_color = Color(0.95, 0.55, 0.2)
	pellet_mat.emission_enabled = true
	pellet_mat.emission = Color(0.5, 0.25, 0.05)
	_add("puffer", 9, 0.16, 0.25, 0.3, 3.5, [Color(1.0, 0.75, 0.85), Color(1.0, 0.9, 0.5), Color(0.75, 0.9, 1.0)],
			_mesh_puffer())
	_add("clown", 14, 0.13, 0.35, 0.8, 1.5, [Color(1.0, 0.5, 0.15), Color(1.0, 0.42, 0.25)], _mesh_clown())
	_add("tang", 10, 0.22, 0.45, 0.6, 2.5, [Color(0.25, 0.45, 1.0), Color(0.35, 0.55, 1.0)], _mesh_tang())
	_add("minnow", 70, 0.09, 0.7, 1.6, 0.7, [Color(0.55, 0.95, 0.9), Color(0.6, 0.85, 1.0), Color(0.75, 1.0, 0.85)],
			_mesh_minnow())
	_add("pinky", 12, 0.12, 0.4, 1.0, 1.2, [Color(1.0, 0.55, 0.9), Color(0.85, 0.6, 1.0)], _mesh_pinky())


func fish_count() -> int:
	var t := 0
	for s in species:
		t += s.count
	return t


# ---------------------------------------------------------------- simulation

func _add(nm: String, count: int, size: float, speed: float, school: float, spread: float,
		tints: Array, mesh: ArrayMesh) -> void:
	var s := Species.new()
	s.name = nm
	s.count = count
	s.size = size
	s.speed = speed
	s.school = school
	s.spread = spread
	for t: Color in tints:
		s.tints.append(t)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	s.mmi = MultiMeshInstance3D.new()
	s.mmi.multimesh = mm
	s.mmi.material_override = mat
	s.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.mmi.custom_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 10, 30))
	add_child(s.mmi)
	s.target = _rand_point()
	for i in count:
		var p := s.target + _rand_dir() * rng.randf_range(0.3, s.spread)
		p.y = clampf(p.y, Y_MIN + 0.2, Y_MAX - 0.5)
		s.pos.append(p)
		var d := _rand_dir()
		d.y *= 0.2
		s.vel.append(d.normalized() * s.speed)
		s.fwd.append(d.normalized())
		s.off.append(_rand_dir() * rng.randf_range(0.0, s.spread))
		s.phase.append(rng.randf() * TAU)
		s.scl.append(size * rng.randf_range(0.85, 1.15))
		s.tint.append(s.tints[rng.randi() % s.tints.size()].srgb_to_linear())
		s.curious.append(1 if rng.randf() < 0.5 else 0)
		s.cool.append(0.0)
	for i in count:
		mm.set_instance_color(i, Color(1, 1, 1, 1))
	species.append(s)


func _rand_dir() -> Vector3:
	return Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()


func _rand_point() -> Vector3:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * (BOUND_R - 3.0) + 1.5
	return Vector3(cos(a) * r, rng.randf_range(0.8, 3.5), sin(a) * r)


func drop_pellet(at: Vector3, v: Vector3) -> void:
	if pellets.size() >= 80:
		pellets[0].node.queue_free()
		pellets.remove_at(0)
	var mi := MeshInstance3D.new()
	mi.mesh = pellet_mesh
	mi.material_override = pellet_mat
	add_child(mi)
	mi.global_position = at
	pellets.append({"node": mi, "vel": v, "age": 0.0})


func call_fish(point: Vector3) -> void:
	call_t = 6.0
	call_point = point


## hands: Array of {ok, tip, vel} dictionaries.  head: player's head position.
func step(dt: float, hands: Array, head: Vector3) -> void:
	dt = minf(dt, 0.05)
	frame += 1
	call_t = maxf(call_t - dt, 0.0)
	_step_pellets(dt)
	for s in species:
		_step_species(s, dt, hands, head)


func _step_pellets(dt: float) -> void:
	for i in range(pellets.size() - 1, -1, -1):
		var p: Dictionary = pellets[i]
		var node: MeshInstance3D = p.node
		var v: Vector3 = p.vel
		v = v.lerp(Vector3(0, -0.06, 0), clampf(dt * 2.0, 0.0, 1.0))
		p.vel = v
		p.age += dt
		var np := node.position + v * dt
		np.y = maxf(np.y, 0.02)
		node.position = np
		if p.age > 40.0:
			node.queue_free()
			pellets.remove_at(i)


func _step_species(s: Species, dt: float, hands: Array, head: Vector3) -> void:
	s.target_t -= dt
	if s.target_t <= 0.0:
		s.target = _rand_point()
		s.target_t = rng.randf_range(6.0, 14.0)
	var neigh_r2 := pow(s.size * 6.0, 2)
	var sep_r2 := pow(s.size * 1.6, 2)
	var mm := s.mmi.multimesh
	var flock_now := (frame + s.count) % 2  # flocking for half the fish each frame
	for i in s.count:
		var p := s.pos[i]
		var v := s.vel[i]
		var acc := Vector3.ZERO
		var max_speed := s.speed
		s.cool[i] = maxf(s.cool[i] - dt, 0.0)
		# wander toward the group target (plus a personal offset)
		var goal := s.target + s.off[i]
		var busy := false
		# food beats everything
		if not pellets.is_empty() and s.cool[i] <= 0.0:
			var best := -1
			var bd := 5.0
			for k in pellets.size():
				var d := p.distance_to(pellets[k].node.position)
				if d < bd:
					bd = d
					best = k
			if best >= 0:
				var pp: Vector3 = pellets[best].node.position
				goal = pp
				busy = true
				max_speed = s.speed * 1.8
				if bd < s.scl[i] * 0.45 + 0.02:
					ate.emit(pp)
					pellets[best].node.queue_free()
					pellets.remove_at(best)
					s.cool[i] = 1.5
					v = -v * 0.3
		if not busy and call_t > 0.0 and s.curious[i] == 1:
			goal = call_point + s.off[i].normalized() * 0.5
			busy = true
		acc += (goal - p).limit_length(1.0) * (1.2 if busy else 0.5)
		# hands: curious fish come to look at still hands and nibble; everyone flees fast ones
		for hi in hands.size():
			var h: Dictionary = hands[hi]
			if not h.ok:
				continue
			var tip: Vector3 = h.tip
			var dvec := p - tip
			var d := dvec.length()
			var hs: float = (h.vel as Vector3).length()
			if hs > 0.9 and d < 1.0:
				acc += dvec / maxf(d, 0.05) * 8.0 * (1.0 - d)
				max_speed = s.speed * 3.5
			elif s.curious[i] == 1 and not busy and d < 3.0 and s.cool[i] <= 0.0:
				var want := tip + dvec / maxf(d, 0.01) * 0.12
				acc += (want - p).limit_length(0.6) * 4.0
				max_speed = s.speed * clampf(d, 0.4, 1.0)
				if d < s.scl[i] * 0.5 + 0.03:
					nibbled.emit(hi, tip)
					s.cool[i] = rng.randf_range(2.0, 5.0)
					v = dvec.normalized() * s.speed * 2.0
		# keep out of the player's face
		var dh := p - head
		var dhl := dh.length()
		if dhl < 0.5:
			acc += dh / maxf(dhl, 0.05) * 5.0 * (0.5 - dhl) / 0.5 * 4.0
		# flocking
		if flock_now == i % 2:
			var coh := Vector3.ZERO
			var ali := Vector3.ZERO
			var sep := Vector3.ZERO
			var nn := 0
			for j in s.count:
				if j == i:
					continue
				var dj := s.pos[j] - p
				var d2 := dj.length_squared()
				if d2 < neigh_r2:
					coh += dj
					ali += s.vel[j]
					nn += 1
					if d2 < sep_r2:
						sep -= dj / maxf(d2, 1e-4) * s.size
			if nn > 0:
				acc += (coh / nn) * s.school * 1.5 + ((ali / nn) - v) * s.school * 0.8
			acc += sep * 2.0
		# bounds
		var hr := Vector2(p.x, p.z).length()
		if hr > BOUND_R:
			acc += Vector3(-p.x, 0, -p.z) / hr * (hr - BOUND_R) * 2.0
		if p.y < Y_MIN:
			acc.y += (Y_MIN - p.y) * 10.0
		if p.y > Y_MAX:
			acc.y -= (p.y - Y_MAX) * 4.0
		acc.y -= v.y * 0.6   # fish like to swim level
		v += acc * dt
		var sp := v.length()
		var min_speed := s.speed * 0.25
		if sp > max_speed:
			v = v * (lerpf(sp, max_speed, clampf(dt * 3.0, 0.0, 1.0)) / sp)
		elif sp < min_speed:
			v = v * (min_speed / maxf(sp, 1e-4)) if sp > 1e-4 else s.fwd[i] * min_speed
		p += v * dt
		s.pos[i] = p
		s.vel[i] = v
		# heading turns smoothly and stays fairly level
		var want_f := v.normalized()
		want_f.y = clampf(want_f.y, -0.5, 0.5)
		var f := s.fwd[i].lerp(want_f, clampf(dt * 4.0, 0.0, 1.0)).normalized()
		s.fwd[i] = f
		s.phase[i] = fmod(s.phase[i] + dt * minf(5.0 + 2.2 * v.length() / s.scl[i], 28.0), TAU * 64.0)
		var b := Basis.looking_at(f, Vector3.UP) if absf(f.y) < 0.98 else Basis()
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * s.scl[i]), p))
		var tc := s.tint[i]
		mm.set_instance_custom_data(i, Color(tc.r, tc.g, tc.b, s.phase[i]))


# ---------------------------------------------------------------- fish meshes (unit length, nose at -Z)

static func _tag(shade: float, whiten := 0.0) -> Color:
	return Color(shade, whiten, 0.0, 1.0)


static func _fixed(col: Color) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, 0.0)


func _body(g: Geo, w: float, h: float, col: Callable, rings := 16, segs := 14) -> void:
	var vb := g.v.size()
	var ib := g.idx.size()
	for ri in rings + 1:
		var t := float(ri) / rings
		var z := -0.5 + t
		var r := pow(sin(PI * t), 0.55) * (1.0 - 0.6 * smoothstep(0.6, 1.0, t))
		for si in segs:
			var a := TAU * si / segs
			var p := Vector3(cos(a) * w * 0.5 * r, sin(a) * h * 0.5 * r, z)
			g.vtx(p, Vector3(cos(a), sin(a), (t - 0.5) * 0.8).normalized(), col.call(t, a, p))
	for ri in rings:
		for si in segs:
			var a := vb + ri * segs + si
			var b := vb + ri * segs + (si + 1) % segs
			g.quad(a, a + segs, b + segs, b)
	g.smooth_normals(vb, ib)


func _ellipsoid(g: Geo, center: Vector3, radii: Vector3, col: Color) -> void:
	g.add_arrays(Geo.sphere(10, 6), Transform3D(Basis.from_scale(radii * 2.0), center), col)


func _eyes(g: Geo, z: float, x: float, y: float, r: float, blush := true) -> void:
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(x * sx, y, z)
		_ellipsoid(g, c, Vector3(r * 0.7, r, r), _fixed(Color(1, 1, 1)))
		_ellipsoid(g, c + Vector3(r * 0.55 * sx, -r * 0.05, -r * 0.15), Vector3(r * 0.35, r * 0.68, r * 0.62),
				_fixed(Color(0.04, 0.04, 0.08)))
		_ellipsoid(g, c + Vector3(r * 0.85 * sx, r * 0.3, -r * 0.35), Vector3(r * 0.12, r * 0.2, r * 0.2),
				_fixed(Color(1, 1, 1)))
		if blush:
			_ellipsoid(g, Vector3((x - r * 0.15) * sx, y - r * 1.25, z + r * 0.9), Vector3(r * 0.25, r * 0.3, r * 0.45),
					_fixed(Color(1.0, 0.55, 0.65)))


func _tail(g: Geo, z0: float, hb: float, ln: float, ht: float, col: Color) -> void:
	var nrm := Vector3.RIGHT
	var a := g.vtx(Vector3(0, hb, z0), nrm, col)
	var b := g.vtx(Vector3(0, -hb, z0), nrm, col)
	var top := g.vtx(Vector3(0, ht, z0 + ln), nrm, col)
	var bot := g.vtx(Vector3(0, -ht, z0 + ln), nrm, col)
	var notch := g.vtx(Vector3(0, 0, z0 + ln * 0.7), nrm, col)
	g.tri(a, top, notch)
	g.tri(a, notch, b)
	g.tri(b, notch, bot)


func _fin_top(g: Geo, z0: float, z1: float, y0: float, hgt: float, col: Color) -> void:
	var nrm := Vector3.RIGHT
	var a := g.vtx(Vector3(0, y0, z0), nrm, col)
	var b := g.vtx(Vector3(0, y0 * 0.8, z1), nrm, col)
	var tip := g.vtx(Vector3(0, y0 + hgt, lerpf(z0, z1, 0.75)), nrm, col)
	g.tri(a, tip, b)


func _fin_side(g: Geo, z: float, x: float, y: float, s: float, col: Color) -> void:
	for sx: float in [-1.0, 1.0]:
		var nrm := Vector3.UP
		var a := g.vtx(Vector3(x * sx, y, z), nrm, col, 0.0)
		var b := g.vtx(Vector3(x * sx, y, z + s), nrm, col, 0.0)
		var tip := g.vtx(Vector3((x + s * 0.9) * sx, y - s * 0.3, z + s * 1.1), nrm, col, 1.0)
		g.tri(a, b, tip)


func _finish(g: Geo) -> ArrayMesh:
	return g.commit()


func _mesh_puffer() -> ArrayMesh:
	var g := Geo.new()
	_body(g, 0.72, 0.78, func(t: float, a: float, p: Vector3) -> Color:
		var spot := sin(p.z * 40.0) * sin(a * 5.0) > 0.75
		return _tag(0.75 if spot else 1.0, 0.75 if p.y < -0.05 else 0.1))
	_eyes(g, -0.25, 0.25, 0.12, 0.12)
	_tail(g, 0.42, 0.05, 0.22, 0.14, _tag(1.0, 0.45))
	_fin_top(g, -0.05, 0.25, 0.3, 0.12, _tag(1.0, 0.45))
	_fin_side(g, -0.05, 0.3, -0.02, 0.12, _tag(1.0, 0.5))
	return _finish(g)


func _mesh_clown() -> ArrayMesh:
	var g := Geo.new()
	_body(g, 0.32, 0.46, func(t: float, a: float, p: Vector3) -> Color:
		for c: float in [0.27, 0.58, 0.9]:
			var d := absf(t - c)
			if d < 0.05:
				return _fixed(Color(1, 1, 1))
			if d < 0.075:
				return _fixed(Color(0.08, 0.05, 0.05))
		return _tag(1.0, 0.0))
	_eyes(g, -0.3, 0.12, 0.06, 0.085)
	_tail(g, 0.42, 0.06, 0.25, 0.17, _tag(1.0, 0.1))
	_fin_top(g, -0.15, 0.35, 0.2, 0.12, _tag(1.0, 0.0))
	_fin_side(g, -0.08, 0.15, -0.05, 0.12, _tag(1.0, 0.2))
	return _finish(g)


func _mesh_tang() -> ArrayMesh:
	var g := Geo.new()
	_body(g, 0.2, 0.78, func(t: float, a: float, p: Vector3) -> Color:
		var dark := p.y > 0.12 and absf(p.z + 0.05) < 0.3
		return _tag(0.35 if dark else 1.0, 0.0))
	_eyes(g, -0.28, 0.08, 0.1, 0.09)
	_tail(g, 0.42, 0.06, 0.28, 0.24, _fixed(Color(1.0, 0.85, 0.15)))
	_fin_top(g, -0.25, 0.4, 0.33, 0.1, _tag(0.4, 0.0))
	_fin_side(g, -0.1, 0.1, -0.05, 0.14, _fixed(Color(1.0, 0.85, 0.15)))
	return _finish(g)


func _mesh_minnow() -> ArrayMesh:
	var g := Geo.new()
	var col := func(t: float, a: float, p: Vector3) -> Color:
		if absf(p.y) < 0.012:
			return _tag(1.0, 0.55)
		return _tag(0.85, 0.75 if p.y < 0.0 else 0.0)
	_body(g, 0.2, 0.3, col, 12, 10)
	_eyes(g, -0.33, 0.07, 0.04, 0.065, false)
	_tail(g, 0.42, 0.03, 0.22, 0.13, _tag(1.0, 0.3))
	_fin_top(g, -0.05, 0.2, 0.13, 0.08, _tag(1.0, 0.3))
	return _finish(g)


func _mesh_pinky() -> ArrayMesh:
	var g := Geo.new()
	_body(g, 0.42, 0.52, func(t: float, a: float, p: Vector3) -> Color:
		return _tag(1.0, 0.6 if p.y < -0.06 else 0.05))
	_eyes(g, -0.27, 0.15, 0.08, 0.1)
	_tail(g, 0.42, 0.05, 0.3, 0.2, _fixed(Color(1.0, 0.85, 0.95)))
	_fin_top(g, -0.2, 0.3, 0.24, 0.16, _fixed(Color(1.0, 0.85, 0.95)))
	_fin_side(g, -0.08, 0.2, -0.05, 0.13, _fixed(Color(1.0, 0.85, 0.95)))
	return _finish(g)
