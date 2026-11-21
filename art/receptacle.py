"""A standard 15 A, 125 V duplex receptacle (NEMA 5-15R), modelled from a
product photo: white faces with a narrow hot slot, a wide neutral slot and a
D-shaped ground hole; the centre bridge with the plate screw's hole; the
steel strap (yoke) with its plaster ears, mounting screws and a green ground
screw; brass terminal screws on the right joined by a break-off tab, silver
ones on the left; the body behind.

Run from the project root:
    blender --background --python art/receptacle.py

Writes art/receptacle.blend and assets/receptacle/receptacle.glb.

Laid out like the game's devices (kit.py): metres, +Y up, +Z out of the wall,
origin at the middle of the box opening, the strap's back on the wall plane.
The terminal screws, faces and mounting screws sit where BoxView.SPEC
["Receptacle"] puts them, so it can replace the plain "Duplex" model.
Each part is its own object, under one empty, "DuplexReceptacle".
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import ART, ROOT, finish, lathe, material, reset, span, to_blender_axes  # noqa: E402

OUT = os.path.join(ROOT, "assets", "receptacle")

FACE_Y = 0.0195          # each face's centre, up and down from the middle
FACE_R = 0.0172          # the faces are circles...
FACE_FLAT = 0.0142       # ...cut flat top and bottom
FACE_BACK = 0.0015       # on the strap
FACE_FRONT = 0.0105      # the face you plug into
BODY_W = 0.0172          # half its width
BODY_H = 0.0345
BODY_BACK = -0.032
STRAP_T = 0.0012
MOUNT_Y = 0.0417         # the screws into the box
TERM_X = 0.0175          # the body's sides, where the terminal screws are
TERM_Y = (0.018, -0.021)
TERM_Z = -0.014


def materials():
    return {
        "face": material("ReceptacleWhite", (0.86, 0.86, 0.83), 0.0, 0.35),
        "back": material("ReceptacleBack", (0.32, 0.5, 0.75), 0.0, 0.45),
        "hole": material("SlotDark", (0.01, 0.01, 0.01), 0.0, 0.9),
        "strap": material("StrapZinc", (0.62, 0.64, 0.66), 0.9, 0.38),
        "brass": material("TerminalBrass", (0.78, 0.58, 0.24), 1.0, 0.3),
        "silver": material("TerminalSilver", (0.8, 0.81, 0.82), 1.0, 0.25),
        "green": material("GroundGreen", (0.08, 0.45, 0.14), 0.6, 0.35),
    }


# --- Shapes ------------------------------------------------------------------------------

def face_outline(cy, n=48):
    """A face: a circle cut flat top and bottom."""
    pts = []
    for i in range(n):
        a = math.tau * i / n
        x, y = math.cos(a) * FACE_R, math.sin(a) * FACE_R
        pts.append((x, cy + max(-FACE_FLAT, min(FACE_FLAT, y))))
    return pts


def slab(name, outline, z0, z1, mat, chamfer=0.0, centre=(0.0, 0.0)):
    """An outline pushed out from z0 to z1, its front edge chamfered in."""
    bm = bmesh.new()
    cx, cy = centre

    def ring(z, inset):
        out = []
        for x, y in outline:
            d = Vector((x - cx, y - cy))
            s = max(d.length - inset, 0.0) / d.length if d.length > 0 else 1.0
            out.append(bm.verts.new((cx + d.x * s, cy + d.y * s, z)))
        return out
    rings = [ring(z0, 0.0), ring(z1 - chamfer, 0.0)]
    if chamfer > 0.0:
        rings.append(ring(z1, chamfer))
    n = len(outline)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(name, bm, mat, 40)


def cut(obj, cutters):
    """Cuts every cutter out of obj, then throws the cutters away."""
    for c in cutters:
        mod = obj.modifiers.new("Cut", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = c
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(c)
    return obj


def rounded_rect(hw, y0, y1, r, cx=0.0, seg=4):
    pts = []
    for ox, oy, a0 in ((cx + hw - r, y0 + r, -90), (cx + hw - r, y1 - r, 0), (cx - hw + r, y1 - r, 90), (cx - hw + r, y0 + r, 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def circle(cx, cy, r, n=16):
    return [(cx + math.cos(math.tau * i / n) * r, cy + math.sin(math.tau * i / n) * r) for i in range(n)]


def d_shape(cx, cy, r, n=16):
    """The ground hole: round at the bottom, flat across the top."""
    return [(cx + math.cos(a) * r, cy + min(math.sin(a) * r, r * 0.45)) for a in (math.tau * i / n for i in range(n))]


def cutter(outline, z0=-0.01, z1=0.03):
    return slab("Cutter", outline, z0, z1, bpy.data.materials["SlotDark"])


def binding_screw(name, centre, axis, mat, r=0.0044):
    """A terminal screw's head on the side of the body: a big flat binding head, slotted."""
    head = lathe(name, [(0.0001, 0.0), (0.0018, 0.0), (0.0018, 0.0012), (r, 0.0012), (r, 0.0026), (r * 0.9, 0.0036), (0.0001, 0.0039)],
            centre, axis, mat, 20)
    slot = span(name + "Slot", (-0.0006, 0.0006), (-r * 0.82, r * 0.82), (0.0028, 0.0041), bpy.data.materials["SlotDark"])
    sign = 1.0 if axis == "RIGHT" else -1.0
    slot.data.transform(Matrix.Rotation(sign * math.pi / 2, 4, "Y"))
    slot.data.transform(Matrix.Translation(Vector(centre)))
    return join_parts([head, slot], name)


def face_screw(name, centre, mat, r=0.0034, h=0.0022, cross=True):
    """A pan-head screw facing out, with a combination slot-and-cross."""
    head = lathe(name, [(0.0001, 0.0), (r, 0.0), (r, h * 0.4), (r * 0.78, h * 0.85), (0.0001, h)], centre, "OUT", mat, 18)
    c = Vector(centre)
    parts = [head, span(name + "Slot", (c.x - r * 0.82, c.x + r * 0.82), (c.y - 0.00045, c.y + 0.00045), (c.z + h * 0.5, c.z + h * 1.02),
            bpy.data.materials["SlotDark"])]
    if cross:
        parts.append(span(name + "Cross", (c.x - 0.00045, c.x + 0.00045), (c.y - r * 0.45, c.y + r * 0.45), (c.z + h * 0.5, c.z + h * 1.02),
                bpy.data.materials["SlotDark"]))
    return join_parts(parts, name)


def join_parts(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


# --- The receptacle ------------------------------------------------------------------------

def build(m):
    parts = []
    # The body behind the faces: white at the front, the back housing behind.
    front = slab("BodyFront", rounded_rect(BODY_W, -BODY_H, BODY_H, 0.004), -0.012, FACE_BACK, m["face"], 0.0005)
    parts.append(front)
    parts.append(slab("BodyBack", rounded_rect(BODY_W - 0.0008, -BODY_H + 0.0008, BODY_H - 0.0008, 0.004), BODY_BACK, -0.0118, m["back"], 0.0015))

    # The two faces, the slots and the ground hole cut right through, dark inside.
    for i, cy in enumerate((FACE_Y, -FACE_Y)):
        face = slab("Face%d" % i, face_outline(cy), FACE_BACK, FACE_FRONT, m["face"], 0.0012, (0.0, cy))
        slot_y = cy + 0.0042
        holes = [rounded_rect(0.0009, slot_y - 0.0032, slot_y + 0.0032, 0.0004, 0.00635),     # hot: the narrow one, on the right
                 rounded_rect(0.0009, slot_y - 0.004, slot_y + 0.004, 0.0004, -0.00635),       # neutral: the wide one, on the left
                 d_shape(0.0, cy - 0.0078, 0.0026)]                                           # ground
        cut(face, [cutter(h) for h in holes])
        parts.append(face)
        for j, h in enumerate(holes):
            parts.append(slab("Face%dHole%d" % (i, j), [(x * 1.0, y) for x, y in h], 0.0035, 0.0045, m["hole"]))
    # The bridge between the faces, with the hole the plate screw goes into.
    bridge = slab("Bridge", rounded_rect(0.0075, -0.0058, 0.0058, 0.002), FACE_BACK, FACE_FRONT - 0.0012, m["face"], 0.0008)
    cut(bridge, [cutter(circle(0.0, 0.0, 0.0017, 6))])
    parts.append(bridge)
    parts.append(slab("BridgeHole", circle(0.0, 0.0, 0.0019, 6), 0.002, 0.0028, m["hole"]))

    # The strap: full length, wider at the ears, with the plaster-ear holes and
    # the slots the mounting screws sit in.
    outline = []
    for x, y in ((0.0, -0.0605), (0.022, -0.0605), (0.022, -0.0455), (0.0125, -0.0425), (0.0125, 0.0425), (0.022, 0.0455),
                 (0.022, 0.0605), (-0.022, 0.0605), (-0.022, 0.0455), (-0.0125, 0.0425), (-0.0125, -0.0425), (-0.022, -0.0455),
                 (-0.022, -0.0605)):
        outline.append((x, y))
    strap = slab("Strap", outline, 0.0, STRAP_T, m["strap"], 0.0002, (0.0, 0.0))
    holes = []
    for sy in (1.0, -1.0):
        holes.append(rounded_rect(0.0034, sy * 0.0556 - 0.0024, sy * 0.0556 + 0.0024, 0.0023, 0.0155))    # plaster ears
        holes.append(rounded_rect(0.0034, sy * 0.0556 - 0.0024, sy * 0.0556 + 0.0024, 0.0023, -0.0155))
        holes.append(rounded_rect(0.0019, sy * MOUNT_Y - 0.0032, sy * MOUNT_Y + 0.0032, 0.0018))         # the screw's slot
    cut(strap, [cutter(h) for h in holes])
    # A tab off the strap's lower left for the ground screw.
    tab = slab("GroundTab", rounded_rect(0.0042, -0.0465, -0.0385, 0.0015, -0.0162), 0.0, STRAP_T, m["strap"], 0.0002, (-0.0162, -0.0425))
    parts += [strap, tab]

    # Screws: the two that hold it in the box, the green ground, and the four
    # terminals with the plates they clamp on and the break-off tabs between.
    for i, y in enumerate((MOUNT_Y, -MOUNT_Y)):
        parts.append(face_screw("MountScrew%d" % i, (0.0, y, STRAP_T), m["strap"]))
    parts.append(face_screw("GroundScrew", (-0.0162, -0.0425, STRAP_T), m["green"], 0.0031, 0.0026, cross=False))
    for side, mat, name, axis in ((1.0, m["brass"], "Brass", "RIGHT"), (-1.0, m["silver"], "Silver", "LEFT")):
        x = side * TERM_X
        for y, where in zip(TERM_Y, ("Top", "Bottom")):
            plate = span("%sPlate%s" % (name, where), sorted((x, x + side * 0.0009)), (y - 0.0048, y + 0.0048), (TERM_Z - 0.0048, TERM_Z + 0.0048), mat, 0.0003)
            parts.append(plate)
            parts.append(binding_screw("%sScrew%s" % (name, where), (x + side * 0.0009, y, TERM_Z), axis, mat))
        # The break-off tab joining the two: snap it to split the receptacle.
        y0, y1 = TERM_Y[1] + 0.0048, TERM_Y[0] - 0.0048
        tab = span("%sBreakTab" % name, sorted((x, x + side * 0.0009)), (y0, y1), (TERM_Z - 0.0022, TERM_Z + 0.0022), mat, 0.0002)
        notch = span("Notch", sorted((x - side * 0.001, x + side * 0.002)), (-0.0015, 0.0005), (TERM_Z - 0.003, TERM_Z + 0.003), m["hole"])
        cut(tab, [notch])
        parts.append(tab)
    return parts


def main():
    os.makedirs(OUT, exist_ok=True)
    reset()
    m = materials()
    parts = build(m)
    for p in parts:                     # crisp edges, smooth curves: sharp wherever it bends more than 30 degrees
        for poly in p.data.polygons:
            poly.use_smooth = True
        p.data.set_sharp_from_angle(angle=math.radians(30))
    to_blender_axes(parts)
    root = bpy.data.objects.new("DuplexReceptacle", None)
    bpy.context.collection.objects.link(root)
    for p in parts:
        p.parent = root
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for p in parts:
        p.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "receptacle.glb"), export_format="GLB", use_selection=True, export_yup=True)
    tris = 0
    for p in parts:
        p.data.calc_loop_triangles()
        tris += len(p.data.loop_triangles)
    print("EXPORTED receptacle.glb", len(parts), "parts", tris, "tris")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "receptacle.blend"))


main()
