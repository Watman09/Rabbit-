"""Sculpt the dark spirits in Blender (headless) and export them for the game.

  /opt/bpyenv/bin/python tools/blender/build_spirits.py

Every spirit type is two meshes:
  core_<kind>  : opaque body built with Skin + Subdivision over an anatomy graph
                 (hunched torso, skull under a horned hood, bony arms, hooked
                 claws, spikes), plus eye and maw glow pieces.
  smoke_<kind> : torn ribbons of ink-smoke trailing behind (drawn alpha-blended
                 with ember edges by spirit_smoke.gdshader).
Per-vertex data goes into the colour attribute (the game unpacks it):
  core : R glow (1 eye, .6 maw, .3 claw tip), G arm (0 / .5 left / 1 right),
         B sway (0 head .. 1 tail), A position along the arm (0 shoulder .. 1 claw tip)
  smoke: R across the ribbon (0..1), G arm, B along the ribbon (0 root .. 1 tip), A arm t
Shoulder pivots (for the arm swing in the shader) go to spirits.json.

Coordinates are written in Godot space (x left, y up, z forward, metres).
"""
import json
import math
import os
import random

import bpy  # noqa: E402  (bpy must be imported before bmesh)
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "spirits.glb")
OUT_JSON = os.path.join(ROOT, "assets", "models", "spirits.json")


def G(x, y, z):
    return Vector((x, -z, y))


def to_g(v):
    return Vector((v.x, v.z, -v.y))


bpy.ops.wm.read_factory_settings(use_empty=True)
COL = bpy.context.collection


# ------------------------------------------------------------------ anatomy graph
class Graph:
    def __init__(self):
        self.p = []      # Godot-space positions
        self.r = []      # radii
        self.tag = []    # dict per node: arm, armt, sway, glow
        self.e = []

    def node(self, pos, r, parent=None, **tag):
        self.p.append(Vector(pos))
        self.r.append(r)
        t = {"arm": 0.0, "armt": 0.0, "sway": 0.0, "glow": 0.0}
        t.update(tag)
        self.tag.append(t)
        i = len(self.p) - 1
        if parent is not None:
            self.e.append((parent, i))
        return i

    def chain(self, start, pts, **tag):
        """pts: list of (pos, r, extra_tags)."""
        cur = start
        out = []
        for pos, r, extra in pts:
            t = dict(tag)
            t.update(extra)
            cur = self.node(pos, r, cur, **t)
            out.append(cur)
        return out


def skin_object(name, g):
    me = bpy.data.meshes.new(name)
    me.from_pydata([G(*p) for p in g.p], g.e, [])
    ob = bpy.data.objects.new(name, me)
    COL.objects.link(ob)
    mod = ob.modifiers.new("Skin", "SKIN")
    mod.branch_smoothing = 0.6
    mod.use_smooth_shade = True
    sk = me.skin_vertices[0].data
    for i, r in enumerate(g.r):
        sk[i].radius = (r, r)
    sk[0].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    return bake(ob)


def bake(ob):
    """Apply all modifiers into a plain mesh object."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    out = bpy.data.objects.new(ob.name + "_baked", me)
    COL.objects.link(out)
    bpy.data.objects.remove(ob)
    return out


def seg_info(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length, t


def paint_from_graph(ob, g):
    """Per-vertex tags from the nearest graph segment (radius-weighted)."""
    me = ob.data
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    col = me.color_attributes["Col"]
    for v in me.vertices:
        p = to_g(v.co)
        best = None
        for a, b in g.e:
            d, t = seg_info(p, g.p[a], g.p[b])
            d -= (g.r[a] * (1 - t) + g.r[b] * t)
            if best is None or d < best[0]:
                best = (d, a, b, t)
        _, a, b, t = best
        ta, tb = g.tag[a], g.tag[b]
        lerp = lambda k: ta[k] * (1 - t) + tb[k] * t
        arm = tb["arm"] if tb["arm"] > 0 else ta["arm"]
        col.data[v.index].color = (lerp("glow"), arm, lerp("sway"), lerp("armt"))


def paint_const(ob, c):
    me = ob.data
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    col = me.color_attributes["Col"]
    for v in me.vertices:
        col.data[v.index].color = c


def ellipsoid(name, center, scale, rot_z=0.0, color=(1, 0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]   # Godot-ish local (x, y up, z fwd) in blender sphere axes
        c, s = math.cos(rot_z), math.sin(rot_z)
        x, y = x * c - y * s, x * s + y * c
        v.co = G(center[0] + x, center[1] + y, center[2] + z)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    COL.objects.link(ob)
    paint_const(ob, color)
    return ob


def hood(name, center, r, horn=0.25, horn_spread=0.55, open_front=0.25, sway=0.05):
    """Hood shell around the skull: open face, two swept-back horn points."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=1.0)
    kill = []
    for v in bm.verts:
        x, y, z = v.co.x, v.co.z, -v.co.y          # unit sphere -> Godot axes
        if z > open_front and y < 0.7:
            kill.append(v)
            continue
        # elongate backward and pull the brow forward over the eyes
        z2 = z * (1.25 if z < 0 else 1.0)
        y2 = y
        if y > 0.15 and z > 0.0:
            z2 += 0.08 * y
        # two horn-like points sweeping up and back (as in the concept)
        k = max(0.0, (y - 0.25)) * max(0.0, (abs(x) - 0.2)) * max(0.0, (0.25 - z))
        if k > 0:
            y2 += k * horn * 9.0
            z2 -= k * horn * 7.0
            x *= 1.0 + k * horn_spread * 4.0
        v.co = G(center[0] + x * r, center[1] + y2 * r, center[2] + z2 * r)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    COL.objects.link(ob)
    so = ob.modifiers.new("Solid", "SOLIDIFY")
    so.thickness = r * 0.12
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    ob = bake(ob)
    paint_const(ob, (0, 0, sway, 0))
    return ob


def ribbon_set(name, ribbons, rng):
    """ribbons: list of dict(start, dir, length, width, drop, wiggle, arm, armt)."""
    verts, faces, cols = [], [], []
    for rb in ribbons:
        segs = 10
        p0 = Vector(rb["start"])
        d = Vector(rb["dir"]).normalized()
        side_hint = Vector((0, 1, 0))
        ph = rng.random() * 6.28
        base = len(verts)
        prev = None
        for i in range(segs + 1):
            t = i / segs
            lat = d.cross(Vector((0, 1, 0)))
            if lat.length < 0.01:
                lat = Vector((1, 0, 0))
            lat.normalize()
            k_drop = rb.get("drop_k", 0.0)
            fall = (1.0 - math.exp(-k_drop * t)) / (1.0 - math.exp(-k_drop)) if k_drop > 0 else t * t
            pos = (p0 + d * rb["length"] * t + Vector((0, -rb["drop"] * fall, 0))
                   + lat * math.sin(t * 3.0 + ph) * rb["wiggle"] * t)
            if prev is not None:
                tang = (pos - prev).normalized()
            else:
                tang = d
            prev = pos
            side = tang.cross(side_hint)
            if side.length < 0.01:
                side = lat
            side.normalize()
            w = rb["width"] * (1.0 - t) ** 0.55 + 0.015
            for s in (-0.5, 0.5):
                verts.append(G(*(pos + side * w * s)))
                cols.append((s + 0.5, rb.get("arm", 0.0), t, rb.get("armt", 0.0)))
        for i in range(segs):
            a = base + i * 2
            faces.append((a, a + 1, a + 3, a + 2))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(name, me)
    COL.objects.link(ob)
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    col = me.color_attributes["Col"]
    for i, c in enumerate(cols):
        col.data[i].color = c
    return ob


def lerp(a, b, t):
    return a + (b - a) * t


def decimate(ob, max_verts):
    """Collapse-decimate to a vertex budget (browser GPUs draw hundreds of these)."""
    n = len(ob.data.vertices)
    if n <= max_verts:
        return ob
    name = ob.name
    mod = ob.modifiers.new("Dec", "DECIMATE")
    mod.ratio = max_verts / n
    mod.use_collapse_triangulate = True
    out = bake(ob)
    out.name = name
    out.data.name = name
    out.data.color_attributes.active_color = out.data.color_attributes["Col"]
    return out


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.data.color_attributes.active_color = ob.data.color_attributes["Col"]
    return ob


# ------------------------------------------------------------------ spirit design
def build(kind, P):
    """P: proportions; returns shoulder pivot (Godot coords)."""
    rng = random.Random(hash(kind) & 0xFFFF)
    s = P["scale"]
    g = Graph()
    hy = P["hover"]
    # spine: tail tip -> pelvis -> chest -> neck -> head (hunched forward)
    root = g.node((0, hy + 0.0 * s, -0.95 * s), 0.02 * s, sway=1.0)
    tail = g.chain(root, [((0, hy + 0.08 * s, -0.6 * s), 0.06 * s, {"sway": 0.75}),
                          ((0, hy + 0.2 * s, -0.3 * s), 0.11 * s, {"sway": 0.45})])
    pelvis = g.node((0, hy + 0.38 * s, -0.08 * s), 0.15 * s * P["bulk"], tail[-1], sway=0.25)
    belly = g.node((0, hy + 0.58 * s, 0.02 * s), 0.17 * s * P["bulk"], pelvis, sway=0.1)
    chest = g.node((0, hy + 0.8 * s, 0.12 * s), 0.22 * s * P["bulk"] * P["chest"], belly)
    hump = g.node((0, hy + 0.92 * s, 0.0), 0.16 * s * P["bulk"] * P["chest"], chest)
    neck = g.node((0, hy + 0.9 * s, 0.3 * s), 0.08 * s, hump)
    head_c = Vector((0, hy + 0.9 * s + P["head_up"] * s, 0.44 * s))
    head = g.node(head_c, P["head_r"] * s, neck)
    jaw = g.node(head_c + Vector((0, -0.07 * s, 0.08 * s)), P["head_r"] * 0.62 * s, head)
    # back spikes
    for k in range(P["spikes"]):
        base = [hump, chest, belly][k % 3]
        bp = g.p[base]
        tip = bp + Vector(((k % 2 * 2 - 1) * 0.12 * s, 0.32 * s * P["spike_len"], -0.22 * s))
        g.chain(base, [(bp.lerp(tip, 0.5), 0.045 * s, {}), (tip, 0.004, {})])
    # arms
    shoulder = None
    if P["arms"]:
        for side, code in ((1, 1.0), (-1, 0.5)):
            sh = Vector((side * 0.27 * s * P["bulk"], hy + 0.86 * s, 0.1 * s))
            reach = P["arm_len"]
            el = sh + Vector((side * 0.16, -0.24, 0.2)) * s * reach
            wr = el + Vector((-side * 0.04, -0.14, 0.3)) * s * reach
            hand = wr + Vector((0, -0.03, 0.07)) * s
            pts = [(sh, 0.1 * s * P["arm_r"], {"armt": 0.0}),
                   (el, 0.06 * s * P["arm_r"], {"armt": 0.45}),
                   (wr, 0.042 * s * P["arm_r"] * P["fist"], {"armt": 0.8}),
                   (hand, 0.05 * s * P["arm_r"] * P["fist"], {"armt": 0.85})]
            ids = g.chain(chest, pts, arm=code)
            if shoulder is None or side == 1:
                shoulder = sh
            hid = ids[-1]
            n = P["claws"]
            fwd = (hand - wr).normalized()
            lat = fwd.cross(Vector((0, 1, 0))).normalized()
            for c in range(n):
                f = (c / max(n - 1, 1)) * 2 - 1
                d = (fwd + lat * f * 0.6).normalized()
                k1 = hand + d * 0.09 * s * P["claw_len"]
                k2 = k1 + (d + Vector((0, -0.6, 0))).normalized() * 0.08 * s * P["claw_len"]
                k3 = k2 + (d + Vector((0, -1.4, -0.3))).normalized() * 0.06 * s * P["claw_len"]
                g.chain(hid, [(k1, 0.022 * s * P["arm_r"], {"armt": 0.92}),
                              (k2, 0.014 * s * P["arm_r"], {"armt": 0.97, "glow": 0.15}),
                              (k3, 0.003, {"armt": 1.0, "glow": 0.3})], arm=code)
    core = skin_object("core_" + kind, g)
    paint_from_graph(core, g)
    parts = [core]
    # hood
    if P["hood"]:
        parts.append(hood("hood_" + kind, head_c + Vector((0, 0.03 * s, -0.03 * s)), P["head_r"] * s * 1.55,
                          horn=P["horn"], horn_spread=P["horn_spread"]))
    # eyes: narrow, slanted, deep under the brow
    ew = P["eye"] * s
    for side in (-1, 1):
        # placed high on the face and tipped up so the top-down camera sees them
        parts.append(ellipsoid("eye", head_c + Vector((side * 0.072 * s, P["head_r"] * s * 0.38, P["head_r"] * s * 1.02)),
                               (ew * 1.25, ew * 0.42, ew * 0.45), rot_z=-side * 0.6, color=(1, 0, 0, 0)))
    # maw: jagged glowing gash
    if P["maw"] > 0:
        parts.append(ellipsoid("maw", head_c + Vector((0, -0.08 * s, P["head_r"] * s * 0.95)),
                               (P["head_r"] * s * 0.38 * P["maw"], P["head_r"] * s * 0.07 * P["maw"], 0.015 * s),
                               color=(0.6, 0, 0, 0)))
    core = join(parts, "core_" + kind)
    core = decimate(core, P.get("max_verts", 1100))

    # smoke ribbons: a torn cloak streaming back from the shoulders, back and hips
    ribbons = []
    for k in range(P["ribbons"]):
        # roots spread around the back half of the torso
        ang = math.radians(lerp(-125.0, 125.0, k / max(P["ribbons"] - 1, 1)) + rng.uniform(-8, 8))
        rad = 0.2 * s * P["bulk"]
        y0 = hy + rng.uniform(0.35, 0.8) * s
        start = Vector((math.sin(ang) * rad, y0, -math.cos(ang) * rad * 0.8 + 0.05 * s))
        d = Vector((math.sin(ang) * 0.7 + rng.uniform(-0.15, 0.15), 0.0, -1.0))
        ribbons.append({"start": start, "dir": d, "length": s * P["trail"] * rng.uniform(0.65, 1.1),
                        "width": s * rng.uniform(0.3, 0.5) * P["bulk"], "drop": max(0.0, y0 - 0.08),
                        "wiggle": s * rng.uniform(0.15, 0.3), "drop_k": rng.uniform(2.5, 4.0)})
    # hood tails / hair
    for k in range(P["hair"]):
        a = (k / max(P["hair"] - 1, 1)) * 2 - 1
        ribbons.append({"start": head_c + Vector((a * 0.08 * s, 0.1 * s, -0.12 * s)),
                        "dir": Vector((a * 0.4, rng.uniform(-0.1, 0.25), -1.0)),
                        "length": s * P["trail"] * rng.uniform(0.5, 0.9), "width": s * rng.uniform(0.06, 0.12),
                        "drop": s * 0.1, "wiggle": s * 0.12})
    # tattered sleeves (move with the arms)
    if P["arms"]:
        for side, code in ((1, 1.0), (-1, 0.5)):
            el = Vector((side * 0.27 * s * P["bulk"], hy + 0.86 * s, 0.1 * s)) + Vector((side * 0.16, -0.24, 0.2)) * s * P["arm_len"]
            for k in range(2):
                ribbons.append({"start": el + Vector((0, 0, -0.03 * k * s)), "dir": Vector((side * 0.3, -0.5, -1.0)),
                                "length": s * rng.uniform(0.45, 0.7), "width": s * 0.1, "drop": s * 0.15,
                                "wiggle": s * 0.06, "arm": code, "armt": 0.45})
    smoke = ribbon_set("smoke_" + kind, ribbons, rng)
    return shoulder, core, smoke


BASE = {"scale": 1.0, "hover": 0.3, "bulk": 1.0, "chest": 1.0, "head_r": 0.12, "head_up": 0.0, "spikes": 0,
        "spike_len": 1.0, "arms": True, "arm_len": 1.0, "arm_r": 1.0, "fist": 1.0, "claws": 3, "claw_len": 1.0,
        "hood": True, "horn": 0.55, "horn_spread": 0.6, "eye": 0.055, "maw": 0.0, "ribbons": 9, "hair": 0,
        "trail": 2.0}
TYPES = {
    "wisp":   dict(BASE, scale=0.62, hover=0.5, arms=False, ribbons=6, trail=2.2, eye=0.065, horn=0.35, maw=0.0),
    "wraith": dict(BASE),
    "banshee": dict(BASE, scale=1.1, bulk=0.8, arm_len=1.3, arm_r=0.75, claw_len=1.5, horn=0.1, hair=6, maw=1.5,
                    ribbons=8, trail=2.6, hover=0.5),
    "shade":  dict(BASE, scale=1.15, bulk=1.15, chest=1.1, spikes=4, horn=0.5, horn_spread=0.8, arm_r=1.2,
                    claw_len=1.3, ribbons=11, trail=2.3),
    "brute":  dict(BASE, scale=1.15, bulk=1.6, chest=1.25, head_r=0.1, head_up=-0.08, spikes=6, spike_len=1.3,
                    arm_len=1.2, arm_r=1.9, fist=1.6, claw_len=1.4, claws=4, hood=False, maw=1.2, ribbons=9,
                    trail=1.6, hover=0.15),
    "boss":   dict(BASE, max_verts=2200, scale=1.25, bulk=1.3, chest=1.2, head_r=0.13, spikes=6, spike_len=1.5, horn=0.85,
                    horn_spread=1.1, arm_len=1.35, arm_r=1.4, claw_len=1.7, claws=4, maw=1.4, ribbons=14, hair=4,
                    trail=2.8),
}

pivots = {}
export = []
for kind, P in TYPES.items():
    sh, core, smoke = build(kind, P)
    pivots[kind] = [sh.x, sh.y, sh.z] if sh else [0.3, 1.2, 0.1]
    export += [core, smoke]
    print(kind, "core verts", len(core.data.vertices), "smoke verts", len(smoke.data.vertices))

mat = bpy.data.materials.new("Spirit")
for o in export:
    o.data.materials.clear()
    o.data.materials.append(mat)
bpy.ops.object.select_all(action="DESELECT")
for o in export:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
                          export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_yup=True,
                          export_normals=True, export_apply=False)
with open(OUT_JSON, "w") as f:
    json.dump({"shoulder": pivots}, f, indent=1)
print("exported", OUT)
