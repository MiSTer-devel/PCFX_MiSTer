// Verilated -*- C++ -*-
// DESCRIPTION: main() calling loop, created with Verilator --main

#include "verilated.h"
#include "Vpcfx_render_tb.h"

//======================

int main(int argc, char** argv, char**) {
    // Setup context, defaults, and parse command line
    Verilated::debug(0);
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);

    // Construct the Verilated model, from Vrender.h generated from Verilating
    const std::unique_ptr<Vpcfx_render_tb> topp{new Vpcfx_render_tb{contextp.get(), ""}};

    // Simulate until $finish
    while (VL_LIKELY(!contextp->gotFinish())) {
        // Evaluate model
        topp->eval();
        // Advance time
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }

    if (VL_LIKELY(!contextp->gotFinish())) {
        VL_DEBUG_IF(VL_PRINTF("+ Exiting without $finish; no events left\n"););
    }

    // Execute 'final' processes
    topp->final();

    // Print statistical summary report
    contextp->statsPrintSummary();

    return 0;
}

// Local Variables:
// compile-command: "verilator --cc --exe pcfx_render_tb.cpp --build -j 0 --timing --assert -O3 --x-assign fast --x-initial fast --trace-fst --trace-threads 1 -Wno-TIMESCALEMOD --top-module pcfx_render_tb --relative-includes -DTB_VDC=1 -DTB_VPU=1 ../fifo/fifo1.v ../huc6272.sv ../huc6261.sv ../huc6270.sv ../huc6271.sv dpram.sv ../memif_sdram.sv ../sdram.sv sdram_xsds.sv as4c32m16sb.sv pcfx_render_tb.sv && obj_dir/Vpcfx_render_tb && python3 yuv_render2png.py pcfx_render.hex pcfx_render.png 360 242"
// End:
