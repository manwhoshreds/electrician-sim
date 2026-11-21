"""Builds the work van you can upgrade to, and exports it.

Run from the project root:
    blender --background --python art/van.py

Writes art/van.blend and assets/van/van.glb. It's laid out in Godot's axes
(metres, origin on the ground under the middle, front toward -Z) so the
numbers match scripts/van.gd. Wheels are the truck's, added by the game.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import *  # noqa: E402,F403

OUT = os.path.join(ROOT, "assets", "van")
FRONT_AXLE = -1.75
REAR_AXLE = 1.55
WHEEL_HUB = (-0.5, 1.55, -1.55)
WHEEL_TILT = -0.6


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


def pane(name, corners, mat):
    bm = bmesh.new()
    bm.faces.new([bm.verts.new(p) for p in corners])
    return finish(name, bm, mat)


def build():
    paint = material("VanWhite", (0.86, 0.87, 0.86), 0.15, 0.22)
    orange = material("Stripe", (1.0, 0.42, 0.04), 0.0, 0.35)
    dark = material("Trim", (0.035, 0.035, 0.04), 0.0, 0.6)
    glass = material("VanGlass", (0.12, 0.15, 0.17), 0.3, 0.05, alpha=0.35)
    alu = material("Rack", (0.7, 0.72, 0.74), 0.9, 0.35)
    seat = material("SeatFabric", (0.12, 0.12, 0.13), 0.0, 0.9)
    parts = []

    # Cargo box and cab, with skirts that leave room for the wheels.
    parts.append(span("Cargo", (-1.0, 1.0), (0.8, 2.45), (-0.8, 2.7), paint, 0.05))
    parts.append(span("CabLower", (-1.0, 1.0), (0.8, 1.3), (-2.0, -0.8), paint, 0.03))
    parts.append(span("Hood", (-0.97, 0.97), (0.65, 1.28), (-2.62, -1.95), paint, 0.07))
    for z in ((-2.62, -2.25), (-1.25, 1.05), (2.05, 2.7)):
        parts.append(span("Skirt", (-1.0, 1.0), (0.45, 0.8), z, paint, 0.025))
    parts.append(span("Chassis", (-0.9, 0.9), (0.42, 0.8), (-2.6, 2.65), dark))

    # The greenhouse: pillars, roof and glass, hollow so you can sit inside.
    for s in (-1, 1):
        parts.append(hexa("APillar", [(s * 0.99, 1.3, -2.0), (s * 0.93, 1.3, -2.0), (s * 0.93, 1.3, -1.9), (s * 0.99, 1.3, -1.9)],
                [(s * 0.96, 2.4, -1.1), (s * 0.9, 2.4, -1.1), (s * 0.9, 2.4, -1.0), (s * 0.96, 2.4, -1.0)], paint))
        parts.append(span("BPillar", sorted((s * 0.92, s * 1.0)), (1.3, 2.45), (-0.9, -0.8), paint))
        parts.append(pane("SideGlass", [(s * 0.99, 1.32, -1.92), (s * 0.99, 1.32, -0.9), (s * 0.965, 2.36, -0.9), (s * 0.965, 2.36, -1.12)], glass))
    parts.append(span("CabRoof", (-0.98, 0.98), (2.37, 2.45), (-1.12, -0.8), paint, 0.02))
    parts.append(pane("Windshield", [(-0.92, 1.34, -2.02), (0.92, 1.34, -2.02), (0.9, 2.36, -1.12), (-0.9, 2.36, -1.12)], glass))
    parts.append(span("Bulkhead", (-0.98, 0.98), (1.3, 2.4), (-0.82, -0.79), dark))

    # Front end.
    parts.append(span("Grille", (-0.6, 0.6), (0.8, 1.16), (-2.645, -2.62), dark, 0.01))
    for i in range(4):
        y = 0.86 + i * 0.08
        parts.append(span("Slat", (-0.58, 0.58), (y - 0.012, y + 0.012), (-2.655, -2.64), alu, 0.003))
    for s in (-1, 1):
        parts.append(span("LampHousing", sorted((s * 0.62, s * 0.95)), (1.0, 1.2), (-2.645, -2.6), dark, 0.01))
        parts.append(span("Mirror", sorted((s * 1.04, s * 1.2)), (1.55, 1.85), (-1.98, -1.9), dark, 0.015))
        parts.append(span("MirrorArm", sorted((s * 0.98, s * 1.06)), (1.62, 1.66), (-1.96, -1.92), dark))
    parts.append(span("BumperFront", (-1.02, 1.02), (0.5, 0.75), (-2.76, -2.6), dark, 0.03))
    parts.append(span("BumperRear", (-1.02, 1.02), (0.5, 0.72), (2.68, 2.82), dark, 0.03))

    # Doors: seams drawn in, rear windows, and the company stripe.
    for s in (-1, 1):
        x = (s * 1.0, s * 1.006)
        for z in (-1.95, -0.85, 0.6):
            parts.append(span("Seam", sorted(x), (0.82, 2.35), (z - 0.006, z + 0.006), dark))
        parts.append(span("StripeCargo", sorted(x), (1.05, 1.2), (-0.8, 2.7), orange))
        parts.append(span("StripeCab", sorted(x), (1.05, 1.2), (-2.0, -0.8), orange))
        parts.append(span("Handle", sorted((s * 1.0, s * 1.02)), (1.38, 1.42), (-1.0, -0.88), dark, 0.005))
        parts.append(pane("RearGlass", [(s * 0.1, 1.75, 2.706), (s * 0.85, 1.75, 2.706), (s * 0.85, 2.25, 2.706), (s * 0.1, 2.25, 2.706)][::s], glass))
    parts.append(span("RearSplit", (-0.006, 0.006), (0.82, 2.4), (2.7, 2.708), dark))
    parts.append(span("StripeRear", (-1.0, 1.0), (1.05, 1.2), (2.7, 2.706), orange))

    # Roof rack and a ladder, because it's an electrician's van.
    for x in (-0.8, 0.8):
        parts.append(span("Rail", (x - 0.03, x + 0.03), (2.52, 2.56), (-0.6, 2.55), alu))
        for z in (-0.4, 1.0, 2.4):
            parts.append(span("Foot", (x - 0.025, x + 0.025), (2.45, 2.53), (z - 0.03, z + 0.03), alu))
    for x in (-0.22, 0.22):
        parts.append(span("LadderSide", (x - 0.025, x + 0.025), (2.57, 2.62), (-0.7, 2.65), alu))
    for k in range(10):
        z = -0.55 + k * 0.33
        parts.append(span("Rung", (-0.22, 0.22), (2.585, 2.605), (z - 0.015, z + 0.015), alu))

    # Inside the cab: enough to sit in.
    parts.append(span("Dash", (-0.95, 0.95), (1.2, 1.45), (-1.97, -1.62), dark, 0.03))
    for x in (-0.5, 0.5):
        parts.append(span("SeatBase", (x - 0.25, x + 0.25), (1.2, 1.38), (-1.2, -0.84), seat, 0.04))
        parts.append(span("SeatBack", (x - 0.25, x + 0.25), (1.38, 2.0), (-0.92, -0.83), seat, 0.04))
    column = lathe("Column", [(0.03, 0.0), (0.03, 0.3)], (0, 0, 0), "BACK", dark, 12)
    column.location = WHEEL_HUB
    column.rotation_euler = (WHEEL_TILT, 0.0, 0.0)
    bpy.context.view_layer.update()
    column.data.transform(column.matrix_world)
    column.matrix_world = Matrix.Identity(4)
    parts.append(column)
    body = join(parts, "VanBody")

    # The steering wheel keeps its own tilt, so the game can turn it round its column.
    rim = lathe("Rim", [(0.17, -0.014), (0.19, 0.0), (0.17, 0.014), (0.155, 0.0), (0.17, -0.014)], (0, 0, 0), "OUT", dark, 36)
    hub = lathe("Hub", [(0.0001, 0.03), (0.05, 0.02), (0.05, -0.01)], (0, 0, 0), "OUT", dark, 16)
    spokes = [span("Spoke", (-0.165, -0.04), (-0.008, 0.008), (-0.006, 0.006), dark),
              span("Spoke", (0.04, 0.165), (-0.008, 0.008), (-0.006, 0.006), dark),
              span("Spoke", (-0.008, 0.008), (-0.165, -0.04), (-0.006, 0.006), dark)]
    wheel = join([rim, hub] + spokes, "SteeringWheel")
    return body, wheel


def main():
    os.makedirs(OUT, exist_ok=True)
    reset()
    body, wheel = build()
    to_blender_axes([body])
    # The wheel's tilt stays on the node rather than in the mesh.
    wheel.matrix_world = TO_BLENDER @ (Matrix.Translation(WHEEL_HUB) @ Matrix.Rotation(WHEEL_TILT, 4, "X"))
    export([body, wheel], os.path.join(OUT, "van.glb"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "van.blend"))


main()
