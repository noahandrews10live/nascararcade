extends SceneTree
## Nothing in the scenery stands on the racing surface or in front of it: every
## prop, building, tree and sign of every track is checked against the track
## (centreline, both walls), and anything whose footprint reaches between the
## walls (or over the apron) and stands taller than a curb is reported.
## Needs a renderer (MultiMesh transforms aren't kept headless):
##   xvfb-run godot --rendering-driver opengl3 -s tests/scenery_clear_test.gd   (TRACK=n for one)

var failures := 0
## Things that belong over the racing surface: the track itself, its walls,
## fences, lines, lights high above, the start/finish gantry...
const ALLOWED := ["Road", "Surface", "Apron", "Wall", "Fence", "Line", "Lines", "Skid", "Rubber", "Marbles", "Grass", "Ground", "Infield", "Catch", "Gantry", "Bridge", "Sky", "Water", "Lake", "Kerb", "Curb", "Shadow", "Banner", "Light", "Lights", "Debris"]


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _allowed(n: Node) -> bool:
	var p: Node = n
	while p:
		for a in ALLOWED:
			if String(p.name).contains(a):
				return true
		if p.has_meta("over_track"):
			return true
		p = p.get_parent()
		if p and p.has_method("car_transform"):
			break
	return false


## Where a world point is relative to the track: [s index, lateral offset d].
func _where(t: Node3D, p: Vector3) -> Array:
	var best := 1e20
	var bi := 0
	var step := 4
	for i in range(0, t.n, step):
		var q: Vector3 = t.pos[i]
		var dd := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if dd < best:
			best = dd
			bi = i
	for i in range(bi - step, bi + step + 1):
		var j: int = posmod(i, t.n)
		var q: Vector3 = t.pos[j]
		var dd := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if dd < best:
			best = dd
			bi = j
	var r: Vector3 = t.right[bi]
	var rel: Vector3 = p - t.pos[bi]
	return [bi, rel.x * r.x + rel.z * r.z, sqrt(best)]


const MERGED := ["scenery", "concrete", "seats", "lamp"]
var _grid := {}
const CELL := 25.0


func _grid_build(t: Node3D) -> void:
	_grid.clear()
	for i in t.n:
		var q: Vector3 = t.pos[i]
		var key := Vector2i(floori(q.x / CELL), floori(q.z / CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


## Like _where, but only near the track (within a cell or two): [] if far away.
func _where_fast(t: Node3D, p: Vector3) -> Array:
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var best := 1e20
	var bi := -1
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in _grid.get(c + Vector2i(dx, dz), []):
				var q: Vector3 = t.pos[i]
				var dd := Vector2(p.x - q.x, p.z - q.z).length_squared()
				if dd < best:
					best = dd
					bi = i
	if bi < 0:
		return []
	var r: Vector3 = t.right[bi]
	var rel: Vector3 = p - t.pos[bi]
	return [bi, rel.x * r.x + rel.z * r.z, sqrt(best)]


func _boxes(n: Node, out: Array) -> void:
	if n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
		var mm: MultiMesh = n.multimesh
		var ab: AABB = mm.mesh.get_aabb()
		for i in mm.instance_count:
			var it: Transform3D = mm.get_instance_transform(i)
			if it.is_equal_approx(Transform3D.IDENTITY):
				continue # not placed (yet): a pool filled at run time
			var xf: Transform3D = n.global_transform * it
			out.append([n, xf * ab])
	elif n is MeshInstance3D and n.mesh and n.visible:
		out.append([n, n.global_transform * n.mesh.get_aabb()])
	for c in n.get_children():
		_boxes(c, out)


func _run() -> void:
	var game := root.get_node("Game")
	var only := OS.get_environment("TRACK")
	for idx in game.tracks.size():
		if only != "" and int(only) != idx:
			continue
		var t: Node3D = load("res://scripts/track.gd").new()
		root.add_child(t)
		t.setup(game.tracks[idx])
		for i in 240: # scenery is filled in over the first frames
			await process_frame
		var boxes: Array = []
		_boxes(t, boxes)
		var bad := {}
		# The racing surface and the apron (cars drive on both).
		var lo: float = t.apron_edge() + 0.3
		var hi: float = t.outer_edge() - 0.3
		for b in boxes:
			var node: Node = b[0]
			var ab: AABB = b[1]
			if ab.size.y < 0.6 or ab.size.x > 400.0 or ab.size.z > 400.0:
				continue # flat (markings, grass) or the whole-track meshes
			if _allowed(node):
				continue
			# Sample the footprint's corners and centre.
			var pts: Array = [ab.get_center()]
			for k in 4:
				pts.append(Vector3(ab.position.x + ab.size.x * float(k & 1), ab.get_center().y, ab.position.z + ab.size.z * float(k >> 1)))
			for p in pts:
				var w: Array = _where(t, p)
				if w[1] > lo and w[1] < hi and abs(w[1]) < 60.0:
					var key := "%s" % _path(node, t)
					if not bad.has(key):
						bad[key] = "d %.1f (surface %.1f..%.1f) at s=%d, size %s, top %.1f m" % [w[1], lo, hi, int(w[0] * t.length / t.n), str(ab.size.snapped(Vector3(0.1, 0.1, 0.1))), ab.end.y]
					break
		# The merged meshes (stands, buildings, haulers, the pylon...: one mesh per
		# material) are checked vertex by vertex: nothing taller than a curb over
		# the racing surface or the apron, except the start/finish gantry.
		_grid_build(t)
		for kind in MERGED:
			var mi: MeshInstance3D = t.get_node_or_null("Surface_" + kind)
			if mi == null or mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				var pts := PackedVector3Array()
				for vi in range(0, verts.size() - 2, 3):
					# Points across the triangle every few metres (a long wall has
					# its corners well away from where its middle crosses the track).
					var a: Vector3 = mi.global_transform * verts[vi]
					var b: Vector3 = mi.global_transform * verts[vi + 1]
					var c: Vector3 = mi.global_transform * verts[vi + 2]
					var m: int = clampi(int(max(a.distance_to(b), a.distance_to(c)) / 4.0), 1, 80)
					for u in m + 1:
						for v in m + 1 - u:
							pts.append(a + (b - a) * (float(u) / m) + (c - a) * (float(v) / m))
				for p in pts:
					var w: Array = _where_fast(t, p)
					if w.is_empty() or w[1] <= lo or w[1] >= hi:
						continue
					var s_m: float = float(w[0]) * t.length / t.n
					if min(s_m, t.length - s_m) < 4.0:
						continue # the flag stand gantry over the line
					var ground: float = t.surface_point(s_m, w[1]).y
					if p.y > ground + 1.0:
						var key := "Surface_%s" % kind
						if not bad.has(key):
							bad[key] = "a vertex %.1f m up at d %.1f (surface %.1f..%.1f), s=%d" % [p.y - ground, w[1], lo, hi, int(s_m)]
		for k in bad:
			print("   %s: %s" % [k, bad[k]])
		_check(bad.is_empty(), "%s: nothing stands on the track (%d meshes checked)" % [game.tracks[idx].name, boxes.size()])
		t.free()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func _path(n: Node, top: Node) -> String:
	var parts: Array = []
	var p: Node = n
	while p and p != top:
		parts.push_front(String(p.name))
		p = p.get_parent()
	return "/".join(parts)
