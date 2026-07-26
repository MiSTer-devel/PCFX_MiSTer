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
    input [5:1]   A,
    input [7:0]   DI,
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

typedef struct packed {
    logic [2:1]    sres;
    logic [2:1]    interp;
    logic [1:0]    div;
} adp_cr_t;

logic               hsync_negedge, hsync_negedge_d;

adp_cr_t            adp_cr, adp_cr_next;

//////////////////////////////////////////////////////////////////////
// I/O bus / Register interface

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        adp_cr_next <= '0;
    end
    else begin
        if (~CSn & ~WRn) begin
            case (A)
                5'h10: adp_cr_next <= DI[5:0];
                default: ;
            endcase
        end
    end
end

always @(posedge CLK) begin
    if (~RESn) begin
        adp_cr <= '0;
    end
    else if (hsync_negedge) begin
        // This register becomes effective on -HSYNC.
        adp_cr <= adp_cr_next;
    end
end

//////////////////////////////////////////////////////////////////////
// ADPCM sample clock generator

// Assumes CLK = 2 * 21.48 MHz
localparam [11:0] PCM_CLOCKS = 12'(2730 / 2); // 31.75 kHz

logic           res_hsync;
logic [11:0]    p_cnt;
logic           pck;
logic [3:0]     adp_cnt;
logic           adpck, adpck_div2;

assign hsync_negedge = DCK & HSYNC_NEGEDGE;

wire p_wrap = p_cnt == (PCM_CLOCKS - 1'd1);

always @(posedge CLK) begin
    hsync_negedge_d <= hsync_negedge;
    res_hsync <= (res_hsync & ~hsync_negedge_d) | ~RESn;
    p_cnt <= (res_hsync | pck) ? '0 : p_cnt + 1'd1;
    pck <= hsync_negedge | p_wrap;
end

always @(posedge CLK) begin
    if (res_hsync)
        adp_cnt <= '0;
    else if (pck)
        adp_cnt <= adp_cnt + 1'd1;
end

// adpck = pck / 2^DIV
wire [3:0] adp_mask = 4'((2 << adp_cr.div) - 1);
assign adpck = pck & ({adp_cnt[2:0], 1'b1} & adp_mask) == adp_mask;

// adpck_div2 = adpck / 2
assign adpck_div2 = pck & (adp_cnt & adp_mask) == adp_mask;

//////////////////////////////////////////////////////////////////////
// ADPCM decoders

logic [15:0]    adpcm1_sout, adpcm2_sout;

wire adpcm1_csn = KBUS_CSn[0] | ~KBUS_CSn[1];
wire adpcm2_csn = KBUS_CSn[1] | ~KBUS_CSn[0];

huc6230_adpcm adpcm1
   (
    .CLK(CLK),
    .RESn(RESn),

    .SRES(adp_cr.sres[1]),
    .INTERP(adp_cr.interp[1]),
    .DIV(adp_cr.div),

    .KBUS_DI(KBUS_DI),
    .KBUS_RHnL(KBUS_RHnL),
    .KBUS_CSn(adpcm1_csn),

    .SCK_ADPCM_DIV2(adpck_div2),
    .SCK_ADPCM(adpck),
    .SCK_PCM(pck),
    .SOUT(adpcm1_sout)
    );

huc6230_adpcm adpcm2
   (
    .CLK(CLK),
    .RESn(RESn),

    .SRES(adp_cr.sres[2]),
    .INTERP(adp_cr.interp[2]),
    .DIV(adp_cr.div),

    .KBUS_DI(KBUS_DI),
    .KBUS_RHnL(KBUS_RHnL),
    .KBUS_CSn(adpcm2_csn),

    .SCK_ADPCM_DIV2(adpck_div2),
    .SCK_ADPCM(adpck),
    .SCK_PCM(pck),
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
