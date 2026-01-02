// PC-FX Gate Array -- KPC: K-Port (Keypad) Control Unit
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - https://github.com/pcfx-devel/PC-FX_Info.git/blob/master/FX_Controllers/README.md

// TODO:
// - Multi-tap

module fx_ga_kpc
   (
    input         RESn,
    input         CLK,
    input         CE,
    
    // Register interface
    input         A6,
    input         A1,
    input         CSn,
    input         RDn,
    input         WRn,
    input [15:0]  DI,
    output [15:0] DO,

    // Interrupt
    output        INT,

    // K-port interface
    output reg    KP_LATCH,
    output reg    KP_CLK,
    output        KP_RW,
    input         KP_DIN,
    output reg    KP_DOUT
    );

logic           trg, trg_set, trg_reset;
logic           mod;
logic           ios;
logic           kend, kend_set, kend_reset, kend_p;
logic [31:0]    data_sr;
logic           data_rd;
logic           data_in, data_in_latched;

//////////////////////////////////////////////////////////////////////

logic [3:0]     ccnt;
logic           tick;
logic [7:0]     cycle, cyclep1;
logic           cycle0;
logic           go;
logic           done;
logic           run;
logic           busy;
logic           port_latch;
logic           xfer;
logic           data_latch;
logic           shift;
logic           clkout;

always @(posedge CLK) if (CE) begin
    if (~RESn)
        ccnt <= '0;
    else
        ccnt <= ccnt + 1'd1;
end

assign tick = &ccnt;
assign cycle0 = cycle == 8'd0;
assign cyclep1 = cycle + 1'd1;
assign go = cycle0 & trg & ~busy;
assign done = (cycle == 8'd131);
assign run = (~cycle0 | (go | busy)) & ~done;

assign port_latch = run & (cycle <= 8'd3);
assign xfer = (cycle >= 8'd5);
assign data_latch = xfer & (cycle[1:0] == 2'b01);
assign shift = xfer & (cycle[1:0] == 2'b11);
assign clkout = xfer & cyclep1[1];

assign data_in = ~(ios ? KP_DIN : KP_DOUT);

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        cycle <= '0;
        busy <= '0;
        KP_LATCH <= '1;
        KP_CLK <= '1;
        data_in_latched <= '0;
    end
    else if (tick) begin
        if (run)
            cycle <= cyclep1;
        else
            cycle <= 8'd0;

        busy <= run;
        KP_LATCH <= ~port_latch;
        KP_CLK <= ~clkout;

        if (data_latch)
            data_in_latched <= data_in;
    end
end

assign trg_reset = tick & done;
assign KP_DOUT = ~(~ios & (xfer & ~done) & data_sr[0]);
assign KP_RW = ~ios;

assign kend_set = trg_reset;
assign kend_reset = data_rd;
assign kend_p = (kend | kend_set) & ~kend_reset;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        trg <= '0;
        kend <= '0;
    end
    else begin
        trg <= (trg | trg_set) & ~trg_reset;
        kend <= kend_p;
    end
end

assign INT = kend_p;

//////////////////////////////////////////////////////////////////////

logic [15:0]    dout;

always @(posedge CLK) if (CE) begin
    trg_set <= '0;

    if (~RESn) begin
        mod <= '1;
        ios <= '1;
        data_sr <= '0;
    end
    else begin
        if (~CSn & ~WRn) begin
            case ({A6, A1})
                2'b00: {ios, mod, trg_set} <= DI[2:0];
                2'b10: data_sr[15:0] <= DI;
                2'b11: data_sr[31:16] <= DI;
                default: ;
            endcase
        end

        if (shift & tick)
            data_sr <= {data_in_latched, data_sr[31:1]};
    end
end

always @* begin
    data_rd = '0;

    if (~CSn & ~RDn) begin
        case ({A6, A1})
            2'b10: data_rd = '1;
            default: ;
        endcase
    end
end

always @* begin
    dout = '0;
    if (~CSn & ~RDn) begin
        case ({A6, A1})
            2'b00: dout[3:0] = {kend, ios, mod, trg};
            2'b10: dout = data_sr[15:0];
            2'b11: dout = data_sr[31:16];
            default: ;
        endcase
    end
end

assign DO = dout;

endmodule
