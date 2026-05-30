#version 450
// Margolus neighborhood sand simulation.
// Each invocation processes one 2×2 block; gravity rules are encoded in LUT.
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Single read-write storage image (r channel: 1.0=sand, 0.0=empty)
layout(set = 0, binding = 0, rgba32f) uniform image2D grid; // TODO: change to integer image format


layout(push_constant, std430) uniform Params {
	int offset_x;
	int offset_y;
	int width;
	int height;
} params;

// Maps every 4-bit block pattern (TL=b3, TR=b2, BL=b1, BR=b0) to its next state.
// Particles fall down; a particle above an empty cell moves into it, spreading sideways if blocked.
const int LUT[16] = int[16](0,1,2,3, 1,3,3,7, 2,3,3,11, 3,7,11,15);

bool read_cell(ivec2 c) {
	if (c.x < 0 || c.x >= params.width || c.y < 0 || c.y >= params.height)
		return true;  // out-of-bounds treated as solid wall
	return imageLoad(grid, c).r > 0.5; // check == 1.0
}

void write_cell(ivec2 c, bool sand) {
	if (c.x < 0 || c.x >= params.width || c.y < 0 || c.y >= params.height)
		return;
	float v = sand ? 1.0 : 0.0;
	imageStore(grid, c, vec4(v, v, v, 1.0));
}

void main() {
	ivec2 block  = ivec2(gl_GlobalInvocationID.xy);
	ivec2 origin = block * 2 + ivec2(params.offset_x, params.offset_y);
	if (origin.x < 0 || origin.y < 0 ||
		origin.x + 1 >= params.width || origin.y + 1 >= params.height) {
		return;
	}

	ivec2 cTL = origin;
	ivec2 cTR = origin + ivec2(1, 0);
	ivec2 cBL = origin + ivec2(0, 1);
	ivec2 cBR = origin + ivec2(1, 1);

	int TL = read_cell(cTL) ? 1 : 0;
	int TR = read_cell(cTR) ? 1 : 0;
	int BL = read_cell(cBL) ? 1 : 0;
	int BR = read_cell(cBR) ? 1 : 0;
	
	// Encode 4-cell state as a 4-bit index and look up the resulting output state.
	int idx = TL*8 + TR*4 + BL*2 + BR;
	int out_code = LUT[idx];
	
	// Unpack the 4-bit output code: bit 3=TL, bit 2=TR, bit 1=BL, bit 0=BR.
	write_cell(cTL, ((out_code >> 3) & 1) == 1);
	write_cell(cTR, ((out_code >> 2) & 1) == 1);
	write_cell(cBL, ((out_code >> 1) & 1) == 1);
	write_cell(cBR, ((out_code     ) & 1) == 1);
}
