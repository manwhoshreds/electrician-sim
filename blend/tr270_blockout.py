import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# Eaton TR270-inspired dimensional blockout, NOT manufacturer-verified part geometry.
# Known reference envelope (approx.): yoke height 106.5 mm, width 33 mm,
# illustrated depth 17.5 mm. Everything else below is provisional and editable.
#
# Safe to re-run: the previous blockout collection is cleared first.
# Runs from Blender's Text Editor or headless:
#     blender --background --python blend/tr270_blockout.py

COLLECTION_NAME = 'Eaton_TR270_Blockout'
MM = 0.001

# --- Dimensions (mm) -----------------------------------------------------------
# X = width, Z = height, Y = depth. The front points toward -Y.

# Yoke (the metal strap)
YOKE_H = 106.5              # overall height (reference)
# Measured off a straight-on front photo (6.2 px/mm). Distances "down" are from the strap's end.
YOKE_W = 19.0               # strap width where it meets the body (and behind it)
YOKE_T = 1.5                # sheet thickness
EAR_W = 33.0                # across the plaster ears
EAR_H = 10.9                # height of each ear
EAR_CORNER = 1.3            # the ears' outer corners are clipped at 45 degrees
EAR_HOLE_R = 2.2            # round hole in each ear
EAR_HOLE_X = 12.7           # hole centre, out from the middle
EAR_HOLE_INSET = 5.6        # hole centre, down from the strap's end
NECK_TOP_W = 12.4           # the neck tapers: this wide up at the ear...
NECK_FULL_DOWN = 17.5       # ...widening to YOKE_W this far down
RELIEF_SLOT_W = 1.6         # narrow U-slot between each ear and the neck
RELIEF_SLOT_DOWN = 6.6      # how far down the slot's rounded top sits
RIB_TOP_W = 7.0             # stamped rib on each ear: narrow at the strap's end...
RIB_BOTTOM_W = 12.4         # ...widening to this where the neck starts
RIB_RAISE = 0.5             # how far the rib stands out from the strap's front
MOUNT_SPACING = 83.3        # device-screw spacing (standard 3-9/32 in)
MOUNT_SLOT = (3.8, 6.4)     # slot each mounting screw sits in, width x height
# Ground bracket: a "[" shaped clip off the strap, sitting in a pocket in the body's
# lower-left corner, with the green hex-washer screw threaded in sideways.
GREEN_SCREW_Z = -28.0       # green screw height (front photo)
GREEN_SCREW_DEPTH = 13.0    # green screw centre, behind the strap (side photo)
BRACKET_X = -13.0           # bracket plate's inner face, out from the middle (front photo:
                            # head's outer face lands at about -18.9)
BRACKET_T = 1.0             # bracket sheet thickness
BRACKET_H = 8.6             # height of the plate running back from the strap...
BRACKET_CLIP_H = 13.0       # ...which grows to this around the screw, where the flanges are
BRACKET_CLIP_D = 9.0        # depth of that taller clip part, centred on the screw
BRACKET_FLANGE = 2.8        # top and bottom flanges bend outward this far
# Green screw, from the bracket outward: thread showing, round washer, hex head.
GREEN_THREAD = (2.4, 2.4)   # radius, exposed length
GREEN_WASHER = (3.8, 0.6)   # radius, thickness
GREEN_HEX = (3.4, 2.0)      # across-corners radius, height

# Housings
BODY_W = 33.0               # reference width
REAR_H = 68.0               # body, end to end (front photo)
REAR_DOME = 12.0            # its ends are domed: how tall each dome would be if not cut flat
REAR_FLAT = 0.85            # where the dome is cut flat, as a fraction of REAR_DOME
                            # (lower = wider flat crown, fuller shoulders)
                            # Only the TOP end is domed; the bottom is near-square:
REAR_FOOT_R = 8.0           # corner rounding at the bottom end (back photo)
POCKET_X = (-BODY_W / 2 - 1, -4.6)   # pocket in the bottom-left corner (seen from the front)
# Seen from behind, the blue housing is an hourglass like the front: a full-width lobe
# at each end and a waist through the terminal area (back photo, 4.47 px/mm).
REAR_WAIST_HALF_W = 14.5    # half-width through the waist (~29 mm across)
REAR_WAIST_Z = (19.0, -7.5) # where the waist starts and ends
REAR_WAIST_FILLET = 2.5     # rounding where each lobe curves in to the waist
POCKET_Z = (-REAR_H / 2 - 1, -20.5)  # where the green screw's bracket sits
# Depths, from the side photo: the white shell starts just in front of the strap and
# carries on behind it; the blue shell takes over from there.
FRONT_T = 1.0               # white base in front of the strap (just enough to cover it)
WHITE_BEHIND = 0.5          # white shell ends just behind the strap (straight-on side photo)
REAR_T = 18.0               # blue shell depth, from the white/blue seam back (back ends ~19.3 mm behind the strap)

# Back of the blue shell (read off the back photos; x is as seen from the FRONT)
BACK_HOLE_X = 10.5          # push-in wire holes and release slots, out from the middle
BACK_HOLE_R = 1.3
BACK_HOLE_Z = (18.0, -10.7) # one hole near the top, one near the bottom, each side (back photo)
BACK_SLOT = (2.0, 1.4)      # release slot beside each hole: width x height...
BACK_SLOT_Z = (14.2, -7.3)  # ...sitting just inside each hole (toward the middle)
BACK_HOLE_DEPTH = 4.0
LABEL = (10.0, 34.0)        # barcode sticker, width x height...
LABEL_Z = 1.8               # ...centred this far above the middle
LABEL_RECESS = 0.3          # it sits in a shallow recess
FOOT_STEP_Z = -20.5         # below this, the back steps down...
FOOT_STEP = 1.5             # ...by this much
# The back face has a raised rim round its edge with a recessed panel inside (back photo):
BACK_RIM = 1.2              # how far the panel is sunk below the raised rim around it
PANEL_INSET_TOP = 2.2       # panel's dome, in from the housing's top edge
PANEL_HALF_W = 13.4         # panel half-width at the wire-hole ends...
PANEL_WAIST_HALF_W = 12.7   # ...and through the middle, beside the terminals
PANEL_WAIST_Z = (11.2, -4.8)   # where the middle (narrow) stretch starts and ends
PANEL_STEP = 1.0            # height of the little slope at each end of the narrow stretch
STRIP_GAUGE = (-4.4, 7.2, -25.8, 1.2, 0.6)   # groove: x from, x to, height, width, depth
BRIDGE_W = 28.0             # the front base pinches in to this width beside the terminals (photo)
WAIST_H = 22.5              # height of that pinched-in stretch...
WAIST_Z = 4.6               # ...centred here, so it spans both terminals and their threads show

# Faces (the two parts you plug into)
FACE_SPACING = 39.0         # centre to centre
FACE_R = 16.0               # each face is a circle...
FACE_FLAT = 13.6            # ...cut flat this far above and below its centre
FACE_RAISE = 4.75           # how far the faces stand out from the front base
FACE_CHAMFER = 0.8

# Openings, measured from each face's centre (NEMA 5-15R layout, ground down)
SLOT_X = 6.35               # slots sit this far left and right of centre
SLOT_Z = 3.0                # slot centres sit this far above the face centre
SLOT_W = 1.8
HOT_L = 6.35                # hot: the shorter slot, on the right
NEUTRAL_L = 7.9             # neutral: the longer slot, on the left
GROUND_Z = -8.8             # ground hole centre, below the face centre
GROUND_R = 2.5
GROUND_FLAT = 0.6           # the arch's flat bottom sits this fraction of the radius below centre
SLOT_CORNER = 0.25          # slots are near-sharp rectangles, just softened a little
OPENING_DEPTH = 3.5         # how deep the openings go (the TR shutters sit behind)

TR_MARK = (3.8, 0.25)       # recessed "TR" square between the slots: size, depth
PLATE_SCREW_R = 1.75        # centre hole for the wall-plate screw

# Screws. Heads are given as (radius, height) steps from the seat outward.
SLOT_GAP = 0.9              # width of the slot (and cross) cut into each head
MOUNT_HEAD = [(3.0, 0), (3.0, 0.6), (2.6, 1.5), (1.6, 2.0)]   # small dome head, combination slot
MOUNT_SLOT_DEPTH = 0.7      # slot and cross depth, as a fraction of the head's height
MOUNT_SHANK = (1.75, 17.5)  # 6-32 shank radius, length behind the yoke (side photo)
# Threads: (major radius, minor radius, threads per inch). Pitch = 25.4 mm / TPI.
MOUNT_THREAD = (1.75, 1.30, 32)    # 6-32 mounting screws
TERM_THREAD = (2.08, 1.60, 32)     # 8-32 terminal screws
GREEN_THREAD_SPEC = (2.40, 1.90, 32)   # 10-32 green ground screw
MOUNT_PILOT = (0.85, 1.4)   # unthreaded pilot at the mounting screws' tips: radius (x minor), length
THREAD_SEG = 16             # sides per turn (more = smoother, heavier)
WASHER = (6.0, 0.5)         # square blue retaining washer on each mounting screw: size, thickness
# Binding screw, from the plate outward: shipped backed out, so ~2 mm of thread shows
# before the head (front photo: head spans 17.1 to 19.5 mm out from the middle).
TERM_THREAD_L = 2.2         # thread showing between the plate and the head
TERM_HEAD = [(4.2, 0), (4.2, 1.2), (3.8, 2.1), (1.5, 2.4)]
TERM_RECESS_X = 14.0        # the terminals sit in a pocket in the body's side; its floor
                            # is this far out from the middle (that's why the front pinches in)
TERM_Z = (11.3, -2.1)       # not symmetric: one beside the top face, one just below the centre hole
TERM_DEPTH = 10.0           # terminal screw centres, behind the strap (side photo)
TERM_PLATE = (9.7, 0.9)     # one brass plate per side spanning both screws: width (depth-wise), thickness
TERM_PLATE_PAD = 4.85       # the plate runs this far past each screw centre, top and bottom
BREAK_TAB = (2.2, 3.7)      # break-off tab sticking forward from the plate's middle: length, height
DIVIDER_H = 3.4             # blue rib across the pocket between the two screws

COLORS = {
    'yoke': (.52, .54, .57),
    'rear': (.02, .12, .60),     # Eaton blue
    'front': (.90, .90, .88),    # TR270W = white
    'brass_plate': (.78, .58, .24),
    'silver_plate': (.80, .81, .82),
    'steel': (.90, .91, .92),    # zinc-plated mounting screws: bright silver
    'brass': (.78, .58, .24),
    'silver': (.80, .81, .82),
    'green': (.08, .45, .14),
    'slot': (.02, .02, .02),     # inside the openings, so they read as holes
    'label': (.90, .90, .88),    # the barcode sticker on the back
}

# --- Setup ---------------------------------------------------------------------

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
for mat in list(bpy.data.materials):
    if mat.name.endswith('_Material') and mat.users == 0:
        bpy.data.materials.remove(mat)

collection = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(collection)

root = bpy.data.objects.new('TR270_Assembly_Root', None)
root.empty_display_size = 20 * MM
collection.objects.link(root)


# --- Outlines (x, z) in mm -----------------------------------------------------

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


def face_outline(cz, grow=0.0, n=48):
    """A circle cut flat top and bottom, grown outward by `grow`."""
    r, flat = FACE_R + grow, FACE_FLAT + grow
    pts = []
    for i in range(n):
        a = math.tau * i / n
        pts.append((r * math.cos(a), cz + max(-flat, min(flat, r * math.sin(a)))))
    return pts


def front_housing_outline(height, r, dome, flat, n=48):
    """The white shell seen from the front: the rear housing's dome at both ends,
    so it follows the faces instead of showing a square corner at the bottom."""
    top = rear_housing_outline(height, r, dome, flat, 1.0, n)[:n // 2 + 1]
    return top + [(x, -z) for x, z in reversed(top)]


def rear_housing_outline(height, r, dome, flat, foot_r, n=48, seg=6):
    """The rear housing seen from the front: straight sides, a domed top cut flat
    across its crown, and a near-square bottom with rounded corners."""
    cut = dome * flat
    zc = height / 2 - cut
    bottom = -height / 2
    pts = []
    for i in range(n // 2 + 1):                     # top dome, right to left
        a = math.pi * i / (n // 2)
        pts.append((r * math.cos(a), zc + min(cut, dome * math.sin(a))))
    for cx, a0 in ((-r + foot_r, 180), (r - foot_r, 270)):   # bottom corners
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((cx + foot_r * math.cos(a), bottom + foot_r + foot_r * math.sin(a)))
    return pts


def half_width_at(outline, z):
    """How far the outline reaches out from the middle at height z."""
    best = 0.0
    for (x0, z0), (x1, z1) in zip(outline, outline[1:] + outline[:1]):
        if min(z0, z1) <= z <= max(z0, z1) and z0 != z1:
            best = max(best, abs(x0 + (x1 - x0) * (z - z0) / (z1 - z0)))
    return best


def ground_d(cx, cz, r, n=24):
    """An arch: round across the top, flat along the bottom."""
    return [(cx + r * math.cos(a), cz + max(r * math.sin(a), -r * GROUND_FLAT))
            for a in (math.tau * i / n for i in range(n))]


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


# --- Building parts ------------------------------------------------------------

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


# --- The receptacle ------------------------------------------------------------

yoke_front, yoke_back = -YOKE_T / 2, YOKE_T / 2
base_front = yoke_front - FRONT_T
face_front = base_front - FACE_RAISE
seam = yoke_back + WHITE_BEHIND                      # where white meets blue
THROUGH = (face_front - 5, seam + REAR_T + 5)   # depth range that cuts all the way through

# Yoke: strap with plaster ears, ear slots, mounting-screw slots and the
# plate-screw hole in the middle.
yoke = prism('01_Metal_Yoke', yoke_outline(), yoke_front, yoke_back, 'yoke')
hole_z = YOKE_H / 2 - EAR_HOLE_INSET
holes = []   # the plate-screw hole is threaded into the strap, so the metal shows through the front
for sz in (1, -1):
    holes.append(rounded_rect(*MOUNT_SLOT, MOUNT_SLOT[0] / 2, 0, sz * MOUNT_SPACING / 2))
    for sx in (1, -1):
        holes.append(circle(sx * EAR_HOLE_X, sz * hole_z, EAR_HOLE_R))
cut(yoke, holes, *THROUGH)

# Stamped stiffening ribs: a raised wedge on each ear, narrow at the end, widening to the neck.
for label, sz in (('Top', 1), ('Bottom', -1)):
    z0, z1 = sz * (YOKE_H / 2 - 0.6), sz * (YOKE_H / 2 - RELIEF_SLOT_DOWN + 0.2)
    rib = [(-RIB_TOP_W / 2, z0), (RIB_TOP_W / 2, z0), (RIB_BOTTOM_W / 2, z1), (-RIB_BOTTOM_W / 2, z1)]
    prism('01d_Yoke_Rib_' + label, rib, yoke_front - RIB_RAISE, yoke_front + 0.01, 'yoke', RIB_RAISE * 0.8)

# Rear housing outline: domed top and bottom like the faces, straight sides.
rear_outline = rear_housing_outline(REAR_H, BODY_W / 2, REAR_DOME, REAR_FLAT, REAR_FOOT_R)

# Ground bracket: a tab off the strap's edge, a plate running back along the body's
# side, a taller clip part around the screw, and flanges bent outward top and bottom.
bx_in, bx_out = BRACKET_X, BRACKET_X - BRACKET_T
gz, gy = GREEN_SCREW_Z, yoke_back + GREEN_SCREW_DEPTH
box('01b_Ground_Bracket_Tab', (bx_out, -YOKE_W / 2 + 1), (yoke_front, yoke_back),
    (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
box('01c_Ground_Bracket_Plate', (bx_out, bx_in), (yoke_front, gy - BRACKET_CLIP_D / 2),
    (gz - BRACKET_H / 2, gz + BRACKET_H / 2), 'yoke')
clip_y = (gy - BRACKET_CLIP_D / 2, gy + BRACKET_CLIP_D / 2)
box('01d_Ground_Bracket_Clip', (bx_out, bx_in), clip_y, (gz - BRACKET_CLIP_H / 2, gz + BRACKET_CLIP_H / 2), 'yoke')
for label, sz in (('Top', 1), ('Bottom', -1)):
    edge = gz + sz * BRACKET_CLIP_H / 2
    box('01e_Ground_Bracket_Flange_' + label, (bx_out - BRACKET_FLANGE, bx_out), clip_y,
        tuple(sorted((edge, edge - sz * BRACKET_T))), 'yoke')

# Rear housing: behind the yoke.
rear = prism('02_Rear_Housing', rear_outline, seam, seam + REAR_T, 'rear')
pocket = [(POCKET_X[0], POCKET_Z[0]), (POCKET_X[1], POCKET_Z[0]), (POCKET_X[1], POCKET_Z[1]), (POCKET_X[0], POCKET_Z[1])]
cut(rear, [pocket], seam - 1, seam + REAR_T + 1)
waist_w = BODY_W / 2 - REAR_WAIST_HALF_W + REAR_WAIST_FILLET + 1
waist_h = REAR_WAIST_Z[0] - REAR_WAIST_Z[1]
cut(rear, [rounded_rect(waist_w, waist_h, REAR_WAIST_FILLET,
                        sx * (REAR_WAIST_HALF_W + waist_w / 2), sum(REAR_WAIST_Z) / 2) for sx in (1, -1)],
    seam - 1, seam + REAR_T + 1)

# Front base: in front of the yoke, the same outline as the rear housing so the
# white covers the blue from the front. It pinches in beside the terminals, and
# the plate-screw hole goes through the middle.
front = prism('03_Front_Housing', front_housing_outline(REAR_H, BODY_W / 2, REAR_DOME, REAR_FLAT),
              base_front, seam, 'front')
waist = [rounded_rect(BODY_W / 2 - BRIDGE_W / 2 + 1, WAIST_H, 1.0, sx * (BRIDGE_W / 2 + (BODY_W / 2 - BRIDGE_W / 2 + 1) / 2), WAIST_Z)
         for sx in (1, -1)]
cut(front, waist + [circle(0, 0, PLATE_SCREW_R)], *THROUGH)

# Faces: hot (short, right), neutral (long, left), D-shaped ground below.
for label, cz in (('Top', FACE_SPACING / 2), ('Bottom', -FACE_SPACING / 2)):
    face = prism('04_Face_' + label, face_outline(cz), face_front, base_front, 'front',
                 FACE_CHAMFER, (0, cz))
    sz = cz + SLOT_Z
    openings = [rounded_rect(SLOT_W, HOT_L, SLOT_CORNER, SLOT_X, sz),
                rounded_rect(SLOT_W, NEUTRAL_L, SLOT_CORNER, -SLOT_X, sz),
                ground_d(0, cz + GROUND_Z, GROUND_R)]
    cut(face, openings, face_front - 1, face_front + OPENING_DEPTH)
    darken_openings(face, openings, face_front)
    tr = rounded_rect(TR_MARK[0], TR_MARK[0], 0.3, 0, sz)
    cut(face, [tr], face_front - 1, face_front + TR_MARK[1])


# --- Screws --------------------------------------------------------------------

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


for label, sz in (('Top', 1), ('Bottom', -1)):
    front_screw('05_Mount_Screw_' + label, 0, sz * MOUNT_SPACING / 2, MOUNT_HEAD, MOUNT_SHANK, 'steel', True)
    wz, ww = sz * MOUNT_SPACING / 2, WASHER[0] / 2
    box('05b_Mount_Washer_' + label, (-ww, ww), (yoke_back, yoke_back + WASHER[1]), (wz - ww, wz + ww), 'rear')

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


# Side terminals: brass (hot) on the right, silver (neutral) on the left. Each side has
# one tall plate under both screws, a break-off tab sticking forward from its middle,
# and a blue divider rib across the pocket between the screws.
term_y = yoke_back + TERM_DEPTH
plate_half = TERM_PLATE[0] / 2
plate_z = (min(TERM_Z) - TERM_PLATE_PAD, max(TERM_Z) + TERM_PLATE_PAD)
mid = sum(TERM_Z) / 2
recess_z = (plate_z[0] - 0.6, plate_z[1] + 0.6)
recess_y = (seam - 0.5, term_y + plate_half + 1.5)     # open to the front, so the threads show
for side in (1, -1):
    x0, x1 = sorted((side * TERM_RECESS_X, side * (BODY_W / 2 + 1)))
    cut(rear, [[(x0, recess_z[0]), (x1, recess_z[0]), (x1, recess_z[1]), (x0, recess_z[1])]], *recess_y)
for side, color, axis in ((1, 'brass', '+X'), (-1, 'silver', '-X')):
    wall = side * TERM_RECESS_X
    face_x = wall + side * TERM_PLATE[1]
    xs = tuple(sorted((wall, face_x)))
    name = color.capitalize()
    box('07_%s_Plate' % name, xs, (term_y - plate_half, term_y + plate_half), plate_z, color + '_plate')
    box('07_%s_Break_Tab' % name, xs, (term_y - plate_half - BREAK_TAB[0], term_y - plate_half + 0.5),
        (mid - BREAK_TAB[1] / 2, mid + BREAK_TAB[1] / 2), color)
    # The white bridge between the faces reaches back to the plate's front edge.
    bridge_x = tuple(sorted((side * (TERM_RECESS_X - 1.0), side * (TERM_RECESS_X + 0.02))))
    box('03b_Bridge_Side_%s' % name, bridge_x, (seam - 0.5, term_y - plate_half), recess_z, 'front')
    divider_x = tuple(sorted((face_x, side * REAR_WAIST_HALF_W)))
    box('07_%s_Divider' % name, divider_x, (term_y - plate_half + 2.0, recess_y[1]),
        (mid - DIVIDER_H / 2, mid + DIVIDER_H / 2), 'rear')
    for label, z in zip(('Top', 'Bottom'), TERM_Z):
        thread('07_%s_Terminal_%s_Thread' % (name, label), TERM_THREAD, TERM_THREAD_L, (face_x, term_y, z), axis, color)
        side_screw('07_%s_Terminal_%s' % (name, label), face_x + side * TERM_THREAD_L, term_y, z, side, TERM_HEAD, color)

# Green ground screw: hex washer head, backed out, threaded in sideways through the clip.
x = bx_out
thread('06_Ground_Screw_Thread', GREEN_THREAD_SPEC, GREEN_THREAD[1], (x, gy, gz), '-X', 'green')
x -= GREEN_THREAD[1]
revolve('06_Ground_Screw_Washer', [(GREEN_WASHER[0], 0), (GREEN_WASHER[0], GREEN_WASHER[1])], (x, gy, gz), '-X', 'green')
x -= GREEN_WASHER[1]
hexhead = revolve('06_Ground_Screw', [(GREEN_HEX[0], 0), (GREEN_HEX[0], GREEN_HEX[1])], (x, gy, gz), '-X', 'green', 6)
top, g, rr = x - GREEN_HEX[1], SLOT_GAP / 2, GREEN_HEX[0] * 0.75
cut_with(hexhead, [box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - g, gy + g), (gz - rr, gz + rr)),
                   box('Cutter', (top - 1, top + GREEN_HEX[1] * 0.5), (gy - rr * 0.6, gy + rr * 0.6), (gz - g, gz + g))])

# Back detail: wire holes and release slots, the stepped-down foot with its strip
# gauge, and the recessed barcode label.
back = seam + REAR_T

# Recessed back panel: sink it by BACK_RIM, leaving a raised rim round the edge.
n = 48
dome = rear_housing_outline(2 * (REAR_H / 2 - PANEL_INSET_TOP), PANEL_HALF_W, REAR_DOME - 1.5, REAR_FLAT, 1.0, n)[:n // 2 + 1]
w0, w1, (za, zb), st = PANEL_HALF_W, PANEL_WAIST_HALF_W, PANEL_WAIST_Z, PANEL_STEP
left = [(-w0, za), (-w1, za - st), (-w1, zb + st), (-w0, zb), (-w0, FOOT_STEP_Z)]
panel = dome + left + [(-x, z) for x, z in reversed(left)]
cut(rear, [panel], back - BACK_RIM, back + 1)
floor = back - BACK_RIM     # the recessed panel's surface: holes, label and lettering sit here
holes = []
for sx in (1, -1):
    for hz, slz in zip(BACK_HOLE_Z, BACK_SLOT_Z):
        holes.append(circle(sx * BACK_HOLE_X, hz, BACK_HOLE_R, 16))
        holes.append(rounded_rect(*BACK_SLOT, 0.2, sx * BACK_HOLE_X, slz))
x0, x1, gz, gw, gd = STRIP_GAUGE
foot = [(-BODY_W, FOOT_STEP_Z), (BODY_W, FOOT_STEP_Z), (BODY_W, -REAR_H), (-BODY_W, -REAR_H)]
cut(rear, [foot], back - FOOT_STEP, back + 1)
gauge = rounded_rect(x1 - x0, gw, 0.3, (x0 + x1) / 2, gz)
cut(rear, [gauge], back - FOOT_STEP - gd, back + 1)
label = rounded_rect(*LABEL, 0.8, 0, LABEL_Z)
cut(rear, [label], floor - LABEL_RECESS, back + 1)
cut(rear, holes, floor - BACK_HOLE_DEPTH, back + 1)
darken_openings(rear, holes, floor, inward=-1)
prism('08_Back_Label', rounded_rect(LABEL[0] - 0.4, LABEL[1] - 0.4, 0.6, 0, LABEL_Z),
      floor - LABEL_RECESS, floor - LABEL_RECESS + 0.1, 'label')

# --- Molded text ---------------------------------------------------------------
# Real lettering, raised a fraction of a millimetre off the plastic. Orientations
# map the font's (right, up, out) onto the part.
FACING = {
    'front': Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))),   # read from the front
    'back': Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))),    # read from behind
}
TEXT_RAISE = 0.15           # how far molded lettering stands off its surface


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


# "TR" (tamper resistant), raised inside the little recess on each face.
for label, cz in (('Top', FACE_SPACING / 2), ('Bottom', -FACE_SPACING / 2)):
    molded_text('09_TR_' + label, 'TR', TR_MARK[0] * 0.62, (0, face_front + TR_MARK[1], cz + SLOT_Z), 'front', 'front')

# Back: wire labels up each column, install text across the dome, strip gauge on the foot.
for sx, line1, line2 in ((1, 'HOT WIRE', 'PRESS TO RELEASE'), (-1, 'WHITE WIRE', 'PRESS TO RELEASE')):
    molded_text('09_Back_%s' % line1.split()[0].title(), line1, 1.9, (sx * BACK_HOLE_X, floor, 5.5), 'back', 'rear', turn=90)
    molded_text('09_Back_%s_Release' % line1.split()[0].title(), line2, 1.1, (sx * (BACK_HOLE_X - 2.4), floor, 5.5),
                'back', 'rear', turn=90)
for i, line in enumerate(('CU WIRE ONLY', '15A 125V~', 'INSTALLATION')):
    molded_text('09_Back_Line_%d' % i, line, 1.5, (0, floor, 28.6 - i * 2.3), 'back', 'rear')
molded_text('09_Back_Strip_Gage', 'STRIP GAGE', 1.4, ((x0 + x1) / 2, back - FOOT_STEP, gz + 2.0), 'back', 'rear')


# --- Surface materials -----------------------------------------------------------
# Procedural (node-based) looks. These show in Material Preview / EEVEE / Cycles,
# not in the flat Workbench view. Each knob below is one number.
SURFACE = {
    #  key:          (metallic, roughness, bump strength, bump scale)
    'front':        (0.0, 0.38, 0.03, 4000),   # glossy white nylon, faint grain
    'rear':         (0.0, 0.45, 0.04, 3000),   # blue thermoplastic
    'yoke':         (0.85, 0.45, 0.12, 6000),  # galvanized steel, fine speckle
    'steel':        (1.0, 0.18, 0.00, 0),   # polished zinc plating
    'brass':        (1.0, 0.40, 0.00, 0),
    'silver':       (1.0, 0.38, 0.00, 0),
    'brass_plate':  (1.0, 0.35, 0.00, 0),
    'silver_plate': (1.0, 0.32, 0.00, 0),
    'green':        (0.3, 0.35, 0.00, 0),
}
GALV_SPANGLE = 700          # galvanized "spangle" crystal size (higher = finer)
GALV_TONE = ((.30, .31, .33), (.60, .61, .62))   # darkest and lightest steel tones
GALV_CLOUD = 2500           # scale of the fine cloudy mottling
PLATE_DIMPLE = 1000         # dimple spacing on the terminal plates (higher = finer)
PLATE_DIMPLE_DEPTH = 1.0    # how strongly the dimples read


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


for key in SURFACE:
    if bpy.data.materials.get(key.capitalize() + '_Material'):
        surface_material(key)


# --- Barcode label ------------------------------------------------------------------
# A generated (made-up) barcode, packed into the .blend, mapped onto the sticker.
BARCODE_SEED = 270
BARCODE_RES = (512, 64)


def barcode_image():
    import random
    rng = random.Random(BARCODE_SEED)
    w, h = BARCODE_RES
    bars, x = [], int(w * 0.08)
    while x < w * 0.92:
        width = rng.choice((2, 2, 3, 4, 6))
        bars.append((x, x + width))
        x += width + rng.choice((2, 3, 4, 5))
    img = bpy.data.images.new('TR270_Barcode', w, h)
    px = [1.0] * (w * h * 4)
    for y in range(int(h * 0.15), int(h * 0.85)):
        for a, b in bars:
            for xx in range(a, min(b, w)):
                i = (y * w + xx) * 4
                px[i:i + 3] = (0.02, 0.02, 0.02)
    img.pixels = px
    img.pack()
    return img


label_obj = bpy.data.objects.get('08_Back_Label')
if label_obj:
    mat = bpy.data.materials.new('Label_Barcode_Material')
    mat.use_nodes = True
    mat.diffuse_color = (*COLORS['label'], 1)
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = 0.5
    coord = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    comb = nt.nodes.new('ShaderNodeCombineXYZ')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = barcode_image()
    tex.interpolation = 'Closest'
    _link(nt, coord.outputs['Generated'], sep.inputs['Vector'])
    _link(nt, sep.outputs['Z'], comb.inputs['X'])     # bars run across the label, stacked up its length
    _link(nt, sep.outputs['X'], comb.inputs['Y'])
    _link(nt, comb.outputs['Vector'], tex.inputs['Vector'])
    _link(nt, tex.outputs['Color'], bsdf.inputs['Base Color'])
    label_obj.data.materials.clear()
    label_obj.data.materials.append(mat)

# Small parts: pull the viewport near-clip in so they don't get cut off up close.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.clip_start = 0.0001

print('Created TR270 dimensional BLOCKOUT. Component shapes are provisional.')
