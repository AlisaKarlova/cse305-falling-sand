#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Single read-write storage image
layout(set = 0, binding = 0, rgba32i) uniform image2D grid; # grid of ints


layout(push_constant, std430) uniform Params {
	int offset_x;
	int offset_y;
	int width;
	int height;
} params;

const int four_cell_conv[16] = int[16](0,1,2,3, 1,3,3,7, 2,3,3,11, 3,7,11,15);
const int two_cell_vert_conv[4] = int[4](0,1,1,3);
const int three_cell_BR_conv[8] = int[4](0,1,2,3, 1,5,3,7);
const int three_cell_BL_conv[8] = int[4](0,1,2,3, 2,3,6,7);
const int three_cell_TR_conv[8] = int[4](0,1,1,3, 4,5,5,7);
const int three_cell_TL_conv[8] = int[4](0,1,2,3, 1,5,3,7);

int moveable_cell(ivec2 c) {
    if  ((c.x == -1) | (c.x == width  - 1)
       | (c.y == -1) | (c.y == height - 1)) {
    // | (imageLoad(grid, c).r == 2)  // wood
        return 0;
    }

    return 1;
}

int read_cell(ivec2 c) {
	return imageLoad(grid, c).r;
}

void write_cell(ivec2 c, int v) {
	imageStore(grid_in, c, vec4(v, v, v, 1));
}

void two_cell_hor(ivec2 cL, ivec2 cR) {
    one_cell(cL);
    one_cell(cR);
    return;
}

void two_cell_vert(ivec2 cT, ivec2 cB) {
    int T = read_cell(cT);
    int B = read_cell(cB);

    int idx = T*2 + B;
    int out_code = two_cell_vert_conv[idx];

    write_cell(cT, ((out_code >> 1) & 1));
    write_cell(cB, ((out_code     ) & 1));
    return;
}

void one_cell(ivec2 c) {
    write_cell(c, read_cell(c));
    return;
}

void three_cell_BR(ivec2 cTR, ivec2 cBL, ivec2 cBR) {
    int TR = read_cell(cTR);
    int BL = read_cell(cBL);
    int BR = read_cell(cBR);

    int idx = TR*4 + BL*2 + BR;
    int out_code = three_cell_BR_conv[idx];

    write_cell(cTR, ((out_code >> 2) & 1));
    write_cell(cBL, ((out_code >> 1) & 1));
    write_cell(cBR, ((out_code     ) & 1));
    return;
}
    
void three_cell_BL(ivec2 cTL, ivec2 cBL, ivec2 cBR);
    int TL = read_cell(cTL);
    int BL = read_cell(cBL);
    int BR = read_cell(cBR);

    int idx = TL*4 + BL*2 + BR;
    int out_code = three_cell_BL_conv[idx];

    write_cell(cTL, ((out_code >> 2) & 1));
    write_cell(cBL, ((out_code >> 1) & 1));
    write_cell(cBR, ((out_code     ) & 1));
    return;
}
    
void three_cell_TR(ivec2 cTL, ivec2 cTR, ivec2 cBR);
    int TL = read_cell(cTL);
    int TR = read_cell(cTR);
    int BR = read_cell(cBR);

    int idx = TL*4 + TR*2 + BR;
    int out_code = three_cell_TR_conv[idx];

    write_cell(cTL, ((out_code >> 2) & 1));
    write_cell(cTR, ((out_code >> 1) & 1));
    write_cell(cBR, ((out_code     ) & 1));
    return;
}
    
void three_cell_TL(ivec2 cTL, ivec2 cTR, ivec2 cBL);
    int TL = read_cell(cTL);
    int TR = read_cell(cTR);
    int BL = read_cell(cBL);

    int idx = TL*4 + TR*2 + BL;
    int out_code = three_cell_TL_conv[idx];

    write_cell(cTL, ((out_code >> 2) & 1));
    write_cell(cTR, ((out_code >> 1) & 1));
    write_cell(cBL, ((out_code     ) & 1));
    return;
}

void four_cell(ivec2 cTL, ivec2 cTR, ivec2 cBL, ivec2 cBR) {
	int TL = read_cell(cTL);
	int TR = read_cell(cTR);
	int BL = read_cell(cBL);
	int BR = read_cell(cBR);

	int idx = TL*8 + TR*4 + BL*2 + BR;
	int out_code = four_cell_conv[idx];

	write_cell(cTL, ((out_code >> 3) & 1));
	write_cell(cTR, ((out_code >> 2) & 1));
	write_cell(cBL, ((out_code >> 1) & 1));
	write_cell(cBR, ((out_code     ) & 1));
}

void main() {
	ivec2 block  = ivec2(gl_GlobalInvocationID.xy);
	ivec2 origin = block * 2 + ivec2(params.offset_x, params.offset_y);

	ivec2 cTL = origin;
	ivec2 cTR = origin + ivec2(1, 0);
	ivec2 cBL = origin + ivec2(0, 1);
	ivec2 cBR = origin + ivec2(1, 1);

	int TL = moveable_cell(cTL);
	int TR = moveable_cell(cTR);
	int BL = moveable_cell(cBL);
	int BR = moveable_cell(cBR);

	int idx = TL*8 + TR*4 + BL*2 + BR;


    switch(idx) {
        case 15: four_cell(cTL, cTR, cBL, cBR); return;

        case 7:  three_cell_BR(cTR, cBL, cBR); return;
        case 11: three_cell_BL(cTL, cBL, cBR); return;
        case 13: three_cell_TR(cTL, cTR, cBR); return;
        case 14: three_cell_TL(cTL, cTR, cBL); return;

        case 5:  two_cell_vert(cTR, cBR); return;
        case 10: two_cell_vert(cTL, cBL); return;

        case 3:  two_cell_hor(cBL, cBR); return;
        case 12; two_cell_hor(cTL, cTR); return;

        case 1:  one_cell(cBR); return;
        case 2:  one_cell(cBL); return;
        case 4:  one_cell(cTR); return;
        case 8:  one_cell(cTL); return;
        
        case default; return;
        case 0:  return;
    }
}
