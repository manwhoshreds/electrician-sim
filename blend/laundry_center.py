"""27" stacked laundry center: top-load washer below, electric dryer above, from the
product photos and the listing's diagram (75.88" tall, 30.88" deep, door open 47.5").
Brand logos are left off. The back connections (vent, 30 A cord and 14-30 plug,
water inlets, drain hose) aren't in the photos and follow standard practice.

INCHES below. World: X = width, Y = depth (washer front at Y = 0, back toward +Y),
Z = up from the floor; one inch = 0.0254 m. The dryer door and washer lid are their
own objects with their pivot on the hinge, ready to animate. Safe to re-run.

    blender --background --python blend/laundry_center.py
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

IN = 0.0254
COLLECTION_NAME = 'Laundry_Center'

# --- Cabinet ------------------------------------------------------------------------------
W, D, H = 27.0, 30.88, 75.88
EDGE_R = 0.6                  # rounding on the cabinet's vertical edges
WASHER_H = 33.8               # top of the lower (washer) cabinet
TOE = (1.4, 0.8)              # toe kick at the washer's bottom front: height, depth
FOOT = (0.8, 0.7)             # leveling feet: radius, height showing
DRYER_SETBACK = 6.2           # dryer front, back from the washer front (diagram)
PANEL_BOTTOM = 46.5           # bottom of the control strip; the recess slopes back from here...
SLOPE_END = 23.5              # ...down to the washer top this far back

# --- Dryer door (photo: 8.46 px/in) --------------------------------------------------------
DOOR = (23.9, 18.9)           # width, height
DOOR_Z = 54.0                 # bottom edge
DOOR_R = 2.4                  # corner radius
DOOR_T = 0.9                  # stands this far proud of the dryer front
DOOR_PANEL_INSET = 1.6        # the embossed centre panel, in from the door edge
DOOR_PANEL_RAISE = 0.25
HANDLE = (1.8, 8.5, -9.1, 64.8, 0.6)   # recessed pull: width, height, x, z centre, depth

# --- Controls --------------------------------------------------------------------------------
KNOBS = [   # x, z, diameter, depth
    (-11.0, 50.6, 2.4, 1.1),  # dryer cycle
    (-3.8, 48.6, 1.3, 0.8),   # small knobs
    (-1.1, 48.6, 1.3, 0.8),
    (10.3, 50.6, 2.4, 1.1),   # washer cycle
]
DIAL_RING = 0.45              # printed ring round each big knob (wider than the knob)

# --- Washer lid ---------------------------------------------------------------------------------
LID = (21.0, 14.5, 0.6)       # width, depth, thickness
LID_FRONT = 2.2               # lid's front edge, back from the washer front
RIM = (0.5, 0.35)             # raised rim round the lid opening: width, height

# --- Back connections (standard practice; not in the photos) -----------------------------------
VENT = (4.0, 2.0, -6.0, 41.0)          # dryer exhaust: diameter, length out the back, x, z
# Dryer cord and terminal block (from the cord photo: 4-wire 30 A, right-angle 14-30P,
# black / white / red / green conductors on ring terminals, galvanized strain-relief clamp).
POCKET = (5.0, 4.2, 1.3)               # recess in the dryer back for the terminal block: width, height, depth
POCKET_C = (7.5, 43.5)                 # its centre (x, z)
BLOCK = (3.2, 1.0, 0.6)                # terminal block: width, height, how far it stands off the pocket floor
BLOCK_Z = 44.7
TERM_X = (6.5, 7.5, 8.5)               # L1 (black), N (white), L2 (red)
GROUND_AT = (5.75, 42.35)              # green ground screw on the pocket floor (x, z)
CORD_X = 8.3                           # where the cord comes up the back and into the pocket
CORD_D = 0.62                          # 10/4 SRDT cord
COND_R = 0.1                           # each insulated #10 conductor
JACKET_END_Z = 42.5                    # jacket stripped back to here inside the pocket
CLAMP_Z = 40.4                         # strain-relief clamp holding the cord to the back panel
PLUG_AT = globals().get('PLUG_AT', (11.5, 6.5, 2.5))   # plug head centre: x, distance out from the back, height
                                       # (house_framing.py sets it to line up with the 14-30R it plugs into)
COVER = (5.6, 4.8, 0.04)               # access cover: width, height, sheet thickness
COVER_NOTCH = (0.95, 1.5)              # notch in its bottom edge where the cord goes in: width, height
ACCESS_OPEN = globals().get('ACCESS_OPEN', False)   # True: cover swung open, wiring showing
ANIMATE = globals().get('ANIMATE', True)            # build the Open_Access animation
COVER_SWING = 105.0                    # degrees the cover swings down when opened
INLETS = [(-4.0, 31.0, (0.75, 0.08, 0.06)), (4.0, 31.0, (0.06, 0.25, 0.75))]  # hot (red), cold (blue): x, z, colour
DRAIN = (9.0, 28.0)                    # drain hose leaves the back here (x, z)

COLORS = {
    'enamel': (0.90, 0.90, 0.89), 'recess': (0.80, 0.80, 0.79), 'door': (0.92, 0.92, 0.91),
    'knob': (0.94, 0.94, 0.93), 'dial': (0.55, 0.75, 0.85), 'rubber': (0.03, 0.03, 0.03),
    'cord': (0.10, 0.10, 0.11), 'plug': (0.08, 0.08, 0.09), 'blade': (0.75, 0.62, 0.35),
    'vent': (0.70, 0.71, 0.72), 'hose': (0.20, 0.20, 0.22), 'brass': (0.78, 0.58, 0.24),
}

# --- Setup -----------------------------------------------------------------------------------------
scene = bpy.context.scene
old = bpy.data.collections.get(COLLECTION_NAME)
if old:
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(old)
for m in list(bpy.data.meshes):
    if m.users == 0:
        bpy.data.meshes.remove(m)
col = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(col)
root = bpy.data.objects.new('Laundry_Center_Root', None)
root.empty_display_size = 0.3
col.objects.link(root)


def material(key, metallic=0.0, rough=0.35, emit=None):
    name = 'Laundry_' + key.capitalize()
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*COLORS[key], 1)
    mat.use_nodes = True
    b = mat.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*COLORS[key], 1)
    b.inputs['Metallic'].default_value = metallic
    b.inputs['Roughness'].default_value = rough
    return mat


MATS = {
    'enamel': material('enamel', 0.0, 0.22), 'recess': material('recess', 0.0, 0.4), 'door': material('door', 0.0, 0.25),
    'knob': material('knob', 0.0, 0.3), 'dial': material('dial', 0.0, 0.4), 'rubber': material('rubber', 0.0, 0.8),
    'cord': material('cord', 0.0, 0.55), 'plug': material('plug', 0.0, 0.5), 'blade': material('blade', 1.0, 0.3),
    'vent': material('vent', 0.9, 0.35), 'hose': material('hose', 0.0, 0.6), 'brass': material('brass', 1.0, 0.35),
}


def to_obj(name, bm, mat, smooth=False, origin=None, bevel=0.0):
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel * IN, segments=3, affect='EDGES', profile=0.5,
                        clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if origin is not None:
        bmesh.ops.translate(bm, vec=-Vector(origin) * IN, verts=bm.verts[:])
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS[mat])
    if smooth or bevel:
        for p in mesh.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    if origin is not None:
        obj.location = Vector(origin) * IN
    col.objects.link(obj)
    obj.parent = root
    return obj


def rrect(w, h, r, cx=0.0, cz=0.0, seg=6):
    pts, hw, hh = [], w / 2, h / 2
    r = min(r, hw - 1e-3, hh - 1e-3)
    for ox, oz, a0 in ((cx + hw - r, cz - hh + r, -90), (cx + hw - r, cz + hh - r, 0),
                       (cx - hw + r, cz + hh - r, 90), (cx - hw + r, cz - hh + r, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((ox + r * math.cos(a), oz + r * math.sin(a)))
    return pts


def extrude(name, outline, plane, a0, a1, mat, **kw):
    """Pushes a 2-D outline through a third axis. plane 'xz': outline (x, z), depth y a0..a1;
    'yz': outline (y, z), across x a0..a1; 'xy': outline (x, y), height z a0..a1."""
    bm = bmesh.new()
    def v3(p, t):
        u, v = p
        return {'xz': (u, t, v), 'yz': (t, u, v), 'xy': (u, v, t)}[plane]
    ra = [bm.verts.new(Vector(v3(p, a0)) * IN) for p in outline]
    rb = [bm.verts.new(Vector(v3(p, a1)) * IN) for p in outline]
    n = len(outline)
    for i in range(n):
        bm.faces.new((ra[i], ra[(i + 1) % n], rb[(i + 1) % n], rb[i]))
    bm.faces.new(ra)
    bm.faces.new(list(reversed(rb)))
    return to_obj(name, bm, mat, **kw)


def boxo(name, xs, ys, zs, mat, **kw):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((lo + hi) / 2 + c * (hi - lo)) * IN for c, (lo, hi) in zip(v.co, (xs, ys, zs)))
    return to_obj(name, bm, mat, **kw)


def lathe(name, profile, base, axis, mat, seg=32):
    """(radius, height) profile spun round `axis` (a direction) from `base` (inches)."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(math.tau * i / seg), r * math.sin(math.tau * i / seg), h)) for i in range(seg)]
             for r, h in profile]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    bmesh.ops.poke(bm, faces=caps)
    rot = Vector(axis).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(base) * IN) @ rot @ Matrix.Scale(IN, 4), verts=bm.verts[:])
    return to_obj(name, bm, mat, smooth=True)


def tube(name, pts, radius, mat, seg=12):
    """Round section swept through inch points (corners pre-rounded by the caller)."""
    bm = bmesh.new()
    rings, prev = [], None
    for i, p in enumerate(pts):
        T = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        N = prev if prev is not None else T.orthogonal().normalized()
        N = (N - T * N.dot(T)).normalized()
        prev = N
        B = T.cross(N)
        rings.append([bm.verts.new((p + (N * math.cos(math.tau * k / seg) + B * math.sin(math.tau * k / seg)) * radius) * IN)
                      for k in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return to_obj(name, bm, mat, smooth=True)


def smooth_path(pts, n=8):
    """Catmull-Rom through the points."""
    P = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


def cut(obj, cutters):
    for c in cutters:
        m = obj.modifiers.new('Cut', 'BOOLEAN')
        m.operation, m.solver, m.object = 'DIFFERENCE', 'EXACT', c
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    old_mesh = obj.data
    obj.modifiers.clear()
    obj.data = baked
    bpy.data.meshes.remove(old_mesh)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    return obj


hw = W / 2

# --- Washer cabinet -------------------------------------------------------------------------------
washer = extrude('01_Washer_Cabinet', rrect(W, D, EDGE_R, 0, D / 2), 'xy', TOE[0], WASHER_H, 'enamel')
boxo('01b_Washer_Base', (-hw + 0.3, hw - 0.3), (TOE[1], D - 0.3), (FOOT[1], TOE[0] + 0.01), 'enamel')
for fx in (-hw + 1.6, hw - 1.6):
    for fy in (1.6, D - 1.6):
        lathe('01c_Foot', [(FOOT[0], 0), (FOOT[0], 0.25), (0.3, 0.3), (0.3, FOOT[1] + 0.1)], (fx, fy, 0), (0, 0, 1), 'rubber')

# Lid opening with its rim, and the lid (pivot on its back edge, the hinge).
lw, ld, lt = LID
l_y0, l_y1 = LID_FRONT, LID_FRONT + ld
rim = extrude('02_Lid_Rim', rrect(lw + 2 * RIM[0], ld + 2 * RIM[0], 1.0, 0, (l_y0 + l_y1) / 2), 'xy',
              WASHER_H - 0.01, WASHER_H + RIM[1], 'enamel')
cut(rim, [extrude('Cut', rrect(lw + 0.15, ld + 0.15, 0.8, 0, (l_y0 + l_y1) / 2), 'xy', WASHER_H - 1, WASHER_H + 1, 'enamel')])
extrude('02b_Washer_Lid', rrect(lw, ld, 0.8, 0, (l_y0 + l_y1) / 2), 'xy', WASHER_H + 0.02, WASHER_H + 0.02 + lt, 'enamel',
        origin=(0, l_y1, WASHER_H))

# --- Dryer cabinet: side profile pushed across the width -------------------------------------------
y0 = DRYER_SETBACK
profile = [(y0, H), (y0, PANEL_BOTTOM), (SLOPE_END, WASHER_H), (D, WASHER_H), (D, H)]
dryer = extrude('03_Dryer_Cabinet', profile, 'yz', -hw, hw, 'enamel', bevel=0.35)
recess = extrude('03b_Recess_Liner', [(y0 + 0.3, PANEL_BOTTOM - 0.25), (SLOPE_END + 0.2, WASHER_H + 0.08),
                                      (SLOPE_END + 0.6, WASHER_H + 0.08), (y0 + 0.6, PANEL_BOTTOM - 0.05)],
                 'yz', -hw + 0.4, hw - 0.4, 'recess')

# --- Dryer door (pivot on its right edge, the hinge) -----------------------------------------------
dw, dh = DOOR
dz = DOOR_Z + dh / 2
hinge = (dw / 2, y0 - DOOR_T, dz)
door = extrude('04_Dryer_Door', rrect(dw, dh, DOOR_R, 0, dz), 'xz', y0 - DOOR_T, y0 + 0.01, 'door', bevel=0.25,
               origin=hinge)
pin = DOOR_PANEL_INSET
panel = extrude('04b_Door_Panel', rrect(dw - 2 * pin, dh - 2 * pin, DOOR_R - pin * 0.6, 0, dz), 'xz',
                y0 - DOOR_T - DOOR_PANEL_RAISE, y0 - DOOR_T + 0.05, 'door', bevel=0.12)
panel.parent = door
panel.matrix_parent_inverse = door.matrix_world.inverted()
hwid, hht, hx, hz, hdep = HANDLE
cut(door, [extrude('Cut', rrect(hwid, hht, hwid / 2 - 0.01, hx, hz), 'xz', y0 - DOOR_T - 1, y0 - DOOR_T + hdep, 'door')])
cut(panel, [extrude('Cut', rrect(hwid + 0.6, hht + 0.6, hwid / 2, hx, hz), 'xz', y0 - DOOR_T - 2, y0, 'door')])

# --- Controls --------------------------------------------------------------------------------------
for i, (kx, kz, kd, kdep) in enumerate(KNOBS):
    r = kd / 2
    if kd > 2:   # printed dial ring behind the big cycle knobs
        ring = extrude('05b_Dial_Ring_%d' % i, rrect(kd + 2 * DIAL_RING, kd + 2 * DIAL_RING, r + DIAL_RING, kx, kz, 12),
                       'xz', y0 - 0.02, y0 + 0.01, 'dial')
        cut(ring, [extrude('Cut', rrect(kd + 0.2, kd + 0.2, r + 0.1, kx, kz, 12), 'xz', y0 - 1, y0 + 1, 'dial')])
    knob = lathe('05_Knob_%d' % i, [(r, 0), (r, kdep * 0.25), (r * 0.92, kdep * 0.3), (r * 0.9, kdep), (0, kdep)],
                 (kx, y0, kz), (0, -1, 0), 'knob')
    # grip bar across the knob face
    boxo('05c_Knob_Grip_%d' % i, (kx - 0.12, kx + 0.12), (y0 - kdep - 0.25, y0 - kdep + 0.05), (kz - r * 0.85, kz + r * 0.85), 'knob')

# --- Back connections -------------------------------------------------------------------------------
vd, vl, vx, vz = VENT
lathe('06_Dryer_Vent', [(vd / 2, 0), (vd / 2, vl), (vd / 2 - 0.05, vl), (vd / 2 - 0.05, 0)], (vx, D, vz), (0, 1, 0), 'vent')
MATS.update({'galv': material('vent', 0.9, 0.45), 'block': material('plug', 0.0, 0.5),
             'green_screw': None})
for key, colour in (('ins_black', (0.02, 0.02, 0.02)), ('ins_white', (0.88, 0.88, 0.86)),
                    ('ins_red', (0.70, 0.04, 0.03)), ('ins_green', (0.05, 0.45, 0.25)), ('green_screw', (0.08, 0.45, 0.14))):
    COLORS[key] = colour
    MATS[key] = material(key, 0.0, 0.35)


def set_origin(obj, p_in):
    c = Vector(p_in) * IN
    obj.data.transform(Matrix.Translation(-c))
    obj.location = c
    return obj


def pan_screw(name, base, axis, r, h, mat):
    """Pan-head screw with a slot, seated at base (inches) facing along axis."""
    s = lathe(name, [(r, 0), (r, h * 0.45), (r * 0.8, h), (0, h * 1.05)], base, axis, mat, seg=20)
    a = Vector(axis).normalized()
    side = a.orthogonal().normalized()
    up = a.cross(side)
    c = Vector(base) + a * h
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(r * 2.2, 0.06, h * 1.1), verts=bm.verts)
    rot = Matrix((side, up, a)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c * IN) @ rot @ Matrix.Scale(IN, 4), verts=bm.verts[:])
    cutter = to_obj('Cut', bm, mat)
    cut(s, [cutter])
    return set_origin(s, base)


pw, ph, pd = POCKET
pcx, pcz = POCKET_C
cut(dryer, [boxo('Cut', (pcx - pw / 2, pcx + pw / 2), (D - pd, D + 1), (pcz - ph / 2, pcz + ph / 2), 'enamel')])

# Terminal block: black phenolic with barriers between three brass screws.
bw_, bh_, bs_ = BLOCK
floor = D - pd
face_y = floor + bs_
boxo('07_Terminal_Block', (pcx - bw_ / 2, pcx + bw_ / 2), (floor, face_y), (BLOCK_Z - bh_ / 2, BLOCK_Z + bh_ / 2), 'block')
for bx in (TERM_X[0] + 0.5, TERM_X[1] + 0.5):
    boxo('07_Block_Barrier', (bx - 0.05, bx + 0.05), (face_y - 0.01, face_y + 0.3), (BLOCK_Z - bh_ / 2, BLOCK_Z + bh_ / 2), 'block')
for i, tx in enumerate(TERM_X):
    pan_screw('07b_Terminal_Screw_%s' % ('L1', 'N', 'L2')[i], (tx, face_y + 0.035, BLOCK_Z), (0, 1, 0), 0.2, 0.14, 'brass')
gx, gz = GROUND_AT
pan_screw('07c_Ground_Screw', (gx, floor + 0.035, gz), (0, 1, 0), 0.2, 0.14, 'green_screw')


def ring_terminal(name, centre, seat_y, mat_ins):
    """Ring tongue flat under a screw at centre (x, z), with its crimp barrel below it."""
    x, z = centre
    ring = lathe(name + '_Ring', [(0.22, 0), (0.22, 0.03), (0.11, 0.03), (0.11, 0)], (x, seat_y, z), (0, 1, 0), 'brass', seg=20)
    boxo(name + '_Neck', (x - 0.09, x + 0.09), (seat_y, seat_y + 0.03), (z - 0.42, z - 0.2), 'brass')
    barrel = lathe(name + '_Barrel', [(0.13, 0), (0.13, 0.45), (0.11, 0.5)], (x, seat_y + 0.13, z - 0.42), (0, 0, -1), 'brass', seg=16)
    return Vector((x, seat_y + 0.13, z - 0.92))          # where the insulated conductor enters the barrel


# Cord: up the back panel, through the clamp, into the pocket; jacket stripped inside.
R = CORD_D / 2
jacket_end = Vector((CORD_X, floor + 0.65, JACKET_END_Z))
px_, pdy, pz_ = PLUG_AT
plug_c = Vector((px_, D + pdy, pz_))
boot_top = plug_c + Vector((0, 0, 2.95))
upper = [jacket_end, Vector((CORD_X, D - 0.25, 41.9)), Vector((CORD_X, D + R, 41.0)),
         Vector((CORD_X, D + R, CLAMP_Z)), Vector((CORD_X, D + R, 38.8))]
if boot_top.z < 20:      # hanging down to the floor
    lower = [Vector((CORD_X + 0.6, D + 2.4, 30)), Vector((px_ - 0.4, D + 5.0, 14)), Vector((px_, plug_c.y, 8.5))]
else:                    # plugged into a receptacle behind the unit: a loose loop down and over to it
    lower = [Vector(((CORD_X + px_) / 2, (D + R + plug_c.y) / 2 + 0.3, (38.8 + boot_top.z) / 2 - 0.8)),
             boot_top + Vector((0, 0, 1.2))]      # a gentle sag from the clamp down into the plug's boot
cord_pts = smooth_path(upper + lower + [boot_top], n=10)
tube('07d_Dryer_Cord_10-4', cord_pts, R, 'cord', seg=16)

# Conductors fanning out from the jacket end to their screws.
fan = {'ins_black': (-0.15, 0.05), 'ins_white': (-0.05, -0.05), 'ins_red': (0.05, 0.05), 'ins_green': (0.15, -0.05)}
targets = {'ins_black': (TERM_X[0], BLOCK_Z, face_y), 'ins_white': (TERM_X[1], BLOCK_Z, face_y),
           'ins_red': (TERM_X[2], BLOCK_Z, face_y), 'ins_green': (gx, gz, floor)}
for key, (tx, tz, seat) in targets.items():
    entry = ring_terminal('07e_%s' % key.split('_')[1].title(), (tx, tz), seat + 0.005, key)
    ox, oy = fan[key]
    s0 = jacket_end + Vector((ox, oy, 0))
    mid = Vector(((s0.x + entry.x) / 2, (s0.y + entry.y) / 2, (s0.z + entry.z) / 2 - 0.25))
    tube('07f_Conductor_%s' % key.split('_')[1].title(), smooth_path([s0 - Vector((0, 0, 0.1)), s0 + Vector((0, 0, 0.35)), mid, entry,
                                                                     entry + Vector((0, 0, 0.12))], n=8), COND_R, key, seg=10)

# Strain-relief clamp: a galvanized saddle over the cord, ears screwed to the panel.
t = 0.04
rs = R + t / 2
cl = []
for k in range(13):
    a = math.pi - math.pi * k / 12
    cl.append((CORD_X + rs * math.cos(a), D + R + rs * math.sin(a)))
pathc = [(CORD_X - 0.95, D + t / 2), (CORD_X - rs, D + t / 2)] + cl + [(CORD_X + rs, D + t / 2), (CORD_X + 0.95, D + t / 2)]
outer, inner = [], []
for i, (x, y) in enumerate(pathc):
    a_ = Vector(pathc[max(i - 1, 0)]); b_ = Vector(pathc[min(i + 1, len(pathc) - 1)])
    d_ = (b_ - a_).normalized()
    nrm = Vector((-d_.y, d_.x))
    outer.append(tuple(Vector((x, y)) + nrm * t / 2))
    inner.append(tuple(Vector((x, y)) - nrm * t / 2))
extrude('07g_Strain_Relief_Clamp', outer + list(reversed(inner)), 'xy', CLAMP_Z - 0.25, CLAMP_Z + 0.25, 'galv')
for ex in (CORD_X - 0.7, CORD_X + 0.7):
    pan_screw('07h_Clamp_Screw', (ex, D + t, CLAMP_Z), (0, 1, 0), 0.14, 0.1, 'galv')

# Right-angle 14-30P: molded head (face toward the wall, +Y), cord boot off the top, brass blades.
head = [(math.cos(a) * 1.3 * (1 - 0.12 * math.sin(a)), math.sin(a) * 1.3) for a in (math.tau * i / 32 for i in range(32))]
extrude('08_Plug_14-30P', [(plug_c.x + x, plug_c.z + z) for x, z in head], 'xz', plug_c.y - 0.55, plug_c.y + 0.5, 'plug', bevel=0.12)
lathe('08a_Plug_Boot', [(0.62, 0), (0.6, 0.5), (0.45, 1.3), (R + 0.04, 1.75), (R + 0.04, 1.8)],
      plug_c + Vector((0, -0.05, 1.0)), (0, 0, 1), 'plug', seg=24)
fy = plug_c.y + 0.5
# Blade layout matches the 14-30R's slots (receptacle_14_30.py, from the NEMA face diagram), so
# the plug really mates. Positions are as seen looking at the receptacle: X hot right, Y hot
# left, the neutral a "┐" (arm across the top, stem down on the right), round ground on top.
bt = 0.065
for name, bx in (('X', 0.758), ('Y', -0.758)):
    boxo('08b_Blade_' + name, (plug_c.x + bx - bt / 2, plug_c.x + bx + bt / 2), (fy - 0.05, fy + 0.75),
         (plug_c.z - 0.34, plug_c.z + 0.16), 'blade')
boxo('08b_Blade_W_Arm', (plug_c.x - 0.217, plug_c.x + 0.32), (fy - 0.05, fy + 0.75),
     (plug_c.z - 0.583 - bt / 2, plug_c.z - 0.583 + bt / 2), 'blade')
boxo('08b_Blade_W_Stem', (plug_c.x + 0.287 - bt / 2, plug_c.x + 0.287 + bt / 2), (fy - 0.05, fy + 0.75),
     (plug_c.z - 1.06, plug_c.z - 0.583), 'blade')
lathe('08c_Ground_Pin', [(0.125, 0), (0.125, 0.72), (0.07, 0.78), (0, 0.8)], (plug_c.x, fy - 0.05, plug_c.z + 0.73), (0, 1, 0), 'blade', seg=12)

# Access cover over the pocket: hinged on its bottom edge, one captive screw at the top.
cw_, ch_, ct_ = COVER
cb = pcz - ch_ / 2
cover = extrude('09_Access_Cover', rrect(cw_, ch_, 0.3, pcx, pcz), 'xz', D, D + ct_, 'galv',
                origin=(pcx, D + ct_ / 2, cb))
nw, nh = COVER_NOTCH
cut(cover, [extrude('Cut', rrect(nw, nh * 2, nw / 2 - 0.01, CORD_X, cb), 'xz', D - 1, D + 1, 'galv')])
screw = pan_screw('09b_Cover_Screw', (pcx, D + ct_, cb + ch_ - 0.35), (0, 1, 0), 0.18, 0.12, 'galv')
screw.parent = cover
screw.matrix_parent_inverse = cover.matrix_world.inverted()
swing = -math.radians(COVER_SWING)
if ACCESS_OPEN:
    screw.location.y += 0.35 * IN
    cover.rotation_euler.x = swing

if ANIMATE and not ACCESS_OPEN:
    # Open_Access: the screw spins out, then the cover swings down on its bottom edge.
    s_loc = screw.location.y
    for f, out, turns in ((1, 0, 0), (12, 0.35, 4)):
        screw.location.y = s_loc + out * IN
        screw.rotation_euler.y = turns * math.tau
        screw.keyframe_insert('location', index=1, frame=f)
        screw.keyframe_insert('rotation_euler', index=1, frame=f)
    for f, ang in ((1, 0), (14, 0), (32, swing)):
        cover.rotation_euler.x = ang
        cover.keyframe_insert('rotation_euler', index=0, frame=f)
    for obj in (screw, cover):
        ad = obj.animation_data
        act = ad.action
        act.name = 'Open_Access_' + obj.name
        track = ad.nla_tracks.new()
        track.name = 'Open_Access'
        strip = track.strips.new('Open_Access', 1, act)
        if hasattr(strip, 'action_slot') and act.slots:
            strip.action_slot = act.slots[0]
        strip.extrapolation = 'HOLD_FORWARD'
        ad.action = None
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 1, 45
    scene.timeline_markers.new('Unscrew', frame=1)
    scene.timeline_markers.new('Cover open', frame=32)
    scene.frame_set(1)

for i, (ix, iz, colour) in enumerate(INLETS):
    lathe('09_Water_Inlet_%d' % i, [(0.45, 0), (0.45, 0.4), (0.38, 0.4), (0.38, 1.3), (0, 1.3)], (ix, D, iz), (0, 1, 0), 'brass')
    tab = boxo('09b_Inlet_Tag_%d' % i, (ix - 0.35, ix + 0.35), (D, D + 0.08), (iz + 0.7, iz + 1.2), 'knob')
    m = bpy.data.materials.get('Laundry_Inlet_Tag_%d' % i) or bpy.data.materials.new('Laundry_Inlet_Tag_%d' % i)
    m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*colour, 1)
    tab.data.materials[0] = m
dx, dz2 = DRAIN
drain = smooth_path([Vector((dx, D, dz2)), Vector((dx, D + 1.5, dz2 + 0.5)), Vector((dx + 1, D + 4, dz2 - 6)),
                     Vector((dx + 2, D + 5, dz2 - 18))])
tube('10_Drain_Hose', drain, 0.55, 'hose')

print('Built laundry center: %d parts.' % (len(col.objects) - 1))
