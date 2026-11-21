"""Builds the 200 A residential meter base and exports it for the game.

Run from the project root:
    blender --background --python art/meter_base.py

Writes art/meter_base.blend and assets/meter_base/meter_base.glb, which holds
four pieces the game takes apart: Can, Cover, Seal and Meter.

Units are metres. The origin is the middle of the back of the can, where it
meets the wall. -Y is out of the wall, which becomes +Z in Godot.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(ROOT, "assets", "meter_base")

SEGMENTS = 40

W = 0.28            # can width, 11 in
H = 0.37            # can height, 14.5 in
CAN_D = 0.085       # can depth, not counting the cover
COVER_D = 0.016     # cover thickness, its front is at -(CAN_D + COVER_D)
FRONT = CAN_D + COVER_D
METER_Z = 0.018     # the socket sits a bit above the middle
HUB_Y = -0.06       # the mast runs this far off the wall
JAWS = [(-0.03, 0.033), (0.03, 0.033), (-0.03, -0.033), (0.03, -0.033)]   # line jaws on top, load below

# Which way a lathe's axis points. "OUT" is out of the wall.
AXES = {
    "UP": Matrix.Identity(3),
    "DOWN": Matrix.Rotation(math.pi, 3, "X"),
    "OUT": Matrix.Rotation(math.pi / 2, 3, "X"),
    "RIGHT": Matrix.Rotation(math.pi / 2, 3, "Y"),
    "LEFT": Matrix.Rotation(-math.pi / 2, 3, "Y"),
}


def material(name, color, metal=0.0, rough=0.5, alpha=1.0, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(ROOT, "art", image))
        m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m


def finish(name, bm, mat, smooth_below=None):
    """Turns a bmesh into a scene object, smooth except for its hard creases."""
    # Every part needs the layer, or joining the parts throws the decals' UVs away.
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


def box(name, size, center, mat, bevel=0.0):
    """A box, with soft edges if bevel is given."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0)))
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.5)
    return finish(name, bm, mat, 35)


def lathe(name, profile, center, axis, mat, segments=SEGMENTS):
    """Spins a [(radius, distance along axis)...] profile round an axis.

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


def decal(name, verts, uvs, center, mat):
    """A flat picture facing out of the wall. verts are (x, z) pairs."""
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x + center[0], center[1], z + center[2])) for x, z in verts])
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, co in zip(face.loops, uvs):
        loop[uv].uv = co
    return finish(name, bm, mat)


def rect_decal(name, width, height, center, mat):
    w, h = width / 2, height / 2
    return decal(name, [(-w, -h), (w, -h), (w, h), (-w, h)], [(0, 0), (1, 0), (1, 1), (0, 1)], center, mat)


def disc_decal(name, radius, center, mat):
    """A round picture, showing the circle that fits inside the image."""
    circle = [(math.cos(math.tau * i / SEGMENTS), math.sin(math.tau * i / SEGMENTS)) for i in range(SEGMENTS)]
    return decal(name, [(c * radius, s * radius) for c, s in circle], [(0.5 + c / 2, 0.5 + s / 2) for c, s in circle], center, mat)


def screw(name, center, axis, mat, radius=0.0065):
    h = 0.004
    return lathe(name, [(0.0001, 0.0), (radius, 0.0), (radius, h * 0.5), (radius * 0.7, h), (0.0001, h)], center, axis, mat, 12)


def tube(name, corners, radius, mat, bend=0.02, sides=10):
    """A round conductor through the corners, with a bend at each one."""
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
    side = Vector((0.31, 0.87, 0.38))
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = (side - t * side.dot(t)).normalized()
        up = t.cross(side)
        rings.append([bm.verts.new(p + (side * math.cos(math.tau * k / sides) + up * math.sin(math.tau * k / sides)) * radius) for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((a[k], a[j], b[j], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(name, bm, mat, 50)


def knockout(name, center, axis, mat, radius):
    """The stamped ring of a knockout, standing just proud of the sheet metal."""
    t = 0.0012
    return lathe(name, [(radius, 0.0), (radius, t), (radius * 0.86, t), (radius * 0.86, 0.0)], center, axis, mat, 24)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    paint = material("MeterBasePaint", (0.36, 0.38, 0.37), 0.15, 0.52)
    steel = material("Galvanized", (0.62, 0.64, 0.65), 0.85, 0.42)
    stainless = material("Stainless", (0.78, 0.79, 0.8), 1.0, 0.25)
    plastic = material("MeterPlastic", (0.74, 0.75, 0.72), 0.0, 0.5)
    dark = material("MeterDark", (0.055, 0.06, 0.065), 0.0, 0.55)
    glass = material("MeterGlass", (0.86, 0.9, 0.9), 0.0, 0.05, alpha=0.1)
    face = material("MeterFace", (1, 1, 1), 0.0, 0.5, image="meter_face.png")
    label = material("CoverLabel", (1, 1, 1), 0.0, 0.6, image="cover_label.png")
    seal = material("SealRed", (0.7, 0.04, 0.03), 0.0, 0.4)

    # The can: a tub open at the front, so there's something to see with the cover off.
    tin = material("JawTin", (0.72, 0.73, 0.74), 0.9, 0.3)
    insulator = material("SocketBlock", (0.03, 0.03, 0.032), 0.0, 0.45)
    black = material("BlackTHHN", (0.015, 0.015, 0.018), 0.0, 0.3)
    red = material("RedTHHN", (0.45, 0.02, 0.015), 0.0, 0.3)
    galv = material("CanInside", (0.5, 0.52, 0.53), 0.7, 0.42)
    t = 0.0015
    box("Can", (W, t, H), (0, -t / 2, 0), galv)
    for s in (-1, 1):
        box("CanWall", (t, CAN_D, H), (s * (W - t) / 2, -CAN_D / 2, 0), paint, 0.0006)
        box("CanWall", (W, CAN_D, t), (0, -CAN_D / 2, s * (H - t) / 2), paint, 0.0006)
    # The socket: a black block with four spring jaws for the meter's blades.
    box("SocketBlock", (0.15, 0.022, 0.17), (0, -0.012, METER_Z), insulator, 0.003)
    for x, z in JAWS:
        box("Jaw", (0.014, 0.034, 0.024), (x, -0.04, METER_Z + z), tin, 0.0015)
        box("JawSlot", (0.004, 0.002, 0.018), (x, -0.0575, METER_Z + z), dark)
        screw("JawScrew", (x, -0.023, METER_Z + z + 0.017), "UP", stainless, 0.004)
    box("NeutralLug", (0.03, 0.02, 0.022), (0, -0.03, METER_Z - 0.105), tin, 0.002)
    # Service conductors from the hub to the line jaws; load side out the bottom.
    hub = (0, HUB_Y, H / 2 - 0.004)
    tube("LineL1", [(-0.012, HUB_Y, H / 2 + 0.01), (-0.012, HUB_Y, 0.16), (-0.03, -0.045, METER_Z + 0.08), (-0.03, -0.045, METER_Z + 0.045)], 0.0045, black)
    tube("LineL2", [(0.012, HUB_Y, H / 2 + 0.01), (0.012, HUB_Y, 0.16), (0.03, -0.045, METER_Z + 0.08), (0.03, -0.045, METER_Z + 0.045)], 0.0045, red)
    tube("LoadL1", [(-0.03, -0.045, METER_Z - 0.045), (-0.03, -0.045, METER_Z - 0.09), (-0.07, -0.045, -0.14), (-0.07, -0.045, -H / 2 - 0.01)], 0.0045, black)
    tube("LoadL2", [(0.03, -0.045, METER_Z - 0.045), (0.03, -0.045, METER_Z - 0.09), (0.07, -0.045, -0.14), (0.07, -0.045, -H / 2 - 0.01)], 0.0045, red)
    box("Cover", (W + 0.006, COVER_D, H + 0.006), (0, -(CAN_D + COVER_D / 2), 0), paint, 0.006)
    # The raised collar pressed into the cover round the socket.
    lathe("CoverCollar", [(0.112, FRONT), (0.111, FRONT + 0.004), (0.104, FRONT + 0.012), (0.09, FRONT + 0.012)],
            (0, 0, METER_Z), "OUT", paint)
    # Mounting tabs, flat against the wall.
    for s in (-1, 1):
        for z in (-0.13, 0.13):
            box("MountTab", (0.03, 0.003, 0.05), (s * (W / 2 + 0.012), -0.0015, z), steel, 0.001)

    # Top hub, where the mast comes in.
    box("HubPlate", (0.105, 0.075, 0.009), (0, HUB_Y, H / 2 + 0.003), steel, 0.002)
    for sx in (-1, 1):
        for sy in (-1, 1):
            screw("HubScrew", (sx * 0.042, HUB_Y + sy * 0.026, H / 2 + 0.0075), "UP", stainless, 0.0045)
    top = H / 2 + 0.0075
    lathe("Hub", [(0.042, top), (0.042, top + 0.006), (0.034, top + 0.014), (0.034, top + 0.03), (0.038, top + 0.032),
            (0.038, top + 0.042), (0.0335, top + 0.044), (0.031, top + 0.044), (0.031, top + 0.02)], (0, HUB_Y, 0), "UP", steel)

    # Knockouts in the sides and the bottom.
    for z in (0.09, -0.1):
        knockout("Knockout", (W / 2, -CAN_D / 2, z), "RIGHT", paint, 0.028)
        knockout("Knockout", (-W / 2, -CAN_D / 2, z), "LEFT", paint, 0.028)
    for x in (-0.07, 0.07):
        knockout("Knockout", (x, -CAN_D / 2, -H / 2), "DOWN", paint, 0.028)

    # Cover screws in the corners.
    for sx in (-1, 1):
        for sz in (-1, 1):
            screw("CoverScrew", (sx * (W / 2 - 0.016), -FRONT, sz * (H / 2 - 0.016)), "OUT", stainless)

    # The latch at the bottom of the cover, with the utility's hasp and red tag seal.
    box("Latch", (0.05, 0.006, 0.03), (0, -(FRONT + 0.003), -0.145), steel, 0.0015)
    box("Hasp", (0.016, 0.022, 0.022), (0, -(FRONT + 0.014), -0.145), steel, 0.002)
    lathe("SealLoop", [(0.009, -0.0013), (0.0105, 0.0), (0.009, 0.0013), (0.0075, 0.0), (0.009, -0.0013)],
            (0, -(FRONT + 0.028), -0.148), "UP", seal, 20)
    box("SealTag", (0.02, 0.002, 0.03), (0, -(FRONT + 0.03), -0.176), seal, 0.0008)

    # The warning sticker, down in the corner clear of the collar.
    rect_decal("Label", 0.085, 0.0425, (-0.075, -(FRONT + 0.0006), -0.14), label)

    # The meter: a dark base, a stainless ring, the works, and a clear dome.
    collar = FRONT + 0.012
    lathe("MeterBase", [(0.0001, collar - 0.001), (0.094, collar - 0.001), (0.094, collar + 0.012), (0.09, collar + 0.018), (0.084, collar + 0.02)],
            (0, 0, METER_Z), "OUT", dark)
    lathe("SealingRing", [(0.0955, collar - 0.0015), (0.0985, collar + 0.002), (0.0985, collar + 0.013), (0.0955, collar + 0.0165)],
            (0, 0, METER_Z), "OUT", stainless)
    box("RingLatch", (0.024, 0.012, 0.012), (0, -(collar + 0.008), METER_Z - 0.102), stainless, 0.002)
    # The blades on its back that plug into the jaws.
    for x, z in JAWS:
        box("Blade", (0.003, collar - 0.045, 0.016), (x, -(collar + 0.045) / 2, METER_Z + z), tin)

    works_front = collar + 0.086
    lathe("MeterWorks", [(0.08, collar + 0.018), (0.08, works_front - 0.008), (0.076, works_front), (0.0001, works_front)],
            (0, 0, METER_Z), "OUT", plastic)
    disc_decal("MeterFace", 0.072, (0, -(works_front + 0.0006), METER_Z), face)
    lathe("MeterGlass", [(0.0845, collar + 0.018), (0.0845, works_front + 0.002), (0.082, works_front + 0.016), (0.074, works_front + 0.026),
            (0.056, works_front + 0.033), (0.0001, works_front + 0.036)], (0, 0, METER_Z), "OUT", glass)


PARTS = {
    "Cover": {"Cover", "CoverCollar", "CoverScrew", "CoverScrewSlot", "Latch", "Hasp", "Label", "SealingRing", "RingLatch"},
    "Seal": {"SealLoop", "SealTag"},
    "Meter": {"MeterBase", "MeterWorks", "MeterFace", "MeterGlass", "Blade"},
}


def merge():
    """Four pieces the game can take apart: the can on the wall (with the socket
    inside), the cover, the utility's tag seal, and the meter. Each one's origin
    is where the game moves it from."""
    collar = FRONT + 0.012
    origins = {"Can": (0, 0, 0), "Cover": (0, -FRONT, 0), "Seal": (0, -(FRONT + 0.028), -0.148), "Meter": (0, -collar, METER_Z)}
    groups = {}
    for obj in list(bpy.context.scene.objects):
        part = obj.name.split(".")[0]
        kind = next((k for k, names in PARTS.items() if part in names), "Can")
        groups.setdefault(kind, []).append(obj)
    for kind, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        joined = bpy.context.active_object
        joined.name = kind
        joined.data.name = kind
        joined.data.transform(Matrix.Translation(-Vector(origins[kind])))
        joined.location = origins[kind]


def export():
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", "meter_base.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(ASSET_DIR, "meter_base.glb"), export_format="GLB", export_yup=True)
    for obj in bpy.context.scene.objects:
        obj.data.calc_loop_triangles()
        print("MESH", obj.name, len(obj.data.loop_triangles), "tris,", len(obj.data.materials), "materials")


build()
merge()
export()
