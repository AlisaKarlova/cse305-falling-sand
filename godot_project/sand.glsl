#version 450
// Margolus neighborhood sand simulation.
// Each invocation processes one 2×2 block; gravity rules are encoded in LUT.
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Single read-write storage image
layout(set = 0, binding = 0, rgba32f) uniform image2D grid; // grid of ints


layout(push_constant, std430) uniform Params {
	int offset_x;
	int offset_y;
	int width;
	int height;
} params;

const int four_cell_conv[16] = int[16](0,1,2,3, 1,3,3,7, 2,3,3,11, 3,7,11,15);
const int two_cell_vert_conv[4] = int[4](0,1,1,3);
const int three_cell_BR_conv[8] = int[8](0,1,2,3, 1,5,3,7);
const int three_cell_BL_conv[8] = int[8](0,1,2,3, 2,3,6,7);
const int three_cell_TR_conv[8] = int[8](0,1,1,3, 4,5,5,7);
const int three_cell_TL_conv[8] = int[8](0,1,2,3, 1,5,3,7);

int read_cell(ivec2 c) {
	return int(imageLoad(grid, c).r);
}

void write_cell(ivec2 c, float v) {
	vec4 color;
	if (v > 1.5) {
		color = vec4(2.0, 0.1, 0.9, 1.0);
	} else if (v > 0.5) {
		color = vec4(1.0, 1.0, 1.0, 1.0);
	} else {
		color = vec4(0.0, 0.0, 0.0, 1.0);
	}
	imageStore(grid, c, color);
}

int moveable_cell(ivec2 c) {
	if ((c.x == -1) || (c.x == params.width  - 1)
	 || (c.y == -1) || (c.y == params.height - 1)
	 || (read_cell(c) == 3)) { // wood
		return 0;
	}

	return 1;
}

void one_cell(ivec2 c) {
	write_cell(c, read_cell(c));
	return;
}

void two_cell_diag_up(ivec2 cTR, ivec2 cBL) {
	one_cell(cTR);
	one_cell(cBL);
}

void two_cell_diag_dn(ivec2 cTL, ivec2 cBR) {
	one_cell(cTL);
	one_cell(cBR);
}

void two_cell_hor(ivec2 cL, ivec2 cR){
	int L = read_cell(cL);
	int R = read_cell(cR);
	if ((L == 2 && R == 0)||(L == 0 && R == 2)){
		bool coin_flip = ((cL.x * 3 + cL.y * 7 + params.offset_x * 11) % 2) == 0;
		if(coin_flip) {
			write_cell(cL, float(R));
			write_cell(cR, float(L));
		}else{
			write_cell(cL, float(L));
			write_cell(cR, float(R));
		}
	}
	else {
		write_cell(cL, float(L));
		write_cell(cR, float(R));
	}
}

void two_cell_vert(ivec2 cT, ivec2 cB) {
	int T = read_cell(cT);
	int B = read_cell(cB);
	if ((T == 1 || T == 2) && B == 0){
		write_cell(cT, 0.0);
		write_cell(cB, float(T));
	}
	else if (T == 1 && B == 2){
		write_cell(cT, 2.0);
		write_cell(cB, 1.0);
	}
	else {
		write_cell(cT, float(T));
		write_cell(cB, float(B));
	}
}


void three_cell_BR(ivec2 cTR, ivec2 cBL, ivec2 cBR) {
	int TR = read_cell(cTR);
	int BL = read_cell(cBL);
	int BR = read_cell(cBR);
	if (TR == 1) {
		if (BR == 0 || BR == 2) {
			int tmp = BR;
			BR = TR; 
			TR = tmp;
		}
	}
	if (TR == 1 && BR > 0 && BL == 0) {
		BL = TR; 
		TR = 0;
	} else if (TR == 1 && BR > 0 && BL == 2) {
		int tmp = BL; 
		BL = TR; 
		TR = tmp;
	}
	bool coin = ((cTR.x * 3 + cTR.y * 7 + params.offset_x * 11) % 2) == 0;
	if (BL == 2 && BR == 0) { 
		if (coin) { 
			BR = 2; 
			BL = 0;
		}
	}
	else if (BL == 0 && BR == 2) {
		if (coin) { 
			BL = 2; 
			BR = 0;
		}
	}
	write_cell(cTR, float(TR));
	write_cell(cBL, float(BL));
	write_cell(cBR, float(BR));
}
	
void three_cell_BL(ivec2 cTL, ivec2 cBL, ivec2 cBR) {
	int TL = read_cell(cTL);
	int BL = read_cell(cBL);
	int BR = read_cell(cBR);
	if (TL == 1){
		if (BL == 0 || BL == 2){
			int tmp = BL; 
			BL = TL; 
			TL = tmp;
		}
	}
	bool coin = ((cBL.x * 3 + cBL.y * 7 + params.offset_x * 11) % 2) == 0;
	if (BL == 2 && BR == 0) { 
		if (coin) { 
			BR = 2; 
			BL = 0; 
		}
	}
	else if (BL == 0 && BR == 2) { 
		if (coin) { 
			BL = 2;
			BR = 0;
		} 
	}
	write_cell(cTL, float(TL));
	write_cell(cBL, float(BL));
	write_cell(cBR, float(BR));
}
	
void three_cell_TR(ivec2 cTL, ivec2 cTR, ivec2 cBR){
	int TL = read_cell(cTL);
	int TR = read_cell(cTR);
	int BR = read_cell(cBR);
	if (TR == 1 || TR == 2) {
		if (BR == 0) {
			BR = TR;
			TR = 0; 
		}
		else if (TR == 1 && BR == 2) {
			BR = 1; 
			TR = 2; 
		}
	}
	if ((TL == 1 || TL == 2) && TR == 0 && BR == 0) {
		BR = TL;
		TL = 0;
	}
	bool coin = ((cTL.x * 3 + cTL.y * 7 + params.offset_x * 11) % 2) == 0;
	if (TL == 2 && TR == 0) {
		if (coin) {
			TR = 2;
			TL = 0;
		}
	}
	else if (TL == 0 && TR == 2) {
		if (coin) {
			TL = 2;
			TR = 0;
		}
	}
	write_cell(cTL, float(TL));
	write_cell(cTR, float(TR));
	write_cell(cBR, float(BR));
}
	
void three_cell_TL(ivec2 cTL, ivec2 cTR, ivec2 cBL){
	int TL = read_cell(cTL);
	int TR = read_cell(cTR);
	int BL = read_cell(cBL);
	if (TL == 1 || TL == 2) {
		if (BL == 0) {
			BL = TL;
			TL = 0;
		}
		else if (TL == 1 && BL == 2) {
			BL = 1;
			TL = 2;
		}
	}
	if ((TR == 1 || TR == 2) && TL == 0 && BL == 0) {
		BL = TR;
		TR = 0;
	}
	bool coin = ((cTL.x * 3 + cTL.y * 7 + params.offset_x * 11) % 2) == 0;
	if (TL == 2 && TR == 0){
		if (coin) {
			TR = 2;
			TL = 0;
		}
	}
	else if (TL == 0 && TR == 2) {
		if (coin) {
			TL = 2;
			TR = 0;
		}
	}
	write_cell(cTL, float(TL));
	write_cell(cTR, float(TR));
	write_cell(cBL, float(BL));
}

void four_cell(ivec2 cTL, ivec2 cTR, ivec2 cBL, ivec2 cBR) {
	int TL = read_cell(cTL);
	int TR = read_cell(cTR);
	int BL = read_cell(cBL);
	int BR = read_cell(cBR);
	if (TL == 1 || TL == 2) {
		if (BL == 0) {
			BL = TL;
			TL = 0;
		}
		else if (TL == 1 && BL == 2) { 
			BL = 1;
			TL = 2;
		}
	}
	if (TR == 1 || TR == 2) {
		if (BR == 0) {
			BR = TR;
			TR = 0;
		}
		else if (TR == 1 && BR == 2) {
			BR = 1;
			TR = 2;
			}
	}
	if (TL == 1 && BL > 0 && TR == 0 && BR == 0) {
		BR = 1; 
		TL = 0;
	} else if (TL == 1 && BL > 0 && TR == 0 && BR == 2) {
		BR = 1; 
		TL = 2;
	}
	if (TR == 1 && BR > 0 && TL == 0 && BL == 0) {
		BL = 1;
		TR = 0;
	} else if (TR == 1 && BR > 0 && TL == 0 && BL == 2) {
		BL = 1;
		TR = 2;
	}
	bool coin = ((cTL.x * 3 + cTL.y * 7 + params.offset_x * 11) % 2) == 0;
	if (TL == 2 && TR == 0 && BL != 0) {
		if (coin) {
			TR = 2;
			TL = 0;
		}
	}
	else if (TL == 0 && TR == 2 && BR != 0) {
		if (coin) {
			TL = 2;
			TR = 0;
		}
	}

	write_cell(cTL, float(TL));
	write_cell(cTR, float(TR));
	write_cell(cBL, float(BL));
	write_cell(cBR, float(BR));
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
		
		case 6:  two_cell_diag_up(cTR, cBL); return;
		case 9:  two_cell_diag_dn(cTL, cBR); return;

		case 5:  two_cell_vert(cTR, cBR); return;
		case 10: two_cell_vert(cTL, cBL); return;
		
		case 3:  two_cell_hor(cBL, cBR); return;
		case 12: two_cell_hor(cTL, cTR); return;

		case 1:  one_cell(cBR); return;
		case 2:  one_cell(cBL); return;
		case 4:  one_cell(cTR); return;
		case 8:  one_cell(cTL); return;
		
		case 0:  return;
		default: return;
	}
}
