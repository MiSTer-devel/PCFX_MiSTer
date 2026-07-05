// HuC6272 (KING)
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`include "huc6272_types.svh"

module huc6272
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

`ifdef HUC6272_DMC_ENABLE

     // DRAM bank A interface
     input [15:0]  RA_DI,
     output [15:0] RA_DO,
     output [8:0]  RA_A,
     output        RA_OEn,
     output        RA_WEn,
     output        RA_RASn,
     output        RA_LCASn,
     output        RA_UCASn,

     // DRAM bank B interface
     input [15:0]  RB_DI,
     output [15:0] RB_DO,
     output [8:0]  RB_A,
     output        RB_OEn,
     output        RB_WEn,
     output        RB_RASn,
     output        RB_LCASn,
     output        RB_UCASn,

`else // ifndef HUC6272_DMC_ENABLE

     // DRAM bank A memory interface
     output [17:0] MA_A,
     input [15:0]  MA_DI,
     output [15:0] MA_DO,
     output [1:0]  MA_BE,
     output        MA_WR,
     output        MA_REQ,
     input         MA_ACK,

     // DRAM bank B memory interface
     output [17:0] MB_A,
     input [15:0]  MB_DI,
     output [15:0] MB_DO,
     output [1:0]  MB_BE,
     output        MB_WR,
     output        MB_REQ,
     input         MB_ACK,

`endif // HUC6272_DMC_ENABLE

     // Video interface
     input         DCK, // pixel clock enable
     input         DCK_NEGEDGE,
     input         HSYNC_POSEDGE,
     input         HSYNC_NEGEDGE,
     input         VSYNC_POSEDGE,
     input         VSYNC_NEGEDGE,
     output [23:0] VD, // [7:0] = palette data / [23:0] = {Y,U,V}
     output        VDE, // data enable (not in blanking)

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

     // K-BUS interface
     output [7:0]  KBUS_DO,
     output        KBUS_RHnL,
     input         KBUS_REQ_C71,
     output        KBUS_ACK_C71,
     output [1:0]  KBUS_CSn_C30
     );

rf_scsi_t       rf_scsi;
rf_bgm_t        rf_bgm;
rf_c71xfer_t    rf_c71xfer;
rf_c30xfer_t    rf_c30xfer;

st_scsi_t       st_scsi;
st_c30xfer_t    st_c30xfer;

wire [9:0]      ROW, COL;

wire            cpuif_m_ba;
wire [17:0]     cpuif_m_a;
wire [15:0]     cpuif_m_di, cpuif_m_do;
wire [1:0]      cpuif_m_be;
wire            cpuif_m_wr, cpuif_m_req, cpuif_m_ack;

wire [17:0]     vid_ma_a;
wire [15:0]     vid_ma_di, vid_ma_do;
wire [1:0]      vid_ma_be;
wire            vid_ma_wr, vid_ma_req, vid_ma_ack;
wire [17:0]     vid_mb_a;
wire [15:0]     vid_mb_di, vid_mb_do;
wire [1:0]      vid_mb_be;
wire            vid_mb_wr, vid_mb_req, vid_mb_ack;

wire [17:0]     dmca_m_a;
wire [15:0]     dmca_m_di, dmca_m_do;
wire [1:0]      dmca_m_be;
wire            dmca_m_wr, dmca_m_req, dmca_m_ack;
wire [17:0]     dmcb_m_a;
wire [15:0]     dmcb_m_di, dmcb_m_do;
wire [1:0]      dmcb_m_be;
wire            dmcb_m_wr, dmcb_m_req, dmcb_m_ack;

wire            c71xfer_m_ba;
wire [17:0]     c71xfer_m_a;
wire [15:0]     c71xfer_m_di, c71xfer_m_do;
wire [1:0]      c71xfer_m_be;
wire            c71xfer_m_wr, c71xfer_m_req, c71xfer_m_ack;

wire            c30xfer_m_ba;
wire [17:0]     c30xfer_m_a;
wire [15:0]     c30xfer_m_di, c30xfer_m_do;
wire [1:0]      c30xfer_m_be;
wire            c30xfer_m_wr, c30xfer_m_req, c30xfer_m_ack;

wor             kbus_rhnl;
wor [7:0]       kbus_do;

//////////////////////////////////////////////////////////////////////
// CPU memory / I/O bus interface

huc6272_cpuif cpuif
   (
    .*,

    .M_BA(cpuif_m_ba),
    .M_A(cpuif_m_a),
    .M_DI(cpuif_m_di),
    .M_DO(cpuif_m_do),
    .M_BE(cpuif_m_be),
    .M_WR(cpuif_m_wr),
    .M_REQ(cpuif_m_req),
    .M_ACK(cpuif_m_ack)
    );

//////////////////////////////////////////////////////////////////////
// DRAM memory controllers

`ifdef HUC6272_DMC_ENABLE

huc6272_dmc dmca
   (
    .*,

    .A(dmca_m_a),
    .DI(dmca_m_di),
    .DO(dmca_m_do),
    .BE(dmca_m_be),
    .WR(dmca_m_wr),
    .REQ(dmca_m_req),
    .ACK(dmca_m_ack),

    .R_DI(RA_DI),
    .R_DO(RA_DO),
    .R_A(RA_A),
    .R_OEn(RA_OEn),
    .R_WEn(RA_WEn),
    .R_RASn(RA_RASn),
    .R_LCASn(RA_LCASn),
    .R_UCASn(RA_UCASn)
    );

huc6272_dmc dmcb
   (
    .*,

    .A(dmcb_m_a),
    .DI(dmcb_m_di),
    .DO(dmcb_m_do),
    .BE(dmcb_m_be),
    .WR(dmcb_m_wr),
    .REQ(dmcb_m_req),
    .ACK(dmcb_m_ack),

    .R_DI(RB_DI),
    .R_DO(RB_DO),
    .R_A(RB_A),
    .R_OEn(RB_OEn),
    .R_WEn(RB_WEn),
    .R_RASn(RB_RASn),
    .R_LCASn(RB_LCASn),
    .R_UCASn(RB_UCASn)
    );

`else // ifndef HUC6272_DMC_ENABLE

// DMC is external to this chip
assign MA_A = dmca_m_a;
assign MA_DO = dmca_m_do;
assign MA_BE = dmca_m_be;
assign MA_WR = dmca_m_wr;
assign MA_REQ = dmca_m_req;
assign dmca_m_di = MA_DI;
assign dmca_m_ack = MA_ACK;

assign MB_A = dmcb_m_a;
assign MB_DO = dmcb_m_do;
assign MB_BE = dmcb_m_be;
assign MB_WR = dmcb_m_wr;
assign MB_REQ = dmcb_m_req;
assign dmcb_m_di = MB_DI;
assign dmcb_m_ack = MB_ACK;

`endif // HUC6272_DMC_ENABLE

//////////////////////////////////////////////////////////////////////
// Memory fabric

huc6272_fabric fabric
   (
    .*
    );

//////////////////////////////////////////////////////////////////////
// SCSI interface

huc6272_scsi scsi
   (
    .*
    );

//////////////////////////////////////////////////////////////////////
// Video interface

huc6272_video video
   (
    .*,

    .MA_A(vid_ma_a),
    .MA_DI(vid_ma_di),
    .MA_DO(vid_ma_do),
    .MA_BE(vid_ma_be),
    .MA_WR(vid_ma_wr),
    .MA_REQ(vid_ma_req),
    .MA_ACK(vid_ma_ack),

    .MB_A(vid_mb_a),
    .MB_DI(vid_mb_di),
    .MB_DO(vid_mb_do),
    .MB_BE(vid_mb_be),
    .MB_WR(vid_mb_wr),
    .MB_REQ(vid_mb_req),
    .MB_ACK(vid_mb_ack)
    );

//////////////////////////////////////////////////////////////////////
// HuC6271 data transfer

logic [7:0]     kbus_do_c71;
logic           kbus_holdn_c71;

huc6272_c71xfer c71xfer
   (
    .*,

    .KBUS_DO(kbus_do_c71),
    .KBUS_REQ(KBUS_REQ_C71),
    .KBUS_ACK(KBUS_ACK_C71),
    .KBUS_HOLDn(kbus_holdn_c71),

    .M_BA(c71xfer_m_ba),
    .M_A(c71xfer_m_a),
    .M_DI(c71xfer_m_di),
    .M_DO(c71xfer_m_do),
    .M_BE(c71xfer_m_be),
    .M_WR(c71xfer_m_wr),
    .M_REQ(c71xfer_m_req),
    .M_ACK(c71xfer_m_ack)
    );

assign kbus_do = kbus_do_c71;

//////////////////////////////////////////////////////////////////////
// HuC6230 data transfer

logic [7:0]     kbus_do_c30;
logic           kbus_rhnl_c30;

huc6272_c30xfer c30xfer
   (
    .*,

    .KBUS_DO(kbus_do_c30),
    .KBUS_RHnL(kbus_rhnl_c30),
    .KBUS_CSn(KBUS_CSn_C30),

    .M_BA(c30xfer_m_ba),
    .M_A(c30xfer_m_a),
    .M_DI(c30xfer_m_di),
    .M_DO(c30xfer_m_do),
    .M_BE(c30xfer_m_be),
    .M_WR(c30xfer_m_wr),
    .M_REQ(c30xfer_m_req),
    .M_ACK(c30xfer_m_ack)
    );

assign kbus_do = kbus_do_c30;
assign kbus_rhnl = kbus_rhnl_c30;

//////////////////////////////////////////////////////////////////////
// K-BUS interface

assign KBUS_DO = kbus_do;
assign KBUS_RHnL = kbus_rhnl;

// C30's have priority over C71
assign kbus_holdn_c71 = &KBUS_CSn_C30;

endmodule

`include "huc6272_cpuif.sv"
`include "huc6272_dmc.sv"
`include "huc6272_fabric.sv"
`include "huc6272_fabric_tee.sv"
`include "huc6272_fabric_bank.sv"
`include "huc6272_scsi.sv"
`include "huc6272_video.sv"
`include "huc6272_fetch.sv"
`include "huc6272_bgm.sv"
`include "huc6272_c71xfer.sv"
`include "huc6272_c30xfer.sv"
