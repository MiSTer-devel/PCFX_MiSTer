//
// sdram.v
//
// sdram controller implementation
// Copyright (c) 2018 Sorgelig
// Copyright (c) 2025 David Hunter
//
// Based on sdram module by Till Harbaum
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
//

/* verilator lint_off CASEX */
/* verilator lint_off CASEINCOMPLETE */

module sdram
(

	// interface to the MT48LC16M16 chip
	inout      [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output reg [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output            SDRAM_DQML, // byte mask (shared w/ A[11])
	output            SDRAM_DQMH, // byte mask (shared w/ A[12])
	output reg  [1:0] SDRAM_BA,   // two banks
	output            SDRAM_nCS,  // a single chip select
	output reg        SDRAM_nWE,  // write enable
	output reg        SDRAM_nRAS, // row address select
	output reg        SDRAM_nCAS, // columns address select
	output            SDRAM_CLK,
	output            SDRAM_CKE,

	// cpu/chipset interface
	input             init,			// init signal after FPGA config to initialize RAM
	input             clk,			// sdram is accessed at up to 128MHz
	input             clkref,		// reference clock to sync to
	
	input      [24:0] raddr,      // 25 bit byte address
	input             rd,         // cpu/chipset requests read
	output reg        rd_rdy = 0,
	output reg [31:0] dout,			// data output to chipset/cpu

	input      [24:0] waddr,      // 25 bit byte address
	input      [31:0] din,			// data input from chipset/cpu
	input	    [3:0] be,	      // byte enable (be[0] => din[7:0])
	input             we,         // cpu/chipset write
	output reg        we_rdy = 0,
	input             we_req,     // cpu/chipset requests write
	output reg        we_ack = 0
);

assign SDRAM_nCS = 0;
assign SDRAM_CKE = 1;

// no burst configured
localparam RASCAS_DELAY   = 3'd2;   // tRCD=20ns -> 3 cycles@128MHz
localparam BURST_LENGTH   = 3'b001; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam WRITE_BURST_LEN = 1'b0;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, WRITE_BURST_LEN, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

localparam [3:0] STATE_IDLE  = 4'd0;   // first state in cycle
localparam [3:0] STATE_START = 4'd1;   // state in which a new command can be started
localparam [3:0] STATE_CONT  = STATE_START+RASCAS_DELAY; // 4 command can be continued
localparam [3:0] STATE_LAST  = 4'd7;   // last state in cycle
localparam [3:0] STATE_READY = STATE_READN+1;
localparam [3:0] STATE_READ0 = STATE_CONT+CAS_LATENCY+1; // first read cycle
localparam [3:0] STATE_READN = STATE_READ0+(1<<BURST_LENGTH)-1; // last read cycle
localparam [3:0] STATE_WRIT0 = STATE_CONT;               // first write cycle
localparam [3:0] STATE_WRITN = STATE_CONT+(1<<BURST_LENGTH)-1; // last write cycle


reg  [3:0] q = 0;
reg [24:0] a;
reg  [1:0] bank;
reg [31:0] data;
reg        wr;
reg  [3:0] bm=0;
reg        ram_req=0;

// access manager
always @(posedge clk) begin
	reg old_ref;

	old_ref<=clkref;

	if(q==STATE_IDLE) begin
		rd_rdy <= 1;
		we_rdy <= 1;
		ram_req <= 0;
		wr <= 0;

		if(we_ack != we_req || we) begin
			ram_req <= 1;
			wr <= 1;
            we_rdy <= 0;
			a <= waddr;
			data <= din;
			bm <= we ? ~be : 0;
		end
		else
		if(rd) begin
			rd_rdy <= 0;
			ram_req <= 1;
			wr <= 0;
			a <= raddr;
			bm <= 0;
		end
	end

	if (q == STATE_READY && ram_req) begin
		if(wr) begin
                        we_ack <= we_req;
			we_rdy <= 1;
		end
		else
			rd_rdy <= 1;
	end

	q <= q + 1'd1;
	if(~old_ref & clkref) q <= 0;
end

localparam MODE_NORMAL = 2'b00;
localparam MODE_RESET  = 2'b01;
localparam MODE_LDM    = 2'b10;
localparam MODE_PRE    = 2'b11;

// initialization 
reg [1:0] 	mode;
reg [4:0] 	reset=5'h1f;
reg 		init_old=0;
always @(posedge clk) begin
	init_old <= init;

	if(init_old & ~init) reset <= 5'h1f;
	else if(q == STATE_LAST) begin
		if(reset != 0) begin
			reset <= reset - 5'd1;
			if(reset == 14)     mode <= MODE_PRE;
			else if(reset == 3) mode <= MODE_LDM;
			else                mode <= MODE_RESET;
		end
		else mode <= MODE_NORMAL;
	end
end

localparam CMD_NOP             = 3'b111;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

reg [31:0] dqout, dqout_p;
reg        dqoe;
reg [3:0]  dqm, dqm_p;

wire	   q_wrcyc = (q>=STATE_WRIT0 && q<=STATE_WRITN && wr && ram_req);

always @* begin
	dqout_p = dqout;
	dqm_p = dqm;
	if(q_wrcyc) begin
		if (q==STATE_WRIT0) begin
			dqout_p = data;
			dqm_p = bm;
		end
		else begin
			dqout_p = {16'b0, dqout[31:16]};
			dqm_p = {2'b0, dqm[3:2]};
		end
	end
end

// SDRAM state machines
always @(posedge clk) begin
	reg [31:0] data_reg;

	casex({ram_req,wr,mode,q})
		{2'b1X, MODE_NORMAL, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
		{2'b11, MODE_NORMAL, STATE_CONT }: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_WRITE;
		{2'b10, MODE_NORMAL, STATE_CONT }: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
		{2'b0X, MODE_NORMAL, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;

		// init
		{2'bXX,    MODE_LDM, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_LOAD_MODE;
		{2'bXX,    MODE_PRE, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;

		                          default: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
	endcase

	dqoe <= q_wrcyc;
	dqout <= dqout_p;
	dqm <= dqm_p;

	if(mode == MODE_NORMAL) begin
		casex(q)
			STATE_START: SDRAM_A <= addr_to_row(a);
			STATE_CONT:  SDRAM_A <= {2'b00, 1'b1, addr_to_col(a)};
            STATE_LAST:  SDRAM_A <= 0;
		endcase;
		if(q_wrcyc)
			SDRAM_A[12:11] <= dqm_p[1:0];
	end
	else if(mode == MODE_LDM && q == STATE_START) SDRAM_A <= MODE;
	else if(mode == MODE_PRE && q == STATE_START) SDRAM_A <= 13'b0010000000000;
	else SDRAM_A <= 0;

	if(q == STATE_START) SDRAM_BA <= (mode == MODE_NORMAL) ? addr_to_bank(a) : 2'b00;
	if (~wr && ram_req) begin
		if(q >= STATE_READ0 && q <= STATE_READN) data_reg <= {SDRAM_DQ, data_reg[31:16]};
		if(q == STATE_READY) dout <= data_reg;
	end
end

function [1:0] addr_to_bank(input [24:0] a);
	addr_to_bank = a[24:23];
endfunction

function [12:0] addr_to_row(input [24:0] a);
	addr_to_row = a[21:9];
endfunction

function [9:0] addr_to_col(input [24:0] a);
	addr_to_col = {1'b0, a[22], a[8:1]};
endfunction

assign SDRAM_DQ = dqoe ? dqout[15:0] : 16'hZZZZ;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11]; // shorted on the SDRAM board

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
