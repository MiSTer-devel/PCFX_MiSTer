// V810 Test Core
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module mycore
(
	input         clk_sys,
    input         clk_cpu,
    input         clk_ram,
	input         reset,
    input         pll_locked,
	
	input         pal,
	input         scandouble,

    input         ioctl_download,
    input [7:0]   ioctl_index,
    input         ioctl_wr,
    input [24:0]  ioctl_addr,
    input [15:0]  ioctl_dout,
    output reg    ioctl_wait = '0,

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
wire [8:0]  vdc0_vd, vdc1_vd;

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

wire [24:0] memif_sdram_waddr;
wire [31:0] memif_sdram_din;

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

   .A(a),
   .VDC0_VD(vdc0_vd),
   .VDC1_VD(vdc1_vd)
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

reg   [9:0] hc;
reg   [9:0] vc;
reg   [7:0] fc;
reg [23:0]  pix;

always @(posedge clk_sys) begin
	if(scandouble) ce_pix <= 1;
		else ce_pix <= ~ce_pix;

	if(reset) begin
		hc <= 0;
		vc <= 0;
        fc <= 0;
	end
	else if(ce_pix) begin
		if(hc == 637) begin
			hc <= 0;
			if(vc == (pal ? (scandouble ? 623 : 311) : (scandouble ? 523 : 261))) begin 
				vc <= 0;
				fc <= fc + 1'd1;
			end else begin
				vc <= vc + 1'd1;
			end
		end else begin
			hc <= hc + 1'd1;
		end
	end
end

always @(posedge clk_sys) begin
	if (hc == 529) HBlank <= 1;
		else if (hc == 0) HBlank <= 0;

	if (hc == 544) begin
		HSync <= 1;

		if(pal) begin
			if(vc == (scandouble ? 609 : 304)) VSync <= 1;
				else if (vc == (scandouble ? 617 : 308)) VSync <= 0;

			if(vc == (scandouble ? 601 : 300)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
		else begin
			if(vc == (scandouble ? 490 : 245)) VSync <= 1;
				else if (vc == (scandouble ? 496 : 248)) VSync <= 0;

			if(vc == (scandouble ? 480 : 240)) VBlank <= 1;
				else if (vc == 0) VBlank <= 0;
		end
	end
	
	if (hc == 590) HSync <= 0;
end

always @(posedge clk_sys) begin
    pix[23:16] <= {a[31], a[8:2]};
    pix[15:8]  <= vdc0_vd[7:0];
    pix[7:0]   <= vdc1_vd[7:0];
end

assign R = pix[23:16];
assign G = pix[15:8];
assign B = pix[7:0];

endmodule
