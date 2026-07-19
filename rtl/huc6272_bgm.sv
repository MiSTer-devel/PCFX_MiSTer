// HuC6272 (KING) video
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_bgm
   #(parameter LAYER=0)
   (
    input         CLK,
    input         CE,
    input         RESn,

    // Register file
    input         rf_bgm_t rf_bgm,

    // Render control interface
    input         DCK,
    input         FETCH,
    input         RENDER,
    input [9:0]   RENDER_BG_COL,

    input         MDSA,
    input [1:0]   MDLA,
    input [15:0]  MDA,
    input         MDSB,
    input [1:0]   MDLB,
    input [15:0]  MDB,

    output        PDMODE,
    output [23:0] PD,
    output        PDE
    );

wire cgbank = rf_bgm.bgp[LAYER].cg[7];
wire format_clr_256 = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_256) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_256));
wire format_clr_16m = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_16M) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_16M) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_DOT_16M));

logic               mds;
logic [1:0]         mdl;
logic [15:0]        md;

assign mds = cgbank ? MDSB : MDSA;
assign mdl = cgbank ? MDLB : MDLA;
assign md = cgbank ? MDB : MDA;

logic               cgfce;
logic [15:0]        cgrd_in;
logic [31:0]        cgrd;
logic               cgra;
logic               cgpdm, cgpdmo;
logic [23:0]        cgpd, cgpdo; // {Y,U,V}
logic               cgpdeo;

wire cgrce = DCK;

assign cgfce = mds & (mdl == LAYER);

always @(posedge CLK) begin
    if (~RESn) begin
        cgra <= '0;
        cgrd <= '0;
        cgrd_in <= '0;
    end
    else if (cgfce) begin
        cgra <= ~cgra;
        cgrd_in <= md;
        if (format_clr_16m) begin
            if (cgra)
                cgrd <= {cgrd_in, md};
        end
        else
            cgrd <= {16'b0, cgrd_in};
    end
    else if (~(FETCH | RENDER)) begin
        cgra <= '0;
    end
end

// Use U/V=128, because yuv2rgb converts all zeros to green.
localparam [23:0] PD_BLACK = {8'd0, 8'd128, 8'd128};

assign cgpdm = format_clr_16m; // 0=palette, 1=YUV

always @* begin
    cgpd = cgpdm ? PD_BLACK : '0;
    if (RENDER) begin
        if (format_clr_256) begin
            cgpd[0+:8] = ~RENDER_BG_COL[0] ? cgrd[8+:8] : cgrd[0+:8];
        end
        if (format_clr_16m) begin
            // 16M CG is ordered in KRAM as {Y0,Y1,U,V}.
            cgpd[16+:8] = ~RENDER_BG_COL[0] ? cgrd[24+:8] : cgrd[16+:8];
            cgpd[0+:16] = cgrd[0+:16];
        end
    end
end

always @(posedge CLK) begin
    if (~RESn) begin
        cgpdmo <= '1;
        cgpdo <= PD_BLACK;
        cgpdeo <= '0;
    end
    else if (cgrce) begin
        cgpdmo <= cgpdm;
        cgpdo <= cgpd;
        cgpdeo <= RENDER;
    end
end

assign PDMODE = cgpdmo;
assign PD = cgpdo;
assign PDE = cgpdeo;

endmodule
