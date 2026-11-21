import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# NEMA 14-30R flush-mount dryer receptacle (30 A, 125/250 V, 4-wire); RATING='14-50' makes the
# 50 A range version (straight neutral slot, from File:NEMA_14-50R.svg). Plate and body from two
# product photos; the slot layout from the NEMA 14-30R face diagram on Wikimedia Commons
# (File:NEMA_14-30R.svg), scaled so its face circle matches FACE_R (front straight on, 6.57 px/mm, scaled from the plate's 83.3 mm device
# holes). Same conventions as the other devices: millimetres, X = width, Z = up, Y = depth
# with the front toward -Y, origin at the plate's centre. Every number is one knob.
#     blender --background --python blend/receptacle_14_30.py

RATING = globals().get('RATING', '14-30')   # '14-30' (30 A dryer) or '14-50' (50 A range): same body, plate,
                                            # hots and ground; the 14-50 has a straight neutral slot
COLLECTION_NAME = 'Receptacle_%sR' % RATING.replace('-', '_')
MM = 0.001

# --- Steel mounting plate ---------------------------------------------------------------
PLATE = (73.0, 124.8, 1.2)       # width, height, thickness
PLATE_CORNER = 2.5
PLATE_SLOT = (7.6, 3.8)          # slotted holes, three across the top and bottom...
PLATE_SLOT_X = (-30.0, 0.0, 30.0)
PLATE_SLOT_Z = 56.3              # ...this far above and below the middle
PLATE_HOLE_R = 1.5               # small round holes
PLATE_HOLES = [(-27.5, 36.5), (27.5, 36.5), (-27.5, -36.5), (27.5, -36.5)]
DEVICE_HOLE_Z = 41.65            # 6-32 device-screw holes (standard 83.3 mm spacing)
EMBOSS = 0.5                     # raised diamond stamped into the plate
EMBOSS_W = 2.5                   # width of each raised rib

# --- Face ---------------------------------------------------------------------------------
FACE_R = 33.5
FACE_PROUD = 9.0                 # face front, in front of the plate
FACE_EDGE = 2.2                  # rounding on its front edge
SLOT_DEPTH = 7.0
# Openings (x, z from the face centre):
GROUND = (0.0, 18.4, 11.0, 10.2)          # U-shaped: centre x, z, width, height
HOT = ((-19.25, -2.3), (19.25, -2.3))     # Y (left) and X (right) straight slots...
HOT_SIZE = (5.0, 24.1)                    # ...width, height
NEUTRAL = [(9.78, -12.28), (-6.24, -12.28), (-6.24, -17.27), (4.79, -17.27), (4.79, -28.72), (9.78, -28.72)]
                                          # W: a "┐" -- arm across the top, stem hanging down on the right
if RATING == '14-50':   # NEMA_14-50R.svg, same scale: a straight slot below the middle, a hair left of centre
    NEUTRAL = [(-2.71, -5.20), (2.29, -5.20), (2.29, -29.33), (-2.71, -29.33)]
CENTER_HOLE_R = 4.8
CENTER_HOLE_Z = 0.0              # dead centre
FACE_TEXT = [   # text, x, z, size, turn (degrees)
    ('NEMA', -19.0, 20.0, 4.6, 48), ('14-30R', 19.5, 20.5, 4.6, -48),
    ('125/250V', -20.0, -19.0, 4.2, -50), ('30A', 21.0, -19.5, 4.6, 52),
]
if RATING == '14-50':
    FACE_TEXT = [(t.replace('14-30R', '14-50R').replace('30A', '50A'), x, z, s, r) for t, x, z, s, r in FACE_TEXT]
PLATE_TEXT = [('AL-CU', -15.0, -47.0, 4.0), ('75°C', 16.0, -47.0, 4.0)]

# --- Body and terminals (back-wired) ------------------------------------------------------------
BODY = (54.0, 70.0, 30.0)        # black housing behind the plate: width, height, depth
BODY_R = 4.0
TERMINALS = [   # name, x, z, metal -- wire hole with its clamp screw beside it on the back
    ('X', 15.0, 16.0, 'brass'), ('Y', -15.0, 16.0, 'brass'),      # X on the right as seen from the front
    ('W', -15.0, -16.0, 'silver'), ('G', 15.0, -16.0, 'green'),
]
WIRE_HOLE_R = 3.4 if RATING == '14-30' else 4.4     # takes 10 AWG (14-30) or 6 AWG (14-50)
CLAMP_SCREW = [(3.0, 0), (3.0, 1.2), (2.6, 2.0), (1.4, 2.3)]

# --- Mounting screws ------------------------------------------------------------------------------
MOUNT_HEAD = [(3.0, 0), (3.0, 0.6), (2.6, 1.5), (1.6, 2.0)]
MOUNT_SLOT_DEPTH = 0.7
MOUNT_SHANK = (1.75, 17.5)
MOUNT_THREAD = (1.75, 1.30, 32)
MOUNT_PILOT = (0.85, 1.4)

SLOT_GAP = 0.9
THREAD_SEG = 16
TEXT_RAISE = 0.2

COLORS = {
    'yoke': (.62, .63, .64), 'face': (.03, .03, .035), 'housing': (.04, .04, .045),
    'steel': (.90, .91, .92), 'brass': (.78, .58, .24), 'silver': (.80, .81, .82),
    'green': (.08, .45, .14), 'slot': (.005, .005, .005),
}
SURFACE = {
    'yoke': (0.85, 0.40, 0.12, 6000), 'face': (0.0, 0.42, 0.03, 3000), 'housing': (0.0, 0.5, 0.03, 3000),
    'steel': (1.0, 0.18, 0.0, 0), 'brass': (1.0, 0.35, 0.0, 0), 'silver': (1.0, 0.3, 0.0, 0), 'green': (0.3, 0.35, 0.0, 0),
}
GALV_SPANGLE = 500
GALV_TONE = ((.42, .43, .45), (.74, .75, .76))
GALV_CLOUD = 2500
PLATE_DIMPLE = 1000
PLATE_DIMPLE_DEPTH = 1.0

scene = bpy.context.scene
old = bpy.data.collections.get(COLLECTION_NAME)
if old:
    for obj in list(old.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old)
for m in list(bpy.data.meshes):
    if m.users == 0:
        bpy.data.meshes.remove(m)
collection = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(collection)
root = bpy.data.objects.new(COLLECTION_NAME + '_Root', None)
root.empty_display_size = 20 * MM
collection.objects.link(root)
yoke_front, yoke_back = -PLATE[2] / 2, PLATE[2] / 2

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


def u_slot(cx, cz, w, h, n=12):
    """Flat across the top, round across the bottom."""
    r = w / 2
    pts = [(cx + r, cz + h / 2), (cx - r, cz + h / 2)]
    for i in range(n + 1):
        a = math.pi + math.pi * i / n
        pts.append((cx + r * math.cos(a), cz - h / 2 + r + r * math.sin(a)))
    return pts


# --- Plate -------------------------------------------------------------------------------
pw, ph, pt = PLATE
plate = prism('01_Mounting_Plate', rounded_rect(pw, ph, PLATE_CORNER), yoke_front, yoke_back, 'yoke')
holes = []
for sz in (1, -1):
    for sx in PLATE_SLOT_X:
        holes.append(rounded_rect(*PLATE_SLOT, PLATE_SLOT[1] / 2 - 0.01, sx, sz * PLATE_SLOT_Z))
    holes.append(circle(0, sz * DEVICE_HOLE_Z, 1.75))
holes += [circle(x, z, PLATE_HOLE_R) for x, z in PLATE_HOLES]
cut(plate, holes, -20, 40)
# Stamped stiffening diamond: raised ribs from each corner toward the middle of each side.
for (x0, z0), (x1, z1) in (((-pw / 2 + 4, ph / 2 - 4), (0, ph / 2 - 22)), ((pw / 2 - 4, ph / 2 - 4), (0, ph / 2 - 22)),
                           ((-pw / 2 + 4, -ph / 2 + 4), (0, -ph / 2 + 22)), ((pw / 2 - 4, -ph / 2 + 4), (0, -ph / 2 + 22))):
    d = Vector((x1 - x0, z1 - z0)).normalized()
    n = Vector((-d.y, d.x)) * EMBOSS_W / 2
    rib = [(x0 + n.x, z0 + n.y), (x1 + n.x, z1 + n.y), (x1 - n.x, z1 - n.y), (x0 - n.x, z0 - n.y)]
    prism('01b_Plate_Rib', rib, yoke_front - EMBOSS, yoke_front + 0.01, 'yoke', EMBOSS * 0.8)

# --- Face ------------------------------------------------------------------------------------
face_front = yoke_front - FACE_PROUD
face = prism('02_Face', circle(0, 0, FACE_R, 72), face_front, yoke_front + 0.01, 'face', FACE_EDGE)
gx, gz, gw, gh = GROUND
openings = [u_slot(gx, gz, gw, gh), NEUTRAL] + [rounded_rect(*HOT_SIZE, 0.6, x, z) for x, z in HOT]
cut(face, openings, face_front - 1, face_front + SLOT_DEPTH)
darken_openings(face, openings, face_front)
cut(face, [circle(0, CENTER_HOLE_Z, CENTER_HOLE_R, 32)], face_front - 1, face_front + FACE_PROUD + 2)
darken_openings(face, [circle(0, CENTER_HOLE_Z, CENTER_HOLE_R, 32)], face_front)
for text, x, z, size, turn in FACE_TEXT:
    molded_text('02b_Face_Text', text, size, (x, face_front, z), 'front', 'face', turn=turn)
for text, x, z, size in PLATE_TEXT:
    molded_text('01c_Plate_Text', text, size, (x, yoke_front, z), 'front', 'yoke', raise_=0.15)

AXES['+Y'] = Matrix.Rotation(-math.pi / 2, 4, 'X')    # for parts facing out the back

# --- Body and back terminals --------------------------------------------------------------------
bw, bh, bd = BODY
back = yoke_back + bd
body = prism('03_Housing', rounded_rect(bw, bh, BODY_R), yoke_back, back, 'housing')
wire_holes = [circle(x, z, WIRE_HOLE_R, 20) for _, x, z, _ in TERMINALS]
cut(body, wire_holes, back - 12, back + 1)
darken_openings(body, wire_holes, back, inward=-1)
for name, x, z, metal in TERMINALS:
    sz = 1 if z > 0 else -1
    s = revolve('04_Terminal_%s_Screw' % name, CLAMP_SCREW, (x, back, z + sz * 8.0), '+Y', metal)
    g = SLOT_GAP / 2
    top = back + CLAMP_SCREW[-1][1]
    cut_with(s, [box('Cutter', (x - 2.6, x + 2.6), (top - 1.0, top + 1), (z + sz * 8.0 - g, z + sz * 8.0 + g))])
    molded_text('04b_Terminal_Label_%s' % name, name, 4.0, (x + 7.0, back, z), 'back', 'housing', raise_=0.2)

# --- Mounting screws ---------------------------------------------------------------------------
for label, sz in (('Top', 1), ('Bottom', -1)):
    front_screw('05_Mount_Screw_' + label, 0, sz * DEVICE_HOLE_Z, MOUNT_HEAD, MOUNT_SHANK, 'steel', True)

for key in SURFACE:
    if bpy.data.materials.get(key.capitalize() + '_Material'):
        surface_material(key)
print('Created %sR receptacle.' % RATING)
