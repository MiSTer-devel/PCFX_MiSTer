// PC-FX core
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

import core_pkg::hmi_t;

module pcfx_top
    #(parameter CLK_RAM_MHZ = 100.0)
(
	input             clk_sys,
    input             clk_ram,
	input             reset,
    input             pll_locked,
	
    input [2:0]       img_mounted,
    input             img_readonly,
    input [63:0]      img_size,

    output reg [31:0] sd_lba_bk,
    output reg [31:0] sd_lba_cd,
    output [5:0]      sd_blk_cnt_bk,
    output [5:0]      sd_blk_cnt_cd,
    output [2:0]      sd_rd,
    output [2:0]      sd_wr,
    input [2:0]       sd_ack,

    input [12:0]      sd_buff_addr,
    input [15:0]      sd_buff_dout,
    output [15:0]     sd_buff_din_bk,
    input             sd_buff_wr,

    input             ioctl_download,
    input [7:0]       ioctl_index,
    input             ioctl_wr,
    input [24:0]      ioctl_addr,
    input [15:0]      ioctl_dout,
    output reg        ioctl_wait = '0,

    output [1:0]      bk_ena_img_mount,
    output            bk_ena,
    input             bk_load,
    input             bk_save,
    output reg        bmp_rom_inserted = 0,
    input             bmp_eject_rom,

    input             hmi_t HMI,

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

    output            ce_pix,

	output            HBlank,
	output            HSync,
	output            VBlank,
	output            VSync,

	output [7:0]      R,
	output [7:0]      G,
	output [7:0]      B,

    output [15:0]     AUD_SLOUT,
    output [15:0]     AUD_SROUT
);

reg [26:0]      romwr_a;
reg [31:0]      romwr_d;
reg             romwr_req = 0;
wire            romwr_ack;
logic [26:0]    bk_sdrd_a;
logic [31:0]    bk_sdrd_din, bk_sdrd_dout;
logic           bk_sdrd_we_req = 0, bk_sdrd_rd_req = 0;
logic           bk_sdrd_we_ack, bk_sdrd_rd_ack;
logic [31:0]    bk_sd_blk_cnt [2];
logic [1:0]     bk_mounted;
logic           cd_mounted = 0;

//////////////////////////////////////////////////////////////////////
// SDRAM controller

wire        sdram_hblank;
wire [26:0] sdram_ch1_addr;
wire [31:0] sdram_ch1_din, sdram_ch1_dout;
wire [3:0]  sdram_ch1_be;
wire        sdram_ch1_rnw, sdram_ch1_req, sdram_ch1_ready;
wire [26:0] sdram_ch2_addr;
wire [15:0] sdram_ch2_din, sdram_ch2_dout;
wire        sdram_ch2_rnw, sdram_ch2_req, sdram_ch2_ready;
wire [26:0] sdram_ch3_addr;
wire [15:0] sdram_ch3_din, sdram_ch3_dout;
wire        sdram_ch3_rnw, sdram_ch3_req, sdram_ch3_ready;

sdram #(.CLK_MHZ(CLK_RAM_MHZ)) sdram
(
    .*,

    .init(~pll_locked),
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

wire [26:1] mcp_a;
wire [7:0]  mcp_di, mcp_do;
wire        mcp_csn;
wire        mcp_rdn;
wire        mcp_wrn;
wire        mcp_readyn;

wire [17:0] krama_a;
wire [15:0] krama_di, krama_do;
wire [1:0]  krama_be;
wire        krama_wr, krama_req, krama_ack;
wire [17:0] kramb_a;
wire [15:0] kramb_di, kramb_do;
wire [1:0]  kramb_be;
wire        kramb_wr, kramb_req, kramb_ack;

wire        sd_rd_cd;
wire        sd_ack_cd;
wire [12:0] cd_sdbuf_addr;
wire [15:0] cd_sdbuf_dout;

wire        bmp_cfg_en;
logic [2:0] bmp_cfg_size;
wire [22:0] bmp_a;
wire [7:0]  bmp_di, bmp_do;
wire        bmp_cen;
wire        bmp_wen;
wire        bmp_readyn;

wire [26:0] ls_addr;
wire [31:0] ls_din, ls_dout;
wire        ls_we_req, ls_we_ack;
wire        ls_rd_req, ls_rd_ack;

wire clk_cpu = clk_sys;
wire reset_int = reset | ioctl_download;

initial cpu_ce = 0;
initial reset_cpu = 1;
initial cpu_resn = 0;

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

   .SDRAM_HBLANK(sdram_hblank),
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

   .MCP_A(mcp_a),
   .MCP_DI(mcp_di),
   .MCP_DO(mcp_do),
   .MCP_CSn(mcp_csn),
   .MCP_RDn(mcp_rdn),
   .MCP_WRn(mcp_wrn),
   .MCP_READYn(mcp_readyn),

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

   .CD_EN(cd_mounted),
   .CD_SD_LBA(sd_lba_cd),
   .CD_SD_RD(sd_rd_cd),
   .CD_SD_ACK(sd_ack_cd),
   .CD_SDBUF_ADDR(cd_sdbuf_addr),
   .CD_SDBUF_DOUT(cd_sdbuf_dout),

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
   .VID_HBL(vid_hbl),

   .AUD_SLOUT(AUD_SLOUT),
   .AUD_SROUT(AUD_SROUT)
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

   .LS_ADDR(ls_addr),
   .LS_DIN(ls_din),
   .LS_WE_REQ(ls_we_req),
   .LS_WE_ACK(ls_we_ack),
   .LS_DOUT(ls_dout),
   .LS_RD_REQ(ls_rd_req),
   .LS_RD_ACK(ls_rd_ack),

   .SDRAM_CLK(clk_ram),
   .SDRAM_CH1_ADDR(sdram_ch1_addr),
   .SDRAM_CH1_DOUT(sdram_ch1_dout),
   .SDRAM_CH1_DIN(sdram_ch1_din),
   .SDRAM_CH1_REQ(sdram_ch1_req),
   .SDRAM_CH1_RNW(sdram_ch1_rnw),
   .SDRAM_CH1_BE(sdram_ch1_be),
   .SDRAM_CH1_READY(sdram_ch1_ready),
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

fx_bmp bmp
  (
   .CFG_EN(bmp_cfg_en),
   .CFG_SIZE(bmp_cfg_size),

   .MCP_A(mcp_a),
   .MCP_DI(mcp_di),
   .MCP_DO(mcp_do),
   .MCP_CSn(mcp_csn),
   .MCP_RDn(mcp_rdn),
   .MCP_WRn(mcp_wrn),
   .MCP_READYn(mcp_readyn),

   .RAM_A(bmp_a),
   .RAM_DI(bmp_di),
   .RAM_DO(bmp_do),
   .RAM_CEn(bmp_cen),
   .RAM_WEn(bmp_wen),
   .RAM_READYn(bmp_readyn)
   );

assign ls_addr = ioctl_download ? romwr_a : bk_sdrd_a;
assign ls_din = ioctl_download ? romwr_d : bk_sdrd_dout;
assign ls_we_req = romwr_req ^ bk_sdrd_we_req;
assign ls_rd_req = bk_sdrd_rd_req;
assign bk_sdrd_din = ls_dout;
assign romwr_ack = ls_we_ack ^ bk_sdrd_we_req;
assign bk_sdrd_we_ack = ls_we_ack ^ romwr_req;
assign bk_sdrd_rd_ack = ls_rd_ack;

//////////////////////////////////////////////////////////////////////
// ROM loader

`include "memif_sdram_part.svh"

reg         romwr_active = 0;
reg         romwr_a1;
wire        romwr_download_bmp;

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
            6'd2:       romwr_a <= BMP_BASE_A;
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
			romwr_a <= romwr_a + 27'd4;
		end
	end
end

assign romwr_download_bmp = romwr_active & ~ioctl_download &
                            (ioctl_index[5:0] == 6'd2);

//////////////////////////////////////////////////////////////////////
// FX-BMP -> Memory Cord Port

logic [31:0]    bmp_ioctl_blk_cnt = 0;
logic [31:0]    bmp_sd_blk_cnt;
logic [31:0]    bmp_blk_cnt;

// BMP contents can come from ioctl (ROM cart) or sd (backup RAM).
always @(posedge clk_sys) begin
    if (~bmp_rom_inserted & romwr_download_bmp) begin
        bmp_rom_inserted <= '1;
        bmp_ioctl_blk_cnt <= 32'(ioctl_addr[24:9]);
    end
    else if (bmp_rom_inserted & bmp_eject_rom) begin
        bmp_rom_inserted <= '0;
    end
end

assign bmp_blk_cnt = bmp_rom_inserted ? bmp_ioctl_blk_cnt : bk_sd_blk_cnt[1];

assign bmp_cfg_en = bmp_rom_inserted | bk_mounted[1];

// Configure the BMP size to match the mounted image size.
always @* begin
    casez ({|bmp_blk_cnt[31:14], bmp_blk_cnt[13:8]})
        7'b1??_????:    bmp_cfg_size = 3'd6; // 8MB
        7'b01?_????:    bmp_cfg_size = 3'd5; // 4MB
        7'b001_????:    bmp_cfg_size = 3'd4; // 2MB
        7'b000_1???:    bmp_cfg_size = 3'd3; // 1MB
        7'b000_01??:    bmp_cfg_size = 3'd2; // 512KB
        7'b000_001?:    bmp_cfg_size = 3'd1; // 256KB
        default:        bmp_cfg_size = 3'd0; // 128KB
    endcase
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

bkst_t          bk_state = BKST_IDLE;
logic           bk_loading = 0;
logic           bk_saving = 0;
logic           sd_vd; // volume select
logic           bk_sdrd_copy_req = 0;
logic           bk_sdrd_copy_ack = 0;

logic [1:0]     sd_rd_bk = '0, sd_wr_bk = '0;
wire [1:0]      sd_ack_bk = sd_ack[1:0];
logic           sd_ack_d;

assign sd_rd[1:0] = sd_rd_bk;
assign sd_wr[1:0] = sd_wr_bk;

assign bk_ena_img_mount[0] = '1; // SRAM
assign bk_ena_img_mount[1] = ~bmp_rom_inserted; // BMP

always @(posedge clk_sys) begin
    if (img_mounted[1:0] != 0) begin
        bk_mounted[img_mounted[1]] <= |img_size;
        bk_sd_blk_cnt[img_mounted[1]] <= img_size[9+:32];
    end
    if (img_mounted[2])
        cd_mounted <= |img_size;
end

assign bk_ena = |bk_mounted;

always @(posedge clk_sys) begin
    sd_ack_d <= |sd_ack_bk;

    if (~sd_ack_d & |sd_ack_bk)
        {sd_rd_bk, sd_wr_bk} <= '0;

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
            if (bk_mounted[sd_vd])
                bk_state <= bkst_t'(bk_loading ? BKST_START_SD_RD : BKST_START_SDRAM_RD);
            else
                bk_state <= BKST_NEXT_VD;
            sd_lba_bk <= 0;
        end
        BKST_START_SD_RD: begin
            sd_rd_bk[sd_vd] <= 1;
            bk_state <= BKST_SD_RD;
        end
        BKST_SD_RD: begin
            if (sd_ack_d & ~|sd_ack_bk) begin
                bk_state <= BKST_START_SDRAM_WR;
            end
        end
        BKST_START_SD_WR: begin
            sd_wr_bk[sd_vd] <= 1;
            bk_state <= BKST_SD_WR;
        end
        BKST_SD_WR: begin
            if (sd_ack_d & ~|sd_ack_bk) begin
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
                bk_state <= bkst_t'(bk_loading ? BKST_START_SDRAM_WR : BKST_START_SD_WR);
        end
        BKST_NEXT_LBA: begin
            if (sd_lba_bk + 1'd1 == bk_sd_blk_cnt[sd_vd]) begin
                bk_state <= BKST_NEXT_VD;
                sd_lba_bk <= 0;
            end
            else begin
                sd_lba_bk <= sd_lba_bk + 1'd1;
                bk_state <= bkst_t'(bk_loading ? BKST_START_SD_RD : BKST_START_SDRAM_RD);
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

//////////////////////////////////////////////////////////////////////
// Backup RAM SD card transfer buffer

logic           bk_sdrd_copying = 0;
logic [26:0]    bk_sdrd_base_a;

logic [7:0]     sdbuf_a;
logic           sdbuf_a0, sdbuf_a0_d;
logic [15:0]    sdbuf_din, sdbuf_dout, sdbuf_dout_d;
logic           sdbuf_wren = 0;
logic           sdbuf_rden = 0;

assign sd_blk_cnt_bk = 6'(1-1); // 1x 512 block
assign sd_blk_cnt_cd = 6'(1-1); // 1x (PCFX_BUFFER_SIZE) block

assign bk_sdrd_base_a = sd_vd ? BMP_BASE_A : SRAM_BASE_A;

always @(posedge clk_sys) begin
    if (~bk_sdrd_copying & (bk_sdrd_copy_req != bk_sdrd_copy_ack)) begin
        bk_sdrd_copying <= 1;
        bk_sdrd_a <= bk_sdrd_base_a + 27'({sd_lba_bk, 9'b0});
        sdbuf_a0 <= '0;
        if (bk_loading)
            sdbuf_rden <= 1;
        else
            bk_sdrd_rd_req <= ~bk_sdrd_rd_req;
    end
    else if (bk_sdrd_copying) begin
        if (bk_loading & sdbuf_rden) begin
            if (sdbuf_a0) begin
                sdbuf_rden <= 0;
                bk_sdrd_we_req <= ~bk_sdrd_we_req;
            end
            else
                sdbuf_a0 <= ~sdbuf_a0;
        end
        else if (bk_saving & ~sdbuf_wren & (bk_sdrd_rd_req == bk_sdrd_rd_ack)) begin
            sdbuf_wren <= 1;
        end
        else if ((bk_loading & (bk_sdrd_we_req == bk_sdrd_we_ack)) |
                 (bk_saving & sdbuf_wren)) begin
            if (sdbuf_a0) begin
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
                bk_sdrd_a <= bk_sdrd_a + 27'd4;
            end
            sdbuf_a0 <= ~sdbuf_a0;
        end
    end
end

always @(posedge clk_sys) begin
    sdbuf_a0_d <= sdbuf_a0;
    if (sdbuf_rden & ~sdbuf_a0_d)
        sdbuf_dout_d <= sdbuf_dout;
end

assign sdbuf_a = {bk_sdrd_a[8:2], sdbuf_a0};
assign sdbuf_din = sdbuf_a0 ? bk_sdrd_din[31:16] : bk_sdrd_din[15:0];
assign bk_sdrd_dout = {sdbuf_dout, sdbuf_dout_d};

dpram #(.addr_width(8), .data_width(16)) sdbuf
   (
    .clock(clk_sys),
    .address_a(sd_buff_addr[7:0]),
    .data_a(sd_buff_dout),
    .enable_a(1'b1),
    .wren_a(sd_buff_wr),
    .q_a(sd_buff_din_bk),
    .cs_a(|sd_ack_bk),

    .address_b(sdbuf_a),
    .data_b(sdbuf_din),
    .enable_b(1'b1),
    .wren_b(sdbuf_wren),
    .q_b(sdbuf_dout),
    .cs_b(1'b1)
    );

//////////////////////////////////////////////////////////////////////
// CD-ROM block transfer

assign sd_rd[2] = sd_rd_cd;
assign sd_wr[2] = '0;
assign sd_ack_cd = sd_ack[2];

dpram #(.addr_width(13), .data_width(16)) cdbuf
   (
    .clock(clk_sys),
    .address_a(sd_buff_addr[12:0]),
    .data_a(sd_buff_dout),
    .enable_a(1'b1),
    .wren_a(sd_buff_wr),
    .q_a(),
    .cs_a(sd_ack_cd),

    .address_b(cd_sdbuf_addr),
    .data_b('0),
    .enable_b(1'b1),
    .wren_b('0),
    .q_b(cd_sdbuf_dout),
    .cs_b(1'b1)
    );

//////////////////////////////////////////////////////////////////////
// Video output

wire csc_vsn, csc_hsn;

yuv2rgb csc
   (
    .CLK(clk_sys),

    .I_PCE(vid_pce),
    .I_Y(vid_y),
    .I_U(vid_u),
    .I_V(vid_v),
    .I_VSn(vid_vsn),
    .I_HSn(vid_hsn),
    .I_VBL(vid_vbl),
    .I_HBL(vid_hbl),

    .O_PCE(ce_pix),
    .O_R(R),
    .O_G(G),
    .O_B(B),
    .O_VSn(csc_vsn),
    .O_HSn(csc_hsn),
    .O_VBL(VBlank),
    .O_HBL(HBlank)
    );

assign HSync = ~csc_hsn;
assign VSync = ~csc_vsn;

endmodule
