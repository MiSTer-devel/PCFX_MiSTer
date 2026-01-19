// PC-FX core
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import core_pkg::hmi_t;

module pcfx_top
(
	input             clk_sys,
    input             clk_ram,
	input             reset,
    input             pll_locked,
	
    input [1:0]       img_mounted,
    input             img_readonly,
    input [63:0]      img_size,

    output reg [31:0] sd_lba,
    output reg [1:0]  sd_rd = 0,
    output reg [1:0]  sd_wr = 0,
    input [1:0]       sd_ack,

    input [7:0]       sd_buff_addr,
    input [15:0]      sd_buff_dout,
    output [15:0]     sd_buff_din,
    input             sd_buff_wr,

    input             ioctl_download,
    input [7:0]       ioctl_index,
    input             ioctl_wr,
    input [24:0]      ioctl_addr,
    input [15:0]      ioctl_dout,
    output reg        ioctl_wait = '0,

    output            bk_ena,
    input             bk_load,
    input             bk_save,

    input             hmi_t HMI,

	output            SDRAM_CLK,
	output            SDRAM_CKE,
	output [12:0]     SDRAM_A,
	output [1:0]      SDRAM_BA,
	inout [15:0]      SDRAM_DQ,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output            SDRAM_nCS,
	output            SDRAM_nCAS,
	output            SDRAM_nRAS,
	output            SDRAM_nWE,

    output            ERROR,

    output reg        ce_pix,

	output reg        HBlank,
	output reg        HSync,
	output reg        VBlank,
	output reg        VSync,

	output [7:0]      R,
	output [7:0]      G,
	output [7:0]      B
);

reg [24:0]      romwr_a;
reg [31:0]      romwr_d;
reg             romwr_req = 0;
logic [24:0]    bk_sdrd_a;
logic [15:0]    bk_sdrd_din, bk_sdrd_dout;
logic           bk_sdrd_we_req = 0, bk_sdrd_rd_req = 0;
logic           bk_sdrd_we_ack, bk_sdrd_rd_ack;

//////////////////////////////////////////////////////////////////////
// SDRAM controller

wire        sdram_clkref;
wire [24:0] sdram_raddr, sdram_waddr, sdram_ls_addr;
wire [31:0] sdram_din, sdram_dout, sdram_ls_din, sdram_ls_dout;
wire        sdram_rd, sdram_rd_rdy;
wire [3:0]  sdram_be;
wire        sdram_we;
wire        sdram_we_rdy;
wire        sdram_ls_we_req, sdram_ls_we_ack;
wire        sdram_ls_rd_req, sdram_ls_rd_ack;

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

	.raddr(sdram_raddr),
	.rd(sdram_rd),
	.rd_rdy(sdram_rd_rdy),
	.dout(sdram_dout),

    .ls_addr(sdram_ls_addr),
    .ls_din(sdram_ls_din),
	.ls_we_req(sdram_ls_we_req),
	.ls_we_ack(sdram_ls_we_ack),
    .ls_dout(sdram_ls_dout),
	.ls_rd_req(sdram_ls_rd_req),
	.ls_rd_ack(sdram_ls_rd_ack)
);

assign sdram_ls_addr = ioctl_download ? romwr_a : bk_sdrd_a;
assign sdram_ls_din = ioctl_download ? romwr_d : {16'b0, bk_sdrd_dout};
assign sdram_ls_we_req = romwr_req ^ bk_sdrd_we_req;
assign bk_sdrd_din = sdram_ls_dout[15:0];
assign sdram_ls_rd_req = bk_sdrd_rd_req;
assign romwr_ack = sdram_ls_we_ack ^ bk_sdrd_we_req;
assign bk_sdrd_we_ack = sdram_ls_we_ack ^ romwr_req;
assign bk_sdrd_rd_ack = sdram_ls_rd_ack;

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

wire [22:0] bmp_a;
wire [7:0]  bmp_di, bmp_do;
wire        bmp_cen;
wire        bmp_wen;
wire        bmp_readyn;

wire clk_cpu = clk_sys;
wire reset_int = reset | ioctl_download;

initial cpu_ce = 0;

always @(posedge clk_cpu) begin
  cpu_ce <= ~cpu_ce;
  reset_cpu <= reset_int;
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

   .BMP_A(bmp_a),
   .BMP_DI(bmp_di),
   .BMP_DO(bmp_do),
   .BMP_CEn(bmp_cen),
   .BMP_WEn(bmp_wen),
   .BMP_READYn(bmp_readyn),

   .HMI(HMI),

   .A(a),
   .ERROR(ERROR),

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

   .BMP_A(bmp_a),
   .BMP_DI(bmp_di),
   .BMP_DO(bmp_do),
   .BMP_CEn(bmp_cen),
   .BMP_WEn(bmp_wen),
   .BMP_READYn(bmp_readyn),

   .SDRAM_CLK(clk_ram),
   .SDRAM_CLKREF(sdram_clkref),
   .SDRAM_WADDR(sdram_waddr),
   .SDRAM_DIN(sdram_din),
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

`include "memif_sdram_part.svh"

reg         romwr_active = 0;
reg         romwr_a1;
wire        romwr_ack;

always @(posedge clk_sys) begin
	reg old_download;

	old_download <= ioctl_download;

    if (~ioctl_download) begin
        romwr_active <= 0;
    end
	if(~old_download && ioctl_download) begin
        romwr_active <= 1;
        romwr_a1 <= 0;
        case (ioctl_index[5:0])
            6'd0, 6'd1: romwr_a <= ROM_BASE_A;
//          6'd2:       romwr_a <= SRAM_BASE_A;
//          6'd3:       romwr_a <= BMP_BASE_A;
            default: romwr_active <= 0;
        endcase
	end
	else begin
		if(ioctl_wr & romwr_active) begin
            if (romwr_a1) begin
			    ioctl_wait <= 1;
			    romwr_req <= ~romwr_req;
            end
            romwr_d <= {ioctl_dout, romwr_d[31:16]};
            romwr_a1 <= ~romwr_a1;
		end else if(ioctl_wait && (romwr_req == romwr_ack)) begin
			ioctl_wait <= 0;
			romwr_a <= romwr_a + 25'd4;
		end
	end
end

//////////////////////////////////////////////////////////////////////
// Backup RAM transfer

typedef enum bit [3:0] {
    BKST_IDLE = '0,
    BKST_SELECT_VD,
    BKST_START_SD_RD,
    BKST_SD_RD,
    BKST_START_SD_WR,
    BKST_SD_WR,
    BKST_START_SDRAM_WR,
    BKST_SDRAM_WR,
    BKST_START_SDRAM_RD,
    BKST_SDRAM_RD,
    BKST_NEXT_LBA,
    BKST_NEXT_VD
} bkst_t;

logic [1:0]     img_mounted_d, img_mounted_add, img_mounted_rem;
logic [63:0]    img_sizes [2];

bkst_t          bk_state = BKST_IDLE;
logic           bk_loading = 0;
logic           bk_saving = 0;
logic           sd_vd; // volume select

logic           sd_ack_d;

assign img_mounted_add = img_mounted & ~img_mounted_d;
assign img_mounted_rem = ~img_mounted & img_mounted_d;

always @(posedge clk_sys) begin
    img_mounted_d <= img_mounted;

    if (|img_mounted_add)
        img_sizes[img_mounted_add[1]] <= img_size;
    if (|img_mounted_rem)
        img_sizes[img_mounted_rem[1]] <= '0;
end

always @(posedge clk_sys) begin
    sd_ack_d <= |sd_ack;

    if (~sd_ack_d & |sd_ack)
        {sd_rd, sd_wr} <= '0;

    case (bk_state)
        BKST_IDLE: begin
            if (bk_load) begin
                bk_loading <= 1;
                sd_vd <= 0;
                bk_state <= BKST_SELECT_VD;
            end
            else if (bk_save) begin
                bk_saving <= 1;
                sd_vd <= 0;
                bk_state <= BKST_SELECT_VD;
            end
        end
        BKST_SELECT_VD: begin
            if (img_mounted[sd_vd])
                bk_state <= bk_loading ? BKST_START_SD_RD : BKST_START_SDRAM_RD;
            else
                bk_state <= BKST_NEXT_VD;
            sd_lba <= 0;
        end
        BKST_START_SD_RD: begin
            sd_rd[sd_vd] <= 1;
            bk_state <= BKST_SD_RD;
        end
        BKST_SD_RD: begin
            if (sd_ack_d & ~|sd_ack) begin
                bk_state <= BKST_START_SDRAM_WR;
            end
        end
        BKST_START_SD_WR: begin
            sd_wr[sd_vd] <= 1;
            bk_state <= BKST_SD_WR;
        end
        BKST_SD_WR: begin
            if (sd_ack_d & ~|sd_ack) begin
                bk_state <= BKST_NEXT_LBA;
            end
        end
        BKST_START_SDRAM_WR: begin
            bk_sdrd_copy_req <= ~bk_sdrd_copy_req;
            bk_state <= BKST_SDRAM_WR;
        end
        BKST_SDRAM_WR: begin
            if (bk_sdrd_copy_req == bk_sdrd_copy_ack) begin
                bk_state <= BKST_NEXT_LBA;
            end
        end
        BKST_START_SDRAM_RD: begin
            bk_sdrd_copy_req <= ~bk_sdrd_copy_req;
            bk_state <= BKST_SDRAM_RD;
        end
        BKST_SDRAM_RD: begin
            if (bk_sdrd_copy_req == bk_sdrd_copy_ack)
                bk_state <= bk_loading ? BKST_START_SDRAM_WR : BKST_START_SD_WR;
        end
        BKST_NEXT_LBA: begin
            if (sd_lba + 1'd1 == img_sizes[sd_vd][9+:32]) begin
                bk_state <= BKST_NEXT_VD;
                sd_lba <= 0;
            end
            else begin
                sd_lba <= sd_lba + 1'd1;
                bk_state <= bk_loading ? BKST_START_SD_RD : BKST_START_SDRAM_RD;
            end
        end
        BKST_NEXT_VD: begin
            sd_vd <= ~sd_vd;
            if (sd_vd) begin // last volume
                bk_state <= BKST_IDLE;
                bk_loading <= 0;
                bk_saving <= 0;
            end
            else
                bk_state <= BKST_SELECT_VD;
        end
        default: ;
    endcase
end

assign bk_ena = |img_mounted;

//////////////////////////////////////////////////////////////////////
// SD card transfer buffer

logic           bk_sdrd_copy_req = 0;
logic           bk_sdrd_copy_ack = 0;
logic           bk_sdrd_copying = 0;
logic [24:0]    bk_sdrd_base_a;

logic [7:0]     sdbuf_a;
logic           sdbuf_wren = 0;
logic           sdbuf_rden = 0;

assign bk_sdrd_base_a = sd_vd ? BMP_BASE_A : SRAM_BASE_A;

always @(posedge clk_sys) begin
    if (~bk_sdrd_copying & (bk_sdrd_copy_req != bk_sdrd_copy_ack)) begin
        bk_sdrd_copying <= 1;
        bk_sdrd_a <= bk_sdrd_base_a + 25'({sd_lba, 9'b0});
        if (bk_loading)
            sdbuf_rden <= 1;
        else
            bk_sdrd_rd_req <= ~bk_sdrd_rd_req;
    end
    else if (bk_sdrd_copying) begin
        if (bk_loading & sdbuf_rden) begin
            sdbuf_rden <= 0;
            bk_sdrd_we_req <= ~bk_sdrd_we_req;
        end
        else if (bk_saving & ~sdbuf_wren & (bk_sdrd_rd_req == bk_sdrd_rd_ack)) begin
            sdbuf_wren <= 1;
        end
        else if ((bk_loading & (bk_sdrd_we_req == bk_sdrd_we_ack)) |
                 (bk_saving & sdbuf_wren)) begin
            sdbuf_wren <= 0;
            if (&sdbuf_a) begin
                bk_sdrd_copying <= 0;
                bk_sdrd_copy_ack <= bk_sdrd_copy_req;
            end
            else begin
                if (bk_loading)
                    sdbuf_rden <= 1;
                else
                    bk_sdrd_rd_req <= ~bk_sdrd_rd_req;
            end
            bk_sdrd_a <= bk_sdrd_a + 25'd2;
        end
    end
end

assign sdbuf_a = bk_sdrd_a[8:1];

dpram #(.addr_width(8), .data_width(16)) sdbuf
   (
    .clock(clk_sys),
    .address_a(sd_buff_addr),
    .data_a(sd_buff_dout),
    .enable_a(1'b1),
    .wren_a(sd_buff_wr),
    .q_a(sd_buff_din),
    .cs_a(1'b1),

    .address_b(sdbuf_a),
    .data_b(bk_sdrd_din),
    .enable_b(1'b1),
    .wren_b(sdbuf_wren),
    .q_b(bk_sdrd_dout),
    .cs_b(1'b1)
    );

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
