// SDRAM controller bank submodule
//
// Copyright (c) 2015-2019 Sorgelig
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module sdram_bank
    #(parameter CLK_MHZ = 142.8571428,
      parameter DM = 31)
(
    input         clk,
    input         init,
    input         REQ,
    output        READY,
    input         RNW,
    input [26:0]  ADDR,
    input [DM:0]  DIN,
    output [DM:0] DOUT,
    input [3:0]   BE,
    output [3:0]  CREQ,
    output [3:0]  DREQ,
    output        IDLE,
    input         PAUSE,
    input         BBSSEL,
    input [15:0]  R_DQI,
    output [15:0] R_DQO,
    output        R_DQOE,
    output [12:0] R_A,
    output [2:0]  R_CMD
);

`include "sdram_defs.svh"

// BAnk STate
localparam BAST_IDLE     = 0;
localparam BAST_ACT      = 1;
localparam BAST_ACT_WAIT = 2;
localparam BAST_R_CMD    = 3;
localparam BAST_R_DQM    = 4;
localparam BAST_R        = 5;
localparam BAST_W_CMD    = 6;
localparam BAST_W_CMD_2  = 7;
localparam BAST_W_REC    = 8;
localparam BAST_PRE      = 9;

// Number of active read/write beats for this bank
localparam BEATS = (DM == 31) ? 2 : 1;

reg         rq, rqc; // access request
reg         rnw; // read / not write
reg [12:0]  row; // row address
reg [9:0]   col; // column address
reg [31:0]  din; // data to write
reg [31:0]  dout; // data read
reg [3:0]   be; // byte enables
reg [3:0]   st, stn; // bank current status
reg [3:0]   wcnt, wcntn; // wait counter
reg [3:0]   creq; // cmd bus cycle request bitmap
reg [3:0]   dreq; // data bus cycle request bitmap
reg [12:0]  r_a;
reg [2:0]   r_cmd;
reg [15:0]  dqout;
reg         dqoe;

reg [CAS_LATENCY+BEATS:0] data_ready_delay = 0;
reg         ready = 0;

always @(posedge clk) begin
    rnw <= RNW;
    row <= addr_to_row(ADDR);
    col <= addr_to_col(ADDR);
    din <= 32'(DIN);
    be <= BE;
end

initial rq = 0;
always @(posedge clk) begin
    if (init)
        rq <= 0;
    else
        rq <= (rq & ~rqc) | REQ;
end

// Bank start trigger and request clear
always @* begin
    rqc = BBSSEL && ~PAUSE && rq && (st == BAST_IDLE);
end

// Bank bus cycle request bitmap generator
always @* begin
    creq = 0;
    dreq = 0;

    case (st)
        BAST_IDLE: begin
            if (~PAUSE && rq) begin
                creq = 4'b1;
            end
        end
        BAST_ACT_WAIT:
            if (wcnt == 0) begin
                creq = (1<<BURST_LENGTH)-1;
                if (rnw)
                    dreq = (1<<BURST_LENGTH)-1 << 2;
                else
                    dreq = (1<<BEATS)-1;
            end
        default: ;
    endcase
end

// Bank FSM
always @* begin
    stn = st;
    wcntn = wcnt;

    if (wcnt != 0)
        wcntn = wcnt - 1'd1;

    case (st)
        BAST_IDLE: if (BBSSEL) begin
            if (rqc) begin
                stn = BAST_ACT;
            end
        end
        BAST_ACT: begin
            stn = BAST_ACT_WAIT;
            wcntn = 4'(TRCD_MIN - 2);
        end
        BAST_ACT_WAIT: if (BBSSEL) begin
            if (wcnt == 0) begin
                stn = rnw ? BAST_R_CMD : BAST_W_CMD;
            end
        end
        BAST_R_CMD: begin
            stn = BAST_R_DQM;
        end
        BAST_R_DQM: begin
            stn = BAST_R;
            wcntn = BURST_LENGTH - 1;
        end
        BAST_R:
            if (wcnt == 0) begin
                if (TRP_MIN-(BURST_LENGTH-1) >= 2) begin
                    stn = BAST_PRE;
                    wcntn = 4'(TRP_MIN-(BURST_LENGTH-1) - 2);
                end
                else
                    stn = BAST_IDLE;
            end
        BAST_W_CMD: begin
            if (BEATS == 2)
                stn = BAST_W_CMD_2;
            else begin
                stn = BAST_W_REC;
                wcntn = 4'(TWR_MIN - 1);
            end
        end
        BAST_W_CMD_2: begin
            stn = BAST_W_REC;
            wcntn = 4'(TWR_MIN - 1);
        end
        BAST_W_REC:
            if (wcnt == 0) begin
                stn = BAST_PRE;
                wcntn = 4'(TRP_MIN - 2);
            end
        BAST_PRE:
            if (wcnt == 0) begin
                stn = BAST_IDLE;
            end
    endcase

    if (init)
        stn = BAST_IDLE;
end

initial st = BAST_IDLE;
initial wcnt = 0;
always @(posedge clk) begin
    st <= stn;
    wcnt <= wcntn;
end

// Register SDRAM outputs for the next state
always @(posedge clk) begin
    r_a        <= '0;
    r_a[12:11] <= 2'b11; // DQM
    r_cmd      <= CMD_NOP;

    case (stn)
        BAST_ACT: begin
            r_a        <= row;
            r_cmd      <= CMD_ACTIVE;
        end
        BAST_R_CMD: begin
            r_a[12:11] <= 0; // DQM for 1st beat
            r_a[10]    <= 1; // auto-precharge
            r_a[9:0]   <= col;
            r_cmd      <= CMD_READ;
        end
        BAST_R_DQM: begin
            r_a[12:11] <= 0; // DQM for 2nd beat
        end
        BAST_W_CMD: begin
            r_a[12:11] <= ~be[1:0]; // DQM for 1st beat
            r_a[10]    <= (BEATS == 1); // auto-precharge on last beat
            r_a[9:0]   <= col;
            r_cmd      <= CMD_WRITE;
        end
        BAST_W_CMD_2: begin
            r_a[12:11] <= ~be[3:2]; // DQM for 2nd beat
            r_a[10]    <= (BEATS == 2); // auto-precharge on last beat
            r_a[9:0]   <= col;
            r_a[0]     <= 1;
            r_cmd      <= CMD_WRITE;
        end
        default: ;
    endcase
end

always @(posedge clk) begin
    dqout <= '0;
    dqoe  <= '0;
    ready <= '0;

    data_ready_delay <= data_ready_delay >> 1;

    if (data_ready_delay[BEATS-1]) dout[15:00] <= R_DQI;
    if (BEATS == 2)
        if (data_ready_delay[BEATS-2]) dout[31:16] <= R_DQI;
    if (data_ready_delay[0]) ready <= 1;

    if (BBSSEL) begin
        case (st)
            BAST_R_CMD:
                data_ready_delay[CAS_LATENCY+BEATS] <= 1;
            default: ;
        endcase

        case (stn)              // final DQ output is 1 clk later
            BAST_W_CMD: begin
                dqout <= din[15:0];
                dqoe  <= 1;
                if (BEATS == 1)
                    ready <= 1;
            end
            BAST_W_CMD_2: begin
                dqout <= din[31:16];
                dqoe  <= 1;
                if (BEATS == 2)
                    ready <= 1;
            end
            default: ;
        endcase
    end
end

assign CREQ = creq;
assign DREQ = dreq;
assign IDLE = st == BAST_IDLE;
assign R_DQO = dqout;
assign R_DQOE = dqoe;
assign R_A = r_a;
assign R_CMD = r_cmd;
assign DOUT = dout[DM:0];
assign READY = ready;

endmodule
