extends RefCounted
func run(t, main, book) -> void:
	await t.frames(60)
	var eye := Vector3(0, 1.6, 0)
	var B: Transform3D = book.global_transform
	await t.shot("book_open", eye, B.origin)
	var R = main.hands[1]
	R.ok = true
	R.trigger = 0.0
	R.tip = B * Vector3(0.15, 0.01, 0.0)
	await t.frames(2)
	R.trigger = 1.0
	await t.frames(2)
	for k in 30:
		R.tip = B * Vector3(lerpf(0.15, -0.05, k / 29.0), 0.03 + 0.05 * sin(PI * k / 29.0), 0.0)
		await t.frames(1)
	await t.shot("book_bend", eye + Vector3(0.25, -0.05, 0.05), B.origin)
	for k in 10:
		R.tip = B * Vector3(lerpf(-0.05, -0.15, k / 9.0), 0.02, 0.0)
		await t.frames(1)
	R.trigger = 0.0
	await t.frames(40)
	print("spread ", book.spread)
	await t.shot("book_spread1", eye, B.origin)
	# tap through three more spreads
	for n in 3:
		R.tip = B * Vector3(0.12, 0.01, 0.02)
		R.trigger = 0.0
		await t.frames(2)
		R.trigger = 1.0
		await t.frames(3)
		R.trigger = 0.0
		await t.frames(40)
	print("spread ", book.spread)
	await t.shot("book_spread4", B * Vector3(0, 0.33, 0.2), B.origin)
	R.ok = false
