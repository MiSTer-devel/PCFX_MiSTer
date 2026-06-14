// RAINBOW render testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module huc6271_render_tb;

initial begin
    $timeformat(-6, 0, " us", 1);

    $dumpfile("huc6271_render_tb.vcd");
    $dumpvars();
end

`include "mmc_kram_vce.svh"
`include "video_bootvid2.svh"

assign vdc0_vd = '0;
assign vdc1_vd = '0;
assign mmc_vd = '0;

//////////////////////////////////////////////////////////////////////

integer fpic;
logic   pice;

initial begin
    fpic = $fopen("huc6271_render.hex", "w");
    pice = 0;
end
always @(posedge clk) begin
    if (dck) begin
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

integer fdat;
logic vpu_kbus_en = '0;

localparam [8:0] vpu_tsr = 9'd6;
localparam [4:0] vpu_tbc = 5'd15;

always @(posedge clk) begin
    if (dck) begin
        if (hsync_negedge && vce.v_cnt == 9'(vpu_tsr))
            vpu_kbus_en <= '1;
        if (hsync_negedge && vce.v_cnt == 9'(vpu_tsr + 16 * vpu_tbc))
            vpu_kbus_en <= '0;
    end
end

initial begin
    fdat = $fopen("bootvid/blk000.bin", "r");
    kbus_di = '0;
    kbus_ack_vpu = '0;
end
always @(posedge clk) if (ce) begin
integer code;
    if (kbus_ack_vpu)
        kbus_ack_vpu <= '0;
    else if (kbus_req_vpu & vpu_kbus_en) begin
        code = $fread(kbus_di, fdat, 0, 1);
        kbus_ack_vpu <= '1;
    end
end
final
    $fclose(fdat);

//////////////////////////////////////////////////////////////////////

initial #0 begin
    load_vmem();

    #10 @(posedge clk) reset <= 0;
    #2 @(posedge clk) ;

    load_vce_reg();
    load_rreg();

    #(16e3) $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s huc6271_render_tb -DTB_VPU -DTB_NO_MMC -o huc6271_render_tb.vvp ../huc6271.sv ../huc6261.sv dpram.sv huc6271_render_tb.sv && ./huc6271_render_tb.vvp && python3 yuv_render2png.py huc6271_render.hex huc6271_render.png 256 242"
// End:
