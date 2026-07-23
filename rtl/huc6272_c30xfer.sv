// HuC6272 (KING) -> HuC6230 data transfer
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_c30xfer
   (
    input         CLK,
    input         CE,
    input         RESn,

    // Register file and status
    input         rf_c30xfer_t rf_c30xfer,
    output        st_c30xfer_t st_c30xfer,

    // Video status
    input [9:0]   COL,

    // K-BUS interface
    output [7:0]  KBUS_DO,
    output        KBUS_RHnL,
    output [1:0]  KBUS_CSn,

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

logic           row_start, row_start_d, row_start_trig;
logic           start;
logic [2:1]     act, ren;
logic           csel; // select ADPCM #1/#2
logic [2:0]     row_cnt; // up counter
logic           row_cnt_wrap;
logic [16:0]    addr1, addr2;
logic [2:1]     send, shlf;
logic           kbus_ack;
logic [15:0]    m_di;
logic           m_req, m_a0, m_ready;
`ifdef HUC6272_DUMP_C30XFER
integer         fdat = -1;
`endif

assign row_start = (COL == '0);
assign row_start_trig = row_start & ~row_start_d;
assign row_cnt_wrap = row_cnt == 3'((2 << rf_c30xfer.div) - 1);
assign start = row_start_trig & row_cnt_wrap;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        row_start_d <= '0;
        act <= '0;
        ren <= '0;
        csel <= '0;
        row_cnt <= '0;
        addr1 <= '0;
        addr2 <= '0;
        send <= '0;
        shlf <= '0;
    end
    else begin
        row_start_d <= row_start;
        row_cnt <= row_cnt_wrap ? '0 : row_cnt + 1'd1;

        if (rf_c30xfer.reset_int) begin
            send <= '0;
            shlf <= '0;
        end
        if (rf_c30xfer.ren_ws) begin
            ren <= rf_c30xfer.ren;
            if (~ren[1] & rf_c30xfer.ren[1])
                addr1 <= {rf_c30xfer.kasta1, 8'b0};
            if (~ren[2] & rf_c30xfer.ren[2])
                addr2 <= {rf_c30xfer.kasta2, 8'b0};
        end
        if (start & |ren) begin
`ifdef HUC6272_DUMP_C30XFER
            if (fdat == -1)
                fdat = $fopen("bootvid/snd.bin", "wb");
`endif
            act <= ren;
            csel <= ~ren[1];
        end
        if (act[1]) begin
            if (~KBUS_CSn[0] & KBUS_RHnL) begin
                if (addr1 == {rf_c30xfer.kahlf1, 6'b0})
                    shlf[1] <= '1;
                if (addr1 == rf_c30xfer.kaend1) begin
                    ren[1] <= '0;
                    send[1] <= '1;
                end
                addr1 <= addr1 + 1'd1;
                act[1] <= '0;
                csel <= '1;
            end
        end
        if (act[2]) begin
            if (~KBUS_CSn[1] & KBUS_RHnL) begin
                if (addr2 == {rf_c30xfer.kahlf2, 6'b0})
                    shlf[2] <= '1;
                if (addr2 == rf_c30xfer.kaend2) begin
                    ren[2] <= '0;
                    send[2] <= '1;
                end
                addr2 <= addr2 + 1'd1;
                act[2] <= '0;
            end
        end
    end
end

// Interrupt flags
wire [3:0] isr = {send, shlf};
wire [3:0] imr = {rf_c30xfer.bend, rf_c30xfer.bhlf};
assign st_c30xfer.send = send;
assign st_c30xfer.shlf = shlf;
assign st_c30xfer.act_int = |(isr & imr);

always @(posedge CLK) begin
    if (~RESn) begin
        m_di <= '0;
        m_req <= '0;
        m_a0 <= '0;
        m_ready <= '0;
        kbus_ack <= '0;
    end
    else begin
        if (|act & ~m_ready & ~m_req)
            m_req <= '1;
        else if (m_req & M_ACK) begin
            m_req <= '0;
            m_di <= M_DI;
            m_ready <= '1;
        end

        if (CE) begin
            if (~kbus_ack & m_ready)
                kbus_ack <= '1;
            else if (kbus_ack) begin
`ifdef HUC6272_DUMP_C30XFER
                $fwrite(fdat, "%c", KBUS_DO);
`endif
                kbus_ack <= '0;
                if (m_a0)
                    m_ready <= '0;
                m_a0 <= ~m_a0;
            end
        end
    end
end

wire [7:0] kbus_do = ~m_a0 ? m_di[0+:8] : m_di[8+:8];
wire kbus_doe = kbus_ack;

assign KBUS_DO = kbus_doe ? kbus_do : '0;
assign KBUS_RHnL = kbus_doe & m_a0;
assign KBUS_CSn = ~({2{kbus_doe}} & {csel, ~csel});

assign M_BA = csel ? rf_c30xfer.kba2 : rf_c30xfer.kba1;
assign M_A = {rf_c30xfer.kpage, csel ? addr2 : addr1};
assign M_DO = '0;
assign M_BE = '1;
assign M_WR = '0;
assign M_REQ = m_req;

`ifdef HUC6272_DUMP_C30XFER
final
    if (fdat != -1)
        $fclose(fdat);
`endif

endmodule
