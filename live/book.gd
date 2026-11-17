extends Node3D
## A book you can flip through with your hands, about how deep neural networks work.
## - Pinch a page with the TRIGGER and drag it across: the page bends and follows your finger.
##   A quick trigger tap on a page also turns it.
## - Or swipe a fingertip across the page, like flicking a real one.
## - Hold GRIP near the book to pick it up and move it.
## Built live over the Fathom Reef link. STAGE = how much of it is switched on (1-3).

const STAGE := 3
const W := 0.2          # page width (m)
const H := 0.26         # page height (m)
const PX := Vector2i(640, 832)
const TILT := 0.6       # radians the book leans toward the reader

var main
var pages: Array[Texture2D] = []   # content pages, P[0] = first right-hand page
var blank: Texture2D
var cover_out: Texture2D
var cover_in: Texture2D
var spread := 0                    # spread s shows P[2s-1] left, P[2s] right
var leaf: MeshInstance3D           # the page being turned
var leaf_mat: ShaderMaterial
var leaf_j := -1                   # which leaf is turning (front P[2j], back P[2j+1])
var leaf_t := 0.0                  # 0 = lying on the right, 1 = lying on the left
var leaf_goal := -1.0              # auto-finish target, -1 = following a finger
var leaf_dir := 1.0
var drag_hand := -1
var drag_start := 0.0
var drag_from := Vector3.ZERO
var left_page: MeshInstance3D
var right_page: MeshInstance3D
var left_mat: ShaderMaterial
var right_mat: ShaderMaterial
var cover: MeshInstance3D
var cover_mat: ShaderMaterial
var open_t := 0.0
var hold_hand := -1
var hold_off := Transform3D()
var prev_trig := [0.0, 0.0]
var prev_grip := [0.0, 0.0]
var prev_tip := [Vector3.ZERO, Vector3.ZERO]
var ready_pages := false
var age := 0.0

const LEAF_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D front_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D back_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float t = 0.0;
uniform float curl = 0.0;
uniform float width = 0.2;
uniform float lift = 0.002;
void vertex() {
	float u = VERTEX.x;
	float th = t * PI;
	float k = curl / width;
	vec2 xy;
	if (abs(k) < 0.001) {
		xy = vec2(cos(th), sin(th)) * u;
	} else {
		xy = vec2(sin(th + k * u) - sin(th), cos(th) - cos(th + k * u)) / k;
	}
	float a = th + k * u;
	VERTEX.x = xy.x;
	VERTEX.y = xy.y + lift;
	NORMAL = vec3(-sin(a), cos(a), 0.0);
}
void fragment() {
	vec3 c = FRONT_FACING ? texture(front_tex, UV).rgb : texture(back_tex, vec2(1.0 - UV.x, UV.y)).rgb;
	ALBEDO = c * 0.6;
	ROUGHNESS = 0.9;
	EMISSION = c * 0.55;
}
"""

const FLAT_SHADER := """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	ALBEDO = c * 0.6;
	ROUGHNESS = 0.9;
	EMISSION = c * 0.55;
}
"""

# ---------------------------------------------------------------- the words

const INK := Color(0.12, 0.13, 0.22)
const PINK := Color(0.85, 0.3, 0.55)
const BLUE := Color(0.2, 0.45, 0.8)
const TEAL := Color(0.1, 0.55, 0.55)
const PAPER := Color(0.98, 0.95, 0.88)

var CONTENT := [
	{"t": "Before we start", "fig": "fishnet", "b":
		"A deep neural network is a big pile of very simple maths that learns from examples instead of being programmed rule by rule.\n\nNobody writes \"a clownfish has white stripes\" into it. You show it thousands of labelled pictures and it slowly adjusts itself until it gets them right.\n\nFlip on for the whole idea, one step per page."},
	{"t": "1. The neuron", "fig": "neuron", "b":
		"The building block is an artificial neuron. It takes some numbers in, multiplies each one by a weight (how much it cares about that input), adds them up with a bias, and passes the total through an activation function.\n\nThat's all one neuron does: weigh, add, squash."},
	{"t": "2. Activation", "fig": "activations", "b":
		"The activation function bends the straight-line sum. Without it, stacking neurons would still only draw straight lines.\n\nReLU (pink) keeps positive values and turns negatives into 0. Sigmoid (blue) squashes anything into 0 to 1, like a soft yes/no.\n\nThose little bends are what let networks learn curvy, complicated things."},
	{"t": "3. Layers", "fig": "layers", "b":
		"Neurons are arranged in layers. Every neuron in one layer feeds every neuron in the next.\n\nThe input layer holds the raw data (pixels, sounds, sensor readings). The output layer gives the answer. The hidden layers in between are where the learning lives.\n\n\"Deep\" just means many hidden layers."},
	{"t": "4. The forward pass", "fig": "forward", "b":
		"Running a network is called the forward pass: numbers flow from input to output, layer by layer.\n\nIn a trained picture network, early layers end up spotting edges and colours, middle layers combine those into shapes like fins and eyes, and late layers combine those into \"clownfish\". Nobody told it to do that; it is what training discovered."},
	{"t": "5. Loss: how wrong?", "fig": "loss", "b":
		"To learn, the network needs a score for how wrong it is. That score is the loss.\n\nIf the picture is a clownfish and the network says \"clownfish: 30%\", the loss is high. If it says 97%, the loss is low.\n\nTraining is nothing more than making this number smaller, over and over."},
	{"t": "6. Gradient descent", "fig": "descent", "b":
		"Picture the loss as a hilly landscape, where every weight is a direction you can walk. We want the lowest valley.\n\nThe gradient tells us which way is downhill from where we stand. We take a small step that way (the size of the step is the learning rate), then look again.\n\nToo big a step and you bounce around; too small and it takes forever."},
	{"t": "7. Backpropagation", "fig": "backprop", "b":
		"With millions of weights, how do we find downhill for each one? Backpropagation.\n\nStarting at the output error, it works backwards through the layers using the chain rule from calculus, handing each weight its share of the blame: \"you pushed the answer this much in the wrong direction\".\n\nThen every weight gets nudged a tiny bit the other way."},
	{"t": "8. The training loop", "fig": "loop", "b":
		"Put together, training is a loop:\n  guess (forward pass)\n  measure the error (loss)\n  share the blame (backprop)\n  nudge the weights (gradient step)\n\nRepeat for a small batch of examples, then the next batch. One trip through all the data is an epoch. Big models do this billions of times."},
	{"t": "9. Learning vs memorising", "fig": "overfit", "b":
		"A network can cheat by memorising its training examples instead of learning the real pattern. That is overfitting: perfect on old data, bad on anything new.\n\nSo we keep some examples hidden (a validation set) and check on those. More varied data, smaller steps and tricks like dropout keep it honest."},
	{"t": "10. Different shapes", "fig": "kinds", "b":
		"The same ideas build different machines:\n\nConvolutional nets slide small filters over images.\n\nTransformers use attention to let every word (or patch) look at every other one. That's what language models like me are built from.\n\nReinforcement learning nets learn by trial, error and reward."},
	{"t": "11. Learning to walk", "fig": "rl", "b":
		"A robot has no labelled answers, only a reward: \"you moved forward without falling\".\n\nIts network reads sensors (joint angles, tilt, speed) and outputs motor commands. Many attempts are scored; the better networks are kept and varied, and the next generation tries again.\n\nThat's what's coming to this reef next."},
	{"t": "12. What it isn't", "fig": "numbers", "b":
		"A neural network isn't a brain and doesn't think like one. It's numbers (lots of them) shaped by examples, which makes it powerful and also fallible: it learns the data's mistakes too, and it can be confidently wrong.\n\nIt is a tool. Knowing how it works is the best way to judge when to trust it.\n\nThanks for reading!  - Claude"},
]


class PageDraw extends Control:
	var page: Dictionary = {}
	var number := 0
	var kind := "page"   # page / cover / plain
	var font: Font

	func _draw() -> void:
		var sz := size
		if kind == "cover":
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.25, 0.5))
			draw_rect(Rect2(Vector2(24, 24), sz - Vector2(48, 48)), Color(1, 0.8, 0.9), false, 4.0)
			_c("How Deep", 150, 62, Color(1, 0.92, 0.96))
			_c("Neural Networks", 225, 62, Color(1, 0.92, 0.96))
			_c("Work", 300, 62, Color(1, 0.92, 0.96))
			_c("a little field guide", 380, 30, Color(1, 0.8, 0.9))
			_net(Rect2(110, 430, 420, 230), [3, 5, 5, 2], Color(1, 0.85, 0.95), 2.0)
			_c("written live in Fathom Reef", 730, 24, Color(1, 0.8, 0.9))
			_c("by Claude", 765, 24, Color(1, 0.8, 0.9))
			return
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.98, 0.95, 0.88))
		if kind == "plain":
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.62, 0.32, 0.58))
			return
		draw_rect(Rect2(Vector2(0, 0), Vector2(sz.x, 6)), Color(0.85, 0.3, 0.55, 0.5))
		if page.is_empty():
			_c("page %d" % number, 420, 40, Color(0.12, 0.13, 0.22))
			return
		draw_string(font, Vector2(48, 82), page.t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.85, 0.3, 0.55))
		draw_multiline_string(font, Vector2(48, 132), page.b, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 96, 22, 16,
				Color(0.12, 0.13, 0.22))
		_figure(page.fig, Rect2(48, 520, sz.x - 96, 250))
		_c(str(number), sz.y - 26, 20, Color(0.5, 0.5, 0.6))

	func _c(s: String, y: float, fs: int, col: Color) -> void:
		draw_string(font, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, col)

	func _t(s: String, p: Vector2, fs: int, col: Color, center := true) -> void:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p - Vector2(w * 0.5 if center else 0.0, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _arrow(a: Vector2, b: Vector2, col: Color, w := 3.0) -> void:
		draw_line(a, b, col, w, true)
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([b, b - d * 14 + n * 7, b - d * 14 - n * 7]), col)

	func _net(r: Rect2, layers: Array, col: Color, lw := 1.5, back := false) -> Array:
		var pos: Array = []
		for li in layers.size():
			var col_pts: Array[Vector2] = []
			var n: int = layers[li]
			var x := r.position.x + r.size.x * li / maxf(layers.size() - 1, 1)
			for k in n:
				col_pts.append(Vector2(x, r.position.y + r.size.y * (k + 0.5) / n))
			pos.append(col_pts)
		for li in layers.size() - 1:
			for a: Vector2 in pos[li]:
				for b: Vector2 in pos[li + 1]:
					draw_line(a, b, Color(col, 0.45), lw, true)
		for li in pos.size():
			for p: Vector2 in pos[li]:
				draw_circle(p, 13, col)
				draw_circle(p, 9, Color(0.98, 0.95, 0.88))
		return pos

	func _figure(f: String, r: Rect2) -> void:
		var ink := Color(0.12, 0.13, 0.22)
		var pink := Color(0.85, 0.3, 0.55)
		var blue := Color(0.2, 0.45, 0.8)
		var teal := Color(0.1, 0.55, 0.55)
		var o := r.position
		var s := r.size
		match f:
			"fishnet":
				_net(Rect2(o + Vector2(150, 10), Vector2(260, 220)), [4, 6, 6, 3], blue)
				_t("examples in", o + Vector2(70, 120), 20, ink)
				_t("answers out", o + Vector2(490, 120), 20, ink)
			"neuron":
				var c := o + Vector2(s.x * 0.55, s.y * 0.5)
				for k in 3:
					var p := o + Vector2(40, 40 + k * 85)
					draw_circle(p, 22, teal)
					_t("x%d" % (k + 1), p, 20, Color.WHITE)
					_arrow(p + Vector2(24, 0), c + (p - c).normalized() * 50, ink, 2.0)
					_t("w%d" % (k + 1), p.lerp(c, 0.45) + Vector2(0, -16), 18, pink)
				draw_circle(c, 48, pink)
				_t("sum", c + Vector2(0, -10), 22, Color.WHITE)
				_t("+ bias", c + Vector2(0, 16), 16, Color.WHITE)
				var out := Vector2(o.x + s.x - 30, c.y)
				_arrow(c + Vector2(50, 0), out - Vector2(26, 0), ink, 2.0)
				_t("squash", c.lerp(out, 0.5) + Vector2(0, -18), 18, ink)
				draw_circle(out, 24, blue)
				_t("out", out, 18, Color.WHITE)
			"activations":
				var ax := o + Vector2(s.x * 0.5, s.y * 0.85)
				draw_line(Vector2(o.x, ax.y), Vector2(o.x + s.x, ax.y), ink, 2)
				draw_line(Vector2(ax.x, o.y), Vector2(ax.x, o.y + s.y), ink, 2)
				var relu := PackedVector2Array()
				var sig := PackedVector2Array()
				for i in 61:
					var x := lerpf(-3.0, 3.0, i / 60.0)
					var px := ax.x + x * s.x / 6.0
					relu.append(Vector2(px, ax.y - maxf(x, 0.0) * 55.0))
					sig.append(Vector2(px, ax.y - 180.0 / (1.0 + exp(-x * 1.6))))
				draw_polyline(relu, pink, 5, true)
				draw_polyline(sig, blue, 5, true)
				_t("ReLU", o + Vector2(s.x - 60, 20), 22, pink)
				_t("sigmoid", o + Vector2(70, 50), 22, blue)
			"layers":
				_net(Rect2(o + Vector2(30, 0), Vector2(s.x - 60, 210)), [3, 5, 5, 2], blue)
				_t("input", o + Vector2(30, 232), 18, ink)
				_t("hidden", o + Vector2(30 + (s.x - 60) / 3.0, 232), 18, ink)
				_t("hidden", o + Vector2(30 + (s.x - 60) * 2 / 3.0, 232), 18, ink)
				_t("output", o + Vector2(s.x - 30, 232), 18, ink)
			"forward":
				var labels := ["pixels", "edges", "shapes", "fins & eyes", "clownfish!"]
				for k in labels.size():
					var p := o + Vector2(10 + k * (s.x - 20) / 4.0, s.y * 0.5 + (k % 2) * 40 - 20)
					var c := pink if k == labels.size() - 1 else teal
					draw_rect(Rect2(p - Vector2(50, 22), Vector2(100, 44)), c)
					_t(labels[k], p, 15, Color.WHITE)
					if k > 0:
						var q := o + Vector2(10 + (k - 1) * (s.x - 20) / 4.0, s.y * 0.5 + ((k - 1) % 2) * 40 - 20)
						_arrow(q + Vector2(50, 0), p - Vector2(52, 0), ink, 2.0)
				_arrow(o + Vector2(20, s.y - 20), o + Vector2(s.x - 20, s.y - 20), blue, 3)
				_t("forward pass", o + Vector2(s.x * 0.5, s.y - 44), 18, blue)
			"loss":
				var pts := PackedVector2Array()
				for i in 50:
					var x := i / 49.0
					var y := 0.08 + 0.9 * exp(-x * 4.0) + sin(i * 1.7) * 0.03 * (1.0 - x)
					pts.append(o + Vector2(20 + x * (s.x - 40), s.y - 30 - y * (s.y - 60)))
				draw_line(o + Vector2(20, s.y - 30), o + Vector2(s.x - 20, s.y - 30), ink, 2)
				draw_line(o + Vector2(20, 10), o + Vector2(20, s.y - 30), ink, 2)
				draw_polyline(pts, pink, 5, true)
				_t("loss", o + Vector2(60, 20), 20, pink)
				_t("training time", o + Vector2(s.x * 0.5, s.y - 8), 18, ink)
			"descent":
				var pts := PackedVector2Array()
				for i in 80:
					var x := i / 79.0
					var y := pow(x - 0.62, 2.0) * 2.4 + sin(x * 14.0) * 0.04
					pts.append(o + Vector2(10 + x * (s.x - 20), 30 + y * (s.y - 40)))
				draw_polyline(pts, teal, 5, true)
				var steps := [0.05, 0.2, 0.33, 0.44, 0.52, 0.57, 0.6]
				for k in steps.size():
					var x: float = steps[k]
					var y := pow(x - 0.62, 2.0) * 2.4 + sin(x * 14.0) * 0.04
					var p := o + Vector2(10 + x * (s.x - 20), 30 + y * (s.y - 40) - 14)
					draw_circle(p, 10, Color(pink, 0.35 + 0.65 * k / 6.0))
				_t("lowest loss", o + Vector2(10 + 0.62 * (s.x - 20), s.y + 5), 18, ink)
			"backprop":
				var pos: Array = _net(Rect2(o + Vector2(30, 10), Vector2(s.x - 60, 190)), [3, 4, 4, 2], blue)
				for li in range(pos.size() - 1, 0, -1):
					var a: Vector2 = pos[li][0]
					var b: Vector2 = pos[li - 1][0]
					_arrow(Vector2(a.x - 15, o.y + 225), Vector2(b.x + 15, o.y + 225), pink, 4)
				_t("error flows backwards: blame for every weight", o + Vector2(s.x * 0.5, s.y - 4), 18, pink)
			"loop":
				var c := o + s * 0.5
				var names := ["guess", "measure", "blame", "nudge"]
				for k in 4:
					var a := -PI / 2 + k * TAU / 4
					var p := c + Vector2(cos(a) * 190, sin(a) * 95)
					var a2 := -PI / 2 + (k + 1) * TAU / 4
					var p2 := c + Vector2(cos(a2) * 190, sin(a2) * 95)
					_arrow(p.lerp(p2, 0.25), p.lerp(p2, 0.75), ink, 2)
					draw_rect(Rect2(p - Vector2(58, 20), Vector2(116, 40)), [teal, pink, blue, teal][k])
					_t(names[k], p, 20, Color.WHITE)
			"overfit":
				var data := [Vector2(0.05, 0.7), Vector2(0.15, 0.55), Vector2(0.27, 0.5), Vector2(0.38, 0.32),
						Vector2(0.5, 0.35), Vector2(0.62, 0.22), Vector2(0.75, 0.25), Vector2(0.88, 0.12)]
				var good := PackedVector2Array()
				var bad := PackedVector2Array()
				for i in 60:
					var x := i / 59.0
					good.append(o + Vector2(x * s.x, (0.7 - 0.6 * x) * s.y))
					var y := 0.7 - 0.6 * x + sin(x * 40.0) * 0.12
					bad.append(o + Vector2(x * s.x, y * s.y))
				draw_polyline(bad, Color(pink, 0.6), 3, true)
				draw_polyline(good, teal, 5, true)
				for d: Vector2 in data:
					draw_circle(o + d * s, 8, ink)
				_t("learned", o + Vector2(s.x - 70, s.y * 0.05), 20, teal)
				_t("memorised", o + Vector2(90, s.y * 0.98), 20, pink)
			"kinds":
				var w := (s.x - 40) / 3.0
				var titles := ["convolution", "attention", "reinforcement"]
				for k in 3:
					var b := Rect2(o + Vector2(k * (w + 20), 20), Vector2(w, 170))
					draw_rect(b, Color([teal, blue, pink][k], 0.15))
					draw_rect(b, [teal, blue, pink][k], false, 2)
					_t(titles[k], b.position + Vector2(w * 0.5, 200), 17, ink)
				for gx in 4:
					for gy in 4:
						draw_rect(Rect2(o + Vector2(25 + gx * 28, 50 + gy * 28), Vector2(24, 24)),
								Color(teal, 0.25 + 0.6 * float((gx + gy) % 3 == 0)))
				var wp: Array[Vector2] = []
				for k in 5:
					wp.append(o + Vector2(w + 20 + w * 0.5, 45 + k * 30))
				for a in wp:
					for b in wp:
						draw_line(a + Vector2(-30, 0), b + Vector2(30, 0), Color(blue, 0.35), 2)
				for p in wp:
					draw_circle(p + Vector2(-30, 0), 7, blue)
					draw_circle(p + Vector2(30, 0), 7, blue)
				var rc := o + Vector2(2 * (w + 20) + w * 0.5, 105)
				draw_arc(rc, 50, 0.3, TAU - 0.3, 24, pink, 3)
				_arrow(rc + Vector2(cos(-0.3), sin(-0.3)) * 50 + Vector2(-4, -10), rc + Vector2(cos(-0.3), sin(-0.3)) * 50, pink, 3)
				_t("try", rc + Vector2(0, -20), 16, pink)
				_t("reward", rc + Vector2(0, 12), 16, pink)
			"rl":
				var labels := ["sensors", "network", "motors", "world", "reward"]
				var c := o + s * 0.5
				for k in 5:
					var a := -PI / 2 + k * TAU / 5
					var p := c + Vector2(cos(a) * 200, sin(a) * 100)
					var a2 := -PI / 2 + (k + 1) * TAU / 5
					var p2 := c + Vector2(cos(a2) * 200, sin(a2) * 100)
					_arrow(p.lerp(p2, 0.3), p.lerp(p2, 0.7), ink, 2)
					draw_rect(Rect2(p - Vector2(52, 18), Vector2(104, 36)), [teal, blue, teal, ink, pink][k])
					_t(labels[k], p, 17, Color.WHITE)
			"numbers":
				var rng := RandomNumberGenerator.new()
				rng.seed = 5
				for gx in 26:
					for gy in 11:
						var v := rng.randf_range(-1, 1)
						draw_rect(Rect2(o + Vector2(gx * 21, gy * 21), Vector2(18, 18)),
								pink.lerp(blue, v * 0.5 + 0.5) * Color(1, 1, 1, 0.35 + absf(v) * 0.65))
			_:
				pass


# ---------------------------------------------------------------- building

func _ready() -> void:
	var head: Transform3D = main.head_transform() if main else Transform3D(Basis(), Vector3(0, 1.6, 0))
	var f := -head.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var p := head.origin + f * 0.45 + Vector3(0, -0.35, 0)
	global_transform = Transform3D(Basis.looking_at(f, Vector3.UP) * Basis(Vector3.RIGHT, TILT), p)
	# looking_at(f) makes local +Z point at the reader; then the far edge tilts up
	if main and not main.sfx.streams.has("page"):
		main.sfx.streams["page"] = main.sfx._make(0.3, func(t: float, r: float) -> float:
			return r * 0.35 * sin(PI * t / 0.3) * sin(PI * t / 0.3) * (0.6 + 0.4 * sin(t * 90.0)))
	_build_meshes()
	_render_pages()


func _mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _plane(w: float, h: float, cx: float, sub: int) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	pm.subdivide_width = sub
	pm.center_offset = Vector3(cx, 0, 0)
	return pm


func _build_meshes() -> void:
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.55, 0.25, 0.5)
	board.emission_enabled = true
	board.emission = Color(0.15, 0.05, 0.12)
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.95, 0.92, 0.84)
	edge.emission_enabled = true
	edge.emission = Color(0.3, 0.29, 0.26)
	for side: float in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(W + 0.012, 0.006, H + 0.016)
		b.mesh = bm
		b.position = Vector3(side * (W * 0.5 + 0.003), -0.012, 0)
		b.material_override = board
		add_child(b)
		var stack := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(W - 0.004, 0.01, H - 0.004)
		stack.mesh = sm
		stack.position = Vector3(side * W * 0.5, -0.0055, 0)
		stack.material_override = edge
		add_child(stack)
	var spine := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = H + 0.016
	spine.mesh = cm
	spine.rotation.x = PI / 2
	spine.position = Vector3(0, -0.014, 0)
	spine.material_override = board
	add_child(spine)
	left_mat = _mat(FLAT_SHADER)
	right_mat = _mat(FLAT_SHADER)
	left_page = MeshInstance3D.new()
	left_page.mesh = _plane(W, H, -W * 0.5, 1)
	left_page.material_override = left_mat
	left_page.position.y = 0.0005
	add_child(left_page)
	right_page = MeshInstance3D.new()
	right_page.mesh = _plane(W, H, W * 0.5, 1)
	right_page.material_override = right_mat
	right_page.position.y = 0.0005
	add_child(right_page)
	leaf_mat = _mat(LEAF_SHADER)
	leaf_mat.set_shader_parameter("width", W)
	leaf = MeshInstance3D.new()
	leaf.mesh = _plane(W, H, W * 0.5, 28)
	leaf.material_override = leaf_mat
	leaf.visible = false
	leaf.extra_cull_margin = 0.3
	add_child(leaf)
	cover_mat = _mat(LEAF_SHADER)
	cover_mat.set_shader_parameter("width", W + 0.01)
	cover_mat.set_shader_parameter("lift", 0.004)
	cover = MeshInstance3D.new()
	cover.mesh = _plane(W + 0.01, H + 0.016, (W + 0.01) * 0.5, 1)
	cover.material_override = cover_mat
	cover.extra_cull_margin = 0.3
	add_child(cover)


func _render_pages() -> void:
	var vp := SubViewport.new()
	vp.size = PX
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var d := PageDraw.new()
	d.font = ThemeDB.fallback_font
	d.size = Vector2(PX)
	vp.add_child(d)
	var snap := func(kind: String, page: Dictionary, number: int) -> Texture2D:
		d.kind = kind
		d.page = page
		d.number = number
		d.queue_redraw()
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	cover_out = await snap.call("cover", {}, 0)
	cover_in = await snap.call("plain", {}, 0)
	blank = await snap.call("page", {"t": "", "b": "", "fig": ""}, 0)
	var n := CONTENT.size() if STAGE >= 3 else 8
	for i in n:
		pages.append(await snap.call("page", CONTENT[i] if STAGE >= 3 else {}, i + 1))
	vp.queue_free()
	cover_mat.set_shader_parameter("front_tex", cover_out)
	cover_mat.set_shader_parameter("back_tex", cover_in)
	ready_pages = true
	_show()


func _p(i: int) -> Texture2D:
	if i < 0:
		return cover_in
	return pages[i] if i < pages.size() else blank


func _show() -> void:
	if leaf_j >= 0:
		left_mat.set_shader_parameter("tex", _p(2 * leaf_j - 1))
		right_mat.set_shader_parameter("tex", _p(2 * leaf_j + 2))
		leaf_mat.set_shader_parameter("front_tex", _p(2 * leaf_j))
		leaf_mat.set_shader_parameter("back_tex", _p(2 * leaf_j + 1))
	else:
		left_mat.set_shader_parameter("tex", _p(2 * spread - 1))
		right_mat.set_shader_parameter("tex", _p(2 * spread))
	leaf.visible = leaf_j >= 0


func _max_spread() -> int:
	return (pages.size() + 1) / 2


# ---------------------------------------------------------------- turning

func start_turn(dir: float) -> bool:
	if leaf_j >= 0:
		return false
	if dir > 0.0 and spread >= _max_spread():
		return false
	if dir < 0.0 and spread <= 0:
		return false
	leaf_dir = dir
	leaf_j = spread if dir > 0.0 else spread - 1
	leaf_t = 0.0 if dir > 0.0 else 1.0
	leaf_goal = -1.0
	_show()
	if main:
		main.sfx.play("page", global_position, -6.0)
	return true


func finish_turn(goal: float) -> void:
	leaf_goal = goal


func _step_leaf(dt: float, follow: float) -> void:
	if leaf_j < 0:
		return
	if leaf_goal >= 0.0:
		leaf_t = move_toward(leaf_t, leaf_goal, dt * 2.2)
		if is_equal_approx(leaf_t, leaf_goal):
			spread = leaf_j + 1 if leaf_goal > 0.5 else leaf_j
			leaf_j = -1
			leaf_goal = -1.0
			_show()
			return
	elif follow >= 0.0:
		leaf_t = lerpf(leaf_t, follow, clampf(dt * 14.0, 0.0, 1.0))
	leaf_mat.set_shader_parameter("t", leaf_t)
	# the free edge lags behind the spine, which is what makes paper look like paper
	leaf_mat.set_shader_parameter("curl", -leaf_dir * sin(PI * leaf_t) * 1.3)


func _process(dt: float) -> void:
	age += dt
	# the cover swings open once the pages are ready
	if ready_pages and open_t < 1.0:
		open_t = minf(open_t + dt * 0.7, 1.0)
	var e := open_t * open_t * (3.0 - 2.0 * open_t)
	cover_mat.set_shader_parameter("t", e)
	cover_mat.set_shader_parameter("curl", sin(PI * e) * -0.25)
	cover_mat.set_shader_parameter("lift", lerpf(0.004, -0.008, e))
	cover.visible = e < 1.0
	left_page.visible = e > 0.5
	if not ready_pages or main == null:
		_step_leaf(dt, -1.0)
		return
	var follow := -1.0
	var inv := global_transform.affine_inverse()
	for i in 2:
		var h = main.hands[i]
		if not h.ok:
			prev_trig[i] = 0.0
			prev_grip[i] = 0.0
			continue
		var lt: Vector3 = inv * h.tip
		var near: bool = absf(lt.x) < W + 0.04 and absf(lt.z) < H * 0.5 + 0.04 and lt.y > -0.04 and lt.y < 0.12
		var tvel: Vector3 = (lt - prev_tip[i]) / maxf(dt, 1e-3)
		prev_tip[i] = lt
		if near:
			h.food_t = 0.3   # trigger means "page", not "fish food", while touching the book
		# GRIP near the book: pick it up
		var palm: Vector3 = h.grip_xf.origin
		var lp: Vector3 = inv * palm
		var grab_zone: bool = absf(lp.x) < W + 0.08 and absf(lp.z) < H * 0.5 + 0.08 and absf(lp.y) < 0.12
		if h.grip > 0.6 and prev_grip[i] <= 0.6 and grab_zone and hold_hand < 0:
			hold_hand = i
			hold_off = h.grip_xf.affine_inverse() * global_transform
			main.buzz(i, 0.3, 0.05)
		if hold_hand == i:
			h.bubble_t = 1.0
			h.bubbles.emitting = false
			if h.grip < 0.4:
				hold_hand = -1
			else:
				global_transform = h.grip_xf * hold_off
		prev_grip[i] = h.grip
		if STAGE < 2:
			continue
		# TRIGGER on a page: pinch it and drag it across
		if h.trigger > 0.6 and prev_trig[i] <= 0.6 and near and drag_hand < 0 and hold_hand != i:
			if start_turn(1.0 if lt.x > 0.0 else -1.0):
				drag_hand = i
				drag_start = age
				drag_from = lt
				main.buzz(i, 0.15, 0.03)
		if drag_hand == i:
			if h.trigger > 0.4:
				follow = acos(clampf(lt.x / W, -1.0, 1.0)) / PI
			else:
				drag_hand = -1
				var tap: bool = age - drag_start < 0.35 and lt.distance_to(drag_from) < 0.03
				if tap:
					finish_turn(1.0 if leaf_dir > 0.0 else 0.0)
				else:
					finish_turn(1.0 if leaf_t > 0.5 else 0.0)
				main.buzz(i, 0.2, 0.03)
		# a quick finger swipe across a page flips it too
		elif drag_hand < 0 and leaf_j < 0 and absf(lt.y) < 0.03 and absf(lt.z) < H * 0.5:
			if lt.x > 0.03 and tvel.x < -0.7:
				if start_turn(1.0):
					finish_turn(1.0)
					main.buzz(i, 0.2, 0.03)
			elif lt.x < -0.03 and tvel.x > 0.7:
				if start_turn(-1.0):
					finish_turn(0.0)
					main.buzz(i, 0.2, 0.03)
		prev_trig[i] = h.trigger
	_step_leaf(dt, follow)
	# if you swim far away, the book drifts back to you
	var head: Transform3D = main.head_transform()
	if hold_hand < 0 and global_position.distance_to(head.origin) > 4.0:
		var f := -head.basis.z
		f.y = 0
		f = f.normalized()
		var goal := head.origin + f * 0.5 + Vector3(0, -0.35, 0)
		global_position = global_position.lerp(goal, clampf(dt * 0.8, 0.0, 1.0))
