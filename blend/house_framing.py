"""Slab-on-grade house: concrete slab, footing, patio and porch slabs, and every
board of the wall framing as its own object.

Plan: 32'-0" x 28'-0" two-bedroom, one-bath ranch (from the floor plan drawing).
The plan is plain data below (PLAN_*), in FEET, measured from the OUTSIDE of the
north-west corner, x running east and y running SOUTH (down the drawing). The
generator turns it into framing using standard practice:

  * 2x4 walls (1-1/2" x 3-1/2"), studs 16" on centre, 92-5/8" precuts (8' walls)
  * pressure-treated bottom plate on the slab, double top plate
  * rough openings 82-1/2" to the head; king + jack studs, built-up headers
    (2x10 outside, 2x6 inside) and cripples above; rough sill + cripples below
  * three-stud corners and T-backers wherever one wall meets another
  * 4" slab with a thickened 12" x 12" footing round the edge

World: metres, Blender Z up, plan x -> world +X, plan y -> world -Y, slab top at Z = 0.
Every number is a knob. Safe to re-run: the House collection is rebuilt.

    blender --background --python blend/house_framing.py
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

FT = 0.3048
IN = 0.0254

# --- Plan (feet) ---------------------------------------------------------------------
HOUSE_W, HOUSE_D = 32.0, 28.0           # outside of framing, east-west x north-south
WALL_T = 3.5 / 12                        # 2x4 wall

# Exterior openings: (from, to) along the wall in feet, kind, rough-sill height (in).
# North and south walls run west -> east (x); west and east walls run north -> south (y).
EXT_OPENINGS = {
    'North': [(2.0, 6.0, 'window', 42.0),          # kitchen, over the sink
              (8.6, 13.2, 'door', 0.0),            # patio slider
              (21.8, 26.5, 'window', 36.0)],       # bedroom 2
    'South': [(3.1, 7.1, 'window', 36.0),          # living
              (10.3, 13.3, 'door', 0.0),           # front door
              (21.8, 26.5, 'window', 36.0)],       # bedroom 1
    'West':  [(11.6, 14.6, 'window', 36.0)],       # living
    'East':  [(12.9, 15.4, 'window', 54.0)],       # bath, high for privacy
}

# Interior partitions: name, runs along ('x' or 'y'), face (the wall's low-side face,
# feet), from, to, openings [(from, to, kind, sill)].
PARTITIONS = [
    ('P1_Kitchen_Living', 'y', 14.05, WALL_T, HOUSE_D - WALL_T, [(11.85, 16.15, 'door', 0.0)]),   # cased opening to hall
    ('P2_Closet2_WH', 'y', 17.33, WALL_T, 11.25, [(1.0, 6.0, 'door', 0.0)]),                     # closet 2 bifold
    ('P3_WD_Closet1', 'y', 17.33, 16.75, HOUSE_D - WALL_T, [(21.9, 25.9, 'door', 0.0)]),         # closet 1 bifold
    ('P4_Closet2_WH', 'x', 7.65, 14.05 + WALL_T, 17.33, []),
    ('P5_Bed2_Bath', 'x', 11.25, 14.05 + WALL_T, HOUSE_W - WALL_T,
     [(14.6, 17.1, 'door', 0.0), (17.9, 20.7, 'door', 0.0)]),                                    # WH bifold, bedroom 2
    ('P6_Bed1_Bath', 'x', 16.46, 14.05 + WALL_T, HOUSE_W - WALL_T,
     [(14.6, 17.1, 'door', 0.0), (17.9, 20.7, 'door', 0.0)]),                                    # W/D bifold, bedroom 1
    ('P7_WD_Closet1', 'x', 20.1, 14.05 + WALL_T, 17.33, []),
    ('P8_Bath', 'y', 20.85, 11.25 + WALL_T, 16.46, [(13.4, 16.1, 'door', 0.0)]),                 # bath door
]

# Patio and porch slabs (feet): x from, x to, y from, y to.
PATIO = (0.0, 14.583, -6.0, 0.0)
PORCH = (2.0, 14.667, HOUSE_D, HOUSE_D + 6.0)

# --- Framing (inches) -----------------------------------------------------------------
STUD_T, STUD_W = 1.5, 3.5               # 2x4 actual
STUD_OC = 16.0
PLATE_T = 1.5
STUD_LEN = 92.625                        # precut, for an 8'-1 1/8" wall
RO_HEAD = 82.5                           # rough-opening head height above the slab
EXT_HEADER = 9.25                        # 2x10
INT_HEADER = 5.5                         # 2x6
HEADER_SPACER = 0.5                      # plywood between the two header plies
LUMBER_EASE = 0.125                      # rounded edges on every board

# --- Slab (inches) ----------------------------------------------------------------------
SLAB_T = 4.0
FOOTING = (12.0, 12.0)                   # thickened edge: width, depth below the slab
EXT_SLAB_T = 4.0
EXT_SLAB_DROP = 1.5                      # patio and porch sit this far below the house slab

COLLECTION_NAME = 'House'

# --- Setup -------------------------------------------------------------------------------
scene = bpy.context.scene
scene.unit_settings.system = 'IMPERIAL'
scene.unit_settings.length_unit = 'FEET'


def clear_collection(name):
    col = bpy.data.collections.get(name)
    if not col:
        return
    for child in list(col.children_recursive):
        for obj in list(child.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(child)
    for obj in list(col.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(col)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


clear_collection(COLLECTION_NAME)
house = bpy.data.collections.new(COLLECTION_NAME)
scene.collection.children.link(house)


def sub_collection(name, parent=house):
    col = bpy.data.collections.new(name)
    parent.children.link(col)
    return col


# --- Materials -----------------------------------------------------------------------------

def _new_material(name, base):
    mat = bpy.data.materials.get(name)
    if mat:
        bpy.data.materials.remove(mat)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*base, 1)
    mat.use_nodes = True
    return mat, mat.node_tree, mat.node_tree.nodes['Principled BSDF']


WOOD_TONES = {   # light and dark grain tones
    'Lumber': ((0.78, 0.60, 0.38), (0.56, 0.38, 0.20)),            # SPF stud grade
    'PT_Lumber': ((0.55, 0.56, 0.36), (0.38, 0.40, 0.24)),         # pressure treated (green)
    'Plywood': ((0.74, 0.58, 0.36), (0.54, 0.38, 0.20)),
}
WOOD_RING_SCALE = 120.0         # growth-ring density (higher = tighter grain lines)
WOOD_DISTORTION = 2.5           # waviness of the grain
WOOD_STRETCH = 0.06             # squashes the waviness along the board, so grain runs long and straight


def wood_material(name):
    light, dark = WOOD_TONES[name]
    mat, nt, bsdf = _new_material(name, light)
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    info = nt.nodes.new('ShaderNodeObjectInfo')
    jitter = nt.nodes.new('ShaderNodeVectorMath')       # each board's rings centred somewhere different
    jitter.operation = 'MULTIPLY'
    jitter.inputs[1].default_value = (0.37, 0.53, 1.7)
    offset = nt.nodes.new('ShaderNodeVectorMath')
    offset.operation = 'ADD'
    stretch = nt.nodes.new('ShaderNodeVectorMath')
    stretch.operation = 'MULTIPLY'
    stretch.inputs[1].default_value = (1.0, 1.0, WOOD_STRETCH)
    wave = nt.nodes.new('ShaderNodeTexWave')            # rings round the board's length = grain lines on its faces
    wave.wave_type = 'RINGS'
    wave.rings_direction = 'Z'
    wave.inputs['Scale'].default_value = WOOD_RING_SCALE
    wave.inputs['Distortion'].default_value = WOOD_DISTORTION
    wave.inputs['Detail'].default_value = 3
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].color = (*light, 1)
    ramp.color_ramp.elements[0].position = 0.15
    ramp.color_ramp.elements[1].position = 0.65
    tint = nt.nodes.new('ShaderNodeMix')                # board-to-board tone variation
    tint.data_type = 'RGBA'
    tint.blend_type = 'MULTIPLY'
    tint_val = nt.nodes.new('ShaderNodeMapRange')
    tint_val.inputs['To Min'].default_value = 0.85
    tint_val.inputs['To Max'].default_value = 1.05
    comb = nt.nodes.new('ShaderNodeCombineColor')
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.08
    bump.inputs['Distance'].default_value = 0.0005
    L(info.outputs['Random'], jitter.inputs[0])
    L(coord.outputs['Object'], offset.inputs[0])
    L(jitter.outputs['Vector'], offset.inputs[1])
    L(offset.outputs['Vector'], stretch.inputs[0])
    L(stretch.outputs['Vector'], wave.inputs['Vector'])
    L(wave.outputs['Fac'], ramp.inputs['Fac'])
    L(info.outputs['Random'], tint_val.inputs['Value'])
    for ch in ('Red', 'Green', 'Blue'):
        L(tint_val.outputs['Result'], comb.inputs[ch])
    tint.inputs['Factor'].default_value = 1.0
    col_in = [sk for sk in tint.inputs if sk.type == 'RGBA']           # the colour A and B sockets
    col_out = next(sk for sk in tint.outputs if sk.type == 'RGBA')
    L(ramp.outputs['Color'], col_in[0])
    L(comb.outputs['Color'], col_in[1])
    L(col_out, bsdf.inputs['Base Color'])
    L(wave.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.62
    return mat


CONCRETE_TONES = ((0.50, 0.50, 0.48), (0.70, 0.69, 0.66))


def concrete_material(name='Concrete'):
    mat, nt, bsdf = _new_material(name, CONCRETE_TONES[1])
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    blotch = nt.nodes.new('ShaderNodeTexNoise')
    blotch.inputs['Scale'].default_value = 3.0
    blotch.inputs['Detail'].default_value = 6
    fine = nt.nodes.new('ShaderNodeTexNoise')
    fine.inputs['Scale'].default_value = 400.0
    fine.inputs['Detail'].default_value = 4
    mix = nt.nodes.new('ShaderNodeMath')
    mix.operation = 'MULTIPLY_ADD'
    mix.inputs[1].default_value = 0.3
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*CONCRETE_TONES[0], 1)
    ramp.color_ramp.elements[1].color = (*CONCRETE_TONES[1], 1)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.75
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.25
    bump.inputs['Distance'].default_value = 0.0008
    L(coord.outputs['Object'], blotch.inputs['Vector'])
    L(coord.outputs['Object'], fine.inputs['Vector'])
    L(fine.outputs['Fac'], mix.inputs[0])
    L(blotch.outputs['Fac'], mix.inputs[2])
    L(mix.outputs['Value'], ramp.inputs['Fac'])
    L(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    L(fine.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.88
    return mat


MATS = {'lumber': wood_material('Lumber'), 'pt': wood_material('PT_Lumber'),
        'ply': wood_material('Plywood'), 'concrete': concrete_material()}


# --- Boards -----------------------------------------------------------------------------------
# Each board is built along its own +Z (so the grain follows its length) and turned into
# place; boards of the same size share one mesh.
_mesh_cache = {}
ROT = {'z': Matrix.Identity(3), 'x': Matrix.Rotation(math.pi / 2, 3, 'Y'), 'y': Matrix.Rotation(-math.pi / 2, 3, 'X')}


def board_mesh(lx, ly, lz):
    key = (round(lx, 4), round(ly, 4), round(lz, 4))
    if key in _mesh_cache:
        return _mesh_cache[key]
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(lx * IN, ly * IN, lz * IN), verts=bm.verts)
    ease = min(LUMBER_EASE, lx / 4, ly / 4, lz / 4)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=ease * IN, segments=2, affect='EDGES', profile=0.5)
    mesh = bpy.data.meshes.new('Board_%gx%gx%g' % key)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    _mesh_cache[key] = mesh
    return mesh


def board(name, col, size, center, long_axis, mat):
    """size = world (x, y, z) extents in inches; center in inches (world axes)."""
    sx, sy, sz = size
    local = {'z': (sx, sy, sz), 'x': (sz, sy, sx), 'y': (sx, sz, sy)}[long_axis]
    mesh = board_mesh(*local)
    if not mesh.materials:
        mesh.materials.append(MATS[mat])
    elif mesh.materials[0] != MATS[mat]:     # same size, different stock: separate mesh
        mesh = mesh.copy()
        mesh.materials[0] = MATS[mat]
    obj = bpy.data.objects.new(name, mesh)
    obj.matrix_world = Matrix.Translation(Vector(center) * IN) @ ROT[long_axis].to_4x4()
    col.objects.link(obj)
    return obj


# --- Walls -----------------------------------------------------------------------------------

class Wall:
    """A straight 2x4 wall. axis 'x' runs east-west at plan y = face..face+thick;
    axis 'y' runs north-south at plan x = face..face+thick. start/end/openings in feet along it."""

    def __init__(self, name, axis, face, start, end, openings, exterior):
        self.name, self.axis, self.face = name, axis, face
        self.start, self.end = start, end
        self.openings = sorted(openings)
        self.exterior = exterior
        self.backers = []        # (from, to) feet along the wall: studs where another wall butts in
        self.members = []        # every non-plate board: (u0, u1, z0, z1, kind), inches -- for placing boxes

    def world(self, u_in, v_in, z_in):
        """Wall-local inches (u along, v across from the face, z up) -> world inches."""
        if self.axis == 'x':
            return (u_in, -(self.face * 12 + v_in), z_in)
        return (self.face * 12 + v_in, -u_in, z_in)

    def size(self, du, dv, dz):
        return (du, dv, dz) if self.axis == 'x' else (dv, du, dz)


def build_wall(w):
    col = sub_collection('Wall_' + w.name, walls_col)
    along = 'x' if w.axis == 'x' else 'y'
    s, e = w.start * 12, w.end * 12
    v = STUD_W / 2
    top = PLATE_T + STUD_LEN
    n = [0]

    def put(kind, u0, u1, z0, z1, axis, mat='lumber', v0=0.0, v1=STUD_W):
        n[0] += 1
        if 'Plate' not in kind:
            w.members.append((u0, u1, z0, z1, kind))
        board('%s_%s_%02d' % (w.name, kind, n[0]), col, w.size(u1 - u0, v1 - v0, z1 - z0),
              w.world((u0 + u1) / 2, (v0 + v1) / 2, (z0 + z1) / 2), axis, mat)

    # Plates: bottom (pressure treated, broken at doors), top and cap (full length).
    doors = [(a * 12, b * 12) for a, b, kind, _ in w.openings if kind == 'door']
    u = s
    for a, b in doors + [(e, e)]:
        if a - u > 0.5:
            put('BottomPlate', u, a, 0, PLATE_T, along, 'pt')
        u = b
    put('TopPlate', s, e, top, top + PLATE_T, along)
    put('CapPlate', s, e, top + PLATE_T, top + 2 * PLATE_T, along)

    # Studs: the opening framing first, then T-backers and wall ends, then layout studs
    # wherever they don't collide.
    taken = []

    def stud(kind, u0, z0=PLATE_T, z1=top, force=False):
        u1 = u0 + STUD_T
        if u0 < s - 0.01 or u1 > e + 0.01:
            return False
        if not force and any(u0 < b - 0.01 and u1 > a + 0.01 for a, b in taken):
            return False
        taken.append((u0, u1))
        put(kind, u0, u1, z0, z1, 'z')
        return True

    spans = []    # (from, to) inches where full-height layout studs become cripples
    for a, b, kind, sill in w.openings:
        a, b = a * 12, b * 12
        hd = EXT_HEADER if w.exterior else INT_HEADER
        stud('Jack', a - STUD_T, PLATE_T, RO_HEAD, force=True)
        stud('Jack', b, PLATE_T, RO_HEAD, force=True)
        stud('King', a - 2 * STUD_T, force=True)
        stud('King', b + STUD_T, force=True)
        # Header: two plies with a plywood spacer, sitting on the jacks.
        h0, h1 = RO_HEAD, RO_HEAD + hd
        put('Header', a - STUD_T, b + STUD_T, h0, h1, along, 'lumber', 0, STUD_T)
        put('Header', a - STUD_T, b + STUD_T, h0, h1, along, 'lumber', STUD_W - STUD_T, STUD_W)
        put('HeaderSpacer', a - STUD_T, b + STUD_T, h0, h1, along, 'ply', STUD_T, STUD_W - STUD_T)
        if kind == 'window':
            put('RoughSill', a, b, sill - STUD_T, sill, along)
        spans.append((a - STUD_T, b + STUD_T, kind, sill, h1))

    for a, b in w.backers:
        stud('Backer', a * 12)
        stud('Backer', b * 12 - STUD_T)
    stud('End', s)
    stud('End', e - STUD_T)

    k = math.floor(s / STUD_OC) + 1
    while k * STUD_OC - STUD_T / 2 < e:
        u0 = k * STUD_OC - STUD_T / 2
        k += 1
        hit = next((sp for sp in spans if sp[0] < u0 + STUD_T and u0 < sp[1]), None)
        if hit is None:
            stud('Stud', u0)
            continue
        a, b, kind, sill, h1 = hit
        if u0 < a + STUD_T or u0 + STUD_T > b - STUD_T:   # would land on a jack
            continue
        if top - h1 > 0.5:
            put('Cripple', u0, u0 + STUD_T, h1, top, 'z')
        if kind == 'window' and sill - STUD_T - PLATE_T > 0.5:
            put('Cripple', u0, u0 + STUD_T, PLATE_T, sill - STUD_T, 'z')
    return col


# --- Build the plan ---------------------------------------------------------------------------
walls_col = sub_collection('Walls')
T = WALL_T
walls = [
    Wall('North', 'x', 0.0, 0.0, HOUSE_W, EXT_OPENINGS['North'], True),
    Wall('South', 'x', HOUSE_D - T, 0.0, HOUSE_W, EXT_OPENINGS['South'], True),
    Wall('West', 'y', 0.0, T, HOUSE_D - T, EXT_OPENINGS['West'], True),
    Wall('East', 'y', HOUSE_W - T, T, HOUSE_D - T, EXT_OPENINGS['East'], True),
]
for name, axis, face, a, b, ops in PARTITIONS:
    walls.append(Wall(name, axis, face, a, b, ops, False))

# Wherever a wall's end butts into another wall's face, give that wall two backer studs.
for w in walls:
    for end in (w.start, w.end):
        for q in walls:
            if q is w or q.axis == w.axis:
                continue
            touches = abs(end - q.face) < 0.02 or abs(end - (q.face + T)) < 0.02
            if touches and q.start - 0.01 <= w.face and w.face + T <= q.end + 0.01:
                q.backers.append((w.face - STUD_T / 12, w.face + T + STUD_T / 12))

for w in walls:
    build_wall(w)

# --- Concrete -----------------------------------------------------------------------------------
slab_col = sub_collection('Concrete')


def slab_box(name, x0, x1, y0, y1, z0, z1):
    """Plan feet in x/y (y south), inches in z."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=((x1 - x0) * FT, (y1 - y0) * FT, (z1 - z0) * IN), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6
                              and e.verts[0].co.z > 0], offset=0.25 * IN, segments=2, affect='EDGES')
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS['concrete'])
    obj = bpy.data.objects.new(name, mesh)
    obj.location = ((x0 + x1) / 2 * FT, -(y0 + y1) / 2 * FT, (z0 + z1) / 2 * IN)
    slab_col.objects.link(obj)
    return obj


slab_box('Slab', 0, HOUSE_W, 0, HOUSE_D, -SLAB_T, 0)
fw, fd = FOOTING[0] / 12, FOOTING[1]
for name, box in (('Footing_North', (0, HOUSE_W, 0, fw)), ('Footing_South', (0, HOUSE_W, HOUSE_D - fw, HOUSE_D)),
                  ('Footing_West', (0, fw, fw, HOUSE_D - fw)), ('Footing_East', (HOUSE_W - fw, HOUSE_W, fw, HOUSE_D - fw))):
    slab_box(name, *box, -SLAB_T - fd, -SLAB_T)
slab_box('Patio_Slab', *PATIO, -EXT_SLAB_DROP - EXT_SLAB_T, -EXT_SLAB_DROP)
slab_box('Porch_Slab', *PORCH, -EXT_SLAB_DROP - EXT_SLAB_T, -EXT_SLAB_DROP)

# --- Roof and ceiling ---------------------------------------------------------------------------
# Fink ("W") trusses span north-south across the 28' depth, 24" on centre; their bottom
# chords are the ceiling framing. Gable-end trusses (studs at 16" instead of webs) sit on
# the west and east walls. Rake overhangs hang off barge rafters on lookouts; eaves end
# in a 2x6 sub-fascia and fascia. Then 4x8 OSB sheets, staggered, and shingles.
PITCH = 6.0                  # rise per 12 of run
TRUSS_OC = 24.0
EAVE_OVERHANG = 12.0         # horizontal, past the wall's outside face
RAKE_OVERHANG = 12.0         # past the gable walls
WEB_POINTS = (1 / 3, 1 / 4)  # Fink: webs from the bottom chord's third points to the top chord's quarter points and the peak
GABLE_STUD_OC = 16.0
GUSSET = (5.0, 3.25, 0.04)   # metal plate at each joint: width, height (stays inside the 3-1/2" lumber), thickness
LOOKOUT_OC = 24.0
SUBFASCIA = (1.5, 5.5)       # 2x6
FASCIA = (0.75, 7.25)        # 1x8
OSB_T = 0.4375               # 7/16" roof sheathing
OSB_SHEET = (96.0, 48.0)
OSB_GAP = 0.125
RIDGE_GAP = 1.0              # sheathing stops this far short of the peak (ridge vent slot)
SHINGLE_T = 0.12             # each layer of a laminated (architectural) shingle
SHINGLE_HEIGHT = 13.25       # strip height, eave to top edge
SHINGLE_EXPOSURE = 5.625     # each course of shingles shows this much
SHINGLE_EAVE = 0.75          # shingles hang past the sheathing at the eave and rake
STARTER_H = 7.0              # starter strip along the eave
TOOTH_W = (5.0, 12.0)        # laminated "teeth" on each course: random width...
TOOTH_GAP = (0.5, 2.5)       # ...with the darker backer showing between them
TOOTH_TONES = (0.75, 1.2)    # tooth-to-tooth colour shift (1 = the base colour)
BACKER_TONE = 0.55           # the backer strip between teeth reads darker
CAP_EXPOSURE = 5.625         # ridge cap pieces, lapped along the ridge
CAP_W, CAP_LEN, CAP_T = 12.0, 12.0, 0.2
SHINGLE_SEED = 7             # change for a different tooth pattern


def simple_material(name, base, metallic=0.0, rough=0.5, noise=(0.0, 0.0)):
    mat, nt, bsdf = _new_material(name, base)
    bsdf.inputs['Base Color'].default_value = (*base, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    if noise[0]:
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = noise[1]
        b = nt.nodes.new('ShaderNodeBump')
        b.inputs['Strength'].default_value = noise[0]
        b.inputs['Distance'].default_value = 0.0003
        nt.links.new(nt.nodes.new('ShaderNodeTexCoord').outputs['Object'], n.inputs['Vector'])
        nt.links.new(n.outputs['Fac'], b.inputs['Height'])
        nt.links.new(b.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def osb_material():
    mat, nt, bsdf = _new_material('OSB', (0.70, 0.55, 0.34))
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    flakes = nt.nodes.new('ShaderNodeTexVoronoi')     # wood strands
    flakes.inputs['Scale'].default_value = 90.0
    stretch = nt.nodes.new('ShaderNodeVectorMath')
    stretch.operation = 'MULTIPLY'
    stretch.inputs[1].default_value = (1.0, 3.5, 1.0)
    grain = nt.nodes.new('ShaderNodeTexNoise')
    grain.inputs['Scale'].default_value = 600.0
    mix = nt.nodes.new('ShaderNodeMath')
    mix.operation = 'MULTIPLY_ADD'
    mix.inputs[1].default_value = 0.35
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (0.50, 0.36, 0.20, 1)
    ramp.color_ramp.elements[1].color = (0.82, 0.68, 0.45, 1)
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.3
    bump.inputs['Distance'].default_value = 0.0004
    L(coord.outputs['Object'], stretch.inputs[0])
    L(stretch.outputs['Vector'], flakes.inputs['Vector'])
    L(coord.outputs['Object'], grain.inputs['Vector'])
    L(flakes.outputs['Color'], sep.inputs['Color'])
    L(grain.outputs['Fac'], mix.inputs[0])
    L(sep.outputs['Red'], mix.inputs[2])
    L(mix.outputs['Value'], ramp.inputs['Fac'])
    L(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    L(sep.outputs['Red'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.75
    return mat


def shingle_material():
    """Dark granules, tinted per tooth by the mesh's `tone` attribute."""
    mat, nt, bsdf = _new_material('Shingles', (0.16, 0.16, 0.17))
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    tone = nt.nodes.new('ShaderNodeAttribute')
    tone.attribute_name = 'tone'
    granules = nt.nodes.new('ShaderNodeTexNoise')
    granules.inputs['Scale'].default_value = 2500.0
    granules.inputs['Detail'].default_value = 4
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (0.035, 0.035, 0.038, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.11, 0.105, 0.10, 1)
    shade = nt.nodes.new('ShaderNodeMix')
    shade.data_type = 'RGBA'
    shade.blend_type = 'MULTIPLY'
    shade.inputs['Factor'].default_value = 1.0
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.5
    bump.inputs['Distance'].default_value = 0.0005
    L(coord.outputs['Object'], granules.inputs['Vector'])
    L(granules.outputs['Fac'], ramp.inputs['Fac'])
    cin = [sk for sk in shade.inputs if sk.type == 'RGBA']
    L(ramp.outputs['Color'], cin[0])
    L(tone.outputs['Fac'], cin[1])
    L(next(sk for sk in shade.outputs if sk.type == 'RGBA'), bsdf.inputs['Base Color'])
    L(granules.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.9
    bsdf.inputs['Specular IOR Level'].default_value = 0.25    # granules: little sheen
    return mat


MATS.update({'osb': osb_material(), 'shingle': shingle_material(),
             'galv': simple_material('Galvanized', (0.62, 0.63, 0.64), 0.9, 0.45, (0.2, 900.0))})


def place(name, col, dims, center, theta, mat):
    """A board (dims = local x, y, z inches, z its length) at `center` (world inches),
    tipped by `theta` about X (local Y stays in the YZ plane)."""
    mesh = board_mesh(*dims)
    if not mesh.materials:
        mesh.materials.append(MATS[mat])
    elif mesh.materials[0] != MATS[mat]:
        mesh = mesh.copy()
        mesh.materials[0] = MATS[mat]
    obj = bpy.data.objects.new(name, mesh)
    obj.matrix_world = Matrix.Translation(Vector(center) * IN) @ Matrix.Rotation(theta, 4, 'X')
    col.objects.link(obj)
    return obj


def member(name, col, x, p1, p2, mat='lumber', depth=STUD_W, trim=0.0):
    """A 2x member in the truss plane at world x (inches), centreline from plan (y, z) p1
    to p2, inches. `trim` shortens both ends."""
    (y1, z1), (y2, z2) = p1, p2
    L = math.hypot(y2 - y1, z2 - z1)
    uy, uz = (y2 - y1) / L, (z2 - z1) / L
    y1, z1, y2, z2 = y1 + uy * trim, z1 + uz * trim, y2 - uy * trim, z2 - uz * trim
    theta = math.atan2(y2 - y1, z2 - z1)
    return place(name, col, (STUD_T, depth, L - 2 * trim), (x, -(y1 + y2) / 2, (z1 + z2) / 2), theta, mat)


class Pieces:
    """Many flat pieces merged into one mesh. Each piece is a 2D outline (u, z) in some face
    frame, pushed off the face: to_world(u, z, d) -> world inches, back(u, z) -> the d of the
    piece's back there (lets a piece tilt, like a lap siding plank resting on the one below).
    Each piece gets a `tone` (face attribute) and a material slot."""

    def __init__(self):
        self.bm = bmesh.new()
        self.tone = self.bm.faces.layers.float.new('tone')
        self.n = 0

    def add(self, poly, to_world, back, thick, tone=1.0, slot=0):
        if len(poly) < 3:
            return
        bv = [self.bm.verts.new(Vector(to_world(u, z, back(u, z))) * IN) for u, z in poly]
        fv = [self.bm.verts.new(Vector(to_world(u, z, back(u, z) + thick)) * IN) for u, z in poly]
        faces = [self.bm.faces.new(bv), self.bm.faces.new(fv[::-1])]
        for i in range(len(poly)):
            j = (i + 1) % len(poly)
            faces.append(self.bm.faces.new((bv[i], bv[j], fv[j], fv[i])))
        for f in faces:
            f[self.tone] = tone
            f.material_index = slot
        self.n += 1

    def build(self, name, col, mats):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        mesh = bpy.data.meshes.new(name + '_Mesh')
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in mats:
            mesh.materials.append(MATS[m])
        obj = bpy.data.objects.new(name, mesh)
        col.objects.link(obj)
        return obj


def flat(d):
    return lambda u, z: d


def rect_poly(u0, u1, z0, z1):
    return [(u0, z0), (u1, z0), (u1, z1), (u0, z1)]


def rect_minus(rects, holes):
    """Rectangles (u0, u1, z0, z1) with the hole rectangles taken out (still rectangles)."""
    for h0, h1, hz0, hz1 in holes:
        nxt = []
        for u0, u1, z0, z1 in rects:
            if not (u0 < h1 and h0 < u1 and z0 < hz1 and hz0 < z1):
                nxt.append((u0, u1, z0, z1))
                continue
            if u0 < h0:
                nxt.append((u0, h0, z0, z1))
            if h1 < u1:
                nxt.append((h1, u1, z0, z1))
            a, b = max(u0, h0), min(u1, h1)
            if z0 < hz0:
                nxt.append((a, b, z0, hz0))
            if hz1 < z1:
                nxt.append((a, b, hz1, z1))
        rects = [r for r in nxt if r[1] - r[0] > 0.05 and r[3] - r[2] > 0.05]
    return rects


def clip_convex(poly, clip):
    """Sutherland-Hodgman: `poly` clipped to the convex, counter-clockwise polygon `clip`."""
    out = list(poly)
    for i in range(len(clip)):
        if not out:
            break
        (ax, az), (bx, bz) = clip[i], clip[(i + 1) % len(clip)]
        side = lambda p: (bx - ax) * (p[1] - az) - (bz - az) * (p[0] - ax)
        inp, out = out, []
        for k in range(len(inp)):
            p, q = inp[k - 1], inp[k]
            sp, sq = side(p), side(q)
            if sq >= -1e-9:
                if sp < -1e-9:
                    t = sp / (sp - sq)
                    out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
                out.append(q)
            elif sp >= -1e-9:
                t = sp / (sp - sq)
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    clean = []
    for p in out:
        if not clean or abs(p[0] - clean[-1][0]) + abs(p[1] - clean[-1][1]) > 1e-4:
            clean.append(p)
    if len(clean) > 1 and abs(clean[0][0] - clean[-1][0]) + abs(clean[0][1] - clean[-1][1]) < 1e-4:
        clean.pop()
    if len(clean) < 3:
        return []
    area = sum(clean[i - 1][0] * clean[i][1] - clean[i][0] * clean[i - 1][1] for i in range(len(clean))) / 2
    return clean if abs(area) > 0.01 else []


SPAN = HOUSE_D * 12
SLOPE = PITCH / 12
COS = 1 / math.sqrt(1 + SLOPE * SLOPE)
ALPHA = math.atan(SLOPE)
WALL_TOP = PLATE_T + STUD_LEN + 2 * PLATE_T          # top of the cap plate
CHORD_TOP = WALL_TOP + STUD_W                         # top of the bottom chord
RIDGE_Y = SPAN / 2


def run(y):
    """Horizontal distance from the nearer eave wall's outside face."""
    return y if y <= RIDGE_Y else SPAN - y


def chord_bottom(y):      # underside of the top chords, plan y inches
    return CHORD_TOP + run(y) * SLOPE


def chord_centre(y):
    return chord_bottom(y) + (STUD_W / 2) / COS


def roof_plane(y):        # top of the top chords = underside of the sheathing
    return chord_bottom(y) + STUD_W / COS


roof_col = sub_collection('Roof')
truss_col = sub_collection('Trusses', roof_col)
tail = -EAVE_OVERHANG


def truss(i, x, gable):
    col = sub_collection('Truss_%02d%s' % (i, '_Gable' if gable else ''), truss_col)
    nm = 'Truss%02d_' % i
    # Bottom chord (ceiling joist) and the two top chords, tails out over the eaves.
    board(nm + 'BottomChord', col, (STUD_T, SPAN, STUD_W), (x, -SPAN / 2, WALL_TOP + STUD_W / 2), 'y', 'lumber')
    member(nm + 'TopChord_N', col, x, (tail, chord_centre(0) + tail * SLOPE), (RIDGE_Y, chord_centre(RIDGE_Y)))
    member(nm + 'TopChord_S', col, x, (SPAN - tail, chord_centre(0) + tail * SLOPE), (RIDGE_Y, chord_centre(RIDGE_Y)))
    bottom_c = WALL_TOP + STUD_W / 2
    joints = [(STUD_W / 2, CHORD_TOP), (SPAN - STUD_W / 2, CHORD_TOP), (RIDGE_Y, chord_centre(RIDGE_Y) - 0.6)]
    if gable:
        k = 1
        while k * GABLE_STUD_OC < SPAN - 1:
            y = k * GABLE_STUD_OC
            k += 1
            h = chord_bottom(y) - CHORD_TOP
            if h > 3:
                board(nm + 'GableStud', col, (STUD_T, STUD_W, h), (x, -y, CHORD_TOP + h / 2), 'z', 'lumber')
    else:
        b3, q4 = WEB_POINTS
        for yb, yt in ((SPAN * b3, SPAN * q4), (SPAN * (1 - b3), SPAN * (1 - q4))):
            member(nm + 'Web', col, x, (yb, bottom_c), (yt, chord_centre(yt)), trim=STUD_W / 2)
            member(nm + 'Web', col, x, (yb, bottom_c), (RIDGE_Y, chord_centre(RIDGE_Y)), trim=STUD_W / 2)
            joints += [(yb, bottom_c), (yt, chord_centre(yt))]
    # Gusset plates, both faces, at every joint.
    gw, gh, gt = GUSSET
    for y, z in joints:
        for side in (-1, 1):
            board(nm + 'Gusset', col, (gt, gw, gh), (x + side * (STUD_T / 2 + gt / 2), -y, z), 'z', 'galv')


xs = [STUD_T / 2]
k = 1
while k * TRUSS_OC < HOUSE_W * 12 - STUD_T:
    xs.append(k * TRUSS_OC)
    k += 1
xs.append(HOUSE_W * 12 - STUD_T / 2)
for i, x in enumerate(xs):
    truss(i + 1, x, gable=(i == 0 or i == len(xs) - 1))

# Overhangs: barge rafters on lookouts at the rakes, sub-fascia and fascia at the eaves.
over_col = sub_collection('Overhangs', roof_col)
W_IN = HOUSE_W * 12
for name, bx in (('West', -RAKE_OVERHANG + STUD_T / 2), ('East', W_IN + RAKE_OVERHANG - STUD_T / 2)):
    member('Barge_%s_N' % name, over_col, bx, (tail, chord_centre(0) + tail * SLOPE), (RIDGE_Y, chord_centre(RIDGE_Y)))
    member('Barge_%s_S' % name, over_col, bx, (SPAN - tail, chord_centre(0) + tail * SLOPE), (RIDGE_Y, chord_centre(RIDGE_Y)))
    x0, x1 = (-RAKE_OVERHANG + STUD_T, xs[1] - STUD_T / 2) if name == 'West' else (xs[-2] + STUD_T / 2, W_IN + RAKE_OVERHANG - STUD_T)
    y = LOOKOUT_OC / 2
    while y < SPAN - 1:
        if abs(y - RIDGE_Y) > 6:
            board('Lookout_%s' % name, over_col, (x1 - x0, STUD_W, STUD_T),
                  ((x0 + x1) / 2, -y, roof_plane(y) - STUD_T / 2 - (STUD_W / 2) * SLOPE), 'x', 'lumber')   # uphill edge just under the roof
        y += LOOKOUT_OC
fx0, fx1 = -RAKE_OVERHANG, W_IN + RAKE_OVERHANG
for name, y_out, sgn in (('North', tail, -1), ('South', SPAN - tail, 1)):
    top_z = roof_plane(0) + tail * SLOPE
    sw, sh = SUBFASCIA
    board('SubFascia_' + name, over_col, (fx1 - fx0, sw, sh), ((fx0 + fx1) / 2, -(y_out + sgn * sw / 2), top_z - sh / 2), 'x', 'lumber')
    fw_, fh = FASCIA
    board('Fascia_' + name, over_col, (fx1 - fx0 + 2 * fw_, fw_, fh),
          ((fx0 + fx1) / 2, -(y_out + sgn * (sw + fw_ / 2)), top_z + 0.5 - fh / 2), 'x', 'lumber')

# Sheathing: 4x8 OSB, long side across the rafters, joints staggered half a sheet.
sheath_col = sub_collection('Sheathing', roof_col)
eave_y = tail - SUBFASCIA[0]
slope_len = (RIDGE_Y - eave_y) / COS - RIDGE_GAP
for side, sgn in (('N', 1), ('S', -1)):
    theta = (math.pi - ALPHA) if sgn > 0 else ALPHA
    y0 = eave_y if sgn > 0 else SPAN - eave_y
    z0 = roof_plane(0) + eave_y * SLOPE

    def on_slope(s, off):
        """Plan (y, z) of a point `s` up the slope from the eave edge, `off` above the plane."""
        y = y0 + sgn * s * COS - sgn * off * math.sin(ALPHA)
        z = z0 + s * math.sin(ALPHA) + off * COS
        return y, z

    course, s = 0, 0.0
    while s < slope_len - 0.5:
        h = min(OSB_SHEET[1], slope_len - s)
        x = fx0 - (OSB_SHEET[0] / 2 if course % 2 else 0)
        while x < fx1 - 0.5:
            a, b = max(x, fx0), min(x + OSB_SHEET[0], fx1)
            if b - a > 1:
                y, z = on_slope(s + h / 2, OSB_T / 2)
                place('OSB_%s_%d' % (side, course), sheath_col, (b - a - OSB_GAP, h - OSB_GAP, OSB_T),
                      ((a + b) / 2, -y, z), theta, 'osb')
            x += OSB_SHEET[0]
        s += OSB_SHEET[1]
        course += 1
    # Shingles: a starter strip along the eave, then laminated courses -- a full-width backer
    # strip with randomly sized teeth on top. Each course tilts a touch so its butt edge rests
    # on the course below (that's the step you see at every course line).
    to_w = lambda x, s, n: (x, -on_slope(s, n)[0], on_slope(s, n)[1])
    rng = random.Random(SHINGLE_SEED * 2 + (sgn > 0))
    pc = Pieces()
    sx0, sx1 = fx0 - SHINGLE_EAVE, fx1 + SHINGLE_EAVE
    lift = 2 * SHINGLE_T * SHINGLE_HEIGHT / SHINGLE_EXPOSURE      # just clears the two layers below
    pc.add(rect_poly(sx0, sx1, -SHINGLE_EAVE, -SHINGLE_EAVE + STARTER_H), to_w, flat(OSB_T), SHINGLE_T, BACKER_TONE)
    i = 0
    while True:
        sb = -SHINGLE_EAVE + i * SHINGLE_EXPOSURE
        if sb > slope_len - 1.0:
            break
        st = min(sb + SHINGLE_HEIGHT, slope_len)
        back = lambda x, s, sb=sb: OSB_T + lift * max(0.0, 1 - (s - sb) / SHINGLE_HEIGHT)
        pc.add(rect_poly(sx0, sx1, sb, st), to_w, back, SHINGLE_T, BACKER_TONE)
        on_top = lambda x, s, back=back: back(x, s) + SHINGLE_T
        x = sx0 - rng.uniform(0, TOOTH_W[1])
        tz = min(sb + SHINGLE_EXPOSURE + 1.0, st)
        while x < sx1:
            w_ = rng.uniform(*TOOTH_W)
            a, b = max(x, sx0), min(x + w_, sx1)
            if b - a > 0.3:
                pc.add(rect_poly(a, b, sb, tz), to_w, on_top, SHINGLE_T, rng.uniform(*TOOTH_TONES))
            x += w_ + rng.uniform(*TOOTH_GAP)
        i += 1
    pc.build('Shingles_' + side, roof_col, ['shingle'])

    # Ridge cap: pieces lapped along the ridge from the west end, each bent over the peak and
    # resting on the one before.
    s_peak = slope_len + RIDGE_GAP
    base = OSB_T + lift + 2 * SHINGLE_T
    cap_lift = CAP_T * CAP_LEN / CAP_EXPOSURE
    cap = Pieces()
    xb = sx0
    while xb < sx1 - 0.5:
        back = lambda x, s, xb=xb: base + cap_lift * max(0.0, 1 - (x - xb) / CAP_LEN)
        n_out = base + cap_lift + CAP_T
        cap.add(rect_poly(xb, min(xb + CAP_LEN, sx1), s_peak - CAP_W / 2, s_peak + n_out * SLOPE),
                to_w, back, CAP_T, rng.uniform(0.8, 1.15))
        xb += CAP_EXPOSURE
    cap.build('RidgeCap_' + side, roof_col, ['shingle'])

count = sum(1 for o in house.all_objects)
print('Built house: %d objects (%d wall framing, %d roof).' % (count, sum(1 for o in walls_col.all_objects),
                                                             sum(1 for o in roof_col.all_objects)))


# --- Electrical boxes -------------------------------------------------------------------------------
# Blue nail-on boxes (blend/nail_on_box.py) nailed to the side of a real stud, front 1/2" proud
# of the stud face for drywall. Each box is a collection instance of the one box model.
# Layout follows common residential practice: receptacles every 12' of wall (none more than
# 6' from a point along the wall), kitchen counters at 44", vanity at 40", switches 46" to
# centre (48" to the top) on the latch side of the door.
REC_H, SWITCH_H, COUNTER_H, VANITY_H, LAUNDRY_H = 15.0, 46.0, 44.0, 40.0, 42.0
DRYWALL = 0.5                     # box front sits this far proud of the stud face
BOX_HALF = (2.25 / 2, 3.7 / 2)    # half width, half height of the box (inches)

# (name, wall, near this point along the wall in feet, room side, centre height in inches).
# Room side: N/S for walls running east-west, W/E for walls running north-south.
BOXES = [
    # Kitchen
    ('Kitchen_Counter_1', 'West', 2.2, 'E', COUNTER_H),
    ('Kitchen_Counter_2', 'West', 5.8, 'E', COUNTER_H),
    ('Kitchen_Counter_3', 'West', 9.4, 'E', COUNTER_H),
    ('Kitchen_Counter_4', 'North', 7.3, 'S', COUNTER_H),
    ('Kitchen_Fridge', 'West', 11.0, 'E', COUNTER_H),
    ('Kitchen_Switch', 'North', 13.7, 'S', SWITCH_H),
    # Living
    ('Living_Rec_1', 'West', 16.5, 'E', REC_H),
    ('Living_Rec_2', 'West', 23.5, 'E', REC_H),
    ('Living_Rec_3', 'South', 2.0, 'N', REC_H),
    ('Living_Rec_4', 'South', 8.3, 'N', REC_H),
    ('Living_Rec_5', 'P1_Kitchen_Living', 19.5, 'W', REC_H),
    ('Living_Rec_6', 'P1_Kitchen_Living', 25.5, 'W', REC_H),
    ('Living_Switch', 'South', 9.6, 'N', SWITCH_H),
    # Bedroom 2
    ('Bed2_Rec_1', 'North', 19.6, 'S', REC_H),
    ('Bed2_Rec_2', 'North', 29.0, 'S', REC_H),
    ('Bed2_Rec_3', 'East', 6.0, 'W', REC_H),
    ('Bed2_Rec_4', 'P5_Bed2_Bath', 25.5, 'N', REC_H),
    ('Bed2_Rec_5', 'P2_Closet2_WH', 7.8, 'E', REC_H),
    ('Bed2_Switch', 'P2_Closet2_WH', 10.4, 'E', SWITCH_H),
    # Bedroom 1
    ('Bed1_Rec_1', 'South', 19.6, 'N', REC_H),
    ('Bed1_Rec_2', 'South', 29.0, 'N', REC_H),
    ('Bed1_Rec_3', 'East', 22.0, 'W', REC_H),
    ('Bed1_Rec_4', 'P6_Bed1_Bath', 25.5, 'S', REC_H),
    ('Bed1_Rec_5', 'P3_WD_Closet1', 20.0, 'E', REC_H),
    ('Bed1_Switch', 'P3_WD_Closet1', 17.6, 'E', SWITCH_H),
    # Bath, hall, laundry
    ('Bath_Vanity_GFCI', 'P5_Bed2_Bath', 22.4, 'S', VANITY_H),
    ('Bath_Switch', 'P8_Bath', 12.9, 'E', SWITCH_H),
    ('Hall_Rec', 'P8_Bath', 12.4, 'W', REC_H),
    ('Laundry_Washer', 'P1_Kitchen_Living', 18.4, 'E', LAUNDRY_H),
]


def load_asset(script, collection_name, **preset):
    """Runs one of the sibling model scripts and returns its collection, unlinked from the
    scene so it's only used through instances."""
    import os
    here = None
    try:
        here = os.path.dirname(os.path.abspath(__file__))
    except NameError:
        pass
    if not here or not os.path.exists(os.path.join(here, script)):
        for t in bpy.data.texts:
            if t.filepath.endswith('house_framing.py'):
                here = os.path.dirname(bpy.path.abspath(t.filepath))
    if not here:                                          # last resort: the project's blend/ folder
        here = os.path.join(os.getcwd(), 'blend')
    path = os.path.join(here, script)
    exec(compile(open(path).read(), path, 'exec'), {'__name__': script[:-3], '__file__': path, **preset})
    asset = bpy.data.collections[collection_name]
    for c in list(scene.collection.children):            # the model and any companion collections
        if c.name in (collection_name, 'GFCI_Load_Tape'):
            scene.collection.children.unlink(c)          # used only through instances
    return asset


def load_box_asset():
    return load_asset('nail_on_box.py', 'Nail_On_Box', NAILS_DRIVEN=True)


def place_box(name, wall, near_ft, side, h, col, asset, half=None):
    w = next(q for q in walls if q.name == wall)
    face = {'N': 0, 'W': 0, 'S': 1, 'E': 1}[side]
    bw, bh = half or BOX_HALF
    z0, z1 = h - bh, h + bh
    target = near_ft * 12
    s, e = w.start * 12, w.end * 12
    in_band = [m for m in w.members if m[2] < z1 and m[3] > z0]       # boards at the box's height
    best = None
    for u0, u1, mz0, mz1, kind in in_band:
        if kind not in ('Stud', 'King', 'End', 'Backer') or mz0 > z0 or mz1 < z1:
            continue                                                  # nail only to a full-height stud
        for sgn in (-1, 1):                                           # box before or after the stud
            a, b = (u0 - 2 * bw, u0) if sgn < 0 else (u1, u1 + 2 * bw)
            if a < s or b > e:
                continue
            if any(m[0] < b - 0.01 and m[1] > a + 0.01 for m in in_band):
                continue
            score = abs((a + b) / 2 - target)
            if best is None or score < best[0]:
                best = (score, (a + b) / 2, -sgn)                       # -sgn: direction from the box toward the stud
    if best is None:
        print('No stud for box', name)
        return None
    _, uc, toward = best
    # Directions in the world: along the wall (+u), out of the room-side face, up.
    du = Vector((1, 0, 0)) if w.axis == 'x' else Vector((0, -1, 0))
    dv = Vector((0, -1, 0)) if w.axis == 'x' else Vector((1, 0, 0))
    out = dv if face else -dv
    v_front = (STUD_W + DRYWALL) if face else -DRYWALL
    pos = Vector(w.world(uc, v_front, h)) * IN
    x_axis = du * toward                                              # box's nail side faces the stud
    rot = Matrix((x_axis, -out, Vector((0, 0, 1)))).transposed()      # box +Y runs back into the wall
    obj = bpy.data.objects.new('Box_' + name, None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = asset
    obj.empty_display_size = 0.05
    obj.matrix_world = Matrix.Translation(pos) @ rot.to_4x4()
    col.objects.link(obj)
    BOX_INFO[name] = {'wall': w, 'face': face, 'uc': uc, 'toward': toward, 'h': h, 'out': out, 'half': (bw, bh)}
    return obj


BOX_INFO = {}    # where each box ended up, for the wiring below
boxes_col = sub_collection('Boxes')
box_asset = load_box_asset()
placed = [place_box(*spec, boxes_col, box_asset) for spec in BOXES]
# Dryer: a 4" square box (the flush 14-30R is too big for a single gang) on the closet's back wall.
DRYER_BOX = ('Laundry_Dryer', 'P7_WD_Closet1', 15.5, 'N', 30.0)
box4_asset = load_asset('nail_on_box.py', 'Nail_On_Box_4Sq', NAILS_DRIVEN=True, BOX_SIZE=(4.0, 4.0, 2.5),
                        COLLECTION_NAME='Nail_On_Box_4Sq')
placed.append(place_box(*DRYER_BOX, boxes_col, box4_asset, half=(2.0, 2.0)))
# Range: a 4" square box low on the kitchen's west wall, behind where the range stands, so the
# 14-50R sits in the recess at the bottom of the range's back (it can still push back to the wall).
RANGE_AT = 7.6               # range centre along the west wall (ft from the north wall's outside)
RANGE_BOX = ('Kitchen_Range', 'West', RANGE_AT + 0.35, 'E', 5.5)
placed.append(place_box(*RANGE_BOX, boxes_col, box4_asset, half=(2.0, 2.0)))
print('Placed %d boxes.' % sum(1 for p in placed if p))


# --- Romex (NM-B) -----------------------------------------------------------------------------------
# Slab house, so everything is fed from the attic: each box gets a drop down its stud bay
# (through the top plates), cables run over the ceiling joists (truss bottom chords) from bay
# to bay, and home runs drop into the panel. The cable is a flat-oval jacket swept along each
# path; inside each box the black, white and bare conductors fold down and out the front
# with stripped ends -- rough-in, ready for devices.
NM = {   # jacket width, thickness, jacket colour, insulated conductor radius, bare ground radius (in)
    '14/2': (0.39, 0.21, (0.86, 0.85, 0.81), 0.066, 0.032),
    '12/2': (0.45, 0.24, (0.86, 0.66, 0.10), 0.075, 0.040),
    '10/3': (0.62, 0.27, (0.90, 0.45, 0.08), 0.105, 0.051),     # orange jacket: black, red, white + bare
    '6/3': (0.92, 0.40, (0.05, 0.05, 0.055), 0.135, 0.051),     # black jacket: #6 black, red, white + #10 bare
}
BEND_R = 2.5                 # bend radius at every corner
JACKET_IN_BOX = 0.45         # the jacket reaches this far into the box (code: at least 1/4")
LEAD_OUT = 3.0               # conductors stick out past the box front by this much...
STRIP = 0.75                 # ...with this much bare copper at the end
STAPLE_FIRST = 6.0           # first staple above a box (code: within 8")
STAPLE_OC = 54.0             # then every 4-1/2'
CABLE_SPACING = 0.55         # side by side where two cables share a box
PANEL = ('West', 19.0, 'E', 60.0)        # wall, near (ft), room side, centre height (in)
PANEL_SIZE = (14.25, 20.0, 3.75)         # recessed load-centre can: width, height, depth

# Circuits: name, cable, boxes in order (the first box gets the home run from the panel).
CIRCUITS = [
    ('Kitchen_Counter_A', '12/2', ['Kitchen_Counter_1', 'Kitchen_Counter_2']),
    ('Kitchen_Counter_B', '12/2', ['Kitchen_Counter_3', 'Kitchen_Counter_4']),
    ('Fridge', '12/2', ['Kitchen_Fridge']),
    ('Bath', '12/2', ['Bath_Vanity_GFCI']),
    ('Laundry', '12/2', ['Laundry_Washer']),
    ('Living', '14/2', ['Living_Rec_1', 'Living_Rec_2', 'Living_Rec_3', 'Living_Rec_4', 'Living_Rec_6',
                        'Living_Rec_5', 'Hall_Rec']),
    ('Bedroom_1', '14/2', ['Bed1_Rec_5', 'Bed1_Rec_1', 'Bed1_Rec_2', 'Bed1_Rec_3', 'Bed1_Rec_4']),
    ('Bedroom_2', '14/2', ['Bed2_Rec_5', 'Bed2_Rec_1', 'Bed2_Rec_2', 'Bed2_Rec_3', 'Bed2_Rec_4']),
    ('Lighting', '14/2', ['Living_Switch', 'Kitchen_Switch', 'Bed2_Switch', 'Bath_Switch', 'Bed1_Switch']),
    ('Dryer', '10/3', ['Laundry_Dryer']),          # 30 A double-pole
    ('Range', '6/3', ['Kitchen_Range']),            # 50 A double-pole
]

for gauge, (_, _, colour, _, _) in NM.items():
    MATS['jacket_' + gauge] = simple_material('NM_Jacket_' + gauge.replace('/', '-'), colour, 0.0, 0.45, (0.05, 1500.0))
MATS.update({
    'ins_black': simple_material('Wire_Black', (0.02, 0.02, 0.02), 0.0, 0.3),
    'ins_red': simple_material('Wire_Red', (0.70, 0.04, 0.03), 0.0, 0.3),
    'ins_white': simple_material('Wire_White', (0.85, 0.85, 0.83), 0.0, 0.3),
    'copper': simple_material('Copper', (0.80, 0.42, 0.24), 1.0, 0.3),
    'staple': simple_material('Staple_Plastic', (0.92, 0.92, 0.90), 0.0, 0.4),
    'panel': simple_material('Panel_Steel', (0.55, 0.56, 0.57), 0.85, 0.4, (0.1, 600.0)),
})
wire_col = sub_collection('Wiring')
UP = Vector((0, 0, 1))


def fillet(points, r=BEND_R, n=6):
    """Rounds every corner of an inch polyline."""
    out = [points[0]]
    for i in range(1, len(points) - 1):
        p0, p1, p2 = points[i - 1], points[i], points[i + 1]
        a, b = p0 - p1, p2 - p1
        if a.length < 1e-4 or b.length < 1e-4:
            continue
        rr = min(r, a.length * 0.45, b.length * 0.45)
        an, bn = a.normalized(), b.normalized()
        if an.dot(bn) < -0.999:
            out.append(p1)
            continue
        s1, s2 = p1 + an * rr, p1 + bn * rr
        for k in range(n + 1):
            t = k / n
            out.append(s1 * (1 - t) ** 2 + p1 * (2 * (1 - t) * t) + s2 * (t * t))
    out.append(points[-1])
    clean = [out[0]]
    for p in out[1:]:
        if (p - clean[-1]).length > 0.02:
            clean.append(p)
    return clean


def sweep(name, pts, half_w, half_t, thin_hint, mat, seg=12):
    """Sweeps a flat-oval (or round, if half_w == half_t) section along inch points.
    thin_hint(i, tangent) gives the direction the thin side should face."""
    c = half_w - half_t
    if c < 1e-4:
        prof = [(half_t * math.cos(math.tau * k / seg), half_t * math.sin(math.tau * k / seg)) for k in range(seg)]
    else:
        m = seg // 2
        prof = [(c + half_t * math.cos(-math.pi / 2 + math.pi * k / (m - 1)),
                 half_t * math.sin(-math.pi / 2 + math.pi * k / (m - 1))) for k in range(m)]
        prof += [(-c + half_t * math.cos(math.pi / 2 + math.pi * k / (m - 1)),
                  half_t * math.sin(math.pi / 2 + math.pi * k / (m - 1))) for k in range(m)]
    bm = bmesh.new()
    rings, prev = [], None
    n = len(pts)
    for i, p in enumerate(pts):
        T = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        N = thin_hint(i, T)
        N = N - T * N.dot(T)
        if N.length < 1e-4:
            N = prev if prev is not None else T.orthogonal()
        N.normalize()
        if prev is not None and N.dot(prev) < 0:
            N = -N
        prev = N
        B = T.cross(N)
        rings.append([bm.verts.new((p + B * x + N * y) * IN) for x, y in prof])
    k = len(prof)
    for a, b in zip(rings, rings[1:]):
        for j in range(k):
            bm.faces.new((a[j], a[(j + 1) % k], b[(j + 1) % k], b[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(MATS[mat])
    obj = bpy.data.objects.new(name, mesh)
    wire_col.objects.link(obj)
    return obj


def world_box(name, w, us, vs, zs, mat):
    """An axis-aligned block given in a wall's local inches."""
    a = Vector(w.world(us[0], vs[0], zs[0]))
    b = Vector(w.world(us[1], vs[1], zs[1]))
    lo, hi = Vector(map(min, a, b)), Vector(map(max, a, b))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((lo[i] + hi[i]) / 2 + v.co[i] * (hi[i] - lo[i]) for i in range(3))) * IN
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS[mat])
    obj = bpy.data.objects.new(name, mesh)
    wire_col.objects.link(obj)
    return obj


def wall_dirs(w):
    du = Vector((1, 0, 0)) if w.axis == 'x' else Vector((0, -1, 0))
    return du


# --- Panel ---------------------------------------------------------------------------------------
pw_name, p_near, p_side, p_h = PANEL
pwall = next(q for q in walls if q.name == pw_name)
p_face = {'N': 0, 'W': 0, 'S': 1, 'E': 1}[p_side]
PW, PH, PD = PANEL_SIZE
pz0, pz1 = p_h - PH / 2, p_h + PH / 2
studs_here = sorted(m for m in pwall.members if m[4] in ('Stud', 'King', 'End', 'Backer') and m[2] < pz1 and m[3] > pz0)
bays = [(a[1], b[0]) for a, b in zip(studs_here, studs_here[1:]) if b[0] - a[1] >= PW + 0.2]
bay = min(bays, key=lambda ab: abs((ab[0] + ab[1]) / 2 - p_near * 12))
p_uc = (bay[0] + bay[1]) / 2
p_front = STUD_W + DRYWALL if p_face else -DRYWALL
p_back = p_front - PD if p_face else p_front + PD
pv = tuple(sorted((p_front, p_back)))
can = world_box('Panel_Can', pwall, (p_uc - PW / 2, p_uc + PW / 2), pv, (pz0, pz1), 'panel')
inner = world_box('Cut', pwall, (p_uc - PW / 2 + 0.06, p_uc + PW / 2 - 0.06),
                  (pv[0] + 0.06, pv[1] + 1) if p_face else (pv[0] - 1, pv[1] - 0.06),    # open on the room side
                  (pz0 + 0.06, pz1 - 0.06), 'panel')
mod = can.modifiers.new('B', 'BOOLEAN')
mod.operation, mod.solver, mod.object = 'DIFFERENCE', 'EXACT', inner
baked = bpy.data.meshes.new_from_object(can.evaluated_get(bpy.context.evaluated_depsgraph_get()))
can.modifiers.clear()
can.data = baked
bpy.data.objects.remove(inner, do_unlink=True)
# Breaker interior: an insulated back plate and the bus down the middle.
back_v = (p_back + (0.08 if p_face else -0.3), p_back + (0.3 if p_face else -0.08))
world_box('Panel_Interior', pwall, (p_uc - 5.5, p_uc + 5.5), tuple(sorted(back_v)), (pz0 + 2, pz1 - 2.5), 'ins_black')
world_box('Panel_Bus', pwall, (p_uc - 0.6, p_uc + 0.6),
          tuple(sorted((back_v[1], back_v[1] + (0.5 if p_face else -0.5)))), (pz0 + 3, pz1 - 4), 'copper')
p_vc = (p_front + p_back) / 2
panel_entries = 0


def panel_end(gauge):
    """World drop point for the next home run into the top of the panel."""
    global panel_entries
    k = panel_entries
    panel_entries += 1
    u = p_uc - PW / 2 + 1.2 + k * 1.3
    return {'xy': Vector(pwall.world(u, p_vc, 0))[:2], 'z_end': pz1 - 0.8, 'du': wall_dirs(pwall),
            'wall': pwall, 'u': u, 'v': p_vc, 'box': None}


box_cables = {}


def box_end(name, gauge):
    info = BOX_INFO[name]
    w, face, uc, toward, h = info['wall'], info['face'], info['uc'], info['toward'], info['h']
    k = box_cables.get(name, 0)
    box_cables[name] = k + 1
    half = info.get('half', BOX_HALF)
    u_stud = uc + toward * half[0]
    u = u_stud - toward * (0.35 + k * CABLE_SPACING)
    v = 1.6 if face == 0 else 1.9
    return {'xy': Vector(w.world(u, v, 0))[:2], 'z_end': h + half[1] - JACKET_IN_BOX, 'du': wall_dirs(w),
            'wall': w, 'u': u, 'v': v, 'box': name, 'toward': toward, 'h': h, 'face': face, 'out': info['out'],
            'half': half}


def nearest_truss(x_in):
    return min(xs, key=lambda t: abs(t - x_in))


def run_cable(name, gauge, A, B):
    wdt, thk, _, _, _ = NM[gauge]
    z_over = CHORD_TOP + thk / 2                     # lying across the chords
    z_side = WALL_TOP + STUD_W / 2                   # stapled to a chord's side
    (xa, ya), (xb, yb) = A['xy'], B['xy']
    pts = [Vector((xa, ya, A['z_end'])), Vector((xa, ya, z_over))]
    if abs(ya - yb) > 6:
        tx = nearest_truss((xa + xb) / 2)
        xs_ = tx + (STUD_T / 2 + wdt / 2 + 0.05) * (1 if xb >= tx else -1)
        pts += [Vector((xs_, ya, z_over)), Vector((xs_, ya, z_side)), Vector((xs_, yb, z_side)),
                Vector((xs_, yb, z_over))]
    pts += [Vector((xb, yb, z_over)), Vector((xb, yb, B['z_end']))]
    path = fillet(pts)
    half = len(path) / 2

    def thin(i, T):
        du = A['du'] if i < half else B['du']
        vert = abs(T.z)
        return (UP * (1 - vert) + du * vert)
    sweep('NM_%s_%s' % (gauge.replace('/', '-'), name), path, wdt / 2, thk / 2, thin, 'jacket_' + gauge)
    for end in (A, B):
        if end['box']:
            staples(name, gauge, end)
            BOX_ENDS.setdefault(end['box'], []).append((name, gauge, end))   # landed on the device below
        else:
            conductors(name, gauge, end, stub=True)


def staples(name, gauge, end):
    wdt, thk, _, _, _ = NM[gauge]
    w, u, v, toward = end['wall'], end['u'], end['v'], end['toward']
    z = end['h'] + end.get('half', BOX_HALF)[1] + STAPLE_FIRST
    top = WALL_TOP - PLATE_T * 3 - 2
    while z < top:
        far = u - toward * (thk / 2 + 0.03)          # crown on the cable's room side, legs to the stud
        near = u + toward * (thk / 2 + 0.25)
        world_box('Staple_' + name, w, tuple(sorted((far, far - toward * 0.06))), (v - wdt / 2 - 0.12, v + wdt / 2 + 0.12),
                  (z - 0.1, z + 0.1), 'staple')
        for sv in (-1, 1):
            vv = v + sv * (wdt / 2 + 0.06)
            world_box('Staple_' + name, w, tuple(sorted((far, near))), (vv - 0.04, vv + 0.04), (z - 0.1, z + 0.1), 'staple')
        z += STAPLE_OC


def conductors(name, gauge, end, stub=False):
    wdt, thk, _, r_ins, r_bare = NM[gauge]
    w = end['wall']
    du = end['du']
    out = end['out'] if end['box'] else (Vector(w.world(0, 1, 0)) - Vector(w.world(0, 0, 0))) * (1 if p_face else -1)
    top = Vector((end['xy'][0], end['xy'][1], end['z_end'] - 0.02))
    if end['box']:
        front_v = (STUD_W + DRYWALL) if end['face'] else -DRYWALL
        reach = abs(front_v - end['v']) + LEAD_OUT
    trio = (('ins_black', -wdt / 4), ('copper', 0.0), ('ins_white', wdt / 4))
    if gauge.endswith('/3'):
        trio = (('ins_black', -3 * wdt / 8), ('ins_red', -wdt / 8), ('copper', wdt / 8), ('ins_white', 3 * wdt / 8))
    for j, (kind, off) in enumerate(trio):
        start = top + out * off
        r = r_bare if kind == 'copper' else r_ins
        if stub:     # home-run end in the panel: conductors hang down toward the breakers
            pts = fillet([start, start - UP * 3.0, start - UP * 6.0 + du * (off * 6)], 1.5)
        else:        # in a box: fold down, then forward out the front, fanned a little
            drop = 1.0 + j * 0.25
            p2 = start - UP * drop
            p4 = start - UP * (drop + 0.6) + out * reach + du * (off * 2.5)
            pts = fillet([start, p2, p2 + out * 1.2 - UP * 0.3, p4], 0.8)
        sweep('Wire_%s_%s' % (kind, name), pts, r, r, lambda i, T: UP, kind, seg=8)
        if not stub and kind != 'copper':                  # stripped copper tip
            tip0 = pts[-1]
            tip1 = tip0 + (pts[-1] - pts[-2]).normalized() * STRIP
            sweep('Wire_Bare_%s' % name, [tip0, tip1], r * 0.55, r * 0.55, lambda i, T: UP, 'copper', seg=8)


BOX_ENDS = {}
cable_count = 0
for cname, gauge, chain in CIRCUITS:
    if not all(b in BOX_INFO for b in chain):
        print('Skipping circuit with a missing box:', cname)
        continue
    run_cable('%s_HomeRun' % cname, gauge, panel_end(gauge), box_end(chain[0], gauge))
    cable_count += 1
    for a, b in zip(chain, chain[1:]):
        run_cable('%s_%s_to_%s' % (cname, a, b), gauge, box_end(a, gauge), box_end(b, gauge))
        cable_count += 1
print('Ran %d cables on %d circuits.' % (cable_count, len(CIRCUITS)))


# --- Devices -----------------------------------------------------------------------------------------
# The TR270 receptacle (tr270_blockout.py) and the toggle switch (toggle_switch.py), each a
# collection instance screwed to its box with the ears at the drywall line. Conductors land
# the way an electrician lands them: black to brass, white to silver, bare to green, each
# stripped end hooked clockwise round its screw. In a switch box the whites are spliced
# under a wire nut. (Kitchen counter, bath and laundry spots want GFCIs -- those get the
# TR270 for now.)
MM_IN = 1 / 25.4
# Terminal geometry in each device's own millimetres: hook centres (x, y, z), shank radius.
RECEPTACLE_TERMS = {'brass': [(15.8, 10.75, 11.3), (15.8, 10.75, -2.1)],
                    'silver': [(-15.8, 10.75, 11.3), (-15.8, 10.75, -2.1)],
                    'green': (-15.2, 13.75, -28.0), 'shank': 2.08, 'green_shank': 2.4}
SWITCH_TERMS = {'brass': [(9.5, 11.8, 15.9), (9.5, 11.8, -14.9)],
                'green': (-11.7, 13.0, -29.4), 'shank': 2.08, 'green_shank': 2.4}
GFCI_TERMS = {'brass': [(22.25, 9.75, -16.5), (22.25, 9.75, 22.0)],      # LINE (bottom), LOAD (top)
              'silver': [(-22.25, 9.75, -16.5), (-22.25, 9.75, 22.0)],
              'green': (-14.2, 6.75, -39.0), 'shank': 2.08, 'green_shank': 2.4}
# A GFCI goes at the first box of each circuit that needs protection: the home run lands on
# LINE, and the cable on to the next box leaves from LOAD, so the receptacles after it are
# protected too. Where LOAD isn't used, the warning tape stays on.
GFCI_BOXES = {'Kitchen_Counter_1', 'Kitchen_Counter_3', 'Kitchen_Fridge', 'Bath_Vanity_GFCI', 'Laundry_Washer'}
WIRE_NUT_AT = (-10.0, 46.0, -18.0)       # switch boxes: where the spliced whites sit (device mm)
HOOK_TURN = 270.0                         # degrees of wrap round each screw
LEAD = 7.0                                # straight bare lead into each hook (mm)
MATS['nut'] = simple_material('Wire_Nut', (0.78, 0.10, 0.07), 0.0, 0.4)

dev_col = sub_collection('Devices')
rec_asset = load_asset('tr270_blockout.py', 'Eaton_TR270_Blockout')
sw_asset = load_asset('toggle_switch.py', 'Toggle_Switch_Blockout')
gfci_asset = load_asset('gfci.py', 'GFCI_Receptacle', ANIMATE=False)   # static in the house
tape_asset = bpy.data.collections['GFCI_Load_Tape']


def device_matrix(info):
    """Device frame: X to the right as you face the wall, Y into the wall, Z up; origin at
    the box front centre (the drywall line)."""
    w, face, uc, h, out = info['wall'], info['face'], info['uc'], info['h'], info['out']
    y_axis = -out
    x_axis = y_axis.cross(UP)
    v_front = (STUD_W + DRYWALL) if face else -DRYWALL
    pos = Vector(w.world(uc, v_front, h)) * IN
    rot = Matrix((x_axis, y_axis, UP)).transposed().to_4x4()
    return Matrix.Translation(pos) @ rot


def revolve_part(name, profile, base_in, axis, mat, seg=16):
    """(radius, length) profile in inches spun round `axis` (a world direction) from base."""
    rot = axis.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector((r * math.cos(math.tau * i / seg), r * math.sin(math.tau * i / seg), h)))
              for i in range(seg)] for r, h in profile]
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.transform(bm, matrix=Matrix.Translation(base_in * IN) @ rot @ Matrix.Scale(IN, 4), verts=bm.verts[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(MATS[mat])
    obj = bpy.data.objects.new(name, mesh)
    wire_col.objects.link(obj)
    return obj


def land(name, start, M, hook_c, shank, cu_r, ins_r, ins_mat):
    """One conductor from its jacket exit `start` (world inches) down and onto a screw:
    insulated run, a short bare lead, then a clockwise hook round the shank."""
    to_w = lambda p_mm: (M @ (Vector(p_mm) * 0.001)) / IN
    xdir = M.col[0].xyz.normalized()
    side = 1 if hook_c[0] > 0 else -1
    R = shank + cu_r / MM_IN
    h0 = Vector(hook_c) + Vector((0, R, 0))                     # top of the hook, on the deep side
    q = h0 + Vector((0, LEAD, 0))
    qi = q + Vector((-side * 3.0, 6.0, 0))
    run = fillet([start, start - UP * 0.8, to_w(qi)], 0.6)
    if ins_mat:
        sweep('Wire_%s' % name, run, ins_r, ins_r, lambda i, T: UP, ins_mat, seg=8)
        bare = [to_w(qi), to_w(q), to_w(h0)]
    else:
        bare = run + [to_w(q), to_w(h0)]
    n = 14
    for k in range(1, n + 1):                                    # clockwise as seen from the screw head
        th = -side * math.radians(HOOK_TURN) * k / n
        bare.append(to_w(Vector(hook_c) + Vector((0, R * math.cos(th), R * math.sin(th)))))
    sweep('Wire_Bare_%s' % name, bare, cu_r, cu_r, lambda i, T: xdir, 'copper', seg=8)


def splice(name, starts, M, ins_r):
    """Whites spliced under a wire nut tucked in the back of a switch box."""
    to_w = lambda p_mm: (M @ (Vector(p_mm) * 0.001)) / IN
    nut = to_w(WIRE_NUT_AT)
    for i, s0 in enumerate(starts):
        sweep('Wire_ins_white_%s_%d' % (name, i), fillet([s0, s0 - UP * 0.8, nut + UP * 0.25], 0.6),
              ins_r, ins_r, lambda i_, T: UP, 'ins_white', seg=8)
    revolve_part('WireNut_' + name, [(0.20, 0), (0.24, 0.12), (0.19, 0.55), (0.07, 0.68), (0.0, 0.70)],
                 nut + UP * 0.32, -UP, 'nut')


installed = 0
for bname, info in BOX_INFO.items():
    if bname in ('Laundry_Dryer', 'Kitchen_Range'):    # the 14-30R and 14-50R are installed below
        continue
    M = device_matrix(info)
    is_switch = 'Switch' in bname
    is_gfci = bname in GFCI_BOXES
    kind = 'Switch_' if is_switch else ('GFCI_' if is_gfci else 'Receptacle_')
    obj = bpy.data.objects.new(kind + bname, None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = sw_asset if is_switch else (gfci_asset if is_gfci else rec_asset)
    obj.empty_display_size = 0.04
    obj.matrix_world = M
    dev_col.objects.link(obj)
    installed += 1
    terms = SWITCH_TERMS if is_switch else (GFCI_TERMS if is_gfci else RECEPTACLE_TERMS)
    if is_gfci and len(BOX_ENDS.get(bname, [])) < 2:     # LOAD unused: tape stays on
        tape = bpy.data.objects.new('GFCI_Tape_' + bname, None)
        tape.instance_type, tape.instance_collection = 'COLLECTION', tape_asset
        tape.matrix_world = M
        dev_col.objects.link(tape)
    whites = []
    for k, (cname, gauge, end) in enumerate(BOX_ENDS.get(bname, [])):
        wdt, thk, _, r_ins, r_bare = NM[gauge]
        top = Vector((end['xy'][0], end['xy'][1], end['z_end'] - 0.02))
        out = end['out']
        s_black, s_bare, s_white = top - out * (wdt / 4), top, top + out * (wdt / 4)
        slot = min(k, 1)
        land('%s_%d_black' % (bname, k), s_black, M, terms['brass'][slot], terms['shank'], r_ins * 0.55, r_ins, 'ins_black')
        land('%s_%d_ground' % (bname, k), s_bare, M, terms['green'], terms['green_shank'], r_bare, None, None)
        if is_switch:
            whites.append(s_white)
        else:
            land('%s_%d_white' % (bname, k), s_white, M, terms['silver'][slot], terms['shank'], r_ins * 0.55, r_ins, 'ins_white')
    if whites:
        splice(bname, whites, M, NM[BOX_ENDS[bname][0][1]][3])
print('Installed %d devices (%d GFCIs).' % (installed, len(GFCI_BOXES & set(BOX_INFO))))


# --- 240 V receptacles: dryer and range ------------------------------------------------------------
# A NEMA 14-30R (30 A, dryer) and a 14-50R (50 A, range) -- both receptacle_14_30.py, same body --
# in 4" square boxes, fed by 10/3 and 6/3 with ground and wired from the back: black -> X,
# red -> Y, white -> W, bare -> G. The stacked laundry center (laundry_center.py) stands in front
# of the dryer's, facing the bifold; the range (range_30.py) stands against the kitchen's west
# wall over the range's. Both are plugged in.
REC1430_TERMS = {'ins_black': (15.0, 30.6, 16.0), 'ins_red': (-15.0, 30.6, 16.0),       # device mm: x, back face, z (X right, Y left)
                 'ins_white': (-15.0, 30.6, -16.0), 'copper': (15.0, 30.6, -16.0)}
REC1430_FACE_Y = -0.6 - 9.0           # its face, in front of its plate (device mm)
UNIT_X = ((14.05 + T) * 12 + 17.33 * 12) / 2   # laundry center's centre across the closet (plan inches)
UNIT_BACK_GAP = 3.7                   # receptacle face to the unit's back (room for the plug, cord and vent)
RANGE_BACK_GAP = 1.0                  # range's back panel to the drywall (the cord runs up in this gap)


def install_240(box, asset, label):
    """Hangs the receptacle in `box` and lands the cable's four conductors on its back terminals."""
    M = device_matrix(BOX_INFO[box])
    dev = bpy.data.objects.new('Receptacle_%s_%s' % (label, box), None)
    dev.instance_type, dev.instance_collection = 'COLLECTION', asset
    dev.matrix_world = M
    dev_col.objects.link(dev)
    to_w = lambda p_mm: (M @ (Vector(p_mm) * 0.001)) / IN
    for k, (cname, gauge, end) in enumerate(BOX_ENDS.get(box, [])):
        wdt, thk, _, r_ins, r_bare = NM[gauge]
        top = Vector((end['xy'][0], end['xy'][1], end['z_end'] - 0.02))
        out = end['out']
        for key, off in (('ins_black', -3 * wdt / 8), ('ins_red', -wdt / 8), ('copper', wdt / 8), ('ins_white', 3 * wdt / 8)):
            tx, ty, tz = REC1430_TERMS[key]
            hole_in = to_w((tx, ty - 4.0, tz))
            behind = to_w((tx, ty + 9.0, tz))
            s0 = top + out * off
            pts = fillet([s0, s0 - UP * 1.0, behind + UP * 0.9, behind, hole_in], 0.5)
            r = r_bare if key == 'copper' else r_ins
            sweep('Wire_%s_%s_%d' % (key, box, k), pts, r, r, lambda i, T_: UP, key, seg=8)
    return M


rec1430_asset = load_asset('receptacle_14_30.py', 'Receptacle_14_30R')
rec1450_asset = load_asset('receptacle_14_30.py', 'Receptacle_14_50R', RATING='14-50')
M = install_240('Laundry_Dryer', rec1430_asset, '14-30R')

# Laundry center: rotated to face north (the bifold), back toward the receptacle.
face_w = Vector(M @ (Vector((0, REC1430_FACE_Y, 0)) * 0.001)) / IN       # receptacle face centre, world inches
unit_back_plan = -face_w.y - UNIT_BACK_GAP                              # plan y of the unit's back
unit_front_plan = unit_back_plan - 30.88
unit_M = Matrix.Translation(Vector((UNIT_X, -unit_front_plan, 0)) * IN) @ Matrix.Rotation(math.pi, 4, 'Z')
local = unit_M.inverted() @ (face_w * IN) / IN                          # receptacle face in the unit's own inches
plug_at = (local.x, local.y - 0.5 - 30.88, local.z)                     # plug face sits on the receptacle face
laundry_asset = load_asset('laundry_center.py', 'Laundry_Center', ANIMATE=False, ACCESS_OPEN=False, PLUG_AT=plug_at)
unit = bpy.data.objects.new('Laundry_Center', None)
unit.instance_type, unit.instance_collection = 'COLLECTION', laundry_asset
unit.matrix_world = unit_M
dev_col.objects.link(unit)
print('Installed the 14-30R and the laundry center (plug at %.1f, %.1f, %.1f in, unit-local).' % plug_at)

# Range: back to the west wall, facing east into the kitchen, cord plugged into the 14-50R.
M = install_240('Kitchen_Range', rec1450_asset, '14-50R')
RANGE_D = 27.875
face_w = Vector(M @ (Vector((0, REC1430_FACE_Y, 0)) * 0.001)) / IN
range_M = (Matrix.Translation(Vector(((T * 12 + DRYWALL) + RANGE_BACK_GAP + RANGE_D, -RANGE_AT * 12, 0)) * IN)
           @ Matrix.Rotation(math.pi / 2, 4, 'Z'))                     # range +Y (its back) -> west
local = range_M.inverted() @ (face_w * IN) / IN
range_plug = (local.x, local.y - 0.5 - RANGE_D, local.z)
range_asset = load_asset('range_30.py', 'Range_30', ANIMATE=False, ACCESS_OPEN=False, PLUG_AT=range_plug)
rng = bpy.data.objects.new('Range', None)
rng.instance_type, rng.instance_collection = 'COLLECTION', range_asset
rng.matrix_world = range_M
dev_col.objects.link(rng)
print('Installed the 14-50R and the range (plug at %.1f, %.1f, %.1f in, range-local).' % range_plug)


# --- Drywall ------------------------------------------------------------------------------------------
# 1/2" board on the walls in 4x12 sheets hung horizontally (top row tight to the ceiling, bottom
# row cut to fit, butt joints on a stud and staggered between rows); 5/8" on the ceiling, across
# the trusses with butts on a truss. Every sheet is cut round the openings, boxes and panel.
# The bath gets moisture-resistant board.
WALL_BOARD_T = 0.5
CEIL_BOARD_T = 0.625
SHEET = (144.0, 48.0)            # 4x12
FLOOR_GAP = 0.5                  # off the slab
JOINT_GAP = 0.0625               # between sheets
BOX_CUT = (2.45, 3.9)            # cutout round each box (the box plus a little)
PANEL_CUT_MARGIN = 0.25
MIN_PIECE = 16.0                 # don't leave a sliver smaller than this at the end of a row
BATH = ((20.85 + T) * 12, (HOUSE_W - T) * 12, (11.25 + T) * 12, 16.46 * 12)   # x0, x1, y0, y1 (plan inches)


def drywall_material(name, paper, flecks):
    mat, nt, bsdf = _new_material(name, paper)
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    n = nt.nodes.new('ShaderNodeTexNoise')            # faint paper mottling
    n.inputs['Scale'].default_value = 40.0
    n.inputs['Detail'].default_value = 6
    fine = nt.nodes.new('ShaderNodeTexNoise')         # paper fibre
    fine.inputs['Scale'].default_value = 3000.0
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*flecks, 1)
    ramp.color_ramp.elements[1].color = (*paper, 1)
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[1].position = 0.6
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.05
    bump.inputs['Distance'].default_value = 0.0002
    L(coord.outputs['Object'], n.inputs['Vector'])
    L(coord.outputs['Object'], fine.inputs['Vector'])
    L(n.outputs['Fac'], ramp.inputs['Fac'])
    L(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    L(fine.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.92
    return mat


MATS['drywall'] = drywall_material('Drywall', (0.87, 0.87, 0.85), (0.80, 0.80, 0.78))
MATS['drywall_mr'] = drywall_material('Drywall_MoistureResistant', (0.62, 0.55, 0.72), (0.56, 0.50, 0.66))

dw_col = sub_collection('Drywall')
dw_walls = sub_collection('Drywall_Walls', dw_col)
dw_ceil = sub_collection('Drywall_Ceiling', dw_col)


def block(name, col, lo, hi, mat):
    """Axis-aligned slab between world-inch corners."""
    lo, hi = Vector(map(min, lo, hi)), Vector(map(max, lo, hi))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((lo[i] + hi[i]) / 2 + v.co[i] * (hi[i] - lo[i]) for i in range(3))) * IN
    mesh = bpy.data.meshes.new(name + '_Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS[mat])
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    return obj


def cut_holes(obj, cutters):
    if not cutters:
        return obj
    for c in cutters:
        m = obj.modifiers.new('Cut', 'BOOLEAN')
        m.operation, m.solver, m.object = 'DIFFERENCE', 'EXACT', c
    baked = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    old = obj.data
    obj.modifiers.clear()
    obj.data = baked
    baked.name = obj.name + '_Mesh'
    bpy.data.meshes.remove(old)
    for c in cutters:
        bpy.data.objects.remove(c, do_unlink=True)
    return obj


def overlaps(a0, a1, b0, b1):
    return a0 < b1 - 0.01 and b0 < a1 - 0.01


def face_runs(w, face):
    """Spans (u0, u1 inches) of a wall face, with the bands where other walls meet it removed."""
    c = w.face + (T if face else 0.0)              # the face's plan line (feet)
    d = 1 if face else -1
    cuts = []
    for q in walls:
        if q is w or q.axis == w.axis:
            continue
        on_side = (q.start <= c + 0.05 and q.end > c + 0.05) if d > 0 else (q.start < c - 0.05 and q.end >= c - 0.05)
        if on_side:
            cuts.append((q.face * 12, (q.face + T) * 12))
    runs, u = [], w.start * 12
    for a, b in sorted(cuts) + [(w.end * 12, w.end * 12)]:
        if a - u > 1.0:
            runs.append((u, min(a, w.end * 12)))
        u = max(u, b)
    return runs


def stud_centres(w):
    return sorted({round((m[0] + m[1]) / 2, 3) for m in w.members
                   if m[4] in ('Stud', 'King', 'End', 'Backer') and m[2] <= PLATE_T + 0.01})


def breaks(u0, u1, first_max, studs):
    """Sheet ends along a run: each sheet as long as allowed, its butt joint on a stud centre."""
    cuts, u, limit = [u0], u0, first_max
    while u1 - u > limit:
        ok = [s for s in studs if u + MIN_PIECE < s <= u + limit and u1 - s >= MIN_PIECE]
        nxt = max(ok) if ok else u + limit
        cuts.append(nxt)
        u, limit = nxt, SHEET[0]
    cuts.append(u1)
    return list(zip(cuts, cuts[1:]))


def in_bath(px, py):
    x0, x1, y0, y1 = BATH
    return x0 <= px <= x1 and y0 <= py <= y1


wall_top = WALL_TOP - CEIL_BOARD_T
sheet_count = 0
EXTERIOR_ROOM_FACE = {'North': 1, 'South': 0, 'West': 1, 'East': 0}
for w in walls:
    faces = [EXTERIOR_ROOM_FACE[w.name]] if w.exterior else [0, 1]
    studs = stud_centres(w)
    for face in faces:
        v0, v1 = ((-WALL_BOARD_T, 0.0) if face == 0 else (STUD_W, STUD_W + WALL_BOARD_T))
        holes = [(a * 12, b * 12, (0.0 if kind == 'door' else sill), RO_HEAD) for a, b, kind, sill in w.openings]
        for bname, info in BOX_INFO.items():
            if info['wall'] is w and info['face'] == face:
                bw, bh = (BOX_CUT if info.get('half', BOX_HALF) == BOX_HALF
                          else (2 * info['half'][0] + 0.2, 2 * info['half'][1] + 0.2))
                holes.append((info['uc'] - bw / 2, info['uc'] + bw / 2, info['h'] - bh / 2, info['h'] + bh / 2))
        if w is pwall and face == p_face:
            mgn = PANEL_CUT_MARGIN
            holes.append((p_uc - PW / 2 - mgn, p_uc + PW / 2 + mgn, pz0 - mgn, pz1 + mgn))
        rows = [(wall_top - SHEET[1], wall_top, SHEET[0]), (FLOOR_GAP, wall_top - SHEET[1], SHEET[0] / 2 + 24)]
        for r, (z0, z1, first) in enumerate(rows):
            for u0, u1 in face_runs(w, face):
                for k, (a, b) in enumerate(breaks(u0, u1, first, studs)):
                    a2, b2 = a + (JOINT_GAP / 2 if a > u0 else 0), b - (JOINT_GAP / 2 if b < u1 else 0)
                    z0g = z0 + (JOINT_GAP / 2 if r == 1 else 0)
                    z1g = z1 - (JOINT_GAP / 2 if r == 1 else 0)
                    centre = Vector(w.world((a2 + b2) / 2, v1 + 2 if face else v0 - 2, 0))
                    mat = 'drywall_mr' if in_bath(centre.x, -centre.y) else 'drywall'
                    name = 'DW_%s_%s_R%d_%02d' % (w.name, 'B' if face else 'A', r + 1, k + 1)
                    sheet = block(name, dw_walls, w.world(a2, v0, z0g), w.world(b2, v1, z1g), mat)
                    cutters = [block('Cutter', dw_walls, w.world(max(h0, a2) - (0 if h0 > a2 else 1), v0 - 1, max(hz0, z0g) - (0 if hz0 > z0g else 1)),
                                     w.world(min(h1, b2) + (0 if h1 < b2 else 1), v1 + 1, min(hz1, z1g) + (0 if hz1 < z1g else 1)), 'drywall')
                               for h0, h1, hz0, hz1 in holes if overlaps(h0, h1, a2, b2) and overlaps(hz0, hz1, z0g, z1g)]
                    full = any(h0 <= a2 and h1 >= b2 and hz0 <= z0g and hz1 >= z1g for h0, h1, hz0, hz1 in holes)
                    if full:
                        for c in cutters:
                            bpy.data.objects.remove(c, do_unlink=True)
                        bpy.data.objects.remove(sheet, do_unlink=True)
                        continue
                    cut_holes(sheet, cutters)
                    sheet_count += 1

# Ceiling: sheets run east-west (across the trusses), butts on a truss, rows staggered;
# each cut round the partition walls it crosses.
cx0, cx1, cy0, cy1 = T * 12, (HOUSE_W - T) * 12, T * 12, (HOUSE_D - T) * 12
truss_centres = [x for x in xs]
part_bands = []
for w in walls:
    if w.exterior:
        continue
    if w.axis == 'x':
        part_bands.append((w.start * 12, w.end * 12, w.face * 12, (w.face + T) * 12))
    else:
        part_bands.append((w.face * 12, (w.face + T) * 12, w.start * 12, w.end * 12))
y, row = cy0, 0
while y < cy1 - 0.5:
    y1 = min(y + SHEET[1], cy1)
    first = SHEET[0] if row % 2 == 0 else SHEET[0] / 2 + 24
    for k, (a, b) in enumerate(breaks(cx0, cx1, first, truss_centres)):
        a2, b2 = a + (JOINT_GAP / 2 if a > cx0 else 0), b - (JOINT_GAP / 2 if b < cx1 else 0)
        ya, yb = y + (JOINT_GAP / 2 if y > cy0 else 0), y1 - (JOINT_GAP / 2 if y1 < cy1 else 0)
        mat = 'drywall_mr' if in_bath((a2 + b2) / 2, (ya + yb) / 2) else 'drywall'
        sheet = block('DW_Ceiling_R%d_%02d' % (row + 1, k + 1), dw_ceil,
                      (a2, -ya, wall_top), (b2, -yb, WALL_TOP), mat)
        cutters = [block('Cutter', dw_ceil, (px0, -py0, wall_top - 1), (px1, -py1, WALL_TOP + 1), 'drywall')
                   for px0, px1, py0, py1 in part_bands if overlaps(px0, px1, a2, b2) and overlaps(py0, py1, ya, yb)]
        cut_holes(sheet, cutters)
        sheet_count += 1
    y, row = y1, row + 1
print('Hung %d drywall sheets.' % sheet_count)


# --- Wall sheathing, Hardie siding and trim ---------------------------------------------------------
# 7/16" OSB on the outside of the exterior walls and up the gable ends: 4x8 sheets laid
# horizontally, butts on a stud, rows staggered half a sheet, cut round every opening. Over it,
# fiber-cement (Hardie-style) lap siding: 8-1/4" planks at 7" exposure, 12' long with butt joints
# on studs and staggered course to course, over a starter strip. 5/4 trim at the corners, round
# the windows and doors, a frieze board under the eaves and rake boards up the gables; the
# siding butts into the trim. Each face frame: u along the wall (plan feet*12), z up, d outward.
WALL_OSB_T = 0.4375              # 7/16" wall sheathing
WALL_OSB_SHEET = (96.0, 48.0)
WALL_OSB_GAP = 0.125
SHEATH_BOTTOM = -0.75            # sheathing laps down over the slab edge this far
GABLE_TOP_GAP = 3.5              # gable sheathing stops this far under the roof plane (lookouts run there)
EAVE_TOP = CHORD_TOP - 1.0       # eave-wall sheathing and frieze stop here, under the truss tails
SIDING_PLANK = (144.0, 8.25, 0.3125)   # 12' long, width, thickness
SIDING_EXPOSURE = 7.0
SIDING_BOTTOM = -1.0             # first course's bottom edge (clears the porch and patio slabs)
SIDING_JOINT_GAP = 0.0625
SIDING_STAGGER = 5               # each course's joints shift this many stud bays from the last
STARTER_STRIP = 1.5              # height of the strip that kicks the first course out
TRIM_T = 1.0                     # 5/4 trim boards
CORNER_TRIM_W = 3.5
CASING_W = 3.5                   # round the windows and doors
FRIEZE_W = 5.5
RAKE_TRIM_W = 5.5
SIDING_COLOR = (0.20, 0.235, 0.25)     # painted siding (linear RGB)
TRIM_COLOR = (0.80, 0.80, 0.78)


def painted_material(name, color, grain):
    """Factory-painted fiber cement; `grain` adds the embossed cedar texture (streaks run along u)."""
    mat, nt, bsdf = _new_material(name, color)
    L = nt.links.new
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 0.6
    coord = nt.nodes.new('ShaderNodeTexCoord')
    squash = nt.nodes.new('ShaderNodeVectorMath')
    squash.operation = 'MULTIPLY'
    squash.inputs[1].default_value = (0.08, 0.08, 1.0) if grain else (1.0, 1.0, 1.0)
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.inputs['Scale'].default_value = 260.0 if grain else 900.0
    n.inputs['Detail'].default_value = 8
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.35 if grain else 0.08
    bump.inputs['Distance'].default_value = 0.0004
    L(coord.outputs['Object'], squash.inputs[0])
    L(squash.outputs['Vector'], n.inputs['Vector'])
    L(n.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


MATS['siding'] = painted_material('Hardie_Siding', SIDING_COLOR, True)
MATS['trim'] = painted_material('Hardie_Trim', TRIM_COLOR, False)

ext_col = sub_collection('Exterior')
wall_osb_col = sub_collection('Wall_Sheathing', ext_col)
siding_col = sub_collection('Siding', ext_col)
W12, D12 = HOUSE_W * 12, HOUSE_D * 12
OT = WALL_OSB_T
FACES = {   # to_world, sheathing u range, openings
    'North': (lambda u, z, d: (u, d, z), (-OT, W12 + OT)),
    'South': (lambda u, z, d: (u, -(D12 + d), z), (-OT, W12 + OT)),
    'West': (lambda u, z, d: (-d, -u, z), (0.0, D12)),
    'East': (lambda u, z, d: (W12 + d, -u, z), (0.0, D12)),
}


def gable_top(y):
    return roof_plane(y) - GABLE_TOP_GAP


def outline(name, u0, u1, z0, drop=0.0):
    """Counter-clockwise outline of a face: eave walls a rectangle, gable ends a pentagon."""
    if name in ('North', 'South'):
        return rect_poly(u0, u1, z0, EAVE_TOP - drop)
    return [(u0, z0), (u1, z0), (u1, gable_top(u1) - drop), (RIDGE_Y, gable_top(RIDGE_Y) - drop),
            (u0, gable_top(u0) - drop)]


osb_count = plank_count = 0
for name, (to_w, (u0, u1)) in FACES.items():
    ops = [(a * 12, b * 12, kind, sill) for a, b, kind, sill in EXT_OPENINGS[name]]
    shape = outline(name, u0, u1, SHEATH_BOTTOM)
    z_max = max(p[1] for p in shape)

    # OSB sheets, each its own object, cut round the openings.
    row, z = 0, SHEATH_BOTTOM
    while z < z_max - 0.5:
        off = (WALL_OSB_SHEET[0] / 2) if row % 2 else 0.0
        k = math.floor((u0 - off) / WALL_OSB_SHEET[0])
        while off + k * WALL_OSB_SHEET[0] < u1 - 0.5:
            a, b = max(u0, off + k * WALL_OSB_SHEET[0]), min(u1, off + (k + 1) * WALL_OSB_SHEET[0])
            k += 1
            g = WALL_OSB_GAP / 2
            poly = clip_convex(rect_poly(a + (g if a > u0 else 0), b - (g if b < u1 else 0),
                                         z + (g if row else 0), z + WALL_OSB_SHEET[1] - g), shape)
            if not poly:
                continue
            pc = Pieces()
            pc.add(poly, to_w, flat(0.0), OT)
            sheet = pc.build('WallOSB_%s_R%d_%02d' % (name, row + 1, k), wall_osb_col, ['osb'])
            pu = [p[0] for p in poly]
            pz = [p[1] for p in poly]
            holes = [(oa, ob, (SHEATH_BOTTOM - 1 if kind == 'door' else sill), RO_HEAD) for oa, ob, kind, sill in ops]
            cutters = [block('Cutter', wall_osb_col, to_w(h0, hz0, -1), to_w(h1, hz1, OT + 1), 'osb')
                       for h0, h1, hz0, hz1 in holes if overlaps(h0, h1, min(pu), max(pu)) and overlaps(hz0, hz1, min(pz), max(pz))]
            cut_holes(sheet, cutters)
            osb_count += 1
        z += WALL_OSB_SHEET[1]
        row += 1

    # Trim: corner boards, casings, frieze or rake boards.
    trim = Pieces()
    on_osb = flat(OT)
    if name in ('North', 'South'):
        c0, c1 = -(OT + TRIM_T), W12 + OT + TRIM_T               # these boards lap the gable-end boards
        s0, s1 = c0 + CORNER_TRIM_W, c1 - CORNER_TRIM_W
        top = EAVE_TOP - FRIEZE_W
        trim.add(rect_poly(c0, c1, EAVE_TOP - FRIEZE_W, EAVE_TOP), to_w, on_osb, TRIM_T)
        for a, b in ((c0, s0), (s1, c1)):
            trim.add(rect_poly(a, b, SIDING_BOTTOM, top), to_w, on_osb, TRIM_T)
    else:
        c0, c1 = -OT, D12 + OT                                   # butt in behind the eave-wall boards
        s0, s1 = c0 + CORNER_TRIM_W - TRIM_T, c1 - CORNER_TRIM_W + TRIM_T
        hb = RAKE_TRIM_W / COS
        for a, b in ((c0, RIDGE_Y), (RIDGE_Y, c1)):
            trim.add([(a, gable_top(a) - hb), (b, gable_top(b) - hb), (b, gable_top(b)), (a, gable_top(a))],
                     to_w, on_osb, TRIM_T)
        for a, b in ((c0, s0), (s1, c1)):
            trim.add(clip_convex(rect_poly(a, b, SIDING_BOTTOM, z_max), outline(name, c0, c1, SIDING_BOTTOM, hb)),
                     to_w, on_osb, TRIM_T)
    blocked = []
    for a, b, kind, sill in ops:
        cw = CASING_W
        zb = SIDING_BOTTOM if kind == 'door' else sill
        trim.add(rect_poly(a - cw, b + cw, RO_HEAD, RO_HEAD + cw), to_w, on_osb, TRIM_T)       # head
        trim.add(rect_poly(a - cw, a, zb, RO_HEAD), to_w, on_osb, TRIM_T)
        trim.add(rect_poly(b, b + cw, zb, RO_HEAD), to_w, on_osb, TRIM_T)
        if kind == 'window':
            trim.add(rect_poly(a - cw, b + cw, sill - cw, sill), to_w, on_osb, TRIM_T)          # sill
        blocked.append((a - cw, b + cw, (SIDING_BOTTOM - 10 if kind == 'door' else sill - cw), RO_HEAD + cw))
    trim.build('Trim_' + name, siding_col, ['trim'])

    # Siding: starter strip, then the courses, each plank tilted to rest on the one below.
    pw, ph, pt = SIDING_PLANK
    lift = pt * ph / SIDING_EXPOSURE
    region = outline(name, s0, s1, SIDING_BOTTOM, 0.0 if name in ('North', 'South') else RAKE_TRIM_W / COS)
    if name in ('North', 'South'):
        region = rect_poly(s0, s1, SIDING_BOTTOM, EAVE_TOP - FRIEZE_W)
    top_z = max(p[1] for p in region)
    sid = Pieces()
    for r in rect_minus([(s0, s1, SIDING_BOTTOM, SIDING_BOTTOM + STARTER_STRIP)], blocked):
        sid.add(rect_poly(*r), to_w, on_osb, pt)
    i = 0
    while SIDING_BOTTOM + i * SIDING_EXPOSURE < top_z - 0.25:
        zb = SIDING_BOTTOM + i * SIDING_EXPOSURE
        zt = zb + ph
        back = lambda u, z, zb=zb, zt=zt: OT + lift * max(0.0, (zt - z) / (zt - zb))
        off = (i * SIDING_STAGGER % 9) * STUD_OC
        k = math.floor((s0 - off) / pw)
        while off + k * pw < s1:
            a, b = max(s0, off + k * pw), min(s1, off + (k + 1) * pw)
            k += 1
            a += SIDING_JOINT_GAP / 2 if a > s0 else 0
            b -= SIDING_JOINT_GAP / 2 if b < s1 else 0
            for r in rect_minus([(a, b, zb, zt)], blocked):
                poly = clip_convex(rect_poly(*r), region)
                if poly:
                    sid.add(poly, to_w, back, pt)
                    plank_count += 1
        i += 1
    sid.build('Siding_' + name, siding_col, ['siding'])
print('Sheathed the walls (%d OSB sheets) and sided them (%d plank pieces).' % (osb_count, plank_count))


# --- Insulation: exterior walls only --------------------------------------------------------------
# Kraft-faced R-13 fiberglass batts filling every stud cavity of the exterior walls (full 3-1/2"),
# facing on the room side. Cavities come straight from the framing: wherever there's no board and
# no opening. Batts are cut round the boxes and the panel on those walls.
BATT_FACING_T = 0.03
BATT_MIN = 0.75                 # skip slivers narrower than this
BATT_COLOR = (0.80, 0.62, 0.22)
KRAFT_COLOR = (0.42, 0.26, 0.11)


def batt_material():
    mat, nt, bsdf = _new_material('Fiberglass_Batt', BATT_COLOR)
    L = nt.links.new
    coord = nt.nodes.new('ShaderNodeTexCoord')
    fluff = nt.nodes.new('ShaderNodeTexNoise')
    fluff.inputs['Scale'].default_value = 150.0
    fluff.inputs['Detail'].default_value = 10
    fluff.inputs['Roughness'].default_value = 0.7
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (BATT_COLOR[0] * 0.7, BATT_COLOR[1] * 0.65, BATT_COLOR[2] * 0.6, 1)
    ramp.color_ramp.elements[1].color = (*BATT_COLOR, 1)
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.8
    bump.inputs['Distance'].default_value = 0.004
    L(coord.outputs['Object'], fluff.inputs['Vector'])
    L(fluff.outputs['Fac'], ramp.inputs['Fac'])
    L(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    L(fluff.outputs['Fac'], bump.inputs['Height'])
    L(bump.outputs['Normal'], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 1.0
    return mat


MATS['batt'] = batt_material()
MATS['kraft'] = simple_material('Kraft_Facing', KRAFT_COLOR, 0.0, 0.8, (0.1, 300.0))
insul_col = sub_collection('Insulation')
batt_count = 0
for w in walls:
    if not w.exterior:
        continue
    s, e = w.start * 12, w.end * 12
    top = PLATE_T + STUD_LEN
    solids = [(m[0], m[1], m[2], m[3]) for m in w.members]
    solids += [(a * 12, b * 12, (0.0 if kind == 'door' else sill), RO_HEAD) for a, b, kind, sill in w.openings]
    edges = sorted({s, e} | {x for m in solids for x in m[:2] if s <= x <= e})
    cells, open_ = [], {}
    for ua, ub in zip(edges, edges[1:]):
        if ub - ua < 0.01:
            continue
        mid = (ua + ub) / 2
        free = [(PLATE_T, top)]
        for m in solids:
            if m[0] < mid < m[1]:
                free = [r for f in free for r in ((f[0], min(f[1], m[2])), (max(f[0], m[3]), f[1])) if r[1] - r[0] > 0.01]
        nxt = {}
        for f in free:
            key = (round(f[0], 3), round(f[1], 3))
            if key in open_ and abs(open_[key][1] - ua) < 0.01:
                open_[key][1] = ub
                nxt[key] = open_[key]
            else:
                cell = [ua, ub, f[0], f[1]]
                cells.append(cell)
                nxt[key] = cell
        open_ = nxt
    room = EXTERIOR_ROOM_FACE[w.name]
    v_face = (STUD_W - BATT_FACING_T, STUD_W) if room else (0.0, BATT_FACING_T)
    v_batt = (0.0, STUD_W - BATT_FACING_T) if room else (BATT_FACING_T, STUD_W)
    to_w = lambda u, z, v, w=w: w.world(u, v, z)
    pc = Pieces()
    for u0_, u1_, z0, z1 in cells:
        if u1_ - u0_ < BATT_MIN or z1 - z0 < BATT_MIN:
            continue
        pc.add(rect_poly(u0_, u1_, z0, z1), to_w, flat(v_batt[0]), v_batt[1] - v_batt[0], slot=0)
        pc.add(rect_poly(u0_, u1_, z0, z1), to_w, flat(v_face[0]), v_face[1] - v_face[0], slot=1)
        batt_count += 1
    obj = pc.build('Insulation_' + w.name, insul_col, ['batt', 'kraft'])
    cuts = []                                                  # round the boxes: room side, box deep
    for info in BOX_INFO.values():
        if info['wall'] is w:
            bw, bh = info['half']
            vv = (STUD_W - 3.0, STUD_W + 1) if info['face'] else (-1, 3.0)
            cuts.append((info['uc'] - bw - 0.1, info['uc'] + bw + 0.1, vv, info['h'] - bh - 0.1, info['h'] + bh + 0.1))
    if w is pwall:
        cuts.append((p_uc - PW / 2 - 0.1, p_uc + PW / 2 + 0.1, (-1, STUD_W + 1), pz0 - 0.1, pz1 + 0.1))
    cut_holes(obj, [block('Cutter', insul_col, w.world(a, vv[0], z0), w.world(b, vv[1], z1), 'batt')
                    for a, b, vv, z0, z1 in cuts])
print('Insulated the exterior walls: %d batts.' % batt_count)
