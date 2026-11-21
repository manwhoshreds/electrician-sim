"""Exports the owner's smoke detector (art/smoke_detector.blend) for the game.

    blender --background art/smoke_detector.blend --python art/smoke_detector_export.py

Never saves over the .blend. Writes assets/smoke_detector/smoke_detector.glb
with these nodes, each centred on its own origin, the ceiling at z = 0 and +Z
down into the room (as the game's ceiling devices are):

    SmokeBase           the mounting plate that stays on the ceiling
    SmokeDetector       the detector, which twists off the base
    SmokeLED            its indicator lens (the game lights it)
    SmokeHarness        the plug and its three pigtails, up into the box
    SmokeHarnessEnd0-2  where each pigtail's stripped end is (black, white, red),
                        for the wire nuts

The model's colours are its vertex colours; every part shares one plastic
material that uses them, so it draws in a handful of calls instead of 170.
"""
import os

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "smoke_detector", "smoke_detector.glb")


def group(prefix):
    return [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(prefix + "__")]


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), \
        Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def plastic():
    m = bpy.data.materials.new("SmokePlastic")
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.45
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = "Color"
    m.node_tree.links.new(colour.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def merge(objs, name, mat):
    """Joins the parts into one object with the one material, origin left at the world origin."""
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    out = bpy.context.active_object
    out.name = name
    out.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)   # origin at the world's, which is now its centre
    return out


def main():
    mat = plastic()
    made = []
    for prefix, name in (("Base", "SmokeBase"), ("Detector", "SmokeDetector"), ("Harness", "SmokeHarness")):
        parts = group(prefix)
        # The harness is centred on its plug, so the plug sits in the detector's socket.
        lo, hi = bounds([o for o in parts if "three_pin_plug" in o.name] if prefix == "Harness" else parts)
        # Centre it across the ceiling; leave its height as modelled (the ceiling's at y = 0).
        shift = Vector((-(lo.x + hi.x) / 2, 0.0, -(lo.z + hi.z) / 2))
        for o in parts:
            o.matrix_world = o.matrix_world.copy()
            o.location += shift
        bpy.context.view_layer.update()
        ends = []
        if prefix == "Harness":
            for i in range(3):
                end = [o for o in parts if o.name.startswith("Harness__harness_stripped_end_%d" % i)]
                elo, ehi = bounds(end)
                ends.append(Vector(((elo.x + ehi.x) / 2, ehi.y, (elo.z + ehi.z) / 2)))
        if prefix == "Detector":
            led = [o for o in parts if o.name.startswith("Detector__detector_indicator_glass")]
            parts = [o for o in parts if o not in led]
            made.append(merge(led, "SmokeLED", mat))
        whole = merge(parts, name, mat)
        made.append(whole)
        for i, p in enumerate(ends):
            e = bpy.data.objects.new("SmokeHarnessEnd%d" % i, None)
            bpy.context.collection.objects.link(e)
            e.location = p
            made.append(e)
            print("harness end", i, tuple(round(c, 4) for c in p))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in made:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    print("exported", OUT, [o.name for o in made])


main()
