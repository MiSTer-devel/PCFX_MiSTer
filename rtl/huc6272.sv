// Placeholder for HuC6272 (KING)
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272
    (
     input         CLK,
     input         CE,
     input         RESn,

     input [2:1]   A,
     input [15:0]  DI,
     output [15:0] DO,
     input         CSn,
     input         WRn,
     input         RDn,
     output        BUSYn,
     output        IRQn,

     input [7:0]   SCSI_DI,
     output [7:0]  SCSI_DO,
     output        SCSI_DOE,
     output        SCSI_ATNn,
     input         SCSI_BSYn,
     output        SCSI_ACKn,
     output        SCSI_RSTn,
     input         SCSI_MSGn,
     output        SCSI_SELn,
     input         SCSI_CDn,
     input         SCSI_REQn,
     input         SCSI_IOn
     );

logic [6:0]     rsel;

logic [31:0]    dout;

logic [7:0]     scsi_cur_bus_stat;
logic [7:0]     scsi_din, scsi_dout, scsi_rxbuf, scsi_txbuf;

logic           scsi_assert_rst;
logic           scsi_assert_ack;
logic           scsi_assert_sel;
logic           scsi_assert_atn;
logic           scsi_assert_data;
logic           scsi_assert_io;
logic           scsi_assert_cd;
logic           scsi_assert_msg;

logic           scsi_dma_mode;
logic           scsi_start_dma_rx, scsi_start_dma_tx;
logic           scsi_dma_req, scsi_dma_req_set, scsi_dma_req_clr;
logic           scsi_phase_match;

logic           scsi_reset_int;
logic           scsi_rxbuf_rd;
logic           scsi_int_req_act;

//////////////////////////////////////////////////////////////////////
// CPU memory / I/O bus interface

always @(posedge CLK) if (CE) begin
    scsi_start_dma_tx <= '0;
    scsi_start_dma_rx <= '0;

    if (~RESn) begin
        rsel <= '0;
        scsi_dout <= '0;
        scsi_assert_rst <= '0;
        scsi_assert_ack <= '0;
        scsi_assert_sel <= '0;
        scsi_assert_atn <= '0;
        scsi_assert_data <= '0;
        scsi_assert_io <= '0;
        scsi_assert_cd <= '0;
        scsi_assert_msg <= '0;
        scsi_txbuf <= '0;
        scsi_dma_mode <= '0;
    end
    else begin
        if (~CSn & ~WRn) begin
            case (A[2:1])
                2'b00: begin
                    rsel <= DI[6:0];
                end
                2'b01: ;
                2'b10: begin
                    case (rsel)
                        7'h00: scsi_dout <= DI[7:0];
                        7'h01: begin
                            scsi_assert_rst <= DI[7];
                            scsi_assert_ack <= DI[4];
                            scsi_assert_sel <= DI[2];
                            scsi_assert_atn <= DI[1];
                            scsi_assert_data <= DI[0];
                        end
                        7'h02: begin
                            scsi_dma_mode <= DI[1];
                        end
                        7'h03: begin
                            scsi_assert_msg <= DI[2];
                            scsi_assert_cd <= DI[1];
                            scsi_assert_io <= DI[0];
                        end
                        7'h05: scsi_start_dma_tx <= '1;
                        7'h07: scsi_start_dma_rx <= '1;
                        default: ;
                    endcase
                end
                2'b11: begin
                    case (rsel)
                        7'h05: scsi_txbuf <= DI[7:0];
                        default: ;
                    endcase
                end
            endcase
        end
    end
end

always @(posedge CLK) if (CE) begin
    scsi_reset_int <= '0;
    scsi_rxbuf_rd <= '0;

    if (~RESn) begin
    end
    else begin
        if (~CSn & ~RDn) begin
            case (A[2:1])
                2'b10: begin
                    case (rsel)
                        7'h07: scsi_reset_int <= '1;
                        default: ;
                    endcase
                end
                2'b11: begin
                    case (rsel)
                        7'h05: scsi_rxbuf_rd <= '1;
                        default: ;
                    endcase
                end
                default: ;
            endcase
        end
    end
end

always @* begin
    dout = '0;
    case (A[2])
        1'b0: begin
            dout[6:0] = rsel;
            dout[23:16] = scsi_cur_bus_stat;
        end
        1'b1: begin
            case (rsel)
                7'h00: dout[7:0] = scsi_din;
                7'h01: begin
                    dout[7] = scsi_assert_rst;
                    dout[4] = scsi_assert_ack;
                    dout[2] = scsi_assert_sel;
                    dout[1] = scsi_assert_atn;
                    dout[0] = scsi_assert_data;
                end
                7'h02: begin
                    dout[1] = scsi_dma_mode;
                end
                7'h03: begin
                    dout[2] = scsi_assert_io;
                    dout[1] = scsi_assert_cd;
                    dout[0] = scsi_assert_msg;
                end
                7'h04: dout[7:0] = scsi_cur_bus_stat;
                7'h05: begin
                    dout[23:16] = scsi_rxbuf;
                    dout[6] = scsi_dma_req;
                    dout[4] = scsi_int_req_act;
                    dout[3] = scsi_phase_match;
                    dout[1] = ~SCSI_ATNn;
                    dout[0] = ~SCSI_ACKn;
                end
                7'h06: dout[7:0] = scsi_rxbuf;
                default: ;
            endcase
        end
    endcase
end

assign DO = (~CSn & ~RDn) ? (A[1] ? dout[31:16] : dout[15:0]) : '0;

assign BUSYn = '1; // TODO
assign IRQn = '1; // TODO

//////////////////////////////////////////////////////////////////////
// SCSI interface

logic           scsi_reqn_d;
logic           scsi_assert_ack_dma, scsi_assert_ack_cnt;

// Data transfer engine (for DMA)

wire scsi_req_posedge = ~SCSI_REQn & scsi_reqn_d;

always @(posedge CLK) if (CE) begin
    scsi_reqn_d <= SCSI_REQn;

    if (~RESn) begin
        scsi_rxbuf <= '0;
    end
    else if (scsi_req_posedge) begin
        // Latch DI into RX buffer on REQn assertion.
        scsi_rxbuf <= scsi_din;
    end
end

// REQn assertion or REG.7L write sets REG.5H[6].
// RX buffer readout triggers ACKn pulse and clears REG.5H[6].

assign scsi_dma_req_set = scsi_dma_mode & (scsi_req_posedge | scsi_start_dma_rx);
assign scsi_dma_req_clr = scsi_dma_mode & scsi_rxbuf_rd;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        scsi_dma_req <= '0;
    end
    else begin
        scsi_dma_req <= (scsi_dma_req & ~scsi_dma_req_clr) | scsi_dma_req_set;
    end
end

// Enforce minimum ACKn pulse assertion and negation periods.
always @(posedge CLK) if (CE) begin
    if (~RESn | ~scsi_dma_mode) begin
        scsi_assert_ack_dma <= '0;
        scsi_assert_ack_cnt <= '0;
    end
    else begin
        if (scsi_assert_ack_cnt)
            scsi_assert_ack_cnt <= '0;
        else begin
            if (scsi_dma_req_clr) begin
                scsi_assert_ack_dma <= '1;
                scsi_assert_ack_cnt <= '1;
            end
            else if (scsi_assert_ack_dma) begin
                scsi_assert_ack_dma <= '0;
                scsi_assert_ack_cnt <= '1;
            end
        end
    end
end

// Bus hookups

assign scsi_cur_bus_stat = {~SCSI_RSTn, ~SCSI_BSYn, ~SCSI_REQn, ~SCSI_MSGn,
                            ~SCSI_CDn, ~SCSI_IOn, ~SCSI_SELn, 1'b0};

assign SCSI_DO = scsi_dout;
assign SCSI_DOE = SCSI_IOn & scsi_assert_data;
assign SCSI_ATNn = ~scsi_assert_atn;
assign SCSI_ACKn = ~(scsi_assert_ack | scsi_assert_ack_dma);
assign SCSI_RSTn = ~scsi_assert_rst;
assign SCSI_SELn = ~scsi_assert_sel;

assign scsi_din = SCSI_DI;

endmodule
