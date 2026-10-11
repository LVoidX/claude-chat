"""Helpers for building the game's 3D models with Blender, from a script (no window).

Run:  D:\Tools\blender\blender-5.2.2-windows-x64\blender.exe --background --python tools/blender/<model>.py
Each model script builds meshes with bmesh, paints VERTEX COLOURS (the game's look: no textures needed), and calls
export_glb(name). The .glb lands in godot_world/models3d/ and is loaded by the game at run time (world.gd
load_mesh()). Keep models low-poly: trees ~500 triangles, props 50-300.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix, noise

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot_world", "models3d")


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if "Col" in mesh.color_attributes:  # the painted layer must be the ACTIVE one: that is what gets exported as COLOR_0
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def paint(bm, func):
    """func(vertex position, normal, face index) -> (r, g, b) in 0..1 (linear). Colours are stored per corner."""
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    bm.verts.index_update()
    bm.faces.index_update()  # (faces made by hand have stale indices until this: the colour functions use them)
    for face in bm.faces:
        for loop in face.loops:
            v = loop.vert
            c = func(v.co.copy(), face.normal.copy(), face.index)
            loop[layer] = (c[0], c[1], c[2], 1.0)


def hex_rgb(h):
    """A hex colour as (r, g, b) floats, in sRGB. Write colours to the mesh as sRGB: Godot converts glTF vertex colours
    from sRGB to linear when it loads them (measured: written 0.5 arrives as 0.2157), so the hex codes you see here are
    the colours you get in the game."""
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def flat(bm):
    for f in bm.faces:
        f.smooth = False


def displace(bm, amount, scale=1.0, seed=0):
    for v in bm.verts:
        n = noise.noise(v.co * scale + Vector((seed, seed * 1.7, seed * 0.3)))
        v.co += v.normal * n * amount


def material():
    mat = bpy.data.materials.new("vertex")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    col = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mat.node_tree.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def export_glb(name, objects=None):
    os.makedirs(OUT, exist_ok=True)
    mat = material()
    objs = objects or [o for o in bpy.data.objects if o.type == "MESH"]
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_attributes=False, export_vertex_color="ACTIVE")
    tris = sum(len(o.data.polygons) for o in objs)
    print("EXPORTED", path, "faces:", tris)
    return path


def preview(name, objects=None, size=(640, 640), distance=1.0, height=0.5):
    """A quick Workbench render (flat, vertex colours) to look at a model without starting the game."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.render.resolution_x, scene.render.resolution_y = size
    objs = objects or [o for o in bpy.data.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3))); hi = Vector((max(hi[i], w[i]) for i in range(3)))
    centre = (lo + hi) / 2.0
    radius = (hi - lo).length / 2.0
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.collection.objects.link(cam)
    cam.location = centre + Vector((radius * 1.6 * distance, -radius * 2.3 * distance, radius * (0.5 + height)))
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, "..", "..", "tools", "blender", name + "_preview.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
