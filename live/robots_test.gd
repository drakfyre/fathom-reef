extends RefCounted
## Save/resume check: run until both species finish a round, rebuild the gym, compare.
func run(t, main, gym) -> void:
	while gym.species["humanoid"].gen < 1 or gym.species["spider"].gen < 1:
		await t.process_frame
	var before := {}
	for s in gym.species.values():
		before[s.name] = [s.gen, s.genomes[1].duplicate(), s.history.size(), s.scores.size()]
	var code := FileAccess.get_file_as_string(t.args[0])
	main.link._run("robots", code, false)
	await t.frames(3)
	var g2 = main.link.live_root.get_node("robots")
	var ok := true
	for s in g2.species.values():
		var b: Array = before[s.name]
		var same: bool = s.gen == b[0] and s.genomes[1] == b[1] and s.history.size() == b[2] and s.scores.size() == b[3] \
				and s.robots[1].genome == b[1]
		print("%s resumed gen %d (was %d), weights identical: %s, history %d, scores %d" % [s.name, s.gen, b[0], s.genomes[1] == b[1], s.history.size(), s.scores.size()])
		ok = ok and same
	print("RESUME ", "PASS" if ok else "FAIL")
