"""Finishes the electric water heater: real-size tank, two element/thermostat
access covers curved to the tank, screws, the thermostats and elements in
pockets behind them, a drain valve, the connections on top (junction box
and supply whip; cold inlet with its shut-off, hot outlet; T&P relief valve and
its discharge pipe), materials; saves a new .blend and exports a .glb for Godot.

    blender -b blend/water_heater.blend --python art/water_heater_covers.py

The original blend/water_heater.blend is never written to. Output:
    blend/water_heater_with_covers.blend
    assets/water_heater/water_heater.glb

Units are metres, Z up, the front of the heater faces -Y (it imports into
Godot facing +Z). The tank's origin is the middle of its base, on the floor.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_BLEND = os.path.join(ROOT, "blend", "water_heater_with_covers.blend")
OUT_GLB = os.path.join(ROOT, "assets", "water_heater", "water_heater.glb")

## The tank's paint, and the junction plate and cover's: the owner's tank is gray.
SHELL_COLOUR = (0.6, 0.61, 0.63)
SHELL_METAL = 0.75      # 0 flat paint, 1 bare steel
SHELL_ROUGH = 0.38      # lower is shinier
TANK_DIAMETER = 0.56
TANK_HEIGHT = 1.5

COVER_W = 0.15          # across the front, measured round the curve
COVER_H = 0.14
COVER_D = 0.015         # how far it stands off the tank
CORNER_R = 0.012        # rounded corners
EDGE_CHAMFER = 0.0025   # the softened front edge
SINK = 0.001            # its back sits this far into the tank, so there's never a gap
COVERS = {"UpperThermostatCover": 1.10, "LowerThermostatCover": 0.50}   # centre height above the floor

SCREW_R = 0.0045
SCREW_H = 0.003
SCREW_FROM_EDGE = 0.018

# The top. Looking at the front: cold on the right (+X), hot on the left, the
# junction box at the front, the T&P valve at the back. Pipes and the whip run
# up to CEILING, the laundry ceiling in the game's house.
CEILING = 2.55
NIPPLE_R = 0.0134       # 3/4 in steel pipe, 26.7 mm
COPPER_R = 0.0111       # 3/4 in copper, 22.2 mm
COLD_AT = (0.12, 0.0)
HOT_AT = (-0.12, 0.0)
TP_AT = (0.0, 0.15)
# The electrical connection, as on a real heater: a pocket let into the top
# front edge holds the splices; a flat plate behind it takes the conduit; a
# cover curved over the edge closes the pocket. Sizes in metres.
POCKET_HALF_W = 0.055
POCKET_BACK = 0.18      # how far the pocket reaches in from the front (from the axis: y = -POCKET_BACK)
POCKET_DEPTH = 0.045
PLATE_Y = (-0.188, -0.07)
PLATE_HALF_W = 0.07
PLATE_CORNER = 0.03
WHIP_AT = (-0.012, -0.125)
KNOCKOUT_AT = (0.0, -0.235)  # the hole in the pocket floor the heater's leads come up through
WHIP_R = 0.009          # 3/8 in flexible metal conduit


# --- Materials ---------------------------------------------------------------------

def material(name, rgb, rough, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


# --- The tank: to real size, standing on the floor ---------------------------------------

def find_tank():
    """The existing tank: the tallest mesh in the file (anything else, like a
    test block, is left alone and not exported)."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    assert meshes, "no meshes in the file"
    def height(o):
        lo, hi = world_bounds(o)
        return hi.z - lo.z
    tank = max(meshes, key=height)
    assert height(tank) > 1.0, "no mesh tall enough to be the tank: %s" % [o.name for o in meshes]
    others = [o.name for o in meshes if o != tank]
    if others:
        print("left alone, not exported:", others)
    return tank


def world_bounds(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def fit_tank(tank):
    """Scales the tank to 560 mm x 1.5 m, bakes the scale into the mesh, and
    puts its origin at the middle of its base, on the floor (z = 0). The mesh
    itself (vertex count, faces, the smoothing modifier) is unchanged."""
    lo, hi = world_bounds(tank)
    size = hi - lo
    centre = (lo + hi) / 2
    print("tank before: %.3f x %.3f x %.3f m, base at z=%.3f" % (size.x, size.y, size.z, lo.z))
    sx = TANK_DIAMETER / size.x
    sz = TANK_HEIGHT / size.z
    me = tank.data
    for v in me.vertices:
        w = tank.matrix_world @ v.co                     # world position now
        v.co = Vector(((w.x - centre.x) * sx, (w.y - centre.y) * sx, (w.z - lo.z) * sz))
    tank.location = (centre.x, centre.y, 0.0)
    tank.rotation_euler = (0, 0, 0)
    tank.scale = (1, 1, 1)
    me.update()
    bpy.context.view_layer.update()                     # matrix_world is stale until the scene updates
    lo, hi = world_bounds(tank)
    size = hi - lo
    print("tank after:  %.3f x %.3f x %.3f m, base at z=%.3f" % (size.x, size.y, size.z, lo.z))
    return (lo + hi) / 2, size.x / 2


# --- A cover, curved to the tank ----------------------------------------------------------

def rounded_rect_columns(w, h, r, corner_steps=4, max_step=0.03):
    """Columns across a rounded rectangle: [(x, z_top)] from left to right.
    The bottom of each column is -z_top. Corner columns follow the arc."""
    xs = []
    for i in range(corner_steps + 1):                   # left corner, across its arc
        a = math.pi / 2 * i / corner_steps
        xs.append(-w / 2 + r - r * math.cos(a))
    inner = w - 2 * r
    n = max(1, math.ceil(inner / max_step))
    for i in range(1, n):
        xs.append(-w / 2 + r + inner * i / n)
    for x in reversed(xs[: corner_steps + 1]):          # right corner, mirrored
        xs.append(-x)
    cols = []
    for x in xs:
        dx = max(0.0, abs(x) - (w / 2 - r))
        top = h / 2 - r + math.sqrt(max(0.0, r * r - dx * dx))
        cols.append((x, top))
    return cols


def cover_mesh(name, tank_r):
    """A rounded-rectangle panel bent round a cylinder of radius tank_r, as a
    shell: a back against the tank, sides, and a front with a chamfered edge.
    Local origin: the middle of the cover, on the tank's surface; -Y is out."""
    cols = rounded_rect_columns(COVER_W, COVER_H, CORNER_R)
    shrink_w = (COVER_W - 2 * EDGE_CHAMFER) / COVER_W
    shrink_h = (COVER_H - 2 * EDGE_CHAMFER) / COVER_H
    # Three layers: back (in the tank a hair), the outer edge, and the front face set in by the chamfer.
    layers = [(-SINK, 1.0, 1.0), (COVER_D - EDGE_CHAMFER, 1.0, 1.0), (COVER_D, shrink_w, shrink_h)]

    def place(u, z, out):
        a = u / tank_r                                  # arc length along the surface -> angle
        r = tank_r + out
        return Vector((r * math.sin(a), -r * math.cos(a) + tank_r, z))

    bm = bmesh.new()
    rings = []
    for out, kw, kh in layers:
        tops = [bm.verts.new(place(x * kw, z * kh, out)) for x, z in cols]
        bots = [bm.verts.new(place(x * kw, -z * kh, out)) for x, z in cols]
        rings.append(tops + list(reversed(bots)))       # round the outline
    n = len(cols)
    for layer in (0, 2):                                # back and front faces, as vertical strips
        ring = rings[layer]
        for i in range(n - 1):
            quad = [ring[i], ring[i + 1], ring[2 * n - 2 - i], ring[2 * n - 1 - i]]
            bm.faces.new(quad if layer == 2 else list(reversed(quad)))
    for a, b in ((0, 1), (1, 2)):                       # the sides, then the chamfer
        ra, rb = rings[a], rings[b]
        m = len(ra)
        for i in range(m):
            bm.faces.new([ra[i], ra[(i + 1) % m], rb[(i + 1) % m], rb[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def screw_mesh(name):
    """A low-poly pan head, axis along -Y, its underside at y = 0."""
    bm = bmesh.new()
    seg = 10
    ring_lo = []
    ring_hi = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        x, z = math.cos(a) * SCREW_R, math.sin(a) * SCREW_R
        ring_lo.append(bm.verts.new((x, 0.0, z)))
        ring_hi.append(bm.verts.new((x * 0.85, -SCREW_H, z * 0.85)))   # a slightly domed top
    top = bm.verts.new((0.0, -SCREW_H - 0.0006, 0.0))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new([ring_lo[i], ring_lo[j], ring_hi[j], ring_hi[i]])
        bm.faces.new([ring_hi[i], ring_hi[j], top])
    bm.faces.new(list(reversed(ring_lo)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def cylinder_mesh(name, r, h, seg=12, z0=0.0):
    """An upright cylinder, capped, from z0 to z0 + h."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=h)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, z0 + h / 2))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def box_mesh(name, size, centre=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=centre)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def tube_mesh(name, points, r, seg=10):
    """A capped tube along a path of points, mitred at the bends."""
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d_in = (p - pts[i - 1]).normalized() if i > 0 else None
        d_out = (pts[i + 1] - p).normalized() if i < len(pts) - 1 else None
        d = (d_in + d_out).normalized() if d_in and d_out else (d_in or d_out)
        scale = 1.0
        if d_in and d_out:
            scale = 1.0 / max(0.5, math.cos(d_in.angle(d_out) / 2))
        if not rings:                                   # first ring: any square-on frame
            ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            u = d.cross(ref).normalized()
        else:                                           # then carry it along, so the tube never twists
            u = (u - d * u.dot(d)).normalized()
        v = d.cross(u).normalized()
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            off = u * math.cos(a) * r + v * math.sin(a) * r
            if d_in and d_out:                          # stretch across the mitre
                along = off.dot((d_in - d_out).normalized()) if (d_in - d_out).length > 1e-6 else 0
                off = off + (d_in - d_out).normalized() * along * (scale - 1)
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new([a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def add_object(name, mesh, collection, location, mat, parent=None):
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = location
    obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


# --- The electrical connection --------------------------------------------------------------

def cut_pocket(tank, axis, top, tank_r):
    """Lets the junction pocket into the tank's top front edge. Changes the
    tank's mesh (in the new file only): a box cut out of it with a boolean."""
    cutter = bpy.data.objects.new("PocketCutter", box_mesh("PocketCutter",
            (POCKET_HALF_W * 2, tank_r - POCKET_BACK + 0.05, POCKET_DEPTH + 0.05),
            (axis.x, axis.y - (POCKET_BACK + tank_r + 0.05) / 2, top - POCKET_DEPTH + (POCKET_DEPTH + 0.05) / 2)))
    tank.users_collection[0].objects.link(cutter)
    mod = tank.modifiers.new("Pocket", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = tank
    bpy.ops.object.modifier_move_to_index(modifier="Pocket", index=0)
    bpy.ops.object.modifier_apply(modifier="Pocket")
    bpy.data.objects.remove(cutter)


def wrap_cover_mesh(name, tank_r, top):
    """The pocket's cover: one thin curved sheet across the top of the pocket,
    round the edge and down the front, following the tank's curve both ways."""
    t = 0.0015
    lift = 0.003                                        # stands this far off the tank's side...
    lift_top = 0.0022                                   # ...and on top just clears the tank, under the raised plate's edge
    c = 0.014                                           # a tight bend over the edge, like the real one
    half_w = POCKET_HALF_W + 0.012
    def profile(off):
        """(radius from the axis, height) along the cover, front-bottom last."""
        rs = tank_r + lift - off
        zt = top + lift_top - off
        pts = [(POCKET_BACK - 0.012, zt)]
        cc = (tank_r + lift - c, top + lift_top - c)
        for i in range(7):
            a = (math.pi / 2) * i / 6
            pts.append((cc[0] + (c - off) * math.sin(a), cc[1] + (c - off) * math.cos(a)))
        pts.append((rs, top - POCKET_DEPTH - 0.012))
        return pts
    cols = [-half_w + 2 * half_w * i / 8 for i in range(9)]
    bm = bmesh.new()
    def grid(off):
        return [[bm.verts.new((x, -math.sqrt(max(rho * rho - x * x, 1e-6)), z)) for rho, z in profile(off)] for x in cols]
    outer, inner = grid(0.0), grid(t)
    nc, npf = len(cols), len(outer[0])
    for ci in range(nc - 1):
        for p in range(npf - 1):
            bm.faces.new([outer[ci][p], outer[ci + 1][p], outer[ci + 1][p + 1], outer[ci][p + 1]])
            bm.faces.new([inner[ci][p + 1], inner[ci + 1][p + 1], inner[ci + 1][p], inner[ci][p]])
    for ci in (0, nc - 1):                              # the two sides
        for p in range(npf - 1):
            bm.faces.new([outer[ci][p], outer[ci][p + 1], inner[ci][p + 1], inner[ci][p]])
    for ci in (0, nc - 1):                              # cheeks: close the wedge between the hood and the rim
        x = cols[ci]
        corner = bm.verts.new((x, -math.sqrt(tank_r * tank_r - x * x), top))
        for p in range(npf - 1):
            if outer[ci][p].co.z < top - 0.002 and outer[ci][p + 1].co.z < top - 0.002:
                continue                                # below the rim: the cover's flat on the tank's side here
            bm.faces.new([corner, outer[ci][p], outer[ci][p + 1]])
    for p in (0, npf - 1):                              # the back edge and the bottom edge
        for ci in range(nc - 1):
            bm.faces.new([outer[ci][p], inner[ci][p], inner[ci + 1][p], outer[ci + 1][p]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def wire_nut_mesh(name):
    """A twist-on wire nut, its open end at the origin, pointing up (+Z)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.008, radius2=0.0045, depth=0.022)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.011))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def rounded_slab_mesh(name, half_w, y0, y1, r, h, seg=4):
    """A flat rounded-rectangle plate, x from -half_w to half_w, y from y0 to
    y1, z from 0 to h."""
    cx = [-half_w + r, half_w - r]
    cy = [y0 + r, y1 - r]
    outline = []
    for (ox, oy, a0) in ((cx[1], cy[0], -90), (cx[1], cy[1], 0), (cx[0], cy[1], 90), (cx[0], cy[0], 180)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            outline.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y, 0.0)) for x, y in outline]
    topv = [bm.verts.new((x, y, h)) for x, y in outline]
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(topv)
    n = len(outline)
    for i in range(n):
        bm.faces.new([bottom[i], bottom[(i + 1) % n], topv[(i + 1) % n], topv[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def text_mesh(name, body, size):
    """Lettering as a thin mesh, facing -Y, centred on the origin."""
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = body
    curve.size = size
    curve.extrude = 0.0          # printed, not raised: flat letters only
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    tmp = bpy.data.objects.new(name + "_tmp", curve)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(curve)
    me.name = name
    me.transform(Matrix.Rotation(math.radians(90), 4, "X"))   # lying flat -> standing up, reading from the front
    return me


PLATE_RAISE = 0.004     # the plate stands on a collar this high, so the cover's tongue slides under its front edge
PLATE_T = 0.003
PLATE_CENTRE = (0.0, -0.127)
PLATE_RADII = (0.068, 0.06)
PLATE_LIP = -POCKET_BACK - 0.008   # its straight front edge, just over the back of the pocket


def plate_mesh(name):
    """The round junction plate: an oval, its front cut straight across where
    it overhangs the back of the pocket. z from 0 to PLATE_T."""
    cx, cy = PLATE_CENTRE
    outline = []
    for i in range(40):
        a = 2 * math.pi * i / 40
        x, y = cx + PLATE_RADII[0] * math.cos(a), cy + PLATE_RADII[1] * math.sin(a)
        outline.append((x, max(y, PLATE_LIP)))
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, 0.0)) for x, y in outline]
    hi = [bm.verts.new((x, y, PLATE_T)) for x, y in outline]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    n = len(outline)
    for i in range(n):
        bm.faces.new([lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def pocket_liner_mesh(name, tank_r, floor):
    """The inside of the pocket, painted dark: its floor and back and side
    walls, each a sheet set a hair inside the cut so it never fights the tank.
    The floor's front edge follows the tank's curve. Faces point into the pocket."""
    e = 0.0003
    hw = POCKET_HALF_W - e
    back = -POCKET_BACK - e
    bm = bmesh.new()
    cols = [-hw + 2 * hw * i / 8 for i in range(9)]
    front = [-math.sqrt(tank_r * tank_r - x * x) for x in cols]
    fz = floor + e
    floor_back = [bm.verts.new((x, back, fz)) for x in cols]
    floor_front = [bm.verts.new((x, y, fz)) for x, y in zip(cols, front)]
    for i in range(len(cols) - 1):
        bm.faces.new([floor_back[i], floor_front[i], floor_front[i + 1], floor_back[i + 1]])
    top = -e
    bw = [bm.verts.new((x, back, z)) for x in (-hw, hw) for z in (fz, top)]
    bm.faces.new([bw[0], bw[2], bw[3], bw[1]])
    for sx, fy in ((-hw, front[0]), (hw, front[-1])):
        quad = [bm.verts.new(v) for v in ((sx, back, fz), (sx, fy, fz), (sx, fy, top), (sx, back, top))]
        bm.faces.new(quad if sx < 0 else list(reversed(quad)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Point every face into the pocket's middle.
    middle = Vector((0, (back + front[4]) / 2, (fz + top) / 2))
    for f in bm.faces:
        if f.normal.dot(middle - f.calc_center_median()) < 0:
            f.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def build_electrical(collection, axis, top, steel, paint, conduit):
    """Like the real thing (and the owner's reference picture): a round plate
    on top with the conduit through a locknut in its middle, standing on a
    collar so the cover tucks under its front edge; a dark pocket let into the
    edge in front of it, with a white-ringed knockout the heater's leads come
    up through; the splices in yellow wire nuts, one standing, one lying over;
    the bare ground looped to a green screw on the plate's lip; and a curved
    cover over it all, WARNING across it, screwed into the tank's side."""
    yellow = material("WireNutYellow", (1.0, 0.78, 0.02), 0.35)
    black = material("WireBlack", (0.02, 0.02, 0.022), 0.45)
    red = material("WireRed", (0.75, 0.05, 0.04), 0.4)
    bare = material("BareCopper", (0.8, 0.42, 0.22), 0.3, 1.0)
    green = material("GroundGreen", (0.05, 0.6, 0.12), 0.35, 0.2)
    dark = material("KnockoutDark", (0.02, 0.02, 0.02), 0.9)
    liner = material("PocketInside", (0.07, 0.07, 0.075), 0.7, 0.2)
    ink = material("LabelInk", (0.12, 0.12, 0.13), 0.6)
    tank_r = TANK_DIAMETER / 2
    floor = -POCKET_DEPTH
    lift = PLATE_RAISE
    plate = add_object("ElectricalJunctionPlate", plate_mesh("ElectricalJunctionPlate"), collection,
            Vector((axis.x, axis.y, top + lift)), paint)
    # Everything else is placed from the tank's top surface (z = 0 below means
    # top), so undo the plate's lift for its children.
    def at(x, y, z):
        return Vector((x, y, z - lift))
    add_object("ElectricalJunctionPlate_Collar", cylinder_mesh("ElectricalJunctionPlate_Collar", 0.032, lift, 16, z0=-lift),
            collection, Vector((PLATE_CENTRE[0], PLATE_CENTRE[1], 0)), paint, parent=plate)
    for i, (x, y) in enumerate(((-0.05, -0.135), (0.04, -0.085))):
        sc = add_object("ElectricalJunctionPlate_Screw%d" % (i + 1), screw_mesh("ElectricalJunctionPlate_Screw%d" % (i + 1)),
                collection, Vector((x, y, PLATE_T)), steel, parent=plate)
        sc.rotation_euler = (-math.pi / 2, 0, 0)
    # The conduit, down through a locknut in the middle of the plate.
    wx, wy = PLATE_CENTRE
    add_object("ElectricalWhipLocknut", cylinder_mesh("ElectricalWhipLocknut", WHIP_R + 0.009, 0.004, 6, z0=PLATE_T), collection,
            Vector((wx, wy, 0)), steel, parent=plate)
    add_object("ElectricalWhipConnector", tube_mesh("ElectricalWhipConnector", [(wx, wy, PLATE_T), (wx, wy, 0.03)], WHIP_R + 0.005, 8),
            collection, Vector((0, 0, 0)), steel, parent=plate)
    add_object("ElectricalWhip", tube_mesh("ElectricalWhip", [(wx, wy, 0.025), (wx, wy, CEILING - top - lift)], WHIP_R),
            collection, Vector((0, 0, 0)), conduit, parent=plate)
    # The pocket's dark inside, and the knockout in its floor with a white bushing.
    add_object("PocketInside", pocket_liner_mesh("PocketInside", tank_r, floor), collection, at(0, 0, 0), liner, parent=plate)
    kx, ky = KNOCKOUT_AT
    add_object("PocketKnockout", cylinder_mesh("PocketKnockout", 0.012, 0.0008, 12, z0=floor + 0.0004), collection,
            at(kx, ky, 0), dark, parent=plate)
    add_object("PocketKnockoutBushing", tube_mesh("PocketKnockoutBushing", [(kx, ky, floor), (kx, ky, floor + 0.005)], 0.0145, 14),
            collection, at(0, 0, 0), paint, parent=plate)
    add_object("PocketKnockoutHole", cylinder_mesh("PocketKnockoutHole", 0.0115, 0.0002, 14, z0=floor + 0.0052), collection,
            at(kx, ky, 0), dark, parent=plate)
    # Black: the supply's black from under the plate and the heater's black
    # lead, in a nut standing up at the back left.
    bz = floor + 0.014
    bx, by = -0.022, -0.2
    add_object("WireNut_Line1", wire_nut_mesh("WireNut_Line1"), collection, at(bx, by, bz), yellow, parent=plate)
    add_object("SupplyWire_Line1", tube_mesh("SupplyWire_Line1",
            [(-0.03, -POCKET_BACK + 0.01, -0.006), (-0.03, -POCKET_BACK - 0.006, -0.01), (bx - 0.004, by + 0.004, bz - 0.004), (bx, by, bz + 0.003)],
            0.0019, 6), collection, at(0, 0, 0), black, parent=plate)
    add_object("HeaterLead_Line1", tube_mesh("HeaterLead_Line1",
            [(kx - 0.004, ky, floor + 0.004), (kx - 0.008, ky + 0.006, floor + 0.012), (bx + 0.004, by - 0.006, bz - 0.004), (bx, by, bz + 0.003)],
            0.0019, 6), collection, at(0, 0, 0), black, parent=plate)
    # Red: the heater's red lead up out of the knockout, and the supply's red,
    # in a nut lying over to the right.
    rx, ry, rz = 0.026, -0.215, floor + 0.009
    nut = add_object("WireNut_Line2", wire_nut_mesh("WireNut_Line2"), collection, at(rx, ry, rz), yellow, parent=plate)
    nut.rotation_euler = (math.radians(-15), math.radians(75), 0)      # tipped over, pointing right and a little up
    add_object("HeaterLead_Line2", tube_mesh("HeaterLead_Line2",
            [(kx + 0.004, ky, floor + 0.004), (kx + 0.007, ky + 0.004, floor + 0.009), (rx - 0.012, ry - 0.002, rz + 0.001), (rx - 0.002, ry, rz)],
            0.0019, 6), collection, at(0, 0, 0), red, parent=plate)
    add_object("SupplyWire_Line2", tube_mesh("SupplyWire_Line2",
            [(0.034, -POCKET_BACK + 0.01, -0.005), (0.034, -POCKET_BACK - 0.004, -0.009), (0.033, -POCKET_BACK - 0.012, rz + 0.012),
             (rx - 0.004, ry + 0.008, rz + 0.005), (rx - 0.002, ry + 0.002, rz + 0.001)],
            0.0019, 6), collection, at(0, 0, 0), red, parent=plate)
    # Ground: a green screw on a tab at the back of the pocket, just under the
    # plate's edge, the bare copper looping up to it from the knockout.
    gx, gy, gz = 0.004, -POCKET_BACK - 0.007, -0.009
    add_object("GroundTab", box_mesh("GroundTab", (0.016, 0.014, 0.002), (gx, gy + 0.001, gz - 0.001)), collection,
            at(0, 0, 0), paint, parent=plate)
    add_object("GroundScrew", cylinder_mesh("GroundScrew", 0.0052, 0.003, 10, z0=gz), collection,
            at(gx, gy, 0), green, parent=plate)
    add_object("GroundScrew_Slot", box_mesh("GroundScrew_Slot", (0.007, 0.0012, 0.0006), (gx, gy, gz + 0.003)), collection,
            at(0, 0, 0), dark, parent=plate)
    add_object("GroundWire", tube_mesh("GroundWire",
            [(kx, ky + 0.006, floor + 0.004), (kx - 0.002, ky + 0.014, floor + 0.022), (gx + 0.012, gy - 0.016, gz + 0.004),
             (gx + 0.006, gy - 0.004, gz + 0.004), (gx + 0.003, gy, gz + 0.0035)], 0.0015, 6),
            collection, at(0, 0, 0), bare, parent=plate)
    # The cover: a rounded hood, its tongue tucked under the plate's front
    # edge, screwed into the side of the tank below the pocket at the right.
    cover = add_object("JunctionBoxCover", wrap_cover_mesh("JunctionBoxCover", tank_r, 0.0), collection,
            at(0, 0, 0), paint, parent=plate)
    side = tank_r + 0.003
    sx, sz = 0.032, floor - 0.004
    add_object("JunctionBoxCover_Screw", screw_mesh("JunctionBoxCover_Screw"), collection,
            Vector((sx, -math.sqrt(side * side - sx * sx), sz)), steel, parent=cover)
    bpy.data.objects["JunctionBoxCover_Screw"].rotation_euler = (0, 0, math.atan2(sx, side))
    words = text_mesh("JunctionBoxCover_WarningLabel", "WARNING", 0.013)
    for v in words.vertices:                            # bent round the cover, printed just proud of it
        r = side + 0.0003 - v.co.y
        v.co = Vector((v.co.x, -math.sqrt(r * r - v.co.x * v.co.x), v.co.z - 0.02))
    label = add_object("JunctionBoxCover_WarningLabel", words, collection, Vector((0, 0, 0)), ink, parent=cover)
    for o in [plate] + list(plate.children_recursive):
        if o != label and not o.name.startswith("PocketInside"):
            smooth(o, 40)
    return plate


# --- Behind the covers: thermostats and elements -------------------------------------------
# Each cover hides a pocket let into the foam: a thermostat clamped to the tank
# above, the element's screw-in head below, wired together. The upper
# thermostat carries the high-limit (ECO) with its red reset button, and the
# supply from the junction box lands on its top two screws. Names are what the
# game looks for (WaterHeaterView), so keep them.
POCKET_W = 0.12
POCKET_H = 0.13
POCKET_IN = 0.035       # how deep the pocket goes in from the tank's front
ELEMENT_DZ = -0.035     # the element head, below the pocket's middle
ELEMENT_HEX_R = 0.024   # across the corners of its hex
WIRE_R = 0.0022


def cut_box(tank, name, size, centre):
    """A box cut out of the tank's mesh with a boolean (in the new file only)."""
    cutter = bpy.data.objects.new(name, box_mesh(name, size, centre))
    tank.users_collection[0].objects.link(cutter)
    mod = tank.modifiers.new(name, "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = tank
    bpy.ops.object.modifier_move_to_index(modifier=name, index=0)
    bpy.ops.object.modifier_apply(modifier=name)
    bpy.data.objects.remove(cutter)


def hex_mesh(name, r, depth):
    """A hex prism, axis along -Y, its back at y = 0."""
    bm = bmesh.new()
    back = [bm.verts.new((math.cos(math.pi / 3 * i) * r, 0.0, math.sin(math.pi / 3 * i) * r)) for i in range(6)]
    front = [bm.verts.new((v.co.x, -depth, v.co.z)) for v in back]
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new([back[i], back[j], front[j], front[i]])
    bm.faces.new(back)
    bm.faces.new(list(reversed(front)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def build_compartment(tank, collection, axis, tank_r, which, z, steel):
    """One cover's pocket and what's in it. `which` is "Upper" or "Lower"."""
    bakelite = material("ThermostatBakelite", (0.13, 0.12, 0.12), 0.6)
    reset_red = material("ResetRed", (0.75, 0.05, 0.04), 0.45)
    black = material("WireBlack", (0.02, 0.02, 0.022), 0.5)
    red = material("WireRed", (0.5, 0.03, 0.02), 0.5)
    y0 = axis.y - tank_r                       # the tank's front surface
    floor_y = y0 + POCKET_IN
    cut_box(tank, which + "PocketCutter", (POCKET_W, POCKET_IN + 0.05, POCKET_H),
            (axis.x, (y0 - 0.05 + floor_y) / 2, z))
    # The pocket's back: the tank's steel skin, everything's mounted on it.
    back = add_object(which + "Compartment", box_mesh(which + "Compartment", (POCKET_W - 0.002, 0.002, POCKET_H - 0.002), (0, 0.001, 0)),
            collection, Vector((axis.x, floor_y - 0.0005, z)), steel)

    def screw(name, x, dz, front_y, parent):
        o = add_object(name, screw_mesh(name), collection, Vector((x, front_y, dz)), steel, parent=parent)
        smooth(o, 50)
        return o

    upper = which == "Upper"
    # The thermostat: the upper one is tall, with the ECO on top of it.
    t_w, t_h, t_d = (0.07, 0.055, 0.014) if upper else (0.05, 0.04, 0.012)
    t_dz = 0.03 if upper else 0.025
    stat = add_object(which + "Thermostat", box_mesh(which + "Thermostat", (t_w, t_d, t_h), (0, -t_d / 2, 0)),
            collection, Vector((0, -0.001, t_dz)), bakelite, parent=back)
    face = -t_d
    terms = {}
    if upper:
        terms["L1"] = screw("UpperThermostat_ScrewL1", 0.024, 0.018, face, stat)
        terms["L2"] = screw("UpperThermostat_ScrewL2", -0.024, 0.018, face, stat)
        terms["Out"] = screw("UpperThermostat_ScrewOut", 0.024, -0.017, face, stat)
        terms["Lower"] = screw("UpperThermostat_ScrewLower", -0.024, -0.017, face, stat)
        button = add_object("UpperThermostat_Reset", cylinder_mesh("UpperThermostat_Reset", 0.0055, 0.006), collection,
                Vector((0, face, 0.016)), reset_red, parent=stat)
        button.rotation_euler = (math.pi / 2, 0, 0)  # its axis out of the face
        smooth(button, 40)
    else:
        terms["In"] = screw("LowerThermostat_ScrewIn", 0.015, 0.012, face, stat)
        terms["Out"] = screw("LowerThermostat_ScrewOut", 0.015, -0.012, face, stat)

    # The element's head, screwed into the tank, with its two terminal screws.
    head = add_object(which + "Element", hex_mesh(which + "Element", ELEMENT_HEX_R, 0.008), collection,
            Vector((0, -0.001, ELEMENT_DZ)), steel, parent=back)
    block = add_object(which + "Element_Block", box_mesh(which + "Element_Block", (0.036, 0.006, 0.016), (0, -0.011, 0)),
            collection, Vector((0, 0, 0)), bakelite, parent=head)
    for tag, x in (("A", 0.011), ("B", -0.011)):
        screw(which + "Element_Screw" + tag, x, 0.0, -0.014, head)

    # Wires, relative to the compartment (they stay put when the element comes out).
    def wire(name, pts, mat):
        add_object(name, tube_mesh(name, pts, WIRE_R, seg=6), collection, Vector((0, 0, 0)), mat, parent=back)

    stat_face = -0.001 + face - 0.003
    elem_face = -0.001 - 0.017
    def on_stat(x, dz):
        return (x, stat_face, t_dz + dz)
    def on_elem(x):
        return (x, elem_face, ELEMENT_DZ)
    top = POCKET_H / 2
    if upper:
        # The supply from the junction box, down inside the foam to the top screws.
        wire("UpperSupply_WireL1", [(0.03, -0.004, top + 0.02), (0.03, -0.004, top - 0.01), on_stat(0.024, 0.018)], black)
        wire("UpperSupply_WireL2", [(-0.03, -0.004, top + 0.02), (-0.03, -0.004, top - 0.01), on_stat(-0.024, 0.018)], red)
        # Off to the lower thermostat, down through the foam.
        wire("UpperThermostat_WireLower", [on_stat(-0.024, -0.017), (-0.05, -0.006, t_dz - 0.03), (-0.05, -0.004, -top - 0.02)], black)
        wire("UpperElement_WireA", [on_stat(0.024, -0.017), (0.03, stat_face, -0.005), on_elem(0.011)], black)
        wire("UpperElement_WireB", [on_stat(-0.024, 0.018), (-0.04, stat_face - 0.002, 0.0), (-0.028, elem_face, -0.02), on_elem(-0.011)], red)
    else:
        wire("LowerThermostat_WireIn", [(0.04, -0.004, top + 0.02), (0.04, -0.004, top - 0.008), on_stat(0.015, 0.012)], black)
        wire("LowerElement_WireA", [on_stat(0.015, -0.012), (0.02, stat_face, -0.008), on_elem(0.011)], black)
        wire("LowerElement_WireB", [(-0.045, -0.004, top + 0.02), (-0.045, -0.004, 0.0), (-0.025, elem_face, -0.02), on_elem(-0.011)], red)
    return back


def build_drain(collection, axis, tank_r, brass):
    """The drain valve near the floor, for a garden hose."""
    plastic = material("DrainKnob", (0.85, 0.83, 0.78), 0.5)
    y0 = axis.y - tank_r
    body = add_object("DrainValve", tube_mesh("DrainValve", [(0, 0.01, 0), (0, -0.05, 0)], 0.011, seg=10), collection,
            Vector((axis.x + 0.09, y0 + 0.012, 0.16)), brass)
    add_object("DrainValve_Thread", tube_mesh("DrainValve_Thread", [(0, -0.03, 0), (0, -0.03, -0.035)], 0.0095, seg=10),
            collection, Vector((0, 0, 0)), brass, parent=body)
    add_object("DrainValve_Handle", tube_mesh("DrainValve_Handle", [(0, -0.05, 0), (0, -0.062, 0)], 0.014, seg=10),
            collection, Vector((0, 0, 0)), plastic, parent=body)
    for o in (body, *body.children):
        smooth(o, 40)
    return body


# --- The connections on top ----------------------------------------------------------------

def build_top(collection, axis, top):
    """Everything on top of the tank, each part its own named object. Parts
    hang off their main object, so Godot gets them grouped."""
    steel = material("GalvanizedSteel", (0.55, 0.56, 0.57), 0.45, 1.0)
    copper = material("Copper", (0.72, 0.42, 0.26), 0.35, 1.0)
    brass = material("Brass", (0.72, 0.58, 0.3), 0.35, 1.0)
    blue = material("ColdBlue", (0.08, 0.25, 0.65), 0.5)
    red = material("HotRed", (0.7, 0.08, 0.06), 0.5)
    box_paint = material("WaterHeaterShell", SHELL_COLOUR, SHELL_ROUGH, SHELL_METAL)   # same enamel as the tank
    conduit = material("FlexConduit", (0.5, 0.51, 0.52), 0.4, 1.0)
    made = []

    def at(xy, z=top):
        return Vector((axis.x + xy[0], axis.y + xy[1], z))

    # Cold in on the right, with a quarter-turn shut-off; hot out on the left.
    for name, xy, band, valve in (("ColdWaterInlet", COLD_AT, blue, True), ("HotWaterOutlet", HOT_AT, red, False)):
        nipple = add_object(name, cylinder_mesh(name, NIPPLE_R, 0.08), collection, at(xy), steel)
        add_object(name + "_Union", cylinder_mesh(name + "_Union", NIPPLE_R + 0.007, 0.03, z0=0.08), collection,
                Vector((0, 0, 0)), brass, parent=nipple)
        add_object(name + "_Pipe", cylinder_mesh(name + "_Pipe", COPPER_R, CEILING - top - 0.11, z0=0.11), collection,
                Vector((0, 0, 0)), copper, parent=nipple)
        add_object(name + "_Band", cylinder_mesh(name + "_Band", COPPER_R + 0.0015, 0.03, z0=0.2), collection,
                Vector((0, 0, 0)), band, parent=nipple)
        if valve:
            body = add_object(name + "_ShutoffValve", cylinder_mesh(name + "_ShutoffValve", COPPER_R + 0.009, 0.07, z0=0.34),
                    collection, Vector((0, 0, 0)), brass, parent=nipple)
            add_object(name + "_ShutoffHandle", box_mesh(name + "_ShutoffHandle", (0.014, 0.085, 0.008), (0, -0.05, 0.375)),
                    collection, Vector((0, 0, 0)), blue, parent=body)
        made.append(nipple)

    # T&P relief valve at the back, its discharge pipe down the back of the tank
    # to 150 mm off the floor.
    tp = add_object("TPReliefValve", cylinder_mesh("TPReliefValve", 0.012, 0.04), collection, at(TP_AT), brass)
    add_object("TPReliefValve_Body", cylinder_mesh("TPReliefValve_Body", 0.022, 0.07, z0=0.04), collection,
            Vector((0, 0, 0)), brass, parent=tp)
    add_object("TPReliefValve_Lever", box_mesh("TPReliefValve_Lever", (0.012, 0.06, 0.006), (0, -0.02, 0.115)),
            collection, Vector((0, 0, 0)), brass, parent=tp)
    tank_r = TANK_DIAMETER / 2
    out_y = tank_r + 0.03 - TP_AT[1]                    # just clear of the tank's back
    add_object("TPDischargePipe", tube_mesh("TPDischargePipe",
            [(0, 0.02, 0.075), (0, out_y, 0.075), (0, out_y, 0.15 - top)], COPPER_R), collection,
            Vector((0, 0, 0)), copper, parent=tp)
    made.append(tp)

    # The electrical connection: the plate with the conduit, the splices down
    # in the pocket, and the cover over the edge.
    made.append(build_electrical(collection, axis, top, steel, box_paint, conduit))
    for o in collection.objects:
        if o.name.startswith(("ColdWater", "HotWater", "TPRelief", "TPDischarge")):
            smooth(o, 40)
    return made


def smooth(obj, angle_deg):
    """Smooth shading, with edges sharper than the angle kept sharp (baked, no modifier)."""
    for p in obj.data.polygons:
        p.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))


# --- Run -----------------------------------------------------------------------------------

def main():
    tank = find_tank()
    collection = tank.users_collection[0]
    tank.name = "WaterHeaterTank"
    tank.data.name = "WaterHeaterTank"
    axis, tank_r = fit_tank(tank)
    shell = material("WaterHeaterShell", SHELL_COLOUR, SHELL_ROUGH, SHELL_METAL)
    paint = material("ThermostatCoverPaint", (0.06, 0.22, 0.55), 0.45)   # water-heater blue
    steel = material("ScrewSteel", (0.62, 0.63, 0.65), 0.35, 1.0)
    tank.data.materials.clear()
    tank.data.materials.append(shell)

    made = []
    for name, height in COVERS.items():
        # The front of the tank, straight out from its axis along -Y.
        surface = Vector((axis.x, axis.y - tank_r, height))
        cover = add_object(name, cover_mesh(name, tank_r), collection, surface, paint)
        smooth(cover, 40)
        for tag, dz in (("ScrewTop", COVER_H / 2 - SCREW_FROM_EDGE), ("ScrewBottom", -(COVER_H / 2 - SCREW_FROM_EDGE))):
            screw = add_object("%s_%s" % (name, tag), screw_mesh("%s_%s" % (name, tag)), collection,
                    Vector((0.0, -COVER_D, dz)), steel, parent=cover)
            smooth(screw, 50)
        made.append(cover)
    for which, name in (("Upper", "UpperThermostatCover"), ("Lower", "LowerThermostatCover")):
        made.append(build_compartment(tank, collection, axis, tank_r, which, COVERS[name], steel))
    made.append(build_drain(collection, axis, tank_r, material("Brass", (0.72, 0.58, 0.3), 0.35, 1.0)))
    cut_pocket(tank, axis, TANK_HEIGHT, tank_r)
    made.extend(build_top(collection, axis, TANK_HEIGHT))

    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, copy=True)
    bpy.ops.object.select_all(action="DESELECT")
    keep = {tank}
    for o in made:
        keep.add(o)
        keep.update(o.children_recursive)
    for o in keep:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("saved", OUT_BLEND)
    print("exported", OUT_GLB)


main()
