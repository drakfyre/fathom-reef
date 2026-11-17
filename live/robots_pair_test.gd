extends RefCounted
## Classic + new-rules gyms side by side.
func run(t, main, gym) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://robots_v2.json"))
	main.link._run("robots_v2", FileAccess.get_file_as_string(t.args[0]), false)
	await t.frames(3)
	var v2 = main.link.live_root.get_node("robots_v2")
	var off: Vector3 = gym.arena.global_transform.affine_inverse() * v2.arena.global_position
	print("v2 rules %d, classic rules %d, v2 offset in classic arena space %s" % [v2.rules, gym.rules, off])
	print("v2 starts at gen ", v2.species["spider"].gen, "/", v2.species["humanoid"].gen, " classic at ", gym.species["spider"].gen)
	while v2.species["humanoid"].gen < 1:
		await t.process_frame
	for s in v2.species.values():
		print("v2 ", s.name, " history ", s.history)
	var A: Transform3D = gym.arena.global_transform
	await t.shot("pair", A * Vector3(5.0, 4.0, 14.0), A * Vector3(5.0, 0.5, -1.0))
	print("fps ", Engine.get_frames_per_second())
