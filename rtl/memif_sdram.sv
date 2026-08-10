// Use external MiSTer SDRAM as memory backing store
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module memif_sdram
  (
    input         CPU_CLK,
    input         CPU_CE,
    input         CPU_RESn,
    input         CPU_BCYSTn,

    input [19:0]  ROM_A,
    output [15:0] ROM_DO,
    input         ROM_CEn,
    output        ROM_READYn,

    input [20:0]  RAM_A,
    input [31:0]  RAM_DI,
    output [31:0] RAM_DO,
    input         RAM_CEn,
    input         RAM_WEn,
    input [3:0]   RAM_BEn,
    output        RAM_READYn,

    input [14:0]  SRAM_A,
    input [7:0]   SRAM_DI,
    output [7:0]  SRAM_DO,
    input         SRAM_CEn,
    input         SRAM_WEn,
    output        SRAM_READYn,

    input [22:0]  BMP_A,
    input [7:0]   BMP_DI,
    output [7:0]  BMP_DO,
    input         BMP_CEn,
    input         BMP_WEn,
    output        BMP_READYn,

    // KRAM bank A memory interface
    input [18:1]  KRAMA_A,
    output [15:0] KRAMA_DI,
    input [15:0]  KRAMA_DO,
    input [1:0]   KRAMA_BE,
    input         KRAMA_WR,
    input         KRAMA_REQ,
    output        KRAMA_ACK,

    // KRAM bank B memory interface
    input [18:1]  KRAMB_A,
    output [15:0] KRAMB_DI,
    input [15:0]  KRAMB_DO,
    input [1:0]   KRAMB_BE,
    input         KRAMB_WR,
    input         KRAMB_REQ,
    output        KRAMB_ACK,

    // ROM / RAM loader/saver interface
	input [26:0]  LS_ADDR,      // byte address
	input [31:0]  LS_DIN,       // data input from loader
	input         LS_WE_REQ,    // loader requests write
	output        LS_WE_ACK,
	output [31:0] LS_DOUT,      // data output to saver
	input         LS_RD_REQ,    // saver requests read
	output        LS_RD_ACK,

    input         SDRAM_CLK,
    output [26:0] SDRAM_CH1_ADDR,
    input [31:0]  SDRAM_CH1_DOUT,
    output [31:0] SDRAM_CH1_DIN,
    output        SDRAM_CH1_REQ,
    output        SDRAM_CH1_RNW,
    output [3:0]  SDRAM_CH1_BE,
    input         SDRAM_CH1_READY,
    output [26:0] SDRAM_CH2_ADDR,
    input [15:0]  SDRAM_CH2_DOUT,
    output [15:0] SDRAM_CH2_DIN,
    output        SDRAM_CH2_REQ,
    output        SDRAM_CH2_RNW,
    input         SDRAM_CH2_READY,
    output [26:0] SDRAM_CH3_ADDR,
    input [15:0]  SDRAM_CH3_DOUT,
    output [15:0] SDRAM_CH3_DIN,
    output        SDRAM_CH3_REQ,
    output        SDRAM_CH3_RNW,
    input         SDRAM_CH3_READY
   );

`include "memif_sdram_part.svh"

// SDRAM_CLK is assumed to be N * CPU_CLK, where N > 1.

// With SDRAM_CLK = 100MHz and CPU_CLK/CE = 25MHz, ROM reads take 4
// CPU cycles or 2 wait states. Coincidentally, that's the correct
// timing for PC-FX.
// TODO: Verify this

logic           ch1_req, ch1_act;
logic           ch1_ready, ch1_ready_d = '1;

logic [15:0]    rom_do;
logic           rom_start_req;
logic           rom_readyn = '1;

logic [31:0]    ram_do;
logic           ram_start_req;
logic           ram_readyn = '1;

logic [7:0]     sram_do;
logic           sram_start_req;
logic           sram_readyn = '1;

logic [7:0]     bmp_do;
logic           bmp_start_req;
logic           bmp_readyn = '1;

logic           mem_start_req;
logic           mem_pend_req = '0;
logic           mem_req;
logic           mem_act = '0;
logic           mem_we;
logic           mem_rdy;
logic           mem_readyn;

logic           ls_rd_req, ls_we_req, ls_req;
logic           ls_rd_ack_d = '0, ls_we_ack_d = '0;
logic           ls_act = '0;
logic           ls_done;
logic           ls_sel;
logic [2:0]     ls_dwell = '0;
logic           ls_act_dwell;

logic [26:0]    sdram_ch1_addr;
logic [31:0]    sdram_ch1_din;
logic [3:0]     sdram_ch1_be;

assign ls_rd_req = LS_RD_REQ ^ ls_rd_ack_d;
assign ls_we_req = LS_WE_REQ ^ ls_we_ack_d;
assign ls_req = ~mem_act & (ls_rd_req | ls_we_req);
assign ls_done = ls_act & SDRAM_CH1_READY;
assign ls_sel = ls_req | ls_act;
assign ls_act_dwell = ls_act | |ls_dwell;
assign LS_RD_ACK = ls_rd_ack_d ^ ((LS_RD_REQ ^ ls_rd_ack_d) & ls_done);
assign LS_WE_ACK = ls_we_ack_d ^ ((LS_WE_REQ ^ ls_we_ack_d) & ls_done);

assign rom_start_req = ~CPU_BCYSTn & ~ROM_CEn;
assign ram_start_req = ~CPU_BCYSTn & ~RAM_CEn;
assign sram_start_req = ~CPU_BCYSTn & ~SRAM_CEn;
assign bmp_start_req = ~CPU_BCYSTn & ~BMP_CEn;
assign mem_start_req = rom_start_req | ram_start_req | sram_start_req | bmp_start_req;

assign mem_req = ~ls_act_dwell & ~mem_act & (mem_start_req | mem_pend_req) & mem_readyn;
assign mem_readyn = rom_readyn & ram_readyn & sram_readyn & bmp_readyn;

assign ch1_req = mem_req | ls_req;
assign ch1_act = mem_act | ls_act;
assign ch1_ready = (ch1_ready_d & ~(~ch1_act & ch1_req)) | SDRAM_CH1_READY;

always @(posedge SDRAM_CLK) begin
    mem_pend_req <= (mem_pend_req | mem_start_req) & ~(~CPU_RESn | mem_act);
    ch1_ready_d <= ch1_ready;

    if (ls_done) begin
        ls_rd_ack_d <= LS_RD_ACK;
        ls_we_ack_d <= LS_WE_ACK;
    end
end

always @(posedge SDRAM_CLK) begin
    if (~ch1_act & SDRAM_CH1_REQ) begin
        if (ls_req)
            ls_act <= '1;
        else if (mem_req)
            mem_act <= '1;
    end

    if (mem_act & (~CPU_RESn | (ch1_ready & ~mem_readyn)))
        mem_act <= '0;
    if (ls_act & ls_done) begin
        ls_act <= '0;
        ls_dwell <= '1;
    end

    if (|ls_dwell)
        ls_dwell <= ls_dwell - 1'd1;
end

assign mem_rdy = mem_act & ch1_ready;

always @(posedge CPU_CLK) if (CPU_CE) begin
    rom_readyn <= ROM_CEn | ~mem_rdy;
    ram_readyn <= RAM_CEn | ~mem_rdy;
    sram_readyn <= SRAM_CEn | ~mem_rdy;
    bmp_readyn <= BMP_CEn | ~mem_rdy;
end

// SDRAM_CH1_DOUT is in the SDRAM_CLK domain. Latching into the CPU_CLK
// domain helps close timing.
always @(posedge CPU_CLK) if (CPU_CE) begin
    rom_do <= SDRAM_CH1_DOUT[15:0];
    ram_do <= SDRAM_CH1_DOUT[31:0];
    sram_do <= SDRAM_CH1_DOUT[(8 * SRAM_A[0])+:8];
    bmp_do <= SDRAM_CH1_DOUT[(8 * BMP_A[0])+:8];
end

assign LS_DOUT = SDRAM_CH1_DOUT;

assign ROM_DO = rom_do;
assign ROM_READYn = rom_readyn;

assign RAM_DO = ram_do;
assign RAM_READYn = ram_readyn;

assign SRAM_DO = sram_do;
assign SRAM_READYn = sram_readyn;

assign BMP_DO = bmp_do;
assign BMP_READYn = bmp_readyn;

always @* begin
    mem_we = '0;
    sdram_ch1_addr = 'X;
    sdram_ch1_din = 'X;
    sdram_ch1_be = 'X;
    if (ls_sel) begin
        mem_we = ls_we_req;
        sdram_ch1_din = LS_DIN;
        sdram_ch1_be = '1;
        sdram_ch1_addr = LS_ADDR;
    end
    else if (~ROM_CEn) begin
        sdram_ch1_addr = ROM_BASE_A + 27'(ROM_A);
        sdram_ch1_be = '1;
    end
    else if (~RAM_CEn) begin
        mem_we = ~RAM_WEn;
        sdram_ch1_din = RAM_DI;
        sdram_ch1_be = ~RAM_BEn;
        sdram_ch1_addr = RAM_BASE_A + 27'(RAM_A);
    end
    else if (~SRAM_CEn) begin
        mem_we = ~SRAM_WEn;
        sdram_ch1_din = {4{SRAM_DI}};
        sdram_ch1_be = {2'b00, SRAM_A[0], ~SRAM_A[0]};
        sdram_ch1_addr = SRAM_BASE_A + 27'(SRAM_A);
    end
    else if (~BMP_CEn) begin
        mem_we = ~BMP_WEn;
        sdram_ch1_din = {4{BMP_DI}};
        sdram_ch1_be = {2'b00, BMP_A[0], ~BMP_A[0]};
        sdram_ch1_addr = BMP_BASE_A + 27'(BMP_A);
    end
end

assign SDRAM_CH1_ADDR = sdram_ch1_addr;
assign SDRAM_CH1_DIN = sdram_ch1_din;
assign SDRAM_CH1_BE = sdram_ch1_be;
assign SDRAM_CH1_RNW = ~mem_we;
assign SDRAM_CH1_REQ = ch1_ready_d & ch1_req;

//////////////////////////////////////////////////////////////////////

logic           ch2_req;
logic           krama_req_d;
logic           krama_ack;
logic           krama_ack_d = '0;

assign ch2_req = ~krama_req_d & KRAMA_REQ;
assign krama_ack = SDRAM_CH2_READY;

always @(posedge SDRAM_CLK) begin
    krama_req_d <= KRAMA_REQ;
    krama_ack_d <= krama_ack;
end

assign SDRAM_CH2_ADDR = KRAMA_BASE_A + 27'({KRAMA_A, 1'b0});
assign SDRAM_CH2_DIN = KRAMA_DO;
assign SDRAM_CH2_REQ = ch2_req;
assign SDRAM_CH2_RNW = ~KRAMA_WR;
assign KRAMA_DI = SDRAM_CH2_DOUT;
assign KRAMA_ACK = krama_ack | krama_ack_d;  // double for CPU_CLK

//////////////////////////////////////////////////////////////////////

logic           ch3_req;
logic           kramb_req_d;
logic           kramb_ack;
logic           kramb_ack_d = '0;

assign ch3_req = ~kramb_req_d & KRAMB_REQ;
assign kramb_ack = SDRAM_CH3_READY;

always @(posedge SDRAM_CLK) begin
    kramb_req_d <= KRAMB_REQ;
    kramb_ack_d <= kramb_ack;
end

assign SDRAM_CH3_ADDR = KRAMB_BASE_A + 27'({KRAMB_A, 1'b0});
assign SDRAM_CH3_DIN = KRAMB_DO;
assign SDRAM_CH3_REQ = ch3_req;
assign SDRAM_CH3_RNW = ~KRAMB_WR;
assign KRAMB_DI = SDRAM_CH3_DOUT;
assign KRAMB_ACK = kramb_ack | kramb_ack_d;  // double for CPU_CLK

endmodule
