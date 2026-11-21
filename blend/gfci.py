import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# 15 A tamper-resistant GFCI receptacle (white, decora face), modelled from a 3/4
# product photo; standard NEMA 5-15R / decora dimensions where the
# photo can't be measured. Same conventions as tr270_blockout.py: millimetres, X = width
# (+X = brass/hot side), Z = up, Y = depth with the front toward -Y, origin at the
# strap's centre. Every number is one knob.
#
# Two collections: the GFCI and its LOAD-terminal warning tape (separate, so it can be
# left off where the LOAD terminals are used).
#     blender --background --python blend/gfci.py

COLLECTION_NAME = 'GFCI_Receptacle'
TAPE_COLLECTION = 'GFCI_Load_Tape'
MM = 0.001

# --- Strap (same as the TR270) -------------------------------------------------------
YOKE_H = 106.5
YOKE_W = 19.0
YOKE_T = 1.5
EAR_W = 33.0
EAR_H = 10.9
EAR_CORNER = 1.3
EAR_HOLE_R = 2.2
EAR_HOLE_X = 12.7
EAR_HOLE_INSET = 5.6
NECK_TOP_W = 12.4
NECK_FULL_DOWN = 17.5
RELIEF_SLOT_W = 1.6
RELIEF_SLOT_DOWN = 6.6
MOUNT_SPACING = 83.3
MOUNT_SLOT = (3.8, 6.4)
PLATE_SCREW_Z = 48.4        # tapped holes for a decora wall plate's screws (3-13/16" apart)
PLATE_SCREW_HOLE_R = 1.4

# --- Body -----------------------------------------------------------------------------
BODY = (40.5, 71.0, 31.0)   # charcoal housing: width, height, depth behind the strap
BODY_Z = 0.5                # its centre height (z -35 to +36 in the photo)
BODY_R = 2.0
CAP_H = 7.0                 # the grey cap across the top of the housing
FRONT_COVER = (41.5, 73.0)  # white front cover behind the strap
FRONT_COVER_T = 3.0         # from this far in front of the strap...
FRONT_COVER_BACK = 4.0      # ...to this far behind it

# --- Face (decora) -----------------------------------------------------------------------
FACE = (33.3, 66.7)         # standard decora opening
FACE_R = 1.2
FACE_PROUD = 7.6            # face front, in front of the strap (decora faces stand proud of the wall)
FACE_CHAMFER = 0.5
# Measured off the photo, z from the face centre:
OUTLET_SLOTS_Z = (26.1, -15.6)
OUTLET_GROUND_Z = (14.2, -27.3)
SLOT_X = 6.35
SLOT_W = 1.8
HOT_L = 6.35
NEUTRAL_L = 7.9
SLOT_CORNER = 0.25
GROUND_R = 2.5
GROUND_FLAT = 0.6
OPENING_DEPTH = 3.5
BUTTONS = {'RESET': (5.4, 14.0, 6.0), 'TEST': (-4.3, 14.0, 6.0)}   # z, width, height
BUTTON_PROUD = 0.9
BUTTON_RECESS = 0.4         # gap round each button
LED = (11.8, -30.6, 1.6)    # status light, bottom right of the face: x, z, size
LED_ON = globals().get('LED_ON', True)   # powered: glows green. False: dark (no power)
LED_GLOW = 1.5              # how bright it glows when on

# --- Buttons and states ---------------------------------------------------------------------
TRIPPED = globals().get('TRIPPED', False)   # True: tripped -- RESET popped out, light dark
ANIMATE = globals().get('ANIMATE', True)    # build the Press_Test / Press_Reset animations
BUTTON_TRAVEL = 1.5         # how far a button pushes in
RESET_POP = 2.5             # how far RESET pops out when tripped
FPS = 24
TEST_AT, RESET_AT = 1, 31   # timeline frames where each animation starts (for previewing in Blender)

# --- Terminals ----------------------------------------------------------------------------
TERM_Z = {'LINE': -16.5, 'LOAD': 22.0}
TERM_DEPTH = 9.0            # screw centres behind the strap
TERM_PLATE = (9.0, 0.9)
TERM_THREAD = (2.08, 1.60, 32)
TERM_THREAD_L = 2.2
TERM_HEAD = [(4.2, 0), (4.2, 1.2), (3.8, 2.1), (1.5, 2.4)]
TAPE = (0.15, 12.0)         # LOAD warning tape: thickness, height (wraps from the white cover round the back)
LABEL = (0.12, 15.0, 22.0)  # "GROUND FAULT CIRCUIT INTERRUPTER" sticker: thickness, height, depth
LABEL_Z = 4.0

# --- Ground -------------------------------------------------------------------------------
GREEN_SCREW_Z = -39.0
GREEN_SCREW_DEPTH = 6.0
BRACKET_X = -12.0
BRACKET_T = 1.0
BRACKET_H = 7.0
GREEN_THREAD = (2.4, 2.4)
GREEN_THREAD_SPEC = (2.40, 1.90, 32)
GREEN_WASHER = (3.8, 0.6)
GREEN_HEX = (3.4, 2.0)

# --- Mounting screws ----------------------------------------------------------------------
MOUNT_HEAD = [(3.0, 0), (3.0, 0.6), (2.6, 1.5), (1.6, 2.0)]
MOUNT_SLOT_DEPTH = 0.7
MOUNT_SHANK = (1.75, 17.5)
MOUNT_THREAD = (1.75, 1.30, 32)
MOUNT_PILOT = (0.85, 1.4)

SLOT_GAP = 0.9
THREAD_SEG = 16
TEXT_RAISE = 0.15

COLORS = {
    'yoke': (.52, .54, .57), 'front': (.90, .90, .88), 'housing': (.09, .09, .10),
    'cap': (.30, .31, .33), 'steel': (.90, .91, .92), 'brass': (.78, .58, .24),
    'brass_plate': (.78, .58, .24), 'silver': (.80, .81, .82), 'silver_plate': (.80, .81, .82),
    'green': (.08, .45, .14), 'slot': (.02, .02, .02), 'tape': (.95, .80, .05),
    'label': (.92, .92, .90), 'ink': (.03, .03, .03), 'led': (.0, .55, .06), 'led_off': (.02, .07, .03),
}
SURFACE = {
    'front': (0.0, 0.30, 0.03, 4000), 'housing': (0.0, 0.5, 0.04, 3000), 'cap': (0.0, 0.5, 0.0, 0),
    'yoke': (0.85, 0.45, 0.12, 6000), 'steel': (1.0, 0.18, 0.0, 0), 'brass': (1.0, 0.40, 0.0, 0),
    'silver': (1.0, 0.38, 0.0, 0), 'brass_plate': (1.0, 0.35, 0.0, 0), 'silver_plate': (1.0, 0.32, 0.0, 0),
    'green': (0.3, 0.35, 0.0, 0), 'tape': (0.0, 0.35, 0.0, 0), 'led': (0.0, 0.15, 0.0, 0),
}
GALV_SPANGLE = 700
GALV_TONE = ((.30, .31, .33), (.60, .61, .62))
GALV_CLOUD = 2500
PLATE_DIMPLE = 1000
PLATE_DIMPLE_DEPTH = 1.0

# --- Setup ---------------------------------------------------------------------------------
scene = bpy.context.scene
for cname in (COLLECTION_NAME, TAPE_COLLECTION, 'Decora_Wall_Plate'):   # (the old plate, if a previous run made one)
    old = bpy.data.collections.get(cname)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
for m in list(bpy.data.meshes):
    if m.users == 0:
        bpy.data.meshes.remove(m)


def new_collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    r = bpy.data.objects.new(name + '_Root', None)
    r.empty_display_size = 20 * MM
    c.objects.link(r)
    return c, r


collection, root = new_collection(COLLECTION_NAME)
tape_col, tape_root = new_collection(TAPE_COLLECTION)
yoke_front, yoke_back = -YOKE_T / 2, YOKE_T / 2

def rounded_rect(w, h, r, cx=0.0, cz=0.0, seg=4):
    hw, hh = w / 2, h / 2
    r = min(r, hw, hh)
    pts = []
    for ox, oz, a0 in ((cx + hw - r, cz - hh + r, -90), (cx + hw - r, cz + hh - r, 0),
                       (cx - hw + r, cz + hh - r, 90), (cx - hw + r, cz - hh + r, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            p = (ox + r * math.cos(a), oz + r * math.sin(a))
            # Fully rounded ends (r = half the width) make corners meet: skip repeats,
            # or the boolean cut fails on the zero-length edge.
            if not pts or math.dist(p, pts[-1]) > 1e-6:
                pts.append(p)
    if math.dist(pts[0], pts[-1]) <= 1e-6:
        pts.pop()
    return pts


def circle(cx, cz, r, n=24):
    return [(cx + r * math.cos(math.tau * i / n), cz + r * math.sin(math.tau * i / n)) for i in range(n)]


def get_material(key):
    name = key.capitalize() + '_Material'
    mat = bpy.data.materials.get(name)
    if mat is None:
        color = COLORS[key]
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*color, 1)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        if bsdf:
            bsdf.inputs['Base Color'].default_value = (*color, 1)
    return mat


def prism(name, outline, y0, y1, color=None, chamfer=0.0, centre=(0.0, 0.0)):
    """Pushes an (x, z) outline through depth from y0 (front) to y1 (back).
    A chamfer bevels the front edge in toward `centre`."""
    bm = bmesh.new()
    cx, cz = centre

    def ring(y, inset):
        verts = []
        for x, z in outline:
            dx, dz = x - cx, z - cz
            d = math.hypot(dx, dz)
            s = max(d - inset, 0.0) / d if d > 0 else 1.0
            verts.append(bm.verts.new(((cx + dx * s) * MM, y * MM, (cz + dz * s) * MM)))
        return verts

    rings = [ring(y1, 0.0)]
    if chamfer > 0.0:
        rings += [ring(y0 + chamfer, 0.0), ring(y0, chamfer)]
    else:
        rings.append(ring(y0, 0.0))
    n = len(outline)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    return to_object(name, bm, color)


def to_object(name, bm, color=None):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = root
    if color:
        mesh.materials.append(get_material(color))
        size = [max(v.co[i] for v in mesh.vertices) - min(v.co[i] for v in mesh.vertices) for i in range(3)]
        obj['dimensions_mm_provisional'] = '(%.1f, %.1f, %.1f)' % tuple(s / MM for s in size)
    return obj


def box(name, xs, ys, zs, color=None):
    """A box spanning the given (min, max) ranges, in mm."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = [(lo + hi) / 2 * MM + c * (hi - lo) * MM for c, (lo, hi) in zip(v.co, (xs, ys, zs))]
    return to_object(name, bm, color)


AXES = {    # turns a part built pointing up +Z so it points the given way
    '-Y': Matrix.Rotation(math.pi / 2, 4, 'X'),
    '+X': Matrix.Rotation(math.pi / 2, 4, 'Y'),
    '-X': Matrix.Rotation(-math.pi / 2, 4, 'Y'),
}


def thread(name, spec, length, seat, axis, color, tip=False, seg=None):
    """A helical V-thread, `length` mm long, built up +Z from its seat then turned to
    point along `axis`. With tip=True the seat end gets a chamfered point."""
    major, minor, tpi = spec
    seg = seg or THREAD_SEG
    pitch = 25.4 / tpi
    pilot_r, pilot_l = MOUNT_PILOT
    start = pilot_l + 0.3 if tip else 0.0
    rows = max(int((length - start - pitch) / (pitch / 2)), 2)
    bm = bmesh.new()
    grid = [[bm.verts.new(((major if j % 2 else minor) * math.cos(math.tau * i / seg) * MM,
                           (major if j % 2 else minor) * math.sin(math.tau * i / seg) * MM,
                           (start + j * pitch / 2 + pitch * i / seg) * MM))
             for j in range(rows + 1)] for i in range(seg)]

    def v(i, j):
        if i == seg:                      # one turn round = one pitch up = two rows
            i, j = 0, j + 2
        return grid[i][j] if j <= rows else None

    for i in range(seg):
        for j in range(rows):
            quad = (v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1))
            if all(quad):
                bm.faces.new(quad)
    core = ([(minor * pilot_r * 0.7, 0), (minor * pilot_r, 0.3), (minor * pilot_r, pilot_l), (minor, start)]
            if tip else [(minor, 0)])
    core.append((minor, length))
    rings = [[bm.verts.new((rr * math.cos(math.tau * i / seg) * MM, rr * math.sin(math.tau * i / seg) * MM, h * MM))
              for i in range(seg)] for rr, h in core]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    bmesh.ops.poke(bm, faces=caps)   # fan the flat ends into triangles so slot cuts go through them
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(seat) * MM) @ AXES[axis], verts=bm.verts[:])
    return to_object(name, bm, color)


def revolve(name, profile, seat, axis, color, seg=24):
    """Spins a (radius, height) profile into a round part, its seat at `seat` (mm),
    pointing along `axis`."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(a) * MM, r * math.sin(a) * MM, h * MM))
              for a in (math.tau * i / seg for i in range(seg))] for r, h in profile]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    bmesh.ops.poke(bm, faces=caps)   # fan the flat ends into triangles so slot cuts go through them
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(seat) * MM) @ AXES[axis], verts=bm.verts[:])
    return to_object(name, bm, color)


def cut(obj, outlines, y0, y1):
    """Cuts each outline out of obj, from depth y0 to y1, and bakes the result in."""
    return cut_with(obj, [prism('Cutter', o, y0, y1) for o in outlines])


def cut_with(obj, cutters, operation='DIFFERENCE'):
    """Cuts each cutter object out of obj (or, with 'UNION', merges it in), bakes
    the result in, and deletes the cutters."""
    for c in cutters:
        mod = obj.modifiers.new('Cut', 'BOOLEAN')
        mod.operation = operation
        mod.solver = 'EXACT'
        mod.object = c
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old_mesh = obj.data
    obj.modifiers.clear()
    obj.data = baked
    baked.name = obj.name + '_Mesh'
    bpy.data.meshes.remove(old_mesh)
    for c in cutters:
        m = c.data
        bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.meshes.remove(m)
    return obj


def darken_openings(obj, outlines, y_front, inward=1):
    """Gives the walls and floor of each opening the dark 'slot' material. The openings
    are cut in from the surface at y_front, going +Y (inward=1) or -Y (inward=-1)."""
    mesh = obj.data
    mesh.materials.append(get_material('slot'))
    dark = len(mesh.materials) - 1
    pad = 0.05
    boxes = [(min(x for x, _ in o) - pad, max(x for x, _ in o) + pad,
              min(z for _, z in o) - pad, max(z for _, z in o) + pad) for o in outlines]
    for poly in mesh.polygons:
        x, y, z = (c / MM for c in poly.center)
        if (y - y_front) * inward > pad and any(x0 <= x <= x1 and z0 <= z <= z1 for x0, x1, z0, z1 in boxes):
            poly.material_index = dark


def head_top(profile):
    return profile[-1][1]


def front_screw(name, x, z, head, shank, color, cross):
    """A screw on the yoke's front, its head facing out (-Y), shank running back."""
    obj = revolve(name, head, (x, yoke_front, z), '-Y', color)
    top = yoke_front - head_top(head)
    r = head[0][0] * 0.9
    g = SLOT_GAP / 2
    depth = top + head_top(head) * MOUNT_SLOT_DEPTH
    cutters = [box('Cutter', (x - r, x + r), (top - 1, depth), (z - g, z + g))]
    if cross:
        cutters.append(box('Cutter', (x - g * 1.1, x + g * 1.1), (top - 1, depth), (z - r * 0.7, z + r * 0.7)))
    cut_with(obj, cutters)
    thread(name + '_Shank', MOUNT_THREAD, shank[1], (x, yoke_back + shank[1], z), '-Y', color, tip=True)
    return obj


def side_screw(name, x, y, z, side, head, color):
    """A screw on the body's side, seated at x, its head facing out (side +1 = +X), with a
    combination head: a straight slot running front to back plus a Phillips cross."""
    obj = revolve(name, head, (x, y, z), '+X' if side > 0 else '-X', color)
    h = head_top(head)
    top = x + side * h
    r = max(rr for rr, _ in head) * 0.85
    g = SLOT_GAP / 2
    slot_x = tuple(sorted((top - side * h * 0.4, top + side)))
    cross_x = tuple(sorted((top - side * h * 0.65, top + side)))
    arm, cw = r * 0.62, g * 1.1
    cut_with(obj, [box('Cutter', slot_x, (y - r, y + r), (z - g, z + g)),
                   box('Cutter', cross_x, (y - arm, y + arm), (z - cw, z + cw)),
                   box('Cutter', cross_x, (y - cw, y + cw), (z - arm, z + arm))])
    return obj


FACING = {
    'front': Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))),   # read from the front
    'back': Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))),    # read from behind
}


def molded_text(name, body, size, at, facing, color, turn=0.0, raise_=TEXT_RAISE):
    """Lettering `size` mm tall, centred on `at` (mm, on the surface), standing out
    from it by `raise_`. `turn` rotates it in the surface plane (degrees, CCW)."""
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body, cu.size = body, size * MM
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    cu.extrude = raise_ / 2 * MM
    tmp = bpy.data.objects.new(name + '_Curve', cu)
    collection.objects.link(tmp)
    mesh = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    mesh.name = name + '_Mesh'
    mesh.transform(Matrix.Translation(Vector(at) * MM) @ FACING[facing] @ Matrix.Rotation(math.radians(turn), 4, 'Z')
                   @ Matrix.Translation((0, 0, raise_ / 2 * MM)))
    mesh.materials.append(get_material(color))
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = root
    return obj


def _link(nt, a, b):
    nt.links.new(a, b)


def surface_material(key):
    mat = get_material(key)
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    metallic, rough, bump_s, bump_scale = SURFACE[key]
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    coord = nt.nodes.new('ShaderNodeTexCoord')
    if bump_s:
        noise = nt.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = bump_scale
        noise.inputs['Detail'].default_value = 4
        bump = nt.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = bump_s
        bump.inputs['Distance'].default_value = 0.00005
        _link(nt, coord.outputs['Object'], noise.inputs['Vector'])
        _link(nt, noise.outputs['Fac'], bump.inputs['Height'])
        _link(nt, bump.outputs['Normal'], bsdf.inputs['Normal'])
    if key == 'yoke':       # mottled galvanizing: spangle facets plus a fine cloudy tone
        vor = nt.nodes.new('ShaderNodeTexVoronoi')
        vor.inputs['Scale'].default_value = GALV_SPANGLE
        cloud = nt.nodes.new('ShaderNodeTexNoise')
        cloud.inputs['Scale'].default_value = GALV_CLOUD
        cloud.inputs['Detail'].default_value = 8
        mix = nt.nodes.new('ShaderNodeMath')
        mix.operation = 'MULTIPLY_ADD'
        mix.inputs[1].default_value = 0.5
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].color = (*GALV_TONE[0], 1)
        ramp.color_ramp.elements[1].color = (*GALV_TONE[1], 1)
        _link(nt, coord.outputs['Object'], vor.inputs['Vector'])
        _link(nt, coord.outputs['Object'], cloud.inputs['Vector'])
        _link(nt, vor.outputs['Color'], mix.inputs[0])      # facet tone (uses the red channel)
        _link(nt, cloud.outputs['Fac'], mix.inputs[2])
        _link(nt, mix.outputs['Value'], ramp.inputs['Fac'])
        _link(nt, ramp.outputs['Color'], bsdf.inputs['Base Color'])
    if key.endswith('_plate'):   # a regular grid of little dimples across the plate face
        grid = nt.nodes.new('ShaderNodeVectorMath')
        grid.operation = 'MULTIPLY'
        grid.inputs[1].default_value = (0, PLATE_DIMPLE, PLATE_DIMPLE)   # plates face sideways (X)
        frac = nt.nodes.new('ShaderNodeVectorMath')
        frac.operation = 'FRACTION'
        centre = nt.nodes.new('ShaderNodeVectorMath')
        centre.operation = 'SUBTRACT'
        centre.inputs[1].default_value = (0, 0.5, 0.5)
        vor = nt.nodes.new('ShaderNodeVectorMath')     # distance from each cell's centre
        vor.operation = 'LENGTH'
        dot = nt.nodes.new('ShaderNodeMapRange')       # smooth bowl at each cell centre
        dot.interpolation_type = 'SMOOTHSTEP'
        dot.inputs['From Min'].default_value = 0.10
        dot.inputs['From Max'].default_value = 0.38
        bump = nt.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = PLATE_DIMPLE_DEPTH
        bump.inputs['Distance'].default_value = 0.0002
        _link(nt, coord.outputs['Object'], grid.inputs[0])
        _link(nt, grid.outputs['Vector'], frac.inputs[0])
        _link(nt, frac.outputs['Vector'], centre.inputs[0])
        _link(nt, centre.outputs['Vector'], vor.inputs[0])
        _link(nt, vor.outputs['Value'], dot.inputs['Value'])
        _link(nt, dot.outputs['Result'], bump.inputs['Height'])
        _link(nt, bump.outputs['Normal'], bsdf.inputs['Normal'])
def yoke_outline(seg=6):
    """The strap: an ear at each end with clipped corners and a round hole, a tapered
    neck, and a narrow U-slot between each ear and the neck. Built as the top-right
    quarter, then mirrored."""
    T, ew, c = YOKE_H / 2, EAR_W / 2, EAR_CORNER
    n0, n1 = NECK_TOP_W / 2, YOKE_W / 2
    slope = (n1 - n0) / (NECK_FULL_DOWN - RELIEF_SLOT_DOWN)   # neck widening per mm down
    neck_at = lambda d: n0 + slope * (d - RELIEF_SLOT_DOWN)
    sr = RELIEF_SLOT_W / 2
    q = [(n1, 0.0), (n1, T - NECK_FULL_DOWN), (n0, T - RELIEF_SLOT_DOWN)]
    for i in range(1, seg):                                   # rounded top of the slot
        a = math.pi - math.pi * i / seg
        q.append((n0 + sr + sr * math.cos(a), T - RELIEF_SLOT_DOWN + sr * math.sin(a)))
    q += [(n0 + RELIEF_SLOT_W, T - RELIEF_SLOT_DOWN),
          (neck_at(EAR_H) + RELIEF_SLOT_W, T - EAR_H),        # ear's inner bottom corner
          (ew - c, T - EAR_H), (ew, T - EAR_H + c), (ew, T - c), (ew - c, T), (0.0, T)]
    tl = [(-x, z) for x, z in reversed(q)][1:]
    bl = [(-x, -z) for x, z in q][1:]
    br = [(x, -z) for x, z in reversed(q)][1:-1]
    return q + tl + bl + br


def ground_d(cx, cz, r, n=24):
    """An arch: round across the top, flat along the bottom."""
    return [(cx + r * math.cos(a), cz + max(r * math.sin(a), -r * GROUND_FLAT))
            for a in (math.tau * i / n for i in range(n))]


FACING.update({
    'right': Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))),     # on the +X side
    'left': Matrix(((0, 0, -1, 0), (-1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))),    # on the -X side
})


def move_to(objs, col, parent):
    for o in objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        o.parent = parent


# --- Strap --------------------------------------------------------------------------------
T = YOKE_H / 2
yoke = prism('01_Strap', yoke_outline(), yoke_front, yoke_back, 'yoke')
holes = []
for sz in (1, -1):
    holes.append(rounded_rect(*MOUNT_SLOT, MOUNT_SLOT[0] / 2, 0, sz * MOUNT_SPACING / 2))
    holes.append(circle(0, sz * PLATE_SCREW_Z, PLATE_SCREW_HOLE_R))
    for sx in (1, -1):
        holes.append(circle(sx * EAR_HOLE_X, sz * (T - EAR_HOLE_INSET), EAR_HOLE_R))
cut(yoke, holes, -20, 40)

# --- Body -----------------------------------------------------------------------------------
bw, bh, bd = BODY
body = prism('02_Housing', rounded_rect(bw, bh - CAP_H, BODY_R, 0, BODY_Z - CAP_H / 2), yoke_back, yoke_back + bd, 'housing')
prism('02b_Housing_Cap', rounded_rect(bw, CAP_H, BODY_R, 0, BODY_Z + bh / 2 - CAP_H / 2), yoke_back, yoke_back + bd - 2.0, 'cap')
cover = prism('03_Front_Cover', rounded_rect(*FRONT_COVER, 2.0), yoke_front - FRONT_COVER_T, yoke_back + FRONT_COVER_BACK, 'front')

# --- Face: two outlets, RESET over TEST, status light ----------------------------------------
face_front = yoke_front - FACE_PROUD
face = prism('04_Face', rounded_rect(*FACE, FACE_R), face_front, yoke_front - FRONT_COVER_T + 0.01, 'front',
             FACE_CHAMFER)
openings = []
for sz_, gz in zip(OUTLET_SLOTS_Z, OUTLET_GROUND_Z):
    openings += [rounded_rect(SLOT_W, HOT_L, SLOT_CORNER, SLOT_X, sz_),
                 rounded_rect(SLOT_W, NEUTRAL_L, SLOT_CORNER, -SLOT_X, sz_),
                 ground_d(0, gz, GROUND_R)]
cut(face, openings, face_front - 1, face_front + OPENING_DEPTH)
darken_openings(face, openings, face_front)
wells = [rounded_rect(w + 2 * BUTTON_RECESS, h + 2 * BUTTON_RECESS, 1.0, 0, z) for z, w, h in BUTTONS.values()]
cut(face, wells, face_front - 1, face_front + 2.0)
darken_openings(face, wells, face_front)
buttons = {}
for label, (z, w, h) in BUTTONS.items():
    btn = prism('05_Button_' + label, rounded_rect(w, h, 0.9, 0, z), face_front - BUTTON_PROUD, face_front + 2.0, 'front',
                0.4, (0, z))
    txt = molded_text('05b_Button_Text_' + label, label, 2.2, (0, face_front - BUTTON_PROUD, z), 'front', 'front', raise_=0.12)
    txt.parent = btn                                  # the lettering rides along with its button
    buttons[label] = btn
lx, lz, ls = LED
cut(face, [rounded_rect(ls, ls, 0.2, lx, lz)], face_front - 1, face_front + 0.6)
box('06_Status_LED', (lx - ls / 2 + 0.05, lx + ls / 2 - 0.05), (face_front + 0.3, face_front + 0.7),
    (lz - ls / 2 + 0.05, lz + ls / 2 - 0.05), 'led_off')
# The glow sits just in front of the dark lens; switching the light off scales it to nothing.
glow = box('06b_Status_LED_Glow', (lx - ls / 2 + 0.06, lx + ls / 2 - 0.06), (face_front + 0.22, face_front + 0.29),
           (lz - ls / 2 + 0.06, lz + ls / 2 - 0.06), 'led')
centre = Vector((lx, face_front + 0.255, lz)) * MM
glow.data.transform(Matrix.Translation(-centre))   # origin at the light's centre, so it scales in place
glow.location = centre
for sz_ in OUTLET_SLOTS_Z:                      # little "TR" between each pair of slots
    molded_text('07_TR', 'TR', 1.6, (0, face_front, sz_), 'front', 'front', raise_=0.08)

# --- Mounting screws -------------------------------------------------------------------------
for label, sz in (('Top', 1), ('Bottom', -1)):
    front_screw('08_Mount_Screw_' + label, 0, sz * MOUNT_SPACING / 2, MOUNT_HEAD, MOUNT_SHANK, 'steel', True)

# --- Side terminals: brass (hot) +X, silver (neutral) -X; LINE at the bottom, LOAD at the top --
term_y = yoke_back + TERM_DEPTH
ph = TERM_PLATE[0] / 2
for side, metal in ((1, 'brass'), (-1, 'silver')):
    wall = side * bw / 2
    face_x = wall + side * TERM_PLATE[1]
    for label, z in TERM_Z.items():
        box('09_%s_Plate_%s' % (metal.title(), label), tuple(sorted((wall - side * 0.01, face_x))),
            (term_y - ph, term_y + ph), (z - ph, z + ph), metal + '_plate')
        thread('09_%s_%s_Thread' % (metal.title(), label), TERM_THREAD, TERM_THREAD_L, (face_x, term_y, z),
               '+X' if side > 0 else '-X', metal)
        side_screw('09_%s_%s_Screw' % (metal.title(), label), face_x + side * TERM_THREAD_L, term_y, z, side,
                   TERM_HEAD, metal)
    molded_text('09b_%s_LINE' % metal.title(), 'LINE', 2.0, (wall, term_y + 8.5, TERM_Z['LINE']),
                'right' if side > 0 else 'left', 'housing', turn=90, raise_=0.15)

# --- LOAD warning tape (its own collection) ---------------------------------------------------
tt, th = TAPE
z = TERM_Z['LOAD']
ty0, ty1 = yoke_back + FRONT_COVER_BACK, yoke_back + bd     # from behind the white cover to the body's back
tape_objs = []
reach = bw / 2 + TERM_PLATE[1] + TERM_THREAD_L + 2.6
for side in (1, -1):
    x0, x1 = sorted((side * reach, side * (reach + tt)))
    tape_objs.append(box('10_Load_Tape_Side', (x0, x1), (ty0, ty1), (z - th / 2, z + th / 2), 'tape'))
    for wx in sorted((side * bw / 2, side * reach)), :                  # folds back onto the body at the back edge
        tape_objs.append(box('10_Load_Tape_Fold', wx, (ty1 - 0.01, ty1 + tt), (z - th / 2, z + th / 2), 'tape'))
    for i, line in enumerate(('LOAD TERMINALS UNDER TAPE', 'USE LINE TERMINALS FOR', 'SINGLE RECEPTACLE')):
        tape_objs.append(molded_text('10b_Tape_Text', line, 1.15, (side * (reach + tt), (ty0 + ty1) / 2, z + 3.0 - i * 2.4),
                                     'right' if side > 0 else 'left', 'ink', raise_=0.02))
tape_objs.append(box('10_Load_Tape_Back', (-bw / 2, bw / 2), (ty1 - 0.01, ty1 + tt), (z - th / 2, z + th / 2), 'tape'))
move_to(tape_objs, tape_col, tape_root)

# --- Side label --------------------------------------------------------------------------------
lt, lh, ld = LABEL
box('11_Label', (bw / 2 - 0.01, bw / 2 + lt), (term_y + 2.0 - ld / 2 + 6, term_y + 2.0 + ld / 2 + 6),
    (LABEL_Z - lh / 2, LABEL_Z + lh / 2), 'label')
for i, line in enumerate(('GROUND FAULT', 'CIRCUIT', 'INTERRUPTER', '15A 125V~')):
    molded_text('11b_Label_Text', line, 1.6, (bw / 2 + lt, term_y + 8.0, LABEL_Z + 4.8 - i * 3.0), 'right', 'ink',
                turn=90 if False else 0, raise_=0.02)

# --- Back markings ------------------------------------------------------------------------------
back = yoke_back + bd
for text, x, z, size in (('LOAD', 0, 22.0, 3.0), ('LINE', 0, -18.0, 3.0), ('HOT', 13.0, 2.0, 2.2), ('WHITE', -13.0, 2.0, 2.2)):
    molded_text('12_Back_' + text, text, size, (x, back, z), 'back', 'housing', raise_=0.2)

# --- Ground bracket and green screw -------------------------------------------------------------
bx_in, bx_out = BRACKET_X, BRACKET_X - BRACKET_T
gz, gy = GREEN_SCREW_Z, yoke_back + GREEN_SCREW_DEPTH
box('13_Ground_Tab', (bx_out, -YOKE_W / 2 + 1), (yoke_front, yoke_back), (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
box('13_Ground_Plate', (bx_out, bx_in), (yoke_front, gy + 4.0), (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
x = bx_out
thread('14_Ground_Screw_Thread', GREEN_THREAD_SPEC, GREEN_THREAD[1], (x, gy, gz), '-X', 'green')
x -= GREEN_THREAD[1]
revolve('14_Ground_Screw_Washer', [(GREEN_WASHER[0], 0), (GREEN_WASHER[0], GREEN_WASHER[1])], (x, gy, gz), '-X', 'green')
x -= GREEN_WASHER[1]
hexhead = revolve('14_Ground_Screw', [(GREEN_HEX[0], 0), (GREEN_HEX[0], GREEN_HEX[1])], (x, gy, gz), '-X', 'green', 6)
top, g, rr = x - GREEN_HEX[1], SLOT_GAP / 2, GREEN_HEX[0] * 0.75
cut_with(hexhead, [box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - g, gy + g), (gz - rr, gz + rr)),
                   box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - rr * 0.6, gy + rr * 0.6), (gz - g, gz + g))])

# --- Materials ------------------------------------------------------------------------------------
for key in SURFACE:
    if bpy.data.materials.get(key.capitalize() + '_Material'):
        surface_material(key)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.clip_start = 0.0001
led = bpy.data.materials.get('Led_Material')
if led:
    bsdf = led.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*(COLORS['led'] if LED_ON else (.02, .08, .03)), 1)
    bsdf.inputs['Emission Color'].default_value = (*COLORS['led'], 1)
    bsdf.inputs['Emission Strength'].default_value = LED_GLOW if LED_ON else 0.0

# --- States and animations --------------------------------------------------------------------
reset_btn, test_btn = buttons['RESET'], buttons['TEST']
if TRIPPED or not LED_ON:
    glow.scale = (0, 0, 0)
if TRIPPED:
    reset_btn.location.y = -RESET_POP * MM


def keys(obj, path, frames):
    # frames: {frame: value}; location values are depth in mm (+ = into the face), scale is 0 or 1
    for f, v in frames.items():
        if path == 'location':
            obj.location.y = v * MM
            obj.keyframe_insert('location', index=1, frame=f)
        else:
            obj.scale = (v, v, v)
            obj.keyframe_insert('scale', frame=f)


def clip(name, start, spec):
    # Records one animation across several objects and stacks it on an NLA track of the same
    # name (glTF export with "NLA Tracks" turns each track into one named animation).
    prefs = bpy.context.preferences.edit
    for obj, path, frames, interp in spec:
        prefs.keyframe_new_interpolation_type = interp
        obj.animation_data_create()
        keys(obj, path, frames)
        ad = obj.animation_data
        act = ad.action
        act.name = '%s_%s' % (name, obj.name)
        track = next((t for t in ad.nla_tracks if t.name == name), None) or ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, start, act)
        if hasattr(strip, 'action_slot') and act.slots:
            strip.action_slot = act.slots[0]
        strip.extrapolation = 'HOLD_FORWARD'
        ad.action = None
    prefs.keyframe_new_interpolation_type = 'BEZIER'


if ANIMATE and LED_ON:
    T_, P_ = BUTTON_TRAVEL, RESET_POP
    # Press_Test: TEST goes in, the GFCI trips (RESET pops out, light off), TEST springs back.
    clip('Press_Test', TEST_AT, [
        (test_btn, 'location', {1: 0, 4: T_, 8: T_, 12: 0, 20: 0}, 'LINEAR'),
        (reset_btn, 'location', {1: 0, 6: 0, 8: -P_, 20: -P_}, 'LINEAR'),
        (glow, 'scale', {1: 1, 5: 1, 6: 0, 20: 0}, 'CONSTANT'),     # held on, then off in one frame
    ])
    # Press_Reset: RESET pushed in past flush, latches, light back on, settles flush.
    clip('Press_Reset', RESET_AT, [
        (test_btn, 'location', {1: 0, 20: 0}, 'LINEAR'),
        (reset_btn, 'location', {1: -P_, 5: T_, 9: T_, 13: 0, 20: 0}, 'LINEAR'),
        (glow, 'scale', {1: 0, 7: 0, 8: 1, 20: 1}, 'CONSTANT'),     # held off, then on in one frame
    ])
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, RESET_AT + 24
    for f, label in ((TEST_AT + 3, 'Press TEST'), (TEST_AT + 7, 'Tripped'), (RESET_AT + 4, 'Press RESET'),
                     (RESET_AT + 7, 'Reset - power back')):
        scene.timeline_markers.new(label, frame=f)
    scene.frame_set(1)
print('Created GFCI and its LOAD tape%s.' % (' (with Press_Test / Press_Reset animations)' if ANIMATE else ''))

