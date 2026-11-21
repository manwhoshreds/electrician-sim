import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# Single-pole 15 A toggle switch (white), modelled from straight-on product photos
# (front 5.14 px/mm, side 3.72 px/mm, back 3.58 px/mm; scale from the 83.3 mm
# mounting-screw spacing). Same conventions as tr270_blockout.py: millimetres,
# X = width, Z = height, Y = depth with the front toward -Y, origin at the strap's
# centre on the ears' plane. Every number below is one knob.
#
# Safe to re-run: the previous switch collection is cleared first.
# Runs from Blender's Text Editor or headless:
#     blender --background --python blend/toggle_switch.py

COLLECTION_NAME = 'Toggle_Switch_Blockout'
MM = 0.001

# --- Strap (yoke) -------------------------------------------------------------------
YOKE_H = 106.6              # end to end (front photo)
YOKE_T = 1.0                # sheet thickness
EAR_W = 33.9                # across the plaster ears
EAR_H = 10.9                # height of each ear
EAR_CORNER = 1.3            # ears' outer corners clipped at 45 degrees
EAR_HOLE_R = 2.15           # round hole in each ear...
EAR_HOLE_X = 13.2           # ...this far out from the middle...
EAR_HOLE_INSET = 5.4        # ...and this far in from the strap's end
RELIEF_SLOT_W = 1.6         # narrow U-slot between each ear and the neck
RELIEF_SLOT_DOWN = 6.6      # its rounded end, in from the strap's end
NECK_TOP_W = 16.3           # strap width below the top ear...
NECK_END_Z = 31.5           # ...down to here, where it widens to...
STRAP_W = 18.7              # ...this, over the top of the body
STRAP_LOWER_W = 19.0        # strap width below the toggle frame, down to the bottom ear
FRAME_W = 21.4              # the strap widens round the toggle window...
FRAME_Z = (14.4, -20.6)     # ...between these heights
FRAME_RAISE = 1.0           # the frame round the window stands this far proud of the ears (side photo)
FRAME_CHAMFER = 0.8
WINDOW = (12.8, 25.3)       # toggle window, width x height...
WINDOW_Z = -0.95            # ...centred here
STRAP_HOLE_R = 1.35         # small round hole between each mounting screw and the body
STRAP_HOLE_Z = 29.6         # (one above, one below)
RIB_TOP_W = 7.0             # stamped stiffening rib on each ear (like the receptacle's)
RIB_BOTTOM_W = 12.4
RIB_RAISE = 0.4

# --- Mounting screws (6-32, combination head) ------------------------------------
MOUNT_SPACING = 83.3
MOUNT_HEAD = [(3.0, 0), (3.0, 0.6), (2.6, 1.5), (1.6, 2.0)]
MOUNT_SLOT_DEPTH = 0.7
MOUNT_SHANK = (1.75, 19.0)  # radius, length behind the strap (side photo)
MOUNT_THREAD = (1.75, 1.30, 32)
MOUNT_PILOT = (0.85, 1.4)
WASHER = (6.0, 0.5)         # square white retaining washer behind the strap: size, thickness

# --- Body ---------------------------------------------------------------------------
WHITE_W, WHITE_H = 21.0, 48.0   # white front body, behind the strap
WHITE_BACK = 4.3            # it ends this far behind the ears, where the blue starts
BLUE_W, BLUE_H = 18.8, 52.5     # blue rear body (back photo)
BLUE_Z = -0.25              # its centre height (z +26 to -26.5)
BLUE_BACK = 23.7            # its back face, behind the ears (side photo)
BODY_CORNER = 1.5
# Two small blue blocks at the front of the blue body (back + side photos), each
# given as x from, x to, z from, z to, and how deep they run back from the white:
BLUE_TOP_TAB = (-9.0, -3.5, 26.0, 31.8, 5.4)    # top, on the side away from the screws
BLUE_FOOT = (2.8, 10.0, -32.6, -24.0, 5.9)      # bottom, on the screw side

# --- Toggle -------------------------------------------------------------------------
# Measured from the side photo (26 px/mm zoom) and the front photo (25.7 px/mm zoom).
PIVOT_FACE_Y = -3.9         # white pivot block's face: it stands proud of the metal frame
PIVOT_ROUND = 0.6           # bevel round the pivot face
LEVER_SLOT = (7.4, 17.9, -1.15, 2.0)   # slot in the pivot face the lever comes out of: w, h, z, depth
LEVER_BASE = (7.0, 7.9)     # lever width x thickness where it leaves the slot...
LEVER_BASE_Z = -3.55
LEVER_TIP = (6.4, 5.4)      # ...and at its tip: only a little thinner, not a point
LEVER_TIP_Z = -7.6          # tip centre: points down (OFF), about 18 degrees
LEVER_TIP_Y = -16.2         # tip, in front of the ears (side photo)
LEVER_ROUND = 0.7           # rounding on the lever's long edges
LEVER_TIP_ROUND = 1.6       # bigger rounding on the tip's end

# --- Terminals (both brass, on the +X side) ---------------------------------------
TERM_Z = (15.9, -14.9)      # averaged across front, side and back photos
TERM_DEPTH = 11.3           # screw centres behind the ears (side photo)
TERM_RECESS_X = 7.5         # pocket floor, out from the middle
TERM_PLATE = (9.7, 0.9)     # one plate per screw: size, thickness
TERM_THREAD = (2.08, 1.60, 32)   # 8-32
TERM_THREAD_L = 2.2
TERM_HEAD = [(4.2, 0), (4.2, 1.2), (3.8, 2.1), (1.5, 2.4)]

# --- Ground (green, on the -X side, below the body) --------------------------------
GREEN_SCREW_Z = -29.4
GREEN_SCREW_DEPTH = 12.5
BRACKET_X = -9.5
BRACKET_T = 1.0
BRACKET_H = 8.0
BRACKET_FLANGE = 2.4
GREEN_THREAD = (2.4, 2.4)
GREEN_THREAD_SPEC = (2.40, 1.90, 32)
GREEN_WASHER = (3.8, 0.6)
GREEN_HEX = (3.4, 2.0)

# --- Blue body relief (side and back close-ups) -------------------------------------
SIDE_RECESS = 1.0           # how far the recessed areas on the blue's sides sit in
SCREW_SIDE_RECESS_Z = (7.4, -6.7)   # screw side: recess between the two ribs that bound the pockets
SCREW_SIDE_RECESS_BACK = 18.0       # ...running back to the rib along the back edge
WEDGE = (4.6, 11.3, 4.0)    # triangular wedge in that recess: front y, apex y, half-height
FAR_SIDE_RECESS_Z = (12.4, -12.1)   # far side: big recessed panel...
FAR_SIDE_RECESS_Y = (7.0, 20.3)     # ...between a front ledge and a back ledge
SNAP_TABS_Z = (6.15, -5.95) # white snap tabs showing through notches in the blue's front edge
SNAP_TAB = (1.2, 2.3, 2.7)  # tab: depth into the side, length back from the white, height
BACK_CHANNEL = (6.4, 24.3, -4.9, -1.0, 1.0)  # oblong channel on the back: width, height, x, z, depth

# --- Back: push-in wire holes (x as seen from the front) ----------------------------
BACK_HOLES = [(8.0, 20.9), (8.0, -23.7)]
BACK_SLOTS = [(4.2, 17.6), (4.2, -20.4)]
BACK_HOLE_R = 1.2
BACK_SLOT = (4.0, 1.2)
BACK_HOLE_DEPTH = 4.0

SLOT_GAP = 0.9
THREAD_SEG = 16
TEXT_RAISE = 0.15

COLORS = {
    'yoke': (.52, .54, .57),
    'rear': (.02, .12, .60),
    'front': (.90, .90, .88),
    'steel': (.90, .91, .92),
    'brass': (.78, .58, .24),
    'brass_plate': (.78, .58, .24),
    'green': (.08, .45, .14),
    'slot': (.02, .02, .02),
}
SURFACE = {
    'front':        (0.0, 0.38, 0.03, 4000),
    'rear':         (0.0, 0.45, 0.04, 3000),
    'yoke':         (0.85, 0.45, 0.12, 6000),
    'steel':        (1.0, 0.18, 0.00, 0),
    'brass':        (1.0, 0.40, 0.00, 0),
    'brass_plate':  (1.0, 0.35, 0.00, 0),
    'green':        (0.3, 0.35, 0.00, 0),
}
GALV_SPANGLE = 700
GALV_TONE = ((.30, .31, .33), (.60, .61, .62))
GALV_CLOUD = 2500
PLATE_DIMPLE = 1000
PLATE_DIMPLE_DEPTH = 1.0

# --- Setup ---------------------------------------------------------------------------

scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.length_unit = 'MILLIMETERS'

old = bpy.data.collections.get(COLLECTION_NAME)
if old:
    for obj in list(old.objects):
        mesh = obj.data if obj.type == 'MESH' else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    bpy.data.collections.remove(old)

collection = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(collection)
root = bpy.data.objects.new('Toggle_Switch_Root', None)
root.empty_display_size = 20 * MM
collection.objects.link(root)

yoke_front, yoke_back = -YOKE_T / 2, YOKE_T / 2

# --- Shared helpers (same as tr270_blockout.py) -------------------------------------

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


# --- Strap -------------------------------------------------------------------------

def strap_outline(seg=6):
    """Right side from the bottom end up, then mirrored: an ear at each end with a
    relief slot beside the neck, a narrow neck under the top ear, and a wider frame
    round the toggle window."""
    T, ew, c, sw, rd = YOKE_H / 2, EAR_W / 2, EAR_CORNER, RELIEF_SLOT_W, RELIEF_SLOT_DOWN
    nt, ns, nb, fw = NECK_TOP_W / 2, STRAP_W / 2, STRAP_LOWER_W / 2, FRAME_W / 2
    r = sw / 2
    p = [(0.0, -T), (ew - c, -T), (ew, -T + c), (ew, -T + EAR_H - c), (ew - c, -T + EAR_H),
         (nb + sw, -T + EAR_H), (nb + sw, -T + rd)]
    for i in range(1, seg):                             # bottom slot's rounded end
        a = -math.pi * i / seg
        p.append((nb + r + r * math.cos(a), -T + rd + r * math.sin(a)))
    p += [(nb, -T + rd), (nb, FRAME_Z[1]), (fw, FRAME_Z[1]), (fw, FRAME_Z[0]), (ns, FRAME_Z[0]),
          (ns, NECK_END_Z), (nt, NECK_END_Z), (nt, T - rd)]
    for i in range(1, seg):                             # top slot's rounded end
        a = math.pi - math.pi * i / seg
        p.append((nt + r + r * math.cos(a), T - rd + r * math.sin(a)))
    p += [(nt + sw, T - rd), (nt + sw, T - EAR_H), (ew - c, T - EAR_H), (ew, T - EAR_H + c),
          (ew, T - c), (ew - c, T), (0.0, T)]
    return p + [(-x, z) for x, z in reversed(p)][1:-1]


T = YOKE_H / 2
yoke = prism('01_Strap', strap_outline(), yoke_front, yoke_back, 'yoke')
window = rounded_rect(*WINDOW, 0.6, 0, WINDOW_Z)
holes = [window]
for sz in (1, -1):
    holes.append(circle(0, sz * STRAP_HOLE_Z, STRAP_HOLE_R))
    for sx in (1, -1):
        holes.append(circle(sx * EAR_HOLE_X, sz * (T - EAR_HOLE_INSET), EAR_HOLE_R))
cut(yoke, holes, -20, 40)

frame_h = FRAME_Z[0] - FRAME_Z[1]
frame = prism('01b_Toggle_Frame', rounded_rect(FRAME_W, frame_h, 1.2, 0, sum(FRAME_Z) / 2),
              yoke_front - FRAME_RAISE, yoke_front + 0.01, 'yoke', FRAME_CHAMFER, (0, sum(FRAME_Z) / 2))
cut(frame, [window], -20, 40)

for label, sz in (('Top', 1), ('Bottom', -1)):
    z0, z1 = sz * (T - 0.6), sz * (T - RELIEF_SLOT_DOWN + 0.2)
    rib = [(-RIB_TOP_W / 2, z0), (RIB_TOP_W / 2, z0), (RIB_BOTTOM_W / 2, z1), (-RIB_BOTTOM_W / 2, z1)]
    prism('01c_Strap_Rib_' + label, rib, yoke_front - RIB_RAISE, yoke_front + 0.01, 'yoke', RIB_RAISE * 0.8)

# --- Body ---------------------------------------------------------------------------
white = prism('02_White_Body', rounded_rect(WHITE_W, WHITE_H, BODY_CORNER), yoke_back, WHITE_BACK, 'front')
blue = prism('03_Blue_Body', rounded_rect(BLUE_W, BLUE_H, BODY_CORNER, 0, BLUE_Z), WHITE_BACK, BLUE_BACK, 'rear')
for label, (x0, x1, z0, z1, d) in (('Top_Tab', BLUE_TOP_TAB), ('Foot', BLUE_FOOT)):
    prism('03b_Blue_' + label, rounded_rect(x1 - x0, z1 - z0, 0.8, (x0 + x1) / 2, (z0 + z1) / 2),
          WHITE_BACK, WHITE_BACK + d, 'rear')

# --- Toggle -------------------------------------------------------------------------
frame_face = yoke_front - FRAME_RAISE
pivot_back = yoke_back + 0.5
win = (WINDOW[0] - 0.4, WINDOW[1] - 0.4)
pivot = prism('04_Toggle_Pivot', rounded_rect(*win, 1.0, 0, WINDOW_Z), PIVOT_FACE_Y, pivot_back, 'front',
              PIVOT_ROUND, (0, WINDOW_Z))
sw_, sh_, sz_, sd_ = LEVER_SLOT
cut(pivot, [rounded_rect(sw_, sh_, 0.8, 0, sz_)], PIVOT_FACE_Y - 1, PIVOT_FACE_Y + sd_)


def lever():
    """A thick paddle from inside the slot out to a blunt, rounded tip, angled down."""
    bm = bmesh.new()
    root_y = PIVOT_FACE_Y + LEVER_SLOT[3]
    rings = []
    for (w, h), zc, y in ((LEVER_BASE, LEVER_BASE_Z, root_y), (LEVER_TIP, LEVER_TIP_Z, LEVER_TIP_Y)):
        rings.append([bm.verts.new((sx * w / 2 * MM, y * MM, (zc + sz * h / 2) * MM))
                      for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    a, b = rings
    for i in range(4):
        bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    tip_edges = [e for e in bm.edges if all(v in b for v in e.verts)]
    long_edges = [e for e in bm.edges if (e.verts[0] in a) != (e.verts[1] in a)]
    bmesh.ops.bevel(bm, geom=tip_edges, offset=LEVER_TIP_ROUND * MM, segments=5, affect='EDGES', profile=0.5)
    bmesh.ops.bevel(bm, geom=[e for e in long_edges if e.is_valid], offset=LEVER_ROUND * MM, segments=3,
                    affect='EDGES', profile=0.5)
    return to_object('04b_Toggle_Lever', bm, 'front')


lever()

# --- Terminals ----------------------------------------------------------------------
term_y = yoke_back + TERM_DEPTH
ph = TERM_PLATE[0] / 2
for label, z in zip(('Top', 'Bottom'), TERM_Z):
    cut(blue, [[(TERM_RECESS_X, z - ph - 0.6), (BLUE_W, z - ph - 0.6), (BLUE_W, z + ph + 0.6), (TERM_RECESS_X, z + ph + 0.6)]],
        WHITE_BACK - 0.5, term_y + ph + 1.5)
    face_x = TERM_RECESS_X + TERM_PLATE[1]
    box('05_Terminal_Plate_' + label, (TERM_RECESS_X, face_x), (term_y - ph, term_y + ph), (z - ph, z + ph), 'brass_plate')
    thread('05_Terminal_%s_Thread' % label, TERM_THREAD, TERM_THREAD_L, (face_x, term_y, z), '+X', 'brass')
    side_screw('05_Terminal_' + label, face_x + TERM_THREAD_L, term_y, z, 1, TERM_HEAD, 'brass')

# --- Blue body relief ----------------------------------------------------------------
hw = BLUE_W / 2
# Screw side: recess between the pocket ribs, with a wedge pointing back.
z0, z1 = SCREW_SIDE_RECESS_Z
cut(blue, [[(hw - SIDE_RECESS, z1), (hw + 1, z1), (hw + 1, z0), (hw - SIDE_RECESS, z0)]],
    WHITE_BACK - 0.5, SCREW_SIDE_RECESS_BACK)


def wedge(name, x0, x1, fy, ay, h, color):
    """A triangular block on the side: flat edge at the front (fy), apex pointing back (ay)."""
    bm = bmesh.new()
    tri = [(fy, -h), (fy, h), (ay, 0.0)]
    a = [bm.verts.new((x0 * MM, y * MM, z * MM)) for y, z in tri]
    b = [bm.verts.new((x1 * MM, y * MM, z * MM)) for y, z in tri]
    for i in range(3):
        bm.faces.new((a[i], a[(i + 1) % 3], b[(i + 1) % 3], b[i]))
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    return to_object(name, bm, color)


wedge('03c_Blue_Wedge', hw - SIDE_RECESS - 0.01, hw, WEDGE[0], WEDGE[1], WEDGE[2], 'rear')

# Far side: big recessed panel.
z0, z1 = FAR_SIDE_RECESS_Z
cut(blue, [[(-hw - 1, z1), (-hw + SIDE_RECESS, z1), (-hw + SIDE_RECESS, z0), (-hw - 1, z0)]], *FAR_SIDE_RECESS_Y)

# White snap tabs in notches along the blue's front edge, both sides.
td, tl, th = SNAP_TAB
for sx in (1, -1):
    for tz in SNAP_TABS_Z:
        xs = tuple(sorted((sx * (hw - td), sx * (hw + 0.01))))
        cut(blue, [[(xs[0], tz - th / 2), (xs[1] + 0.5 * (sx > 0), tz - th / 2),
                    (xs[1] + 0.5 * (sx > 0), tz + th / 2), (xs[0], tz + th / 2)]], WHITE_BACK - 0.5, WHITE_BACK + tl)
        box('02b_White_Snap_Tab', xs, (WHITE_BACK - 0.1, WHITE_BACK + tl), (tz - th / 2, tz + th / 2), 'front')

# Back: oblong channel on the half away from the screws.
cw, ch, cx, cz, cd = BACK_CHANNEL
cut(blue, [rounded_rect(cw, ch, cw / 2 - 0.01, cx, cz)], BLUE_BACK - cd, BLUE_BACK + 1)

# --- Back: push-in holes ------------------------------------------------------------
back_holes = [circle(x, z, BACK_HOLE_R, 16) for x, z in BACK_HOLES]
back_holes += [rounded_rect(*BACK_SLOT, 0.2, x, z) for x, z in BACK_SLOTS]
cut(blue, back_holes, BLUE_BACK - BACK_HOLE_DEPTH, BLUE_BACK + 1)
darken_openings(blue, back_holes, BLUE_BACK, inward=-1)

# --- Mounting screws ------------------------------------------------------------------
for label, sz in (('Top', 1), ('Bottom', -1)):
    front_screw('06_Mount_Screw_' + label, 0, sz * MOUNT_SPACING / 2, MOUNT_HEAD, MOUNT_SHANK, 'steel', True)
    wz, ww = sz * MOUNT_SPACING / 2, WASHER[0] / 2
    box('06b_Mount_Washer_' + label, (-ww, ww), (yoke_back, yoke_back + WASHER[1]), (wz - ww, wz + ww), 'front')

# --- Ground bracket and green screw ---------------------------------------------------
bx_in, bx_out = BRACKET_X, BRACKET_X - BRACKET_T
gz, gy = GREEN_SCREW_Z, yoke_back + GREEN_SCREW_DEPTH
box('07_Ground_Bracket_Tab', (bx_out, -STRAP_LOWER_W / 2 + 1), (yoke_front, yoke_back), (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
box('07_Ground_Bracket_Plate', (bx_out, bx_in), (yoke_front, gy + 4.0), (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
for label, sz in (('Top', 1), ('Bottom', -1)):
    edge = gz + sz * BRACKET_H / 2
    box('07_Ground_Bracket_Flange_' + label, (bx_out - BRACKET_FLANGE, bx_out), (gy - 4.0, gy + 4.0),
        tuple(sorted((edge, edge - sz * BRACKET_T))), 'yoke')
x = bx_out
thread('08_Ground_Screw_Thread', GREEN_THREAD_SPEC, GREEN_THREAD[1], (x, gy, gz), '-X', 'green')
x -= GREEN_THREAD[1]
revolve('08_Ground_Screw_Washer', [(GREEN_WASHER[0], 0), (GREEN_WASHER[0], GREEN_WASHER[1])], (x, gy, gz), '-X', 'green')
x -= GREEN_WASHER[1]
hexhead = revolve('08_Ground_Screw', [(GREEN_HEX[0], 0), (GREEN_HEX[0], GREEN_HEX[1])], (x, gy, gz), '-X', 'green', 6)
top, g, rr = x - GREEN_HEX[1], SLOT_GAP / 2, GREEN_HEX[0] * 0.75
cut_with(hexhead, [box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - g, gy + g), (gz - rr, gz + rr)),
                   box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - rr * 0.6, gy + rr * 0.6), (gz - g, gz + g))])

# --- Materials ------------------------------------------------------------------------
for key in SURFACE:
    if bpy.data.materials.get(key.capitalize() + '_Material'):
        surface_material(key)

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.clip_start = 0.0001

print('Created toggle switch blockout.')
