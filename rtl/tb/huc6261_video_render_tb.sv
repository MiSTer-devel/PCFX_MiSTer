// NEW Iron Guanyin video render testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module huc6261_video_render_tb;

initial begin
    $timeformat(-6, 0, " us", 1);

    $dumpfile("huc6261_video_render_tb.vcd");
    $dumpvars();
end

`include "mmc_kram_vce.svh"
`include "video_rtz0.svh"

//////////////////////////////////////////////////////////////////////

integer fpic;
logic   pice;

initial begin
    fpic = $fopen("huc6261_video_render.hex", "w");
    pice = 0;
end
always @(posedge clk) begin
    if (dck70) begin
        if (vce_vde) begin
            $fwrite(fpic, "%x", vce_vd);
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

    load_vce_reg();
    load_vdc0_reg();
    load_vdc1_reg();
    load_kreg();
    load_rreg();

    // Advance a frame to trigger V-Blank actions like SATB copy.
    @(posedge vsync_negedge) ;
    repeat (2) @(posedge hsync_negedge) ;
    vdc0.DISP_CNT = 10'h014;
    vdc1.DISP_CNT = 10'h014;
    repeat (2) @(posedge hsync_negedge) ;
    vdc0.DISP_CNT = 10'h104;
    vdc1.DISP_CNT = 10'h104;
    vce.v_cnt = 9'h106;
    mmc.video.row = 10'h103;
    @(posedge hsync_negedge) ;

    #(15e3) $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s huc6261_video_render_tb -DHUC6272_DMC_ENABLE -DTB_VDC -DTB_VPU -o huc6261_video_render_tb.vvp ../huc6272.sv ../huc6261.sv ../huc6270.sv ../huc6271.sv dpram.sv pd424260.sv huc6261_video_render_tb.sv && ./huc6261_video_render_tb.vvp && python3 yuv_render2png.py huc6261_video_render.hex huc6261_video_render.png 360 242"
// End:
