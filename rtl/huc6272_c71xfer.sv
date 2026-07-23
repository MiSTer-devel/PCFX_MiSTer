// HuC6272 (KING) -> HuC6271 data transfer
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_c71xfer
   (
    input         CLK,
    input         CE,
    input         RESn,

    // Register file
    input         rf_c71xfer_t rf_c71xfer,
    output        st_c71xfer_t st_c71xfer,

    // Video status
    input [9:0]   ROW,
    input [9:0]   COL,

    // K-BUS interface
    output [7:0]  KBUS_DO,
    input         KBUS_REQ,
    output        KBUS_ACK,
    input         KBUS_HOLDn,

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
logic           start_raster_match, raster_mon_match;
logic           start;
logic           act;
logic [3:0]     row_cnt; // down counter
logic [4:0]     block_cnt; // up counter
logic [16:0]    addr;
logic           rm_int;
logic           kbus_ack;
logic [15:0]    m_di;
logic           m_req, m_a0, m_ready;
`ifdef HUC6272_DUMP_C71XFER
integer         fdat = -1;
integer         blknum = 0;
string          fname;
`endif

assign row_start = (COL == '0);
assign row_start_trig = row_start & ~row_start_d;
assign start_raster_match = (ROW[8:0] == rf_c71xfer.tsr);
assign raster_mon_match = (ROW[8:0] == rf_c71xfer.rm);
assign start = row_start_trig & start_raster_match;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        row_start_d <= '0;
        act <= '0;
        row_cnt <= '0;
        block_cnt <= '0;
        addr <= '0;
        rm_int <= '0;
    end
    else begin
        row_start_d <= row_start;

        if (start & rf_c71xfer.ren) begin
`ifdef HUC6272_DUMP_C71XFER
            $sformat(fname, "bootvid/blk%03d.bin", blknum);
            blknum += 1;
            if (fdat != -1)
                $fclose(fdat);
            fdat = $fopen(fname, "wb");
`endif
            act <= '1;
            row_cnt <= '1;
            block_cnt <= '0;
            addr <= rf_c71xfer.ka;
        end
        if (act) begin
            if (row_start_trig) begin
                if (row_cnt == '0) begin
                    if ((block_cnt + 1'd1) == rf_c71xfer.tbc) begin
                        act <= '0;
                    end
                    block_cnt <= block_cnt + 1'd1;
                end
                row_cnt <= row_cnt - 1'd1;
            end
            if (KBUS_ACK & m_a0)
                addr <= addr + 1'd1;
        end

        if (rf_c71xfer.rint & row_start_trig & raster_mon_match)
            rm_int <= '1;
        else if (~rf_c71xfer.rint)
            rm_int <= '0;
    end
end

always @(posedge CLK) begin
    if (~RESn) begin
        m_di <= '0;
        m_req <= '0;
        m_a0 <= '0;
        m_ready <= '0;
        kbus_ack <= '0;
    end
    else begin
        if (act & KBUS_REQ & ~m_ready & ~m_req)
            m_req <= '1;
        else if (m_req & M_ACK) begin
            m_req <= '0;
            m_di <= M_DI;
            m_ready <= '1;
        end

        if (CE) begin
            if (KBUS_REQ & ~kbus_ack & m_ready)
                kbus_ack <= '1;
            else if (KBUS_ACK) begin
`ifdef HUC6272_DUMP_C71XFER
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

assign st_c71xfer.rm_int = rm_int;

wire [7:0] kbus_do = ~m_a0 ? m_di[0+:8] : m_di[8+:8];
wire kbus_doe = kbus_ack & KBUS_HOLDn;

assign KBUS_DO = kbus_doe ? kbus_do : '0;
assign KBUS_ACK = kbus_doe;

assign M_BA = rf_c71xfer.kba;
assign M_A = {rf_c71xfer.kpage, addr};
assign M_DO = '0;
assign M_BE = '1;
assign M_WR = '0;
assign M_REQ = m_req;

`ifdef HUC6272_DUMP_C71XFER
final
    if (fdat != -1)
        $fclose(fdat);
`endif

endmodule
