extends SceneTree
## Desktop check of a live script before it goes to the headset:
## godot-gpu --xr-mode off --path game -s ../tools/live_test.gd -- <script.gd> <name> <shots dir> [scenario]
var main: Node
var args := OS.get_cmdline_user_args()

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_go.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(nm: String, pos: Vector3, at: Vector3) -> void:
	main.camera.global_position = pos
	main.camera.look_at(at)
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[2])
	root.get_viewport().get_texture().get_image().save_png(args[2].path_join(nm + ".png"))
	print("shot ", nm)

func _go() -> void:
	main.desktop_spin = false
	main.help_t = 0.0
	await frames(3)
	var r: Dictionary = main.link._run(args[1], FileAccess.get_file_as_string(args[0]), false)
	print("run: ", r)
	if not r.ok:
		quit(1)
		return
	var node: Node3D = main.link.live_root.get_node(args[1])
	var sc := load(args[0].get_basename() + "_test.gd") if FileAccess.file_exists(args[0].get_basename() + "_test.gd") else null
	if sc:
		await sc.new().run(self, main, node)
	quit()
