"""Builds the 100 A outdoor load center and the plug-on breakers, and exports them.

Run from the project root:
    blender --background --python art/panel.py

Writes art/panel.blend, art/breakers.blend, and in assets/panel/:
  panel.glb       Enclosure, Interior, Wiring, MainHandle, DeadFront, CoverScrew, Door,
                  and three versions of every hot wire, one shown at a time by the game:
                  Hot<pole>_Landed, Hot<pole>_Freed (pulled off the terminal), Hot<pole>_Burnt
  breaker_1p.glb  Body, Handle    (built for the right-hand column; the game mirrors it)
  breaker_2p.glb  Body, Handle

Everything is laid out in Godot's axes for the panel, so the numbers match
scripts/panel_view.gd: metres, origin on the wall at the middle of the box,
+X right, +Y up, +Z out of the wall. It's turned into Blender's axes at the end.
CIRCUITS must match scripts/electrical_panel.gd.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")
OUT = os.path.join(ROOT, "assets", "panel")

# Kept in step with panel_view.gd.
W = 0.46
H = 0.86
DEPTH = 0.1
ROW = 0.046
TOP_ROW = 0.16
HANDLE_X = 0.055
TERM_X = 0.114
SHEET = 0.0015
WIRE_Z = 0.08            # hots run at this depth, level with the breaker terminals
NEUTRAL_Z = 0.04
GROUND_Z = 0.018
# slot, poles, rating, has a neutral
CIRCUITS = [(1, [1, 3], 40, True), (2, [2, 4], 30, True), (5, [5, 7], 30, False), (6, [6, 8], 30, False),
        (9, [9], 20, True), (10, [10], 20, True), (11, [11], 20, True), (12, [12], 15, True),
        (13, [13], 15, True), (14, [14], 15, True), (15, [15], 15, True), (16, [16], 15, True)]
INSULATED = {15: 0.00145, 20: 0.0018, 30: 0.0022, 40: 0.0028}   # THHN, outside radius
BARE = {15: 0.0008, 20: 0.001, 30: 0.0013, 40: 0.0016}
SHEATH = {15: 0.0049, 20: 0.0054, 30: 0.0061, 40: 0.0074}       # NM cable, across its wide side
COVER_Z = 0.0965         # front face of the dead front
SCREW_AT = (0.0, -0.39)  # the one cover screw
DOOR_HINGE = (-W / 2 - 0.013, 0.11)

AXES = {
    "OUT": Matrix.Identity(3),
    "UP": Matrix.Rotation(-math.pi / 2, 3, "X"),
    "DOWN": Matrix.Rotation(math.pi / 2, 3, "X"),
    "RIGHT": Matrix.Rotation(math.pi / 2, 3, "Y"),
}
TO_BLENDER = Matrix.Rotation(math.pi / 2, 4, "X")


# --- Geometry ---------------------------------------------------------------

def finish(name, bm, mat, smooth_below=None):
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


def span(name, x, y, z, mat, bevel=0.0):
    """A box given as (low, high) on each axis."""
    bm = bmesh.new()
    size = (x[1] - x[0], y[1] - y[0], z[1] - z[0])
    center = ((x[0] + x[1]) / 2, (y[0] + y[1]) / 2, (z[0] + z[1]) / 2)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0)))
    return solid(name, bm, mat, bevel)


def lathe(name, profile, center, axis, mat, segments=24):
    """Spins (radius, distance along axis) points round an axis. Outside on your right."""
    bm = bmesh.new()
    turn = AXES[axis]
    rings = []
    for r, along in profile:
        ring = []
        for i in range(segments):
            a = math.tau * i / segments + math.pi / segments
            ring.append(bm.verts.new(turn @ Vector((math.cos(a) * r, math.sin(a) * r, along)) + Vector(center)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    return finish(name, bm, mat, 40)


def screw(name, center, mat, slot_mat, radius=0.005, axis="OUT", height=0.0035):
    """A pan-head screw with a slot across it."""
    head = lathe(name, [(0.0001, 0.0), (radius, 0.0), (radius, height * 0.45), (radius * 0.75, height * 0.9), (0.0001, height)],
            center, axis, mat, 16)
    if axis == "OUT":
        c = Vector(center)
        span(name + "Slot", (c.x - radius * 0.8, c.x + radius * 0.8), (c.y - radius * 0.14, c.y + radius * 0.14),
                (c.z + height * 0.55, c.z + height * 1.02), slot_mat)
    return head


def tube(name, corners, radius, mat, bend=0.01, sides=12, side_hint=(0.31, 0.87, 0.38), squash=1.0):
    """A conductor through the corners, with real bends at each one. squash flattens it, for cable sheath."""
    path = [Vector(corners[0])]
    for i in range(1, len(corners) - 1):
        a, p, b = Vector(corners[i - 1]), Vector(corners[i]), Vector(corners[i + 1])
        r = min(bend, (a - p).length * 0.45, (b - p).length * 0.45)
        s0 = p + (a - p).normalized() * r
        s1 = p + (b - p).normalized() * r
        for k in range(9):
            t = k / 8
            path.append(s0.lerp(p, t).lerp(p.lerp(s1, t), t))
    path.append(Vector(corners[-1]))
    bm = bmesh.new()
    side = Vector(side_hint)
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized()
        up = t.cross(side)
        rings.append([bm.verts.new(p + (side * math.cos(math.tau * k / sides) + up * math.sin(math.tau * k / sides) * squash) * radius)
                for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((a[k], a[j], b[j], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(name, bm, mat, 50)


def picture(name, width, height, center, mat):
    """A flat sticker facing out of the wall."""
    w, h = width / 2, height / 2
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x + center[0], y + center[1], center[2])) for x, y in ((-w, -h), (w, -h), (w, h), (-w, h))])
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = co
    return finish(name, bm, mat)


def plate_with_holes(name, xs, ys, holes, z0, z1, mat, bevel):
    """A flat sheet cut on a grid, with the cells in holes left open."""
    bm = bmesh.new()
    grid = [[bm.verts.new((x, y, z1)) for x in xs] for y in ys]
    faces = []
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            if (i, j) not in holes:
                faces.append(bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    made = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    moved = [g for g in made["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, 0, z0 - z1))
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts[:], edges=bm.edges[:])
    return solid(name, bm, mat, bevel)


def set_origin(obj, pivot):
    obj.data.transform(Matrix.Translation(-Vector(pivot)))
    obj.location = pivot


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


def to_blender_axes(objs):
    """Everything was laid out in Godot's axes; turn it so the export comes out that way."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.matrix_world = TO_BLENDER @ o.matrix_world
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)


def export(objs, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, filename), export_format="GLB", use_selection=True, export_yup=True)
    tris = 0
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    print("EXPORTED", filename, tris, "tris")


# --- Materials --------------------------------------------------------------

def material(name, color, metal=0.0, rough=0.5, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(ART, image))
        m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m


def materials():
    return {
        "paint": material("PanelPaint", (0.42, 0.43, 0.42), 0.1, 0.48),
        "galv": material("Galvanized", (0.5, 0.52, 0.53), 0.75, 0.42),
        "tin": material("TinPlate", (0.7, 0.71, 0.72), 0.9, 0.3),
        "lug": material("AluminumLug", (0.78, 0.79, 0.8), 0.9, 0.38),
        "copper": material("Copper", (0.86, 0.47, 0.26), 1.0, 0.3),
        "plastic": material("BlackPlastic", (0.02, 0.02, 0.022), 0.0, 0.42),
        "handle": material("HandlePlastic", (0.045, 0.045, 0.05), 0.0, 0.35),
        "zinc": material("ZincScrew", (0.72, 0.72, 0.68), 1.0, 0.28),
        "green": material("GreenScrew", (0.08, 0.32, 0.1), 0.6, 0.35),
        "dark": material("Shadow", (0.01, 0.01, 0.01), 0.0, 0.8),
        "black": material("BlackTHHN", (0.015, 0.015, 0.018), 0.0, 0.3),
        "red": material("RedTHHN", (0.45, 0.02, 0.015), 0.0, 0.3),
        "white": material("WhiteTHHN", (0.78, 0.78, 0.75), 0.0, 0.35),
        "burnt": material("ScorchedInsulation", (0.07, 0.035, 0.015), 0.0, 0.9),
        "nm14": material("SheathWhite", (0.72, 0.71, 0.66), 0.0, 0.55),
        "nm12": material("SheathYellow", (0.72, 0.5, 0.06), 0.0, 0.55),
        "nm10": material("SheathOrange", (0.75, 0.25, 0.04), 0.0, 0.55),
        "nm8": material("SheathBlack", (0.025, 0.025, 0.028), 0.0, 0.5),
        "warning": material("WarningSticker", (1, 1, 1), 0.0, 0.6, "panel_warning.png"),
        "rating": material("RatingSticker", (1, 1, 1), 0.3, 0.45, "panel_rating.png"),
    }


# --- The load center --------------------------------------------------------

def knockout(name, x, y, z, axis, m, radius=0.011):
    """The stamped ring of a knockout in the sheet metal."""
    t = 0.001
    return lathe(name, [(radius, 0.0), (radius, t), (radius * 0.82, t), (radius * 0.82, 0.0)], (x, y, z), axis, m, 20)


def build_enclosure(m):
    parts = []
    hw, hh = W / 2, H / 2
    parts.append(span("Back", (-hw, hw), (-hh, hh), (0.0, SHEET), m["galv"]))
    parts.append(span("WallL", (-hw, -hw + SHEET), (-hh, hh), (0.0, DEPTH), m["paint"], 0.0006))
    parts.append(span("WallR", (hw - SHEET, hw), (-hh, hh), (0.0, DEPTH), m["paint"], 0.0006))
    parts.append(span("WallTop", (-hw, hw), (hh - SHEET, hh), (0.0, DEPTH), m["paint"], 0.0006))
    parts.append(span("WallBottom", (-hw, hw), (-hh, -hh + SHEET), (0.0, DEPTH), m["paint"], 0.0006))
    # The front edge is rolled inward, which stiffens the box.
    for x in ((-hw, -hw + 0.008), (hw - 0.008, hw)):
        parts.append(span("Lip", x, (-hh, hh), (DEPTH - SHEET, DEPTH), m["paint"]))
    for y in ((-hh, -hh + 0.008), (hh - 0.008, hh)):
        parts.append(span("Lip", (-hw, hw), y, (DEPTH - SHEET, DEPTH), m["paint"]))
    # Rain hood over the door.
    hood = span("RainHood", (-hw - 0.006, hw + 0.006), (hh - 0.004, hh + 0.004), (DEPTH * 0.5, DEPTH + 0.03), m["paint"], 0.0015)
    parts.append(hood)
    # Knockouts in two staggered rows top and bottom, a few in the sides and back.
    for top in (True, False):
        y = hh if top else -hh
        axis = "UP" if top else "DOWN"
        for s in (-1, 1):
            for i in range(4):
                parts.append(knockout("KO", s * (0.145 + i * 0.016), y, 0.035 if i % 2 == 0 else 0.07, axis, m["paint"]))
        for x in (-0.07, 0.07):
            parts.append(knockout("KO", x, y, 0.05, axis, m["paint"], 0.016))
    for s in (-1, 1):
        for y in (-0.3, 0.3):
            parts.append(knockout("KO", s * hw, y, 0.05, "RIGHT", m["paint"], 0.014))
    for x, y in ((-0.1, -0.12), (0.1, -0.12), (0.0, 0.33)):
        parts.append(knockout("KO", x, y, SHEET, "OUT", m["galv"], 0.016))
    # Mounting holes, and the green bonding screw on the back.
    for x in (-0.15, 0.15):
        parts.append(lathe("MountHole", [(0.006, SHEET), (0.006, SHEET + 0.0004), (0.0001, SHEET + 0.0004)], (x, 0.38, 0), "OUT", m["dark"], 12))
    parts.append(screw("BondScrew", (-0.12, -0.38, SHEET), m["green"], m["dark"], 0.006))
    return join(parts, "Enclosure")


def build_interior(m):
    parts = []
    # Bus assembly: black base, two bars, a finger per row out to the stabs.
    parts.append(span("BusBase", (-0.034, 0.034), (-0.208, 0.226), (SHEET, 0.012), m["plastic"], 0.002))
    for s in (-1, 1):
        parts.append(span("BusBar", sorted((s * 0.0025, s * 0.0155)), (-0.19, 0.205), (0.012, 0.02), m["tin"], 0.0008))
    for row in range(8):
        y = TOP_ROW - row * ROW
        bar = -0.009 if row % 2 == 0 else 0.009
        parts.append(span("Riser", (bar - 0.006, bar + 0.006), (y - 0.006, y + 0.006), (0.02, 0.024), m["tin"]))
        parts.append(span("Finger", (-0.05, 0.05), (y - 0.006, y + 0.006), (0.024, 0.027), m["tin"], 0.0008))
        for s in (-1, 1):
            parts.append(span("Stab", sorted((s * 0.032, s * 0.048)), (y - 0.0075, y + 0.0075), (0.027, 0.036), m["tin"], 0.001))
        # Ribs between rows keep the breakers apart.
        rib = y - ROW / 2
        if row < 7:
            parts.append(span("Rib", (-0.03, 0.03), (rib - 0.0015, rib + 0.0015), (0.012, 0.03), m["plastic"]))

    # Main breaker, with its line lugs above and load straps down to the bus.
    parts.append(span("MainBody", (-0.085, 0.085), (0.2325, 0.3075), (0.018, 0.074), m["plastic"], 0.003))
    parts.append(span("MainFace", (-0.065, 0.065), (0.24, 0.3), (0.074, 0.078), m["plastic"], 0.002))
    parts.append(span("MainSlot", (-0.054, 0.054), (0.255, 0.285), (0.0775, 0.0785), m["dark"]))
    for s in (-1, 1):
        x = s * 0.04
        parts.append(span("LineTab", (x - 0.012, x + 0.012), (0.3, 0.322), (0.04, 0.05), m["tin"]))
        parts.append(span("LineLug", (x - 0.021, x + 0.021), (0.32, 0.35), (0.035, 0.064), m["lug"], 0.002))
        parts.append(lathe("LugSocket", [(0.0075, 0.064), (0.0075, 0.0665), (0.0045, 0.0665), (0.0045, 0.062)], (x, 0.335, 0), "OUT", m["lug"], 6))
        parts.append(span("LugHex", (x - 0.003, x + 0.003), (0.332, 0.338), (0.0655, 0.0662), m["dark"]))
        parts.append(span("LoadLug", (x - 0.016, x + 0.016), (0.201, 0.223), (0.023, 0.047), m["lug"], 0.0015))
        parts.append(screw("LoadScrew", (x, 0.212, 0.047), m["zinc"], m["dark"], 0.005))
        parts.append(span("LoadStrap", sorted((s * 0.009, x)), (0.196, 0.206), (0.016, 0.022), m["tin"]))

    # Service conductors from the hub in the top down to the lugs.
    hub_x = -0.02
    parts.append(lathe("ServiceHub", [(0.03, H / 2 + 0.03), (0.03, H / 2), (0.036, H / 2), (0.036, H / 2 - 0.006), (0.026, H / 2 - 0.006),
            (0.026, H / 2 + 0.03)], (hub_x, 0, 0.05), "UP", m["galv"], 24))
    top = H / 2 + 0.03
    parts.append(tube("ServiceL1", [(-0.032, top, 0.05), (-0.032, 0.39, 0.05), (-0.04, 0.37, 0.05), (-0.04, 0.35, 0.05)], 0.0047, m["black"], 0.015))
    parts.append(tube("ServiceL2", [(-0.008, top, 0.05), (-0.008, 0.395, 0.05), (0.04, 0.375, 0.05), (0.04, 0.35, 0.05)], 0.0047, m["red"], 0.015))
    parts.append(tube("ServiceN", [(-0.009, top, 0.042), (-0.009, 0.41, 0.04), (-0.2, 0.405, 0.04), (-0.2, 0.282, 0.04)], 0.0047, m["white"], 0.025))
    parts.append(span("ServiceTape", (-0.038, -0.026), (0.398, 0.404), (0.044, 0.056), m["black"]))

    # Neutral bars on standoffs, with a big lug for the service neutral.
    for s in (-1, 1):
        x = s * 0.2
        parts.append(span("NeutralBar", (x - 0.011, x + 0.011), (-0.25, 0.25), (0.03, 0.05), m["tin"], 0.0015))
        for y in (-0.235, 0.235):
            parts.append(span("Standoff", (x - 0.01, x + 0.01), (y - 0.008, y + 0.008), (SHEET, 0.03), m["plastic"], 0.001))
        y = 0.235
        while y > -0.25:
            parts.append(screw("NeutralScrew", (x, y, 0.05), m["zinc"], m["dark"], 0.0048))
            parts.append(lathe("WireHole", [(0.0022, 0.0), (0.0022, 0.0005), (0.0001, 0.0005)], (x - s * 0.011, y, 0.04), "RIGHT" if s < 0 else "RIGHT", m["dark"], 10))
            y -= 0.04
    parts.append(span("NeutralLug", (-0.216, -0.184), (0.25, 0.282), (0.026, 0.056), m["lug"], 0.002))
    parts.append(screw("NeutralLugScrew", (-0.2, 0.266, 0.056), m["zinc"], m["dark"], 0.006))
    # Bonding strap tying the neutral bars together, and the grounding electrode conductor out the bottom.
    parts.append(span("BondStrap", (-0.205, 0.205), (-0.271, -0.259), (0.022, 0.026), m["copper"], 0.0008))
    for s in (-1, 1):
        parts.append(span("StrapTab", (s * 0.2 - 0.006, s * 0.2 + 0.006), (-0.265, -0.248), (0.026, 0.03), m["tin"]))
    parts.append(tube("GEC", [(-0.2, -0.25, 0.04), (-0.2, -0.29, 0.04), (-0.214, -0.31, 0.03), (-0.214, -H / 2 - 0.02, 0.03)], 0.0021, m["copper"], 0.015))

    # Ground bar along the bottom, green screws.
    parts.append(span("GroundBar", (-0.135, 0.135), (-0.34, -0.32), (0.03, 0.05), m["tin"], 0.0015))
    for x in (-0.12, 0.12):
        parts.append(span("GroundFoot", (x - 0.01, x + 0.01), (-0.338, -0.322), (SHEET, 0.03), m["tin"]))
    for k in range(12):
        x = (0.02 + (k % 6) * 0.02) * (-1 if k < 6 else 1)
        parts.append(screw("GroundScrew", (x, -0.33, 0.05), m["green"], m["dark"], 0.0045))
    return join(parts, "Interior")


def build_main_handle(m):
    handle = span("MainHandle", (-0.05, 0.05), (0.259, 0.281), (0.072, 0.1), m["handle"], 0.003)
    grip = span("MainGrip", (-0.046, 0.046), (0.262, 0.278), (0.1, 0.102), m["handle"], 0.0015)
    joined = join([handle, grip], "MainHandle")
    set_origin(joined, (0.0, 0.27, 0.086))
    return joined


def build_dead_front(m):
    hw, hh = W / 2 + 0.006, H / 2 + 0.006
    xs = [-hw, -0.108, -0.008, 0.008, 0.108, hw]
    ys = [-hh, -0.2, 0.19, 0.22, 0.31, hh]
    holes = {(1, 1), (3, 1), (1, 3), (2, 3), (3, 3)}
    parts = [plate_with_holes("DeadFrontPlate", xs, ys, holes, COVER_Z - 0.0015, COVER_Z, m["paint"], 0.0006)]
    # Flanges bent back round the edge, over the front of the box.
    for x in ((-hw, -hw + SHEET), (hw - SHEET, hw)):
        parts.append(span("Flange", x, (-hh, hh), (0.084, COVER_Z), m["paint"], 0.0005))
    for y in ((-hh, -hh + SHEET), (hh - SHEET, hh)):
        parts.append(span("Flange", (-hw, hw), y, (0.084, COVER_Z), m["paint"], 0.0005))
    # Stiffening rib pressed round the openings.
    for x in ((-0.116, -0.112), (0.112, 0.116)):
        parts.append(span("Rib", x, (-0.208, 0.318), (COVER_Z, COVER_Z + 0.0012), m["paint"], 0.0005))
    for y in ((-0.208, -0.204), (0.314, 0.318)):
        parts.append(span("Rib", (-0.116, 0.116), y, (COVER_Z, COVER_Z + 0.0012), m["paint"], 0.0005))
    parts.append(lathe("ScrewDimple", [(0.011, COVER_Z), (0.011, COVER_Z + 0.0008), (0.008, COVER_Z + 0.0008), (0.0001, COVER_Z + 0.0008)],
            (SCREW_AT[0], SCREW_AT[1], 0), "OUT", m["paint"], 20))
    parts.append(picture("Warning", 0.2, 0.06, (0.0, 0.37, COVER_Z + 0.0004), m["warning"]))
    parts.append(picture("Rating", 0.16, 0.0615, (0.0, -0.285, COVER_Z + 0.0004), m["rating"]))
    return join(parts, "DeadFront")


def build_cover_screw(m):
    z = COVER_Z + 0.0008
    head = screw("CoverScrew", (SCREW_AT[0], SCREW_AT[1], z), m["zinc"], m["dark"], 0.0068, height=0.0042)
    slot = bpy.data.objects["CoverScrewSlot"]
    joined = join([head, slot], "CoverScrew")
    set_origin(joined, (SCREW_AT[0], SCREW_AT[1], z))
    return joined


def build_door(m):
    hw, hh = W / 2 + 0.013, H / 2 + 0.006
    z = DOOR_HINGE[1]
    parts = [span("DoorSkin", (-hw, hw), (-hh, hh), (z - 0.0015, z + 0.0015), m["paint"], 0.0012)]
    for x in ((-hw, -hw + SHEET), (hw - SHEET, hw)):
        parts.append(span("DoorEdge", x, (-hh, hh), (0.1, z + 0.0015), m["paint"], 0.0005))
    for y in ((-hh, -hh + SHEET), (hh - SHEET, hh)):
        parts.append(span("DoorEdge", (-hw, hw), y, (0.1, z + 0.0015), m["paint"], 0.0005))
    # Two pressed ribs across the door so it isn't a flat sheet.
    for y in (-0.22, 0.22):
        parts.append(span("DoorRib", (-hw + 0.04, hw - 0.04), (y - 0.006, y + 0.006), (z + 0.0015, z + 0.003), m["paint"], 0.002))
    # Hinge knuckles down the hinge side.
    for y in (-0.33, 0.0, 0.33):
        parts.append(lathe("Hinge", [(0.0001, y - 0.035), (0.004, y - 0.035), (0.004, y + 0.035), (0.0001, y + 0.035)],
                (DOOR_HINGE[0], 0, z - 0.002), "UP", m["galv"], 12))
    # Latch handle and padlock hasp on the free side.
    parts.append(span("LatchPlate", (hw - 0.045, hw - 0.015), (-0.055, 0.055), (z + 0.0015, z + 0.004), m["galv"], 0.0015))
    parts.append(span("Latch", (hw - 0.04, hw - 0.02), (-0.045, 0.045), (z + 0.004, z + 0.015), m["handle"], 0.003))
    parts.append(span("Hasp", (hw - 0.034, hw - 0.026), (-0.36, -0.33), (z + 0.0015, z + 0.02), m["galv"], 0.0015))
    parts.append(lathe("HaspHole", [(0.0035, -0.004), (0.0035, 0.004)], (hw - 0.03, -0.345, z + 0.013), "RIGHT", m["dark"], 10))
    door = join(parts, "Door")
    set_origin(door, (DOOR_HINGE[0], 0.0, z))
    return door


def connector(x, wall_y, z, top, m):
    """An NM cable connector through a knockout: body outside, locknut inside."""
    axis = "UP" if top else "DOWN"
    sgn = 1 if top else -1
    parts = [lathe("ConnectorBody", [(0.0105, 0.018), (0.0105, 0.004), (0.0125, 0.004), (0.0125, 0.0), (0.0095, 0.0), (0.0095, 0.018)],
            (x, wall_y, z), axis, m["galv"], 16)]
    parts.append(lathe("Locknut", [(0.0135, -SHEET - 0.003), (0.0135, -SHEET), (0.0092, -SHEET), (0.0092, -SHEET - 0.003)],
            (x, wall_y, z), axis, m["galv"], 6))
    parts.append(span("ClampStrap", (x - 0.013, x + 0.013), sorted((wall_y + sgn * 0.012, wall_y + sgn * 0.016)), (z - 0.007, z + 0.007), m["galv"], 0.0008))
    for dx in (-0.011, 0.011):
        parts.append(lathe("ClampScrew", [(0.0001, 0.0), (0.0025, 0.0), (0.0025, 0.002), (0.0001, 0.0026)],
                (x + dx, wall_y + sgn * 0.016, z), axis, m["zinc"], 8))
    return parts


# --- Wiring -------------------------------------------------------------------

def side_of(slot):
    return -1 if slot % 2 == 1 else 1


def row_of(slot):
    return (slot - 1) // 2


def y_of(slot):
    return TOP_ROW - row_of(slot) * ROW


def from_top(slot):
    return row_of(slot) < 4


def wobble(corners, rng, amount=0.0012):
    """Real wire never runs dead straight: nudge the middle of each long run a touch."""
    out = [corners[0]]
    for a, b in zip(corners, corners[1:]):
        if (Vector(b) - Vector(a)).length > 0.08:
            mid = (Vector(a) + Vector(b)) / 2
            out.append((mid.x + rng.uniform(-amount, amount), mid.y, mid.z + rng.uniform(-amount, amount)))
        out.append(b)
    return out


def build_wiring(m):
    """Every circuit's cable: through a connector, the sheath stripped back just
    inside, hots dressed down the gutter and into their breakers, the white to a
    neutral bar, the bare copper to the ground bar."""
    sheath_mat = {15: m["nm14"], 20: m["nm12"], 30: m["nm10"], 40: m["nm8"]}
    static = []
    hots = []
    entry = {}
    lanes = {}
    for top in (True, False):
        for s in (-1, 1):
            poles = [p for c in CIRCUITS if side_of(c[0]) == s and from_top(c[0]) == top for p in c[1]]
            poles.sort(key=lambda p: row_of(p) if top else -row_of(p))
            for j, p in enumerate(poles):
                lanes[p] = 0.145 + j * 0.008
    neutral_n = {}
    ground_n = {-1: 0, 1: 0}
    for slot, poles, rating, has_neutral in CIRCUITS:
        rng = random.Random(slot * 31)
        s = side_of(slot)
        top = from_top(slot)
        i = entry.get((s, top), 0)
        entry[(s, top)] = i + 1
        cx = s * (0.145 + i * 0.016)
        cz = 0.035 if i % 2 == 0 else 0.07
        dirn = -1 if top else 1                  # the way into the box
        edge = -dirn * H / 2
        end = edge + dirn * 0.06                 # where the sheath is stripped back
        static += connector(cx, edge, cz, top, m)
        static.append(tube("Sheath", [(cx, edge - dirn * 0.075, -0.02), (cx, edge - dirn * 0.035, cz), (cx, end, cz)],
                SHEATH[rating], sheath_mat[rating], 0.02, 14, (1, 0, 0), 0.5))
        r = INSULATED[rating]
        out_of_sheath = lambda dx: [(cx + dx, end - dirn * 0.004, cz), (cx + dx, end + dirn * 0.012, cz)]

        for k, pole in enumerate(poles):
            y = y_of(pole)
            lane = s * lanes[pole]
            colour = m["black"] if k == 0 else m["red"]
            run = out_of_sheath(s * 0.0024 * (k - 0.5) if len(poles) > 1 else 0.0) + [(lane, end + dirn * 0.035, WIRE_Z), (lane, y, WIRE_Z)]
            run = wobble(run, rng)
            stripped = (s * (TERM_X + 0.012), y, WIRE_Z)
            landed = [tube("Insulation", run + [stripped], r, colour, 0.006),
                    tube("Copper", [stripped, (s * (TERM_X - 0.004), y, WIRE_Z)], r * 0.62, m["copper"])]
            pulled = (s * (TERM_X + 0.03), y - dirn * 0.006, WIRE_Z + 0.03)
            tip = Vector(pulled) + (Vector(pulled) - Vector(run[-1])).normalized() * 0.013
            freed = [tube("Insulation", run + [pulled], r, colour, 0.006), tube("Copper", [pulled, tuple(tip)], r * 0.62, m["copper"])]
            burnt = [tube("Scorched", [(s * (TERM_X + 0.032), y, WIRE_Z), stripped], r * 1.28, m["burnt"]),
                    tube("BlackCopper", [stripped, (s * (TERM_X - 0.002), y, WIRE_Z)], r * 0.7, m["dark"])]
            hots.append(join(landed, "Hot%d_Landed" % pole))
            hots.append(join(freed, "Hot%d_Freed" % pole))
            hots.append(join(burnt, "Hot%d_Burnt" % pole))

        if has_neutral:
            key = (s, top)
            n = neutral_n.get(key, 0)
            neutral_n[key] = n + 1
            bar_y = 0.235 - n * 0.04 if top else -0.205 + n * 0.04
            lane = s * (0.186 - n * 0.005)
            run = wobble(out_of_sheath(0.0) + [(lane, end + dirn * 0.03, NEUTRAL_Z), (lane, bar_y, NEUTRAL_Z)], rng)
            stripped = (s * 0.183, bar_y, NEUTRAL_Z)
            static.append(tube("Neutral", run + [stripped], r, m["white"], 0.006))
            static.append(tube("NeutralCopper", [stripped, (s * 0.195, bar_y, NEUTRAL_Z)], r * 0.62, m["copper"]))

        g = ground_n[s]
        ground_n[s] = g + 1
        gx = s * (0.02 + g * 0.02)
        lane = s * (0.2145 + g * 0.0022)
        across = -0.29 - g * 0.004
        run = wobble(out_of_sheath(0.0) + [(lane, end + dirn * 0.02, GROUND_Z), (lane, across, GROUND_Z), (gx, across, GROUND_Z),
                (gx, -0.312, 0.04), (gx, -0.326, 0.04)], rng, 0.0008)
        static.append(tube("Ground", run, BARE[rating], m["copper"], 0.005, 8))
    return [join(static, "Wiring")] + hots


# --- Breakers ---------------------------------------------------------------

def build_breaker(m, poles):
    """A plug-on breaker for the right-hand column, centred on its row(s)."""
    h = ROW * poles - 0.003
    parts = [span("Case", (0.02, 0.12), (-h / 2, h / 2), (0.02, 0.07), m["plastic"], 0.0025)]
    parts.append(span("Face", (0.029, 0.081), (-h / 2 + 0.003, h / 2 - 0.003), (0.069, 0.077), m["plastic"], 0.002))
    parts.append(span("HandleWell", (0.04, 0.07), (-h / 2 + 0.005, h / 2 - 0.005), (0.0765, 0.0775), m["dark"]))
    parts.append(span("Jaw", (0.026, 0.044), (-0.008, 0.008), (0.02, 0.03), m["tin"]))
    parts.append(span("Vent", (0.088, 0.106), (-h / 2 + 0.004, -h / 2 + 0.007), (0.0695, 0.0705), m["dark"]))
    centers = [0.0] if poles == 1 else [ROW / 2, -ROW / 2]
    for y in centers:
        parts.append(span("Lug", (0.105, 0.123), (y - 0.009, y + 0.009), (0.068, 0.076), m["lug"], 0.0015))
        parts.append(screw("TermScrew", (TERM_X, y, 0.076), m["zinc"], m["dark"], 0.0062, height=0.0052))
    body = join(parts, "Body")
    handles = []
    for y in centers:
        hh = (ROW - 0.012) / 2
        handles.append(span("Lever", (HANDLE_X - 0.012, HANDLE_X + 0.012), (y - hh, y + hh), (0.075, 0.095), m["handle"], 0.002))
        for k in (-1, 0, 1):
            handles.append(span("Grip", (HANDLE_X - 0.01, HANDLE_X + 0.01), (y + k * 0.006 - 0.0008, y + k * 0.006 + 0.0008),
                    (0.095, 0.0962), m["handle"]))
    if poles > 1:
        handles.append(span("TieBar", (HANDLE_X - 0.004, HANDLE_X + 0.004), (-ROW / 2, ROW / 2), (0.089, 0.093), m["tin"], 0.001))
    handle = join(handles, "Handle")
    set_origin(handle, (HANDLE_X, 0.0, 0.085))
    return [body, handle]


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = materials()
    panel = [build_enclosure(m), build_interior(m), build_main_handle(m), build_dead_front(m), build_cover_screw(m),
            build_door(m)] + build_wiring(m)
    to_blender_axes(panel)
    export(panel, "panel.glb")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "panel.blend"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = materials()
    for poles in (1, 2):
        before = set(bpy.context.scene.objects)
        breaker = build_breaker(m, poles)
        to_blender_axes(breaker)
        export(breaker, "breaker_%dp.glb" % poles)
        # Park it to one side so both are visible in the .blend, and free up
        # the names Body and Handle for the next one.
        for o in set(bpy.context.scene.objects) - before:
            o.location.x += 0.2 * poles
            o.name = "Breaker%dP_%s" % (poles, o.name)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "breakers.blend"))


main()
