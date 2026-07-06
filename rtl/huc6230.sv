// HuC6230 (SOUNDBOX)
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - https://github.com/MiSTer-devel/TurboGrafx16_MiSTer/blob/master/rtl/HUC6280/psg.vhd
// - PC-FXGA Authoring Software / GMAKER Starter Kit Plus (Ver. 1.0) / Device Description: HuC6230

module huc6230
   (
    input         CLK,
    input         CE,
    input         RESn,

    // CPU memory / I/O bus interface
    input         A2,
    input [15:0]  DI,
    input         CSn,
    input         WRn,

    // K-BUS interface
    input [7:0]   KBUS_DI,
    input         KBUS_RHnL,
    input [1:0]   KBUS_CSn,

    // Video timing sync. interface
    input         DCK, // pixel clock enable
    input         HSYNC_NEGEDGE,

    // Audio interface
    output [15:0] SLOUT, // left channel
    output [15:0] SROUT // right channel
    );

//////////////////////////////////////////////////////////////////////
// I/O bus interface
//
// TODO

//////////////////////////////////////////////////////////////////////
// ADPCM sample clock generator

// Assumes CLK = 2 * 21.48 MHz
localparam [11:0] PCM_CLOCKS = 12'(2730 / 2); // 31.75 kHz

logic [11:0]    p_cnt;
logic           pck;
logic [1:0]     adp_cnt;
logic           adpck;

wire p_wrap = p_cnt == (PCM_CLOCKS - 1'd1);

always @(posedge CLK)
    p_cnt <= (~RESn | pck) ? '0 : p_cnt + 1'd1;

assign pck = (DCK & HSYNC_NEGEDGE) | p_wrap;

// adpck = pck / 2^DIV
localparam div = 2'b00; // TODO
wire adp_wrap = adp_cnt == 2'((1 << div) - 1);

always @(posedge CLK) begin
    if (~RESn)
        adp_cnt <= '0;
    else if (pck)
        adp_cnt <= adp_wrap ? '0 : adp_cnt + 1'd1;
end

assign adpck = pck & adp_wrap;

//////////////////////////////////////////////////////////////////////
// ADPCM decoders

logic [15:0]    adpcm1_sout, adpcm2_sout;

wire adpcm1_csn = KBUS_CSn[0] | ~KBUS_CSn[1];
wire adpcm2_csn = KBUS_CSn[1] | ~KBUS_CSn[0];

huc6230_adpcm adpcm1
   (
    .CLK(CLK),
    .RESn(RESn),

    .KBUS_DI(KBUS_DI),
    .KBUS_RHnL(KBUS_RHnL),
    .KBUS_CSn(adpcm1_csn),

    .DCK(DCK),
    .HSYNC_NEGEDGE(HSYNC_NEGEDGE),

    .SCK(adpck),
    .SOUT(adpcm1_sout)
    );

huc6230_adpcm adpcm2
   (
    .CLK(CLK),
    .RESn(RESn),

    .KBUS_DI(KBUS_DI),
    .KBUS_RHnL(KBUS_RHnL),
    .KBUS_CSn(adpcm2_csn),

    .DCK(DCK),
    .HSYNC_NEGEDGE(HSYNC_NEGEDGE),

    .SCK(adpck),
    .SOUT(adpcm2_sout)
    );

//////////////////////////////////////////////////////////////////////
// Output mixer
//
// TODO

assign SLOUT = adpcm1_sout;
assign SROUT = adpcm2_sout;

endmodule

`include "huc6230_adpcm.sv"
