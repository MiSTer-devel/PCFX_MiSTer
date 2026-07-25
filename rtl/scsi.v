// File SCSI.vhd translated with vhd2vl 3.0 VHDL to Verilog RTL translator
// vhd2vl settings:
//  * Verilog Module Declaration Style: 2001

// vhd2vl is Free (libre) Software:
//   Copyright (C) 2001-2023 Vincenzo Liguori - Ocean Logic Pty Ltd
//     http://www.ocean-logic.com
//   Modifications Copyright (C) 2006 Mark Gonzales - PMC Sierra Inc
//   Modifications (C) 2010 Shankar Giri
//   Modifications Copyright (C) 2002-2023 Larry Doolittle
//     http://doolittle.icarus.com/~larry/vhd2vl/
//   Modifications (C) 2017 Rodrigo A. Melo
//
//   vhd2vl comes with ABSOLUTELY NO WARRANTY.  Always check the resulting
//   Verilog for correctness, ideally with a formal verification tool.
//
//   You are welcome to redistribute vhd2vl under certain conditions.
//   See the license (GPLv2) file included with the source for details.

// The result of translation follows.  Its copyright status should be
// considered unchanged from the original VHDL.

module scsi(
input wire RESET_N,
input wire CLK,
input wire [7:0] DBI,
output reg [7:0] DBO,
input wire SEL_N,
input wire ACK_N,
input wire RST_N,
input wire ATN_N,
output wire BSY_N,
output wire REQ_N,
output wire MSG_N,
output wire CD_N,
output wire IO_N,
input wire [7:0] STATUS,
input wire [7:0] MESSAGE,
input wire STAT_GET,
output wire [95:0] COMMAND,
output wire COMM_SEND,
input wire DOUT_REQ,
output wire [79:0] DOUT,
output wire DOUT_SEND,
input wire [7:0] CD_DATA,
input wire CD_WR,
output wire CD_READY,
output reg CD_DATA_END,
output reg STOP_CD_SND,
output wire MSGOUT_PEND,
output reg [7:0] MSGOUT,
output wire MSGOUT_SEND,
output wire [15:0] DBG_DATAIN_CNT
);




wire RESET;
parameter [3:0]
  SP_FREE = 0,
  SP_COMM_BEFOREREQ = 1,
  SP_COMM_START = 2,
  SP_COMM_END = 3,
  SP_STAT_START = 4,
  SP_STAT_END = 5,
  SP_STAT_HOLD = 6,
  SP_MSGIN_START = 7,
  SP_MSGIN_END = 8,
  SP_MSGIN_HOLD = 9,
  SP_DATAIN_START = 10,
  SP_DATAIN_END = 11,
  SP_DATAOUT_START = 12,
  SP_DATAOUT_END = 13,
  SP_MSGOUT_START = 14,
  SP_MSGOUT_END = 15;

reg [3:0] SP;
reg BSY_Nr;
reg MSG_Nr;
reg CD_Nr;
reg IO_Nr;
reg REQ_Nr;
//	signal TR_DONE		: std_logic;
//	signal TR_RDY		: std_logic;

reg [7:0] COMM[0:11];
reg [3:0] COMM_POS;
reg COMM_OUT;
reg [3:0] COMM_LEN;

reg [7:0] DATA_BUF[0:9];
reg [3:0] DATA_POS;
reg DATA_OUT;
reg MSGOUT_OUT;
wire FULL;
wire EMPTY;
reg FIFO_RD_REQ;
reg FIFO_WR_REQ;
reg [7:0] FIFO_D;
wire [7:0] FIFO_Q;
reg CD_WR_OLD;
reg STAT_PEND;
reg DOUT_PEND;
reg [15:0] DATAIN_CNT;
reg [15:0] STAT_COUNT;
reg [16:0] DELAY_COUNT;

  assign RESET =  ~RESET_N;

  always @(COMM[0][7:5]) begin
    COMM_LEN = 4'b1010;
    if(COMM[0][7:5] == 3'b000) begin
      COMM_LEN = 4'b0110;
    end
    else if(COMM[0][7:5] == 3'b101) begin
      COMM_LEN = 4'b1100;
    end
  end

  always @(posedge CLK) begin
    if(RESET_N == 1'b0) begin
      FIFO_D <= {8{1'b0}};
      FIFO_WR_REQ <= 1'b0;
      //CD_WR_OLD <= '0';
    end else begin
      FIFO_WR_REQ <= 1'b0;
      //			if EN = '1' then
      CD_WR_OLD <= CD_WR;
      if(CD_WR == 1'b1 && CD_WR_OLD == 1'b0) begin
        FIFO_D <= CD_DATA;
        if(FULL == 1'b0) begin
          FIFO_WR_REQ <= 1'b1;
        end
      end
      //			end if;
    end
  end

assign CD_READY = ~FULL;

// Keep this small to speed up ATN response.
fifo1 #(.DSIZE(8), .ASIZE(6)) FIFO(
    .WRST_N(RESET_N),
    .WCLK(CLK),
    .WDATA(FIFO_D),
    .WINC(FIFO_WR_REQ),
    .WFULL(FULL),
    .RRST_N(RESET_N),
    .RCLK(CLK),
    .RINC(FIFO_RD_REQ),
    .REMPTY(EMPTY),
    .RDATA(FIFO_Q));

  always @(posedge CLK) begin
    if(RESET_N == 1'b0) begin
      DBO <= {8{1'b0}};
      BSY_Nr <= 1'b1;
      MSG_Nr <= 1'b1;
      CD_Nr <= 1'b1;
      IO_Nr <= 1'b1;
      REQ_Nr <= 1'b1;
      COMM[0] <= 8'b0;
      COMM[1] <= 8'b0;
      COMM[2] <= 8'b0;
      COMM[3] <= 8'b0;
      COMM[4] <= 8'b0;
      COMM[5] <= 8'b0;
      COMM[6] <= 8'b0;
      COMM[7] <= 8'b0;
      COMM[8] <= 8'b0;
      COMM[9] <= 8'b0;
      COMM[10] <= 8'b0;
      COMM[11] <= 8'b0;
      COMM_POS <= {4{1'b0}};
      DATA_BUF[0] <= 8'b0;
      DATA_BUF[1] <= 8'b0;
      DATA_BUF[2] <= 8'b0;
      DATA_BUF[3] <= 8'b0;
      DATA_BUF[4] <= 8'b0;
      DATA_BUF[5] <= 8'b0;
      DATA_BUF[6] <= 8'b0;
      DATA_BUF[7] <= 8'b0;
      DATA_BUF[8] <= 8'b0;
      DATA_BUF[9] <= 8'b0;
      DATA_POS <= {4{1'b0}};
      MSGOUT <= 8'b0;
      SP <= SP_FREE;
      STOP_CD_SND <= 1'b0;
      COMM_OUT <= 1'b0;
      DATA_OUT <= 1'b0;
      MSGOUT_OUT <= 1'b0;
      CD_DATA_END <= 1'b0;
      STAT_PEND <= 1'b0;
      DOUT_PEND <= 1'b0;
      FIFO_RD_REQ <= 1'b0;
      STAT_COUNT <= {16{1'b0}};
      DELAY_COUNT <= {17{1'b0}};
      DATAIN_CNT <= {16{1'b0}};
    end else begin
      if(STAT_GET == 1'b1) begin
        STAT_PEND <= 1'b1;
      end
      if(DOUT_REQ == 1'b1) begin
        DOUT_PEND <= 1'b1;
      end
      COMM_OUT <= 1'b0;
      DATA_OUT <= 1'b0;
      MSGOUT_OUT <= 1'b0;
      CD_DATA_END <= 1'b0;
      FIFO_RD_REQ <= 1'b0;
      if(RST_N == 1'b0) begin
        BSY_Nr <= 1'b1;
        MSG_Nr <= 1'b1;
        CD_Nr <= 1'b1;
        IO_Nr <= 1'b1;
        REQ_Nr <= 1'b1;
      end
      else begin
        case(SP)
        SP_FREE : begin
          if(SEL_N == 1'b0) begin
            BSY_Nr <= 1'b0;
            MSG_Nr <= 1'b1;
            CD_Nr <= 1'b0;
            IO_Nr <= 1'b1;
            SP <= SP_COMM_BEFOREREQ;
            DELAY_COUNT <= 1700;
            // Wait 40 microseconds after control signals are set up, before triggering REQ in COMMAND phase
            DATAIN_CNT <= {16{1'b0}};
          end
          else if(ATN_N == 1'b0) begin
            BSY_Nr <= 1'b0;
            MSG_Nr <= 1'b0;
            CD_Nr <= 1'b0;
            IO_Nr <= 1'b1;
            REQ_Nr <= 1'b0;
            SP <= SP_MSGOUT_START;
          end
          else if(STAT_PEND == 1'b1) begin
            STAT_COUNT <= STAT_COUNT + 1;
            if((STAT_COUNT == 45000)) begin
              // CLK is 42.95 MHz; this gives ~1.05 millisec delay before transitioning to STATUS phase
              // this is empirical and may not be correct but it solves
              // the Sailor Moon hang issue
              STAT_COUNT <= {16{1'b0}};
              STAT_PEND <= 1'b0;
              DBO <= STATUS;
              BSY_Nr <= 1'b0;
              MSG_Nr <= 1'b1;
              CD_Nr <= 1'b0;
              IO_Nr <= 1'b0;
              REQ_Nr <= 1'b0;
              SP <= SP_STAT_START;
            end
          end
          else if(EMPTY == 1'b0) begin
            DBO <= FIFO_Q;
            BSY_Nr <= 1'b0;
            MSG_Nr <= 1'b1;
            CD_Nr <= 1'b1;
            IO_Nr <= 1'b0;
            REQ_Nr <= 1'b0;
            FIFO_RD_REQ <= 1'b1;
            SP <= SP_DATAIN_START;
          end
          else if(DOUT_PEND == 1'b1) begin
            DOUT_PEND <= 1'b0;
            BSY_Nr <= 1'b0;
            MSG_Nr <= 1'b1;
            CD_Nr <= 1'b1;
            IO_Nr <= 1'b1;
            REQ_Nr <= 1'b0;
            SP <= SP_DATAOUT_START;
          end
        end
        SP_COMM_BEFOREREQ : begin
          if((DELAY_COUNT == 0)) begin
            REQ_Nr <= 1'b0;
            SP <= SP_COMM_START;
          end
          else begin
            DELAY_COUNT <= DELAY_COUNT - 1;
          end
        end
        SP_COMM_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            COMM[COMM_POS] <= DBI;
            COMM_POS <= COMM_POS + 1;
            SP <= SP_COMM_END;
          end
        end
        SP_COMM_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            if(COMM_POS == COMM_LEN) begin
              COMM_POS <= {4{1'b0}};
              COMM_OUT <= 1'b1;
              CD_Nr <= 1'b1;
              SP <= SP_FREE;
              if(((COMM[0] == 8'h08) || (COMM[0] == 8'hDA))) begin
                // READ6 and PAUSE commands should mute sound, but still drain FIFO
                STOP_CD_SND <= 1'b1;
              end
              if(((COMM[0] == 8'hD8) || (COMM[0] == 8'hD9))) begin
                // SAPSP and SAPEP commands should unmute sound (FIFO should be empty by now)
                STOP_CD_SND <= 1'b0;
              end
            end
            else begin
              SP <= SP_COMM_BEFOREREQ;
              DELAY_COUNT <= 5370;
              // Wait 125 microseconds after ACK, before next REQ in COMMAND phase
            end
          end
        end
        SP_STAT_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            SP <= SP_STAT_END;
          end
        end
        SP_STAT_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            SP <= SP_STAT_HOLD;
            DELAY_COUNT <= 49400;
            // wait 1.15 milliseconds after ACK in STATUS pahse before transitioning to next phase (MSGIN)
          end
        end
        SP_STAT_HOLD : begin
          if((DELAY_COUNT == 0)) begin
            DBO <= MESSAGE;
            BSY_Nr <= 1'b0;
            MSG_Nr <= 1'b0;
            CD_Nr <= 1'b0;
            IO_Nr <= 1'b0;
            REQ_Nr <= 1'b0;
            SP <= SP_MSGIN_START;
          end
          else begin
            DELAY_COUNT <= DELAY_COUNT - 1;
          end
        end
        SP_MSGIN_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            SP <= SP_MSGIN_END;
          end
        end
        SP_MSGIN_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            SP <= SP_MSGIN_HOLD;
            DELAY_COUNT <= 6600;
            // wait 154 microseconds after ACK in STATUS phase before transitioning to next phase/disconnecting
          end
        end
        SP_MSGIN_HOLD : begin
          if((DELAY_COUNT == 0)) begin
            BSY_Nr <= 1'b1;
            MSG_Nr <= 1'b1;
            CD_Nr <= 1'b1;
            IO_Nr <= 1'b1;
            REQ_Nr <= 1'b1;
            SP <= SP_FREE;
          end
          else begin
            DELAY_COUNT <= DELAY_COUNT - 1;
          end
        end
        SP_DATAIN_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            SP <= SP_DATAIN_END;
            STOP_CD_SND <= 1'b0;
            // unmute
          end
        end
        SP_DATAIN_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            if(EMPTY == 1'b0) begin
              DBO <= FIFO_Q;
              REQ_Nr <= 1'b0;
              FIFO_RD_REQ <= 1'b1;
              SP <= SP_DATAIN_START;
            end
            else begin
              CD_DATA_END <= 1'b1;
              SP <= SP_FREE;
            end
            DATAIN_CNT <= DATAIN_CNT + 1;
          end
        end
        SP_DATAOUT_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            DATA_BUF[DATA_POS] <= DBI;
            DATA_POS <= DATA_POS + 1;
            SP <= SP_DATAOUT_END;
          end
        end
        SP_DATAOUT_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            if(DATA_POS == 10) begin
              DATA_POS <= {4{1'b0}};
              DATA_OUT <= 1'b1;
              SP <= SP_FREE;
            end
            else begin
              REQ_Nr <= 1'b0;
              SP <= SP_DATAOUT_START;
            end
          end
        end
        SP_MSGOUT_START : begin
          if(REQ_Nr == 1'b0 && ACK_N == 1'b0) begin
            REQ_Nr <= 1'b1;
            MSGOUT <= DBI;
            SP <= SP_MSGOUT_END;
          end
        end
        SP_MSGOUT_END : begin
          if(REQ_Nr == 1'b1 && ACK_N == 1'b1) begin
            if(ATN_N == 1'b1) begin
              // Treat all messages as ABORT.
              BSY_Nr <= 1'b1;
              MSG_Nr <= 1'b1;
              CD_Nr <= 1'b1;
              IO_Nr <= 1'b1;
              REQ_Nr <= 1'b1;
              MSGOUT_OUT <= 1'b1;
              SP <= SP_FREE;
            end
            else begin
              REQ_Nr <= 1'b0;
              SP <= SP_MSGOUT_START;
            end
          end
        end
        default : begin
        end
        endcase
      end
    end
  end

  assign BSY_N = BSY_Nr;
  assign MSG_N = MSG_Nr;
  assign CD_N = CD_Nr;
  assign IO_N = IO_Nr;
  assign REQ_N = REQ_Nr;
  assign COMMAND = {COMM[11],COMM[10],COMM[9],COMM[8],COMM[7],COMM[6],COMM[5],COMM[4],COMM[3],COMM[2],COMM[1],COMM[0]};
  assign COMM_SEND = COMM_OUT;
  assign DOUT = {DATA_BUF[9],DATA_BUF[8],DATA_BUF[7],DATA_BUF[6],DATA_BUF[5],DATA_BUF[4],DATA_BUF[3],DATA_BUF[2],DATA_BUF[1],DATA_BUF[0]};
  assign DOUT_SEND = DATA_OUT;
  assign MSGOUT_SEND = MSGOUT_OUT;
  assign MSGOUT_PEND = ~ATN_N;
  assign DBG_DATAIN_CNT = DATAIN_CNT;

/* -----\/----- EXCLUDED -----\/-----
always @(negedge REQ_Nr)
    $display("MCI=%x%x%x DB=%x", ~MSG_N, ~CD_N, ~IO_N, IO_Nr ? DBI : DBO);
 -----/\----- EXCLUDED -----/\----- */

endmodule
