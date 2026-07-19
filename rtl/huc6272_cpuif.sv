// CPU memory / I/O bus interface
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_cpuif
   (
    input         CLK,
    input         CE,
    input         RESn,

    // CPU memory / I/O bus interface
    input [2:1]   A,
    input [15:0]  DI,
    output [15:0] DO,
    input         CSn,
    input         WRn,
    input         RDn,
    output        BUSYn,
    output        IRQn,

    // Register files
    output        rf_scsi_t rf_scsi,
    output        rf_bgm_t rf_bgm,
    output        rf_c71xfer_t rf_c71xfer,
    output        rf_c30xfer_t rf_c30xfer,

    // Status
    input         st_scsi_t st_scsi,
    input         st_c30xfer_t st_c30xfer,

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

typedef struct packed {
    logic               page; // KA[17]
    logic [2:0]         _res28;
    logic signed [9:0]  ainc;
    logic               bank; // -A/B
    logic [16:0]        addr; // KA[16:0]
} kradr_t;

logic [6:0]     rsel;
logic [31:0]    dout;
logic           rbusy;

logic           scsi_reset_int, scsi_reset_dma_end_int;
logic           scsi_start_dma_tx, scsi_start_dma_rx;
logic           scsi_rxbuf_rd, scsi_txbuf_wr;
logic           c30xfer_ren_ws;
logic           c30xfer_reset_int;

kradr_t         krra, krwa;
logic [15:0]    krd;
logic           krwr_pend;
logic           krrd_act, krwr_act;
logic           krrd_done;
kradr_t         kra;

logic           mpwr_pend;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        rsel <= '0;
        rf_scsi <= '0;
        rf_bgm <= '0;
        rf_c71xfer <= '0;
        rf_c30xfer <= '0;
        krra <= '0;
        krwa <= '0;
        krd <= '0;
        krwr_pend <= '0;
        krwr_act <= '0;
        krrd_done <= '0;
        mpwr_pend <= '0;
        scsi_reset_int <= '0;
        scsi_reset_dma_end_int <= '0;
        scsi_start_dma_tx <= '0;
        scsi_start_dma_rx <= '0;
        scsi_rxbuf_rd <= '0;
        scsi_txbuf_wr <= '0;
        c30xfer_ren_ws <= '0;
        c30xfer_reset_int <= '0;
    end
    else begin
        if (~CSn & ~WRn & BUSYn) begin
            case (A[2:1])
                2'b00: begin
                    rsel <= DI[6:0];
                end
                2'b01: ;
                2'b10: begin
                    case (rsel)
                        7'h00: rf_scsi.dout <= DI[7:0];
                        7'h01: begin
                            rf_scsi.assert_rst <= DI[7];
                            rf_scsi.assert_ack <= DI[4];
                            rf_scsi.assert_sel <= DI[2];
                            rf_scsi.assert_atn <= DI[1];
                            rf_scsi.assert_data <= DI[0];
                        end
                        7'h02: begin
                            rf_scsi.dma_mode <= DI[1];
                        end
                        7'h03: begin
                            rf_scsi.assert_msg <= DI[2];
                            rf_scsi.assert_cd <= DI[1];
                            rf_scsi.assert_io <= DI[0];
                        end
                        7'h05: scsi_start_dma_tx <= '1;
                        7'h07: scsi_start_dma_rx <= '1;
                        7'h09: rf_scsi.dma_ka[15:0] <= DI;
                        7'h0a: rf_scsi.dma_byte_cnt[15:1] <= DI[15:1];
                        7'h0b: begin
                            rf_scsi.dma_en <= DI[0];
                            rf_scsi.dma_int_en <= DI[1];
                        end
                        7'h0c: krra[0+:16] <= DI;
                        7'h0d: krwa[0+:16] <= DI;
                        7'h0e: begin
                            krd <= DI;
                            krwr_pend <= '1;
                        end
                        7'h10: begin
                            rf_bgm.bgp[0].format <= bg_format_t'(DI[00+:4]);
                            rf_bgm.bgp[1].format <= bg_format_t'(DI[04+:4]);
                            rf_bgm.bgp[2].format <= bg_format_t'(DI[08+:4]);
                            rf_bgm.bgp[3].format <= bg_format_t'(DI[12+:4]);
                        end
                        7'h12: begin
                            rf_bgm.bgp[0].prio <= DI[0+:3];
                            rf_bgm.bgp[1].prio <= DI[3+:3];
                            rf_bgm.bgp[2].prio <= DI[6+:3];
                            rf_bgm.bgp[3].prio <= DI[9+:3];
                            rf_bgm.rsw <= DI[12];
                        end
                        7'h13: begin
                            rf_bgm.mpwa <= DI[3:0];
                        end
                        7'h14: begin
                            rf_bgm.mpwd <= DI[8:0];
                            mpwr_pend <= '1;
                        end
                        7'h15: rf_bgm.mpsw <= DI[0];
                        7'h16: rf_bgm.sub_wrap <= DI[3:0];
                        7'h20: rf_bgm.bgp[0].bat <= DI[7:0];
                        7'h21: rf_bgm.bgp[0].cg <= DI[7:0];
                        7'h22: rf_bgm.sub_bat0 <= DI[7:0];
                        7'h23: rf_bgm.sub_cg0 <= DI[7:0];
                        7'h24: rf_bgm.bgp[1].bat <= DI[7:0];
                        7'h25: rf_bgm.bgp[1].cg <= DI[7:0];
                        7'h28: rf_bgm.bgp[2].bat <= DI[7:0];
                        7'h29: rf_bgm.bgp[2].cg <= DI[7:0];
                        7'h2a: rf_bgm.bgp[3].bat <= DI[7:0];
                        7'h2b: rf_bgm.bgp[3].cg <= DI[7:0];
                        7'h2c: begin
                            rf_bgm.bgp[0].size_m <= DI[0+:4];
                            rf_bgm.bgp[0].size_n <= DI[4+:4];
                            rf_bgm.size_sub_m0 <= DI[8+:4];
                            rf_bgm.size_sub_n0 <= DI[12+:4];
                        end
                        7'h2d: begin
                            rf_bgm.bgp[1].size_m <= DI[0+:4];
                            rf_bgm.bgp[1].size_n <= DI[4+:4];
                        end
                        7'h2e: begin
                            rf_bgm.bgp[2].size_m <= DI[0+:4];
                            rf_bgm.bgp[2].size_n <= DI[4+:4];
                        end
                        7'h2f: begin
                            rf_bgm.bgp[3].size_m <= DI[0+:4];
                            rf_bgm.bgp[3].size_n <= DI[4+:4];
                        end
                        7'h30: rf_bgm.bgp[0].bsx <= DI[10:0];
                        7'h31: rf_bgm.bgp[0].bsy <= DI[10:0];
                        7'h32: rf_bgm.bgp[1].bsx <= {1'b0, DI[9:0]};
                        7'h33: rf_bgm.bgp[1].bsy <= {1'b0, DI[9:0]};
                        7'h34: rf_bgm.bgp[2].bsx <= {1'b0, DI[9:0]};
                        7'h35: rf_bgm.bgp[2].bsy <= {1'b0, DI[9:0]};
                        7'h36: rf_bgm.bgp[3].bsx <= {1'b0, DI[9:0]};
                        7'h37: rf_bgm.bgp[3].bsy <= {1'b0, DI[9:0]};
                        7'h40: begin
                            rf_c71xfer.ren <= DI[0];
                            rf_c71xfer.rint <= DI[1];
                        end
                        7'h41: rf_c71xfer.ka[15:0] <= DI;
                        7'h42: rf_c71xfer.tsr <= DI[8:0];
                        7'h43: rf_c71xfer.tbc <= DI[4:0];
                        7'h44: rf_c71xfer.rm <= DI[8:0];
                        7'h50: begin
                            c30xfer_ren_ws <= '1;
                            rf_c30xfer.ren <= DI[1:0];
                            rf_c30xfer.div <= DI[3:2];
                        end
                        7'h51: begin
                            rf_c30xfer.rng[1] <= DI[0];
                            rf_c30xfer.bend[1] <= DI[1];
                            rf_c30xfer.bhlf[1] <= DI[2];
                        end
                        7'h52: begin
                            rf_c30xfer.rng[2] <= DI[0];
                            rf_c30xfer.bend[2] <= DI[1];
                            rf_c30xfer.bhlf[2] <= DI[2];
                        end
                        7'h58: begin
                            rf_c30xfer.kba1 <= DI[9];
                            rf_c30xfer.kasta1[16:8] <= DI[8:0];
                        end
                        7'h59: rf_c30xfer.kaend1[15:0] <= DI[15:0];
                        7'h5a: rf_c30xfer.kahlf1[16:6] <= DI[10:0]; // drop A/-B
                        7'h5c: begin
                            rf_c30xfer.kba2 <= DI[9];
                            rf_c30xfer.kasta2[16:8] <= DI[8:0];
                        end
                        7'h5d: rf_c30xfer.kaend2[15:0] <= DI[15:0];
                        7'h5e: rf_c30xfer.kahlf2[16:6] <= DI[10:0]; // drop A/-B
                        default: ;
                    endcase
                end
                2'b11: begin
                    case (rsel)
                        7'h05: begin
                            rf_scsi.txbuf <= DI[7:0];
                            scsi_txbuf_wr <= '1;
                        end
                        7'h09: begin
                            rf_scsi.dma_kba <= DI[1];
                            rf_scsi.dma_ka[16] <= DI[0];
                        end
                        7'h0a: rf_scsi.dma_byte_cnt[17:16] <= DI[1:0];
                        7'h0c: krra[16+:16] <= DI;
                        7'h0d: krwa[16+:16] <= DI;
                        7'h0e: begin
                            krd <= DI;
                            krwr_pend <= '1;
                        end
                        7'h41: begin
                            rf_c71xfer.kba <= DI[1];
                            rf_c71xfer.ka[16] <= DI[0];
                        end
                        7'h59: rf_c30xfer.kaend1[16] <= DI[0]; // drop A/-B
                        7'h5d: rf_c30xfer.kaend2[16] <= DI[0]; // drop A/-B
                        default: ;
                    endcase
                end
            endcase
        end
        else begin
            if (mpwr_pend) begin
                mpwr_pend <= '0;
                rf_bgm.mpwr <= '1;
            end
            else if (rf_bgm.mpwr) begin
                rf_bgm.mpwr <= '0;
                rf_bgm.mpwa <= rf_bgm.mpwa + 1'd1;
            end

            if (krwr_pend) begin
                krwr_pend <= '0;
                krwr_act <= '1;
            end

            c30xfer_ren_ws <= '0;
            rf_c30xfer.ren_ws <= c30xfer_ren_ws;

            scsi_start_dma_tx <= '0;
            rf_scsi.start_dma_tx <= scsi_start_dma_tx;

            scsi_start_dma_rx <= '0;
            rf_scsi.start_dma_rx <= scsi_start_dma_rx;

            scsi_txbuf_wr <= '0;
            rf_scsi.txbuf_wr <= scsi_txbuf_wr;

            if (st_scsi.dma_end)
                rf_scsi.dma_en <= '0;
        end

        if (~CSn & ~RDn) begin
            case (A[2:1])
                2'b10: begin
                    case (rsel)
                        7'h07: scsi_reset_int <= '1;
                        7'h0b: scsi_reset_dma_end_int <= '1;
                        7'h53: c30xfer_reset_int <= '1;
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
        else begin
            krrd_done <= '0;

            scsi_reset_int <= '0;
            rf_scsi.reset_int <= scsi_reset_int;

            scsi_reset_dma_end_int <= '0;
            rf_scsi.reset_dma_end_int <= scsi_reset_dma_end_int;

            scsi_rxbuf_rd <= '0;
            rf_scsi.rxbuf_rd <= scsi_rxbuf_rd;

            c30xfer_reset_int <= '0;
            rf_c30xfer.reset_int <= c30xfer_reset_int;
        end

        if (krrd_act & M_ACK) begin
            krd <= M_DI;
            krrd_done <= '1;
            krra.addr += 16'(krra.ainc);
        end
        if (krwr_act & M_ACK) begin
            krwr_act <= '0;
            krwa.addr += 16'(krwa.ainc);
        end
        if (st_scsi.dma_next) begin
            rf_scsi.dma_byte_cnt <= rf_scsi.dma_byte_cnt - 1'd1;
            rf_scsi.dma_ka <= rf_scsi.dma_ka + 1'd1;
        end
    end
end

always @* begin
    krrd_act = '0;

    if (RESn) begin
        if (~CSn & ~RDn) begin
            case (A[2:1])
                2'b10: begin
                    case (rsel)
                        7'h0e: krrd_act = ~krrd_done;
                        default: ;
                    endcase
                end
                2'b11: begin
                    case (rsel)
                        7'h0e: krrd_act = ~krrd_done;
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
    rbusy = '0;
    case (A[2])
        1'b0: begin
            dout[6:0] = rsel;
            dout[23:16] = st_scsi.cur_bus_stat;
        end
        1'b1: begin
            case (rsel)
                7'h00: dout[7:0] = st_scsi.din;
                7'h01: begin
                    dout[7] = rf_scsi.assert_rst;
                    dout[4] = rf_scsi.assert_ack;
                    dout[2] = rf_scsi.assert_sel;
                    dout[1] = rf_scsi.assert_atn;
                    dout[0] = rf_scsi.assert_data;
                end
                7'h02: begin
                    dout[1] = rf_scsi.dma_mode;
                end
                7'h03: begin
                    dout[2] = rf_scsi.assert_io;
                    dout[1] = rf_scsi.assert_cd;
                    dout[0] = rf_scsi.assert_msg;
                end
                7'h04: dout[7:0] = st_scsi.cur_bus_stat;
                7'h05: begin
                    dout[23:16] = st_scsi.rxbuf;
                    dout[6] = st_scsi.dma_req;
                    dout[4] = st_scsi.int_req_act;
                    dout[3] = st_scsi.phase_match;
                    dout[1] = st_scsi.atn;
                    dout[0] = st_scsi.ack;
                end
                7'h06: dout[7:0] = st_scsi.rxbuf;
                7'h09: begin
                    dout[17] = rf_scsi.dma_kba;
                    dout[16:0] = rf_scsi.dma_ka;
                end
                7'h0a: dout[17:1] = rf_scsi.dma_byte_cnt[17:1];
                7'h0b: dout[0] = st_scsi.dma_end;
                7'h0c: dout = krra;
                7'h0d: begin
                    dout = krwa;
                    rbusy = '1;
                end
                7'h0e: begin
                    dout = {2{krd}};
                    rbusy = '1;
                end
                7'h53: begin
                    dout[0] = st_c30xfer.send[1];
                    dout[1] = st_c30xfer.shlf[1];
                    dout[2] = st_c30xfer.send[2];
                    dout[3] = st_c30xfer.shlf[2];
                end
                default: ;
            endcase
        end
    endcase
end

assign DO = (~CSn & ~RDn) ? (A[1] ? dout[31:16] : dout[15:0]) : '0;

assign BUSYn = ~((~CSn & (~RDn | ~WRn)) & rbusy & (krrd_act | krwr_act));
assign IRQn = '1; // TODO

always @* begin
    kra = '0;
    if (krrd_act)
        kra = krra;
    else if (krwr_act)
        kra = krwa;
end

assign M_BA = kra.bank;
assign M_A = {kra.page, kra.addr};
assign M_DO = krd;
assign M_BE = '1;
assign M_WR = krwr_act;
assign M_REQ = krrd_act | krwr_act;

endmodule
