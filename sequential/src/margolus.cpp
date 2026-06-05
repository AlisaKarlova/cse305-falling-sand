#include "margolus.h"
#include "grid.h"

namespace sand {

namespace {
inline int  rd(const Grid& g, int x, int y) { return static_cast<int>(g.cell(y, x)); }
inline void wr(Grid& g, int x, int y, int v) { g.cell(y, x) = static_cast<CellType>(v); }

inline int moveable(int x, int y, int W, int H) {
    if (x == -1 || x == W - 1 || y == -1 || y == H - 1) return 0;
    return 1;
}

void two_cell_hor(Grid& g, int Lx, int Ly, int Rx, int Ry, int ox) {
    int L = rd(g, Lx, Ly), R = rd(g, Rx, Ry);
    if ((L == 2 && R == 0) || (L == 0 && R == 2)) {
        bool coin = ((Lx * 3 + Ly * 7 + ox * 11) % 2) == 0;
        if (coin) { wr(g, Lx, Ly, R); wr(g, Rx, Ry, L); }
        else      { wr(g, Lx, Ly, L); wr(g, Rx, Ry, R); }
    } else        { wr(g, Lx, Ly, L); wr(g, Rx, Ry, R); }
}

void two_cell_vert(Grid& g, int Tx, int Ty, int Bx, int By) {
    int T = rd(g, Tx, Ty), B = rd(g, Bx, By);
    if ((T == 1 || T == 2) && B == 0) { wr(g, Tx, Ty, 0); wr(g, Bx, By, T); }
    else if (T == 1 && B == 2)        { wr(g, Tx, Ty, 2); wr(g, Bx, By, 1); }
    else                              { wr(g, Tx, Ty, T); wr(g, Bx, By, B); }
}

void three_cell_BR(Grid& g, int TRx, int TRy, int BLx, int BLy, int BRx, int BRy, int ox) {
    int TR = rd(g, TRx, TRy), BL = rd(g, BLx, BLy), BR = rd(g, BRx, BRy);
    if (TR == 1) { if (BR == 0 || BR == 2) { int t = BR; BR = TR; TR = t; } }
    if      (TR == 1 && BR > 0 && BL == 0) { BL = TR; TR = 0; }
    else if (TR == 1 && BR > 0 && BL == 2) { int t = BL; BL = TR; TR = t; }
    bool coin = ((TRx * 3 + TRy * 7 + ox * 11) % 2) == 0;
    if      (BL == 2 && BR == 0) { if (coin) { BR = 2; BL = 0; } }
    else if (BL == 0 && BR == 2) { if (coin) { BL = 2; BR = 0; } }
    wr(g, TRx, TRy, TR); wr(g, BLx, BLy, BL); wr(g, BRx, BRy, BR);
}

void three_cell_BL(Grid& g, int TLx, int TLy, int BLx, int BLy, int BRx, int BRy, int ox) {
    int TL = rd(g, TLx, TLy), BL = rd(g, BLx, BLy), BR = rd(g, BRx, BRy);
    if (TL == 1) { if (BL == 0 || BL == 2) { int t = BL; BL = TL; TL = t; } }
    bool coin = ((BLx * 3 + BLy * 7 + ox * 11) % 2) == 0;
    if      (BL == 2 && BR == 0) { if (coin) { BR = 2; BL = 0; } }
    else if (BL == 0 && BR == 2) { if (coin) { BL = 2; BR = 0; } }
    wr(g, TLx, TLy, TL); wr(g, BLx, BLy, BL); wr(g, BRx, BRy, BR);
}

void three_cell_TR(Grid& g, int TLx, int TLy, int TRx, int TRy, int BRx, int BRy, int ox) {
    int TL = rd(g, TLx, TLy), TR = rd(g, TRx, TRy), BR = rd(g, BRx, BRy);
    if (TR == 1 || TR == 2) {
        if (BR == 0)                  { BR = TR; TR = 0; }
        else if (TR == 1 && BR == 2)  { BR = 1;  TR = 2; }
    }
    if ((TL == 1 || TL == 2) && TR == 0 && BR == 0) { BR = TL; TL = 0; }
    bool coin = ((TLx * 3 + TLy * 7 + ox * 11) % 2) == 0;
    if      (TL == 2 && TR == 0) { if (coin) { TR = 2; TL = 0; } }
    else if (TL == 0 && TR == 2) { if (coin) { TL = 2; TR = 0; } }
    wr(g, TLx, TLy, TL); wr(g, TRx, TRy, TR); wr(g, BRx, BRy, BR);
}

void three_cell_TL(Grid& g, int TLx, int TLy, int TRx, int TRy, int BLx, int BLy, int ox) {
    int TL = rd(g, TLx, TLy), TR = rd(g, TRx, TRy), BL = rd(g, BLx, BLy);
    if (TL == 1 || TL == 2) {
        if (BL == 0)                  { BL = TL; TL = 0; }
        else if (TL == 1 && BL == 2)  { BL = 1;  TL = 2; }
    }
    if ((TR == 1 || TR == 2) && TL == 0 && BL == 0) { BL = TR; TR = 0; }
    bool coin = ((TLx * 3 + TLy * 7 + ox * 11) % 2) == 0;
    if      (TL == 2 && TR == 0) { if (coin) { TR = 2; TL = 0; } }
    else if (TL == 0 && TR == 2) { if (coin) { TL = 2; TR = 0; } }
    wr(g, TLx, TLy, TL); wr(g, TRx, TRy, TR); wr(g, BLx, BLy, BL);
}

void four_cell(Grid& g, int TLx, int TLy, int TRx, int TRy,
               int BLx, int BLy, int BRx, int BRy, int ox) {
    int TL = rd(g, TLx, TLy), TR = rd(g, TRx, TRy);
    int BL = rd(g, BLx, BLy), BR = rd(g, BRx, BRy);
    if (TL == 1 || TL == 2) {
        if (BL == 0)                  { BL = TL; TL = 0; }
        else if (TL == 1 && BL == 2)  { BL = 1;  TL = 2; }
    }
    if (TR == 1 || TR == 2) {
        if (BR == 0)                  { BR = TR; TR = 0; }
        else if (TR == 1 && BR == 2)  { BR = 1;  TR = 2; }
    }
    if      (TL == 1 && BL > 0 && TR == 0 && BR == 0) { BR = 1; TL = 0; }
    else if (TL == 1 && BL > 0 && TR == 0 && BR == 2) { BR = 1; TL = 2; }
    if      (TR == 1 && BR > 0 && TL == 0 && BL == 0) { BL = 1; TR = 0; }
    else if (TR == 1 && BR > 0 && TL == 0 && BL == 2) { BL = 1; TR = 2; }
    bool coin = ((TLx * 3 + TLy * 7 + ox * 11) % 2) == 0;
    if      (BL == 2 && BR == 0) { if (coin) { BR = 2; BL = 0; } }
    else if (BL == 0 && BR == 2) { if (coin) { BL = 2; BR = 0; } }
    if      (TL == 2 && TR == 0) { if (coin) { TR = 2; TL = 0; } }
    else if (TL == 0 && TR == 2) { if (coin) { TL = 2; TR = 0; } }
    wr(g, TLx, TLy, TL); wr(g, TRx, TRy, TR);
    wr(g, BLx, BLy, BL); wr(g, BRx, BRy, BR);
}

// Dispatch one 2x2 block
void process_block(Grid& g, int W, int H, int bx, int by, int ox, int oy) {
    const int orgx = bx * 2 + ox;
    const int orgy = by * 2 + oy;
    const int TLx = orgx,     TLy = orgy;
    const int TRx = orgx + 1, TRy = orgy;
    const int BLx = orgx,     BLy = orgy + 1;
    const int BRx = orgx + 1, BRy = orgy + 1;

    const int idx = moveable(TLx, TLy, W, H) * 8
                  + moveable(TRx, TRy, W, H) * 4
                  + moveable(BLx, BLy, W, H) * 2
                  + moveable(BRx, BRy, W, H);

    switch (idx) {
        case 15: four_cell(g, TLx,TLy, TRx,TRy, BLx,BLy, BRx,BRy, ox); break;
        case 7:  three_cell_BR(g, TRx,TRy, BLx,BLy, BRx,BRy, ox);      break;
        case 11: three_cell_BL(g, TLx,TLy, BLx,BLy, BRx,BRy, ox);      break;
        case 13: three_cell_TR(g, TLx,TLy, TRx,TRy, BRx,BRy, ox);      break;
        case 14: three_cell_TL(g, TLx,TLy, TRx,TRy, BLx,BLy, ox);      break;
        case 5:  two_cell_vert(g, TRx,TRy, BRx,BRy);                   break;
        case 10: two_cell_vert(g, TLx,TLy, BLx,BLy);                   break;
        case 3:  two_cell_hor(g, BLx,BLy, BRx,BRy, ox);                break;
        case 12: two_cell_hor(g, TLx,TLy, TRx,TRy, ox);                break;
        default: break; // 0,1,2,4,8 -> single/no moveable cell -> no movement
    }
}

} // anonymous namespace

MargolusSimulation::MargolusSimulation(std::uint64_t /*seed*/, int threads)
    : threads_(threads < 1 ? 1 : threads)
{
    const int nhelpers = threads_ - 1;
    workers_.reserve(static_cast<std::size_t>(nhelpers));
    for (int id = 1; id <= nhelpers; ++id)
        workers_.emplace_back([this, id] { worker_loop(id); });
}

MargolusSimulation::~MargolusSimulation() {
    {
        std::lock_guard<std::mutex> lk(m_);
        stop_ = true;
    }
    cv_start_.notify_all();
    for (auto& t : workers_)
        if (t.joinable()) t.join();
}

void MargolusSimulation::run_band(int id) {
    Grid& g = *g_;
    const int base  = nby_ / threads_;
    const int rem   = nby_ % threads_;
    const int begin = id * base + (id < rem ? id : rem);
    const int end   = begin + base + (id < rem ? 1 : 0);

    for (int by = begin; by < end; ++by)
        for (int bx = 0; bx < nbx_; ++bx)
            process_block(g, W_, H_, bx, by, ox_, oy_);
}

void MargolusSimulation::worker_loop(int id) {
    long long mygen = 0;
    for (;;) {
        {
            std::unique_lock<std::mutex> lk(m_);
            cv_start_.wait(lk, [&] { return stop_ || generation_ != mygen; });
            if (stop_) return;
            mygen = generation_;
        }
        run_band(id);
        {
            std::lock_guard<std::mutex> lk(m_);
            if (++done_count_ == threads_ - 1)
                cv_done_.notify_one();
        }
    }
}

void MargolusSimulation::step(Grid& g) {
    // One phase offset per step, same order as the Godot drivers.
    static const int PH[4][2] = { {0,0}, {-1,-1}, {0,-1}, {-1,0} };
    const int ox = PH[steps_ % 4][0];
    const int oy = PH[steps_ % 4][1];

    const int W = g.width(), H = g.height();
    const int groups_x = (W / 2 + 15) / 16; // matches benchmark.gd dispatch
    const int groups_y = (H / 2 + 15) / 16;

    g_ = &g; W_ = W; H_ = H;
    nbx_ = groups_x * 16;
    nby_ = groups_y * 16;
    ox_ = ox; oy_ = oy;

    const int nhelpers = threads_ - 1;
    if (nhelpers <= 0) {
        run_band(0); // serial baseline: one code path
    } else {
        {
            std::lock_guard<std::mutex> lk(m_);
            done_count_ = 0;
            ++generation_;
        }
        cv_start_.notify_all();
        run_band(0); // main thread is worker 0
        std::unique_lock<std::mutex> lk(m_);
        cv_done_.wait(lk, [&] { return done_count_ == nhelpers; });
    }

    ++steps_;
}

} // namespace sand