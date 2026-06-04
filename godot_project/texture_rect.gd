# Drives the GPU compute sand simulation using Godot's RenderingDevice API.
# Grid state lives in a single RGBA32F texture: r=1.0 is sand, r=0.0 is empty.
extends TextureRect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var grid_texture: RID
var uniform_set: RID

var brush_radius: int = 5
var brush_type: int = 1  # 1 = sand, 2 = water, 3 = wood, 0 = empty
const WIDTH: int = 126
const HEIGHT: int = 126
const SHADER_PATH: String = "res://sand.glsl"

var simulation_running: bool = false
var frame_counter: int = 0
const FRAMES_PER_UPDATE: int = 1   # lower = faster sim. Raise to watch closely.

# Cycling through all four offsets covers every 2×2 block without overlap (Margolus partitioning).
var phase_offsets := [Vector2i(0,0), Vector2i(-1,-1), Vector2i(0,-1), Vector2i(-1,0)]
var frame_index: int = 0

func _ready():
	rd = RenderingServer.get_rendering_device()
	if not rd:
		printerr("RenderingDevice not available! Switch renderer to Forward+.")
		return

	grid_texture = create_texture()
	initialize_sand_blob(grid_texture)

	if not create_compute_pipeline():
		printerr("Failed to create pipeline!")
		return

	uniform_set = create_uniform_set(grid_texture)

	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_rd = Texture2DRD.new()
	tex_rd.texture_rd_rid = grid_texture
	texture = tex_rd

	print("Ready! Space = run/pause, Right Arrow = single step")

func create_texture() -> RID:
	var fmt = RDTextureFormat.new()
	fmt.width = WIDTH
	fmt.height = HEIGHT
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT # float texture; only r channel used
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(fmt, RDTextureView.new())

func initialize_sand_blob(tex: RID) -> void:
	var data = PackedFloat32Array()
	data.resize(WIDTH * HEIGHT * 4)
	for i in range(data.size()):
		data[i] = 0.0
	var cx = WIDTH / 2
	var cy = HEIGHT / 4 # upper area so it has room to fall
	var r = 8
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:  # inside circle of radius r
				var idx = (y * WIDTH + x) * 4
				data[idx] = 1.0
				data[idx + 1] = 1.0
				data[idx + 2] = 1.0
				data[idx + 3] = 1.0
	
	cx = WIDTH * 3 / 5
	cy = HEIGHT * 5 / 16
	r = 3
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:  # inside circle of radius r
				var idx = (y * WIDTH + x) * 4
				data[idx] = 3.0
				data[idx + 1] = 0.6
				data[idx + 2] = 0.4
				data[idx + 3] = 1.0
				
	cx = WIDTH * 2 / 5
	cy = HEIGHT * 3 / 16
	r = 6
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:  # inside circle of radius r
				var idx = (y * WIDTH + x) * 4
				data[idx] = 2.0
				data[idx + 1] = 0.1
				data[idx + 2] = 0.9
				data[idx + 3] = 1.0
	
	rd.texture_update(tex, 0, data.to_byte_array())
	print("Sand blob initialized")

func create_compute_pipeline() -> bool:
	if not FileAccess.file_exists(SHADER_PATH):
		printerr("Shader file not found: ", SHADER_PATH)
		return false
	var f = FileAccess.open(SHADER_PATH, FileAccess.READ)
	var code = f.get_as_text()
	f.close()
	var src = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code
	var spirv = rd.shader_compile_spirv_from_source(src)
	var err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err != "":
		printerr("Shader compile error: ", err)
		return false
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		printerr("shader invalid"); return false
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		printerr("pipeline invalid"); return false
	print("Pipeline created!")
	return true

func create_uniform_set(tex: RID) -> RID:
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0 # matches layout(binding = 0) in the shader
	u.add_id(tex)
	return rd.uniform_set_create([u], shader, 0)

func step_once() -> void:
	var off: Vector2i = phase_offsets[frame_index]
	# Push current phase offset and grid size to the shader.
	var pc = PackedInt32Array([off.x, off.y, WIDTH, HEIGHT])
	var pc_bytes = pc.to_byte_array()

	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_set_push_constant(cl, pc_bytes, pc_bytes.size())
	# Each shader invocation handles a 2×2 block, so dispatch half the grid in each dimension.
	# Workgroup size is 16×16, so round up to the nearest multiple of 16.
	var blocks_x = WIDTH / 2
	var blocks_y = HEIGHT / 2
	var groups_x = (blocks_x + 15) / 16
	var groups_y = (blocks_y + 15) / 16
	rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
	rd.compute_list_end()

	frame_index = (frame_index + 1) % phase_offsets.size()
	
func mouse_click():
	var local_pos = get_local_mouse_position()
	get_rect()
	var tex_pos = Vector2i(int(local_pos.x * WIDTH / get_rect().size.x), int(local_pos.y * HEIGHT / get_rect().size.y))
	if tex_pos.x >= 0 and tex_pos.x < WIDTH and tex_pos.y >= 0 and tex_pos.y < HEIGHT:
		fill_radius(tex_pos)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: brush_type = 1
		elif event.keycode == KEY_2: brush_type = 2
		elif event.keycode == KEY_3: brush_type = 3
		elif event.keycode == KEY_0: brush_type = 0
		elif event.keycode == KEY_5: brush_radius = 3
		elif event.keycode == KEY_6: brush_radius = 10
		elif event.keycode == KEY_7: brush_radius = 50
		elif event.keycode == KEY_SPACE:
			simulation_running = not simulation_running
			print("Simulation: ", "RUNNING" if simulation_running else "PAUSED")
		elif event.keycode == KEY_RIGHT:
			step_once()
			print("Stepped once. frame_index now ", frame_index)

func fill_radius(center: Vector2i):
	var data = rd.texture_get_data(grid_texture, 0).to_float32_array()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var dx = x - center.x
			var dy = y - center.y
			if dx * dx + dy * dy <= brush_radius * brush_radius:
				var idx = (y * WIDTH + x) * 4
				if brush_type == 0:
					data[idx]     = 0.0
					data[idx + 1] = 0.0
					data[idx + 2] = 0.0
					data[idx + 3] = 1.0
				elif brush_type == 1:
					data[idx]     = 1.0
					data[idx + 1] = 1.0
					data[idx + 2] = 1.0
					data[idx + 3] = 1.0
				elif brush_type == 2:
					data[idx]     = 2.0
					data[idx + 1] = 0.1
					data[idx + 2] = 0.9
					data[idx + 3] = 1.0
				elif brush_type == 3:
					data[idx]     = 3.0
					data[idx + 1] = 0.6
					data[idx + 2] = 0.2
					data[idx + 3] = 1.0
					
	rd.texture_update(grid_texture, 0, data.to_byte_array())
			
func _process(_delta):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		mouse_click()
	if not rd or not pipeline.is_valid(): return
	if not simulation_running: return
	frame_counter += 1
	if frame_counter < FRAMES_PER_UPDATE: return
	frame_counter = 0
	step_once()

func _exit_tree():
	if rd:
		if uniform_set.is_valid(): rd.free_rid(uniform_set)
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if shader.is_valid(): rd.free_rid(shader)
		if grid_texture.is_valid(): rd.free_rid(grid_texture)
