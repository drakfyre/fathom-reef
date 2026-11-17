extends RefCounted
func run(t, main, gym) -> void:
	await t.frames(5)
	var A: Transform3D = gym.arena.global_transform
	await t.shot("gym_spawn", A * Vector3(-3.0, 1.4, 5.5), A * Vector3(-3.0, 0.3, -1.0))
	var err := {"spider": [0.0, 0], "humanoid": [0.0, 0]}
	for k in 300:
		await t.process_frame
		if k > 60 and k % 10 == 0:
			for s in gym.species.values():
				for r in s.robots:
					if r.alive:
						for jj in r.joints:
							err[s.name][0] += absf(jj.target - jj.angle())
							err[s.name][1] += 1
	for nm in err:
		print("tracking error %s: %.3f rad" % [nm, err[nm][0] / maxf(err[nm][1], 1)])
	for s in gym.species.values():
		var f: Array = []
		for r in s.robots:
			f.append("%.2f%s" % [r.fitness, "" if r.alive else "x"])
		print(s.name, " t=%.1f fitness " % s.t, f)
	await t.shot("gym_run", A * Vector3(-2.0, 1.6, 5.0), A * Vector3(-2.5, 0.4, -1.0))
	await t.shot("gym_humanoids", A * Vector3(-1.0, 1.5, 1.0), A * Vector3(-3.4, 0.9, -3.0))
	await t.shot("gym_spiders", A * Vector3(-2.4, 0.9, 4.4), A * Vector3(-3.4, 0.3, 2.0))
