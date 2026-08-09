// SDRAM controller shared definitions
//
// Copyright (c) 2015-2019 Sorgelig
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// SDRAM commands
wire [2:0] CMD_NOP             = 3'b111;
wire [2:0] CMD_ACTIVE          = 3'b011;
wire [2:0] CMD_READ            = 3'b101;
wire [2:0] CMD_WRITE           = 3'b100;
wire [2:0] CMD_PRECHARGE       = 3'b010;
wire [2:0] CMD_AUTO_REFRESH    = 3'b001;
wire [2:0] CMD_LOAD_MODE       = 3'b000;

// All times in ns are for AS4C32M16SB-7: tCK3 (clk cycle) = 7 ns (143 MHz)
// Parameters are in whole cycles, and assume clk cycle = 1 / CLK_MHZ
function int ns_to_cyc(int ns);
    // ns_to_cyc = int'($ceil(CLK_MHZ * ns / 1000.0));
    ns_to_cyc = int'(((CLK_MHZ * ns + 500.0) / 1000.0));
endfunction

localparam TRC_MIN  = ns_to_cyc(63);
localparam TRRD_MIN = ns_to_cyc(14);
localparam TRCD_MIN = ns_to_cyc(21);
localparam TRP_MIN  = ns_to_cyc(21);
localparam TWR_MIN  = ns_to_cyc(14);
localparam TRAS_MIN = ns_to_cyc(42);
localparam TRAS_MAX = ns_to_cyc(120000);

localparam BURST_LENGTH        = 2;
localparam ACCESS_TYPE         = 1'b0;     // 0=sequential, 1=interleaved
localparam CAS_LATENCY         = 3'd2;     // 2 for < 100MHz, 3 for >100MHz
localparam OP_MODE             = 2'b00;    // only 00 (standard operation) allowed
localparam NO_WRITE_BURST      = 1'b1;     // 0= write burst enabled, 1=only single access write

function [1:0] addr_to_bank(input [26:0] a);
    addr_to_bank = a[25:24];
endfunction

function [12:0] addr_to_row(input [26:0] a);
    addr_to_row = a[22:10];
endfunction

function [9:0] addr_to_col(input [26:0] a);
    addr_to_col = {a[23], a[9:1]};
endfunction
