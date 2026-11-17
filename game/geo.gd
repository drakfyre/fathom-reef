class_name Geo
extends RefCounted
## Collects triangles (position, normal, colour, sway weight in UV.x) and turns them into one
## ArrayMesh, so a whole reef or a whole fish is a single draw call.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var idx := PackedInt32Array()


func vtx(p: Vector3, nrm: Vector3, col: Color, w := 0.0) -> int:
	v.append(p)
	n.append(nrm)
	c.append(col)
	uv.append(Vector2(w, 0))
	return v.size() - 1


func tri(a: int, b: int, cc: int) -> void:
	## Godot's front faces have cross(b-a, c-a) pointing against the outward normal;
	## orient every triangle that way so lighting is right with cull_disabled too.
	var f := (v[b] - v[a]).cross(v[cc] - v[a])
	if f.dot(n[a] + n[b] + n[cc]) > 0.0:
		idx.append_array([a, cc, b])
	else:
		idx.append_array([a, b, cc])


func quad(a: int, b: int, cc: int, d: int) -> void:
	tri(a, b, cc)
	tri(a, cc, d)


func add_arrays(arr: Array, xf: Transform3D, col: Variant, sway: Variant = 0.0) -> void:
	## Adds a primitive's arrays. col / sway are constants or Callables(local, world, normal).
	var base := v.size()
	var av: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nb := xf.basis.inverse().transposed()
	for i in av.size():
		var lp := av[i]
		var wp := xf * lp
		var wn := (nb * an[i]).normalized()
		v.append(wp)
		n.append(wn)
		c.append(col.call(lp, wp, wn) if col is Callable else col)
		uv.append(Vector2(sway.call(lp, wp, wn) if sway is Callable else float(sway), 0))
	for i: int in arr[Mesh.ARRAY_INDEX]:
		idx.append(base + i)


func smooth_normals(vfrom: int, ifrom: int) -> void:
	## Recomputes normals of vertices >= vfrom from the faces at indices >= ifrom.
	for i in range(vfrom, v.size()):
		n[i] = Vector3.ZERO
	for i in range(ifrom, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var cc := idx[i + 2]
		var f := (v[cc] - v[a]).cross(v[b] - v[a])  # outward for front faces
		n[a] += f
		n[b] += f
		n[cc] += f
	for i in range(vfrom, v.size()):
		n[i] = n[i].normalized() if n[i].length_squared() > 1e-12 else Vector3.UP


func commit(mat: Material = null) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat:
		m.surface_set_material(0, mat)
	return m


static func sphere(radial := 10, rings := 6) -> Array:
	var s := SphereMesh.new()
	s.radial_segments = radial
	s.rings = rings
	return s.get_mesh_arrays()


static func cyl(top: float, bottom: float, h: float, radial := 6, caps := true) -> Array:
	var s := CylinderMesh.new()
	s.top_radius = top
	s.bottom_radius = bottom
	s.height = h
	s.radial_segments = radial
	s.rings = 1
	s.cap_top = caps
	s.cap_bottom = false
	return s.get_mesh_arrays()


static func lin(col: Color) -> Color:
	return col.srgb_to_linear()
