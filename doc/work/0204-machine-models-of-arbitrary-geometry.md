# 0204: Machine models of arbitrary geometry

Status: todo (user, 2026-10-03: "this chunky blocky machine aesthetic needs to go, it does not fit the current look of the game anymore, we need to allow models with arbitrary geometry, it doesnt need to be high fidelity or massive amount of triangles, but we can maybe approach techtonica's look"; after 0189, before 0205)

## Goal

A machine model is a list of triangles with flat colours, not a grid of voxels. The look (low polygon counts, flat shading, geometry over texture) is set in `DESIGN.md` (Art direction) and applied by 0205 and 0206; this item is the pipeline that loads, meshes, lights, moves and hot reloads such a model, proved on two machines.

## Change

- Format: Wavefront OBJ with an MTL material file, `data/models/<model>.obj` and `<model>.mtl`, read by a new leaf package `src/model_obj/` beside `model_vox` (it references only `platform`; a row in `doc/code_map.md`). The subset: `v`, `vn`, `vt` (read and ignored, there are no textures), `f` with three or more corners (fan triangulated; the `v`, `v/vt`, `v//vn` and `v/vt/vn` forms; positive 1-based indices only), `o` and `g` (the part name), `usemtl`, `mtllib` and `#`; every other keyword is ignored. MTL: `newmtl`, `Kd` (the colour) and `Ke` (any channel above 0 makes the material emissive: drawn at the glow brightness, as the emissive palette indices are today). A missing material file, an unknown material, an index out of range, a face with fewer than three corners and more vertices in a layer than `MESH_PART_VERTEX_LIMIT` (u16 indices) are problems named with the file and the line, and refuse the models as a malformed .vox does.
- Why OBJ and an own reader, not glTF through raylib: the file is text, so Blender's exporter writes it and a diff reads it; Blender and Blockbench export it; `o`/`g` and `usemtl` carry the parts and the emissive layer with no extra convention; and the reader has no GPU in it, so the mesher's tests keep running headless. raylib's `LoadModel` uploads on load (needs a window) and reads textures through its own path (the gray format trap of 0106).
- Frame and units: one unit is one cell of the unrotated footprint, x and z centred on the footprint, y from its bottom, +x the front, y up, right handed: the frame `model_mesh.odin` already produces, so `model_transform`, `entity_frame_matrix` and the renderer are unchanged, and nothing scales the model to the footprint any more. The loader refuses a model whose x or z bounds leave the footprint by more than `MODEL_FOOTPRINT_TOLERANCE_CELLS` (0.02) or whose bottom is below y 0, and reads the top off the mesh (`Machine_Model_Mesh.top`); a chimney may stand above the footprint's height, since the markers and the ghost chevron follow the top. Blender export: +X forward, +Y up, scale 1 unit per cell.
- Shading: flat. A face's corners are emitted unshared, coloured `Kd` times a shade of the face normal (`vn` when given, else the winding's): `shade = 0.775 + 0.28 * dot(normal, key)` with `key` the normalised (0.30, 0.80, 0.52), chosen so an axis aligned box's six faces come within 0.1 of `model_face_shades` (top 1.0, bottom 0.55). `model_face_shades` stays for the voxel reader until 0206. The renderer keeps multiplying the vertex colour by the light tint and the glow brightness (`render_models.odin` unchanged: the new meshes are the same `Model_Layers`).
- Parts: the group named `part` is the moving part (the same frame, posed by `motion` as `<model>_part.vox` is today); every other group and ungrouped geometry is the body. One file per machine. The arm keeps its six .vox files in this item (0206 moves it).
- Resolution: a machine's `model` key names `<model>.obj` when that file exists, else `<model>.vox`; `Data_File_Category.Models` takes `.obj` and `.mtl` too, so a save of either rebuilds the models (`reload_models`). Both readers live until 0206 removes the voxel one.
- The generator runs inside Blender (user, 2026-10-03: Blender 5.2 LTS installed as the Flatpak `org.blender.Blender` with host file access; headless through `flatpak run org.blender.Blender --background --python <script> -- <arguments>`, Python 3.13 inside): the package `tools/models/` with the entry `tools/make_models.py`, run by the wrapper `tools/blender` (the host's `blender` when on the PATH, else the Flatpak), one script per machine under `tools/models/machines/`, each building the machine from bpy and bmesh (cubes, cylinders of n sides, the bevel modifier at one segment, booleans for openings, materials with a base colour and an emission colour) in the game's frame and writing `<model>.obj` and `.mtl` with Blender's OBJ exporter (forward +X, up +Y, triangulated, flat shaded, materials on, one object per part: `body`, `part`, the arm's parts), the scene cleared between machines so one Blender process writes them all. The committed files are the product: the build, the tests and CI never need Blender, only a regeneration does, and the same script in the same Blender version writes the same bytes. The kit's first helpers (a material table of `DESIGN.md`'s palette, the frame, the export) and two machines as the proof: the stone furnace (an emissive mouth, no part) and the burner mining drill (its `part` object spins as today), in the look of `DESIGN.md`. `make_placeholder_models.py` stops writing those two models and their .vox files are deleted. The reader ignores the MTL lines Blender adds beyond `Kd` and `Ke` (`Ns`, `Ka`, `Ks`, `Ni`, `d`, `illum`).
- Docs: `doc/presentation.md` Machine models (the format, the frame, the shade, the parts, the two readers, the generator), `doc/content.md` authoring rules (the line on 8 or 16 voxels per block), the header of `data/machines.sjson` (`model`), `doc/code_map.md`, `doc/architecture.md` if it names the model files under hot reload, the log.

## Verify

- The build and check commands of 0168.
- Tests, no GPU: the reader on hand written OBJ text (a quad fan triangulated into two triangles; `v//vn` and `v/vt/vn` corners; a group named `part`; a material with `Ke` landing in the emissive layer and one without in the lit layer; an unknown material, a missing MTL, a zero index and a two corner face each refused naming the line). The mesher: a unit box's six shades within 0.1 of `model_face_shades`; a face without `vn` shaded from its winding; a model past the footprint's x or z refused, one above its height accepted with the top read off the mesh; the vertex limit. The resolution: an .obj beside a .vox wins and a machine with only a .vox still loads. The watch classifies `.obj` and `.mtl` as `Models`. The two shipped machines load with a part for the drill and an emissive layer for the furnace.
- A headless screenshot of the planet preview or a session with the furnace and the drill placed, sent to the user.

## Specification (design, 2026-10-03)

Designed against `main` at 2411594. 0189 (in the main checkout, uncommitted) touches only the planet generation files, none of the files below. No binding, no string key, no save, record or network layout change: models are presentation, so floats are fine throughout.

### Answers to what the item left open

1. **Shade constants (changed from the item).** The item's `0.775 + 0.28 * dot(normal, key)` with key (0.30, 0.80, 0.52) gives -z 0.63 against `model_face_shades` -z 0.78, outside its own 0.1 bound: a linear shade makes each opposite pair sum to twice the base, and the old z pair sums to 1.70, not 1.55. Chosen: `shade = clamp(MODEL_SHADE_BASE + dot(unit_normal, MODEL_SHADE_GRADIENT), 0, 1)` with base 0.775 and gradient (0.03, 0.225, 0.085). The six box faces: -x 0.745, +x 0.805, -y 0.55, +y 1.0, -z 0.69, +z 0.86 (the largest gap is 0.09, at -z). x and z differ, so the front and right faces still meet at a visible edge. The gradient is 0.242 long, so a normal tilted up, forward and right reaches 1.017. That is the reason for the clamp.
2. **Export axes (the item's "+X forward" is the game frame, not the option value).** Blender's exporter maps Blender +Y to `forward_axis` and Blender +Z to `up_axis`. The kit builds every machine in Blender with its front at Blender +X, Z up and one Blender unit per cell. The game frame then needs Blender (x, y, z) to become file (x, z, -y), and that is the exporter's default pair `forward_axis='NEGATIVE_Z', up_axis='Y'`. `forward_axis='X'` would turn every model a quarter turn. `test_the_shipped_obj_machines_load` pins this: the furnace's glow is on the +x side.
3. **The drill's motion stays `pump`.** The item says the drill's part "spins as today", but today's record is `motion = {kind = "pump", axis = "y", amplitude = -0.25, period_seconds = 0.8}`, so "as today" is a pump. `data/machines.sjson` keeps that record unchanged. The part is built about the shaft axis at footprint point (0.45, y, 1.0), so a later spin only needs `pivot = [0.45, 0, 1.0]` (question 1 below).
4. **The bottom gets the tolerance too.** A vertex whose y is below `-MODEL_FOOTPRINT_TOLERANCE_CELLS` is refused, not one below exactly 0. The exporter writes six decimals, and a bevel's computed corner can land at -0.000001.
5. **Emissive colour.** An emissive triangle is drawn in its `Kd`, unshaded, as an emissive voxel is drawn in its palette colour. `Ke` decides only the layer. The kit gives emissive materials Kd equal to the glow colour, so either reading looks the same.
6. **Ke robustness.** Blender's Principled BSDF defaults to Emission Color white with Strength 0 (read off Blender 5.2 here). The kit sets Emission Color to black and Strength to 0 on every lit material, and the glow colour with Strength 1 on emissive ones. `Ke` is then 0 exactly where it must be, whichever of colour or colour times strength the exporter writes.
7. **Colour space.** `Kd` is read as the display colour: byte = round(Kd * 255), with no gamma. The kit writes palette bytes / 255 straight into Base Color. Blender's viewport shows them washed out, which does not matter because the game is the viewer (0207). The test on the furnace's glow colour pins the round trip.
8. **A part group without a moving motion is refused**, as is a moving motion without a part group. Both are typos the shipped test would otherwise hide.
9. **The material library name** must be a plain file name (`[a-z0-9_]+\.mtl`), resolved beside the .obj. A path from the file's text then stays under `data/models` (hand-back check).
10. **A degenerate triangle** (zero area, no `vn`) is skipped by the mesher, since it draws nothing. Blender's boolean can leave slivers.
11. **Hot reload mid-export:** Blender writes the .obj before the .mtl, so the first event can see a new .obj with an old .mtl and fail. The reload keeps the old meshes and logs the problem (`reload_models`, unchanged), and the .mtl's event reloads cleanly. Nothing is added for this.

### The reader: new leaf package `src/model_obj/`

`model_obj.odin` imports `core:fmt`, `core:os`, `core:strconv`, `core:strings`, `core:math` and `../platform` (for `join_path` only). It has no raylib and no game types. Its header comment states the subset below and the frame.

Constants: `MODELS_DIRECTORY :: "models"`, `MODEL_FILE_EXTENSION :: ".obj"`, `MATERIAL_FILE_EXTENSION :: ".mtl"`, `PART_GROUP_NAME :: "part"`.

Types:
```odin
Obj_Material :: struct {
	name:     string, // a slice of the material file's text
	colour:   [3]u8,  // Kd
	emissive: bool,   // any Ke channel above 0
}
Obj_Triangle :: struct {
	corners:  [3][3]f32, // file order, the file's frame (cells)
	normal:   [3]f32,    // normalised sum of the face's vn; zero when a corner has none or the sum is zero
	colour:   [3]u8,
	emissive: bool,
	part:     bool,      // in the group named part
}
Obj_Model :: struct {
	triangles: [dynamic]Obj_Triangle,
}
```

Procedures. Every problem string from a parse starts with `line N: `, N counted from 1.
- `model_file_path :: proc(data_directory, id: string) -> string`: `<data>/models/<id>.obj` in the temp allocator. Called by `load_machine_model_mesh`.
- `is_material_library_name :: proc(name: string) -> bool`: a non-empty stem of `a`-`z`, `0`-`9` and `_`, followed by `.mtl`. Called by `material_library_name`.
- `material_library_name :: proc(text: string) -> (name: string, line: int, problem: string)`: the single `mtllib` line's one name, or "" when there is none. Refuses a second `mtllib`, a line with other than one name, and a name that `is_material_library_name` refuses. Called by `load_obj_model_file`.
- `parse_material_library :: proc(text: string, allocator := context.allocator) -> (materials: [dynamic]Obj_Material, problem: string)`: the MTL subset. `materials` is in allocator, also on a problem.
- `parse_obj_model :: proc(text: string, materials: []Obj_Material, allocator := context.allocator) -> (model: Obj_Model, problem: string)`: the OBJ subset. Fan triangulates (corners 0, i, i+1). `triangles` is in allocator, also on a problem.
- `load_obj_model_file :: proc(path: string, allocator := context.allocator) -> (model: Obj_Model, problem: string)`: reads the .obj (temp), then `material_library_name`, then reads `<directory of path>/<name>` (temp), then parses both. Problems: `invalid model <obj path>: line N: ...`, `invalid model <mtl path>: line N: ...`, `cannot read <obj path>: <error>`, and for a missing MTL `invalid model <obj path>: line N: cannot read <mtl path>: <error>`, where N is the `mtllib` line. Nothing is kept on a problem. Called by `load_obj_machine_model_mesh`.
- `destroy_obj_model :: proc(model: Obj_Model)`.
- Private helpers (names free, each 5 to 15 lines): parse three finite floats from the fields (`strconv.parse_f32`, refusing NaN and infinity), parse one corner token, parse an index with `strconv.parse_int` checked to 1..count (never `parse_i64`, which wraps), and find a material by name.

Lines: split on `\n`, trim a trailing `\r` and surrounding blanks, and split into fields on blanks (`strings.fields`). An empty line, or one whose first field starts with `#`, is skipped. A `#` after content is not a comment, since Blender never writes one there.

#### The OBJ and MTL subset (the reader's tests follow this table)

| File | Keyword | Read as | Refused (problem names the line) |
|---|---|---|---|
| OBJ | `v x y z [more]` | a position; numbers after the third are ignored (vertex colours) | fewer than 3 numbers, a number that does not parse or is not finite |
| OBJ | `vn x y z` | a normal | as `v` |
| OBJ | `vt ...` | ignored (no textures) | never |
| OBJ | `f c1 c2 c3 [...]` | a polygon, fan triangulated; each corner is `v`, `v/vt`, `v//vn` or `v/vt/vn`; the vt slot is ignored | fewer than 3 corners; more than 3 slash parts; an empty or non-integer v; v or vn outside 1..count so far (zero, negative and forward references included); no `usemtl` before the face |
| OBJ | `o name`, `g [name]` | starts a group; the faces after are the part when the first name is `part`, else body (`g` without a name is body); faces before any group are body | never |
| OBJ | `usemtl name` | the material of the faces after it | a name not in the library (also when there is no `mtllib`) |
| OBJ | `mtllib name` | the library beside the file | a second `mtllib`, not exactly one name, not a plain `.mtl` name |
| OBJ | `#`, `s`, `l`, `p`, anything else | ignored | never |
| MTL | `newmtl name` | starts a material | no name; a name already defined |
| MTL | `Kd r g b` | the colour, each channel 0 to 1, byte = channel * 255 + 0.5 truncated | before any `newmtl`; not 3 numbers; a channel outside 0 to 1 |
| MTL | `Ke r g b` | emissive when any channel is above 0 | before any `newmtl`; not 3 numbers; a negative or non-finite channel |
| MTL | `Ns`, `Ka`, `Ks`, `Ni`, `d`, `illum`, `map_*`, `#`, anything else | ignored | never |
| MTL | end of file | | a material without `Kd`: the problem names its `newmtl` line |

### The mesher and the loader (game package)

New file `src/model_triangle_mesh.odin` (presentation cluster by its prefix), importing `core:fmt`, `core:math/linalg`, `core:os` and `model_obj`:
- `MODEL_SHADE_BASE :: 0.775`, `MODEL_SHADE_GRADIENT :: [3]f32{0.03, 0.225, 0.085}`, `MODEL_FOOTPRINT_TOLERANCE_CELLS :: 0.02`, each with a comment giving the reason (answer 1, the item).
- `model_normal_shade :: proc(normal: [3]f32) -> f32`: `clamp(MODEL_SHADE_BASE + linalg.dot(normal, MODEL_SHADE_GRADIENT), 0, 1)` for a unit normal.
- `triangle_winding_normal :: proc(corners: [3][3]f32) -> [3]f32`: `normalize(cross(b - a, c - a))`, zero for zero area. Counter-clockwise seen from the front, as raylib culls.
- `obj_triangle_normal :: proc(triangle: model_obj.Obj_Triangle) -> [3]f32`: `triangle.normal` when non-zero, else the winding normal.
- `obj_triangle_colour :: proc(triangle: model_obj.Obj_Triangle) -> [4]u8`: emissive gives `{Kd, 255}`, otherwise `shade_colour({Kd, 255}, model_normal_shade(normal))` (the existing `shade_colour`).
- `append_model_triangle :: proc(mesh: ^Model_Mesh, corners: [3][3]f32, colour: [4]u8)`: three unshared vertices with indices base+0, +1, +2, in file order.
- `mesh_obj_triangles :: proc(model: model_obj.Obj_Model, part: bool, allocator := context.allocator) -> (meshes: Model_Layers, problem: string)`: the triangles whose `part` matches, each into `.Emissive` or `.Lit`. Skips a triangle whose normal is zero. Refuses `more than %d vertices` once a layer would pass `MESH_PART_VERTEX_LIMIT`, the voxel mesher's check and text.
- `model_layers_bounds :: proc(body, part: Model_Layers) -> (minimum, maximum: [3]f32)`: over every position of both. Only called with a non-empty body.
- `model_footprint_problem :: proc(minimum, maximum: [3]f32, footprint: [3]i32) -> string`: "" when x is within ±(footprint.x / 2 + tolerance), z within ±(footprint.z / 2 + tolerance) and minimum y ≥ -tolerance. Otherwise for example `reaches x 1.050, past the footprint's 1.000`. No upper bound on y.
- `mesh_obj_machine_model :: proc(model: model_obj.Obj_Model, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string)`: body = `mesh_obj_triangles(model, false)`, part = `(model, true)`. It refuses `no triangles` for an empty body, `no group named part for its %v motion` when `motion_has_part(kind)` and the part is empty, and `a group named part but its motion moves none` the other way round, then the footprint problem. `top = maximum.y`. Destroys what it made on a problem. It is pure, so the tests use it without files.
- `load_obj_machine_model_mesh :: proc(path: string, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string)`: `load_obj_model_file` (temp allocator), then `mesh_obj_machine_model`, then `destroy_obj_model`. Problems come out as `machine %q: <reader problem>` and `machine %q: model <id>: <mesher problem>`.

`src/model_mesh.odin`:
- `load_machine_model_mesh` (same signature) keeps the arm branch first. Then: `if obj := model_obj.model_file_path(data_directory, machine.model); os.is_file(obj) { return load_obj_machine_model_mesh(obj, machine, allocator) }`, else `load_voxel_machine_model_mesh(data_directory, machine, allocator)`. The resolution is per machine: an .obj wins, a .vox is the fallback.
- `load_voxel_machine_model_mesh :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string)`: today's voxel body of `load_machine_model_mesh`, moved verbatim.
- `#assert(model_obj.MODELS_DIRECTORY == model_vox.MODELS_DIRECTORY)` near the imports. The two readers share the directory until 0206 removes `model_vox`.
- The header comment adds the OBJ path (cells, no scaling, the shade, the part group). `model_face_shades` stays for the voxel mesher (until 0206).

`src/data_watch.odin`: a new `is_model_file_name :: proc(name: string) -> bool` (no leading `.`, and a suffix of `model_vox.MODEL_FILE_EXTENSION`, `model_obj.MODEL_FILE_EXTENSION` or `model_obj.MATERIAL_FILE_EXTENSION`) is used by the `model_vox.MODELS_DIRECTORY` case of `data_file_category`. The `Models` comment becomes "The .vox, .obj and .mtl files under models/". The game package adds `import "model_obj"` here.

Unchanged: `render_models.odin`, `hot_reload.odin` (`reload_models` already reloads every machine through `replace_machine_models`, and the `.Models` directory stays `model_vox.MODELS_DIRECTORY`), `model_motion.odin`, `model_arm.odin`, `render_player_model.odin`, `model_transform`.

`src/machine.odin` line 311 comment: "The id of data/models/<model>.obj (model_obj), else <model>.vox (model_vox), or "" for the placeholder box."

### Data

- New `data/models/stone_furnace.obj`, `stone_furnace.mtl`, `burner_mining_drill.obj`, `burner_mining_drill.mtl`, all written by the generator.
- Delete `data/models/stone_furnace.vox`, `burner_mining_drill.vox` and `burner_mining_drill_part.vox`.
- `data/machines.sjson`: the records are unchanged. The header's `model` paragraph becomes: names `data/models/<model>.obj` with its `.mtl` when that file exists, else `<model>.vox`. An OBJ is in cells of the unrotated footprint (x and z centred, y from the bottom, +x the front, y up), is not scaled, must stay within the footprint's x and z (0.02 cells of slack) and above its bottom, and may rise above its height. Its group `part` is the moving part (the `motion` paragraph's `<model>_part.vox` for a voxel model). A material with a non-zero `Ke` is emissive. Models are written by `tools/make_models.py` (OBJ) and `tools/make_placeholder_models.py` (voxel).

### The generator: `tools/models/` in Blender

Files:
- `tools/blender` (sh, executable): `exec <blender> --background --factory-startup --python-exit-code 1 --python "$(realpath "$1")" -- "${@:2}"`, where `<blender>` is `blender` when `command -v blender` finds it and `flatpak run org.blender.Blender` otherwise. Usage: `tools/blender tools/make_models.py [model ...]`. All flags are checked against Blender 5.2's `--help`.
- `tools/make_models.py`: the entry, run inside Blender. It puts its own directory on `sys.path`, reads the model names after `--` (none means all, an unknown name exits 1 listing the known ones), and for each in `models.machines.MACHINES` order: `kit.clear_scene()`, `build()`, `kit.export(name, REPOSITORY_ROOT / "data" / "models")`. It prints `wrote data/models/<name>.obj`.
- `tools/models/__init__.py` (empty), `tools/models/palette.py`, `tools/models/kit.py`, `tools/models/machines/__init__.py` (`MACHINES = {"stone_furnace": stone_furnace.build, "burner_mining_drill": burner_mining_drill.build}`), `tools/models/machines/stone_furnace.py`, `tools/models/machines/burner_mining_drill.py`.

`palette.py`: `MATERIALS` maps a name to an sRGB byte triple and an emissive flag. The values follow DESIGN.md's palette, desaturated for daylight: `steel` (74, 84, 99), `steel_dark` (52, 58, 68), `galvanised` (150, 156, 160), `soot` (40, 38, 37), `hazard_black` (34, 34, 36), `mining_ochre` (176, 132, 52), `smelting_brick` (140, 66, 48), `power_yellow` (206, 168, 46), `fluids_teal` (54, 128, 124), `logistics_grey` (118, 120, 122), `science_white` (208, 212, 214), `heat_glow` (255, 140, 48, emissive), `electric_glow` (80, 220, 240, emissive). Only the ones a machine uses become materials in its file.

`kit.py`. Blender's frame for every machine is front +X, up +Z and one unit per cell, the footprint spanning x ±w/2, y ±d/2 and z 0..h (Blender y = -game z):
- `clear_scene()`: `bpy.ops.wm.read_factory_settings(use_empty=True)`, then removes orphan materials and meshes.
- `material(name)`: get or create a material from `palette.MATERIALS`. On the Principled BSDF node: `Base Color` = bytes / 255 with alpha 1; `Emission Color` = black or the glow; `Emission Strength` = 0 or 1 (answer 6). Input names were read off 5.2.
- `box(minimum, maximum, material, bevel=0.0)`, `cylinder(centre_xy, z0, z1, radius, sides, material, bevel=0.0, axis="Z")` (a `bmesh.ops.create_cone` with equal radii, `cap_ends=True`, rotated for axes X and Y) and `cone(centre_xy, z0, z1, radius_bottom, radius_top, sides, material, rotation=0.0)`. Each makes one mesh object from bmesh and assigns the material. With `bevel` it adds a Bevel modifier: `width=bevel`, `segments=1`, `limit_method='ANGLE'`, default angle, `harden_normals=False`.
- `cut(target, cutter)`: a Boolean modifier on target with `operation='DIFFERENCE'`, `solver='EXACT'`, `object=cutter`, and the cutter hidden from export (deleted after `join` applies it).
- `join(objects, name)`: for each object, a mesh from the evaluated object (`bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))`, which applies modifiers and keeps materials). Then it joins those into one object called `name`, sets every polygon's `use_smooth = False` (flat, so the exporter writes one `vn` per face) and deletes the sources. Every machine ends with one object `body` and, for a machine with a moving part, one `part`.
- `export(name, directory)`: `bpy.ops.wm.obj_export(filepath=str(directory / f"{name}.obj"), check_existing=False, export_animation=False, forward_axis='NEGATIVE_Z', up_axis='Y', global_scale=1.0, apply_modifiers=True, apply_transform=True, export_eval_mode='DAG_EVAL_VIEWPORT', export_selected_objects=False, export_uv=False, export_normals=True, export_colors=False, export_materials=True, export_pbr_extensions=False, path_mode='STRIP', export_triangulated_mesh=True, export_curves_as_nurbs=False, export_object_groups=False, export_material_groups=False, export_vertex_groups=False, export_smooth_groups=False)`. Every option name and enum was verified against `bpy.ops.wm.obj_export` in Blender 5.2.0 LTS here. With `export_object_groups=False` the `o` line is the object's name alone, so `part` reaches the reader as written. With `export_uv=False` the corners are `v//vn`.

The two proof machines. Both are 2 by 2 by 2 cells (1 m at the 500 mm pitch, so 0.3 m is 0.6 cells), in Blender coordinates (x front, y = -game z, z up). Bevels are 0.03 to 0.05. Counts are kept uneven (DESIGN.md, No perceivable repetition). Budget: body 200 to 800 triangles, part under 200, at most 8 materials. If a number below makes the footprint check fail, the implementer moves that volume inward and says so.
- **Stone furnace** (smelting, `body` only, motion `glow` unchanged). Materials: steel_dark, smelting_brick, steel, galvanised, soot, heat_glow.
  1. Base plate, steel_dark: x ±0.96, y ±0.96, z 0 to 0.12, bevel 0.03.
  2. Primary firebox, smelting_brick: x -0.82 to 0.78, y ±0.80, z 0.12 to 1.25, bevel 0.05.
  3. Mouth on the front: cut a box x 0.60 to 0.90, y ±0.30, z 0.30 to 0.75 from the firebox. Inside: a soot back plate x 0.58 to 0.62 (y and z as the mouth), a heat_glow coal bed x 0.62 to 0.68, y ±0.26, z 0.30 to 0.38 (the thin inset strip, on the working side), and a steel lintel x 0.76 to 0.84, y ±0.36, z 0.75 to 0.83.
  4. Two steel bands around the firebox, x -0.84 to 0.80, y ±0.82: z 0.16 to 0.22 and z 0.88 to 0.94, both clear of the mouth.
  5. Hopper (secondary), galvanised: a 4-sided cone turned 45 degrees at (-0.30, 0.25), z 1.25 to 1.50, radius 0.42 to 0.25.
  6. Chimney (secondary), steel_dark: a 10-sided cylinder at (-0.50, -0.45), radius 0.14, z 1.25 to 2.35 (above the footprint's height, allowed), with a steel rim cylinder of radius 0.18 at z 2.25 to 2.33.
  7. Ribs: steel boxes 0.04 thick on the two side faces (y ±0.80 to ±0.83), z 0.22 to 0.88, at x -0.61, -0.19 and 0.37 on +y, and at x -0.55 and 0.12 on -y.
  8. Scale cue: an ash door on the +y side, steel x -0.45 to -0.05, y 0.80 to 0.84, z 0.24 to 0.52, with a galvanised 6-sided handle cylinder along x.
- **Burner mining drill** (mining, `body` plus `part`; motion pump along y by -0.25, unchanged). The mast stands at the back, so the moving head shows over the low housing from the front and from above. Materials: steel_dark, mining_ochre, steel, galvanised, heat_glow.
  1. Skid, steel_dark: two rails x ±0.95, y 0.60 to 0.90 and -0.90 to -0.60, z 0 to 0.14, bevel 0.03, and a cross plate x -0.95 to -0.15, y ±0.60, z 0.06 to 0.12.
  2. Primary engine housing, mining_ochre: x -0.10 to 0.90, y ±0.75, z 0.14 to 0.85, bevel 0.05. On its front face a heat_glow firebox slit x 0.90 to 0.93, y -0.60 to -0.30, z 0.30 to 0.36, and a galvanised output chute x 0.90 to 0.98, y 0.10 to 0.45, z 0.20 to 0.40.
  3. Mast (secondary), steel: four 0.08-square legs at x -0.85 and -0.25, y ±0.35, z 0.14 to 1.90, cross braces at z 0.70 and 1.30, and a steel_dark crown block x -0.90 to -0.20, y ±0.40, z 1.82 to 1.95.
  4. Burner chimney (secondary), steel_dark: an 8-sided cylinder at (0.55, 0.45), radius 0.10, z 0.85 to 1.45.
  5. Bore collar, steel_dark: a 10-sided cylinder at (-0.55, 0), radius 0.22, z 0.14 to 0.24.
  6. Scale cue: ladder rungs, galvanised 6-sided cylinders of radius 0.025 along y between the back legs (x -0.85, y ±0.35) at z 0.45, 1.05 and 1.62.
  7. `part`, built about the shaft axis through Blender (-0.55, 0) (footprint point (0.45, y, 1.0)): a galvanised gearbox x -0.72 to -0.38, y ±0.20, z 1.25 to 1.60, bevel 0.03; a steel_dark motor cylinder of radius 0.12, 10 sides, z 1.60 to 1.78; a steel shaft of radius 0.06, 8 sides, z 0.45 to 1.25; and a mining_ochre bit cone of radius 0.10 to 0, 8 sides, z 0.25 to 0.45. At full stroke (-0.25) the tip sinks into the collar.

`tools/make_placeholder_models.py`: remove the `stone_furnace` and `burner_mining_drill` entries from `MODELS` and their two builder functions, plus any constant or helper that only they used (grep each). The docstring says these two are made by `tools/make_models.py`.

### Tests

`src/model_obj/model_obj_test.odin` (package `model_obj`; OBJ and MTL as string literals):
- `test_a_quad_is_fan_triangulated`: `f 1 2 3 4` gives two triangles, corners (1, 2, 3) and (1, 3, 4) in file order.
- `test_every_corner_form_is_read`: one face each in the forms `v`, `v/vt`, `v//vn` and `v/vt/vn` gives four triangles. The `vn` forms carry the normalised normal (a `vn 0 2 0` reads as (0, 1, 0)), the other two a zero normal.
- `test_the_part_group_is_the_moving_part`: faces before any group, after `o body`, after `g` with no name and after `g other` are body; after `o part` and `g part` they are part.
- `test_emissive_materials_come_from_ke`: a material with `Kd 0.5 0.25 1` and `Ke 0 0 0` gives (128, 64, 255) and not emissive. One with `Kd 1 0.549 0.188` and `Ke 1 0.5 0` gives (255, 140, 48) and emissive. Blender's `Ns`, `Ka`, `Ks`, `Ni`, `d` and `illum` lines are ignored.
- `test_malformed_obj_text_is_refused_naming_the_line`, a table of text and expected `line N:` prefix: an unknown material at `usemtl`, `f 0 1 2`, `f 1 2 9` past the count, `f -1 -2 -3`, `f 1 2`, a face before any `usemtl`, `v 1 2`, `v 1 nan 2`, `f 1//7 2//7 3//7` past the normals, `f 1/1/1/1 2 3`.
- `test_malformed_mtl_text_is_refused_naming_the_line`: `Kd` before `newmtl`, `Kd 1.5 0 0`, `Kd 1 0`, `Ke -1 0 0`, a duplicate `newmtl`, and a material without `Kd` (named at its `newmtl` line).
- `test_a_model_file_problem_names_the_file_and_the_line`: in a temporary directory (`os.make_directory_temp`, removed): an .obj whose `mtllib missing.mtl` has no file names the .obj path, `line` and `missing.mtl`; a broken .mtl names the .mtl path; `mtllib ../outside.mtl` is refused; a missing .obj names its path.
- `test_a_model_file_loads_with_its_material_library`: a box written to the temporary directory loads with 12 triangles and the Kd colour.

`src/model_triangle_mesh_test.odin` (game package):
- `test_a_box_keeps_the_voxel_shades`: for each `Direction`, `model_normal_shade(direction_vector)` is within 0.1 of `model_face_shades[direction]` and within 1e-4 of the table in answer 1, and the normalised gradient's shade is exactly 1 (the clamp).
- `test_a_face_without_normals_is_shaded_from_its_winding`: the triangle (0, 0, 0), (0, 0, 1), (1, 0, 0) with zero normal meshes with shade 1.0 (it faces +y). Reversed it gets 0.55. A triangle with `vn` pointing +x gets 0.805 whatever its winding.
- `test_obj_and_voxel_meshes_wind_alike`: every triangle of a single voxel's `mesh_voxel_model` has a winding normal pointing away from the voxel's centre, and so does every triangle of an OBJ unit box (outward, counter-clockwise) through `mesh_obj_triangles`. This proves both agree with the culling.
- `test_emissive_triangles_mesh_apart_without_the_shade`: an emissive triangle lands in `.Emissive` with its Kd unshaded, a lit one in `.Lit`, shaded.
- `test_an_obj_model_must_stay_on_its_footprint`: through `mesh_obj_machine_model` with footprint {2, 2, 2}: x 1.05 is refused naming x, z -1.05 naming z, y -0.05 naming the bottom. x 1.01 is accepted. A vertex at y 3.5 is accepted with `top` 3.5.
- `test_a_part_group_follows_the_motion`: a pump motion without a part group is refused, a part group with motion `.None` or `.Glow` is refused, and a pump with a part group fills `mesh.part`.
- `test_an_obj_layer_past_the_vertex_limit_is_refused`: 21845 triangles (65535 vertices) mesh, 21846 are refused with `more than 65536 vertices`.
- `test_a_degenerate_triangle_is_skipped`: three collinear corners without `vn` give no vertices.
- `test_an_obj_model_wins_over_a_voxel_model`: a temporary data directory with `models/box.obj`, `box.mtl` and `box.vox` (the bytes of `wooden_chest.vox`) loads the OBJ (vertex count three per triangle, the Kd colour). With the .obj removed, the .vox loads. A shipped machine with only a .vox (`wooden_chest`) still loading is covered by `test_a_missing_model_or_part_file_is_refused`.
- `test_the_shipped_obj_machines_load`: both machines from `shipped_machines()` have an .obj on disk and load. The furnace has an empty part, a non-empty emissive layer whose centroid has x > 0 (the front, pinning the export axes), and emissive colours exactly (255, 140, 48) (pinning Kd). The drill has a part of 1 to 199 triangles and an emissive layer. Both bodies have 200 to 800 triangles (lit plus emissive vertices / 3). Each .mtl has at most 8 `newmtl` lines. `stone_furnace.vox`, `burner_mining_drill.vox` and `burner_mining_drill_part.vox` are gone.

Changed tests:
- `test_the_shipped_furnace_glow_is_emissive` (`model_motion_test.odin`) is deleted, since its .vox is gone and `test_the_shipped_obj_machines_load` covers it. Drop `import "model_vox"` there if nothing else uses it.
- `test_the_shipped_machine_models_mesh` (`model_mesh_test.odin`): the top check becomes `without_model || mesh.top > 0 && (is_obj || mesh.top <= f32(machine.footprint.y))`, where `is_obj` is `os.is_file(model_obj.model_file_path(...))`.
- `test_data_files_fall_into_their_categories` (`data_watch_test.odin`) adds `models/stone_furnace.obj` and `models/stone_furnace.mtl` as `.Models`, and `models/.stone_furnace.obj.swp` and `models/stone_furnace.blend` as `.Ignored`.
- `test_shipped_spinning_parts_turn_about_their_middle` reads `<model>_part.vox` for spin machines. No spin machine moves to OBJ here, so it stays. 0205 must switch it to the loaded part mesh's bounds.

Verify commands: `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows` (a new package), `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`. Run `tools/blender tools/make_models.py` twice, and `cmp` the four files between the runs to show the same bytes.

### Docs

- `doc/presentation.md`, Machine models: bullet 1 covers the two readers and the resolution order (.obj, else .vox), the OBJ frame in cells with no scaling, the footprint check with its tolerance, the top read off the mesh (a chimney may rise above), the flat shade with its constants (and that `model_face_shades` serves the voxel mesher until 0206), the part group and `Ke` emissive. Bullet 3: `tools/make_models.py` writes the OBJ machines in Blender ([build.md](build.md), Models), and `tools/make_placeholder_models.py` writes the rest.
- `doc/content.md`, Models: the first bullet becomes: an OBJ machine is authored by a script under `tools/models/machines/` in cells with +x the front, in the look of DESIGN.md (Art direction), and a voxel machine at 8 or 16 voxels per block until 0206. Also, in the Blocks section, "is emissive voxels in their models" becomes "is emissive materials or voxels in their models".
- `data/machines.sjson` header: the `model` paragraph (Data, above).
- `doc/code_map.md`: a Clusters row for `model_obj` ("the package `src/model_obj/`: the Wavefront OBJ and MTL reader", entry `model_obj.odin`, counts from `tools/code_graph.py`, audit presentation); `model_obj` added to every game cluster's allowed list and its own row `model_obj | platform`; the sentence under the table names `model_obj` beside `model_vox`; the presentation file list adds `model_triangle_mesh.odin` ("the OBJ mesher: flat shade, footprint check"); a Packages bullet for `model_obj` (`model_obj.odin`, `Obj_Model`, `load_obj_model_file`, `model_file_path`, imports `platform`, tests `model_obj_test.odin`).
- `doc/architecture.md`, Source layout: add `src/model_obj/` to the package list. Hot reload already says "models".
- `doc/build.md`: a Host toolchain row "Blender 5.2 LTS | Flatpak `org.blender.Blender` with host file access | only to regenerate models". A new section `## Models` after Source checks: `tools/blender` and how it finds Blender, `tools/blender tools/make_models.py [model ...]`, that the committed OBJ and MTL files are the product (build, tests and CI never run Blender), that one script in one Blender version writes the same bytes, the export options in one line, and the package layout.
- `doc/log/2026-10-03.md`, a new entry "The model pipeline (0204)" with answers 1 to 4 and 8 (the shade gradient and why the item's key failed, the export axes, the pump kept, the bottom tolerance, the strict part group).

### Hand-back lines that apply

- Memory a frame draws from: the meshes are still replaced only through `replace_machine_models` from `reload_models` and `use_machine_models`, between frames as today. There is no new path.
- A path built from a listing stays under its directory: the `mtllib` name must pass `is_material_library_name`, resolved beside the .obj (test above).
- A start-up load the game can make fail: a model that fails still leaves the machines as boxes (`use_machine_models`, unchanged).
- A number parsed from text is range checked: indices through `parse_int` to 1..count, Kd 0 to 1, Ke non-negative, every float finite (tests above).
- Tests use temporary directories only: the file tests above.
- Not applicable: the save layout, shared budgets, unbounded lists, UI audit cases.

### Questions to the main agent

1. The drill: keep `pump` (as specified, matching today's data), or switch it to `spin` with `axis = "y"`, `pivot = [0.45, 0, 1.0]`, as the item's wording says? A spin would also need `test_shipped_spinning_parts_turn_about_their_middle` to read OBJ parts in this item.
2. Approve the shade gradient (0.03, 0.225, 0.085) over the item's key, which breaks the item's own 0.1 bound on -z.
3. A model rising above its footprint moves everything `machine_model_top` feeds: the markers (`render_entities.odin:355`), the ghost chevron (`render_player.odin:216`) and the particle source (`render_particles.odin:85`, so the furnace's smoke leaves at the chimney top, 2.35). The item intends the first two. Confirm the third is wanted, since it follows the top of any volume, not the chimney.

### Approval (main agent, 2026-10-03)

Approved as specified. Answers: 1, keep `pump`, the record stays; the item's "spins" was wrong, a later item may switch it. 2, the gradient (0.03, 0.225, 0.085) with the clamp is approved. 3, the particle source following the top is wanted: smoke leaves at the chimney, and a machine whose highest volume is not its chimney is an authoring choice.
