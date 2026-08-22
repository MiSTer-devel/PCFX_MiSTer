// Verilated -*- C++ -*-
// DESCRIPTION: main() calling loop, created with Verilator --main

#include "verilated.h"
#include "Vpcfx_top_tb.h"

#ifdef PCFX_TOP_TB_CD
#include "svdpi.h"
#include "Vpcfx_top_tb__Dpi.h"
#include "mister_main/support/pcfx/pcfx.h"
#include "libchdr/chd.h"
#endif

//======================

int main(int argc, char** argv, char**) {
    // Setup context, defaults, and parse command line
    Verilated::debug(0);
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);

    // Construct the Verilated model, from Vtop.h generated from Verilating
    const std::unique_ptr<Vpcfx_top_tb> topp{new Vpcfx_top_tb{contextp.get(), ""}};

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

#ifdef PCFX_TOP_TB_CD
extern "C" {
svBit pcfx_mount_cd()
{
    pcfx_mount_cd(3, "cd.chd");
    return (pcfx_get_img_size() == 0) ? sv_0 : sv_1;
}

int pcfx_read_cd(const svOpenArrayHandle buffer, int lba, int cnt)
{
    VL_PRINTF("pcfx_read_cd(lba=%d, cnt=%d)\n", lba, cnt);
    void *aptr = svGetArrayPtr(buffer);
    pcfx_read_cd(reinterpret_cast<uint8_t*>(aptr), lba, cnt);
    return 1;
}

} // extern "C"
#endif

// Local Variables:
// compile-command: "make -C mister_main DEBUG=1 bin/MiSTer.a && verilator --cc --exe pcfx_top_tb.cpp --make gmake --timing --assert -O3 --x-assign fast --x-initial fast --trace-fst --trace-threads 1 -Wno-TIMESCALEMOD --top-module pcfx_top_tb --relative-includes -DPCFX_TOP_TB_CD -CFLAGS '-g -DPCFX_TOP_TB_CD -I../mister_main/lib/libchdr/include' -F pcfx_top.files pcfx_top_tb.sv && make -C obj_dir -j -f ../Vpcfx_top_tb_wrap.mk default"
// End:
