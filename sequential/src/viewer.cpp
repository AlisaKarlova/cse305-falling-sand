// SDL2-based interactive viewer for the sequential sand simulation.
//
// Controls:
//   LMB held : paint current material at the cursor
//   S / W : select Sand / Wood as the brush material
//   Mouse wheel : change brush radius (1..50)
//   Space : pause / unpause the simulation
//   R : clear the grid
//   Esc : quit
//
// The grid is rendered into a single SDL streaming texture sized W x H
// and then SDL_RenderCopy'd into the window (the renderer handles the
// scale). A separate Uint32 pixel buffer mirrors Grid::data() and is
// repainted from scratch each frame -- at the grid sizes we run this
// is cheap and keeps the code branch-free.

#include "viewer.h"
#include "grid.h"
#include "simulation.h"

#include <SDL.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace sand {

namespace {

// Flat per-material colours. No HSV interpolation -- with three cell
// types it would just be visual noise.
constexpr std::uint8_t kEmptyRGB[3] = {  24,  22,  18 };
constexpr std::uint8_t kSandRGB[3]  = { 224, 188, 120 };
constexpr std::uint8_t kWoodRGB[3]  = { 110,  70,  40 };

void paint_pixels(std::uint32_t* pixels, const Grid& g,
                  const SDL_PixelFormat* fmt) {
    const auto& data = g.data();
    const std::size_t n = data.size();
    const std::uint32_t empty =
        SDL_MapRGBA(fmt, kEmptyRGB[0], kEmptyRGB[1], kEmptyRGB[2], 255);
    const std::uint32_t sand  =
        SDL_MapRGBA(fmt, kSandRGB[0],  kSandRGB[1],  kSandRGB[2],  255);
    const std::uint32_t wood  =
        SDL_MapRGBA(fmt, kWoodRGB[0],  kWoodRGB[1],  kWoodRGB[2],  255);
    for (std::size_t i = 0; i < n; ++i) {
        switch (data[i]) {
            case CellType::Empty: pixels[i] = empty; break;
            case CellType::Sand:  pixels[i] = sand;  break;
            case CellType::Wood:  pixels[i] = wood;  break;
        }
    }
}

// Stamp disks at every interpolated point between two grid coords, so
// fast cursor motion paints a continuous stroke instead of a dotted
// trail. Simpler than the reference's Bresenham-with-tangent-offset and
// visually equivalent for an opaque brush.
void stamp_line(Grid& g, int r0, int c0, int r1, int c1,
                int radius, CellType t) {
    const int dr = r1 - r0;
    const int dc = c1 - c0;
    const int steps = std::max(std::abs(dr), std::abs(dc));
    if (steps == 0) {
        g.seed_blob(r0, c0, radius, t);
        return;
    }
    for (int i = 0; i <= steps; ++i) {
        const int r = r0 + dr * i / steps;
        const int c = c0 + dc * i / steps;
        g.seed_blob(r, c, radius, t);
    }
}

// Midpoint-circle outline. Drawn in window coordinates on top of the
// blitted grid texture so the user sees the brush footprint.
void draw_circle_outline(SDL_Renderer* ren, int cx, int cy, int radius) {
    if (radius <= 0) return;
    int x = radius;
    int y = 0;
    int err = 1 - x;
    while (x >= y) {
        SDL_RenderDrawPoint(ren, cx + x, cy + y);
        SDL_RenderDrawPoint(ren, cx + y, cy + x);
        SDL_RenderDrawPoint(ren, cx - y, cy + x);
        SDL_RenderDrawPoint(ren, cx - x, cy + y);
        SDL_RenderDrawPoint(ren, cx - x, cy - y);
        SDL_RenderDrawPoint(ren, cx - y, cy - x);
        SDL_RenderDrawPoint(ren, cx + y, cy - x);
        SDL_RenderDrawPoint(ren, cx + x, cy - y);
        ++y;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            --x;
            err += 2 * (y - x) + 1;
        }
    }
}

} // namespace

int run_viewer(const ViewerArgs& a) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    // Pick an integer scale so cells stay crisp. Target ~800 px window.
    const int max_dim = std::max(a.width, a.height);
    const int scale   = std::max(1, std::min(8, 800 / std::max(max_dim, 1)));
    const int win_w   = a.width  * scale;
    const int win_h   = a.height * scale;

    // Nearest-neighbour scaling so the cells stay sharp pixels.
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");

    SDL_Window* win = SDL_CreateWindow(
        "Falling Sand -- sequential",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        win_w, win_h, SDL_WINDOW_SHOWN);
    if (!win) {
        std::fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* ren = SDL_CreateRenderer(
        win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) {
        std::fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }

    const Uint32 pixel_format = SDL_PIXELFORMAT_RGBA8888;
    SDL_PixelFormat* fmt = SDL_AllocFormat(pixel_format);

    SDL_Texture* tex = SDL_CreateTexture(
        ren, pixel_format, SDL_TEXTUREACCESS_STREAMING,
        a.width, a.height);
    if (!tex) {
        std::fprintf(stderr, "SDL_CreateTexture failed: %s\n", SDL_GetError());
        SDL_FreeFormat(fmt);
        SDL_DestroyRenderer(ren);
        SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }

    Grid g(a.width, a.height);
    Simulation sim(a.seed);

    std::vector<std::uint32_t> pixels(
        static_cast<std::size_t>(a.width) * static_cast<std::size_t>(a.height));

    bool     paused    = false;
    bool     quit      = false;
    bool     lmb_held  = false;
    int      brush_rad = std::max(2, std::min(a.width, a.height) / 32);
    CellType brush_mat = CellType::Sand;

    int last_gr = -1, last_gc = -1;
    int mouse_x = 0,  mouse_y = 0;

    while (!quit) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
            case SDL_QUIT:
                quit = true;
                break;
            case SDL_KEYDOWN:
                switch (e.key.keysym.sym) {
                case SDLK_ESCAPE: quit = true; break;
                case SDLK_SPACE:  paused = !paused; break;
                case SDLK_r:      g.clear(); last_gr = last_gc = -1; break;
                case SDLK_s:      brush_mat = CellType::Sand; break;
                case SDLK_w:      brush_mat = CellType::Wood; break;
                }
                break;
            case SDL_MOUSEMOTION:
                mouse_x = e.motion.x;
                mouse_y = e.motion.y;
                break;
            case SDL_MOUSEBUTTONDOWN:
                if (e.button.button == SDL_BUTTON_LEFT) {
                    lmb_held = true;
                    last_gr = last_gc = -1;
                    mouse_x = e.button.x;
                    mouse_y = e.button.y;
                }
                break;
            case SDL_MOUSEBUTTONUP:
                if (e.button.button == SDL_BUTTON_LEFT) {
                    lmb_held = false;
                    last_gr = last_gc = -1;
                }
                break;
            case SDL_MOUSEWHEEL:
                brush_rad = std::clamp(brush_rad + e.wheel.y, 1, 50);
                break;
            }
        }

        // Map window coords to grid coords and apply the brush.
        const int gc = std::clamp(mouse_x * a.width  / std::max(win_w, 1),
                                  0, a.width  - 1);
        const int gr = std::clamp(mouse_y * a.height / std::max(win_h, 1),
                                  0, a.height - 1);
        if (lmb_held) {
            if (last_gr < 0) {
                g.seed_blob(gr, gc, brush_rad, brush_mat);
            } else {
                stamp_line(g, last_gr, last_gc, gr, gc, brush_rad, brush_mat);
            }
            last_gr = gr;
            last_gc = gc;
        }

        if (!paused) sim.step(g);

        paint_pixels(pixels.data(), g, fmt);
        SDL_UpdateTexture(tex, nullptr, pixels.data(),
                          a.width * static_cast<int>(sizeof(std::uint32_t)));

        SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
        SDL_RenderClear(ren);
        SDL_RenderCopy(ren, tex, nullptr, nullptr);

        // Brush footprint in window coordinates.
        SDL_SetRenderDrawColor(ren, 255, 255, 255, 255);
        draw_circle_outline(ren, mouse_x, mouse_y, brush_rad * scale);

        SDL_RenderPresent(ren);
    }

    SDL_DestroyTexture(tex);
    SDL_FreeFormat(fmt);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}

} // namespace sand