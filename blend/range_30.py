"""30" freestanding electric range: smooth glass cooktop, steel backguard with four knobs and a
display, black glass oven door with a steel handle bar, steel storage drawer. Measured from the
straight-on product photo (13.07 px/in, from the 30" body width) and the listing's diagram
(47.25" tall to the top of the backguard, 27.875" deep, 30" wide). Brand logos are left off.
The back (receptacle recess, terminal block, 50 A cord and 14-50P plug) isn't in the photos
and follows standard practice for a 4-wire range hookup.

INCHES below. World: X = width (+X to the right, looking at the front), Y = depth (door front
at Y = 0, back toward +Y), Z = up from the floor; one inch = 0.0254 m. The oven door (pivot on
its bottom hinge line), storage drawer and terminal cover are their own objects, ready to
animate. Safe to re-run.

    blender --background --python blend/range_30.py
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

IN = 0.0254
COLLECTION_NAME = globals().get('COLLECTION_NAME', 'Range_30')

# --- Cabinet -------------------------------------------------------------------------------------
W, D, H = 30.0, 27.875, 47.25
BODY_FRONT = 1.2              # cabinet front, behind the door and drawer
FOOT_H = 0.9                  # leveling legs: height showing under the cabinet
SIDE_PANELS = [(3.0, 9.5), (10.0, 16.5), (17.0, 24.5)]   # embossed panels on each side (y from, to)...
SIDE_PANEL_Z = (2.5, 33.0)    # ...this tall
SIDE_PANEL_RAISE = 0.06

# --- Cooktop (photo: front edge of the glass at px row 181 = 36") -------------------------------
COOKTOP_Z = 36.0
GLASS_T = 0.25
GLASS_Y = (-0.35, 23.4)       # front overhang, back edge (meets the rear riser)
FRONT_TRIM_Z = 34.25          # black frame under the glass front edge
# Elements, printed rings on the glass: x, y (back from the front edge), ring diameters.
ELEMENTS = [(-8.7, 6.5, (8.2,)), (6.7, 6.5, (9.4, 6.0)), (-9.9, 16.5, (6.0,)), (9.9, 16.5, (6.0,))]
RING_W = 0.07

# --- Oven door, handle bar, drawer --------------------------------------------------------------
DOOR_Z = (11.1, 31.6)         # black glass door, bottom to top
DOOR_T = 1.2
DOOR_SIDE_GAP = 0.15
WINDOW = (19.1, 11.2, 22.7)   # smoked window in the door: width, height, centre height
WINDOW_INSET = 0.06
BAR = [(-1.6, 31.7), (-1.6, 33.2), (0.2, 34.15), (0.2, 31.5)]   # handle bar profile (y, z), full width
BAR_SLOTS = [(-9.3, -7.8), (-5.8, -3.6), (-3.2, -1.1), (1.1, 3.2), (3.7, 5.7), (7.9, 9.3)]   # vent slots (x from, to)
BAR_SLOT_ROWS = (0.3, 0.75)   # two rows, this far up the bar's sloped top from its front edge
BAR_SLOT_W = 0.22
BAR_END_SLOTS = 4             # small slots in each end of the bar
DRAWER_Z = (FOOT_H, 10.1)     # steel storage drawer front
DRAWER_T = 0.8
DOOR_OPEN = globals().get('DOOR_OPEN', 0.0)       # degrees the oven door is dropped open
DRAWER_OPEN = globals().get('DRAWER_OPEN', 0.0)   # inches the drawer is pulled out

# --- Backguard (leaning steel face, black end caps) ---------------------------------------------
RISER_Z = 38.6                # black riser behind the glass, up to the steel
GUARD = [(23.6, RISER_Z), (25.3, H), (D, H), (D, RISER_Z)]   # steel profile (y, z): leans back as it rises
GUARD_CAP_T = 0.4
KNOBS = [-12.8, -9.9, 9.9, 12.8]   # knob centres (x), photo
KNOB_Z = 43.0
KNOB = (2.0, 1.1)             # diameter, depth
DISPLAY = (10.2, 2.6, 43.4)   # width, height, centre height
DISPLAY_TEXT = globals().get('DISPLAY_TEXT', '12:00')

# --- Back: receptacle recess, terminal block, cord (standard practice) -------------------------
RECESS = (-13.5, 4.5, 4.0, 11.5)       # open pocket at the lower back for the plug: x from, to, depth, top
POCKET = (6.0, 5.0, 1.3)               # terminal-block pocket: width, height, depth...
POCKET_C = (-4.5, 15.0)                # ...centre (x, z)
BLOCK = (4.2, 1.2, 0.7)                # terminal block: width, height, stand-off
BLOCK_Z = 15.7
TERM_X = (-5.75, -4.5, -3.25)          # L1 (black), N (white), L2 (red)
GROUND_AT = (-6.9, 13.6)               # green ground screw on the pocket floor
CORD_X = -3.0                          # cord comes up the back into the pocket here
CORD_D = 0.78                          # 50 A range cord (6-3 + 8)
COND_R = 0.14                          # each insulated #6 conductor
JACKET_END_Z = 13.4
CLAMP_Z = 11.95                        # strain-relief clamp just below the pocket
PLUG_AT = globals().get('PLUG_AT', (-4.5, 0.1, 5.5))    # plug head centre: x, distance out from the back, height
                                       # (house_framing.py sets it to line up with the 14-50R it plugs into)
COVER = (6.6, 5.6, 0.04)               # access cover over the pocket
COVER_NOTCH = (1.15, 1.6)
ACCESS_OPEN = globals().get('ACCESS_OPEN', False)
ANIMATE = globals().get('ANIMATE', True)            # build the Open_Access animation
COVER_SWING = 105.0

COLORS = {
    'steel': (0.60, 0.60, 0.59), 'paint': (0.025, 0.025, 0.027), 'glass': (0.008, 0.008, 0.009),
    'window': (0.035, 0.036, 0.04), 'ring': (0.22, 0.22, 0.22), 'knob': (0.02, 0.02, 0.022),
    'slot': (0.005, 0.005, 0.005), 'digits': (0.85, 0.92, 1.0), 'back': (0.45, 0.46, 0.47),
    'rubber': (0.03, 0.03, 0.03), 'cord': (0.10, 0.10, 0.11), 'plug': (0.08, 0.08, 0.09),
    'blade': (0.75, 0.62, 0.35), 'brass': (0.78, 0.58, 0.24), 'galv': (0.70, 0.71, 0.72),
}

# --- Setup ---------------------------------------------------------------------------------------
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
root = bpy.data.objects.new('Range_Root', None)
root.empty_display_size = 0.3
col.objects.link(root)


def material(key, metallic=0.0, rough=0.35, emit=None):
    name = 'Range_' + key.capitalize()
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*COLORS[key], 1)
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*COLORS[key], 1)
    b.inputs['Metallic'].default_value = metallic
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*COLORS[key], 1)
        b.inputs['Emission Strength'].default_value = emit
    if key == 'steel':    # brushed: fine streaks running across the width
        coord = nt.nodes.new('ShaderNodeTexCoord')
        squash = nt.nodes.new('ShaderNodeVectorMath')
        squash.operation = 'MULTIPLY'
        squash.inputs[1].default_value = (0.01, 1.0, 1.0)
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = 4000.0
        n.inputs['Detail'].default_value = 4
        ramp = nt.nodes.new('ShaderNodeMapRange')
        ramp.inputs['To Min'].default_value = 0.22
        ramp.inputs['To Max'].default_value = 0.36
        bump = nt.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = 0.08
        bump.inputs['Distance'].default_value = 0.0001
        L = nt.links.new
        L(coord.outputs['Object'], squash.inputs[0])
        L(squash.outputs['Vector'], n.inputs['Vector'])
        L(n.outputs['Fac'], ramp.inputs['Value'])
        L(ramp.outputs['Result'], b.inputs['Roughness'])
        L(n.outputs['Fac'], bump.inputs['Height'])
        L(bump.outputs['Normal'], b.inputs['Normal'])
    if key in ('glass', 'window'):
        b.inputs['Coat Weight'].default_value = 1.0
        b.inputs['Coat Roughness'].default_value = 0.02
    return mat


MATS = {
    'steel': material('steel', 1.0, 0.3), 'paint': material('paint', 0.0, 0.35), 'glass': material('glass', 0.0, 0.05),
    'window': material('window', 0.0, 0.08), 'ring': material('ring', 0.0, 0.3), 'knob': material('knob', 0.0, 0.3),
    'slot': material('slot', 0.0, 0.9), 'digits': material('digits', 0.0, 0.5, emit=3.0), 'back': material('back', 0.85, 0.45),
    'rubber': material('rubber', 0.0, 0.8), 'cord': material('cord', 0.0, 0.55), 'plug': material('plug', 0.0, 0.5),
    'blade': material('blade', 1.0, 0.3), 'brass': material('brass', 1.0, 0.35), 'galv': material('galv', 0.9, 0.45),
}
MATS['block'] = MATS['plug']
for key, colour in (('ins_black', (0.02, 0.02, 0.02)), ('ins_white', (0.88, 0.88, 0.86)),
                    ('ins_red', (0.70, 0.04, 0.03)), ('ins_green', (0.05, 0.45, 0.25)), ('green_screw', (0.08, 0.45, 0.14))):
    COLORS[key] = colour
    MATS[key] = material(key, 0.0, 0.35)


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



def ring_terminal(name, centre, seat_y, mat_ins):
    """Ring tongue flat under a screw at centre (x, z), with its crimp barrel below it."""
    x, z = centre
    ring = lathe(name + '_Ring', [(0.22, 0), (0.22, 0.03), (0.11, 0.03), (0.11, 0)], (x, seat_y, z), (0, 1, 0), 'brass', seg=20)
    boxo(name + '_Neck', (x - 0.09, x + 0.09), (seat_y, seat_y + 0.03), (z - 0.42, z - 0.2), 'brass')
    barrel = lathe(name + '_Barrel', [(0.13, 0), (0.13, 0.45), (0.11, 0.5)], (x, seat_y + 0.13, z - 0.42), (0, 0, -1), 'brass', seg=16)
    return Vector((x, seat_y + 0.13, z - 0.92))          # where the insulated conductor enters the barrel


def parent_to(child, parent):
    bpy.context.view_layer.update()           # parent's matrix_world must be current
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def flat_quad(name, corners, mat):
    """A single thin decal quad (four inch points), nudged along its normal."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(c) * IN) for c in corners]
    bm.faces.new(vs)
    return to_obj(name, bm, mat)


hw = W / 2

# --- Cabinet ---------------------------------------------------------------------------------------
body = boxo('01_Cabinet', (-hw, hw), (BODY_FRONT, D), (FOOT_H, FRONT_TRIM_Z), 'paint', bevel=0.12)
rx0, rx1, rdep, rtop = RECESS
cut(body, [boxo('Cut', (rx0, rx1), (D - rdep, D + 1), (FOOT_H - 1, rtop), 'paint')])
backp = boxo('01b_Back_Panel', (-hw + 0.3, hw - 0.3), (D - 0.03, D), (FOOT_H + 0.2, RISER_Z - 0.3), 'back')
pw, ph, pd = POCKET
pcx, pcz = POCKET_C
cut(backp, [boxo('Cut', (rx0, rx1), (D - 1, D + 1), (FOOT_H - 1, rtop), 'back'),
            boxo('Cut', (pcx - pw / 2, pcx + pw / 2), (D - 1, D + 1), (pcz - ph / 2, pcz + ph / 2), 'back')])
cut(body, [boxo('Cut', (pcx - pw / 2, pcx + pw / 2), (D - pd, D + 1), (pcz - ph / 2, pcz + ph / 2), 'paint')])
boxo('01c_Recess_Liner', (rx0 + 0.02, rx1 - 0.02), (D - rdep, D - rdep + 0.03), (FOOT_H, rtop - 0.02), 'back')
for fx in (-hw + 1.5, hw - 1.5):
    for fy in (BODY_FRONT + 1.0, D - 1.5):
        lathe('01d_Leveling_Leg', [(0.55, 0), (0.55, 0.2), (0.3, 0.3), (0.3, FOOT_H + 0.1)], (fx, fy, 0), (0, 0, 1), 'rubber')
for sx in (-1, 1):                                  # embossed panels on the sides
    for y0, y1 in SIDE_PANELS:
        x = sx * hw
        boxo('01e_Side_Panel', tuple(sorted((x, x + sx * SIDE_PANEL_RAISE))), (y0, y1), SIDE_PANEL_Z, 'paint', bevel=0.03)

# --- Cooktop -----------------------------------------------------------------------------------------
gy0, gy1 = GLASS_Y
boxo('02_Front_Trim', (-hw, hw), (gy0, BODY_FRONT + 1.0), (FRONT_TRIM_Z, COOKTOP_Z - GLASS_T), 'paint', bevel=0.08)
boxo('02b_Cooktop_Glass', (-hw, hw), (gy0, gy1), (COOKTOP_Z - GLASS_T, COOKTOP_Z), 'glass', bevel=0.06)
boxo('02c_Cooktop_Pan', (-hw + 0.2, hw - 0.2), (BODY_FRONT, gy1), (FRONT_TRIM_Z - 0.02, COOKTOP_Z - GLASS_T), 'paint')
for i, (ex, ey, rings) in enumerate(ELEMENTS):
    for k, dia in enumerate(rings):
        r0, r1 = dia / 2 - RING_W / 2, dia / 2 + RING_W / 2
        ring = extrude('02d_Element_%d_Ring_%d' % (i, k), [(ex + r1 * math.cos(math.tau * j / 64), gy0 + ey + r1 * math.sin(math.tau * j / 64))
                                                          for j in range(64)], 'xy', COOKTOP_Z, COOKTOP_Z + 0.004, 'ring')
        cut(ring, [extrude('Cut', [(ex + r0 * math.cos(math.tau * j / 64), gy0 + ey + r0 * math.sin(math.tau * j / 64))
                                   for j in range(64)], 'xy', COOKTOP_Z - 1, COOKTOP_Z + 1, 'ring')])

# --- Oven door (pivot on its bottom front edge, the hinge line) --------------------------------------
dz0, dz1 = DOOR_Z
dxh = hw - DOOR_SIDE_GAP
door = boxo('03_Oven_Door', (-dxh, dxh), (0, DOOR_T), (dz0, dz1), 'glass', bevel=0.1, origin=(0, 0, dz0))
ww, wh, wz = WINDOW
win = boxo('03b_Door_Window', (-ww / 2, ww / 2), (-0.004, WINDOW_INSET), (wz - wh / 2, wz + wh / 2), 'window', bevel=0.03)
parent_to(win, door)
bar = extrude('03c_Handle_Bar', BAR, 'yz', -dxh, dxh, 'steel', bevel=0.15)
parent_to(bar, door)
(fy_, fz_), (ty_, tz_) = BAR[1], BAR[2]                 # sloped top: front edge -> back edge
slope = Vector((0, ty_ - fy_, tz_ - fz_))
up_n = Vector((0, -slope.z, slope.y)).normalized()     # its outward normal
for row in BAR_SLOT_ROWS:
    for x0, x1 in BAR_SLOTS:
        s0 = Vector((0, fy_, fz_)) + slope.normalized() * row + up_n * 0.004
        s1 = s0 + slope.normalized() * BAR_SLOT_W
        q = flat_quad('03d_Bar_Slot', [(x0, s0.y, s0.z), (x1, s0.y, s0.z), (x1, s1.y, s1.z), (x0, s1.y, s1.z)], 'slot')
        parent_to(q, door)
for sx in (-1, 1):                                       # little slots in each end of the bar
    for k in range(BAR_END_SLOTS):
        z = 31.95 + k * 0.32
        x = sx * (dxh + 0.004)
        q = flat_quad('03e_Bar_End_Slot', [(x, -1.35, z), (x, -0.45, z), (x, -0.45, z + 0.16), (x, -1.35, z + 0.16)], 'slot')
        parent_to(q, door)
door.rotation_euler.x = math.radians(DOOR_OPEN)
drawer = boxo('04_Storage_Drawer', (-dxh, dxh), (0, DRAWER_T), (DRAWER_Z[0] + 0.1, DRAWER_Z[1]), 'steel', bevel=0.1,
              origin=(0, 0, DRAWER_Z[0]))
drawer.location.y -= DRAWER_OPEN * IN

# --- Backguard ------------------------------------------------------------------------------------------
boxo('05_Rear_Riser', (-hw, hw), (gy1, D), (COOKTOP_Z - GLASS_T, RISER_Z), 'paint', bevel=0.08)
extrude('05b_Backguard', GUARD, 'yz', -hw + GUARD_CAP_T, hw - GUARD_CAP_T, 'steel', bevel=0.12)
for sx in (-1, 1):
    a, b = sorted((sx * (hw - GUARD_CAP_T), sx * hw))
    extrude('05c_Backguard_End_Cap', GUARD, 'yz', a, b, 'paint', bevel=0.1)
(gy_a, gz_a), (gy_b, gz_b) = GUARD[0], GUARD[1]
lean = math.atan2(gy_b - gy_a, gz_b - gz_a)
FACE_M = Matrix.Translation(Vector((0, gy_a, gz_a)) * IN) @ Matrix.Rotation(-lean, 4, 'X')   # face frame: x, z up the face, -y out


def on_face(obj):
    obj.matrix_world = FACE_M @ obj.matrix_world
    return obj


kz = (KNOB_Z - gz_a) / math.cos(lean)
kd, kdep = KNOB
for i, kx in enumerate(KNOBS):
    r = kd / 2
    on_face(lathe('05d_Knob_%d' % i, [(r * 0.98, 0), (r, 0.15), (r, kdep * 0.45), (r * 0.9, kdep * 0.55), (r * 0.82, kdep), (0, kdep)],
                  (kx, 0, kz), (0, -1, 0), 'knob'))
    on_face(boxo('05e_Knob_Grip_%d' % i, (kx - 0.14, kx + 0.14), (-kdep - 0.3, -kdep + 0.05), (kz - r * 0.8, kz + r * 0.8), 'knob', bevel=0.05))
dw_, dh_, dzc = DISPLAY
dz = (dzc - gz_a) / math.cos(lean)
on_face(boxo('05f_Display', (-dw_ / 2, dw_ / 2), (-0.05, 0.01), (dz - dh_ / 2, dz + dh_ / 2), 'glass', bevel=0.03))
curve = bpy.data.curves.new('Range_Display_Text', 'FONT')
curve.body = DISPLAY_TEXT
curve.size = 0.75 * IN
curve.align_x, curve.align_y = 'CENTER', 'CENTER'
curve.extrude = 0.004 * IN
curve.materials.append(MATS['digits'])
digits = bpy.data.objects.new('05g_Display_Digits', curve)
col.objects.link(digits)
digits.parent = root
digits.matrix_world = Matrix.Translation(Vector((0, -0.06, dz)) * IN) @ Matrix.Rotation(math.pi / 2, 4, 'X')
on_face(digits)

# --- Terminal block in the back pocket -------------------------------------------------------------------
bw_, bh_, bs_ = BLOCK
floor = D - pd
face_y = floor + bs_
boxo('06_Terminal_Block', (pcx - bw_ / 2, pcx + bw_ / 2), (floor, face_y), (BLOCK_Z - bh_ / 2, BLOCK_Z + bh_ / 2), 'block')
for bx in ((TERM_X[0] + TERM_X[1]) / 2, (TERM_X[1] + TERM_X[2]) / 2):
    boxo('06_Block_Barrier', (bx - 0.06, bx + 0.06), (face_y - 0.01, face_y + 0.35), (BLOCK_Z - bh_ / 2, BLOCK_Z + bh_ / 2), 'block')
for i, tx in enumerate(TERM_X):
    pan_screw('06b_Terminal_Screw_%s' % ('L1', 'N', 'L2')[i], (tx, face_y + 0.035, BLOCK_Z), (0, 1, 0), 0.24, 0.16, 'brass')
gx, gz = GROUND_AT
pan_screw('06c_Ground_Screw', (gx, floor + 0.035, gz), (0, 1, 0), 0.22, 0.15, 'green_screw')

# Cord: from the plug in the recess, out behind the back panel, through the clamp, up into the pocket.
R = CORD_D / 2
jacket_end = Vector((CORD_X, floor + 0.7, JACKET_END_Z))
px_, pdy, pz_ = PLUG_AT
plug_c = Vector((px_, D + pdy, pz_))
boot_top = plug_c + Vector((0, 0, 2.95))
path = [boot_top, boot_top + Vector((0, 0, 0.9)),
        Vector(((px_ + CORD_X) / 2, D + R * 0.6, min(rtop - 0.4, boot_top.z + 1.8))),
        Vector((CORD_X, D + R, CLAMP_Z - 0.7)), Vector((CORD_X, D + R, CLAMP_Z)),
        Vector((CORD_X, D + R, CLAMP_Z + 0.55)), Vector((CORD_X, D - 0.3, pcz - ph / 2 + 0.6)), jacket_end]
tube('06d_Range_Cord_50A', smooth_path(path, n=10), R, 'cord', seg=16)

fan = {'ins_black': (-0.2, 0.06), 'ins_white': (-0.07, -0.06), 'ins_red': (0.07, 0.06), 'ins_green': (0.2, -0.06)}
targets = {'ins_black': (TERM_X[0], BLOCK_Z, face_y), 'ins_white': (TERM_X[1], BLOCK_Z, face_y),
           'ins_red': (TERM_X[2], BLOCK_Z, face_y), 'ins_green': (gx, gz, floor)}
for key, (tx, tz, seat) in targets.items():
    entry = ring_terminal('06e_%s' % key.split('_')[1].title(), (tx, tz), seat + 0.005, key)
    ox, oy = fan[key]
    s0 = jacket_end + Vector((ox, oy, 0))
    mid = Vector(((s0.x + entry.x) / 2, (s0.y + entry.y) / 2, (s0.z + entry.z) / 2 - 0.2))
    tube('06f_Conductor_%s' % key.split('_')[1].title(),
         smooth_path([s0 - Vector((0, 0, 0.1)), s0 + Vector((0, 0, 0.3)), mid, entry, entry + Vector((0, 0, 0.12))], n=8),
         COND_R, key, seg=10)

# Strain-relief clamp: a galvanized saddle over the cord, ears screwed to the back panel.
t = 0.045
rs = R + t / 2
arc = [(CORD_X + rs * math.cos(math.pi - math.pi * k / 12), D + R + rs * math.sin(math.pi - math.pi * k / 12)) for k in range(13)]
pathc = [(CORD_X - 1.1, D + t / 2), (CORD_X - rs, D + t / 2)] + arc + [(CORD_X + rs, D + t / 2), (CORD_X + 1.1, D + t / 2)]
outer, inner = [], []
for i, (x, y) in enumerate(pathc):
    a_ = Vector(pathc[max(i - 1, 0)])
    b_ = Vector(pathc[min(i + 1, len(pathc) - 1)])
    d_ = (b_ - a_).normalized()
    nrm = Vector((-d_.y, d_.x))
    outer.append(tuple(Vector((x, y)) + nrm * t / 2))
    inner.append(tuple(Vector((x, y)) - nrm * t / 2))
extrude('06g_Strain_Relief_Clamp', outer + list(reversed(inner)), 'xy', CLAMP_Z - 0.3, CLAMP_Z + 0.3, 'galv')
for ex in (CORD_X - 0.8, CORD_X + 0.8):
    pan_screw('06h_Clamp_Screw', (ex, D + t, CLAMP_Z), (0, 1, 0), 0.15, 0.1, 'galv')

# Right-angle 14-50P: molded head (face toward the wall, +Y), cord boot off the top, brass blades.
# Blade layout matches the 14-50R's slots (receptacle_14_30.py with RATING='14-50', from the NEMA
# face diagram): X hot right, Y hot left as seen looking at the receptacle, straight neutral
# below the middle, round ground on top.
head = [(math.cos(a) * 1.35 * (1 - 0.12 * math.sin(a)), math.sin(a) * 1.4) for a in (math.tau * i / 32 for i in range(32))]
extrude('07_Plug_14-50P', [(plug_c.x + x, plug_c.z + z) for x, z in head], 'xz', plug_c.y - 0.6, plug_c.y + 0.5, 'plug', bevel=0.12)
lathe('07a_Plug_Boot', [(0.7, 0), (0.68, 0.5), (0.52, 1.3), (R + 0.05, 1.75), (R + 0.05, 1.8)],
      plug_c + Vector((0, -0.05, 1.05)), (0, 0, 1), 'plug', seg=24)
fy = plug_c.y + 0.5
bt = 0.065
for name, bx in (('X', 0.758), ('Y', -0.758)):
    boxo('07b_Blade_' + name, (plug_c.x + bx - bt / 2, plug_c.x + bx + bt / 2), (fy - 0.05, fy + 0.75),
         (plug_c.z - 0.34, plug_c.z + 0.16), 'blade')
boxo('07b_Blade_W', (plug_c.x - bt / 2, plug_c.x + bt / 2), (fy - 0.05, fy + 0.75), (plug_c.z - 0.93, plug_c.z - 0.43), 'blade')
lathe('07c_Ground_Pin', [(0.125, 0), (0.125, 0.72), (0.07, 0.78), (0, 0.8)], (plug_c.x, fy - 0.05, plug_c.z + 0.73), (0, 1, 0), 'blade', seg=12)

# Access cover over the pocket: hinged on its bottom edge, one captive screw at the top.
cw_, ch_, ct_ = COVER
cb = pcz - ch_ / 2
cover = extrude('08_Access_Cover', rrect(cw_, ch_, 0.3, pcx, pcz), 'xz', D, D + ct_, 'galv', origin=(pcx, D + ct_ / 2, cb))
nw, nh = COVER_NOTCH
cut(cover, [extrude('Cut', rrect(nw, nh * 2, nw / 2 - 0.01, CORD_X, cb), 'xz', D - 1, D + 1, 'galv')])
screw = pan_screw('08b_Cover_Screw', (pcx, D + ct_, cb + ch_ - 0.4), (0, 1, 0), 0.18, 0.12, 'galv')
parent_to(screw, cover)
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
    scene.frame_set(1)

print('Built range: %d parts.' % (len(col.objects) - 1))
