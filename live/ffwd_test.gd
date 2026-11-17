extends RefCounted
func run(t, main, ff) -> void:
	main.link._run("robots", FileAccess.get_file_as_string("../live/robots.gd"), false)
	await t.frames(5)
	var gym = main.link.live_root.get_node("robots")
	var fishmove := func(secs: float) -> float:
		var a: Array = []
		for s in main.fish.species: a.append_array(Array(s.pos))
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < secs * 1000.0:
			await t.process_frame
		var b: Array = []
		for s in main.fish.species: b.append_array(Array(s.pos))
		var d := 0.0
		for i in a.size(): d += a[i].distance_to(b[i])
		return d / a.size() / secs
	for lvl in [0, 2]:
		# poke the button like a finger would
		var btn: Node3D = ff.buttons[lvl]
		var R = main.hands[1]
		R.ok = true
		R.tip = btn.global_transform * Vector3(0, 0, 0.005)
		await t.frames(2)
		R.ok = false
		ff.settle = 999.0   # desktop GPU is slower than the headset: no auto step-down in this test
		await t.frames(10)
		var st0: float = gym.species["spider"].t
		var g0: int = gym.species["spider"].gen
		var r0 := Time.get_ticks_msec()
		var fm: float = await fishmove.call(3.0)
		var real := (Time.get_ticks_msec() - r0) / 1000.0
		var sim: float = gym.species["spider"].t - st0 + (gym.species["spider"].gen - g0) * gym.species["spider"].episode
		print("level %dx: time_scale %.0f, ticks %d, physics step %.4f s, robots sim %.2f s in %.2f s real (%.2fx), fish %.2f m/s" % [
				int(ff.SPEEDS[ff.level]), Engine.time_scale, Engine.physics_ticks_per_second,
				t.root.get_physics_process_delta_time() if false else gym.get_physics_process_delta_time(), sim, real, sim / real, fm])
	await t.shot("ffwd_panel", ff.global_transform * Vector3(0, 0.05, 0.35), ff.global_position)
