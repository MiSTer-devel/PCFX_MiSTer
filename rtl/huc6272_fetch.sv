// HuC6272 (KING) video fetch engine, one bank
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_fetch
   (
    input         CLK,
    input         CE,
    input         RESn,

    // Register file
    input         rf_bgm_t rf_bgm,

    // Render control interface
    input         DCK, // pixel clock enable
    input         FETCH,
    input [9:0]   FETCH_BG_ROW,
    input [9:0]   FETCH_BG_COL,

    // Microprogram data store interface
    input         mpd_t MPRBUF,

    // Memory client interface
    output [17:0] M_A,
    input [15:0]  M_DI,
    output [15:0] M_DO,
    output [1:0]  M_BE,
    output        M_WR,
    output        M_REQ,
    input         M_ACK,

    // Fetched CG data
    output        MDS,
    output [1:0]  MDL,
    output [15:0] MD
    );

function rf_bgp_t get_bgp(input [1:0] layer);
    case (layer)
        2'd0: get_bgp = rf_bgm.bgp[0];
        2'd1: get_bgp = rf_bgm.bgp[1];
        2'd2: get_bgp = rf_bgm.bgp[2];
        2'd3: get_bgp = rf_bgm.bgp[3];
        default: get_bgp = 'X;
    endcase
endfunction

//////////////////////////////////////////////////////////////////////
// Microprogram engine

mpd_t               mpe_d;
logic [17:0]        mpe_ra;
logic               mpe_ren;
logic [1:0]         mpe_layer;

assign mpe_d = (rf_bgm.mpsw & FETCH) ? MPRBUF : 9'h100;

function mpe_rd_en(mpd_t mpd);
rf_bgp_t bgp;
    bgp = get_bgp(mpd.layer);
    mpe_rd_en = |bgp.prio & ~mpd.nop;
endfunction

function [17:3] bg_size_off(rf_bgp_t bgp);
logic [3:0] xw, yw;
logic [17:3] xoff, yoff;
    xw = bgp.size_n - 4'd3;
    yw = bgp.size_m;
    xoff = 15'(FETCH_BG_COL[9:3] & ((1 << xw) - 1));
    yoff = 15'(FETCH_BG_ROW[9:0] & ((1 << yw) - 1)) << xw;
    bg_size_off = xoff | yoff;
endfunction

function [17:0] mpe_addr(mpd_t mpd);
logic [17:3] size_off;
rf_bgp_t bgp;
    bgp = get_bgp(mpd.layer);
    mpe_addr = '0;
    size_off = bg_size_off(bgp);
    // TODO: mpe_addr[17] = REG.0F[4];
    if (~mpd.nop) begin
        mpe_addr[16:10] = mpd.bat ? bgp.bat[6:0] : bgp.cg[6:0]; // [7] is A/-B
        if (mpd.bat)
            ; // TODO
        else begin // CG
            mpe_addr[17:3] += size_off;
            mpe_addr[2:0] = mpd.cgoff;
        end
    end
endfunction

always @(posedge CLK) begin
    mpe_ren <= mpe_rd_en(mpe_d);
    mpe_layer <= mpe_d.layer;
    mpe_ra <= mpe_addr(mpe_d);
end

//////////////////////////////////////////////////////////////////////
// Bank A/B memory client interface

logic               mtrg, mtrg2, mreq0, mreq, mack;
logic [1:0]         mdl;
logic [17:0]        ma;
logic [15:0]        md;

assign mtrg = mpe_ren & FETCH & DCK;
assign mreq0 = (~mreq | mack) & (mtrg | mtrg2);
assign mack = M_REQ & M_ACK;

always @(posedge CLK) begin
    if (~RESn) begin
        mtrg2 <= '0;
        ma <= '0;
        mdl <= '0;
        md <= '0;
        mreq <= '0;
    end
    else begin
        if (mreq0) begin
            mreq <= '1;
            mtrg2 <= '0;
            ma <= mpe_ra;
            mdl <= mpe_layer;
        end
        else if (mreq) begin
            mtrg2 <= mtrg;
        end

        if (mack) begin
            md <= M_DI;
            mreq <= mreq0;
        end
    end
end

assign M_A = ma;
assign M_BE = '1;
assign M_WR = '0;
assign M_REQ = mreq;

assign MDS = mack;
assign MDL = mdl;
assign MD = md;

endmodule
