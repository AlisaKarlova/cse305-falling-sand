
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D input_grid;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D output_grid;

void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	
	// Count living neighbors
	int alive_neighbors = 0;
	
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) continue;
			
			ivec2 neighbor = coord + ivec2(x, y);
			
			// Only count if within bounds
			if (neighbor.x >= 0 && neighbor.x < 512 && 
				neighbor.y >= 0 && neighbor.y < 512) {
				
				vec4 cell = imageLoad(input_grid, neighbor);
				if (cell.r > 0.5) {
					alive_neighbors++;
				}
			}
		}
	}
	
	// Get current cell state
	vec4 current = imageLoad(input_grid, coord);
	bool is_alive = current.r > 0.5;
	
	// Apply Game of Life rules
	bool next_state = false;
	
	if (is_alive) {
		// Cell survives with 2 or 3 neighbors
		if (alive_neighbors == 2 || alive_neighbors == 3) {
			next_state = true;
		}
	} else {
		// Dead cell becomes alive with exactly 3 neighbors
		if (alive_neighbors == 3) {
			next_state = true;
		}
	}
	
	// Write output
	float val = next_state ? 1.0 : 0.0;
	imageStore(output_grid, coord, vec4(val, val, val, 1.0));
}
