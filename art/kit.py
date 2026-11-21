"""Shared modelling helpers for the asset scripts.

Everything is laid out in Godot's axes (metres, +Y up, +Z toward the viewer)
and turned into Blender's at the end with to_blender_axes(), so the numbers in
the scripts match the numbers in the game.

    import sys, os; sys.path.insert(0, os.path.dirname(__file__)); from kit import *
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art")

AXES = {
    "OUT": Matrix.Identity(3),                          # +Z
    "BACK": Matrix.Rotation(math.pi, 3, "Y"),           # -Z
    "UP": Matrix.Rotation(-math.pi / 2, 3, "X"),        # +Y
    "DOWN": Matrix.Rotation(math.pi / 2, 3, "X"),       # -Y
    "RIGHT": Matrix.Rotation(math.pi / 2, 3, "Y"),      # +X
    "LEFT": Matrix.Rotation(-math.pi / 2, 3, "Y"),      # -X
}
TO_BLENDER = Matrix.Rotation(math.pi / 2, 4, "X")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


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


def _soften(bm, bevel):
    if bevel <= 0.0:
        return
    edges = [e for e in bm.edges if e.calc_face_angle(0.0) > math.radians(25)]
    verts = list({v for e in edges for v in e.verts})
    bmesh.ops.bevel(bm, geom=verts + edges, offset=bevel, segments=2, affect="EDGES", profile=0.5, clamp_overlap=True)


def solid(name, bm, mat, bevel):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    _soften(bm, bevel)
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
    """Spins (radius, distance along axis) points round an axis. Keep the outside on your right."""
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


def dome(name, radius, height, center, axis, mat, segments=24, rings=8):
    """A shallow dome along the axis, like a light's glass shade."""
    profile = [(radius, 0.0)]
    for k in range(1, rings + 1):
        a = (math.pi / 2) * k / rings
        profile.append((max(radius * math.cos(a), 0.0001), height * math.sin(a)))
    return lathe(name, profile, center, axis, mat, segments)


def tube(name, corners, radius, mat, bend=0.01, sides=12):
    """A rod through the corners, with a bend at each one."""
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
        rings.append([bm.verts.new(p + (side * math.cos(math.tau * k / sides) + up * math.sin(math.tau * k / sides)) * radius)
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
    """A flat picture facing +Z."""
    w, h = width / 2, height / 2
    bm = bmesh.new()
    face = bm.faces.new([bm.verts.new((x + center[0], y + center[1], center[2])) for x, y in ((-w, -h), (w, -h), (w, h), (-w, h))])
    uv = bm.loops.layers.uv.new("UVMap")
    for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = co
    return finish(name, bm, mat)


def screw(name, center, mat, slot_mat, radius=0.005, height=0.0035):
    """A slotted pan-head screw facing +Z."""
    head = lathe(name, [(0.0001, 0.0), (radius, 0.0), (radius, height * 0.45), (radius * 0.75, height * 0.9), (0.0001, height)],
            center, "OUT", mat, 16)
    c = Vector(center)
    slot = span(name + "Slot", (c.x - radius * 0.8, c.x + radius * 0.8), (c.y - radius * 0.14, c.y + radius * 0.14),
            (c.z + height * 0.55, c.z + height * 1.02), slot_mat)
    return [head, slot]


def set_origin(obj, pivot):
    obj.data.transform(Matrix.Translation(-Vector(pivot)))
    obj.location = pivot


def join(objs, name, origin=None):
    flat = []
    for o in objs:
        flat.extend(o if isinstance(o, list) else [o])
    bpy.ops.object.select_all(action="DESELECT")
    for o in flat:
        o.select_set(True)
    bpy.context.view_layer.objects.active = flat[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    if origin is not None:
        set_origin(joined, origin)
    return joined


def to_blender_axes(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.matrix_world = TO_BLENDER @ o.matrix_world
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    tris = 0
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
    print("EXPORTED", os.path.basename(path), len(objs), "objects", tris, "tris")


def material(name, color, metal=0.0, rough=0.5, alpha=1.0, image=None, emission=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    if emission is not None:
        p.inputs["Emission Color"].default_value = (*emission, 1.0)
        p.inputs["Emission Strength"].default_value = 1.0
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(ART, image))
        m.node_tree.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m
