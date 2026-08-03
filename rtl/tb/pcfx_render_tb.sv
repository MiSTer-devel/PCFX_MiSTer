// System video render testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module pcfx_render_tb;

initial begin
    $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
    //$dumpfile("pcfx_render_tb.vcd");
    $dumpvars();
`else
    $dumpfile("pcfx_render_tb.verilator.fst");
    $dumpvars();
`endif
end

/* verilator lint_off PINMISSING */
/* verilator lint_off INITIALDLY */
`include "mmc_kram_vce.svh"
`include "video_rtz5.svh"

//////////////////////////////////////////////////////////////////////

integer fpic;
logic   pice;

initial begin
    fpic = $fopen("pcfx_render.hex", "w");
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

logic clk_ram = 1;

initial forever begin :clkgen_ram
    #0.005 clk_ram = ~clk_ram; // 100 MHz
end

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

localparam CLK_RAM_MHZ = 100.0;

assign SDRAM_CLK = clk_ram;
assign SDRAM_CKE = 1'b1;

sdram_xsds #(.CLK_MHZ(CLK_RAM_MHZ)) sdrb (.*);

//////////////////////////////////////////////////////////////////////
// SDRAM controller

wire [26:0] sdram_ch1_addr;
wire [31:0] sdram_ch1_din, sdram_ch1_dout;
wire [3:0]  sdram_ch1_be;
wire        sdram_ch1_rnw, sdram_ch1_req, sdram_ch1_ready;
wire [26:0] sdram_ch2_addr;
wire [31:0] sdram_ch2_din, sdram_ch2_dout;
wire        sdram_ch2_rnw, sdram_ch2_req, sdram_ch2_ready;
wire [26:0] sdram_ch3_addr;
wire [31:0] sdram_ch3_din, sdram_ch3_dout;
wire        sdram_ch3_rnw, sdram_ch3_req, sdram_ch3_ready;

sdram #(.CLK_MHZ(CLK_RAM_MHZ)) sdram
(
    .*,

    .init('0),
    .clk(clk_ram),
    .hblank(sdram_hblank),

    .ch1_addr(sdram_ch1_addr),
    .ch1_dout(sdram_ch1_dout),
    .ch1_din(sdram_ch1_din),
    .ch1_req(sdram_ch1_req),
    .ch1_rnw(sdram_ch1_rnw),
    .ch1_be(sdram_ch1_be),
    .ch1_ready(sdram_ch1_ready),
    .ch2_addr(sdram_ch2_addr),
    .ch2_dout(sdram_ch2_dout),
    .ch2_din(sdram_ch2_din),
    .ch2_req(sdram_ch2_req),
    .ch2_rnw(sdram_ch2_rnw),
    .ch2_ready(sdram_ch2_ready),
    .ch3_addr(sdram_ch3_addr),
    .ch3_dout(sdram_ch3_dout),
    .ch3_din(sdram_ch3_din),
    .ch3_req(sdram_ch3_req),
    .ch3_rnw(sdram_ch3_rnw),
    .ch3_ready(sdram_ch3_ready)
);

task sdram_read(input [26:0] addr, output [15:0] d);
    sdrb.u1a.read(sdram.addr_to_bank(addr),
                  sdram.addr_to_row(addr),
                  sdram.addr_to_col(addr),
                  d);
endtask

task sdram_write(input [26:0] addr, input [15:0] d);
    sdrb.u1a.write(sdram.addr_to_bank(addr),
                   sdram.addr_to_row(addr),
                   sdram.addr_to_col(addr),
                   d);
endtask

task vram_write(input page, input [17:0] addr, input [15:0] d);
    if (addr[17])
        sdram_write(memif_sdram.KRAMB_BASE_A + {8'b0, page, addr[16:0], 1'b0}, d);
    else
        sdram_write(memif_sdram.KRAMA_BASE_A + {8'b0, page, addr[16:0], 1'b0}, d);
endtask

//////////////////////////////////////////////////////////////////////
// Traffic generator

event           cpu_read, cpu_write;

logic [26:0]    ch1_addr;
logic [31:0]    ch1_dout;
logic [31:0]    ch1_din;
logic           ch1_req;
logic           ch1_rnw;
logic [3:0]     ch1_be;
logic           ch1_ready;

localparam [26:0] ch1_addr0 = 27'h0000000;

initial begin
    ch1_addr = ch1_addr0;
    ch1_req = 0;
    ch1_be = '1;
end

bit cpu_busy_read, cpu_busy_write = 0;

always @(cpu_read) begin :cpu_read_blk
reg [31:0] d;
    cpu_busy_read <= 1;
    ch1_addr <= ch1_addr + 27'd4;
    ch1_rnw <= 1;
    ch1_req <= 1;
    @(posedge clk_ram) ch1_req <= 0;
    @(negedge ch1_ready) ;
    sdram_read(ch1_addr, d[15:0]);
    sdram_read(ch1_addr+2, d[31:16]);
    assert(ch1_dout == d);
    cpu_busy_read <= 0;
end

always @(cpu_write) begin :cpu_write_blk
reg [31:0] d;
    cpu_busy_write <= 1;
    ch1_din <= ~ch1_dout;
    ch1_rnw <= 0;
    ch1_req <= 1;
    @(posedge clk_ram) ch1_req <= 0;
    @(negedge ~ch1_ready) ;
    repeat (5) @(posedge clk_ram) ; // wait for write to commit
    sdram_read(ch1_addr, d[15:0]);
    sdram_read(ch1_addr+2, d[31:16]);
    assert(d == ch1_din);
    cpu_busy_write <= 0;
end

assign sdram_ch1_addr = ch1_addr;
assign ch1_dout = sdram_ch1_dout;
assign sdram_ch1_din = ch1_din;
assign sdram_ch1_req = ch1_req;
assign sdram_ch1_rnw = ch1_rnw;
assign sdram_ch1_be = ch1_be;
assign ch1_ready = sdram_ch1_ready;

//////////////////////////////////////////////////////////////////////

memif_sdram memif_sdram
  (
   .CPU_CLK(clk),
   .CPU_CE('0),
   .CPU_RESn('0),
   .CPU_BCYSTn('1),

   .ROM_A('Z),
   .ROM_DO(),
   .ROM_CEn('1),
   .ROM_READYn(),

   .RAM_A('Z),
   .RAM_DI('Z),
   .RAM_DO(),
   .RAM_CEn('1),
   .RAM_WEn('1),
   .RAM_BEn('1),
   .RAM_READYn(),

   .SRAM_A('Z),
   .SRAM_DI('Z),
   .SRAM_DO(),
   .SRAM_CEn('1),
   .SRAM_WEn('1),
   .SRAM_READYn(),

   .BMP_A('Z),
   .BMP_DI('Z),
   .BMP_DO(),
   .BMP_CEn('1),
   .BMP_WEn('1),
   .BMP_READYn(),

   .KRAMA_A(krama_a),
   .KRAMA_DI(krama_di),
   .KRAMA_DO(krama_do),
   .KRAMA_BE(krama_be),
   .KRAMA_WR(krama_wr),
   .KRAMA_REQ(krama_req),
   .KRAMA_ACK(krama_ack),

   .KRAMB_A(kramb_a),
   .KRAMB_DI(kramb_di),
   .KRAMB_DO(kramb_do),
   .KRAMB_BE(kramb_be),
   .KRAMB_WR(kramb_wr),
   .KRAMB_REQ(kramb_req),
   .KRAMB_ACK(kramb_ack),

   .LS_ADDR('Z),
   .LS_DIN('Z),
   .LS_WE_REQ('0),
   .LS_WE_ACK(),
   .LS_DOUT(),
   .LS_RD_REQ('0),
   .LS_RD_ACK(),

   .SDRAM_CLK(clk_ram),
   .SDRAM_CH1_ADDR(),
   .SDRAM_CH1_DOUT('Z),
   .SDRAM_CH1_DIN(),
   .SDRAM_CH1_REQ(),
   .SDRAM_CH1_RNW(),
   .SDRAM_CH1_BE(),
   .SDRAM_CH1_READY('0),
   .SDRAM_CH2_ADDR(sdram_ch2_addr),
   .SDRAM_CH2_DOUT(sdram_ch2_dout),
   .SDRAM_CH2_DIN(sdram_ch2_din),
   .SDRAM_CH2_REQ(sdram_ch2_req),
   .SDRAM_CH2_RNW(sdram_ch2_rnw),
   .SDRAM_CH2_READY(sdram_ch2_ready),
   .SDRAM_CH3_ADDR(sdram_ch3_addr),
   .SDRAM_CH3_DOUT(sdram_ch3_dout),
   .SDRAM_CH3_DIN(sdram_ch3_din),
   .SDRAM_CH3_REQ(sdram_ch3_req),
   .SDRAM_CH3_RNW(sdram_ch3_rnw),
   .SDRAM_CH3_READY(sdram_ch3_ready)
   );

//////////////////////////////////////////////////////////////////////

function int fuzzy_time(int base);
static int deltas[10] = '{0, -3, 2, 4, -1, -2, 3, 1, -4, 0};
static int i = 0;
    fuzzy_time = base;
    fuzzy_time += deltas[i];
    i = (i + 1) % $size(deltas);
endfunction

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
    @(posedge vsync_negedge) ;

    fork
        begin
        int t;
        static int base = 8; // 8 is worst
            forever begin
                -> cpu_read;
                t = fuzzy_time(base);
                repeat (t) @(posedge clk) ;
                while (cpu_busy_read) @(posedge clk) ;
                -> cpu_write;
                t = fuzzy_time(base);
                repeat (t) @(posedge clk) ;
                while (cpu_busy_write) @(posedge clk) ;
            end
        end
        begin
            @(posedge vsync_negedge) $finish;
        end
    join
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s pcfx_render_tb -DTB_VDC -DTB_VPU -o pcfx_render_tb.vvp ../fifo/fifo1.v ../huc6272.sv ../huc6261.sv ../huc6270.sv ../huc6271.sv dpram.sv ../memif_sdram.sv ../sdram.sv sdram_xsds.sv as4c32m16sb.sv pcfx_render_tb.sv && ./pcfx_render_tb.vvp && python3 yuv_render2png.py pcfx_render.hex pcfx_render.png 360 242"
// End:
