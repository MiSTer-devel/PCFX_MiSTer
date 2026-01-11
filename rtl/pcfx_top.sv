// PC-FX core
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import core_pkg::hmi_t;

module pcfx_top
(
	input         clk_sys,
    input         clk_ram,
	input         reset,
    input         pll_locked,
	
    input         ioctl_download,
    input [7:0]   ioctl_index,
    input         ioctl_wr,
    input [24:0]  ioctl_addr,
    input [15:0]  ioctl_dout,
    output reg    ioctl_wait = '0,

    input         hmi_t HMI,

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output [1:0]  SDRAM_BA,
	inout [15:0]  SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

    output reg    ce_pix,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,

	output [7:0]  R,
	output [7:0]  G,
	output [7:0]  B
);

//////////////////////////////////////////////////////////////////////
// SDRAM controller

wire        sdram_clkref;
wire [24:0] sdram_raddr, sdram_waddr;
wire [31:0] sdram_din, sdram_dout;
wire        sdram_rd, sdram_rd_rdy;
wire [3:0]  sdram_be;
wire        sdram_we;
wire        sdram_we_rdy;
wire        sdram_we_req, sdram_we_ack;

sdram sdram
(
	.*,

	.init(~pll_locked),
	.clk(clk_ram),
	.clkref(sdram_clkref),

	.waddr(sdram_waddr),
	.din(sdram_din),
    .be(sdram_be),
	.we(sdram_we),
    .we_rdy(sdram_we_rdy),
	.we_req(sdram_we_req),
	.we_ack(sdram_we_ack),

	.raddr(sdram_raddr),
	.rd(sdram_rd),
	.rd_rdy(sdram_rd_rdy),
	.dout(sdram_dout)
);

//////////////////////////////////////////////////////////////////////
// Computer assembly

reg         cpu_ce;
reg         reset_cpu;
reg         cpu_resn;
wire        cpu_bcystn;
reg [31:0]  a;
wire        vid_pce;
wire [7:0]  vid_y;
wire [7:0]  vid_u;
wire [7:0]  vid_v;
wire        vid_vsn;
wire        vid_hsn;
wire        vid_vbl;
wire        vid_hbl;

wire [19:0] rom_a;
wire [15:0] rom_do;
wire        rom_cen;
wire        rom_readyn;

wire [20:0] ram_a;
wire [31:0] ram_di, ram_do;
wire        ram_cen;
wire        ram_wen;
wire [3:0]  ram_ben;
wire        ram_readyn;

wire [14:0] sram_a;
wire [7:0]  sram_di, sram_do;
wire        sram_cen;
wire        sram_wen;
wire        sram_readyn;

wire [24:0] memif_sdram_waddr;
wire [31:0] memif_sdram_din;

wire clk_cpu = clk_sys;

initial cpu_ce = 0;

always @(posedge clk_cpu) begin
  cpu_ce <= ~cpu_ce;
  reset_cpu <= reset /*| &fc*/;
end

always @(posedge clk_cpu) if (cpu_ce) begin
  cpu_resn <= ~reset_cpu;
end

mach mach
  (
   .CLK(clk_cpu),
   .CE(cpu_ce),
   .RESn(cpu_resn),

   .CPU_BCYSTn(cpu_bcystn),

   .ROM_A(rom_a),
   .ROM_DO(rom_do),
   .ROM_CEn(rom_cen),
   .ROM_READYn(rom_readyn),

   .RAM_A(ram_a),
   .RAM_DI(ram_di),
   .RAM_DO(ram_do),
   .RAM_CEn(ram_cen),
   .RAM_WEn(ram_wen),
   .RAM_BEn(ram_ben),
   .RAM_READYn(ram_readyn),

   .SRAM_A(sram_a),
   .SRAM_DI(sram_di),
   .SRAM_DO(sram_do),
   .SRAM_CEn(sram_cen),
   .SRAM_WEn(sram_wen),
   .SRAM_READYn(sram_readyn),

   .HMI(HMI),

   .A(a),

   .VID_PCE(vid_pce),
   .VID_Y(vid_y),
   .VID_U(vid_u),
   .VID_V(vid_v),
   .VID_VSn(vid_vsn),
   .VID_HSn(vid_hsn),
   .VID_VBL(vid_vbl),
   .VID_HBL(vid_hbl)
   );

memif_sdram memif_sdram
  (
   .CPU_CLK(clk_cpu),
   .CPU_CE(cpu_ce),
   .CPU_RESn(cpu_resn),
   .CPU_BCYSTn(cpu_bcystn),

   .ROM_A(rom_a),
   .ROM_DO(rom_do),
   .ROM_CEn(rom_cen),
   .ROM_READYn(rom_readyn),

   .RAM_A(ram_a),
   .RAM_DI(ram_di),
   .RAM_DO(ram_do),
   .RAM_CEn(ram_cen),
   .RAM_WEn(ram_wen),
   .RAM_BEn(ram_ben),
   .RAM_READYn(ram_readyn),

   .SRAM_A(sram_a),
   .SRAM_DI(sram_di),
   .SRAM_DO(sram_do),
   .SRAM_CEn(sram_cen),
   .SRAM_WEn(sram_wen),
   .SRAM_READYn(sram_readyn),

   .SDRAM_CLK(clk_ram),
   .SDRAM_CLKREF(sdram_clkref),
   .SDRAM_WADDR(memif_sdram_waddr),
   .SDRAM_DIN(memif_sdram_din),
   .SDRAM_BE(sdram_be),
   .SDRAM_WE(sdram_we),
   .SDRAM_WE_RDY(sdram_we_rdy),
   .SDRAM_RADDR(sdram_raddr),
   .SDRAM_RD(sdram_rd),
   .SDRAM_RD_RDY(sdram_rd_rdy),
   .SDRAM_DOUT(sdram_dout)
   );

//////////////////////////////////////////////////////////////////////
// ROM loader

wire rombios_download   = ioctl_download & (ioctl_index[5:0] <= 6'h01);

reg [23:0]  romwr_a;
reg         romwr_a1;
reg [31:0]  romwr_d;
reg         rom_wr = 0;
wire        romwr_ack;

always @(posedge clk_sys) begin
	reg old_download, old_reset;

	old_download <= rombios_download;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(~old_download && rombios_download) begin
		romwr_a <= 0;
        romwr_a1 <= 0;
	end
	else begin
		if(ioctl_wr & rombios_download) begin
            if (romwr_a1) begin
			    ioctl_wait <= 1;
			    rom_wr <= ~rom_wr;
            end
            romwr_d <= {ioctl_dout, romwr_d[31:16]};
            romwr_a1 <= ~romwr_a1;
		end else if(ioctl_wait && (rom_wr == romwr_ack)) begin
			ioctl_wait <= 0;
			romwr_a <= romwr_a + 24'd4;
		end
	end
end

assign sdram_waddr = rombios_download ? {1'b0, romwr_a} : memif_sdram_waddr;
assign sdram_din = rombios_download ? romwr_d : memif_sdram_din;
assign sdram_we_req = rombios_download & rom_wr;
assign romwr_ack = sdram_we_ack;

//////////////////////////////////////////////////////////////////////
// Video output

assign ce_pix = vid_pce;
assign R = vid_u;
assign G = vid_y;
assign B = vid_v;
assign HBlank = vid_hbl;
assign VBlank = vid_vbl;
assign HSync = ~vid_hsn;
assign VSync = ~vid_vsn;

endmodule
