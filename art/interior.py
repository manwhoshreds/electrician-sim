"""Builds the wiring devices and furniture that go inside a house, and exports them.

Run from the project root:
    blender --background --python art/interior.py

Writes art/interior.blend and assets/interior/interior.glb. Every piece is its
own top-level node, and the game copies them where it needs them:

  Devices, origin on the wall face, +Z out of the wall:
    Receptacle, GFCI, Switch + SwitchToggle (origin at its pivot), RangeOutlet
  Working in a box, origin at the middle of the box opening in the wall face:
    DeviceBox, Duplex, GFCIDevice + GFCITest + GFCIReset, DuplexPlate, DecoraPlate,
    PlateScrew (origin at its own centre), PlugTester + TesterLED1..3,
    RangeDevice + RangePlate (50 A, NEMA 14-50), Strippers (jaws at the origin),
    SwitchDevice + SwitchLever + SwitchPlate, DimmerDevice,
    FixtureCanopy + FixtureBulb + FixtureShade (built along +Z: out of the ceiling),
    ThreeWayDevice, FanBody + FanBlades (spin round Z) + FanGlass, SmokeDetector + SmokeLED
  Light, origin on the ceiling, hanging down -Y:
    CeilingLight + LampShade (the glass, which the game lights up)
  Furniture, origin on the floor against the wall, sticking out along +Z:
    BaseCabinet, SinkCabinet, Fridge, Range + RangeClock, Microwave + MicrowaveClock
    (Microwave and Toaster sit on a counter), Toaster, Couch, TVStand, TV + TVScreen,
    Bed, Nightstand, Toilet, Vanity, Tub
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit import *  # noqa: E402,F403

OUT = os.path.join(ROOT, "assets", "interior")


def materials():
    return {
        "device": material("DeviceWhite", (0.82, 0.81, 0.77), 0.0, 0.32),
        "slot": material("Slot", (0.01, 0.01, 0.01), 0.0, 0.8),
        "brass": material("Brass", (0.75, 0.55, 0.22), 1.0, 0.35),
        "steel": material("Stainless", (0.66, 0.67, 0.68), 1.0, 0.28),
        "black": material("BlackGloss", (0.012, 0.012, 0.014), 0.0, 0.12),
        "dark": material("DarkPlastic", (0.03, 0.03, 0.032), 0.0, 0.45),
        "led": material("LED", (0.01, 0.02, 0.01), 0.0, 0.3),
        "screen": material("Screen", (0.008, 0.008, 0.01), 0.0, 0.08),
        "shade": material("LampGlass", (0.92, 0.9, 0.85), 0.0, 0.4),
        "oak": material("Oak", (0.42, 0.27, 0.15), 0.0, 0.5),
        "walnut": material("Walnut", (0.17, 0.1, 0.06), 0.0, 0.45),
        "granite": material("Granite", (0.07, 0.07, 0.075), 0.0, 0.22),
        "appliance": material("ApplianceWhite", (0.84, 0.84, 0.82), 0.0, 0.2),
        "fabric": material("Fabric", (0.2, 0.26, 0.32), 0.0, 0.95),
        "cushion": material("Cushion", (0.24, 0.3, 0.37), 0.0, 0.95),
        "sheet": material("Sheet", (0.85, 0.84, 0.8), 0.0, 0.9),
        "blanket": material("Blanket", (0.06, 0.1, 0.22), 0.0, 0.95),
        "porcelain": material("Porcelain", (0.88, 0.88, 0.86), 0.0, 0.12),
        "basin": material("BasinShadow", (0.6, 0.6, 0.6), 0.6, 0.25),
        "mirror": material("Mirror", (0.85, 0.86, 0.86), 1.0, 0.03),
        "pvc": material("BlueBox", (0.05, 0.16, 0.5), 0.0, 0.45),
        "yoke": material("Yoke", (0.6, 0.62, 0.64), 0.9, 0.35),
        "silver": material("SilverScrew", (0.78, 0.79, 0.8), 1.0, 0.25),
        "green": material("GreenScrew", (0.08, 0.32, 0.1), 0.6, 0.35),
        "tape": material("LoadTape", (0.85, 0.7, 0.1), 0.0, 0.6),
        "tester": material("TesterYellow", (0.9, 0.62, 0.05), 0.0, 0.4),
        "lens": material("TesterLens", (0.25, 0.22, 0.18), 0.0, 0.2),
        "red": material("RedGrip", (0.6, 0.05, 0.03), 0.0, 0.5),
    }


# --- Wiring devices -----------------------------------------------------------------

def plate(name, m, z=0.005):
    return span(name, (-0.035, 0.035), (-0.0575, 0.0575), (0.0, z), m["device"], 0.0018)


def outlet_face(cy, m, prefix):
    """One half of a duplex: the raised face, two slots and the round ground."""
    parts = [span(prefix + "Face", (-0.0165, 0.0165), (cy - 0.0175, cy + 0.0175), (0.005, 0.0095), m["device"], 0.004)]
    parts.append(span(prefix + "Neutral", (-0.0085, -0.0055), (cy - 0.0005, cy + 0.0105), (0.0093, 0.0097), m["slot"]))
    parts.append(span(prefix + "Hot", (0.0058, 0.0082), (cy + 0.001, cy + 0.0095), (0.0093, 0.0097), m["slot"]))
    parts.append(lathe(prefix + "Ground", [(0.0001, 0.0), (0.0028, 0.0), (0.0028, 0.0004)], (0, cy - 0.008, 0.0093), "OUT", m["slot"], 12))
    return parts


def build_devices(m):
    out = []
    out.append(join([plate("Plate", m)] + outlet_face(0.02, m, "Top") + outlet_face(-0.02, m, "Bottom")
            + screw("PlateScrew", (0, 0, 0.005), m["device"], m["slot"], 0.0035, 0.002), "Receptacle"))

    gfci = [plate("Plate", m), span("Decora", (-0.0165, 0.0165), (-0.033, 0.033), (0.005, 0.0095), m["device"], 0.0025)]
    for cy in (0.021, -0.021):
        gfci.append(span("Neutral", (-0.0085, -0.0055), (cy - 0.005, cy + 0.006), (0.0093, 0.0097), m["slot"]))
        gfci.append(span("Hot", (0.0058, 0.0082), (cy - 0.004, cy + 0.005), (0.0093, 0.0097), m["slot"]))
    gfci.append(span("Test", (-0.012, -0.001), (-0.006, 0.006), (0.0093, 0.0115), m["dark"], 0.0015))
    gfci.append(span("Reset", (0.001, 0.012), (-0.006, 0.006), (0.0093, 0.0115), m["device"], 0.0015))
    out.append(join(gfci, "GFCI"))

    out.append(join([plate("Plate", m), span("Slot", (-0.006, 0.006), (-0.0135, 0.0135), (0.005, 0.0052), m["slot"])]
            + screw("ScrewTop", (0, 0.03, 0.005), m["device"], m["slot"], 0.0035, 0.002)
            + screw("ScrewBottom", (0, -0.03, 0.005), m["device"], m["slot"], 0.0035, 0.002), "Switch"))
    out.append(join([span("Lever", (-0.0045, 0.0045), (-0.004, 0.012), (0.004, 0.016), m["device"], 0.002)], "SwitchToggle", (0, 0, 0.005)))

    rng = [lathe("RangeBody", [(0.052, 0.0), (0.052, 0.03), (0.048, 0.036), (0.0001, 0.036)], (0, 0, 0), "OUT", m["dark"], 32)]
    for x, y, a in ((-0.017, 0.012, 0.5), (0.017, 0.012, -0.5), (0, -0.018, 0.0)):
        slot = span("RangeSlot", (x - 0.002, x + 0.002), (y - 0.008, y + 0.008), (0.0358, 0.0364), m["slot"])
        slot.rotation_euler = (0, 0, a)
        slot.location = (0, 0, 0)
        rng.append(slot)
    out.append(join(rng, "RangeOutlet"))

    light = [lathe("Canopy", [(0.13, 0.0), (0.13, 0.012), (0.115, 0.02), (0.0001, 0.02)], (0, 0, 0), "DOWN", m["device"], 32)]
    out.append(join(light, "CeilingLight"))
    shade = dome("Shade", 0.155, 0.1, (0, -0.02, 0), "DOWN", m["shade"], 32, 10)
    finial = lathe("Finial", [(0.0001, 0.115), (0.012, 0.115), (0.012, 0.128), (0.0001, 0.13)], (0, 0, 0), "DOWN", m["brass"], 12)
    out.append(join([shade, finial], "LampShade"))
    return out


# --- Working in a wall box ------------------------------------------------------
# Origin at the middle of the box's opening in the wall face, +Z out of the wall.
# Kept in step with scripts/box_view.gd.

def side_screw(name, center, axis, mat, radius=0.0034):
    return lathe(name, [(0.0001, 0.0), (radius, 0.0), (radius, 0.0012), (radius * 0.7, 0.0022), (0.0001, 0.0024)], center, axis, mat, 14)


def plate_strips(name, m, holes, w=0.07, h=0.115):
    """A cover plate: the plate with rectangular openings, built from strips."""
    z = (0.0015, 0.0065)
    xs = sorted({-w / 2, w / 2} | {x for hx, hy in holes for x in hx})
    ys = sorted({-h / 2, h / 2} | {y for hx, hy in holes for y in hy})
    parts = []
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx, cy = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
            if any(hx[0] < cx < hx[1] and hy[0] < cy < hy[1] for hx, hy in holes):
                continue
            parts.append(span(name, (xs[i], xs[i + 1]), (ys[j], ys[j + 1]), z, m["device"]))
    # A bevelled edge round the outside so it reads as a plate, not a sheet.
    parts.append(span(name + "Rim", (-w / 2 - 0.001, w / 2 + 0.001), (-h / 2 - 0.001, h / 2 + 0.001), (0.0, 0.0018), m["device"], 0.0009))
    return parts


def device_body(m, half_w, half_h, depth, prefix):
    p = [span(prefix + "Body", (-half_w, half_w), (-half_h, half_h), (-depth, 0.0), m["dark"], 0.002),
         span(prefix + "Yoke", (-0.012, 0.012), (-0.06, 0.06), (0.0, 0.0015), m["yoke"]),
         span(prefix + "Ears", (-0.019, 0.019), (0.05, 0.06), (0.0, 0.0015), m["yoke"]),
         span(prefix + "Ears", (-0.019, 0.019), (-0.06, -0.05), (0.0, 0.0015), m["yoke"])]
    p += screw(prefix + "Ground", (0.0, -0.0545, 0.0015), m["green"], m["slot"], 0.0032, 0.002)
    return p


def build_box_work(m):
    out = []
    # The box in the wall, open at the front.
    bw, bh, bd, t = 0.027, 0.046, 0.065, 0.002
    box = [span("Back", (-bw, bw), (-bh, bh), (-bd, -bd + t), m["pvc"]),
           span("Side", (-bw, -bw + t), (-bh, bh), (-bd, 0.0), m["pvc"]),
           span("Side", (bw - t, bw), (-bh, bh), (-bd, 0.0), m["pvc"]),
           span("Top", (-bw, bw), (bh - t, bh), (-bd, 0.0), m["pvc"]),
           span("Bottom", (-bw, bw), (-bh, -bh + t), (-bd, 0.0), m["pvc"])]
    for y in (0.0417, -0.0417):   # the bosses the device screws go into
        s = 1 if y > 0 else -1
        box.append(span("Boss", (-0.006, 0.006), sorted((s * (bh - t), s * 0.0375)), (-bd, -0.002), m["pvc"]))
    out.append(join(box, "DeviceBox"))

    # Duplex receptacle, its own model so it can come out of the box.
    d = device_body(m, 0.0175, 0.036, 0.032, "D")
    for cy in (0.0195, -0.0195):
        d.append(span("Face", (-0.0165, 0.0165), (cy - 0.0165, cy + 0.0165), (0.0015, 0.0105), m["device"], 0.003))
        d.append(span("Neutral", (-0.0085, -0.0055), (cy - 0.0005, cy + 0.0105), (0.0101, 0.0107), m["slot"]))
        d.append(span("Hot", (0.0058, 0.0082), (cy + 0.001, cy + 0.0095), (0.0101, 0.0107), m["slot"]))
        d.append(lathe("GroundHole", [(0.0001, 0.0), (0.0028, 0.0), (0.0028, 0.0004)], (0, cy - 0.008, 0.0102), "OUT", m["slot"], 12))
        d.append(side_screw("Brass", (0.0175, cy - 0.0015, -0.014), "RIGHT", m["brass"]))
        d.append(side_screw("Silver", (-0.0175, cy - 0.0015, -0.014), "LEFT", m["silver"]))
    for y in (0.0417, -0.0417):
        d += screw("Mount", (0.0, y, 0.0015), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(d, "Duplex"))

    g = device_body(m, 0.021, 0.037, 0.04, "G")
    g.append(span("Face", (-0.0165, 0.0165), (-0.033, 0.033), (0.0015, 0.0105), m["device"], 0.0025))
    for cy in (0.021, -0.021):
        g.append(span("Neutral", (-0.0085, -0.0055), (cy - 0.005, cy + 0.006), (0.0101, 0.0107), m["slot"]))
        g.append(span("Hot", (0.0058, 0.0082), (cy - 0.004, cy + 0.005), (0.0101, 0.0107), m["slot"]))
    for cy, line in ((0.018, True), (-0.018, False)):
        g.append(side_screw("Brass", (0.021, cy, -0.016), "RIGHT", m["brass"]))
        g.append(side_screw("Silver", (-0.021, cy, -0.016), "LEFT", m["silver"]))
        if not line:   # the LOAD screws come taped over
            g.append(span("Tape", (0.0212, 0.0222), (cy - 0.008, cy + 0.008), (-0.03, -0.002), m["tape"]))
            g.append(span("Tape", (-0.0222, -0.0212), (cy - 0.008, cy + 0.008), (-0.03, -0.002), m["tape"]))
    for y in (0.0417, -0.0417):
        g += screw("Mount", (0.0, y, 0.0015), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(g, "GFCIDevice"))
    out.append(join([span("Test", (-0.012, -0.001), (-0.006, 0.006), (0.0101, 0.0125), m["dark"], 0.0015)], "GFCITest"))
    out.append(join([span("Reset", (0.001, 0.012), (-0.006, 0.006), (0.0101, 0.0125), m["device"], 0.0015)], "GFCIReset"))

    # Cover plates. The screws are separate so they can come out one at a time.
    out.append(join(plate_strips("P", m, [((-0.0168, 0.0168), (0.0027, 0.0363)), ((-0.0168, 0.0168), (-0.0363, -0.0027))]), "DuplexPlate"))
    out.append(join(plate_strips("P", m, [((-0.0168, 0.0168), (-0.0338, 0.0338))]), "DecoraPlate"))
    out.append(join(screw("PlateScrew", (0, 0, 0.0065), m["device"], m["slot"], 0.0032, 0.0018), "PlateScrew"))

    # 50 A range receptacle (NEMA 14-50): two hots, a neutral and a ground, big lugs on the sides.
    r = [span("RBody", (-0.03, 0.03), (-0.04, 0.04), (-0.045, 0.0), m["dark"], 0.003),
         span("RYoke", (-0.02, 0.02), (-0.068, 0.068), (0.0, 0.0018), m["yoke"]),
         span("REars", (-0.026, 0.026), (0.056, 0.068), (0.0, 0.0018), m["yoke"]),
         span("REars", (-0.026, 0.026), (-0.068, -0.056), (0.0, 0.0018), m["yoke"]),
         lathe("RFace", [(0.031, 0.0018), (0.031, 0.009), (0.028, 0.0115), (0.0001, 0.0115)], (0, 0, 0), "OUT", m["dark"], 32)]
    for x in (0.012, -0.012):
        r.append(span("RHot", (x - 0.0014, x + 0.0014), (0.002, 0.016), (0.0112, 0.0118), m["slot"]))
    r.append(span("RNeutral", (-0.0055, 0.0055), (-0.0135, -0.0105), (0.0112, 0.0118), m["slot"]))
    r.append(lathe("RGround", [(0.0001, 0.0), (0.0035, 0.0), (0.0035, 0.0006)], (0, 0.022, 0.0112), "OUT", m["slot"], 14))
    for x, y, mat, axis in ((0.03, 0.015, "brass", "RIGHT"), (-0.03, 0.015, "brass", "LEFT"), (-0.03, -0.02, "silver", "LEFT"), (0.03, -0.02, "green", "RIGHT")):
        r.append(span("Lug", sorted((x, x + (0.006 if x > 0 else -0.006))), (y - 0.007, y + 0.007), (-0.03, -0.01), m["silver"], 0.001))
        r.append(side_screw("LugScrew", (x + (0.006 if x > 0 else -0.006), y, -0.02), axis, m[mat], 0.0045))
    for y in (0.06, -0.06):
        r += screw("Mount", (0.0, y, 0.0018), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(r, "RangeDevice"))
    out.append(join(plate_strips("P", m, [((-0.032, 0.032), (-0.032, 0.032))], 0.09, 0.14), "RangePlate"))

    # Single-pole toggle switch: two brass screws on the right side, green on the yoke.
    sw = device_body(m, 0.0165, 0.034, 0.03, "S")
    sw.append(span("Bezel", (-0.0055, 0.0055), (-0.0135, 0.0135), (0.0015, 0.004), m["device"], 0.0015))
    for y in (0.018, -0.018):
        sw.append(side_screw("Brass", (0.0165, y, -0.012), "RIGHT", m["brass"]))
    for y in (0.0417, -0.0417):
        sw += screw("Mount", (0.0, y, 0.0015), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(sw, "SwitchDevice"))
    out.append(join([span("Lever", (-0.0042, 0.0042), (-0.002, 0.014), (0.004, 0.012), m["device"], 0.0018)], "SwitchLever"))
    out.append(join(plate_strips("P", m, [((-0.005, 0.005), (-0.0125, 0.0125))]), "SwitchPlate"))

    # Dimmer: same screws, a paddle and a slider in a decora face.
    dm = device_body(m, 0.02, 0.036, 0.034, "D")
    dm.append(span("Face", (-0.0165, 0.0165), (-0.033, 0.033), (0.0015, 0.008), m["device"], 0.002))
    dm.append(span("Paddle", (-0.0135, 0.004), (-0.03, 0.03), (0.008, 0.0105), m["device"], 0.002))
    dm.append(span("Track", (0.007, 0.0115), (-0.026, 0.026), (0.008, 0.0085), m["slot"]))
    dm.append(span("Slider", (0.006, 0.0125), (0.004, 0.012), (0.008, 0.012), m["device"], 0.001))
    for y in (0.018, -0.018):
        dm.append(side_screw("Brass", (0.02, y, -0.014), "RIGHT", m["brass"]))
    for y in (0.0417, -0.0417):
        dm += screw("Mount", (0.0, y, 0.0015), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(dm, "DimmerDevice"))

    # 3-way switch: a dark common screw and two brass travelers, no ON/OFF on the lever.
    tw = device_body(m, 0.0165, 0.034, 0.03, "T")
    tw.append(span("Bezel", (-0.0055, 0.0055), (-0.0135, 0.0135), (0.0015, 0.004), m["device"], 0.0015))
    tw.append(side_screw("TravA", (0.0165, 0.018, -0.012), "RIGHT", m["brass"]))
    tw.append(side_screw("TravB", (-0.0165, 0.018, -0.012), "LEFT", m["brass"]))
    tw.append(side_screw("Common", (0.0165, -0.018, -0.012), "RIGHT", m["slot"]))
    for y in (0.0417, -0.0417):
        tw += screw("Mount", (0.0, y, 0.0015), m["yoke"], m["slot"], 0.0033, 0.002)
    out.append(join(tw, "ThreeWayDevice"))

    # Ceiling fan, built along +Z: canopy, downrod, motor, a light kit. The blades
    # are their own piece, centred on the shaft, so the game can spin them.
    fan = [lathe("Canopy", [(0.0001, 0.0), (0.085, 0.0), (0.085, 0.01), (0.05, 0.06), (0.0001, 0.06)], (0, 0, 0), "OUT", m["walnut"], 32),
           lathe("Downrod", [(0.012, 0.05), (0.012, 0.22)], (0, 0, 0), "OUT", m["walnut"], 12),
           lathe("Motor", [(0.0001, 0.2), (0.06, 0.2), (0.13, 0.25), (0.13, 0.3), (0.1, 0.34), (0.0001, 0.34)], (0, 0, 0), "OUT", m["walnut"], 40)]
    for x, mat in ((0.03, "black"), (-0.03, "device")):
        lead = m["dark"] if mat == "black" else m["sheet"]
        fan.append(tube("Lead", [(0.0, 0.0, 0.0), (0.0, 0.0, -0.012), (x, 0.015, -0.025), (x, 0.015, -0.03)], 0.0016, lead, 0.008))
        fan.append(lathe("WireNut", [(0.0001, -0.047), (0.004, -0.045), (0.0075, -0.035), (0.0075, -0.028), (0.0001, -0.028)], (x, 0.015, 0), "OUT", m["tape"], 12))
    fan.append(lathe("GroundScrew", [(0.0001, 0.0), (0.004, 0.0), (0.004, -0.003), (0.0001, -0.004)], (0.0, -0.045, 0.0), "OUT", m["green"], 12))
    fan.append(lathe("Bulb", [(0.0001, 0.33), (0.03, 0.345), (0.04, 0.37), (0.0001, 0.39)], (0, 0, 0), "OUT", m["shade"], 20))
    out.append(join(fan, "FanBody"))
    blades = []
    for k in range(5):
        a = math.tau * k / 5
        b = span("Blade", (0.2, 0.68), (-0.065, 0.065), (0.27, 0.278), m["oak"], 0.004)
        iron = span("Iron", (0.1, 0.24), (-0.012, 0.012), (0.27, 0.284), m["brass"], 0.003)
        for o in (b, iron):
            o.data.transform(Matrix.Rotation(a, 4, "Z"))
        blades += [b, iron]
    out.append(join(blades, "FanBlades"))
    out.append(join([dome("Glass", 0.11, 0.08, (0, 0, 0.335), "OUT", m["shade"], 32, 8)], "FanGlass"))

    # Smoke detector, built along +Z out of the ceiling.
    sd = [lathe("Base", [(0.0001, 0.0), (0.075, 0.0), (0.075, 0.006), (0.0001, 0.006)], (0, 0, 0), "OUT", m["device"], 40),
          lathe("Body", [(0.07, 0.006), (0.07, 0.03), (0.06, 0.04), (0.0001, 0.042)], (0, 0, 0), "OUT", m["device"], 40)]
    for k in range(16):
        a = math.tau * k / 16
        v = span("Vent", (0.058, 0.07), (-0.0025, 0.0025), (0.012, 0.028), m["slot"])
        v.data.transform(Matrix.Rotation(a, 4, "Z"))
        sd.append(v)
    sd.append(lathe("TestButton", [(0.0001, 0.042), (0.014, 0.041), (0.014, 0.046), (0.0001, 0.047)], (0, 0, 0), "OUT", m["device"], 20))
    out.append(join(sd, "SmokeDetector"))
    out.append(join([lathe("LED", [(0.0001, 0.036), (0.0035, 0.036), (0.0035, 0.039), (0.0001, 0.0405)], (0.035, 0.0, 0.0), "OUT", m["lens"], 10)], "SmokeLED"))

    # Ceiling fixture, built along +Z (out of the ceiling, so down in the room).
    # The canopy sits against the ceiling; its leads go up into the box to wire nuts.
    fx = [lathe("Canopy", [(0.0001, 0.0), (0.125, 0.0), (0.125, 0.008), (0.11, 0.02), (0.0001, 0.02)], (0, 0, 0), "OUT", m["device"], 40),
          lathe("Socket", [(0.018, 0.02), (0.018, 0.055), (0.0001, 0.055)], (0, 0, 0), "OUT", m["dark"], 20)]
    for x, mat in ((0.03, "black"), (-0.03, "device")):
        lead = m["dark"] if mat == "black" else m["sheet"]
        fx.append(tube("Lead", [(0.0, 0.0, 0.0), (0.0, 0.0, -0.012), (x, 0.015, -0.025), (x, 0.015, -0.03)], 0.0016, lead, 0.008))
        fx.append(lathe("WireNut", [(0.0001, -0.047), (0.004, -0.045), (0.0075, -0.035), (0.0075, -0.028), (0.0001, -0.028)], (x, 0.015, 0), "OUT", m["tape"], 12))
    fx.append(lathe("GroundScrew", [(0.0001, 0.0), (0.004, 0.0), (0.004, -0.003), (0.0001, -0.004)], (0.0, -0.045, 0.0), "OUT", m["green"], 12))
    for y in (0.075, -0.075):
        fx.append(lathe("CanopyNut", [(0.0001, 0.02), (0.006, 0.02), (0.006, 0.026), (0.0001, 0.027)], (0, y, 0), "OUT", m["brass"], 12))
    out.append(join(fx, "FixtureCanopy"))
    out.append(join([lathe("Bulb", [(0.0001, 0.055), (0.02, 0.06), (0.03, 0.085), (0.026, 0.11), (0.0001, 0.12)], (0, 0, 0), "OUT", m["shade"], 20)], "FixtureBulb"))
    shade = [dome("Glass", 0.15, 0.1, (0, 0, 0.02), "OUT", m["shade"], 36, 10),
             lathe("Finial", [(0.0001, 0.115), (0.012, 0.115), (0.012, 0.128), (0.0001, 0.13)], (0, 0, 0.0), "OUT", m["brass"], 12)]
    out.append(join(shade, "FixtureShade"))

    # Attic junction box: a 4" octagon can, its cover, and the three wire nuts
    # the splices sit in once they're pulled out of the box toward you (+Z).
    out.append(join([lathe("Can", [(0.055, 0.0), (0.055, -0.054), (0.0001, -0.054)], (0, 0, 0), "OUT", m["steel"], 8)], "JBoxCan"))
    cover = [lathe("Cover", [(0.0001, 0.0), (0.06, 0.0), (0.06, 0.004), (0.0001, 0.004)], (0, 0, 0), "OUT", m["steel"], 8)]
    out.append(join(cover, "JBoxCover"))
    nuts = []
    for x, mat in ((0.022, "tape"), (-0.022, "tape"), (0.0, "green")):
        nuts.append(lathe("Nut", [(0.0001, 0.05), (0.004, 0.048), (0.0075, 0.038), (0.0075, 0.031), (0.0001, 0.031)], (x, 0.01, 0), "OUT", m[mat], 12))
    out.append(join(nuts, "JBoxNuts"))

    # Wire strippers: jaws at the origin, handles back along +Y.
    st = [span("Jaw", (-0.006, 0.006), (0.0, 0.05), (-0.003, 0.003), m["steel"], 0.001),
          tube("Pivot", [(0, 0.05, -0.004), (0, 0.05, 0.004)], 0.004, m["steel"])]
    for x in (-0.01, 0.01):
        st.append(tube("Handle", [(x * 0.5, 0.055, 0.0), (x, 0.09, 0.0), (x * 1.4, 0.16, 0.0)], 0.007, m["red"] if "red" in m else m["dark"], 0.02))
    out.append(join(st, "Strippers"))

    # Plug-in tester, prongs toward -Z.
    t = [span("Body", (-0.022, 0.022), (-0.03, 0.03), (0.0, 0.034), m["tester"], 0.006)]
    for x in (-0.006, 0.006):
        t.append(span("Prong", (x - 0.0008, x + 0.0008), (0.0, 0.009), (-0.014, 0.0), m["silver"]))
    t.append(tube("GroundPin", [(0, -0.015, 0.0), (0, -0.015, -0.014)], 0.0018, m["silver"]))
    out.append(join(t, "PlugTester"))
    for i, x in enumerate((-0.012, 0.0, 0.012)):
        out.append(join([lathe("LED", [(0.0035, 0.0), (0.0035, 0.002), (0.0001, 0.0035)], (x, 0.012, 0.034), "OUT", m["lens"], 12)], "TesterLED%d" % (i + 1)))
    return out


# --- Furniture ------------------------------------------------------------------

def cabinet_parts(m, prefix=""):
    p = [span(prefix + "Carcass", (-0.3, 0.3), (0.1, 0.88), (0.0, 0.58), m["oak"], 0.003),
         span(prefix + "ToeKick", (-0.29, 0.29), (0.0, 0.1), (0.0, 0.52), m["dark"])]
    for x in ((-0.296, -0.003), (0.003, 0.296)):
        p.append(span(prefix + "Door", x, (0.11, 0.7), (0.58, 0.6), m["oak"], 0.004))
        p.append(span(prefix + "Panel", (x[0] + 0.04, x[1] - 0.04), (0.17, 0.64), (0.6, 0.604), m["oak"], 0.002))
    p.append(span(prefix + "Drawer", (-0.296, 0.296), (0.715, 0.865), (0.58, 0.6), m["oak"], 0.004))
    for x in (-0.03, 0.03):
        p.append(tube(prefix + "Knob", [(x, 0.65, 0.6), (x, 0.65, 0.622)], 0.006, m["steel"]))
    p.append(tube(prefix + "Pull", [(-0.06, 0.79, 0.6), (-0.06, 0.79, 0.618), (0.06, 0.79, 0.618), (0.06, 0.79, 0.6)], 0.004, m["steel"], 0.006))
    p.append(span(prefix + "Top", (-0.302, 0.302), (0.88, 0.915), (0.0, 0.635), m["granite"], 0.004))
    return p


def build_furniture(m):
    out = [join(cabinet_parts(m), "BaseCabinet")]

    sink = cabinet_parts(m, "S")
    sink.append(span("Basin", (-0.23, 0.23), (0.915, 0.92), (0.07, 0.47), m["steel"], 0.006))
    sink.append(span("BasinWell", (-0.21, 0.21), (0.9152, 0.9208), (0.09, 0.45), m["basin"], 0.004))
    sink.append(span("Drain", (-0.02, 0.02), (0.9205, 0.9212), (0.25, 0.29), m["dark"]))
    sink.append(tube("Faucet", [(0, 0.915, 0.04), (0, 1.2, 0.04), (0, 1.2, 0.22), (0, 1.12, 0.22)], 0.011, m["steel"], 0.06))
    sink.append(tube("Handle", [(0.07, 0.94, 0.04), (0.07, 0.94, 0.08)], 0.008, m["steel"]))
    out.append(join(sink, "SinkCabinet"))

    fridge = [span("Body", (-0.45, 0.45), (0.0, 1.78), (0.0, 0.7), m["steel"], 0.02),
              span("Kick", (-0.43, 0.43), (0.01, 0.08), (0.69, 0.705), m["dark"]),
              span("Freezer", (-0.445, 0.445), (0.1, 0.62), (0.7, 0.75), m["steel"], 0.01)]
    for x in ((-0.445, -0.003), (0.003, 0.445)):
        fridge.append(span("Door", x, (0.64, 1.775), (0.7, 0.75), m["steel"], 0.01))
    for x in (-0.03, 0.03):
        fridge.append(tube("Handle", [(x, 0.85, 0.75), (x, 0.85, 0.79), (x, 1.5, 0.79), (x, 1.5, 0.75)], 0.009, m["steel"], 0.02))
    fridge.append(tube("FreezerHandle", [(-0.3, 0.55, 0.75), (-0.3, 0.55, 0.785), (0.3, 0.55, 0.785), (0.3, 0.55, 0.75)], 0.009, m["steel"], 0.02))
    out.append(join(fridge, "Fridge"))

    rng = [span("Body", (-0.38, 0.38), (0.0, 0.9), (0.0, 0.63), m["steel"], 0.006),
           span("OvenDoor", (-0.37, 0.37), (0.09, 0.74), (0.63, 0.66), m["steel"], 0.008),
           span("OvenWindow", (-0.25, 0.25), (0.28, 0.6), (0.66, 0.662), m["black"]),
           span("Drawer", (-0.37, 0.37), (0.01, 0.08), (0.63, 0.65), m["dark"]),
           tube("Handle", [(-0.3, 0.7, 0.66), (-0.3, 0.7, 0.69), (0.3, 0.7, 0.69), (0.3, 0.7, 0.66)], 0.01, m["steel"], 0.02),
           span("Cooktop", (-0.38, 0.38), (0.9, 0.915), (0.0, 0.64), m["black"], 0.004),
           span("Backguard", (-0.38, 0.38), (0.915, 1.12), (0.0, 0.07), m["steel"], 0.006)]
    for x, z, r in ((-0.18, 0.2, 0.08), (0.18, 0.2, 0.07), (-0.18, 0.46, 0.07), (0.18, 0.46, 0.09)):
        for k in range(3):
            rr = r * (1.0 - k * 0.3)
            rng.append(lathe("Coil", [(rr, -0.004), (rr + 0.006, 0.0), (rr, 0.004), (rr - 0.006, 0.0), (rr, -0.004)], (x, 0.918, z), "UP", m["dark"], 28))
    for x in (-0.3, -0.18, 0.18, 0.3):
        rng.append(lathe("Knob", [(0.018, 0.0), (0.018, 0.014), (0.0001, 0.018)], (x, 1.01, 0.07), "OUT", m["dark"], 16))
    out.append(join(rng, "Range"))
    out.append(join([span("Clock", (-0.05, 0.05), (0.99, 1.03), (0.0702, 0.0712), m["led"])], "RangeClock"))

    mw = [span("Body", (-0.25, 0.25), (0.0, 0.29), (0.0, 0.37), m["black"], 0.01),
          span("Window", (-0.235, 0.1), (0.03, 0.26), (0.37, 0.374), m["screen"]),
          span("Keypad", (0.115, 0.235), (0.03, 0.2), (0.37, 0.374), m["dark"]),
          tube("Handle", [(0.105, 0.04, 0.37), (0.105, 0.04, 0.39), (0.105, 0.25, 0.39), (0.105, 0.25, 0.37)], 0.007, m["steel"], 0.01)]
    out.append(join(mw, "Microwave"))
    out.append(join([span("Clock", (0.13, 0.22), (0.215, 0.255), (0.3742, 0.3752), m["led"])], "MicrowaveClock"))

    toaster = [span("Body", (-0.14, 0.14), (0.0, 0.19), (0.0, 0.17), m["steel"], 0.03)]
    for x in (-0.05, 0.05):
        toaster.append(span("Slot", (x - 0.02, x + 0.02), (0.188, 0.192), (0.025, 0.145), m["slot"]))
    toaster.append(span("Lever", (0.14, 0.16), (0.12, 0.135), (0.07, 0.1), m["dark"], 0.003))
    out.append(join(toaster, "Toaster"))

    couch = [span("Base", (-1.0, 1.0), (0.1, 0.42), (0.0, 0.9), m["fabric"], 0.03),
             span("Back", (-1.0, 1.0), (0.42, 0.88), (0.0, 0.24), m["fabric"], 0.05)]
    for s in (-1, 1):
        couch.append(span("Arm", sorted((s * 0.86, s * 1.0)), (0.1, 0.66), (0.0, 0.9), m["fabric"], 0.04))
        for z in (0.06, 0.82):
            couch.append(span("Leg", sorted((s * 0.92, s * 0.96)), (0.0, 0.1), (z, z + 0.04), m["walnut"]))
    for i in range(3):
        x0 = -0.86 + i * 0.5733
        couch.append(span("Seat", (x0 + 0.005, x0 + 0.568), (0.42, 0.55), (0.24, 0.88), m["cushion"], 0.045))
        couch.append(span("BackCushion", (x0 + 0.005, x0 + 0.568), (0.5, 0.86), (0.2, 0.36), m["cushion"], 0.05))
    out.append(join(couch, "Couch"))

    out.append(join([span("Cabinet", (-0.65, 0.65), (0.05, 0.5), (0.0, 0.42), m["walnut"], 0.008),
                     span("Shelf", (-0.62, 0.62), (0.22, 0.24), (0.02, 0.43), m["walnut"])], "TVStand"))
    tv = [span("Bezel", (-0.58, 0.58), (0.58, 1.25), (0.14, 0.19), m["black"], 0.006),
          span("Foot", (-0.18, 0.18), (0.5, 0.515), (0.08, 0.3), m["black"], 0.004),
          span("Neck", (-0.03, 0.03), (0.51, 0.6), (0.15, 0.17), m["black"])]
    out.append(join(tv, "TV"))
    out.append(join([span("Glass", (-0.565, 0.565), (0.595, 1.235), (0.1902, 0.1912), m["screen"])], "TVScreen"))

    bed = [span("Headboard", (-0.86, 0.86), (0.0, 1.1), (0.0, 0.06), m["walnut"], 0.01),
           span("Frame", (-0.82, 0.82), (0.1, 0.33), (0.06, 2.12), m["walnut"], 0.01),
           span("Mattress", (-0.8, 0.8), (0.33, 0.58), (0.08, 2.1), m["sheet"], 0.05),
           span("Blanket", (-0.83, 0.83), (0.5, 0.62), (0.75, 2.13), m["blanket"], 0.04)]
    for x in (-0.4, 0.4):
        bed.append(span("Pillow", (x - 0.33, x + 0.33), (0.58, 0.71), (0.12, 0.48), m["sheet"], 0.055))
    out.append(join(bed, "Bed"))
    out.append(join([span("Box", (-0.24, 0.24), (0.0, 0.55), (0.0, 0.4), m["walnut"], 0.008),
                     span("Drawer", (-0.21, 0.21), (0.36, 0.5), (0.4, 0.415), m["walnut"], 0.004),
                     tube("Knob", [(0, 0.43, 0.415), (0, 0.43, 0.43)], 0.008, m["brass"])], "Nightstand"))

    toilet = [span("Tank", (-0.2, 0.2), (0.42, 0.78), (0.0, 0.2), m["porcelain"], 0.02),
              span("Lid", (-0.21, 0.21), (0.78, 0.81), (0.0, 0.21), m["porcelain"], 0.012),
              lathe("Bowl", [(0.11, 0.0), (0.13, 0.15), (0.19, 0.38), (0.0001, 0.38)], (0, 0, 0.44), "UP", m["porcelain"], 28),
              lathe("Seat", [(0.18, 0.38), (0.19, 0.4), (0.12, 0.4), (0.12, 0.38)], (0, 0, 0.44), "UP", m["porcelain"], 28),
              span("Neck", (-0.12, 0.12), (0.0, 0.38), (0.15, 0.32), m["porcelain"], 0.03),
              span("Flush", (-0.16, -0.12), (0.72, 0.74), (0.2, 0.22), m["steel"])]
    out.append(join(toilet, "Toilet"))

    vanity = [span("Cabinet", (-0.4, 0.4), (0.08, 0.82), (0.0, 0.5), m["appliance"], 0.006),
              span("Kick", (-0.38, 0.38), (0.0, 0.08), (0.0, 0.46), m["dark"]),
              span("Top", (-0.41, 0.41), (0.82, 0.85), (0.0, 0.53), m["porcelain"], 0.006),
              span("Bowl", (-0.2, 0.2), (0.8505, 0.852), (0.12, 0.4), m["basin"], 0.02),
              tube("Faucet", [(0, 0.85, 0.06), (0, 0.97, 0.06), (0, 0.97, 0.15)], 0.009, m["steel"], 0.03),
              span("Mirror", (-0.35, 0.35), (1.0, 1.75), (0.0, 0.015), m["mirror"], 0.004)]
    for x in ((-0.395, -0.003), (0.003, 0.395)):
        vanity.append(span("Door", x, (0.1, 0.78), (0.5, 0.52), m["appliance"], 0.004))
    out.append(join(vanity, "Vanity"))

    out.append(join([span("Shell", (-0.75, 0.75), (0.0, 0.56), (0.0, 0.76), m["porcelain"], 0.03),
                     span("Water", (-0.66, 0.66), (0.25, 0.561), (0.07, 0.69), m["basin"], 0.05),
                     tube("Spout", [(-0.62, 0.62, 0.38), (-0.68, 0.62, 0.38)], 0.012, m["steel"])], "Tub"))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    reset()
    m = materials()
    parts = build_devices(m) + build_box_work(m) + build_furniture(m)
    to_blender_axes(parts)
    export(parts, os.path.join(OUT, "interior.glb"))
    # Spread them out so they can be looked at in the .blend.
    for i, o in enumerate(parts):
        o.location.x += (i % 8) * 2.5
        o.location.y += (i // 8) * 2.5
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "interior.blend"))


main()
