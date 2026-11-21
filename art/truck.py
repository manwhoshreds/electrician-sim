"""Builds the rusty old pickup you start the game with, and exports it.

Run from the project root (takes a few minutes, the rust is baked on the CPU):
    blender --background --python art/truck.py

Writes art/truck.blend, the baked textures in art/truck_*.png, and
assets/truck/truck.glb and assets/truck/truck_wheel.glb.

Units are metres, the origin is on the ground under the middle of the truck,
and the nose points along +Y, which becomes -Z in Godot. Keep the wheel and
lamp positions in step with scripts/van.gd.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
OUT = os.path.join(ROOT, "assets", "truck")

FRONT_AXLE = 1.75
REAR_AXLE = -1.45
TRACK = 0.8             # wheel centre, off the middle of the truck
AXLE_Z = 0.38
ARCH = 0.5              # wheel arch radius
HALF_W = 0.95
ROCKER = 0.46           # bottom edge of the cab and front fenders
BED_BOTTOM = 0.5
BED_TOP = 1.24
BED_FRONT = -0.82
BED_REAR = -2.42
BED_FLOOR = 0.76
FLOOR = 0.62            # the cab floor
SEAT = 0.98             # top of the seat cushion
WHEEL_HUB = (-0.42, 0.12, 1.22)
WHEEL_TILT = math.radians(-25)

AXES = {
    "UP": Matrix.Identity(3),
    "FWD": Matrix.Rotation(-math.pi / 2, 3, "X"),
    "BACK": Matrix.Rotation(math.pi / 2, 3, "X"),
    "RIGHT": Matrix.Rotation(math.pi / 2, 3, "Y"),
}


# --- Geometry ---------------------------------------------------------------

def finish(name, bm, mat, smooth_below=None):
    """Turns a bmesh into a scene object, smooth except for its hard creases."""
    if "UVMap" not in bm.loops.layers.uv:
        bm.loops.layers.uv.new("UVMap")
    if smooth_below is not None:
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            angle = e.calc_face_angle(None)
            e.smooth = angle is not None and angle < math.radians(smooth_below)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def soften(bm, bevel):
    """Rounds the real corners and leaves curves that are already curved alone."""
    if bevel <= 0.0:
        return
    edges = [e for e in bm.edges if e.calc_face_angle(0.0) > math.radians(25)]
    verts = list({v for e in edges for v in e.verts})
    bmesh.ops.bevel(bm, geom=verts + edges, offset=bevel, segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)


def solid(name, bm, mat, bevel):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    soften(bm, bevel)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(name, bm, mat, 35)


def box(name, size, center, mat, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0)))
    return solid(name, bm, mat, bevel)


def span(name, x, y, z, mat, bevel=0.0):
    """A box given as (low, high) ranges on each axis, handy for body panels."""
    size = (x[1] - x[0], y[1] - y[0], z[1] - z[0])
    center = ((x[0] + x[1]) / 2, (y[0] + y[1]) / 2, (z[0] + z[1]) / 2)
    return box(name, size, center, mat, bevel)


def side_panel(name, outline, x0, x1, mat, bevel=0.0):
    """A shape drawn from the side as (y, z) points, given thickness along X."""
    bm = bmesh.new()
    near = [bm.verts.new((x0, y, z)) for y, z in outline]
    far = [bm.verts.new((x1, y, z)) for y, z in outline]
    bm.faces.new(near)
    bm.faces.new(list(reversed(far)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((near[i], far[i], far[j], near[j]))
    return solid(name, bm, mat, bevel)


def plan_panel(name, outline, z0, z1, mat, bevel=0.0):
    """A shape drawn from above as (x, y) points, given height along Z."""
    bm = bmesh.new()
    low = [bm.verts.new((x, y, z0)) for x, y in outline]
    high = [bm.verts.new((x, y, z1)) for x, y in outline]
    bm.faces.new(low)
    bm.faces.new(list(reversed(high)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((low[i], high[i], high[j], low[j]))
    return solid(name, bm, mat, bevel)


def hexa(name, low, high, mat, bevel=0.0):
    """A six-sided block from a bottom and a top ring of four corners."""
    bm = bmesh.new()
    a = [bm.verts.new(p) for p in low]
    b = [bm.verts.new(p) for p in high]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a[i], a[j], b[j], b[i]))
    return solid(name, bm, mat, bevel)


def post(name, foot, head, half_x, half_y, mat, bevel=0.012):
    """A window pillar running from foot to head."""
    ring = lambda p: [(p[0] - half_x, p[1] - half_y, p[2]), (p[0] + half_x, p[1] - half_y, p[2]),
            (p[0] + half_x, p[1] + half_y, p[2]), (p[0] - half_x, p[1] + half_y, p[2])]
    return hexa(name, ring(foot), ring(head), mat, bevel)


def pane(name, corners, outward, mat):
    """A flat sheet of glass, facing outward."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new(p) for p in corners])
    bmesh.ops.recalc_face_normals(bm, faces=[face])
    face.normal_update()
    if face.normal.dot(Vector(outward)) < 0.0:
        face.normal_flip()
    return finish(name, bm, mat)


def picture(name, width, height, center, mat):
    """A flat picture facing the back of the truck, like a gauge facing the driver."""
    w, h = width / 2, height / 2
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x + center[0], center[1], z + center[2])) for x, z in ((-w, -h), (w, -h), (w, h), (-w, h))])
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = co
    return finish(name, bm, mat)


def lathe(name, profile, center, axis, mat, segments=32):
    """Spins (radius, distance along axis) points round an axis.

    Walk the profile with the outside of the shape on your right as you
    head along the axis, or the surface comes out inside-out.
    """
    bm = bmesh.new()
    turn = AXES[axis]
    rings = []
    for r, along in profile:
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            ring.append(bm.verts.new(turn @ Vector((math.cos(a) * r, math.sin(a) * r, along)) + Vector(center)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return finish(name, bm, mat, 40)


def arch(axle_y, bottom, front_first):
    """The wheel arch as (y, z) points, cut off at the panel's bottom edge."""
    trim = math.asin((bottom - AXLE_Z) / ARCH)
    steps = 18
    points = []
    for i in range(steps + 1):
        t = trim + (math.pi - 2.0 * trim) * i / steps
        t = t if front_first else math.pi - t
        points.append((axle_y + math.cos(t) * ARCH, AXLE_Z + math.sin(t) * ARCH))
    return points


# --- Materials --------------------------------------------------------------

def plain(name, color, metal=0.0, rough=0.6, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    return m


def textured(name, filename, rough=0.5):
    m = plain(name, (1, 1, 1), 0.0, rough)
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(ART, filename))
    m.node_tree.links.new(tex.outputs["Color"], m.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return m


def rusty(name, paint, rust_bias, wheel_arches=True):
    """Faded paint eaten by rust: worst low down and round the wheel arches.

    The rust is worked out from position on the truck, so it runs straight
    across panel seams and UV islands. It only exists until the bake.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    tree = m.node_tree
    n, link = tree.nodes, tree.links.new
    bsdf = n["Principled BSDF"]
    where = n.new("ShaderNodeTexCoord").outputs["Object"]
    axes = n.new("ShaderNodeSeparateXYZ")
    link(where, axes.inputs[0])

    def noise(scale, detail=8.0, rough=0.6):
        node = n.new("ShaderNodeTexNoise")
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        link(where, node.inputs["Vector"])
        return node.outputs["Fac"]

    def math_node(op, a, b):
        node = n.new("ShaderNodeMath")
        node.operation = op
        for socket, value in zip(node.inputs, (a, b)):
            if isinstance(value, float):
                socket.default_value = value
            else:
                link(value, socket)
        return node.outputs[0]

    def remap(value, in_low, in_high, out_low, out_high):
        node = n.new("ShaderNodeMapRange")
        link(value, node.inputs["Value"])
        for key, v in (("From Min", in_low), ("From Max", in_high), ("To Min", out_low), ("To Max", out_high)):
            node.inputs[key].default_value = v
        return node.outputs[0]

    def ramp(value, stops):
        node = n.new("ShaderNodeValToRGB")
        cr = node.color_ramp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            el.color = (*col, 1.0)
        link(value, node.inputs["Fac"])
        return node.outputs["Color"]

    def mix(fac, a, b):
        node = n.new("ShaderNodeMix")
        node.data_type = "RGBA"
        link(fac, node.inputs["Factor"])
        for slot, v in (("A", a), ("B", b)):
            socket = next(s for s in node.inputs if s.name == slot and s.type == "RGBA")
            if isinstance(v, tuple):
                socket.default_value = (*v, 1.0)
            else:
                link(v, socket)
        return next(s for s in node.outputs if s.type == "RGBA")

    # How likely rust is here.
    amount = math_node("ADD", noise(7.0, 10.0, 0.66), remap(axes.outputs["Z"], 0.45, 1.35, 0.17, -0.12))
    amount = math_node("ADD", amount, rust_bias)
    if wheel_arches:
        def from_wheel(y):
            a = n.new("ShaderNodeVectorMath")
            a.operation = "DISTANCE"
            combine = n.new("ShaderNodeCombineXYZ")
            link(axes.outputs["Y"], combine.inputs["Y"])
            link(axes.outputs["Z"], combine.inputs["Z"])
            link(combine.outputs[0], a.inputs[0])
            a.inputs[1].default_value = (0.0, y, AXLE_Z)
            return a.outputs["Value"]
        near = math_node("MINIMUM", from_wheel(FRONT_AXLE), from_wheel(REAR_AXLE))
        amount = math_node("ADD", amount, remap(near, 0.5, 0.95, 0.22, 0.0))
    # Fine speckle out ahead of the big patches.
    speckle = remap(noise(130.0, 3.0, 0.5), 0.6, 0.72, 0.0, 0.12)
    amount = math_node("ADD", amount, speckle)
    mask = remap(amount, 0.56, 0.63, 0.0, 1.0)

    # What the rust and the old paint look like.
    grain = noise(46.0, 10.0, 0.7)
    rust_color = ramp(grain, [(0.3, (0.05, 0.022, 0.012)), (0.5, (0.27, 0.095, 0.03)), (0.68, (0.44, 0.18, 0.05))])
    chalk = remap(noise(3.0, 6.0, 0.55), 0.35, 0.68, 0.0, 0.6)
    sun = remap(axes.outputs["Z"], 0.9, 1.5, 0.0, 0.2)
    faded = tuple(c * 0.75 + 0.07 for c in paint)
    paint_color = mix(math_node("ADD", chalk, sun), paint, faded)

    link(mix(mask, paint_color, rust_color), bsdf.inputs["Base Color"])
    rough = n.new("ShaderNodeMapRange")
    link(mask, rough.inputs["Value"])
    rough.inputs["To Min"].default_value = 0.56
    rough.inputs["To Max"].default_value = 0.96
    link(rough.outputs[0], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0   # the bake can't see colour through metal

    # Rust stands proud of the paint and is rough to the touch.
    bump = n.new("ShaderNodeBump")
    height = math_node("ADD", math_node("MULTIPLY", mask, 0.6), math_node("MULTIPLY", grain, mask))
    link(height, bump.inputs["Height"])
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.01
    link(bump.outputs[0], bsdf.inputs["Normal"])
    return m


# --- The truck --------------------------------------------------------------

def build_truck():
    paint = rusty("Paint", (0.02, 0.1, 0.11), 0.0)
    primer = rusty("Primer", (0.085, 0.085, 0.08), -0.06)
    chrome = rusty("OldChrome", (0.5, 0.5, 0.48), 0.09, wheel_arches=False)
    dark = plain("Underneath", (0.02, 0.02, 0.022), 0.0, 0.8)
    vinyl = plain("Vinyl", (0.1, 0.075, 0.05), 0.0, 0.55)
    glass = plain("Glass", (0.3, 0.36, 0.34), 0.0, 0.08, alpha=0.2)
    headliner = plain("Headliner", (0.3, 0.27, 0.2), 0.0, 0.92)
    mirror = plain("MirrorGlass", (0.75, 0.77, 0.78), 1.0, 0.06)
    gauges = textured("Gauges", "truck_gauges.png")

    # Frame and everything you'd otherwise see straight through the wheel wells.
    span("FrameFront", (-0.62, 0.62), (0.7, 2.36), (0.36, 1.12), dark)
    span("FrameMiddle", (-0.62, 0.62), (-0.82, 0.7), (0.36, 0.56), dark)
    span("FrameRear", (-0.62, 0.62), (BED_REAR, BED_FRONT), (0.36, 0.7), dark)
    for y in (FRONT_AXLE, REAR_AXLE):
        span("Axle", (-0.72, 0.72), (y - 0.05, y + 0.05), (AXLE_Z - 0.05, AXLE_Z + 0.05), dark)

    # Front end: separate fenders either side of the hood, so the seams show.
    fender = [(0.72, ROCKER), (0.72, 1.17), (2.34, 1.17), (2.46, 1.11), (2.46, 0.54), (2.38, ROCKER)] + arch(FRONT_AXLE, ROCKER, True)
    side_panel("FenderR", fender, 0.655, HALF_W, paint, 0.022)
    side_panel("FenderL", fender, -HALF_W, -0.655, paint, 0.022)
    side_panel("Hood", [(0.93, 1.1), (0.93, 1.3), (2.28, 1.225), (2.43, 1.17), (2.43, 1.1)], -0.645, 0.645, primer, 0.03)
    span("Cowl", (-HALF_W, HALF_W), (0.68, 0.93), (1.1, 1.32), paint, 0.02)
    span("GrilleBack", (-0.645, 0.645), (2.4, 2.46), (0.66, 1.1), dark)

    # Grille: a frame, horizontal bars and a centre post.
    for name, x, y, z in (("GrilleTop", (-0.64, 0.64), (2.44, 2.5), (1.06, 1.11)), ("GrilleBottom", (-0.64, 0.64), (2.44, 2.5), (0.65, 0.7)),
            ("GrilleL", (-0.64, -0.59), (2.44, 2.5), (0.65, 1.11)), ("GrilleR", (0.59, 0.64), (2.44, 2.5), (0.65, 1.11)),
            ("GrilleMid", (-0.022, 0.022), (2.46, 2.51), (0.65, 1.11))):
        span(name, x, y, z, chrome, 0.008)
    for i in range(5):
        z = 0.74 + i * 0.07
        span("GrilleBar", (-0.59, 0.59), (2.46, 2.49), (z - 0.012, z + 0.012), chrome, 0.004)
    # Headlight surrounds. The lenses are added by the game so they can light up.
    for s in (-1, 1):
        lathe("HeadlightRing", [(0.13, 0.0), (0.13, 0.03), (0.115, 0.05), (0.095, 0.042), (0.095, 0.0)], (s * 0.8, 2.46, 0.9), "FWD", chrome)
        span("ParkingLamp", (s * 0.8 - 0.07, s * 0.8 + 0.07), (2.45, 2.475), (0.63, 0.69), chrome, 0.006)
    # Bumpers, a little out of true because something got backed into.
    bumper = box("BumperFront", (2.08, 0.16, 0.2), (0.0, 2.58, 0.62), chrome, 0.04)
    bumper.rotation_euler = (0.0, math.radians(0.9), 0.0)
    for s in (-1, 1):
        span("BumperBracket", (s * 0.55 - 0.05, s * 0.55 + 0.05), (2.36, 2.52), (0.56, 0.66), dark)
        span("RearBracket", (s * 0.55 - 0.05, s * 0.55 + 0.05), (-2.5, -2.3), (0.52, 0.62), dark)
    box("BumperRear", (2.0, 0.13, 0.16), (0.0, -2.54, 0.6), chrome, 0.03)

    # Cab, from the waist down. The right door has been replaced, in primer.
    # It's a hollow tub, open at the top, so there's room to sit inside.
    wall = HALF_W - 0.05
    plan_panel("CabTub", [(-HALF_W, 0.72), (-HALF_W, -0.78), (HALF_W, -0.78), (HALF_W, 0.72),
            (wall, 0.72), (wall, -0.72), (-wall, -0.72), (-wall, 0.72)], ROCKER, 1.3, paint, 0.02)
    span("CabFloor", (-wall, wall), (-0.74, 0.72), (ROCKER, FLOOR), paint)
    span("Firewall", (-wall, wall), (0.66, 0.72), (FLOOR, 1.3), paint)
    for s, mat in ((1, primer), (-1, paint)):
        x = (0.95, 0.972) if s > 0 else (-0.972, -0.95)
        span("Door", x, (-0.55, 0.66), (0.54, 1.27), mat, 0.008)
        handle = s * 0.982
        span("DoorHandle", (handle - 0.012, handle + 0.012), (-0.47, -0.33), (1.16, 1.19), chrome, 0.005)
        span("Lock", (handle - 0.008, handle + 0.008), (-0.3, -0.27), (1.16, 1.19), chrome, 0.003)
        # Mirror on a bent arm.
        span("MirrorArm", sorted((s * 0.93, s * 1.1)), (0.63, 0.65), (1.36, 1.38), chrome)
        span("Mirror", sorted((s * 1.04, s * 1.16)), (0.6, 0.65), (1.28, 1.48), chrome, 0.012)

    # The greenhouse: real pillars and glass, so you can see into the cab.
    sill, eave = 1.3, 1.78
    for s in (-1, 1):
        post("PillarA", (s * 0.915, 0.7, sill), (s * 0.8, 0.22, eave), 0.03, 0.05, paint)
        post("PillarB", (s * 0.915, -0.55, sill), (s * 0.8, -0.52, eave), 0.028, 0.045, paint)
        post("PillarC", (s * 0.915, -0.75, sill), (s * 0.8, -0.7, eave), 0.03, 0.045, paint)
    hexa("Roof", [(-0.84, -0.73, eave), (0.84, -0.73, eave), (0.84, 0.26, eave), (-0.84, 0.26, eave)],
            [(-0.77, -0.66, 1.87), (0.77, -0.66, 1.87), (0.77, 0.15, 1.87), (-0.77, 0.15, 1.87)], paint, 0.035)
    pane("Windshield", [(-0.885, 0.69, sill), (0.885, 0.69, sill), (0.775, 0.215, eave), (-0.775, 0.215, eave)], (0, 1, 0.6), glass)
    pane("BackGlass", [(-0.885, -0.77, sill), (0.885, -0.77, sill), (0.775, -0.715, eave), (-0.775, -0.715, eave)], (0, -1, 0), glass)
    for s in (-1, 1):
        pane("SideGlass", [(s * 0.915, 0.7, sill), (s * 0.915, -0.75, sill), (s * 0.8, -0.7, eave), (s * 0.8, 0.22, eave)], (s, 0, 0.2), glass)
        wiper_x = s * 0.33
        wiper = span("Wiper", (wiper_x - 0.28, wiper_x + 0.28), (0.71, 0.718), (1.325, 1.335), dark)
        wiper.rotation_euler = (0.0, math.radians(s * 12), 0.0)

    # Inside. The driver sits on the -X side, and the game's inside view looks out from there.
    span("FloorMat", (-wall + 0.01, wall - 0.01), (-0.5, 0.64), (FLOOR, FLOOR + 0.012), dark)
    span("SeatBase", (-0.84, 0.84), (-0.66, -0.12), (FLOOR, SEAT), vinyl, 0.05)
    hexa("SeatBack", [(-0.84, -0.7, SEAT - 0.04), (0.84, -0.7, SEAT - 0.04), (0.84, -0.52, SEAT - 0.04), (-0.84, -0.52, SEAT - 0.04)],
            [(-0.84, -0.74, 1.58), (0.84, -0.74, 1.58), (0.84, -0.62, 1.58), (-0.84, -0.62, 1.58)], vinyl, 0.04)
    hexa("Dash", [(-wall, 0.4, 1.02), (wall, 0.4, 1.02), (wall, 0.68, 1.02), (-wall, 0.68, 1.02)],
            [(-wall, 0.36, 1.4), (wall, 0.36, 1.4), (wall, 0.7, 1.42), (-wall, 0.7, 1.42)], vinyl, 0.025)
    span("GaugeHood", (-0.64, -0.2), (0.3, 0.38), (1.36, 1.42), dark, 0.015)
    picture("GaugeFace", 0.36, 0.18, (-0.42, 0.352, 1.26), gauges)
    span("Radio", (0.02, 0.3), (0.352, 0.37), (1.2, 1.28), dark, 0.004)
    span("GloveBox", (0.42, 0.8), (0.352, 0.37), (1.08, 1.26), vinyl, 0.006)
    for s in (-1, 1):
        x = (wall - 0.015, wall) if s > 0 else (-wall, -wall + 0.015)
        span("DoorCard", x, (-0.55, 0.6), (FLOOR + 0.03, 1.29), vinyl)
        inner = s * (wall - 0.03)
        span("ArmRest", sorted((s * wall, inner)), (-0.2, 0.32), (1.06, 1.1), dark, 0.008)
        span("WindowCrank", sorted((s * wall, s * (wall - 0.06))), (0.14, 0.17), (1.18, 1.21), chrome, 0.004)
        # Mirror glass, on the side you see from the driver's seat.
        span("MirrorFace", sorted((s * 1.05, s * 1.15)), (0.594, 0.6), (1.29, 1.47), mirror)
    span("Headliner", (-0.82, 0.82), (-0.72, 0.25), (1.772, 1.78), headliner)
    span("VisorL", (-0.74, -0.16), (0.1, 0.24), (1.75, 1.772), headliner, 0.008)
    span("VisorR", (0.16, 0.74), (0.1, 0.24), (1.75, 1.772), headliner, 0.008)
    span("RearviewBack", (-0.12, 0.12), (0.26, 0.285), (1.67, 1.74), dark, 0.008)
    span("RearviewFace", (-0.11, 0.11), (0.254, 0.26), (1.676, 1.734), mirror)
    span("RearviewStalk", (-0.012, 0.012), (0.27, 0.285), (1.74, 1.78), dark)
    column = lathe("SteeringColumn", [(0.035, 0.0), (0.035, 0.32)], (0, 0, 0), "FWD", dark, 12)
    column.location = WHEEL_HUB
    column.rotation_euler = (WHEEL_TILT, 0.0, 0.0)

    # The bed.
    side = [(BED_FRONT, BED_BOTTOM), (BED_FRONT, BED_TOP), (BED_REAR, BED_TOP), (BED_REAR, BED_BOTTOM)] + arch(REAR_AXLE, BED_BOTTOM, False)
    side_panel("BedSideR", side, 0.86, HALF_W, paint, 0.02)
    side_panel("BedSideL", side, -HALF_W, -0.86, paint, 0.02)
    for s in (-1, 1):
        rail = (0.84, 0.97) if s > 0 else (-0.97, -0.84)
        span("BedRail", rail, (BED_REAR, BED_FRONT), (BED_TOP, BED_TOP + 0.03), paint, 0.01)
        house = (0.62, 0.86) if s > 0 else (-0.86, -0.62)
        span("WheelHouse", house, (REAR_AXLE - 0.5, REAR_AXLE + 0.5), (BED_FLOOR, 0.98), paint, 0.05)
        # Tail lamp housings. The red lenses are added by the game.
        span("TailLamp", sorted((s * 0.84, s * 0.97)), (-2.45, BED_REAR), (0.9, 1.14), chrome, 0.006)
    span("BedFloor", (-0.86, 0.86), (-2.38, -0.88), (0.7, BED_FLOOR), paint)
    for i in range(7):
        x = -0.72 + i * 0.24
        span("FloorRib", (x - 0.025, x + 0.025), (-2.36, -0.9), (BED_FLOOR, BED_FLOOR + 0.012), paint)
    span("Headboard", (-0.86, 0.86), (-0.88, BED_FRONT), (BED_FLOOR, BED_TOP), paint, 0.01)
    span("Tailgate", (-0.855, 0.855), (BED_REAR, -2.37), (0.6, BED_TOP), primer, 0.012)
    span("Toolbox", (-0.8, 0.8), (-1.05, -0.9), (BED_FLOOR, 1.14), chrome, 0.02)
    span("ToolboxLid", (-0.81, 0.81), (-1.07, -0.88), (1.14, 1.17), chrome, 0.012)

    # A whip antenna and a tail pipe.
    span("Antenna", (0.888, 0.894), (0.62, 0.626), (1.3, 2.25), chrome)
    lathe("TailPipe", [(0.04, 0.0), (0.04, 0.26), (0.034, 0.26), (0.034, 0.2)], (0.45, -2.3, 0.44), "BACK", dark, 12)


def build_steering_wheel():
    """Its own object, centred on the hub, so the game can turn it."""
    vinyl = bpy.data.materials["Vinyl"]
    dark = bpy.data.materials["Underneath"]
    parts = [lathe("Rim", [(0.17, -0.014), (0.19, 0.0), (0.17, 0.014), (0.155, 0.0), (0.17, -0.014)], (0, 0, 0), "BACK", vinyl, 36),
            lathe("Hub", [(0.05, -0.01), (0.05, 0.02), (0.035, 0.03), (0.0001, 0.03)], (0, 0, 0), "BACK", dark, 16)]
    parts.append(span("SpokeL", (-0.165, -0.04), (-0.008, 0.008), (-0.018, 0.018), dark))
    parts.append(span("SpokeR", (0.04, 0.165), (-0.008, 0.008), (-0.018, 0.018), dark))
    parts.append(span("SpokeDown", (-0.018, 0.018), (-0.008, 0.008), (-0.165, -0.04), dark))
    wheel = join(parts, "SteeringWheel")
    wheel.location = WHEEL_HUB
    wheel.rotation_euler = (WHEEL_TILT, 0.0, 0.0)
    return wheel


def build_wheel():
    rubber = plain("Tyre", (0.018, 0.018, 0.02), 0.0, 0.92)
    steel = rusty("RimSteel", (0.1, 0.1, 0.1), 0.03, wheel_arches=False)
    lathe("Tyre", [(0.22, -0.125), (0.345, -0.125), (0.385, -0.1), (0.39, -0.062), (0.376, -0.056), (0.376, -0.032), (0.39, -0.026), (0.39, 0.026),
            (0.376, 0.032), (0.376, 0.056), (0.39, 0.062), (0.385, 0.1), (0.345, 0.125), (0.235, 0.125)], (0, 0, 0), "RIGHT", rubber, 48)
    lathe("Rim", [(0.245, 0.126), (0.228, 0.13), (0.2, 0.115), (0.17, 0.075), (0.158, 0.065), (0.12, 0.065), (0.1, 0.082), (0.05, 0.088), (0.0001, 0.088)],
            (0, 0, 0), "RIGHT", steel, 40)
    for i in range(5):
        a = math.tau * i / 5
        lathe("LugNut", [(0.016, 0.0), (0.016, 0.014), (0.01, 0.018), (0.0001, 0.018)], (0.076, math.cos(a) * 0.1, math.sin(a) * 0.1), "RIGHT", steel, 6)


# --- Joining, baking, exporting ----------------------------------------------

def apply_transforms():
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    return joined


def bake(obj, name, size, metal):
    """Bakes the rust into colour, roughness and normal maps on its own UVs."""
    print("BAKING", name)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 6
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True

    maps = {}
    for kind, bake_type, colorspace in (("albedo", "DIFFUSE", "sRGB"), ("rough", "ROUGHNESS", "Non-Color"), ("normal", "NORMAL", "Non-Color")):
        img = bpy.data.images.new(f"truck_{name}_{kind}", size, size, alpha=False)
        img.colorspace_settings.name = colorspace
        for mat in obj.data.materials:
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = img
            mat.node_tree.nodes.active = node
        args = {"type": bake_type}
        if bake_type == "DIFFUSE":
            args["pass_filter"] = {"COLOR"}
        bpy.ops.object.bake(**args)
        img.filepath_raw = os.path.join(ART, f"truck_{name}_{kind}.png")
        img.file_format = "PNG"
        img.save()
        maps[kind] = img

    # Swap the rust recipe for the finished pictures.
    final = bpy.data.materials.new(f"Truck{name}")
    final.use_nodes = True
    tree = final.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = metal

    def image_node(img):
        node = tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        return node
    tree.links.new(image_node(maps["albedo"]).outputs["Color"], bsdf.inputs["Base Color"])
    split = tree.nodes.new("ShaderNodeSeparateColor")
    tree.links.new(image_node(maps["rough"]).outputs["Color"], split.inputs[0])
    tree.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    normal = tree.nodes.new("ShaderNodeNormalMap")
    tree.links.new(image_node(maps["normal"]).outputs["Color"], normal.inputs["Color"])
    tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(final)
    for poly in obj.data.polygons:
        poly.material_index = 0


def by_material(names):
    """Every object whose material is one of names."""
    return [o for o in bpy.context.scene.objects if o.data.materials[0].name in names]


def export(objs, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, filename), export_format="GLB", use_selection=True,
            export_yup=True, export_image_format="JPEG", export_jpeg_quality=92)
    tris = 0
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    print("EXPORTED", filename, tris, "tris")


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    build_truck()
    apply_transforms()
    body = join(by_material({"Paint", "Primer"}), "Body")
    trim = join(by_material({"OldChrome"}), "Trim")
    inside = join(by_material({"Underneath", "Vinyl", "Headliner", "MirrorGlass", "Gauges"}), "Inside")
    glass = join(by_material({"Glass"}), "Windows")
    truck = [body, trim, inside, glass, build_steering_wheel()]
    bake(body, "body", 2048, 0.0)
    bake(trim, "trim", 1024, 0.55)
    export(truck, "truck.glb")

    # The wheel is built at the origin and exported from there, then parked
    # on the truck's axles so the .blend looks like a whole truck.
    before = set(bpy.context.scene.objects)
    build_wheel()
    new = [o for o in bpy.context.scene.objects if o not in before]
    tyre = join([o for o in new if o.data.materials[0].name == "Tyre"], "Tyre")
    rim = join([o for o in new if o.data.materials[0].name == "RimSteel"], "Rim")
    bake(rim, "rim", 512, 0.3)
    export([tyre, rim], "truck_wheel.glb")
    for y in (FRONT_AXLE, REAR_AXLE):
        for s in (-1, 1):
            for part in (tyre, rim):
                copy = part.copy()
                bpy.context.collection.objects.link(copy)
                copy.location = (s * TRACK, y, AXLE_Z)
                copy.rotation_euler = (0.0, 0.0, 0.0 if s > 0 else math.pi)
    bpy.data.objects.remove(tyre)
    bpy.data.objects.remove(rim)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "truck.blend"))


main()
