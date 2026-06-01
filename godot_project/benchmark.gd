# GPU benchmark for the Margolus sand shader.
#
# Mirrors the sequential C++ benchmark so the two
# implementations are timed in the SAME manner:
#   * identical sand-only scene (same blobs/radii, no wood),
#   * untimed warmup steps, then a single wall-clock span around N steps,
#   * reports elapsed_s and cell_updates_per_s (CUPS),
#   * conservation check on the sand count,
#   * prints one grep-able "BENCH key=value ..." line.
#
# Runs without a window via local RenderingDevice
# so we can submit/sync explicitly and time GPU work end-to-end:
# godot --path godot_project --script res://benchmark.gd --width 128 --height 128 --steps 500 --warmup 5
# Args after the "--" are parsed below; defaults match the C++ Args struct.
extends SceneTree

const SHADER_PATH := "res://sand.glsl"

# Margolus partition shifts, same order as texture_rect.gd.
const PHASE_OFFSETS := [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0)]

# Defaults mirror the C++ Args struct in main.cpp.
var width: int = 200
var height: int = 200
var steps: int = 1000
var warmup: int = 5
var rng_seed: int = 0xC5E305 # accepted for parity, the GPU rule is deterministic
var chunk: int = 0 # 0 = one submit for the whole batch; >0 = submit/sync every `chunk` steps
var fill: float = 0.0 #0 = blob scene; >0 = random Bernoulli fill at this density

func _initialize() -> void:
	if not parse_args(OS.get_cmdline_user_args()):
		quit(1)
		return

	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		printerr("Failed to create local RenderingDevice (no GPU/driver?).")
		quit(1)
		return

	var shader := compile_shader(rd)
	if not shader.is_valid():
		quit(1)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		printerr("Failed to create compute pipeline.")
		quit(1)
		return

	var grid_texture := create_texture(rd)
	var initial_sand := seed_scene(rd, grid_texture) # count seeded grains on the CPU side
	var uniform_set := create_uniform_set(rd, shader, grid_texture)

	var groups_x := (width / 2 + 15) / 16
	var groups_y := (height / 2 + 15) / 16

	var phase := 0 # continuous phase counter spanning warmup + timed region

	# Warmup (untimed): let the driver/GPU reach steady state.
	for i in range(warmup):
		record_step(rd, pipeline, uniform_set, phase, groups_x, groups_y)
		phase += 1
	rd.submit()
	rd.sync()

	# Timed region: single wall-clock span around N steps
	var t0 := Time.get_ticks_usec()
	var pending := 0
	for i in range(steps):
		record_step(rd, pipeline, uniform_set, phase, groups_x, groups_y)
		phase += 1
		pending += 1
		# Optional chunking guards against Windows TDR on very large batches.
		if chunk > 0 and pending >= chunk:
			rd.submit()
			rd.sync()
			pending = 0
	if pending > 0:
		rd.submit()
		rd.sync()
	var t1 := Time.get_ticks_usec()

	var elapsed_s := float(t1 - t0) / 1_000_000.0
	var cell_updates := float(width) * float(height) * float(steps)
	var cups := (cell_updates / elapsed_s) if elapsed_s > 0.0 else 0.0

	var final_sand := count_sand(rd, grid_texture)

	# Same one-line, key=value format the C++ benchmark prints so run_gpu.sh can parse it.
	print("BENCH width=%d height=%d steps=%d warmup=%d elapsed_s=%.6f cell_updates_per_s=%s sand_initial=%d sand_final=%d wood_initial=0 wood_final=0" % [
		width, height, steps, warmup, elapsed_s, String.num_scientific(cups), initial_sand, final_sand
	])
	rd.free_rid(uniform_set)
	rd.free_rid(grid_texture)
	rd.free_rid(pipeline)
	rd.free_rid(shader)

	var exit_code := 0
	if initial_sand != final_sand:
		printerr("CONSERVATION VIOLATION: sand %d -> %d" % [initial_sand, final_sand])
		exit_code = 2
	quit(exit_code)


# CLI parser, matches the flags the C++ benchmark understands so the
# two can be driven by near-identical sweep scripts.
func parse_args(args: PackedStringArray) -> bool:
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--width":
			width = _need_int(args, i)
		elif a == "--height":
			height = _need_int(args, i)
		elif a == "--steps":
			steps = _need_int(args, i)
		elif a == "--warmup":
			warmup = _need_int(args, i)
		elif a == "--seed":
			rng_seed = _need_int(args, i)
		elif a == "--chunk":
			chunk = _need_int(args, i)
		elif a == "--fill":
			fill = _need_float(args, i)
		else:
			printerr("unknown argument: ", a)
			return false
		i += 2 # skip the flag and its value
	if width <= 0 or height <= 0:
		printerr("--width and --height must be > 0")
		return false
	if steps < 0 or warmup < 0:
		printerr("--steps and --warmup must be >= 0")
		return false
	return true

func _need_int(args: PackedStringArray, i: int) -> int:
	if i + 1 >= args.size():
		printerr("missing value for ", args[i])
		return 0
	return args[i + 1].to_int()

func _need_float(args: PackedStringArray, i: int) -> float:
	if i + 1 >= args.size():
		printerr("missing value for ", args[i])
		return 0.0
	return args[i + 1].to_float()


func compile_shader(rd: RenderingDevice) -> RID:
	if not FileAccess.file_exists(SHADER_PATH):
		printerr("Shader not found: ", SHADER_PATH)
		return RID()
	var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
	var code := f.get_as_text()
	f.close()
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = code
	var spirv := rd.shader_compile_spirv_from_source(src)
	var err := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err != "":
		printerr("Shader compile error: ", err)
		return RID()
	return rd.shader_create_from_spirv(spirv)


func create_texture(rd: RenderingDevice) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = width
	fmt.height = height
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	# CAN_COPY_FROM lets us read the texture back for the conservation check.
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(fmt, RDTextureView.new())


# Seed the scene, return the number of grains seeded (the conservation baseline).
func seed_scene(rd: RenderingDevice, tex: RID) -> int:
	var data := PackedFloat32Array()
	data.resize(width * height * 4)
	if fill > 0.0:
		_seed_random_fill(data)
	else:
		var small_dim := mini(width, height)
		stamp_blob(data, height / 6, width / 2, small_dim / 16)
		stamp_blob(data, height / 4, width / 3, small_dim / 24)
		stamp_blob(data, height / 4, 2 * width / 3, small_dim / 24)
	rd.texture_update(tex, 0, data.to_byte_array())

	var sand := 0
	var n := width * height
	for p in range(n):
		if data[p * 4] > 0.5:
			sand += 1
	return sand

# Random Bernoulli fill at target density. Each cell is set to sand with
# probability `fill` independently. Uses Godot's RandomNumberGenerator (PCG32,
# period 2^64, high statistical quality), reproducible given the same seed.
func _seed_random_fill(data: PackedFloat32Array) -> void:
	var f: float = clamp(fill, 0.0, 1.0)
	if f <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	for r in range(height):
		for c in range(width):
			if rng.randf() < f:
				var idx := (r * width + c) * 4
				data[idx] = 1.0
				data[idx + 1] = 1.0
				data[idx + 2] = 1.0
				data[idx + 3] = 1.0

# Stamp a filled disk of sand

func stamp_blob(data: PackedFloat32Array, row: int, col: int, radius: int) -> void:
	var r2 := radius * radius
	for dr in range(-radius, radius + 1):
		for dc in range(-radius, radius + 1):
			if dr * dr + dc * dc <= r2:
				var x := col + dc
				var y := row + dr
				if x < 0 or x >= width or y < 0 or y >= height:
					continue
				var idx := (y * width + x) * 4
				data[idx] = 1.0
				data[idx + 1] = 1.0
				data[idx + 2] = 1.0
				data[idx + 3] = 1.0


func create_uniform_set(rd: RenderingDevice, shader: RID, tex: RID) -> RID:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(tex)
	return rd.uniform_set_create([u], shader, 0)


# Record one simulation step into the current command buffer. Each step is its
# own compute list so Godot inserts the image barrier that serializes it after
# the previous step (every step reads neighbour cells the last step wrote).
func record_step(rd: RenderingDevice, pipeline: RID, uniform_set: RID,
		phase: int, groups_x: int, groups_y: int) -> void:
	var off: Vector2i = PHASE_OFFSETS[phase % PHASE_OFFSETS.size()]
	var pc := PackedInt32Array([off.x, off.y, width, height]).to_byte_array()
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
	rd.compute_list_end()


# Read the grid back and count sand cells (r channel > 0.5) for the
# conservation check. Done once at the end, outside the timed region.
func count_sand(rd: RenderingDevice, tex: RID) -> int:
	var bytes := rd.texture_get_data(tex, 0)
	var floats := bytes.to_float32_array()
	var sand := 0
	var n := width * height
	for p in range(n):
		if floats[p * 4] > 0.5:
			sand += 1
	return sand




