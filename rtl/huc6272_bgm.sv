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
    input         HSYNC_NEGEDGE,
    input         FETCH,
    input         RENDER,
    input [9:0]   RENDER_BG_COL,

    input         MDSA,
    input [1:0]   MDLA,
    input [2:0]   MDCCA,
    input [15:0]  MDA,
    input         MDSB,
    input [1:0]   MDLB,
    input [2:0]   MDCCB,
    input [15:0]  MDB,

    output        PDMODE,
    output [23:0] PD,
    output        PDE
    );

wire rotate = rf_bgm.rsw & (LAYER == 0);

wire cgbank = rf_bgm.bgp[LAYER].cg[7];

wire format_clr_4   = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_4) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_4));
wire format_clr_16  = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_16) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_16));
wire format_clr_256 = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_256) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_256));
wire format_clr_64k = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_64K) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_64K) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_DOT_64K));
wire format_clr_16m = ((rf_bgm.bgp[LAYER].format == BGF_INT_DOT_16M) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_BLK_16M) |
                       (rf_bgm.bgp[LAYER].format == BGF_EXT_DOT_16M));

logic               mds;
logic [1:0]         mdl;
logic [2:0]         mdcc;
logic [15:0]        md;

assign mds = cgbank ? MDSB : MDSA;
assign mdl = cgbank ? MDLB : MDLA;
assign mdcc = cgbank ? MDCCB : MDCCA;
assign md = cgbank ? MDB : MDA;

logic               cgfce;
logic [2:0]         pdwa, pdra;
logic [18:0]        pdrout;
logic [2:0]         pdcc;
logic [18:0]        cgrd_in;
logic [2:0]         cgcol, cgccnt, cgcc;
logic [31:0]        cgrd;
logic               cgra;
logic               render_d, render_dd;
logic               cgpdm, cgpdmo;
logic [23:0]        cgpd, cgpdo; // {Y,U,V}
logic               cgpdeo;

wire cgrce = DCK;

assign cgfce = mds & (mdl == LAYER);

// Pixel data buffer
// Up to 8x 16-bit words arrive every 8x pixel clocks.
// To align BG layers, all 8 pixels are buffered.
// For rotated BG0, words arrive every pixel clock.
// CG column (valid for rotated) is paired with the pixel data.
//
dpram #(.addr_width(3), .data_width(19)) pdram
   (
    .clock(CLK),
    .address_a(pdwa),
    .data_a({mdcc, md}),
    .enable_a(1'b1),
    .wren_a(cgfce),
    .q_a(),
    .cs_a(1'b1),

    .address_b(pdra),
    .data_b('0),
    .enable_b(1'b1),
    .wren_b('0),
    .q_b(pdrout),
    .cs_b(1'b1)
    );

always @(posedge CLK) begin
    if (~RESn | HSYNC_NEGEDGE) begin
        pdwa <= '0;
        pdra <= '0;
        pdcc <= '0;
    end
    else begin
        if (cgfce) begin
            pdwa <= pdwa + 1'd1;
        end
        if (RENDER & cgrce) begin
            if ((format_clr_4   & &pdcc[2:0]) |
                (format_clr_16  & &pdcc[1:0]) |
                (format_clr_256 & &pdcc[0:0]) |
                (format_clr_64k | format_clr_16m) |
                rotate)
                pdra <= pdra + 1'd1;
            pdcc <= pdcc + 1'd1;
        end
    end
end

always @(posedge CLK) begin
    if (~RESn | HSYNC_NEGEDGE) begin
        render_d <= '0;
        cgrd_in <= '0;
        cgrd <= '0;
    end
    else if (cgrce) begin
        render_d <= RENDER;
        cgrd_in <= pdrout;
        if (render_d) begin
            if (format_clr_16m) begin
                // Each 16M YUV pixel spans two 16-bit words
                if (cgra)
                    cgrd <= {cgrd_in[15:0], pdrout[15:0]};
            end
            else begin
                cgrd <= {16'b0, cgrd_in[15:0]};
                // CG column is split out here
                cgcol <= cgrd_in[18:16];
            end
        end
    end
end

assign cgra = pdcc[0];

// Use U/V=128, because yuv2rgb converts all zeros to green.
localparam [23:0] PD_BLACK = {8'd0, 8'd128, 8'd128};

assign cgpdm = format_clr_16m; // 0=palette, 1=YUV

always @(posedge CLK) begin
    if (~RESn | HSYNC_NEGEDGE) begin
        render_dd <= '0;
        cgccnt <= '0;
    end
    else if (cgrce) begin
        render_dd <= render_d;
        if (render_dd)
            cgccnt <= cgccnt + 1'd1;
    end
end

assign cgcc = rotate ? cgcol : cgccnt;

always @* begin
    cgpd = cgpdm ? PD_BLACK : '0;
    if (render_dd) begin
        if (format_clr_256) begin
            cgpd[0+:8] = ~cgcc[0] ? cgrd[8+:8] : cgrd[0+:8];
        end
        if (format_clr_16m) begin
            // 16M CG is ordered in KRAM as {Y0,Y1,U,V}.
            cgpd[16+:8] = ~cgcc[0] ? cgrd[24+:8] : cgrd[16+:8];
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
        cgpdeo <= render_dd;
    end
end

assign PDMODE = cgpdmo;
assign PD = cgpdo;
assign PDE = cgpdeo;

endmodule
