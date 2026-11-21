"""Build a beige, ribbed twist-on wire connector (wire nut).

Run from the repository root:
    blender --background --python art/wire_nut.py

Writes art/wire_nut.blend and assets/wire_nut/wire_nut.glb. Dimensions are
based on the supplied reference: 30 mm tall and 20 mm maximum diameter.
The connector stands on its open end, centered at the world origin.
"""
import math
import os

import bpy
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "wire_nut")
BLEND_PATH = os.path.join(ROOT, "art", "wire_nut.blend")
GLB_PATH = os.path.join(OUT_DIR, "wire_nut.glb")


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(name, color, metallic=0.0, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def shell_mesh(mat):
    """Hollow molded shell: outer skin, deep inner cavity, and bottom lip."""
    segments = 64
    # Soft shoulder, tapered cap, and a subtly flattened crown.
    outer = [(0.0000, 0.0096), (0.0012, 0.0100), (0.0040, 0.0101),
             (0.0205, 0.0080), (0.0257, 0.0062), (0.0290, 0.0036),
             (0.0300, 0.0017)]
    # Cavity narrows deeply; the last ring is capped to represent molded plastic.
    inner = [(0.0000, 0.00735), (0.0012, 0.00725), (0.0050, 0.0068),
             (0.0150, 0.0050), (0.0228, 0.00255)]
    verts, faces = [], []

    def add_ring(z, radius):
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            ring.append(len(verts))
            verts.append((radius * math.cos(a), radius * math.sin(a), z))
        return ring

    def bridge(a, b, reverse=False):
        for i in range(segments):
            q = (a[i], a[(i + 1) % segments], b[(i + 1) % segments], b[i])
            faces.append(tuple(reversed(q)) if reverse else q)

    outer_rings = [add_ring(z, r) for z, r in outer]
    for a, b in zip(outer_rings, outer_rings[1:]):
        bridge(a, b)
    top = len(verts)
    verts.append((0.0, 0.0, 0.03015))
    for i in range(segments):
        faces.append((outer_rings[-1][i], outer_rings[-1][(i + 1) % segments], top))

    inner_rings = [add_ring(z, r) for z, r in inner]
    for a, b in zip(inner_rings, inner_rings[1:]):
        bridge(a, b, reverse=True)
    cavity_top = len(verts)
    verts.append((0.0, 0.0, inner[-1][0] + 0.0007))
    for i in range(segments):
        faces.append((inner_rings[-1][(i + 1) % segments], inner_rings[-1][i], cavity_top))
    bridge(inner_rings[0], outer_rings[0], reverse=True)

    mesh = bpy.data.meshes.new("WireNutShellMesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new("WireNutShell", mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    bevel = obj.modifiers.new("Molded edge softness", "BEVEL")
    bevel.width = 0.00018
    bevel.segments = 2
    bevel.affect = "EDGES"
    bevel.limit_method = "ANGLE"
    return obj


def grip_rib(index, count, mat):
    """One broad tapered gripping flute, made as a faceted radial wedge."""
    a = math.tau * index / count
    da = math.radians(5.3)
    levels = [(0.0028, 0.0099, 0.0011), (0.0060, 0.01025, 0.00125),
              (0.0203, 0.0080, 0.0010), (0.0253, 0.00625, 0.00045)]
    verts = []
    for z, base_r, height in levels:
        for angle, r in ((a - da, base_r), (a + da, base_r),
                         (a + da * 0.70, base_r + height), (a - da * 0.70, base_r + height)):
            verts.append((r * math.cos(angle), r * math.sin(angle), z))
    faces = []
    for j in range(len(levels) - 1):
        p, q = j * 4, (j + 1) * 4
        for k in range(4):
            faces.append((p + k, p + (k + 1) % 4, q + (k + 1) % 4, q + k))
    faces += [(0, 1, 2, 3), tuple(range((len(levels) - 1) * 4, len(levels) * 4))]
    mesh = bpy.data.meshes.new("GripRibMesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("GripRib_%02d" % (index + 1), mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Rounded molded rib", "BEVEL")
    bevel.width = 0.00025
    bevel.segments = 2
    return obj


def helix(name, mat):
    """Tapered zinc spring insert visible through the open mouth."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.resolution_v = 2
    curve.bevel_depth = 0.00034
    curve.bevel_resolution = 2
    turns, points = 6.0, 150
    spline = curve.splines.new("POLY")
    spline.points.add(points - 1)
    for i, point in enumerate(spline.points):
        t = i / (points - 1)
        z = 0.0024 + t * 0.0174
        radius = 0.0060 * (1.0 - t) + 0.0027 * t
        angle = math.tau * turns * t
        point.co = (radius * math.cos(angle), radius * math.sin(angle), z, 1.0)
    curve.materials.append(mat)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    reset()
    plastic = material("WarmIvoryNylon", (0.69, 0.59, 0.43), 0.0, 0.48)
    metal = material("ZincSpring", (0.47, 0.49, 0.47), 0.82, 0.25)
    dark = material("CavityShadow", (0.055, 0.040, 0.024), 0.0, 0.8)

    root = bpy.data.objects.new("WireNut", None)
    bpy.context.collection.objects.link(root)
    parts = [shell_mesh(plastic)]
    parts += [grip_rib(i, 10, plastic) for i in range(10)]
    parts.append(helix("InternalSpring", metal))

    # A recessed dark cap makes the cavity read as deep without closing its mouth.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=12,
                                        location=(0, 0, 0.0218), scale=(0.0023, 0.0023, 0.0011))
    cap = bpy.context.object
    cap.name = "CavityEnd"
    cap.data.materials.append(dark)
    parts.append(cap)
    for obj in parts:
        obj.parent = root

    # Metric scene and useful asset metadata.
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.length_unit = "MILLIMETERS"
    root["real_height_mm"] = 30.0
    root["maximum_diameter_mm"] = 20.5
    root["reference_type"] = "UL-style twist-on wire connector"
    return root


def save_and_export(root):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB",
                              use_selection=True, export_apply=True)


if __name__ == "__main__":
    connector = build()
    save_and_export(connector)
    print("Created", BLEND_PATH)
    print("Created", GLB_PATH)
