// Alliance AS4C32M16SB - 512Mbit (4x8Mx16) SDRAM
//
// Copyright (c) 2025 David Hunter
//
// Portions copied from sdram.v:
//   sdram controller implementation
//   Copyright (c) 2018 Sorgelig
//
// This program is GPL licensed. See COPYING for the full license.

// TODO:
// - Enforce refresh cycle timing
// - Enforce DQ contention avoidance timing
// - Command interrupt

module as4c32m16sb
    #(parameter CLK_MHZ = 142.8571428)
    (
	 inout [15:0] DQ, // 16 bit bidirectional data bus
	 input [12:0] A, // 13 bit multiplexed address bus
	 input        DQML, // byte mask
	 input        DQMH, // byte mask
	 input [1:0]  BA, // two banks
	 input        nCS, // a single chip select
	 input        nWE, // write enable
	 input        nRAS, // row address select
	 input        nCAS, // columns address select
	 input        CLK,
	 input        CKE
     );

localparam CMD_NOP             = 3'b111;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

// All times in ns are for -7: tCK3 (clk cycle) = 7 ns (143 MHz)
// Parameters are in whole cycles, and assume clk cycle = 1 / CLK_MHZ
function int ns_to_cyc(int ns);
    ns_to_cyc = int'($ceil(CLK_MHZ * ns / 1000.0));
endfunction

localparam trc_min  = ns_to_cyc(63);
localparam trrd_min = ns_to_cyc(14);
localparam trcd_min = ns_to_cyc(21);
localparam trp_min  = ns_to_cyc(21);
localparam tras_min = ns_to_cyc(42);
localparam tras_max = ns_to_cyc(120000);

int 			rbl, wbl;
int             cas_latency;
int             cas_cnt, rd_cnt, wr_cnt;
logic           bt; // burst type
logic [9:0]     bc; // burst counter

int             trrd_cnt;
int             trc_cnt[4];
int             trc_cnt0, trc_cnt1, trc_cnt2, trc_cnt3;
int             trcd_cnt[4];
int             trcd_cnt0, trcd_cnt1, trcd_cnt2, trcd_cnt3;
int             trp_cnt[4];
int             trp_cnt0, trp_cnt1, trp_cnt2, trp_cnt3;
int             tras_cnt[4]; // up counter
int             tras_cnt0, tras_cnt1, tras_cnt2, tras_cnt3;

logic [3:0] 	cmd;
logic [1:0]     ba;
logic [12:0]    a;
logic           cke;
logic [15:0]    din, dout;
logic           rden;
logic [15:0]    wr_din;
logic           dqml, dqmh;
logic [1:0]     dqmn;
logic           dqloe, dqhoe;
logic [3:0]     active, row_open, prechg;
logic           auto_refresh;

logic [1:0] 	bank;
logic [12:0]    row[4];
logic [9:0]     col[4], col0[4];

logic [15:0] 	mem[1<<2][1<<13][1<<10];

task read(input [1:0] bank, input [12:0] row, input [9:0] col, output [15:0] d);
    d = mem[bank][row][col];
endtask

task write(input [1:0] bank, input [12:0] row, input [9:0] col, input [15:0] d);
    mem[bank][row][col] = d;
endtask

always @(posedge CLK) begin
    cmd <= {nCS, nRAS, nCAS, nWE};
    a <= A;
    dqml <= DQML;
    dqmh <= DQMH;
    ba <= BA;
    cke <= CKE;
    din <= DQ;
end

initial begin
    cas_cnt = 0;
    rd_cnt = 0;
    wr_cnt = 0;
    trrd_cnt = 0;
    for (int b = 0; b < 4; b++) begin
        trc_cnt[b] = 0;
        trcd_cnt[b] = 0;
        trp_cnt[b] = 0;
        tras_cnt[b] = 0;
        active[b] = 0;
        row_open[b] = 0;
        prechg[b] = 0;
    end
    auto_refresh = 0;
end

// For iverilog
assign trc_cnt0 = trc_cnt[0];
assign trc_cnt1 = trc_cnt[1];
assign trc_cnt2 = trc_cnt[2];
assign trc_cnt3 = trc_cnt[3];
assign trcd_cnt0 = trcd_cnt[0];
assign trcd_cnt1 = trcd_cnt[1];
assign trcd_cnt2 = trcd_cnt[2];
assign trcd_cnt3 = trcd_cnt[3];
assign trp_cnt0 = trp_cnt[0];
assign trp_cnt1 = trp_cnt[1];
assign trp_cnt2 = trp_cnt[2];
assign trp_cnt3 = trp_cnt[3];
assign tras_cnt0 = tras_cnt[0];
assign tras_cnt1 = tras_cnt[1];
assign tras_cnt2 = tras_cnt[2];
assign tras_cnt3 = tras_cnt[3];

always @(posedge CLK) if (cke & ~cmd[3]) begin
    case (cmd[2:0])
        CMD_LOAD_MODE: begin
            // A[2:0] = burst length: 0-3=2^N, 7=512 (full page)
            if (A[2:0] < 3'd7)
                rbl = 1 << a[2:0];
            else
                rbl = 512;
            // A[6:4] = CAS latency
            cas_latency = int'(a[6:4]);
            wbl = a[9] ? 1 : rbl;
            // A[3] = burst type: 0=sequential, 1=interleave
            bt = a[3];
        end
        CMD_ACTIVE: begin
            row[ba] <= a[12:0];
            bank <= ba;
        end
        CMD_READ: begin
            col0[ba] <= a[9:0];
            bank <= ba;
        end
        CMD_WRITE: begin
            col0[ba] <= a[9:0];
            bank <= ba;
        end
        default: ;
    endcase
end

always @* begin
logic [9:0] mask;
    mask = rbl[9:0] - 1'd1;
    for (int b = 0; b < 4; b++) begin
        if (bt)                     // interleave
            col[b] = col0[b] ^ bc;
        else                        // sequential
            col[b] = (col0[b] & ~mask) | ((col0[b] + bc) & mask);
    end
end

assign dout = row_open[bank] ? mem[bank][row[bank]][col[bank]] : 'X;

always @(posedge CLK) if (cke) begin
    if (cas_cnt != 0) begin
        cas_cnt <= cas_cnt - 1;
    end
    else if (rd_cnt != 0) begin
        rd_cnt <= rd_cnt - 1;
        bc <= bc + 1'd1;
    end
    else if (wr_cnt != 0) begin
        wr_cnt <= wr_cnt - 1;
        bc <= bc + 1'd1;
    end

    if (~cmd[3]) begin
        case (cmd[2:0])
            CMD_READ: begin
                cas_cnt <= cas_latency - 2;
                rd_cnt <= rbl;
                bc <= 0;
            end
            CMD_WRITE: begin
                wr_cnt <= wbl;
                bc <= 0;
            end
            default: ;
        endcase
    end

    if (((rd_cnt - 1 == 0) || (wr_cnt - 1 == 0)) && prechg[bank]) begin
        assert(tras_cnt[bank] >= tras_min - trp_min);
        prechg[bank] <= 0;
        active[bank] <= 0;
        row_open[bank] <= 0;
        trp_cnt[bank] <= trp_min - 1;
    end

    if (trrd_cnt != 0)
        trrd_cnt -= 1;
    for (int b = 0; b < 4; b++) begin
        if (trc_cnt[b] != 0) begin
            trc_cnt[b] <= trc_cnt[b] - 1;
        end
        if (trcd_cnt[b] != 0) begin
            if (trcd_cnt[b] - 1 == 0) begin
                assert(active[b]);
                row_open[b] <= 1;
            end
            trcd_cnt[b] <= trcd_cnt[b] - 1;
        end
        if (trp_cnt[b] != 0) begin
            trp_cnt[b] <= trp_cnt[b] - 1;
        end
        if (active[b] != 0) begin
            tras_cnt[b] <= tras_cnt[b] + 1; // yes, this is an up counter
            assert(tras_cnt[b] <= tras_max);
        end
    end

    if (auto_refresh) begin
        if (trc_cnt[0] == 1)
            auto_refresh <= 0;
        assert(cmd[3] || cmd[2:0] == CMD_NOP);
    end

    if (~cmd[3]) begin
        if (cmd[2:0] != CMD_NOP)
            assert(~|prechg); // interrupting AP is ILLEGAL
        case (cmd[2:0])
            CMD_ACTIVE: begin
                assert(trc_cnt[ba] == 0);
                trc_cnt[ba] <= trc_min - 1;
                assert(trrd_cnt == 0);
                trrd_cnt <= trrd_min - 1;
                assert(trcd_cnt[ba] == 0);
                trcd_cnt[ba] <= trcd_min - 1;
                assert(trp_cnt[ba] == 0);
                active[ba] <= 1;
                tras_cnt[ba] <= 1;
            end
            CMD_READ, CMD_WRITE: begin
                assert(trcd_cnt[ba] == 0);
                prechg[ba] <= a[10];
            end
            CMD_PRECHARGE: begin
                // a[10] is BankPrecharge (0) or PrechargeAll (1)
                for (int b = 0; b < 4; b++) begin
                    if ((~a[10] && b[1:0] == ba) || a[10]) begin
                        assert(trcd_cnt[b] == 0);
                        assert(a[10] || active[b]);
                        if (active[b]) begin
                            assert(tras_cnt[b] >= tras_min - trp_min);
                            active[b] <= 0;
                        end
                        row_open[b] <= 0;
                        trp_cnt[b] <= trp_min - 1;
                        tras_cnt[b] <= 0;
                    end
                end
            end
            CMD_AUTO_REFRESH: begin
                auto_refresh <= 1;
                for (int b = 0; b < 4; b++) begin
                    assert(trc_cnt[b] == 0);
                    trc_cnt[b] <= trc_min - 1;
                    assert(~row_open[b]);
                end
            end
            default: ;
        endcase
    end
end

always @(posedge CLK) if (cke) begin
    wr_din <= din;
    dqmn <= ~{dqmh, dqml};

    if (wr_cnt != 0) begin
        if (dqmn[1])
            mem[bank][row[bank]][col[bank]][15:8] <= wr_din[15:8];
        if (dqmn[0])
            mem[bank][row[bank]][col[bank]][7:0] <= wr_din[7:0];
    end
end

assign rden = (cas_cnt == 0) & (rd_cnt != 0);
assign {dqhoe, dqloe} = {2{rden}} & dqmn;

always @* begin
    assert(~(|{dqhoe, dqloe} & ~nWE)); // likely DQ I/O contention
end

assign DQ[15:8] = dqhoe ? dout[15:8] : 'Z;
assign DQ[7:0]  = dqloe ? dout[7:0]  : 'Z;

endmodule
