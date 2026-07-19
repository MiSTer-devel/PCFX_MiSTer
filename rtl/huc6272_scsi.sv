// SCSI interface
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_scsi
   (
    input         CLK,
    input         CE,
    input         RESn,

    // SCSI (CD-ROM) interface
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
    input         SCSI_IOn,

    // Register file and status
    input         rf_scsi_t rf_scsi,
    output        st_scsi_t st_scsi,

    // Memory client interface
    output        M_BA,
    output [17:0] M_A,
    input [15:0]  M_DI,
    output [15:0] M_DO,
    output [1:0]  M_BE,
    output        M_WR,
    output        M_REQ,
    input         M_ACK
    );

logic           req_posedge, req_posedge_d;
logic [7:0]     rxbuf, dma_rxbuf;
logic           dma_req, dma_req_set, dma_req_clr;
logic           dma_a0;
logic           dma_rxbuf_rd, dma_end;
logic           dma_next_word;

logic           reqn_d;
logic           assert_ack_dma, assert_ack_cnt;
logic           phase_match;

logic           m_req;
logic [15:0]    m_do;

// Data transfer engine (for DMA)

assign req_posedge = ~SCSI_REQn & reqn_d;

always @(posedge CLK) if (CE) begin
    req_posedge_d <= req_posedge;
    reqn_d <= SCSI_REQn;

    if (~RESn) begin
        rxbuf <= '0;
    end
    else if (req_posedge) begin
        // Latch DI into RX buffer on REQn assertion.
        rxbuf <= st_scsi.din;
    end
end

// REQn assertion or REG.5L write or REG.7L write sets REG.5H[6] .
// RX buffer readout or TX buffer write triggers ACKn pulse and clears REG.5H[6].

assign dma_req_set = rf_scsi.dma_mode & phase_match &
                     (req_posedge_d | rf_scsi.start_dma_rx | rf_scsi.start_dma_tx);
assign dma_req_clr = rf_scsi.dma_mode &
                     (dma_rxbuf_rd | rf_scsi.rxbuf_rd | rf_scsi.txbuf_wr);

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        dma_req <= '0;
    end
    else begin
        dma_req <= (dma_req & ~dma_req_clr) | dma_req_set;
    end
end

// Buffer RX buffer input for word DMA transfer to KRAM
always @(posedge CLK) begin
    if (~RESn) begin
        dma_a0 <= '0;
        dma_rxbuf <= '0;
        dma_rxbuf_rd <= '0;
        dma_next_word <= '0;
        dma_end <= '0;
        m_do <= '0;
        m_req <= '0;
    end
    else begin
        if (CE) begin
            dma_rxbuf_rd <= '0;
            dma_next_word <= '0;

            if (~rf_scsi.dma_en) begin
                dma_a0 <= '0;
            end
            else if (rf_scsi.dma_en & dma_req_set) begin
                if (rf_scsi.start_dma_rx | rf_scsi.start_dma_tx)
                    $display("huc6272_scsi: rf_scsi.dma_kba=%x, .dma_ka=%x, .dma_byte_cnt=%x", 
                             rf_scsi.dma_kba, rf_scsi.dma_ka, rf_scsi.dma_byte_cnt);
                dma_a0 <= ~dma_a0;
                if (~dma_a0) begin
                    dma_rxbuf <= rxbuf;
                    dma_rxbuf_rd <= '1;
                end
                else begin
                    m_do <= {rxbuf, dma_rxbuf};
                    m_req <= '1;
                end
            end
            if (rf_scsi.reset_dma_end_int)
                dma_end <= '0;
        end

        if (m_req & M_ACK) begin
            m_req <= '0;
            dma_rxbuf_rd <= '1;
            dma_next_word <= '1;
            dma_end <= (rf_scsi.dma_byte_cnt == 17'd1);
        end
    end
end

wire [17:1] dma_byte_cnt = rf_scsi.dma_byte_cnt; // debug aid

// Enforce minimum ACKn pulse assertion and negation periods.
always @(posedge CLK) if (CE) begin
    if (~RESn | ~rf_scsi.dma_mode) begin
        assert_ack_dma <= '0;
        assert_ack_cnt <= '0;
    end
    else begin
        if (assert_ack_cnt)
            assert_ack_cnt <= '0;
        else begin
            if (dma_req_clr) begin
                assert_ack_dma <= '1;
                assert_ack_cnt <= '1;
            end
            else if (assert_ack_dma) begin
                assert_ack_dma <= '0;
                assert_ack_cnt <= '1;
            end
        end
    end
end

// Bus phase match detection
assign phase_match = (~SCSI_IOn == rf_scsi.assert_io) &
                     (~SCSI_CDn == rf_scsi.assert_cd) &
                     (~SCSI_MSGn == rf_scsi.assert_msg);

// Bus hookups
assign SCSI_DO = rf_scsi.dout;
assign SCSI_DOE = SCSI_IOn & rf_scsi.assert_data;
assign SCSI_ATNn = ~rf_scsi.assert_atn;
assign SCSI_ACKn = ~(rf_scsi.assert_ack | assert_ack_dma);
assign SCSI_RSTn = ~rf_scsi.assert_rst;
assign SCSI_SELn = ~rf_scsi.assert_sel;

// Status outputs
assign st_scsi.cur_bus_stat = {~SCSI_RSTn, ~SCSI_BSYn, ~SCSI_REQn, ~SCSI_MSGn,
                               ~SCSI_CDn, ~SCSI_IOn, ~SCSI_SELn, 1'b0};
assign st_scsi.atn = ~SCSI_ATNn;
assign st_scsi.ack = ~SCSI_ACKn;
assign st_scsi.din = SCSI_DI;
assign st_scsi.rxbuf = rxbuf;
assign st_scsi.dma_req = dma_req;
assign st_scsi.int_req_act = '0; // TODO
assign st_scsi.dma_next = dma_next_word;
assign st_scsi.dma_end = dma_end;
assign st_scsi.phase_match = phase_match;

// KRAM memory client interface
wire page = 1'b0; // TODO: wire up to R.0F

assign M_BA = rf_scsi.dma_kba;
assign M_A = {page, rf_scsi.dma_ka};
assign M_DO = m_do;
assign M_BE = '1;
assign M_WR = '1;
assign M_REQ = m_req;

endmodule
