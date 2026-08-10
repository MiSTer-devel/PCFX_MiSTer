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
    input [9:0]   FETCH_BAT_BG0_ROT_ROW,
    input [9:0]   FETCH_BAT_BG0_ROT_COL,

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
    output [2:0]  MDCC,
    output [15:0] MD
    );

mpd_t               mpe_d;

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
// Screen address generator

logic [9:0]         sag_row, sag_col;
logic [9:0]         sag_bat_bg0_rot_row_d, sag_bat_bg0_rot_col_d;
logic [9:0]         sag_cg_bg0_rot_row, sag_cg_bg0_rot_col;

always @(posedge CLK) begin
    if (~RESn) begin
        sag_bat_bg0_rot_row_d <= '0;
        sag_bat_bg0_rot_col_d <= '0;
        sag_cg_bg0_rot_row <= '0;
        sag_cg_bg0_rot_col <= '0;
    end
    else if (DCK) begin
        sag_bat_bg0_rot_row_d <= FETCH_BAT_BG0_ROT_ROW;
        sag_bat_bg0_rot_col_d <= FETCH_BAT_BG0_ROT_COL;
        sag_cg_bg0_rot_row <= sag_bat_bg0_rot_row_d;
        sag_cg_bg0_rot_col <= sag_bat_bg0_rot_col_d;
    end    
end

always @* begin
    sag_row = FETCH_BG_ROW;
    sag_col = mpe_d.bat ? FETCH_BAT_BG_COL : FETCH_CG_BG_COL;
    if (mpe_d.rotate) begin
        sag_row = mpe_d.bat ? FETCH_BAT_BG0_ROT_ROW : sag_cg_bg0_rot_row;
        sag_col = mpe_d.bat ? FETCH_BAT_BG0_ROT_COL : sag_cg_bg0_rot_col;
    end
end

//////////////////////////////////////////////////////////////////////
// Microprogram engine

rf_bgp_t            mpe_bgp;
logic [17:0]        mpe_ra;
logic               mpe_rs;
logic               mpe_ren;
logic [1:0]         mpe_layer;
logic               mpe_bnc;
logic [2:0]         mpe_cgcol;

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
    row = sag_row >> 3;
    col = sag_col;
    size_off = bg_size_off(row, col);
    mpe_bataddr = '0;
    mpe_bataddr[11:0] = size_off[14:3];
endfunction

function [16:0] mpe_cgaddr(mpd_t mpd);
logic [9:0]  row, col;
logic [2:0]  cgoff;
logic [17:0] size_off;
    row = sag_row;
    col = sag_col;
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
    if (DCK) begin
        // Silicon probably allocates a full DCK cycle to compute the
        // fetch address -- half of the 2x DCK cycles allocated to
        // complete data fetch.
        mpe_ra <= mpe_addr(mpe_d);
        mpe_cgcol <= sag_col[2:0];
    end
end

//////////////////////////////////////////////////////////////////////
// Bank A/B memory client interface

logic               fetch;
logic               mtrg, mreq;
logic               mds;
logic [1:0]         mdl;
logic               mdbnc;

assign fetch = mpe_bnc ? FETCH_BAT : FETCH_CG;
assign mtrg = DCK & mpe_ren & fetch;
// This strobe aligns with the DCK after the fetch started.
// Note we ignore M_ACK, in case it's late.
assign mds = DCK & mreq;

always @(posedge CLK) begin
    if (~RESn) begin
        mreq <= '0;
    end
    else begin
        if (DCK) begin
            mreq <= mtrg;
            mdl <= mpe_layer;
            mdbnc <= mpe_bnc;
            if (mreq)
                assert(M_ACK) else $error("late M_ACK");
        end
    end
end

assign M_A = mpe_ra;
assign M_BE = '1;
assign M_WR = '0;
assign M_REQ = mreq;

assign MDS = mds;
assign MDL = mdl;
assign MDBnC = mdbnc;
assign MDCC = mpe_cgcol;
assign MD = M_DI;

endmodule
