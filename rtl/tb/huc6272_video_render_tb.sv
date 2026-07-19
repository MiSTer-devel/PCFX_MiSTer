// KING video render testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module huc6272_video_render_tb;

initial begin
    $timeformat(-6, 0, " us", 1);

    $dumpfile("huc6272_video_render_tb.vcd");
    $dumpvars();
end

`include "mmc_kram_vce.svh"
`include "video_rtz0.svh"

//////////////////////////////////////////////////////////////////////

integer fpic;
logic   pice;

initial begin
    fpic = $fopen("huc6272_video_render.hex", "w");
    pice = 0;
end
always @(posedge clk) begin
    if (dck) begin
        if (mmc_vde) begin
            $fwrite(fpic, "%x", mmc_vd);
            pice = 1;
        end
        else if (pice) begin
            pice = 0;
            $fwrite(fpic, "\n");
        end
    end
end
final
    $fclose(fpic);

//////////////////////////////////////////////////////////////////////

initial #0 begin
    load_vmem();

    #10 @(posedge clk) reset <= 0;
    #2 @(posedge clk) ;

    load_kreg();

    #(15e3) $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s huc6272_video_render_tb -DHUC6272_DMC_ENABLE -o huc6272_video_render_tb.vvp ../huc6272.sv ../huc6261.sv dpram.sv pd424260.sv huc6272_video_render_tb.sv && ./huc6272_video_render_tb.vvp && python3 yuv_render2png.py huc6272_video_render.hex huc6272_video_render.png 256 242"
// End:
