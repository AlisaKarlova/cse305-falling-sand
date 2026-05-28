extends TextureRect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var textures: Array[RID] = [RID(), RID()]
var current_texture_index: int = 0
var uniform_sets: Array[RID] = [RID(), RID()]

const WIDTH: int = 512
const HEIGHT: int = 512
const SHADER_PATH: String = "res://gol.glsl"

var simulation_running: bool = false
var frame_counter: int = 0
const FRAMES_PER_UPDATE: int = 10

func _ready():
	rd = RenderingServer.get_rendering_device()
	
	if not rd:
		printerr("RenderingDevice not available!")
		return
	
	# Create textures
	textures[0] = create_texture()
	textures[1] = create_texture()
	
	# Initialize with simple pattern
	initialize_simple_pattern(textures[0])
	initialize_simple_pattern(textures[1])
	
	# Load and compile shader
	if not create_compute_pipeline():
		printerr("Failed to create pipeline!")
		return
	
	# Create uniform sets
	uniform_sets[0] = create_uniform_set(textures[0], textures[1])
	uniform_sets[1] = create_uniform_set(textures[1], textures[0])
	
	# Display settings
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	
	# Display initial texture
	var tex_rd = Texture2DRD.new()
	tex_rd.texture_rd_rid = textures[0]
	texture = tex_rd
	
	print("Ready! Press Space to start/stop simulation")

func create_texture() -> RID:
	var format = RDTextureFormat.new()
	format.width = WIDTH
	format.height = HEIGHT
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
					   RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
					   RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					   RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	return rd.texture_create(format, RDTextureView.new())

func initialize_simple_pattern(texture_rid: RID) -> void:
	var data = PackedFloat32Array()
	data.resize(WIDTH * HEIGHT * 4)
	
	# Fill with zeros (all black/dead)
	for i in range(data.size()):
		data[i] = 0.0
	
	# Draw a simple glider pattern at the center
	var cx = WIDTH / 2
	var cy = HEIGHT / 2
	
	# Glider pattern coordinates (relative to center)
	var glider = [
		[0, -1], [1, 0], [-1, 1], [0, 1], [1, 1]
	]
	
	# Draw the glider multiple times in different positions
	for i in range(20):
		var offset_x = randi() % (WIDTH - 100) + 50
		var offset_y = randi() % (HEIGHT - 100) + 50
		
		for cell in glider:
			var x = cell[0] + offset_x
			var y = cell[1] + offset_y
			
			if x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT:
				var idx = (y * WIDTH + x) * 4
				data[idx] = 1.0      # R
				data[idx + 1] = 1.0  # G
				data[idx + 2] = 1.0  # B
				data[idx + 3] = 1.0  # A
	
	# Also add a blinker (oscillator)
	for i in range(10):
		var offset_x = randi() % (WIDTH - 100) + 50
		var offset_y = randi() % (HEIGHT - 100) + 50
		
		for dy in range(-1, 2):
			var y = offset_y + dy
			
			if y >= 0 and y < HEIGHT:
				var idx = (y * WIDTH + offset_x) * 4
				data[idx] = 1.0
				data[idx + 1] = 1.0
				data[idx + 2] = 1.0
				data[idx + 3] = 1.0
	
	rd.texture_update(texture_rid, 0, data.to_byte_array())
	print("Pattern initialized")

func create_compute_pipeline() -> bool:
	if not FileAccess.file_exists(SHADER_PATH):
		printerr("Shader file not found: ", SHADER_PATH)
		return false
	
	var file = FileAccess.open(SHADER_PATH, FileAccess.READ)
	var shader_code = file.get_as_text()
	file.close()
	
	var shader_source = RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = shader_code
	
	var shader_spirv = rd.shader_compile_spirv_from_source(shader_source)
	
	var error = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if error != "":
		printerr("Shader compilation error: ", error)
		return false
	
	shader = rd.shader_create_from_spirv(shader_spirv)
	
	if not shader.is_valid():
		printerr("Failed to create shader")
		return false
	
	pipeline = rd.compute_pipeline_create(shader)
	
	if not pipeline.is_valid():
		printerr("Failed to create pipeline")
		return false
	
	print("Pipeline created!")
	return true

func create_uniform_set(input_texture: RID, output_texture: RID) -> RID:
	var input_uniform = RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_uniform.binding = 0
	input_uniform.add_id(input_texture)
	
	var output_uniform = RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding = 1
	output_uniform.add_id(output_texture)
	
	return rd.uniform_set_create([input_uniform, output_uniform], shader, 0)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		simulation_running = !simulation_running
		print("Simulation: ", "RUNNING" if simulation_running else "PAUSED")

func _process(delta: float) -> void:
	if not rd or not pipeline.is_valid():
		return
	
	if not simulation_running:
		return
	
	# Slow down the simulation
	frame_counter += 1
	if frame_counter < FRAMES_PER_UPDATE:
		return
	frame_counter = 0
	
	var input_idx = current_texture_index
	var output_idx = 1 - current_texture_index
	
	# Run compute shader
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[input_idx], 0)
	
	var groups_x = (WIDTH + 15) / 16
	var groups_y = (HEIGHT + 15) / 16
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()
	
	# Update display with output texture
	var tex_rd = Texture2DRD.new()
	tex_rd.texture_rd_rid = textures[output_idx]
	texture = tex_rd
	
	# Swap for next frame
	current_texture_index = output_idx

func _exit_tree():
	if rd:
		if shader.is_valid(): rd.free_rid(shader)
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if textures[0].is_valid(): rd.free_rid(textures[0])
		if textures[1].is_valid(): rd.free_rid(textures[1])
		if uniform_sets[0].is_valid(): rd.free_rid(uniform_sets[0])
		if uniform_sets[1].is_valid(): rd.free_rid(uniform_sets[1]) 
