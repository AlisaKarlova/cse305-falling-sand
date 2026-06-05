#pragma once
// CPU port of the Godot Margolus sand shader (godot_project/sand.glsl).
// Same algorithm as the GPU
#include <cstdint>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>

namespace sand {

class Grid;

class MargolusSimulation {
public:
    // seed is accepted for API parity with Simulation; the Margolus rule is
    // deterministic, so it is unused.
    explicit MargolusSimulation(std::uint64_t seed = 0xC5E305ULL, int threads = 1);
    ~MargolusSimulation();

    MargolusSimulation(const MargolusSimulation&)            = delete;
    MargolusSimulation& operator=(const MargolusSimulation&) = delete;

    void step(Grid& g);
    std::uint64_t step_count() const { return steps_; }

private:
    void run_band(int id); // process this worker's contiguous band of block-rows
    void worker_loop(int id); //helper-thread entry point

    int           threads_;
    std::uint64_t steps_ = 0;

    //worker pool
    std::vector<std::thread> workers_;
    std::mutex               m_;
    std::condition_variable  cv_start_;
    std::condition_variable  cv_done_;
    long long                generation_ = 0;
    int                      done_count_ = 0;
    bool                     stop_       = false;

    // Per-step task parameters
    Grid* g_  = nullptr;
    int   W_  = 0, H_  = 0;
    int   nbx_ = 0, nby_ = 0; // number of 2x2 blocks dispatched (matches GPU groups*16)
    int   ox_ = 0, oy_ = 0; // current Margolus phase offset
};

} // namespace sand