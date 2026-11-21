"""Single-gang blue PVC nail-on device box (new construction), with its two captive
16d nails. Built from the listing photo and its stated size: 2.25" wide x 3.7" tall
x 2.85" deep.

Same conventions as the receptacle and switch scripts so a device bolts straight on:
X = width (+X is the stud side, where the nail points come out), Z = up, Y = depth
with the box's open front on Y = 0 and the back toward +Y. Units below are INCHES.
Every number is a knob. Safe to re-run.

    blender --background --python blend/nail_on_box.py
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

IN = 0.0254
COLLECTION_NAME = globals().get('COLLECTION_NAME', 'Nail_On_Box')

# --- Shell --------------------------------------------------------------------------------
BOX_W, BOX_H, BOX_D = globals().get('BOX_SIZE', (2.25, 3.7, 2.85))   # outside, at the front (listing)
                                          # (house_framing.py also builds a 4" square version for the dryer receptacle)
WALL_T = 0.09                              # molded wall
BACK_T = 0.10
DRAFT = 0.05                               # each side narrows this much from front to back (mould draft)
CORNER_R = 0.12                            # outside corner rounding, seen from the front
RIM_LIP = 0.03                             # the front rim stands this far out round the opening

# --- Device screw bosses (6-32, standard 3-9/32" spacing) ---------------------------------
BOSS_SPACING = 3.28125
BOSS_R = 0.17
BOSS_DEPTH = BOX_D - BACK_T               # the screw channels run all the way to the back wall
BOSS_HOLE_R = 0.07
BOSS_HOLE_DEPTH = 0.36

# --- Inside -------------------------------------------------------------------------------
FLOOR_RIBS_X = (-0.55, 0.55)               # raised ribs running front-to-back on the top and bottom inside walls
FLOOR_RIB = (0.14, 0.10)                   # width, height
FLOOR_RIB_FRONT = 0.55                     # they stop this far back from the front
KNOCKOUTS = [(-0.45, -1.05), (0.45, -1.05), (-0.45, 1.05), (0.45, 1.05)]   # scored panels in the back wall (x, z)
KNOCKOUT = (0.55, 0.45)                    # width, height
SCORE = (0.025, 0.03)                      # score-line width, depth

# --- Nail rails, clips and nails ----------------------------------------------------------
RAILS_X = ((-1.0, -0.76), (-0.46, -0.16))  # raised rails on top (and bottom) running front-to-back
RAIL_H = 0.22
RAIL_Y = (0.12, 2.1)
NAIL_Y = 0.62                              # nail centre at the box's centreline, back from the front
NAIL_ANGLE = 20.0                          # degrees: the point heads toward the back as it goes into the stud
NAIL_LEN = 3.5                             # 16d common
NAIL_R = 0.081                             # 0.162" shank
NAIL_HEAD = (0.17, 0.022)                  # head radius, thickness: a flat common-nail head
NAIL_POINT = 0.22                          # length of the pointed tip
NAIL_TIP_X = BOX_W / 2 + 0.02              # point just at the stud side, ready to drive
NAILS_DRIVEN = globals().get('NAILS_DRIVEN', False)   # True: nails driven home into the stud (set by house_framing.py)
CLIPS_X = (-0.88, -0.31, 0.98)             # hook clips holding each nail
CLIP = (0.16, 0.26, 0.20)                  # width (x), depth (y), height above the nail centre
STUD_NUBS_Z = (1.2, -1.2)                  # little depth-gauge nubs on the stud side, near the front
STUD_NUB = (0.08, 0.14, 0.22)              # out from the side, depth, height

COLORS = {'pvc': (0.015, 0.20, 0.72), 'nail': (0.72, 0.72, 0.73)}

# --- Setup ---------------------------------------------------------------------------------
scene = bpy.context.scene
old = bpy.data.collections.get(COLLECTION_NAME)
if old:
    for obj in list(old.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
col = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(col)
root = bpy.data.objects.new('Nail_On_Box_Root', None)
root.empty_display_size = 2 * IN
col.objects.link(root)


def material(key):
    name = 'Box_' + key.capitalize()
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*COLORS[key], 1)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*COLORS[key], 1)
    if key == 'pvc':        # semi-gloss moulded PVC with faint mould texture
        bsdf.inputs['Roughness'].default_value = 0.32
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 3000
        b = nt.nodes.new('ShaderNodeBump')
        b.inputs['Strength'].default_value = 0.04
        nt.links.new(nt.nodes.new('ShaderNodeTexCoord').outputs['Object'], n.inputs['Vector'])
        nt.links.new(n.outputs['Fac'], b.inputs['Height'])
        nt.links.new(b.outputs['Normal'], bsdf.inputs['Normal'])
    else:                   # bright common nail
        bsdf.inputs['Metallic'].default_value = 1.0
        bsdf.inputs['Roughness'].default_value = 0.35
    return mat


# --- Geometry helpers (inches) ---------------------------------------------------------------

def rrect(w, h, r, cx=0.0, cz=0.0, seg=4):
    pts = []
    hw, hh = w / 2, h / 2
    r = min(r, hw, hh)
    for ox, oz, a0 in ((cx + hw - r, cz - hh + r, -90), (cx + hw - r, cz + hh - r, 0),
                       (cx - hw + r, cz + hh - r, 90), (cx - hw + r, cz - hh + r, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            p = (ox + r * math.cos(a), oz + r * math.sin(a))
            if not pts or math.dist(p, pts[-1]) > 1e-6:
                pts.append(p)
    if math.dist(pts[0], pts[-1]) < 1e-6:
        pts.pop()
    return pts


def to_obj(name, bm, key=None, smooth=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    obj.parent = root
    if key:
        mesh.materials.append(material(key))
    return obj


def loft(name, front, back, y0, y1, key=None):
    """Joins an (x, z) outline at depth y0 to a matching one at y1, capped."""
    bm = bmesh.new()
    a = [bm.verts.new((x * IN, y0 * IN, z * IN)) for x, z in front]
    b = [bm.verts.new((x * IN, y1 * IN, z * IN)) for x, z in back]
    n = len(a)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    return to_obj(name, bm, key)


def prism(name, outline, y0, y1, key=None):
    return loft(name, outline, outline, y0, y1, key)


def box(name, xs, ys, zs, key=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = [((lo + hi) / 2 + c * (hi - lo)) * IN for c, (lo, hi) in zip(v.co, (xs, ys, zs))]
    return to_obj(name, bm, key)


def cylinder(name, profile, seat, axis, key, seg=24):
    """(radius, height) profile spun round local +Z, seated at `seat`, pointing along axis."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(math.tau * i / seg) * IN, r * math.sin(math.tau * i / seg) * IN, h * IN))
              for i in range(seg)] for r, h in profile]
    for p, q in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((p[i], p[(i + 1) % seg], q[(i + 1) % seg], q[i]))
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    bmesh.ops.poke(bm, faces=caps)
    rot = axis if isinstance(axis, Matrix) else {
        '+Y': Matrix.Rotation(-math.pi / 2, 4, 'X'), '+X': Matrix.Rotation(math.pi / 2, 4, 'Y'),
        '-X': Matrix.Rotation(-math.pi / 2, 4, 'Y')}[axis]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(seat) * IN) @ rot, verts=bm.verts[:])
    return to_obj(name, bm, key, smooth=True)


def boolean(obj, others, op):
    for o in others:
        m = obj.modifiers.new('B', 'BOOLEAN')
        m.operation, m.solver, m.object = op, 'EXACT', o
    dg = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old_mesh = obj.data
    obj.modifiers.clear()
    obj.data = baked
    bpy.data.meshes.remove(old_mesh)
    for o in others:
        m = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.meshes.remove(m)
    return obj


# --- Shell ---------------------------------------------------------------------------------------
W, H, D, t = BOX_W, BOX_H, BOX_D, WALL_T
shell = loft('01_Box_Shell', rrect(W, H, CORNER_R), rrect(W - 2 * DRAFT, H - 2 * DRAFT, CORNER_R), 0, D, 'pvc')
cavity = loft('Cut', rrect(W - 2 * t, H - 2 * t, CORNER_R * 0.5),
              rrect(W - 2 * t - 2 * DRAFT, H - 2 * t - 2 * DRAFT, CORNER_R * 0.5), -1, D - BACK_T)
boolean(shell, [cavity], 'DIFFERENCE')

# Screw bosses: round posts inside the top and bottom walls, tapped from the front.
bz = BOSS_SPACING / 2
posts = [cylinder('Post', [(BOSS_R, 0), (BOSS_R, BOSS_DEPTH)], (0, 0.0, sz * bz), '+Y', None) for sz in (1, -1)]
ribs = []
for sz in (1, -1):                         # floor/ceiling ribs on the top and bottom inside walls
    inner = sz * (H / 2 - t)
    for rx in FLOOR_RIBS_X:
        w, h = FLOOR_RIB
        ribs.append(box('Rib', (rx - w / 2, rx + w / 2), (FLOOR_RIB_FRONT, D - BACK_T + 0.01),
                        tuple(sorted((inner, inner - sz * h)))))
boolean(shell, posts + ribs, 'UNION')
holes = [cylinder('Hole', [(BOSS_HOLE_R, -0.1), (BOSS_HOLE_R, BOSS_HOLE_DEPTH)], (0, 0.0, sz * bz), '+Y', None)
         for sz in (1, -1)]
boolean(shell, holes, 'DIFFERENCE')

# Scored knockouts in the back wall: a thin groove round each panel, from inside.
sw, sd = SCORE
cuts = []
for kx, kz in KNOCKOUTS:
    kw, kh = KNOCKOUT
    yb = D - BACK_T
    for xs, zs in (((kx - kw / 2, kx + kw / 2), (kz + kh / 2 - sw, kz + kh / 2)),
                   ((kx - kw / 2, kx + kw / 2), (kz - kh / 2, kz - kh / 2 + sw)),
                   ((kx - kw / 2, kx - kw / 2 + sw), (kz - kh / 2, kz + kh / 2)),
                   ((kx + kw / 2 - sw, kx + kw / 2), (kz - kh / 2, kz + kh / 2))):
        cuts.append(box('Score', xs, (yb - 0.05, yb + sd), zs))
boolean(shell, cuts, 'DIFFERENCE')

# Rim lip round the front opening.
lip = prism('02_Box_Rim', rrect(W + 2 * RIM_LIP, H + 2 * RIM_LIP, CORNER_R + RIM_LIP), 0, 0.06, 'pvc')
boolean(lip, [prism('Cut', rrect(W - 2 * t, H - 2 * t, CORNER_R * 0.5), -1, 1)], 'DIFFERENCE')

# --- Rails, clips and nails ------------------------------------------------------------------------
for sz, side in ((1, 'Top'), (-1, 'Bottom')):
    face = sz * H / 2
    for i, (x0, x1) in enumerate(RAILS_X):
        box('03_Rail_%s_%d' % (side, i), (x0, x1), RAIL_Y, tuple(sorted((face - sz * 0.02, face + sz * RAIL_H))), 'pvc')
    nz = face + sz * (RAIL_H + NAIL_R)
    tilt = math.radians(NAIL_ANGLE)
    nail_rot = Matrix.Rotation(tilt, 4, 'Z') @ Matrix.Rotation(-math.pi / 2, 4, 'Y')   # tip -> head runs toward -X and the front
    nail_y = lambda x: NAIL_Y + x * math.tan(tilt)                                     # the nail's line, seen from above
    for i, cx in enumerate(CLIPS_X):
        cw, cd, ch = CLIP
        cy = nail_y(cx)
        clip = box('04_Clip_%s_%d' % (side, i), (cx - cw / 2, cx + cw / 2), (cy - cd / 2, cy + cd / 2),
                   tuple(sorted((face, nz + sz * ch))), 'pvc')
        boolean(clip, [cylinder('Hole', [(NAIL_R + 0.01, -1), (NAIL_R + 0.01, 1)], (cx, cy, nz), nail_rot, None)],
                'DIFFERENCE')
    # The nail: point at the stud side angled toward the back, shank, flat head off the far side.
    tip_x = NAIL_TIP_X
    if NAILS_DRIVEN:          # slide it in until the head seats on the outer clip
        tip_x = CLIPS_X[0] - CLIP[0] / 2 - 0.005 + (NAIL_LEN - NAIL_HEAD[1]) * math.cos(tilt)
    cylinder('05_Nail_%s' % side, [(0.012, 0), (NAIL_R, NAIL_POINT), (NAIL_R, NAIL_LEN - NAIL_HEAD[1]),
                                   (NAIL_HEAD[0], NAIL_LEN - NAIL_HEAD[1]), (NAIL_HEAD[0], NAIL_LEN)],
             (tip_x, nail_y(tip_x), nz), nail_rot, 'nail', seg=16)

for nz in STUD_NUBS_Z:
    o, d, h = STUD_NUB
    box('06_Stud_Nub', (W / 2 - 0.01, W / 2 + o), (0.06, 0.06 + d), (nz - h / 2, nz + h / 2), 'pvc')

for o in col.objects:
    if o.type == 'MESH' and o.data.materials and o.data.materials[0].name == 'Box_Pvc':
        for p in o.data.polygons:
            p.use_smooth = False
print('Built nail-on box: %d parts.' % (len(col.objects) - 1))
