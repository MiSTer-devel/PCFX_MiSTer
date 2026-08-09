//
// sdram
// Copyright (c) 2015-2019 Sorgelig
// Copyright (c) 2026 David Hunter
//
// Some parts of SDRAM code used from project:
// http://hamsterworks.co.nz/mediawiki/index.php/Simple_SDRAM_Controller
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// TODO: Handle CAS_LATENCY == 3

module sdram
    #(parameter CLK_MHZ = 142.8571428)
(
    input             init,        // reset to initialize RAM
    input             clk,         // clock ~100MHz
    input             hblank,      // good time to do refresh

    inout      [15:0] SDRAM_DQ,    // 16 bit bidirectional data bus
    output reg [12:0] SDRAM_A,     // 13 bit multiplexed address bus
    output            SDRAM_DQML,  // two byte masks
    output            SDRAM_DQMH,  // 
    output reg  [1:0] SDRAM_BA,    // two banks
    output            SDRAM_nCS,   // a single chip select
    output            SDRAM_nWE,   // write enable
    output            SDRAM_nRAS,  // row address select
    output            SDRAM_nCAS,  // columns address select
    output            SDRAM_CKE,   // clock enable

    input      [26:0] ch1_addr,    // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
    output reg [31:0] ch1_dout,    // data output to cpu
    input      [31:0] ch1_din,     // data input from cpu
    input             ch1_req,     // request
    input             ch1_rnw,     // 1 - read, 0 - write
    input      [3:0]  ch1_be,
    output            ch1_ready,

    input      [26:0] ch2_addr,    // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
    output reg [31:0] ch2_dout,    // data output to cpu
    input      [31:0] ch2_din,     // data input from cpu
    input             ch2_req,     // request
    input             ch2_rnw,     // 1 - read, 0 - write
    output            ch2_ready,

    input      [26:0] ch3_addr,
    output reg [31:0] ch3_dout,
    input      [31:0] ch3_din,
    input             ch3_req,
    input             ch3_rnw,
    output            ch3_ready
);

`include "sdram_defs.svh"

localparam BURST_CODE          = (BURST_LENGTH == 8) ? 3'b011 : (BURST_LENGTH == 4) ? 3'b010 : (BURST_LENGTH == 2) ? 3'b001 : 3'b000;  // 000=1, 001=2, 010=4, 011=8
localparam MODE                = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_CODE};

localparam sdram_startup_cycles= 14'd12100;// 100us, plus a little more, @ 100MHz
localparam cycles_per_refresh  = 14'(ns_to_cyc(int'(64e6 / 8192))-1);  // 64ms / 8192 refresh cycles
localparam startup_refresh_max = 14'b11111111111111;
localparam startup_mode_cnt    = startup_refresh_max - 7;
localparam startup_ref2_cnt    = 14'(startup_mode_cnt - TRC_MIN);
localparam startup_ref1_cnt    = 14'(startup_ref2_cnt - TRC_MIN);
localparam startup_pchg_cnt    = 14'(startup_ref1_cnt - TRP_MIN);
localparam cycles_per_row      = 5460; // HuC6261 LINE_CLOCKS * 2
localparam cycles_per_hbl      = 1140; // HuC6261 (LINE_CLOCKS - DISP_CLOCKS) * 2
localparam refresh_per_hbl     = 5'(cycles_per_row / int'(cycles_per_refresh) + 1);
localparam refresh_sys_wcnt_cnt = 9'(cycles_per_hbl / (int'(refresh_per_hbl) - 1));
reg [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
reg        refresh_due = '0;
reg [3:0]  refresh_credit = '0;
reg  [3:0] refresh_wait;
reg [4:0]  refresh_sys_cnt = '0;
reg        refresh_sys = '0;
reg [8:0]  refresh_sys_wcnt = '0;
logic      refresh_start;
reg  [2:0] command;

logic      hblank_d;

logic [3:0]  baidle; // bank idle status
logic        bapause;
// bacreq, badreq are bitmaps of future bus cycles required, LSB first
logic [3:0]  bacreq [4]; // cmd bus cycle request bitmap
logic [3:0]  badreq [4]; // data bus cycle request bitmap
logic [12:0] bar_a [4];
logic [2:0]  bar_cmd [4];
logic [15:0] bar_dqo [4];
logic [3:0]  bar_dqoe;

// Bus Bank Scheduler
reg [1:0]  bbsba; // current bank
reg [1:0]  bbsba_d; // last bank
reg [3:0]  bbscact; // cmd bus cycle activity bitmap
reg [3:0]  bbsdact; // data bus cycle activity bitmap
reg        bbsschn; // bank was newly scheduled
reg [1:0]  bbsschban; // the newly scheduled bank
reg [3:0]  bbsschv; // schedule filled
reg [1:0]  bbsschba [4]; // bank schedule

wire [1:0] bbsschba0 = bbsschba[0];
wire [1:0] bbsschba1 = bbsschba[1];
wire [1:0] bbsschba2 = bbsschba[2];
wire [1:0] bbsschba3 = bbsschba[3];

logic [15:0] dqi, dqo;
logic        dqoe;

localparam STATE_STARTUP = 0;
localparam STATE_ACTIVE  = 1;
localparam STATE_REFRESH = 2;

reg  [1:0] state = STATE_STARTUP;

assign refresh_start = refresh_due | refresh_sys;
assign bapause = state != STATE_ACTIVE || refresh_start;

// HBlank-driven refresh
always @(posedge clk) begin
    hblank_d <= hblank;

    if ((state != STATE_STARTUP) & hblank & ~hblank_d) begin
        refresh_sys_cnt <= refresh_per_hbl;
    end

    if (refresh_sys_cnt != 0) begin
        if (~refresh_sys && refresh_sys_wcnt == 0) begin
            refresh_sys <= '1;
            refresh_sys_wcnt <= refresh_sys_wcnt_cnt;
        end
        else if (refresh_sys && state == STATE_REFRESH) begin
            refresh_sys <= '0;
            refresh_sys_cnt <= refresh_sys_cnt - 1'd1;
        end
    end

    if (refresh_sys_wcnt != 0) begin
        refresh_sys_wcnt <= refresh_sys_wcnt - 1'd1;
    end
end

// Bank submodules
sdram_bank #(CLK_MHZ) ba0
   (
    .clk(clk),
    .init(init),
    .REQ(ch1_req),
    .READY(ch1_ready),
    .RNW(ch1_rnw),
    .ADDR(ch1_addr),
    .DIN(ch1_din),
    .DOUT(ch1_dout),
    .BE(ch1_be),
    .CREQ(bacreq[0]),
    .DREQ(badreq[0]),
    .IDLE(baidle[0]),
    .PAUSE(bapause),
    .BBSSEL(bbsba == 2'd0),
    .R_DQI(dqi),
    .R_DQO(bar_dqo[0]),
    .R_DQOE(bar_dqoe[0]),
    .R_A(bar_a[0]),
    .R_CMD(bar_cmd[0])
    );

sdram_bank #(CLK_MHZ) ba1
   (
    .clk(clk),
    .init(init),
    .REQ(ch2_req),
    .READY(ch2_ready),
    .RNW(ch2_rnw),
    .ADDR(ch2_addr),
    .DIN(ch2_din),
    .DOUT(ch2_dout),
    .BE(4'b0011),
    .CREQ(bacreq[1]),
    .DREQ(badreq[1]),
    .IDLE(baidle[1]),
    .PAUSE(bapause),
    .BBSSEL(bbsba == 2'd1),
    .R_DQI(dqi),
    .R_DQO(bar_dqo[1]),
    .R_DQOE(bar_dqoe[1]),
    .R_A(bar_a[1]),
    .R_CMD(bar_cmd[1])
    );

sdram_bank #(CLK_MHZ) ba2
   (
    .clk(clk),
    .init(init),
    .REQ(ch3_req),
    .READY(ch3_ready),
    .RNW(ch3_rnw),
    .ADDR(ch3_addr),
    .DIN(ch3_din),
    .DOUT(ch3_dout),
    .BE(4'b0011),
    .CREQ(bacreq[2]),
    .DREQ(badreq[2]),
    .IDLE(baidle[2]),
    .PAUSE(bapause),
    .BBSSEL(bbsba == 2'd2),
    .R_DQI(dqi),
    .R_DQO(bar_dqo[2]),
    .R_DQOE(bar_dqoe[2]),
    .R_A(bar_a[2]),
    .R_CMD(bar_cmd[2])
    );

sdram_bank #(CLK_MHZ) ba3
   (
    .clk(clk),
    .init(init),
    .REQ('0),
    .READY(),
    .RNW('0),
    .ADDR('0),
    .DIN('0),
    .DOUT(),
    .BE('0),
    .CREQ(bacreq[3]),
    .DREQ(badreq[3]),
    .IDLE(baidle[3]),
    .PAUSE(bapause),
    .BBSSEL(bbsba == 2'd3),
    .R_DQI(dqi),
    .R_DQO(bar_dqo[3]),
    .R_DQOE(bar_dqoe[3]),
    .R_A(bar_a[3]),
    .R_CMD(bar_cmd[3])
    );

// Bus bank scheduler
always @* begin
    bbsba = bbsba_d;
    bbsschn = 0;
    bbsschban = 0;

    if (bbsschv[0]) begin
        // Select previously scheduled bank
        bbsba = bbsschba[0];
    end
    else begin
        // Nothing scheduled yet. Any volunteers?
        for (int b = 3; b >= 0; b--) begin
            if (bbsschn == 0) begin
                bbsschban = b[1:0];

                if (|(bacreq[b] | badreq[b]) &
                    ~|(bacreq[b] & bbscact) & ~|(badreq[b] & bbsdact))
                    bbsschn = 1;
            end
        end
        if (bbsschn)
            // Select newly scheduled bank
            bbsba = bbsschban;
    end
end

initial
    bbsba_d = 0;

always @(posedge clk) begin
    bbsba_d <= bbsba;

    for (int i = 0; i < $size(bbsschv); i++) begin
        if (i < $size(bbsschv) - 1) begin
            bbsschv[i] <= bbsschv[i+1];
            bbsschba[i] <= bbsschba[i+1];
        end
        else begin
            bbsschv[i] <= 0;
            bbsschba[i] <= 0;
        end

        if (bbsschn & bacreq[bbsschban][i]) begin
            bbsschv[i] <= 1;
            bbsschba[i] <= bbsschban;
        end
    end
end

always @(posedge clk) begin
    bbscact <= {1'b0, bbscact[$left(bbscact):1]} | bacreq[bbsba];
    bbsdact <= {1'b0, bbsdact[$left(bbsdact):1]} | badreq[bbsba];
end

// Main FSM
always @(posedge clk) begin
    refresh_count <= refresh_count+1'b1;

    command <= CMD_NOP;
    SDRAM_A[12:11] <= 2'b11; // DQM
    case (state)
        STATE_STARTUP: begin
            SDRAM_A[10:0] <= 0;
            SDRAM_BA      <= 0;

            // All the commands during the startup are NOPS, except these
            if (refresh_count == startup_pchg_cnt) begin
                // ensure all rows are closed
                command     <= CMD_PRECHARGE;
                SDRAM_A[10] <= 1;  // all banks
                SDRAM_BA    <= 2'b00;
            end
            if (refresh_count == startup_ref1_cnt) begin
                // these refreshes need to be at least tRC apart
                command     <= CMD_AUTO_REFRESH;
            end
            if (refresh_count == startup_ref2_cnt) begin
                command     <= CMD_AUTO_REFRESH;
            end
            if (refresh_count == startup_pchg_cnt) begin
                // Now load the mode register
                command     <= CMD_LOAD_MODE;
                SDRAM_A     <= MODE;
            end

            if (refresh_count == 0) begin
                state   <= STATE_ACTIVE;
                refresh_count <= 0;
            end
        end

        STATE_REFRESH: begin
            // mask possible refresh to reduce colliding.
            if (refresh_wait == 4'(TRC_MIN)) begin
                // Start the refresh cycle.
                command  <= CMD_AUTO_REFRESH;
                if (refresh_due)
                    refresh_due <= '0;
                else if (~&refresh_credit)
                    refresh_credit <= refresh_credit + 1'd1;
                refresh_wait <= refresh_wait - 1'd1;
            end
            else begin
                refresh_wait <= refresh_wait - 1'd1;
                if (refresh_wait - 1'd1 == 0)
                    state <= STATE_ACTIVE;
            end
        end

        STATE_ACTIVE: begin
            SDRAM_BA <= bbsba;
            SDRAM_A  <= bar_a[bbsba];
            command  <= bar_cmd[bbsba];

            if (&baidle & refresh_start) begin
                // Priority is to issue a refresh if one is outstanding
                state <= STATE_REFRESH;
                refresh_wait <= 4'(TRC_MIN);
            end

            if (~refresh_due && refresh_count > cycles_per_refresh) begin
                refresh_count <= refresh_count - cycles_per_refresh + 1'd1;
                if (refresh_credit != 0)
                    refresh_credit <= refresh_credit - 1'd1;
                else
                    refresh_due <= '1;
            end
        end
    endcase

    if (init) begin
        state <= STATE_STARTUP;
        refresh_count <= startup_refresh_max - sdram_startup_cycles;
    end
end

// DQ registers
//
// Note: To meet data timing requirements, the critical I/O settings
// FAST_INPUT_REGISTER, FAST_OUTPUT_REGISTER, and
// FAST_OUTPUT_ENABLE_REGISTER must be applied on SDRAM_DQ pins.  They
// will only be applied if each pin is latched/driven by a single
// I/O/OE register.

always @(posedge clk) begin
    dqi <= SDRAM_DQ;
    dqo <= bar_dqo[0] | bar_dqo[1] | bar_dqo[2] | bar_dqo[3];
    dqoe <= |bar_dqoe;
end

assign SDRAM_DQ = dqoe ? dqo : 'Z;
assign SDRAM_nCS  = 0;
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
assign SDRAM_CKE  = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

endmodule

`include "sdram_bank.sv"
