// HuC6272 (KING) BG0 rotated screen address generator
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_rsag
   (
    input        CLK,
    input        RESn,

    // Register file
    input        rf_bgm_t rf_bgm,

    // Render control interface
    input        DCK,
    input [9:0]  FETCH_BG_ROW,
    input [9:0]  FETCH_RSAG_BG0_COL,

    // BG0 rotated screen address
    output [9:0] ROW,
    output [9:0] COL
    );

// Affine transform algorithm:
//
// |x1| = |a b| |x2-x0| + |x0|
// |y1|   |c d| |y2-y0|   |y0|
//
// The matrix product is |p11; p21|, where:
//   p11 = a(x2-x0) + b(y2-y0)
//   p21 = c(x2-x0) + d(y2-y0)

logic signed [15:0] x0, y0, x1, y1, x2, y2;
logic signed [15:0] a, b, c, d;
logic signed [15:0] x2m0, y2m0;
logic signed [23:0] mac;
logic [9:0]         row, col;
logic [2:0]         phase;

always @* begin
    x0 = rf_bgm.bg0at.x0;
    y0 = rf_bgm.bg0at.y0;

    a = rf_bgm.bg0at.a;
    b = rf_bgm.bg0at.b;
    c = rf_bgm.bg0at.c;
    d = rf_bgm.bg0at.d;

    x2 = $signed(16'(FETCH_RSAG_BG0_COL));
    y2 = $signed(16'(FETCH_BG_ROW));
end

always @(posedge CLK) begin
    if (~RESn) begin
        x2m0 <= '0;
        y2m0 <= '0;
        mac <= '0;
        row <= '0;
        col <= '0;
        phase <= '0;
    end
    else begin
        if (DCK) begin
            row <= y1[9:0];
            col <= x1[9:0];

            x2m0 <= x2 - x0;
            y2m0 <= y2 - y0;
            phase <= 3'd1;
        end
        else begin
            phase <= phase + 1'd1;
            case (phase)
                3'd1:
                    mac <= a * $size(mac)'(x2m0);
                3'd2:
                    mac <= mac + b * $size(mac)'(y2m0);
                3'd3: begin
                    // mac = p11
                    x1 <= 16'(mac >>> 8) + x0;
                    mac <= c * $size(mac)'(x2m0);
                end
                3'd4:
                    mac <= mac + d * $size(mac)'(y2m0);
                3'd5: begin
                    // mac = p21
                    y1 <= 16'(mac >>> 8) + y0;
                    phase <= '0;
                end
                default:
                    phase <= '0;
            endcase
        end
    end
end

assign ROW = row;
assign COL = col;

endmodule
