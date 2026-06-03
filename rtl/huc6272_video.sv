// HuC6272 (KING) video
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_video
   (
    input         CLK,
    input         CE,
    input         RESn,

    // Register file
    input         rf_bgm_t rf_bgm,

    // Video status
    output [9:0]  ROW,
    output [9:0]  COL,

    // Bank A memory client interface
    output [17:0] MA_A,
    input [15:0]  MA_DI,
    output [15:0] MA_DO,
    output [1:0]  MA_BE,
    output        MA_WR,
    output        MA_REQ,
    input         MA_ACK,

    // Bank B memory client interface
    output [17:0] MB_A,
    input [15:0]  MB_DI,
    output [15:0] MB_DO,
    output [1:0]  MB_BE,
    output        MB_WR,
    output        MB_REQ,
    input         MB_ACK,

    // Video interface
    input         DCK, // pixel clock enable
    input         DCK_NEGEDGE,
    input         HSYNC_POSEDGE,
    input         HSYNC_NEGEDGE,
    input         VSYNC_POSEDGE,
    input         VSYNC_NEGEDGE,
    output [23:0] VD, // [7:0] = palette data / [23:0] = {Y,U,V}
    output        VDE
    );

logic [9:0]         row, col;

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
// Video counter

logic               vsync_l;

always @(posedge CLK) begin
    if (~RESn) begin
        row <= '0;
        col <= '0;
        vsync_l <= '0;
    end
    else if (DCK) begin
        col <= col + 1'd1;
        if (HSYNC_NEGEDGE) begin
            col <= '0;
            row <= row + 1'd1;
            if (vsync_l) begin
                row <= '0;
                vsync_l <= '0;
            end
        end
        if (VSYNC_NEGEDGE)
            vsync_l <= '1;
    end
end

assign ROW = row;
assign COL = col;

//////////////////////////////////////////////////////////////////////
// Active fetch / render windows

localparam [9:0] FETCH_ROW_START = 10'd21;
localparam [9:0] FETCH_ROW_END = FETCH_ROW_START + 10'd240 - 10'd1;
localparam [9:0] FETCH_COL_START = 10'd60;
localparam [9:0] FETCH_COL_END = FETCH_COL_START + 10'd256 - 10'd1;

wire fetch_row = (row >= FETCH_ROW_START) & (row <= FETCH_ROW_END);
wire fetch_col = (col >= FETCH_COL_START) & (col <= FETCH_COL_END);
wire fetch = fetch_row & fetch_col;

wire [9:0] fetch_bg_row = row - FETCH_ROW_START;
wire [9:0] fetch_bg_col = col - FETCH_COL_START;

localparam [9:0] RENDER_ROW_START = FETCH_ROW_START;
localparam [9:0] RENDER_ROW_END = FETCH_ROW_END;
localparam [9:0] RENDER_COL_START = FETCH_COL_START + 10'd3;
localparam [9:0] RENDER_COL_END = FETCH_COL_END + 10'd3;

wire render_row = (row >= RENDER_ROW_START) & (row <= RENDER_ROW_END);
wire render_col = (col >= RENDER_COL_START) & (col <= RENDER_COL_END);
wire render = render_row & render_col;

wire [9:0] render_bg_row = row - RENDER_ROW_START;
wire [9:0] render_bg_col = col - RENDER_COL_START;

//////////////////////////////////////////////////////////////////////
// Microprogram data store

mpd_t               mpd [2][8];
mpd_t               mprbufa, mprbufb;
logic [2:0]         mpra;

assign mpra = fetch ? fetch_bg_col[2:0] : '0;

always @(posedge CLK) begin
    if (rf_bgm.mpsw) begin
        mprbufa <= mpd[0][mpra];
        mprbufb <= mpd[1][mpra];
    end
    else if (rf_bgm.mpwr)
        mpd[rf_bgm.mpwa[3]][rf_bgm.mpwa[2:0]] <= rf_bgm.mpwd;
end

//////////////////////////////////////////////////////////////////////
// Bank A/B microprogram engine and memory client interfaces

logic               mdsa, mdsb;
logic [1:0]         mdla, mdlb;
logic [15:0]        mda, mdb;

huc6272_fetch vfea
   (
    .CLK(CLK),
    .CE(CE),
    .RESn(RESn),

    .rf_bgm(rf_bgm),

    .DCK(DCK),
    .FETCH(fetch),
    .FETCH_BG_ROW(fetch_bg_row),
    .FETCH_BG_COL(fetch_bg_col),

    .MPRBUF(mprbufa),

    .M_A(MA_A),
    .M_DI(MA_DI),
    .M_DO(MA_DO),
    .M_BE(MA_BE),
    .M_WR(MA_WR),
    .M_REQ(MA_REQ),
    .M_ACK(MA_ACK),

    .MDS(mdsa),
    .MDL(mdla),
    .MD(mda)
    );

huc6272_fetch vfeb
   (
    .CLK(CLK),
    .CE(CE),
    .RESn(RESn),

    .rf_bgm(rf_bgm),

    .DCK(DCK),
    .FETCH(fetch),
    .FETCH_BG_ROW(fetch_bg_row),
    .FETCH_BG_COL(fetch_bg_col),

    .MPRBUF(mprbufb),

    .M_A(MB_A),
    .M_DI(MB_DI),
    .M_DO(MB_DO),
    .M_BE(MB_BE),
    .M_WR(MB_WR),
    .M_REQ(MB_REQ),
    .M_ACK(MB_ACK),

    .MDS(mdsb),
    .MDL(mdlb),
    .MD(mdb)
    );

//////////////////////////////////////////////////////////////////////
// BG pipelines

logic [23:0]        bg0_pd;
logic               bg0_pde;

huc6272_bgm #(0) bg0
   (
    .CLK(CLK),
    .CE(CE),
    .RESn(RESn),

    .rf_bgm(rf_bgm),

    .DCK(DCK),
    .FETCH(fetch),
    .RENDER(render),
    .RENDER_BG_COL(render_bg_col),

    .MDSA(mdsa),
    .MDLA(mdla),
    .MDA(mda),
    .MDSB(mdsb),
    .MDLB(mdlb),
    .MDB(mdb),

    .PD(bg0_pd),
    .PDE(bg0_pde)
    );

//////////////////////////////////////////////////////////////////////
// Final video output

assign VD = bg0_pd;
assign VDE = bg0_pde;

endmodule
