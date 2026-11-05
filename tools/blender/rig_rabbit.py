"""Rig + animate the Rabbit Reaper in Blender (headless).

  /opt/bpyenv/bin/python tools/blender/rig_rabbit.py      (bpy as a module)
  or: blender -b -P tools/blender/rig_rabbit.py

Input : assets/models/rabbit_reaper.fbx (static AI mesh, 1 unit tall)
Output: assets/models/hero_rigged.glb  (Body skinned to an 18-bone armature,
        vertex-colour palette in COLOR_0, actions: Idle, Run, Dash, Hit, Death)
The scythe is NOT in the glb: the game animates it separately
(assets/models/hero_scythe.res, made by tools/build_hero_meshes.gd).

Coordinates below are written in Godot model space (x = character's left,
y = up, z = forward, 1 unit = model height) and converted with G().
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "models", "rabbit_reaper.fbx")
OUT = os.path.join(ROOT, "assets", "models", "hero_rigged.glb")
S = 1.75   # model height in metres (matches the game)
FPS = 30


def G(x, y, z):
    """Godot model coords (unit height) -> Blender world coords (metres)."""
    return Vector((x * S, -z * S, y * S))


def from_blender(v):
    """Blender metres -> Godot unit coords."""
    return Vector((v.x / S, v.z / S, -v.y / S))


# ---------------------------------------------------------------- import
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
src = [o for o in bpy.data.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = src
src.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
src.scale = (S, S, S)
bpy.ops.object.transform_apply(scale=True)

# ---------------------------------------------------------------- split into parts
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.data.objects if o.type == "MESH"]


def bbox(o):
    ws = [from_blender(o.matrix_world @ v.co) for v in o.data.vertices]
    mn = Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws)))
    mx = Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))
    return mn, mx, len(ws)


info = {o.name: bbox(o) for o in parts}
by_size = sorted(parts, key=lambda o: -info[o.name][2])
kind = {}
for o in parts:
    mn, mx, n = info[o.name]
    size = mx - mn
    c = (mn + mx) * 0.5
    if size.y > 0.6 and size.x < 0.25 and size.z < 0.15:
        kind[o.name] = "staff"
    elif mn.y > 0.72 and size.x > 0.25 and mx.y < 0.98:
        kind[o.name] = "blade"
    elif c.x > 0.15 and size.y > 0.2:
        kind[o.name] = "ribbon"
    else:
        kind[o.name] = "cloth"
# identify big pieces by shape, not by vertex count (counts change after merging)
big = [o for o in by_size[:8] if kind[o.name] == "cloth"]
torso = max(big, key=lambda o: info[o.name][1].y)                 # reaches the ear tips
kind[torso.name] = "torso"
rest = [o for o in big if o != torso]
legs = max([o for o in rest if info[o.name][0].y < 0.03], key=lambda o: info[o.name][2])
kind[legs.name] = "legs"
cape = max([o for o in rest if o != legs], key=lambda o: (info[o.name][1] - info[o.name][0]).x)
kind[cape.name] = "cape"
hood = max([o for o in rest if o not in (legs, cape) and info[o.name][0].y > 0.55], key=lambda o: info[o.name][2])
kind[hood.name] = "hood"
print("parts:", {k: v for k, v in kind.items() if v != "cloth"})


# ---------------------------------------------------------------- palette (same rules as build_hero_meshes.gd)
def colour(k, p, n):
    if k == "legs":
        return (0.07, 0.06, 0.09, 0.0)
    if k == "hood":
        return (0.09, 0.05, 0.08, 0.0)
    if k == "cape":
        return (0.05, 0.04, 0.07, 0.0)
    if k == "torso":
        if p.y > 0.785:  # ears
            inner = max(0.0, min(1.0, n.z))
            a = Vector((0.62, 0.66, 0.86)).lerp(Vector((0.85, 0.45, 1.0)), inner * 0.8)
            return (a.x, a.y, a.z, 0.25 + inner * 0.5)
        if p.y > 0.70:
            return (0.66, 0.70, 0.86, 0.0)
        if p.y < 0.2:
            return (0.45, 0.47, 0.6, 0.0)
        return (0.08, 0.06, 0.10, 0.0)
    return (0.12, 0.08, 0.12, 0.0)


body_parts = []
for o in parts:
    k = kind[o.name]
    if k in ("staff", "blade", "ribbon"):
        bpy.data.objects.remove(o)   # scythe lives in hero_scythe.res
        continue
    me = o.data
    me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    me.attributes.new(name="part", type="INT", domain="POINT")
    # fetch after creating both: adding an attribute invalidates earlier references
    attr = me.color_attributes["Col"]
    code = me.attributes["part"]
    pcode = {"torso": 1, "legs": 2, "hood": 3, "cape": 4}.get(k, 5)
    for v in me.vertices:
        p = from_blender(o.matrix_world @ v.co)
        nb = o.matrix_world.to_3x3() @ v.normal
        n = Vector((nb.x, nb.z, -nb.y))
        attr.data[v.index].color = colour(k, p, n)
        code.data[v.index].value = pcode
    body_parts.append(o)

bpy.ops.object.select_all(action="DESELECT")
for o in body_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = body_parts[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
body.data.name = "Body"
body.data.color_attributes.active_color = body.data.color_attributes["Col"]
mat = bpy.data.materials.new("HeroMat")
mat.use_nodes = True
body.data.materials.clear()
body.data.materials.append(mat)
bpy.ops.object.shade_smooth()

# ---------------------------------------------------------------- armature
# (head, tail, parent) in Godot unit coords. ".L" = character's left (+x),
# the hand that holds the scythe.
BONES = {
    "root":       ((0, 0.00, 0), (0, 0.06, 0), None),
    "hips":       ((0, 0.45, 0.0), (0, 0.53, 0.0), "root"),
    "spine":      ((0, 0.53, 0.0), (0, 0.62, 0.0), "hips"),
    "chest":      ((0, 0.62, 0.0), (0, 0.71, 0.0), "spine"),
    "neck":       ((0, 0.71, 0.01), (0, 0.76, 0.02), "chest"),
    "head":       ((0, 0.76, 0.02), (0, 0.86, 0.03), "neck"),
    "ear.L":      ((0.025, 0.83, 0.0), (0.105, 0.99, 0.03), "head"),
    "ear.R":      ((-0.055, 0.83, 0.0), (-0.10, 0.99, 0.03), "head"),
    "shoulder.L": ((0.03, 0.69, 0.0), (0.10, 0.675, 0.0), "chest"),
    "upper_arm.L": ((0.10, 0.675, 0.0), (0.135, 0.53, 0.05), "shoulder.L"),
    "forearm.L":  ((0.135, 0.53, 0.05), (0.13, 0.565, 0.14), "upper_arm.L"),
    "hand.L":     ((0.13, 0.565, 0.14), (0.13, 0.57, 0.18), "forearm.L"),
    "shoulder.R": ((-0.03, 0.69, 0.0), (-0.10, 0.675, 0.0), "chest"),
    "upper_arm.R": ((-0.10, 0.675, 0.0), (-0.14, 0.51, 0.0), "shoulder.R"),
    "forearm.R":  ((-0.14, 0.51, 0.0), (-0.15, 0.38, 0.01), "upper_arm.R"),
    "hand.R":     ((-0.15, 0.38, 0.01), (-0.15, 0.32, 0.01), "forearm.R"),
    "thigh.L":    ((0.08, 0.44, 0.0), (0.12, 0.25, 0.015), "hips"),
    "shin.L":     ((0.12, 0.25, 0.015), (0.15, 0.08, -0.01), "thigh.L"),
    "foot.L":     ((0.15, 0.08, -0.01), (0.16, 0.01, 0.08), "shin.L"),
    "thigh.R":    ((-0.08, 0.44, 0.0), (-0.12, 0.25, 0.015), "hips"),
    "shin.R":     ((-0.12, 0.25, 0.015), (-0.16, 0.08, -0.01), "thigh.R"),
    "foot.R":     ((-0.16, 0.08, -0.01), (-0.17, 0.01, 0.08), "shin.R"),
}
arm_data = bpy.data.armatures.new("Armature")
rig = bpy.data.objects.new("Armature", arm_data)
bpy.context.collection.objects.link(rig)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent) in BONES.items():
    eb = arm_data.edit_bones.new(name)
    eb.head = G(*h)
    eb.tail = G(*t)
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
    eb.use_deform = name != "root"
# consistent rolls: bend axis (local X) points to the character's side
for eb in arm_data.edit_bones:
    eb.align_roll(Vector((0, -1, 0)))   # local Z faces forward (Blender -Y)
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- skinning
# Bone-heat fails on this mesh (dozens of open, disconnected cloth pieces), so
# weights are computed here: each vertex picks candidate bones by body region,
# gets inverse-distance weights to the two nearest, then weights are smoothed.
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = rig
segs = {}
for b in arm_data.bones:
    if b.use_deform:
        segs[b.name] = (from_blender(b.head_local), from_blender(b.tail_local))
groups = {n: body.vertex_groups.new(name=n) for n in segs}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


LEG_L = ["hips", "thigh.L", "shin.L", "foot.L"]
LEG_R = ["hips", "thigh.R", "shin.R", "foot.R"]
ARM_L = ["chest", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L"]
ARM_R = ["chest", "shoulder.R", "upper_arm.R", "forearm.R", "hand.R"]
TRUNK = ["hips", "spine", "chest", "neck"]


def candidates(part, p):
    side = "L" if p.x >= 0 else "R"
    if part == 1:   # torso: head, ears, arms, trunk, feet (the feet are in this piece)
        if p.y > 0.83:
            return ["head", "ear." + ("L" if p.x > -0.015 else "R")]
        if p.y > 0.72:
            return ["neck", "head"]
        if p.y < 0.16:
            return LEG_L[2:] if side == "L" else LEG_R[2:]
        if abs(p.x) > 0.085 and 0.3 < p.y < 0.7:
            return ARM_L if side == "L" else ARM_R
        return TRUNK
    if part == 2:   # trousers
        if p.y > 0.42:
            return ["hips", "thigh." + side]
        return LEG_L if side == "L" else LEG_R
    if part in (3, 4):  # hood, cape follow the trunk
        return ["spine", "chest", "neck", "hips"]
    # small cloth/accessory pieces: nearest of trunk + arms + legs
    if p.y < 0.42 and abs(p.x) > 0.04:
        return LEG_L if side == "L" else LEG_R
    if abs(p.x) > 0.11 and p.y > 0.3:
        return ARM_L if side == "L" else ARM_R
    return TRUNK


part_attr = body.data.attributes["part"]
names = list(segs)
nv = len(body.data.vertices)
W = [[0.0] * len(names) for _ in range(nv)]
for v in body.data.vertices:
    p = from_blender(body.matrix_world @ v.co)
    cand = candidates(part_attr.data[v.index].value, p)
    d = sorted((seg_dist(p, *segs[n]), n) for n in cand)[:2]
    w0 = 1.0 / max(d[0][0], 0.004) ** 2.5
    w1 = 1.0 / max(d[1][0], 0.004) ** 2.5 if len(d) > 1 else 0.0
    W[v.index][names.index(d[0][1])] += w0 / (w0 + w1)
    if len(d) > 1:
        W[v.index][names.index(d[1][1])] += w1 / (w0 + w1)

# Laplacian smoothing over mesh edges (keeps seams between regions soft)
nbr = [[] for _ in range(nv)]
for e in body.data.edges:
    a, b = e.vertices
    nbr[a].append(b)
    nbr[b].append(a)
for _ in range(4):
    W2 = []
    for i in range(nv):
        if not nbr[i]:
            W2.append(W[i])
            continue
        avg = [0.0] * len(names)
        for j in nbr[i]:
            wj = W[j]
            for k in range(len(names)):
                avg[k] += wj[k]
        inv = 1.0 / len(nbr[i])
        W2.append([0.5 * W[i][k] + 0.5 * avg[k] * inv for k in range(len(names))])
    W = W2
for i in range(nv):
    top = sorted(((w, k) for k, w in enumerate(W[i]) if w > 0.01), reverse=True)[:4]
    tot = sum(w for w, _ in top) or 1.0
    for w, k in top:
        groups[names[k]].add([i], w / tot, "REPLACE")
print("weights done for", len(body.data.vertices), "vertices")

# ---------------------------------------------------------------- animation helpers
pose = rig.pose
rest_rot = {b.name: b.matrix_local.to_3x3().to_quaternion() for b in arm_data.bones}
# Godot-space axes as Blender vectors
SIDE = Vector((1, 0, 0))      # character's left; rotation +angle about it pitches down-forward? see below
UP = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))


def q_world(bone, axis, deg):
    """Rotation about an armature-space axis, expressed in the bone's local frame."""
    r = rest_rot[bone]
    return r.inverted() @ Quaternion(axis, math.radians(deg)) @ r


def key(action_name, frame, rots, locs=None):
    """rots: {bone: [(axis, deg), ...]}  locs: {bone: Vector armature-space delta}"""
    for pb in pose.bones:
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        for axis, deg in rots.get(pb.name, []):
            q = q_world(pb.name, axis, deg) @ q
        pb.rotation_quaternion = q
        loc = (locs or {}).get(pb.name)
        if loc is not None:
            pb.location = rest_rot[pb.name].inverted() @ loc
        else:
            pb.location = (0, 0, 0)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
        pb.keyframe_insert("location", frame=frame, group=pb.name)


def make_action(name, frames, cyclic=True):
    """frames: list of (frame, rots, locs)."""
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    rig.animation_data.action = act
    for f, rots, locs in frames:
        key(name, f, rots, locs)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "AUTO"
        if cyclic:
            fc.modifiers.new("CYCLES")
    act.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, int(frames[0][0]), act)
    rig.animation_data.action = None
    return act


# Sign conventions (checked against renders): a positive rotation about SIDE
# tilts upward bones (spine, head, ears) FORWARD and swings downward bones
# (legs, arms) BACKWARD.
def leg(side, thigh, shin, foot):
    return {f"thigh.{side}": [(SIDE, thigh)], f"shin.{side}": [(SIDE, shin)], f"foot.{side}": [(SIDE, foot)]}


def merge(*ds):
    out = {}
    for d in ds:
        for k, v in d.items():
            out.setdefault(k, []).extend(v)
    return out


# ---------------------------------------------------------------- Idle (2 s)
idle = []
for i, f in enumerate([1, 16, 31, 46, 61]):
    s = math.sin(i * math.pi / 2)
    c = math.cos(i * math.pi / 2)
    idle.append((f, merge(
        {"chest": [(SIDE, -2.0 * s)], "spine": [(SIDE, -1.0 * s)],
         "head": [(SIDE, 2.0 * c), (UP, 3.0 * s)],
         "ear.L": [(SIDE, 4.0 + 5.0 * s), (FWD, -3.0 * c)], "ear.R": [(SIDE, 4.0 - 4.0 * c), (FWD, 3.0 * s)],
         "upper_arm.R": [(SIDE, -3.0 * s), (FWD, -4.0)], "forearm.R": [(SIDE, -6.0 - 3.0 * s)],
         "thigh.L": [(SIDE, 0.0)], "shin.L": [(SIDE, 1.5 + 1.5 * s)],
         "thigh.R": [(SIDE, 0.0)], "shin.R": [(SIDE, 1.5 + 1.5 * s)]},
    ), {"hips": Vector((0, 0, -0.008 - 0.008 * s))}))
make_action("Idle", idle)

# ---------------------------------------------------------------- Run (20 frames = 0.667 s, two steps)
# keyed every frame for a crisp gait; foot contacts at frames 6 (L) and 16 (R)
run = []
N = 20
for f in range(0, N + 1, 1):
    ph = f / N * math.tau
    s = math.sin(ph)
    c = math.cos(ph)
    # left leg forward at ph = pi/2
    thL = -42.0 * s
    thR = 42.0 * s
    # knee bends most while the leg swings forward (recovery), less on contact
    shL = 15.0 + 55.0 * max(0.0, -c) + 10.0 * max(0.0, s)
    shR = 15.0 + 55.0 * max(0.0, c) + 10.0 * max(0.0, -s)
    bob = 0.035 * abs(math.cos(ph))   # high at mid-stance x2 per cycle
    run.append((f + 1, merge(
        leg("L", thL, shL, -12.0 * s - 10.0),
        leg("R", thR, shR, 12.0 * s - 10.0),
        {"hips": [(UP, 8.0 * s), (SIDE, 7.0)],
         "spine": [(UP, -5.0 * s), (SIDE, 5.0)],
         "chest": [(UP, -6.0 * s), (SIDE, 4.0)],
         "head": [(UP, 4.0 * s), (SIDE, -8.0)],
         "ear.L": [(SIDE, -32.0 - 8.0 * abs(c)), (FWD, -6.0 * s)],
         "ear.R": [(SIDE, -34.0 - 8.0 * abs(s)), (FWD, 6.0 * s)],
         "upper_arm.R": [(SIDE, -40.0 * s), (FWD, -10.0)],
         "forearm.R": [(SIDE, -55.0 - 20.0 * max(0.0, -s))]},
    ), {"hips": Vector((0, 0, bob - 0.03))}))
make_action("Run", run)

# ---------------------------------------------------------------- Dash pose (short loop)
dash_pose = merge(
    leg("L", -55.0, 35.0, -20.0), leg("R", 45.0, 60.0, 10.0),
    {"hips": [(SIDE, 14.0)], "spine": [(SIDE, 10.0)], "chest": [(SIDE, 8.0)], "head": [(SIDE, -16.0)],
     "ear.L": [(SIDE, -60.0)], "ear.R": [(SIDE, -63.0)],
     "upper_arm.R": [(SIDE, 60.0), (FWD, -20.0)], "forearm.R": [(SIDE, -30.0)]})
make_action("Dash", [(1, dash_pose, {"hips": Vector((0, 0, -0.06))}),
                     (5, dash_pose, {"hips": Vector((0, 0, -0.05))})])

# ---------------------------------------------------------------- Hit flinch (0.33 s)
flinch = merge({"chest": [(SIDE, -14.0)], "spine": [(SIDE, -6.0)], "head": [(SIDE, -16.0)],
                "ear.L": [(SIDE, 25.0)], "ear.R": [(SIDE, 25.0)],
                "upper_arm.R": [(FWD, -25.0)]}, leg("L", 8.0, 12.0, 0.0), leg("R", -6.0, 10.0, 0.0))
make_action("Hit", [(1, {}, None), (3, flinch, {"hips": Vector((0, 0.02, -0.02))}), (10, {}, None)], cyclic=False)

# ---------------------------------------------------------------- Death (1.2 s): drop to the knees, slump
kneel = merge(leg("L", -70.0, 120.0, 30.0), leg("R", -60.0, 125.0, 30.0),
              {"spine": [(SIDE, 18.0)], "chest": [(SIDE, 20.0)], "head": [(SIDE, 25.0)],
               "ear.L": [(SIDE, 30.0)], "ear.R": [(SIDE, 25.0)],
               "upper_arm.R": [(SIDE, -10.0), (FWD, -15.0)], "forearm.R": [(SIDE, -10.0)]})
slump = merge(leg("L", -75.0, 135.0, 35.0), leg("R", -65.0, 135.0, 35.0),
              {"spine": [(SIDE, 30.0)], "chest": [(SIDE, 28.0)], "head": [(SIDE, 35.0)],
               "ear.L": [(SIDE, 70.0)], "ear.R": [(SIDE, 65.0)],
               "upper_arm.R": [(SIDE, -20.0), (FWD, -10.0)], "forearm.R": [(SIDE, -5.0)]})
make_action("Death", [(1, {}, None), (6, flinch, None), (16, kneel, {"hips": Vector((0, 0.05, -0.33))}),
                      (36, slump, {"hips": Vector((0, 0.08, -0.40))})], cyclic=False)

# ---------------------------------------------------------------- combat footwork
# Rotation about FWD abducts the legs: +deg spreads the left leg outward,
# -deg the right one.
def leg2(side, thigh, abduct, shin, foot):
    sg = 1.0 if side == "L" else -1.0
    return {f"thigh.{side}": [(SIDE, thigh), (FWD, abduct * sg)],
            f"shin.{side}": [(SIDE, shin)], f"foot.{side}": [(SIDE, foot), (FWD, -abduct * sg * 0.6)]}


def stance(lead, k=1.0):
    """Fighting stance with the `lead` foot forward. k scales how low it sits."""
    back = "R" if lead == "L" else "L"
    return merge(leg2(lead, -14.0 * k, 9.0, 26.0 * k, -12.0 * k), leg2(back, 16.0 * k, 9.0, 24.0 * k, 4.0),
                 {"hips": [(SIDE, 5.0 * k)], "spine": [(SIDE, 4.0 * k)], "chest": [(SIDE, 2.0)], "head": [(SIDE, -6.0 * k)],
                  "ear.L": [(SIDE, -8.0)], "ear.R": [(SIDE, -10.0)],
                  "upper_arm.R": [(SIDE, -18.0), (FWD, -14.0)], "forearm.R": [(SIDE, -40.0)]})


STANCE_LOC = {"hips": Vector((0, 0, -0.06))}

# Ready: combat idle (breathing in a low stance) - 1.6 s loop
ready = []
for i, f in enumerate([1, 13, 25, 37, 49]):
    s = math.sin(i * math.pi / 2)
    ready.append((f, merge(stance("L"), {"chest": [(SIDE, 2.0 * s)], "head": [(UP, 2.5 * s)],
                                         "ear.L": [(SIDE, 4.0 * s)], "ear.R": [(SIDE, -3.0 * s)]}),
                  {"hips": Vector((0, 0, -0.06 - 0.008 * s))}))
make_action("Ready", ready)


def strike(lead):
    """Step-in strike. Key times are fixed so the game can map attack phases:
    wind-up ends at frame 5 (0.133 s), the swing ends at frame 10 (0.30 s),
    recovery ends at frame 23 (0.733 s)."""
    back = "R" if lead == "L" else "L"
    tw = 1.0 if lead == "L" else -1.0
    wind = merge(leg2(lead, -6.0, 9.0, 20.0, -6.0), leg2(back, 10.0, 10.0, 42.0, 2.0),
                 {"hips": [(SIDE, -2.0), (UP, 8.0 * tw)], "spine": [(SIDE, -6.0)], "chest": [(SIDE, -4.0)], "head": [(SIDE, 2.0)],
                  "ear.L": [(SIDE, 6.0)], "ear.R": [(SIDE, 6.0)],
                  "upper_arm.R": [(SIDE, 10.0), (FWD, -20.0)], "forearm.R": [(SIDE, -50.0)]})
    lunge = merge(leg2(lead, -50.0, 8.0, 52.0, -8.0), leg2(back, 34.0, 8.0, 12.0, 24.0),
                  {"hips": [(SIDE, 14.0), (UP, -10.0 * tw)], "spine": [(SIDE, 12.0)], "chest": [(SIDE, 8.0)], "head": [(SIDE, -14.0)],
                   "ear.L": [(SIDE, -40.0)], "ear.R": [(SIDE, -44.0)],
                   "upper_arm.R": [(SIDE, 30.0), (FWD, -40.0)], "forearm.R": [(SIDE, -20.0)]})
    settle = merge(leg2(lead, -42.0, 9.0, 46.0, -10.0), leg2(back, 28.0, 9.0, 16.0, 18.0),
                   {"hips": [(SIDE, 10.0), (UP, -6.0 * tw)], "spine": [(SIDE, 9.0)], "chest": [(SIDE, 5.0)], "head": [(SIDE, -10.0)],
                    "ear.L": [(SIDE, -20.0)], "ear.R": [(SIDE, -24.0)],
                    "upper_arm.R": [(SIDE, 12.0), (FWD, -25.0)], "forearm.R": [(SIDE, -30.0)]})
    return [(1, stance(lead), STANCE_LOC),
            (5, wind, {"hips": Vector((0, 0.03, -0.08))}),
            (8, lunge, {"hips": Vector((0, -0.07, -0.13))}),
            (10, lunge, {"hips": Vector((0, -0.08, -0.14))}),
            (15, settle, {"hips": Vector((0, -0.05, -0.11))}),
            (23, stance(lead), STANCE_LOC)]


make_action("Strike_L", strike("L"), cyclic=False)
make_action("Strike_R", strike("R"), cyclic=False)

# Spin: low wide crouch for whirl / maelstrom (body rotation comes from the game)
spin = []
for i, f in enumerate([1, 4, 7, 10, 13]):
    s = math.sin(i * math.pi / 2)
    spin.append((f, merge(leg2("L", -22.0, 20.0, 55.0, -18.0), leg2("R", -10.0, 20.0, 50.0, -10.0),
                          {"hips": [(SIDE, 12.0)], "spine": [(SIDE, 10.0)], "chest": [(SIDE, 6.0)], "head": [(SIDE, -10.0)],
                           "ear.L": [(SIDE, -60.0 + 8.0 * s), (FWD, 20.0)], "ear.R": [(SIDE, -62.0 - 8.0 * s), (FWD, -20.0)],
                           "upper_arm.R": [(FWD, -70.0 - 5.0 * s)], "forearm.R": [(SIDE, -10.0)]}),
                 {"hips": Vector((0, 0, -0.16 - 0.01 * s))}))
make_action("Spin", spin)

# Charge: coiled crouch, weight on the back leg, trembling
charge = []
for i, f in enumerate([1, 3, 5, 7, 9]):
    s = math.sin(i * math.pi / 2)
    charge.append((f, merge(leg2("L", -30.0, 12.0, 58.0, -14.0), leg2("R", 22.0, 12.0, 62.0, 8.0),
                            {"hips": [(SIDE, 4.0), (UP, 12.0)], "spine": [(SIDE, -2.0 + 1.0 * s), (UP, 8.0)], "chest": [(SIDE, -6.0), (UP, 8.0)],
                             "head": [(SIDE, 4.0), (UP, -14.0)], "ear.L": [(SIDE, -55.0 + 4.0 * s)], "ear.R": [(SIDE, -58.0 - 4.0 * s)],
                             "upper_arm.R": [(SIDE, 25.0), (FWD, -30.0)], "forearm.R": [(SIDE, -60.0)]}),
                   {"hips": Vector((0, 0.04, -0.17 + 0.006 * s))}))
make_action("Charge", charge)

# Heavy: crouch -> spring up -> slam into a deep lunge -> recover
# (frames: 1 stance, 4 crouch, 8 airborne, 11 slam (0.333 s), 14 hold, 30 recover)
crouch = merge(leg2("L", -30.0, 12.0, 70.0, -16.0), leg2("R", 18.0, 12.0, 72.0, 10.0),
               {"hips": [(SIDE, 8.0)], "spine": [(SIDE, 4.0)], "chest": [(SIDE, -6.0)], "head": [(SIDE, 2.0)],
                "ear.L": [(SIDE, -40.0)], "ear.R": [(SIDE, -40.0)], "upper_arm.R": [(SIDE, 30.0)], "forearm.R": [(SIDE, -50.0)]})
air = merge(leg2("L", -40.0, 6.0, 60.0, 10.0), leg2("R", 10.0, 6.0, 70.0, 20.0),
            {"hips": [(SIDE, -6.0)], "spine": [(SIDE, -12.0)], "chest": [(SIDE, -14.0)], "head": [(SIDE, 6.0)],
             "ear.L": [(SIDE, 20.0)], "ear.R": [(SIDE, 22.0)], "upper_arm.R": [(SIDE, -40.0), (FWD, -30.0)], "forearm.R": [(SIDE, -30.0)]})
slam = merge(leg2("L", -62.0, 10.0, 82.0, -6.0), leg2("R", 44.0, 10.0, 26.0, 30.0),
             {"hips": [(SIDE, 22.0)], "spine": [(SIDE, 20.0)], "chest": [(SIDE, 14.0)], "head": [(SIDE, -18.0)],
              "ear.L": [(SIDE, 40.0)], "ear.R": [(SIDE, 44.0)], "upper_arm.R": [(SIDE, 40.0), (FWD, -50.0)], "forearm.R": [(SIDE, -10.0)]})
make_action("Heavy", [(1, stance("L"), STANCE_LOC), (4, crouch, {"hips": Vector((0, 0.02, -0.2))}),
                      (8, air, {"hips": Vector((0, -0.04, 0.06))}), (11, slam, {"hips": Vector((0, -0.12, -0.26))}),
                      (14, slam, {"hips": Vector((0, -0.12, -0.25))}), (30, stance("L"), STANCE_LOC)], cyclic=False)

# ---------------------------------------------------------------- export
bpy.context.scene.render.fps = FPS
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_def_bones=True,
    export_vertex_color="ACTIVE",
    export_all_vertex_colors=False,
    export_skins=True,
    export_yup=True,
    export_apply=False,
)
print("exported", OUT)
