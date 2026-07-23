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
    input         FETCH_BAT,
    input         FETCH_CG,
    input [9:0]   FETCH_BG_ROW,
    input [9:0]   FETCH_BAT_BG_COL,
    input [9:0]   FETCH_CG_BG_COL,

    // Microprogram data store interface
    input         mpd_t MPR,
    input         MPRS,

    // Memory client interface
    output [17:0] M_A,
    input [15:0]  M_DI,
    output [15:0] M_DO,
    output [1:0]  M_BE,
    output        M_WR,
    output        M_REQ,
    input         M_ACK,

    // BAT data (palette bank and character code) input
    input [15:0]  BATD,

    // Fetched data output
    output        MDS,
    output [1:0]  MDL,
    output        MDBnC,
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
rf_bgp_t            mpe_bgp;
logic [17:0]        mpe_ra;
logic               mpe_rs;
logic               mpe_ren;
logic [1:0]         mpe_layer;
logic               mpe_bnc;

assign mpe_d = (rf_bgm.mpsw & FETCH) ? MPR : 9'h100;
always @*
    mpe_bgp = get_bgp(mpe_d.layer);

function [17:0] bg_size_off(input [9:0] row, input [9:0] col);
logic [3:0] xw, yw;
logic [17:0] xoff, yoff;
    xw = mpe_bgp.size_n;
    yw = mpe_bgp.size_m;
    xoff = 18'(col[9:0] & ((1 << xw) - 1));
    yoff = 18'(row[9:0] & ((1 << yw) - 1)) << xw;
    bg_size_off = xoff | yoff;
endfunction

function [16:0] mpe_bataddr(mpd_t mpd);
logic [9:0]  row, col;
logic [17:0] size_off;
    row = FETCH_BG_ROW >> 3;
    col = FETCH_BAT_BG_COL;
    size_off = bg_size_off(row, col);
    mpe_bataddr = '0;
    mpe_bataddr[11:0] = size_off[14:3];
endfunction

function [16:0] mpe_cgaddr(mpd_t mpd);
logic [9:0]  row, col;
logic [2:0]  cgoff;
logic [17:0] size_off;
    row = FETCH_BG_ROW;
    col = FETCH_CG_BG_COL;
    size_off = bg_size_off(row, col);
    cgoff = mpd.cgoff[2:0];
    if (mpd.rotate) begin
        cgoff = '0;
        case (mpe_bgp.format)
            BGF_INT_DOT_4:   ;
            BGF_INT_DOT_16,
            BGF_EXT_BLK_16:  cgoff[0] = col[2];
            BGF_INT_DOT_256,
            BGF_EXT_BLK_256: cgoff[1:0] = col[2:1];
            BGF_INT_DOT_64K,
            BGF_INT_DOT_16M,
            BGF_EXT_BLK_64K,
            BGF_EXT_DOT_16M: cgoff[2:0] = col[2:0];
            default: ;
        endcase
    end
    mpe_cgaddr = '0;
    case (mpe_bgp.format)
        BGF_INT_DOT_256: mpe_cgaddr[16:0] = {size_off[17:3], cgoff[1:0]};
        BGF_INT_DOT_16M: mpe_cgaddr[16:0] = {size_off[16:3], cgoff[2:0]};
        BGF_EXT_BLK_256: mpe_cgaddr[16:0] = {BATD[11:0], row[2:0], cgoff[1:0]};
        default: ;
    endcase
endfunction

function [17:0] mpe_addr(mpd_t mpd);
    mpe_addr = '0;
    mpe_addr[17] = rf_bgm.kpage;
    if (~mpd.nop) begin
        if (mpd.bat) begin
            mpe_addr[16:0] = mpe_bataddr(mpd);
            mpe_addr[16:10] += mpe_bgp.bat[6:0]; // [7] is A/-B
        end
        else begin // CG
            mpe_addr[16:0] = mpe_cgaddr(mpd);
            mpe_addr[16:10] += mpe_bgp.cg[6:0]; // [7] is A/-B
        end
    end
endfunction

assign mpe_ren = |mpe_bgp.prio & ~mpe_d.nop;
assign mpe_layer = mpe_d.layer;
assign mpe_bnc = mpe_d.bat;

always @(posedge CLK) begin
    mpe_rs <= MPRS;
    if (MPRS) begin
        // Silicon probably allocates a full DCK cycle to compute the
        // fetch address -- half of the 2x DCK cycles allocated to
        // complete data fetch.  We need more time to compensate for
        // SDRAM delays, and so we keep compute time to a minimum.
        mpe_ra <= mpe_addr(mpe_d);
    end
end

//////////////////////////////////////////////////////////////////////
// Bank A/B memory client interface

logic               mrcke;
logic               fetch;
logic               mtrg, mtrg2, mreq0, mreq, mack;
logic               mdspp, mdsp, mds;
logic [1:0]         mdlp, mdl;
logic               mdbncp, mdbnc;
logic [17:0]        ma;
logic [15:0]        mdp, md;

assign mrcke = mpe_rs;
assign fetch = mpe_bnc ? FETCH_BAT : FETCH_CG;
assign mtrg = mpe_ren & fetch & mrcke;
assign mreq0 = (~mreq | mack) & (mtrg | mtrg2);
assign mack = M_REQ & M_ACK;
// This strobe aligns with the 2nd DCK after the start of the
// microprogram data (mpe_d) that drove it.
assign mds = DCK & mdsp;

always @(posedge CLK) begin
    if (~RESn) begin
        mtrg2 <= '0;
        ma <= '0;
        mdlp <= '0;
        mdl <= '0;
        mdbncp <= '0;
        mdbnc <= '0;
        mdspp <= '0;
        mdsp <= '0;
        mdp <= '0;
        md <= '0;
        mreq <= '0;
    end
    else begin
        if (mreq0) begin
            mreq <= '1;
            mtrg2 <= '0;
            ma <= mpe_ra;
            mdlp <= mpe_layer;
            mdbncp <= mpe_bnc;
        end
        else if (mreq) begin
            mtrg2 <= mtrg;
        end

        if (mack) begin
            mreq <= mreq0;
            md <= M_DI;
            mdl <= mdlp;
            mdbnc <= mdbncp;
        end
        if (mrcke) begin
            mdspp <= mtrg;
            mdsp <= mdspp;
        end
    end
end

assign M_A = ma;
assign M_BE = '1;
assign M_WR = '0;
assign M_REQ = mreq;

assign MDS = mds;
assign MDL = mdl;
assign MDBnC = mdbnc;
assign MD = md;

endmodule
