// Core testbench
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

//`define USE_IOCTL_FOR_LOAD 1
`define SAVE_FRAMES 1

import core_pkg::hmi_t;

module pcfx_top_tb;

logic		reset;
logic       clk_sys, clk_ram;

initial begin
    $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
    $dumpfile("pcfx_top_tb.vcd");
    $dumpvars();
`else
    $dumpfile("pcfx_top_tb.verilator.fst");
    #(3500e3) $dumpvars();
`endif
end

/////////////////////////   MEMORY   /////////////////////////

wire        SDRAM_CLK;
wire        SDRAM_CKE;
wire [12:0] SDRAM_A;
wire [1:0]  SDRAM_BA;
wire [15:0] SDRAM_DQ;
wire        SDRAM_DQML;
wire        SDRAM_DQMH;
wire        SDRAM_nCS;
wire        SDRAM_nCAS;
wire        SDRAM_nRAS;
wire        SDRAM_nWE;

sdram_xsds sdrb (.*);

//////////////////////////////////////////////////////////////////////

reg         ioctl_download = 0;
reg [7:0]   ioctl_index;
reg         ioctl_wr;
reg [24:0]  ioctl_addr;
reg [15:0]  ioctl_dout;
wire        ioctl_wait;

hmi_t       hmi;

wire        pce;
wire        hbl, vbl;
wire        vs;
wire [7:0]  r, g, b;

pcfx_top pcfx_top
(
	.clk_sys(clk_sys),
    .clk_ram(clk_ram),
	.reset(reset),
    .pll_locked('1),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

    .HMI(hmi),

    .SDRAM_CLK(SDRAM_CLK),
    .SDRAM_CKE(SDRAM_CKE),
    .SDRAM_A(SDRAM_A),
    .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQ(SDRAM_DQ),
    .SDRAM_DQML(SDRAM_DQML),
    .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS),
    .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nRAS(SDRAM_nRAS),
    .SDRAM_nWE(SDRAM_nWE),

	.ce_pix(pce),

	.HBlank(hbl),
	.HSync(),
	.VBlank(vbl),
	.VSync(vs),

	.R(r),
	.G(g),
	.B(b)
);

initial begin
    reset = 1;
    clk_sys = 1;
    clk_ram = 1;

    hmi = '0;
end

initial forever begin :clkgen_sys
    #0.01 clk_sys = ~clk_sys; // 50 MHz
end

initial forever begin :clkgen_ram
    #0.005 clk_ram = ~clk_ram; // 100 MHz
end

//////////////////////////////////////////////////////////////////////

string fn_rombios = "rombios.bin";
bit    swap_rombios = 1;

`ifdef USE_IOCTL_FOR_LOAD

bit         ioctl_active = 0;
bit         ioctl_swap;
integer     ioctl_fin;
bit         ioctl_wrote = 0;

always @(posedge clk_sys) if (ioctl_active) begin
integer code;
logic [15:0] data;
    if (~ioctl_download) begin
        ioctl_download <= '1;
        ioctl_addr <= 0;
    end
    else if (ioctl_wr) begin
        ioctl_wr <= '0;
        ioctl_wrote <= '1;
    end
    else if (ioctl_wrote) begin
        if (~ioctl_wait) begin
            ioctl_addr <= ioctl_addr + 25'd2;
            ioctl_wrote <= 0;
        end
    end
    else begin
        code = $fread(data, ioctl_fin, 0, 2);
        if (!$feof(ioctl_fin)) begin
            if (ioctl_swap)
                data = {data[7:0], data[15:8]};
            ioctl_dout <= data;
            ioctl_wr <= '1;
        end
        else begin
            ioctl_active <= 0;
            ioctl_download <= 0;
            ioctl_addr <= 'X;
            ioctl_dout <= 'X;
            ioctl_wr <= 0;
        end
    end
end

task ioctl_go(input string fn, bit swap_endian);
    ioctl_fin = $fopen(fn, "r");
    assert(ioctl_fin != 0) else $finish;
    ioctl_active = '1;
    ioctl_swap = swap_endian;
    while (ioctl_active)
        @(posedge clk_sys) ;
    $fclose(ioctl_fin);
endtask

task load_rombios;
    ioctl_index = {2'd0, 6'd0};
    ioctl_go(fn_rombios, swap_rombios);
endtask

`else // ifndef USE_IOCTL_FOR_LOAD

task load_file(input [24:0] base, input string fn, bit swap_endian);
integer	fin;
integer code;
logic [15:0] data;
logic [24:0] addr;
    begin
        fin = $fopen(fn, "r");
        assert(fin != 0) else $finish;
        addr = base;
        while (!$feof(fin)) begin :load_loop
            code = $fread(data, fin, 0, 2);
            if (!$feof(fin)) begin
                if (swap_endian)
                    data = {data[7:0], data[15:8]};
                sdrb.u1a.write(pcfx_top.sdram.addr_to_bank(addr),
                               pcfx_top.sdram.addr_to_row(addr),
                               pcfx_top.sdram.addr_to_col(addr),
                               data);
                addr += 2;
            end
        end
        $fclose(fin);
    end
endtask

task load_rombios;
    load_file(pcfx_top.memif_sdram.ROM_BASE_A, fn_rombios, swap_rombios);
endtask

`endif

//////////////////////////////////////////////////////////////////////

`ifdef SAVE_FRAMES

integer frame = 0;
integer fpic;
logic   pice;
string  fname;

initial fpic = -1;
always @(negedge vs) begin
  if (fpic != -1) begin
    $fclose(fpic);
    fpic = -1;
`ifdef VERILATOR
    $system({"python3 render2png.py ", fname, {".hex "}, fname, ".png; rm ", fname, ".hex"});
`endif
  end
  $display("%t: Frame %03d  A=%x", $time, frame, pcfx_top.mach.cpu_a);
  $sformat(fname, "frames/render-%03d", frame);
  pice = 0;
  if (frame >= 237) begin
    fpic = $fopen({fname, ".hex"}, "w");
  end
  frame = frame + 1;
end
final
  $fclose(fpic);

wire de = ~(hbl | vbl);

always @(posedge clk_sys) begin
  if (fpic != -1 && pce) begin
    if (de) begin
      $fwrite(fpic, "%x", {r, g, b});
      pice = 1;
    end
    else if (pice) begin
      pice = 0;
      $fwrite(fpic, "\n");
    end
  end
end

`endif

//////////////////////////////////////////////////////////////////////

initial #0 begin
    #10 ; // wait for sdram init.

    load_rombios();
    $display("ROMs loaded.");

    //load_file(pcfx_top.memif_sdram.RAM_BASE_A, "ram.bin", '0);

    reset = 0;
end

initial begin
    repeat (4) #(1000e3) ;
    //#(500e3) ;
    //$writememh("vram0.hex", pcfx_top.mach.vram0.mem);
    //$writememh("vram1.hex", pcfx_top.mach.vram1.mem);
    //$writememh("vce_cp.hex", pcfx_top.mach.vce.cpram.mem);

    $finish;
end

initial if (1) begin
    #(216e3);

    repeat (4) begin
        $display("Pressing JP1.Select...");
        hmi.jp1.select = '1;
        #(20e3) hmi.jp1.select = '0;
        #(20e3) ;
    end

    $display("Pressing JP1.Run...");
    hmi.jp1.run = '1;
    #(20e3) hmi.jp1.run = '0;
    #(20e3);
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s pcfx_top_tb -o pcfx_top_tb.vvp -f pcfx_top.files pcfx_top_tb.sv && ./pcfx_top_tb.vvp"
// End:
