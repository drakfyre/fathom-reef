extends Node3D
## The underwater world: water colour + fog, sand with caustics, rocks, corals, anemones,
## kelp forest, starfish, light shafts, the water surface overhead, bubbles and marine snow.
## Everything static is merged into one mesh (one draw call) with a swaying vertex shader.

const FOG := Color(0.02, 0.17, 0.27)   # linear; also the sky's horizon colour

const SKY_SHADER := """shader_type sky;
void sky() {
	float y = EYEDIR.y;
	vec3 deep = vec3(0.004, 0.025, 0.06);
	vec3 mid = vec3(0.02, 0.17, 0.27);
	vec3 top = vec3(0.2, 0.55, 0.65);
	vec3 c = mix(mid, top, smoothstep(0.0, 0.95, y));
	c = mix(c, deep, smoothstep(0.0, -0.5, y));
	c += vec3(0.6, 0.9, 0.9) * pow(max(y, 0.0), 14.0) * 0.9;
	COLOR = c;
}
"""

const CAUSTIC := """
float caustic(vec2 p, float t) {
	vec2 q = p;
	for (int n = 0; n < 3; n++) {
		q += vec2(sin(q.y * 1.3 + t), cos(q.x * 1.1 - t * 0.8)) * 0.55;
	}
	float a = abs(sin(q.x + q.y * 0.5));
	float b = abs(sin(q.y - q.x * 0.4));
	return pow(clamp(1.0 - min(a, b), 0.0, 1.0), 10.0);
}
"""

const SAND_SHADER := """shader_type spatial;
varying vec3 wp;
""" + CAUSTIC + """
void vertex() {
	vec2 q = VERTEX.xz;
	float d = length(q);
	VERTEX.y += (sin(q.x * 0.35 + 1.0) * cos(q.y * 0.28) * 0.35 + sin(q.x * 1.3 + q.y * 0.9) * 0.04)
			* smoothstep(2.0, 6.0, d) - 0.02;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float ripple = sin(wp.x * 9.0 + sin(wp.z * 2.0) * 2.0) * 0.5 + 0.5;
	vec3 sand = mix(vec3(0.42, 0.36, 0.25), vec3(0.55, 0.48, 0.34), ripple * 0.6);
	ALBEDO = sand;
	ROUGHNESS = 0.95;
	float fade = clamp(1.0 - length(wp.xz - CAMERA_POSITION_WORLD.xz) / 14.0, 0.0, 1.0);
	EMISSION = vec3(0.45, 0.8, 0.85) * caustic(wp.xz * 1.6, TIME * 0.5) * 0.55 * fade + sand * 0.08;
}
"""

const REEF_SHADER := """shader_type spatial;
render_mode cull_disabled;
varying vec3 wn;
varying vec3 wp;
""" + CAUSTIC + """
void vertex() {
	float w = UV.x;
	float t = TIME;
	VERTEX.x += sin(t * 1.1 + VERTEX.x * 0.6 + VERTEX.z * 0.4 + VERTEX.y * 0.5) * w;
	VERTEX.z += cos(t * 0.9 + VERTEX.x * 0.5 + VERTEX.y * 0.4) * w * 0.6;
	wn = NORMAL;
	wp = VERTEX;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	float up = clamp(wn.y, 0.0, 1.0);
	float c = 0.0;
	if (up > 0.05) { c = caustic(wp.xz * 1.6, TIME * 0.5) * up; }
	EMISSION = COLOR.rgb * 0.18 + vec3(0.45, 0.8, 0.85) * c * 0.35;
}
"""

const RAY_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float seed = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fall = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float flick = 0.6 + 0.4 * sin(TIME * 0.7 + seed * 3.0 + wp.y * 0.5);
	float near = smoothstep(0.8, 3.0, distance(wp, CAMERA_POSITION_WORLD));
	ALBEDO = vec3(0.55, 0.85, 0.95) * edge * edge * fall * flick * near * 0.07;
}
"""

const SURFACE_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.6;
	float w = sin(p.x * 2.0 + TIME * 0.8 + sin(p.y * 1.7 + TIME * 0.5)) * sin(p.y * 2.3 - TIME * 0.6 + sin(p.x * 1.3));
	float glint = pow(max(w, 0.0), 6.0);
	float d = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	vec3 base = mix(vec3(0.25, 0.6, 0.68), vec3(0.02, 0.17, 0.27), smoothstep(4.0, 30.0, d));
	ALBEDO = base + vec3(0.7, 0.95, 1.0) * glint * (1.0 - smoothstep(5.0, 25.0, d)) * 0.8;
}
"""

const BUBBLE_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = vec3(0.7, 0.95, 1.0) * (pow(f, 2.0) * 0.8 + 0.06);
}
"""

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var bubble_mat: ShaderMaterial
var bubble_mesh: SphereMesh


func _ready() -> void:
	rng.seed = 42
	noise.seed = 3
	noise.frequency = 1.4
	_environment()
	_sand()
	_reef()
	_rays()
	_surface()
	bubble_mat = _shader_mat(BUBBLE_SHADER)
	bubble_mesh = SphereMesh.new()
	bubble_mesh.radius = 0.012
	bubble_mesh.height = 0.024
	bubble_mesh.radial_segments = 8
	bubble_mesh.rings = 4
	for vent: Vector3 in [Vector3(-2.6, 0.05, -3.4), Vector3(3.8, 0.05, -2.2), Vector3(1.5, 0.05, 4.5)]:
		var b := make_bubbles(40, 7.0)
		b.position = vent
		add_child(b)


func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _environment() -> void:
	var sky := Sky.new()
	sky.sky_material = _shader_mat(SKY_SHADER)
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.6, 0.7)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = FOG.linear_to_srgb()
	env.fog_light_energy = 1.0
	env.fog_density = 0.075
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-75, 20, 0)
	sun.light_color = Color(0.75, 0.95, 1.0)
	sun.light_energy = 1.0
	add_child(sun)


func _sand() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	pm.subdivide_width = 70
	pm.subdivide_depth = 70
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = _shader_mat(SAND_SHADER)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func sand_height(x: float, z: float) -> float:
	## Same dunes as the sand shader, so things sit on the floor.
	var d := Vector2(x, z).length()
	return (sin(x * 0.35 + 1.0) * cos(z * 0.28) * 0.35 + sin(x * 1.3 + z * 0.9) * 0.04) \
			* smoothstep(2.0, 6.0, d) - 0.02


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, sand_height(x, z), z)


func _ring(rmin: float, rmax: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf_range(rmin * rmin, rmax * rmax))
	return _ground(cos(a) * r, sin(a) * r)


# ---------------------------------------------------------------- static reef (one mesh)

func _reef() -> void:
	var g := Geo.new()
	for i in 16:
		_rock(g, _ring(4.0, 16.0), rng.randf_range(0.5, 1.6))
	for i in 10:
		_rock(g, _ring(2.2, 6.0), rng.randf_range(0.2, 0.5))
	var coral_cols := [Color(1.0, 0.45, 0.6), Color(0.85, 0.45, 1.0), Color(1.0, 0.6, 0.3), Color(1.0, 0.8, 0.35),
			Color(0.5, 0.75, 1.0)]
	for i in 26:
		_branch_coral(g, _ring(1.8, 8.0), Geo.lin(coral_cols[rng.randi() % coral_cols.size()]))
	for i in 10:
		_brain_coral(g, _ring(1.8, 8.0))
	for i in 12:
		_anemone(g, _ring(1.6, 7.0))
	for i in 14:
		_tubes(g, _ring(2.0, 9.0))
	for i in 22:
		_starfish(g, _ring(1.0, 7.0))
	for i in 60:
		_seagrass(g, _ring(1.5, 12.0))
	for cl in 9:
		var c := _ring(7.0, 13.0)
		for k in rng.randi_range(4, 8):
			var p := c + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			_kelp(g, _ground(p.x, p.z), rng.randf_range(3.0, 6.5))
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit()
	mi.material_override = _shader_mat(REEF_SHADER)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _rock(g: Geo, at: Vector3, size: float) -> void:
	var arr := Geo.sphere(14, 8)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var off := Vector3(rng.randf() * 50, rng.randf() * 50, 0)
	for i in vs.size():
		var p := vs[i]
		vs[i] = p * (1.0 + noise.get_noise_3dv(p * 2.0 + off) * 0.45)
	arr[Mesh.ARRAY_VERTEX] = vs
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 1.3, size * 0.8, size)),
			at + Vector3(0, size * 0.15, 0))
	var base := Geo.lin(Color(0.38, 0.33, 0.45))
	var moss := Geo.lin(Color(0.3, 0.5, 0.3))
	g.add_arrays(arr, xf, func(lp: Vector3, wp: Vector3, wn: Vector3) -> Color:
		return base.lerp(moss, smoothstep(0.5, 0.9, wn.y)) * (0.8 + 0.4 * noise.get_noise_3dv(wp * 3.0)))


func _branch_coral(g: Geo, at: Vector3, col: Color) -> void:
	var tip := col.lerp(Color(1, 1, 1), 0.35)
	_branch(g, Transform3D(Basis(), at), 0.045, 0.28 * rng.randf_range(0.8, 1.3), 0, col, tip)


func _branch(g: Geo, xf: Transform3D, r: float, ln: float, depth: int, col: Color, tip: Color) -> void:
	var seg := xf * Transform3D(Basis(), Vector3(0, ln * 0.5, 0))
	var last := depth >= 3
	g.add_arrays(Geo.cyl(r * 0.75, r, ln, 6, last), seg, tip if last else col, 0.015 * depth)
	if last:
		return
	var end := xf * Transform3D(Basis(), Vector3(0, ln, 0))
	var kids := rng.randi_range(2, 3)
	for k in kids:
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.35, 0.8))
		_branch(g, end * Transform3D(b, Vector3.ZERO), r * 0.75, ln * rng.randf_range(0.7, 0.9), depth + 1, col, tip)


func _brain_coral(g: Geo, at: Vector3) -> void:
	var s := rng.randf_range(0.2, 0.45)
	var a := Geo.lin(Color(0.95, 0.7, 0.45))
	var b := Geo.lin(Color(0.7, 0.85, 0.45)) if rng.randf() < 0.5 else Geo.lin(Color(0.95, 0.55, 0.6))
	g.add_arrays(Geo.sphere(14, 8), Transform3D(Basis.from_scale(Vector3(s * 2.2, s * 1.2, s * 2.2)), at),
			func(lp: Vector3, wp: Vector3, wn: Vector3) -> Color:
				return a.lerp(b, 0.5 + 0.5 * sin(lp.x * 30.0 + sin(lp.z * 25.0) * 3.0)))


func _anemone(g: Geo, at: Vector3) -> void:
	var col := Geo.lin([Color(0.7, 0.45, 1.0), Color(1.0, 0.5, 0.7), Color(0.4, 0.9, 0.7)][rng.randi() % 3])
	var tip := Geo.lin(Color(1.0, 0.9, 0.95))
	g.add_arrays(Geo.cyl(0.12, 0.1, 0.12, 8), Transform3D(Basis(), at + Vector3(0, 0.06, 0)),
			Geo.lin(Color(0.6, 0.3, 0.4)))
	for k in 18:
		var a := rng.randf() * TAU
		var rr := rng.randf() * 0.1
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.0, 0.6))
		var p := at + Vector3(cos(a) * rr, 0.12, sin(a) * rr)
		var h := rng.randf_range(0.15, 0.25)
		g.add_arrays(Geo.cyl(0.006, 0.012, h, 5), Transform3D(b, p) * Transform3D(Basis(), Vector3(0, h * 0.5, 0)),
				func(lp: Vector3, wp: Vector3, wn: Vector3) -> Color: return col.lerp(tip, clampf(lp.y / h + 0.5, 0, 1)),
				func(lp: Vector3, wp: Vector3, wn: Vector3) -> float: return clampf(wp.y - at.y - 0.12, 0, 1) * 0.35)


func _tubes(g: Geo, at: Vector3) -> void:
	var col := Geo.lin([Color(1.0, 0.55, 0.25), Color(0.65, 0.4, 0.9), Color(0.95, 0.85, 0.4)][rng.randi() % 3])
	for k in rng.randi_range(2, 5):
		var h := rng.randf_range(0.2, 0.6)
		var r := rng.randf_range(0.03, 0.06)
		var b := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, 0.3))
		var p := at + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		g.add_arrays(Geo.cyl(r, r * 0.8, h, 8, false), Transform3D(b, p) * Transform3D(Basis(), Vector3(0, h * 0.5, 0)),
				col, 0.01)


func _starfish(g: Geo, at: Vector3) -> void:
	var col := Geo.lin([Color(1.0, 0.45, 0.4), Color(1.0, 0.65, 0.3), Color(0.8, 0.4, 0.9)][rng.randi() % 3])
	var rot := rng.randf() * TAU
	var s := rng.randf_range(0.06, 0.11)
	var c := g.vtx(at + Vector3(0, 0.025, 0), Vector3.UP, col)
	var pts: Array[int] = []
	for k in 10:
		var a := rot + TAU * k / 10.0
		var r := s if k % 2 == 0 else s * 0.4
		pts.append(g.vtx(at + Vector3(cos(a) * r, 0.008, sin(a) * r), Vector3.UP, col))
	for k in 10:
		g.tri(c, pts[k], pts[(k + 1) % 10])


func _seagrass(g: Geo, at: Vector3) -> void:
	var col := Geo.lin(Color(0.35, 0.6, 0.3))
	var top := Geo.lin(Color(0.6, 0.8, 0.4))
	for k in 7:
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.2, 0.5)
		var p := at + Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.15
		var side := Vector3(cos(a + 1.6), 0, sin(a + 1.6)) * 0.012
		var nrm := Vector3(cos(a), 0, sin(a))
		var lean := Vector3(cos(a), 0, sin(a)) * h * 0.3
		var i0 := g.vtx(p - side, nrm, col, 0.0)
		var i1 := g.vtx(p + side, nrm, col, 0.0)
		var i2 := g.vtx(p + lean + Vector3(0, h, 0), nrm, top, h * 0.4)
		g.tri(i0, i1, i2)


func _kelp(g: Geo, at: Vector3, h: float) -> void:
	var col := Geo.lin(Color(0.45, 0.5, 0.18))
	var top := Geo.lin(Color(0.65, 0.7, 0.25))
	var segs := 14
	var twist := rng.randf() * TAU
	var prev_a := -1
	var prev_b := -1
	for s in segs + 1:
		var t := float(s) / segs
		var y := t * h
		var ang := twist + t * 2.5
		var w := 0.09 * (1.0 - 0.6 * t) + 0.02
		var side := Vector3(cos(ang), 0, sin(ang)) * w
		var nrm := Vector3(-sin(ang), 0, cos(ang))
		var c := col.lerp(top, t)
		var sway := t * t * 0.45
		var a := g.vtx(at + Vector3(0, y, 0) - side, nrm, c, sway)
		var b := g.vtx(at + Vector3(0, y, 0) + side, nrm, c, sway)
		if prev_a >= 0:
			g.quad(prev_a, prev_b, b, a)
		prev_a = a
		prev_b = b
		if s > 1 and s % 2 == 0:
			# a little gas bladder + leaf
			var lp := at + Vector3(0, y, 0) + side * 1.4
			g.add_arrays(Geo.sphere(6, 4), Transform3D(Basis.from_scale(Vector3.ONE * 0.05), lp), top, sway)


# ---------------------------------------------------------------- light, surface, particles

func _rays() -> void:
	for i in 8:
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.3, 0.6)
		cm.bottom_radius = cm.top_radius * 2.2
		cm.height = 11.0
		cm.radial_segments = 12
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var m := _shader_mat(RAY_SHADER)
		m.set_shader_parameter("seed", float(i))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p := _ring(1.8, 10.0)
		mi.position = Vector3(p.x, 4.6, p.z)
		mi.rotation = Vector3(deg_to_rad(12), deg_to_rad(20), 0)
		add_child(mi)


func _surface() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = 9.5
	mi.material_override = _shader_mat(SURFACE_SHADER)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func make_bubbles(amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.mesh = bubble_mesh
	p.material_override = bubble_mat
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 0.1
	p.damping_max = 0.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func make_snow() -> CPUParticles3D:
	## Drifting "marine snow" around the player, which is what makes water feel like water.
	var p := CPUParticles3D.new()
	p.amount = 400
	p.lifetime = 14.0
	p.preprocess = 14.0
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.008)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.75, 0.9, 0.9)
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(6, 3, 6)
	p.direction = Vector3(1, 0, 0.3)
	p.spread = 180.0
	p.initial_velocity_min = 0.01
	p.initial_velocity_max = 0.05
	p.gravity = Vector3(0.0, -0.008, 0.0)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
