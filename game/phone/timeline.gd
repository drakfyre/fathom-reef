extends Node3D
## Evolution timeline: replays saved champions side by side on their own stage, e.g. the best
## spider of generation 1, 60, 120, 180 and the latest, so you can watch what evolution learned.
## The gyms save a champion snapshot at generation 1, every 10th generation and on new records.
## Uses the gym's own body builder and neural network, so a replay behaves like the original run.
## set_view("robots" | "robots_v2", "spider" | "humanoid") picks what to show.

const LANES := 5
const START_X := -3.6

var main
var gym_name := "robots"
var species_name := "spider"
var arena: Node3D
var board: Label3D
var robots: Array = []      # {r, snap, label}
var t := 0.0
var episode := 12.0
var tick := 0
var Robot   # the gym's inner classes, borrowed for building
var placed := false


func _ready() -> void:
	arena = Node3D.new()
	add_child(arena)
	_build_stage()


func _gym() -> Node:
	return get_parent().get_node_or_null(gym_name) if get_parent() else null


func set_view(gname: String, sname: String) -> void:
	gym_name = gname
	species_name = sname
	_respawn()


func _place() -> bool:
	## Stand to the right of the new-rules gym, lined up with both gyms.
	var g := get_parent().get_node_or_null("robots") if get_parent() else null
	if g == null or g.get("arena") == null:
		return false
	global_transform = Transform3D.IDENTITY
	arena.global_transform = (g.arena.global_transform as Transform3D).translated_local(Vector3(20.0, 0, 0))
	return true


func _build_stage() -> void:
	var sb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9.0, 0.2, 7.0)
	sb.mesh = bm
	sb.position = Vector3(0, -0.1, -0.2)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 g = abs(fract(lp.xz * 2.0) - 0.5);
	float line = smoothstep(0.46, 0.49, max(g.x, g.y));
	float edge = smoothstep(4.35, 4.48, abs(lp.x)) + smoothstep(3.35, 3.48, abs(lp.z));
	ALBEDO = vec3(0.07, 0.06, 0.12);
	ROUGHNESS = 0.6;
	EMISSION = vec3(0.45, 0.3, 0.7) * line * 0.5 + vec3(1.0, 0.8, 0.4) * edge * 0.9;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	sb.material_override = m
	arena.add_child(sb)
	# the floor the robots stand on (same physics as the gyms)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	body.position = sb.position
	arena.add_child(body)
	board = Label3D.new()
	board.font_size = 64
	board.pixel_size = 0.004
	board.outline_size = 12
	board.modulate = Color(1.0, 0.92, 0.75)
	board.outline_modulate = Color(0.08, 0.05, 0.12)
	board.shaded = false
	board.position = Vector3(0, 3.2, -4.0)
	arena.add_child(board)


func _snapshots(gym: Node) -> Array:
	var s = gym.species.get(species_name)
	if s == null or s.timeline.is_empty():
		return []
	var tl: Array = s.timeline
	if tl.size() <= LANES:
		return tl.duplicate()
	var pick: Array = []
	for k in LANES:
		pick.append(tl[int(round(float(k) * (tl.size() - 1) / (LANES - 1)))])
	return pick


func _clear() -> void:
	for e in robots:
		e.r.root.queue_free()
		e.label.queue_free()
	robots.clear()


func _respawn() -> void:
	_clear()
	t = 0.0
	var gym := _gym()
	if gym == null or gym.species.is_empty():
		return
	var s = gym.species.get(species_name)
	if s == null:
		return
	episode = s.episode
	if Robot == null:
		Robot = gym.get_script().get_script_constant_map()["Robot"]
	var snaps := _snapshots(gym)
	var rules := "new rules" if gym.rules == 2 else "classic rules"
	if snaps.is_empty():
		board.text = "EVOLUTION TIMELINE  -  %s, %s\nno champions saved yet: the first one is saved after generation 1" % [
				species_name.capitalize(), rules]
		return
	board.text = "EVOLUTION TIMELINE  -  %s, %s\nchampions from generation %d to %d, side by side  ->" % [
			species_name.capitalize(), rules, int(snaps[0].gen), int(snaps[-1].gen)]
	var gap := 1.25 if species_name == "humanoid" else 1.1
	for k in snaps.size():
		var snap: Dictionary = snaps[k]
		var g := PackedFloat32Array(snap.g)
		if g.size() != gym._gsize(s):
			continue
		var r = Robot.new()
		r.root = Node3D.new()
		arena.add_child(r.root)
		r.lane_z = 2.5 - k * gap
		r.root.position = Vector3(START_X, 0.0, r.lane_z)
		var col := Color(0.55, 0.6, 0.7).lerp(Color(1.0, 0.8, 0.3), float(k) / maxf(snaps.size() - 1, 1))
		if species_name == "spider":
			gym._make_spider(r, col)
		else:
			gym._make_humanoid(r, col)
		r.start = arena.global_transform.affine_inverse() * r.trunk.global_position
		r.genome = g
		var label := Label3D.new()
		label.font_size = 48
		label.pixel_size = 0.0065
		label.outline_size = 10
		label.shaded = false
		label.modulate = col.lightened(0.3)
		label.outline_modulate = Color(0.05, 0.05, 0.1)
		label.position = Vector3(START_X - 1.3, 0.6, r.lane_z)
		arena.add_child(label)
		robots.append({"r": r, "snap": snap, "label": label})


func _physics_process(dt: float) -> void:
	if not placed:
		placed = _place()
		if placed:
			_respawn()
		return
	var gym := _gym()
	if gym == null:
		return
	var s = gym.species.get(species_name)
	if s == null:
		return
	tick += 1
	t += dt
	var inv := arena.global_transform.affine_inverse()
	for e in robots:
		var r = e.r
		if not is_instance_valid(r.trunk):
			continue
		r.phase += dt * TAU * s.clock_hz
		var lp: Vector3 = inv * r.trunk.global_position
		var up: float = (arena.global_basis.inverse() * r.trunk.global_basis.y).y
		if r.alive and (lp.y < s.fall_h or up < 0.25):
			r.alive = false
		if r.alive and tick % 3 == 0:
			var out: PackedFloat32Array = gym._forward(s, r.genome, gym._sense(s, r))
			for k in r.joints.size():
				var jj = r.joints[k]
				jj.target = lerpf(jj.lo, jj.hi, out[k] * 0.5 + 0.5)
		for jj in r.joints:
			var goal: float = jj.target if r.alive else 0.0
			var vel: float = clampf((goal - jj.angle()) * 10.0, -7.0, 7.0) * gym.ANGLE_SIGN
			jj.j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, vel)
		if tick % 10 == 0:
			e.label.text = "gen %d\n%.2f m%s" % [int(e.snap.gen), lp.x - r.start.x, "" if r.alive else "  (fell)"]
	if t >= episode or (robots.is_empty() and t >= 3.0):
		_respawn()   # loop, and pick up any new champions
