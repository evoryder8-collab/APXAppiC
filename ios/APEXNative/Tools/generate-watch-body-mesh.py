# Builds APEXWatch/WatchBody.bin, the glass figure on the Watch water page, from the app's own body silhouette.
# The silhouette is given depth (thicker where the body is wider), smoothed and reduced to about 11,000 triangles.
#
# Blender -b --python Tools/generate-watch-body-mesh.py -- \
#   APEXWatch/WatchAssets.xcassets/WatchHydrationSilhouette.imageset/WatchHydrationSilhouette.png \
#   APEXWatch/WatchBody.bin /tmp/watch-body-preview.png
#
# File layout (little-endian): UInt32 vertex count, UInt32 triangle count, then per vertex six Float32
# (position x y z, normal x y z; feet at y = 0, head at y = 1), then three UInt16 indices per triangle.
import bpy, sys, struct, bmesh, math, time
import numpy as np
src, out, png = sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
img = bpy.data.images.load(src)
W, H = img.size
a = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[:, :, 3]  # row 0 = bottom
ys, xs = np.nonzero(a > 0.5)
a = a[ys.min():ys.max()+1, xs.min():xs.max()+1]
RH = 300
step = a.shape[0] / RH
RW = int(round(a.shape[1] / step))
yi = np.clip((np.arange(RH) * step + step/2).astype(int), 0, a.shape[0]-1)
xi = np.clip((np.arange(RW) * step + step/2).astype(int), 0, a.shape[1]-1)
m = a[np.ix_(yi, xi)] > 0.5
m = np.pad(m, 2)
RH, RW = m.shape
# brute-force distance to the nearest outside cell
inside = np.argwhere(m); outside = np.argwhere(~m)
edge = np.zeros_like(m)
edge[1:-1,1:-1] = (~m[1:-1,1:-1]) & (m[:-2,1:-1] | m[2:,1:-1] | m[1:-1,:-2] | m[1:-1,2:])
eo = np.argwhere(edge).astype(np.float32)
d = np.zeros(m.shape, dtype=np.float32)
for i in range(0, len(inside), 2000):
    c = inside[i:i+2000].astype(np.float32)
    dd = np.sqrt(((c[:, None, :] - eo[None, :, :])**2).sum(-1)).min(1)
    d[inside[i:i+2000, 0], inside[i:i+2000, 1]] = dd
dmax = d.max()
print("LOG grid", RW, RH, "dmax", dmax, flush=True)
z = 0.62 * np.sqrt(np.maximum(d - 1.0, 0) * dmax)
idx = -np.ones(m.shape + (2,), dtype=np.int64)
verts = []
for (r, c) in inside:
    if z[r, c] <= 0:
        idx[r, c, 0] = idx[r, c, 1] = len(verts); verts.append((c, r, 0.0))
    else:
        idx[r, c, 0] = len(verts); verts.append((c, r, z[r, c]))
        idx[r, c, 1] = len(verts); verts.append((c, r, -z[r, c]))
faces = []
for r in range(RH-1):
    for c in range(RW-1):
        if m[r, c] and m[r+1, c] and m[r, c+1] and m[r+1, c+1]:
            q = [idx[r, c], idx[r, c+1], idx[r+1, c+1], idx[r+1, c]]
            for s in (0, 1):
                f = [int(v[s]) for v in q]
                if len(set(f)) >= 3:
                    f = list(dict.fromkeys(f))
                    faces.append(f if s == 0 else f[::-1])
me = bpy.data.meshes.new("body")
# Blender: x right, z up, y depth
me.from_pydata([(x, -zz, y) for (x, y, zz) in verts], [], faces)
me.update()
o = bpy.data.objects.new("body", me); bpy.context.scene.collection.objects.link(o)
bpy.context.view_layer.objects.active = o; o.select_set(True)
bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
s = o.modifiers.new("sm", 'SMOOTH'); s.factor = 0.5; s.iterations = 40
bpy.ops.object.modifier_apply(modifier="sm")
rm = o.modifiers.new("rm", 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = RH / 220; rm.adaptivity = 0
bpy.ops.object.modifier_apply(modifier="rm")
s = o.modifiers.new("sm2", 'SMOOTH'); s.factor = 0.6; s.iterations = 25
bpy.ops.object.modifier_apply(modifier="sm2")
me = o.data
tris = len(me.polygons) * 2
dm = o.modifiers.new("dc", 'DECIMATE'); dm.ratio = min(1, 11000 / tris)
bpy.ops.object.modifier_apply(modifier="dc")
me = o.data
bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.triangulate(bm, faces=bm.faces); bm.to_mesh(me)
print("LOG closed", all(e.is_manifold for e in bm.edges), flush=True); bm.free()
for p in me.polygons: p.use_smooth = True
me.update()
co = np.array([v.co[:] for v in me.vertices])
mn, mx = co.min(0), co.max(0); h = mx[2] - mn[2]; cx = (mn[0] + mx[0]) / 2
print("LOG final", len(me.vertices), len(me.polygons), mn, mx, flush=True)
with open(out, "wb") as f:
    f.write(struct.pack("<II", len(me.vertices), len(me.polygons)))
    for v in me.vertices:
        n = v.normal
        f.write(struct.pack("<6f", (v.co.x - cx) / h, (v.co.z - mn[2]) / h, -v.co.y / h, n.x, n.z, -n.y))
    for p in me.polygons:
        f.write(struct.pack("<3H", *p.vertices))
cz = (mn[2] + mx[2]) / 2
for i, (loc, rot) in enumerate([((cx, -h*3, cz), (math.pi/2, 0, 0)), ((cx + h*2.1, -h*2.1, cz), (math.pi/2, 0, math.pi/4)), ((cx + h*3, 0, cz), (math.pi/2, 0, math.pi/2))]):
    bpy.ops.object.camera_add(location=loc, rotation=rot)
    bpy.context.scene.camera = bpy.context.object
    if i == 0: bpy.ops.object.light_add(type='SUN', rotation=(0.9, 0.3, 0.5))
    sc = bpy.context.scene; sc.render.resolution_x = 900; sc.render.resolution_y = 1600
    sc.render.engine = 'BLENDER_WORKBENCH'; sc.render.filepath = png.replace(".png", f"{i}.png")
    bpy.ops.render.render(write_still=True)
