# Blender models for the game

The 3D models that are more than boxes are made here, from Python scripts, with Blender running without a window.

    D:\Tools\blender\blender-5.2.2-windows-x64\blender.exe --background --python tools/blender/oak.py

Each script builds meshes with bmesh, paints VERTEX COLOURS (no textures: the look is in the vertices) and calls
`export_glb(name)` from `lib.py`, which writes `godot_world/models3d/<name>.glb`. The game loads the file at run time:
`W.load_mesh("oak")` (world.gd) returns an ArrayMesh with the colours; the part gives it a material (terrain.gd:
`painted_tree_material()` reads the colours and sways with the wind; rocks use a plain vertex-colour material).

Things to know:
- Write colours as **sRGB** (`hex_rgb("#3d7a2e")`): Godot converts glTF vertex colours from sRGB to linear on import.
- Face indices must be refreshed before painting: `paint()` does it. Make the painted layer the active colour layer
  (`new_object()` does that), or the exporter writes a white one.
- Keep models low-poly: trees ~100-600 faces, props under 300. The look comes from flat shading + painted colours.
- Models so far: oak, pine, rock1-3, bush (see their scripts for the palette).
- Add a model: copy a script, change the shape and palette, run it, then call `W.load_mesh(name)` where it is used.
