"""Build the Rustgrave 3D title hero set in Blender and export it as glTF.

Run (portable Blender 4.2):

    blender -b -P tools/blender/build_forge_hall.py -- --out assets/title3d/forge_hall.glb

Coordinates: the script is written in *Godot* space (1 unit = 1 m, +Y up, the
camera looks down -Z, the bridge deck is y = 0, the knight stands at the origin,
the hall spans x +-16 / z -30..+6). Blender works Z-up, so every vertex goes
through `P()` (x, -z, y) and the glTF exporter converts back to Godot space.

The scene is the forge hall from the 2D reference frame: brick back wall with
arched bays, the overhead catwalk lane with hangers, the riveted bridge with
hazard-striped ends, the left gear/pipe tower, the right machine housing with
the amber arched window, wall pipes, cables and the lava pit below the bridge.

Colour model: a single material, palette colours live in a per-vertex colour
attribute. Godot imports glTF COLOR_0 as *linear* colour, while the rest of the
title kit writes sRGB palette values and lets the engine convert, so this script
converts every palette colour to linear before writing it. Vertex alpha 0 marks
emissive geometry exactly like `TitleKit` does (1 - emissive mask).
"""

import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

# ------------------------------------------------------------------ palette ---


def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def col(hex_or_rgb, emissive=False):
    if isinstance(hex_or_rgb, str):
        h = hex_or_rgb.lstrip("#")
        rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    else:
        rgb = list(hex_or_rgb)
    linear = [srgb_to_linear(c) for c in rgb]
    return (linear[0], linear[1], linear[2], 0.0 if emissive else 1.0)


STEEL_DARK = col("#1B2028")
STEEL = col("#2C333D")
STEEL_MID = col("#3A4451")
STEEL_LIGHT = col("#5A6675")
IRON_RUST = col("#6E3A1E")
RUST = col("#8A4A1E")
RUST_HOT = col("#B5652A")
BRICK = col("#2A2A31")
BRICK_DARK = col("#22232A")
BRICK_WARM = col("#332C2C")
STONE = col("#3A3A42")
AMBER = col("#FF9A3C", emissive=True)
AMBER_HOT = col("#FFC85C", emissive=True)
BLUE_GLASS = col("#5B82B0", emissive=True)
LAMP = col("#FFD08A", emissive=True)
HAZARD = col("#C9A227")
DARK = col("#121014")
BLACK = col("#0A090C")

OBJECTS = []


def P(x, y, z):
    """Godot space -> Blender space."""
    return Vector((x, -z, y))


def new_mesh_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    OBJECTS.append(obj)
    return obj


def apply_colors(mesh, color):
    attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    r, g, b, a = color
    for i in range(len(attr.data)):
        attr.data[i].color = (r, g, b, a)


def bevel(obj, width=0.035):
    if width <= 0.0:
        return
    mod = obj.modifiers.new(name="Bevel", type="BEVEL")
    mod.width = width
    mod.segments = 1
    mod.limit_method = "ANGLE"


# ------------------------------------------------------------------ builders ---


def box(name, size, loc, color, rot=(0.0, 0.0, 0.0), bev=0.035, parent=None):
    """Axis-aligned (or euler-rotated) box; size/loc in Godot space, rot in degrees."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    # Godot (x, y, z) -> Blender (x, -z, y): sizes swap Y/Z the same way.
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[2]
        v.co.z *= size[1]
    bm.to_mesh(me)
    bm.free()
    apply_colors(me, color)
    obj = new_mesh_object(name, me)
    obj.location = P(*loc)
    # rot is authored in Godot terms: X pitch, Y yaw, Z roll in the camera plane.
    obj.rotation_euler = (math.radians(rot[0]), math.radians(-rot[2]), math.radians(-rot[1]))
    bevel(obj, bev)
    if parent is not None:
        obj.parent = parent
    return obj


def cylinder(name, radius, depth, loc, color, axis="Z", bev=0.0, sides=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides,
                          radius1=radius, radius2=radius, depth=depth)
    bm.to_mesh(me)
    bm.free()
    apply_colors(me, color)
    obj = new_mesh_object(name, me)
    obj.location = P(*loc)
    # Blender Z is Godot Y; Godot X/Z cylinders need a rotation.
    if axis == "Y":      # Godot Y (vertical) == Blender Z: no rotation
        obj.rotation_euler = (0.0, 0.0, 0.0)
    elif axis == "Z":    # Godot Z (towards camera) == Blender -Y
        obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    else:                # Godot X == Blender X
        obj.rotation_euler = (0.0, math.radians(90.0), 0.0)
    bevel(obj, bev)
    return obj


def cylinder_between(name, p1, p2, radius, color, sides=10, bev=0.0):
    a = P(*p1)
    b = P(*p2)
    delta = b - a
    length = delta.length
    if length <= 1e-4:
        return None
    mid = (a + b) * 0.5
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides,
                          radius1=radius, radius2=radius, depth=length)
    bm.to_mesh(me)
    bm.free()
    apply_colors(me, color)
    obj = new_mesh_object(name, me)
    obj.location = mid
    obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
    bevel(obj, bev)
    return obj


def gear(name, radius, teeth, depth, loc, color, rot_y=0.0):
    """Tooth-wheel in the Godot X/Y plane (facing the camera along Godot Z)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    inner = radius * 0.72
    hub = radius * 0.22
    steps = teeth * 4
    ring = []
    for i in range(steps):
        t = i / float(steps)
        phase = i % 4
        r = radius if phase in (1, 2) else inner
        ang = t * math.tau
        ring.append(bm.verts.new((math.cos(ang) * r, math.sin(ang) * r, 0.0)))
    bm.faces.new(ring)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # extrude along Blender -Y (Godot Z, towards the camera)
    res = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    verts = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(0.0, -depth, 0.0))
    # hub hole suggestion: a raised hub disc
    bm.to_mesh(me)
    bm.free()
    apply_colors(me, color)
    obj = new_mesh_object(name, me)
    obj.location = P(*loc)
    obj.rotation_euler = (math.radians(90.0), math.radians(rot_y), 0.0)
    return obj


def arch_frame(name, center, width, height, thickness, color, z):
    """A doorway arch: two piers + a stepped semicircle, facing the camera."""
    cx, cy = center
    box(name + "_l", (thickness, height, 0.5), (cx - width * 0.5, cy + height * 0.5, z), color)
    box(name + "_r", (thickness, height, 0.5), (cx + width * 0.5, cy + height * 0.5, z), color)
    segments = 7
    for i in range(segments):
        a0 = math.pi * (i / float(segments))
        mid = math.pi * ((i + 0.5) / float(segments))
        seg_len = width * 0.5 * (math.pi / segments) * 1.15
        x = math.cos(mid) * width * 0.5
        y = cy + height + math.sin(mid) * width * 0.5
        box(name + "_s%d" % i, (seg_len, thickness, 0.5), (cx + x, y, z), color,
            rot=None if False else (0.0, 0.0, math.degrees(-mid) + 90.0))


def emissive_panel(name, size, loc, color):
    return box(name, size, loc, color, bev=0.0)


def chain(name, x, y_top, z, length, color):
    links = max(2, int(length / 0.5))
    for i in range(links):
        y = y_top - 0.25 - 0.5 * i
        size = (0.14, 0.34, 0.06) if i % 2 == 0 else (0.06, 0.34, 0.14)
        box(name + "_%d" % i, size, (x, y, z), color, bev=0.0)


# ------------------------------------------------------------------- groups ---


def build_back_wall():
    g = []
    # brick wall behind everything
    box("BackWall", (33.0, 22.0, 0.8), (0.0, 8.0, -15.6), BRICK_DARK, bev=0.0)
    # brick bands
    for row in range(9):
        y = -1.0 + 1.9 * row
        shade = BRICK if row % 3 else BRICK_WARM
        box("BackBrick_%d" % row, (32.0, 1.5, 0.25), (0.0, y, -15.1), shade, bev=0.0)
    # tall arched bays
    for i, x in enumerate((-11.5, -5.75, 0.0, 5.75, 11.5)):
        box("BackPier%d" % i, (1.3, 15.0, 1.1), (x, 7.0, -14.6), STEEL_DARK, bev=0.05)
        box("BackPierCap%d" % i, (1.9, 0.7, 1.4), (x, 14.4, -14.6), STEEL_MID, bev=0.04)
    box("BackLintel", (32.0, 1.0, 1.2), (0.0, 13.4, -14.6), STEEL_DARK)
    # high windows with cool blue glass
    for i, x in enumerate((-9.0, -3.0, 3.0, 9.0)):
        box("WinFrame%d" % i, (3.4, 4.6, 0.6), (x, 10.4, -14.2), STEEL_MID, bev=0.03)
        emissive_panel("WinGlass%d" % i, (2.8, 4.0, 0.3), (x, 10.4, -13.9), BLUE_GLASS)
        box("WinMullion%d" % i, (0.14, 4.0, 0.4), (x, 10.4, -13.8), STEEL_DARK, bev=0.0)
        box("WinMullionH%d" % i, (2.8, 0.14, 0.4), (x, 10.4, -13.8), STEEL_DARK, bev=0.0)
    # girder network behind the catwalk
    box("GirderA", (32.0, 0.6, 0.5), (0.0, 8.6, -13.4), STEEL_DARK)
    box("GirderB", (32.0, 0.6, 0.5), (0.0, 11.6, -13.0), STEEL)
    for i in range(9):
        x = -14.0 + 3.5 * i
        box("GirderV%d" % i, (0.4, 6.4, 0.4), (x, 9.6, -13.2), STEEL_DARK, bev=0.0)
    return g


def build_catwalk():
    y = 11.15
    z = 2.2
    box("CatDeck", (29.0, 0.4, 2.2), (0.0, y - 0.35, z), STEEL_DARK)
    box("CatCurb", (29.0, 0.3, 0.25), (0.0, y - 0.05, z - 1.05), STEEL_MID)
    # railings
    for side in (-1.0, 1.0):
        zr = z + 0.95 * side
        box("CatRailTop%.0f" % side, (29.0, 0.14, 0.14), (0.0, y + 0.95, zr), STEEL_LIGHT)
        box("CatRailMid%.0f" % side, (29.0, 0.1, 0.1), (0.0, y + 0.5, zr), STEEL_MID)
        for i in range(15):
            x = -13.8 + 1.97 * i
            box("CatPost%d_%.0f" % (i, side), (0.12, 1.1, 0.12), (x, y + 0.45, zr), STEEL_MID, bev=0.0)
    # support hangers up to the roof truss
    for i in range(8):
        x = -13.0 + 3.7 * i
        box("CatHanger%d" % i, (0.18, 3.2, 0.18), (x, y + 1.7, z), STEEL_DARK, bev=0.0)
        box("CatBrace%d" % i, (1.6, 0.16, 0.16), (x + 0.7, y + 2.7, z), STEEL, bev=0.0)
    # chain hangers + lamps (the reference has a whole lane of them)
    for i in range(12):
        x = -12.8 + 2.33 * i
        chain("CatChain%d" % i, x, y - 0.4, z - 0.9, 1.7, STEEL_LIGHT)
        box("CatLamp%d" % i, (0.42, 0.55, 0.42), (x, y - 2.55, z - 0.9), LAMP, bev=0.03)
        box("CatLampCap%d" % i, (0.3, 0.18, 0.3), (x, y - 2.9, z - 0.9), STEEL_DARK, bev=0.0)
    # pipes running along the catwalk
    cylinder_between("CatPipeA", (-14.0, y + 1.4, z - 1.4), (14.0, y + 1.4, z - 1.4), 0.22, IRON_RUST, sides=8)
    cylinder_between("CatPipeB", (-14.0, y + 1.9, z - 1.5), (14.0, y + 1.9, z - 1.5), 0.14, STEEL_MID, sides=8)
    return []


def build_bridge():
    # deck
    box("BridgeDeck", (17.4, 0.55, 7.2), (0.0, -0.28, 0.0), STEEL_DARK, bev=0.05)
    for i in range(9):
        x = -8.0 + 2.0 * i
        box("DeckBand%d" % i, (0.9, 0.58, 7.1), (x, -0.27, 0.0), STEEL, bev=0.03)
    # side beams with rivets
    for zs in (3.55, -3.55):
        box("BridgeBeam%.0f" % zs, (17.4, 0.9, 0.35), (0.0, -0.55, zs), IRON_RUST)
        for i in range(12):
            x = -8.0 + 1.45 * i
            box("Rivet%.0f_%d" % (zs, i), (0.16, 0.16, 0.16), (x, -0.2, zs - 0.2 * (1 if zs > 0 else -1)), STEEL_LIGHT, bev=0.0)
    # railings on both edges
    for zs in (3.3, -3.3):
        box("RailTop%.0f" % zs, (17.4, 0.14, 0.2), (0.0, 1.15, zs), STEEL_LIGHT)
        box("RailMid%.0f" % zs, (17.4, 0.1, 0.14), (0.0, 0.62, zs), STEEL_MID)
        for i in range(10):
            x = -8.1 + 1.8 * i
            box("RailPost%.0f_%d" % (zs, i), (0.16, 1.25, 0.16), (x, 0.55, zs), STEEL_MID, bev=0.0)
            box("RailBase%.0f_%d" % (zs, i), (0.34, 0.18, 0.34), (x, 0.02, zs), STEEL_DARK, bev=0.0)
    # hazard stripes on the bridge ends
    for side in (-1.0, 1.0):
        for k in range(6):
            c = HAZARD if k % 2 == 0 else DARK
            box("Hazard%.0f_%d" % (side, k), (0.55, 0.42, 0.25),
                (7.4 * side + 0.55 * k * side, 0.3, 3.62), c, bev=0.0)
    # understructure
    for i in range(6):
        x = -7.0 + 2.8 * i
        box("UnderRib%d" % i, (0.4, 1.6, 6.8), (x, -1.5, 0.0), STEEL_DARK, bev=0.0,
            rot=(0.0, 0.0, 0.0))
        cylinder_between("SupportPillar%d" % i, (x, -6.2, 0.0), (x, -2.0, 0.0), 0.38, IRON_RUST, sides=8)
    # cross bracing under the deck
    for i in range(5):
        x = -6.0 + 3.0 * i
        cylinder_between("BraceA%d" % i, (x - 2.0, -2.2, -2.6), (x + 2.0, -2.2, 2.6), 0.12, STEEL_MID, sides=6)
        cylinder_between("BraceB%d" % i, (x - 2.0, -2.2, 2.6), (x + 2.0, -2.2, -2.6), 0.12, STEEL_MID, sides=6)
    return []


def build_pit():
    # pit walls below the bridge, and the molten river at the bottom
    box("PitLeft", (0.9, 5.6, 18.0), (-9.2, -3.2, -4.0), BRICK_DARK, bev=0.0)
    box("PitRight", (0.9, 5.6, 18.0), (9.2, -3.2, -4.0), BRICK_DARK, bev=0.0)
    box("PitBack", (18.5, 5.6, 0.9), (0.0, -3.2, -13.0), BRICK_DARK, bev=0.0)
    emissive_panel("Lava", (18.0, 0.1, 17.0), (0.0, -5.45, -4.0), AMBER)
    for i in range(7):
        x = -8.0 + 2.7 * i
        box("LavaRock%d" % i, (1.7, 0.5, 1.3), (x, -5.1, -6.0 + 2.0 * (i % 3)), RUST_HOT, bev=0.03)
    # pipes crossing the pit
    for z in (-1.0, -7.0, -11.0):
        cylinder_between("PitPipe%.0f" % z, (-9.0, -4.2, z), (9.0, -4.2, z), 0.26, STEEL_MID, sides=8)
    return []


def build_gear_tower():
    """Left hero tower from the reference frame: gears, shaft, bearing blocks,
    the big diagonal pipe and the bracket structure up to the catwalk."""
    gx = -10.4
    gy = 7.4
    gz = -6.4
    gear("GearTowerBig", 2.9, 22, 0.55, (gx, gy, gz), RUST)
    gear("GearTowerBig2", 2.65, 20, 0.4, (gx, gy, gz - 0.35), IRON_RUST)
    gear("GearTowerSmall", 1.45, 14, 0.5, (gx + 3.1, gy - 2.3, gz), RUST_HOT)
    gear("GearTowerSmall2", 1.2, 12, 0.4, (gx + 3.1, gy - 2.3, gz - 0.3), IRON_RUST)
    for g in (("GearTowerBig", gx, gy, gz), ("GearTowerSmall", gx + 3.1, gy - 2.3, gz)):
        pass
    # axle + bearing blocks
    cylinder("GearAxle", 0.4, 3.2, (gx, gy, gz - 0.2), STEEL_LIGHT, axis="Z", sides=10)
    box("GearBearing", (1.7, 1.7, 1.2), (gx, gy, gz - 1.4), STEEL_DARK, bev=0.06)
    box("GearBracket", (0.8, 3.4, 0.8), (gx + 0.9, gy - 0.4, gz - 1.9), STEEL_MID)
    box("GearBackPlate", (5.0, 5.0, 0.3), (gx + 1.4, gy - 0.4, gz - 2.4), STEEL, bev=0.03)
    for i in range(5):
        box("GearRib%d" % i, (0.5, 6.4, 0.35), (gx - 1.4 + 1.4 * i, gy - 0.6, gz - 1.6), STEEL)
    # the big diagonal pipe (upper left landmark)
    cylinder_between("BigPipe", (-16.5, 8.6, -1.6), (-5.2, 12.8, -2.4), 1.0, STEEL, sides=12, bev=0.0)
    cylinder_between("BigPipeCapA", (-16.9, 8.45, -1.6), (-16.5, 8.6, -1.6), 1.1, IRON_RUST, sides=12)
    cylinder_between("BigPipeCapB", (-5.2, 12.8, -2.4), (-4.8, 12.95, -2.4), 1.1, IRON_RUST, sides=12)
    cylinder_between("PipeBraceA", (-12.6, 9.9, -3.6), (-12.6, 12.4, -6.0), 0.18, STEEL_MID, sides=6)
    cylinder_between("PipeBraceB", (-8.4, 11.3, -3.8), (-8.4, 12.6, -6.0), 0.18, STEEL_MID, sides=6)
    # pipe rack above the gears
    for i in range(4):
        y = 11.9 + 0.42 * i
        cylinder_between("RackPipe%d" % i, (-15.2, y, -6.6), (-4.0, y, -6.6), 0.17 - 0.02 * i, STEEL_MID, sides=8)
    return []


def build_machine_housing():
    """Right hero block: riveted housing with the amber arched window from the
    reference, valve wheels, ladder, exhaust stack and crane arm."""
    cx = 12.2
    box("MachineBody", (6.6, 7.2, 5.4), (cx, 3.4, -6.4), STEEL_DARK, bev=0.08)
    box("MachinePanelA", (5.8, 3.0, 0.4), (cx, 2.2, -3.6), STEEL, bev=0.04)
    box("MachinePanelB", (5.8, 2.2, 0.4), (cx, 5.6, -3.6), STEEL_MID, bev=0.04)
    box("MachineBelt", (6.0, 0.5, 0.5), (cx, 4.2, -3.55), IRON_RUST)
    for i in range(8):
        box("MachineRivet%d" % i, (0.2, 0.2, 0.2), (cx - 2.4 + 0.69 * i, 6.9, -3.4), STEEL_LIGHT, bev=0.0)
    # arched amber window
    arch_frame("Arch", (cx, 1.0), 3.2, 2.2, 0.34, STEEL_MID, -3.3)
    emissive_panel("ArchGlass", (2.7, 2.0, 0.25), (cx, 2.1, -3.5), AMBER)
    emissive_panel("ArchGlassHot", (1.1, 0.8, 0.2), (cx, 1.4, -3.4), AMBER_HOT)
    box("ArchSill", (3.6, 0.4, 0.6), (cx, 0.35, -3.3), STEEL, bev=0.03)
    # hazard stripe base
    for k in range(8):
        c = HAZARD if k % 2 == 0 else DARK
        box("MachHazard%d" % k, (0.72, 0.5, 0.3), (cx - 2.6 + 0.72 * k, 0.72, -3.55), c, bev=0.0)
    # pipes and valves on top
    cylinder("Stack", 0.65, 5.6, (cx + 1.9, 8.2, -6.0), IRON_RUST, axis="Y", sides=10)
    cylinder("StackCap", 0.8, 0.5, (cx + 1.9, 11.1, -6.0), STEEL_MID, axis="Y", sides=10)
    cylinder("ValvePipe", 0.5, 6.4, (cx - 2.6, 8.0, -5.0), STEEL, axis="Y", sides=10)
    cylinder("ValveWheel", 0.9, 0.2, (cx - 2.6, 9.4, -4.6), RUST_HOT, axis="Z", sides=12)
    cylinder("ValveWheel2", 0.55, 0.18, (cx - 2.6, 9.4, -4.4), STEEL_LIGHT, axis="Z", sides=10)
    # crane arm reaching over the bridge
    box("CraneArm", (9.0, 0.45, 0.45), (cx - 4.0, 7.6, -5.0), STEEL_MID, bev=0.03)
    box("CraneArmTip", (0.6, 1.3, 0.6), (cx - 8.2, 7.0, -5.0), STEEL_DARK, bev=0.03)
    chain("CraneChain", cx - 8.2, 6.4, -5.0, 2.4, STEEL_LIGHT)
    box("CraneHook", (0.8, 0.8, 0.4), (cx - 8.2, 3.9, -5.0), RUST, bev=0.03)
    # ladder up the side
    for i in range(7):
        box("LadderRung%d" % i, (1.0, 0.1, 0.1), (cx + 3.2, 1.2 + 0.62 * i, -3.9), STEEL_LIGHT, bev=0.0)
    for side in (-0.5, 0.5):
        box("LadderRail%.0f" % side, (0.1, 4.4, 0.1), (cx + 3.2 + side, 3.0, -3.9), STEEL_MID, bev=0.0)
    return []


def build_side_walls():
    # left wall with pipe racks
    box("WallLeft", (0.8, 20.0, 34.0), (-15.8, 7.0, -8.0), BRICK_DARK, bev=0.0)
    box("WallRight", (0.8, 20.0, 34.0), (15.8, 7.0, -8.0), BRICK_DARK, bev=0.0)
    for side in (-1.0, 1.0):
        for i in range(6):
            z = 2.0 - 4.6 * i
            cylinder("WallPipe%d_%.0f" % (i, side), 0.28, 12.0,
                     (15.1 * side, 7.0, z), STEEL_MID, axis="Y", sides=8)
            box("WallPipeBracket%d_%.0f" % (i, side), (1.2, 0.3, 0.3),
                (15.3 * side, 4.2 + 1.6 * (i % 3), z), STEEL)
    # duct runs along both walls at mid height
    for side in (-1.0, 1.0):
        cylinder_between("WallDuct%.0f" % side, (14.6 * side, 6.8, 2.0), (14.6 * side, 6.8, -16.0),
                         0.5, IRON_RUST, sides=8)
    # foreground guard rail behind the camera side (reference bottom band)
    box("ForeRailTop", (26.0, 0.2, 0.24), (0.0, 1.35, 5.4), STEEL_LIGHT)
    box("ForeRailMid", (26.0, 0.14, 0.18), (0.0, 0.72, 5.4), STEEL_MID)
    for i in range(13):
        x = -12.6 + 2.1 * i
        box("ForePost%d" % i, (0.2, 1.5, 0.2), (x, 0.65, 5.4), STEEL_MID, bev=0.0)
        box("ForeBase%d" % i, (0.4, 0.2, 0.4), (x, -0.05, 5.4), STEEL_DARK, bev=0.0)
    return []


def build_ceiling():
    for i in range(7):
        z = 2.0 - 5.0 * i
        box("TrussChord%d" % i, (32.0, 0.5, 0.5), (0.0, 14.6, z), STEEL_DARK)
        box("TrussChordLow%d" % i, (32.0, 0.35, 0.35), (0.0, 13.2, z), STEEL)
        for k in range(8):
            x = -13.5 + 3.85 * k
            box("TrussDiag%d_%d" % (i, k), (0.25, 1.7, 0.25), (x, 13.9, z), STEEL, bev=0.0,
                rot=(0.0, 0.0, 28.0 if k % 2 else -28.0))
    # cables and hanging clutter
    for i in range(6):
        x = -11.0 + 4.4 * i
        cylinder_between("Cable%d" % i, (x, 13.6, -10.0), (x + 1.2, 10.4, -12.0), 0.05, STEEL_LIGHT, sides=5)
    return []


# -------------------------------------------------------------------- export ---

def join_groups():
    """Join everything into a handful of objects so Godot gets few nodes."""
    bpy.ops.object.select_all(action="DESELECT")
    groups = {}
    for obj in OBJECTS:
        key = obj.name.split("_")[0].rstrip("0123456789")
        groups.setdefault(key, []).append(obj)
    joined = []
    for key, objs in groups.items():
        if not objs:
            continue
        if len(objs) == 1:
            joined.append(objs[0])
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        merged = bpy.context.view_layer.objects.active
        merged.name = key
        joined.append(merged)
    return joined


def main():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # one shared material (colours are vertex data; the Godot side overrides it
    # with the title kit's vertex-colour shader)
    mat = bpy.data.materials.new("TitleVertexColor")
    mat.use_nodes = True
    scene.world = bpy.data.worlds.new("W")
    scene.world.use_nodes = True

    builders = [
        build_back_wall, build_side_walls, build_ceiling,
        build_catwalk, build_bridge, build_pit,
        build_gear_tower, build_machine_housing,
    ]
    for builder in builders:
        builder()
    for obj in OBJECTS:
        if obj.data.materials is not None and len(obj.data.materials) == 0:
            obj.data.materials.append(mat)

    # apply bevel modifiers so the export is plain geometry
    for obj in OBJECTS:
        if obj.modifiers:
            bpy.context.view_layer.objects.active = obj
            for mod in list(obj.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                except RuntimeError:
                    pass

    joined = join_groups()
    # bake transforms so placement is in world space (Godot instances nodes at origin)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in joined:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = joined[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        use_selection=False,
    )
    print("EXPORTED", out, os.path.getsize(out))


if __name__ == "__main__":
    main()
