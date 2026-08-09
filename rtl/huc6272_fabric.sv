// Memory fabric
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_fabric
   (
    input         CLK,
    input         RESn,
    input         DCK,

    input         cpuif_m_ba,
    input [17:0]  cpuif_m_a,
    output [15:0] cpuif_m_di,
    input [15:0]  cpuif_m_do,
    input [1:0]   cpuif_m_be,
    input         cpuif_m_wr, 
    input         cpuif_m_req, 
    output        cpuif_m_ack,

    input [17:0]  vid_ma_a,
    output [15:0] vid_ma_di,
    input [15:0]  vid_ma_do,
    input [1:0]   vid_ma_be,
    input         vid_ma_wr,
    input         vid_ma_req, 
    output        vid_ma_ack,

    input [17:0]  vid_mb_a,
    output [15:0] vid_mb_di,
    input [15:0]  vid_mb_do,
    input [1:0]   vid_mb_be,
    input         vid_mb_wr,
    input         vid_mb_req, 
    output        vid_mb_ack,

    input         scsi_m_ba,
    input [17:0]  scsi_m_a,
    output [15:0] scsi_m_di,
    input [15:0]  scsi_m_do,
    input [1:0]   scsi_m_be,
    input         scsi_m_wr,
    input         scsi_m_req,
    output        scsi_m_ack,

    input         c71xfer_m_ba,
    input [17:0]  c71xfer_m_a,
    output [15:0] c71xfer_m_di,
    input [15:0]  c71xfer_m_do,
    input [1:0]   c71xfer_m_be,
    input         c71xfer_m_wr,
    input         c71xfer_m_req,
    output        c71xfer_m_ack,

    input         c30xfer_m_ba,
    input [17:0]  c30xfer_m_a,
    output [15:0] c30xfer_m_di,
    input [15:0]  c30xfer_m_do,
    input [1:0]   c30xfer_m_be,
    input         c30xfer_m_wr,
    input         c30xfer_m_req,
    output        c30xfer_m_ack,

    output [17:0] dmca_m_a,
    input [15:0]  dmca_m_di, 
    output [15:0] dmca_m_do,
    output [1:0]  dmca_m_be,
    output        dmca_m_wr, 
    output        dmca_m_req, 
    input         dmca_m_ack,

    output [17:0] dmcb_m_a,
    input [15:0]  dmcb_m_di, 
    output [15:0] dmcb_m_do,
    output [1:0]  dmcb_m_be,
    output        dmcb_m_wr, 
    output        dmcb_m_req, 
    input         dmcb_m_ack
    );

//////////////////////////////////////////////////////////////////////
// Tees for clients that have a bank select bit

wire [15:0]   cpuif_ma_di, cpuif_mb_di;
wire          cpuif_ma_req, cpuif_mb_req;
wire          cpuif_ma_ack, cpuif_mb_ack;

wire [15:0]   scsi_ma_di, scsi_mb_di;
wire          scsi_ma_req, scsi_mb_req;
wire          scsi_ma_ack, scsi_mb_ack;

wire [15:0]   c71xfer_ma_di, c71xfer_mb_di;
wire          c71xfer_ma_req, c71xfer_mb_req;
wire          c71xfer_ma_ack, c71xfer_mb_ack;

wire [15:0]   c30xfer_ma_di, c30xfer_mb_di;
wire          c30xfer_ma_req, c30xfer_mb_req;
wire          c30xfer_ma_ack, c30xfer_mb_ack;

huc6272_fabric_tee cpuif
   (
    .M_BA(cpuif_m_ba),
    .M_DI(cpuif_m_di),
    .M_REQ(cpuif_m_req), 
    .M_ACK(cpuif_m_ack),

    .MA_DI(cpuif_ma_di),
    .MA_REQ(cpuif_ma_req), 
    .MA_ACK(cpuif_ma_ack),

    .MB_DI(cpuif_mb_di),
    .MB_REQ(cpuif_mb_req), 
    .MB_ACK(cpuif_mb_ack)
    );

huc6272_fabric_tee scsi
   (
    .M_BA(scsi_m_ba),
    .M_DI(scsi_m_di),
    .M_REQ(scsi_m_req),
    .M_ACK(scsi_m_ack),

    .MA_DI(scsi_ma_di),
    .MA_REQ(scsi_ma_req),
    .MA_ACK(scsi_ma_ack),

    .MB_DI(scsi_mb_di),
    .MB_REQ(scsi_mb_req),
    .MB_ACK(scsi_mb_ack)
    );

huc6272_fabric_tee c71xfer
   (
    .M_BA(c71xfer_m_ba),
    .M_DI(c71xfer_m_di),
    .M_REQ(c71xfer_m_req),
    .M_ACK(c71xfer_m_ack),

    .MA_DI(c71xfer_ma_di),
    .MA_REQ(c71xfer_ma_req),
    .MA_ACK(c71xfer_ma_ack),

    .MB_DI(c71xfer_mb_di),
    .MB_REQ(c71xfer_mb_req),
    .MB_ACK(c71xfer_mb_ack)
    );

huc6272_fabric_tee c30xfer
   (
    .M_BA(c30xfer_m_ba),
    .M_DI(c30xfer_m_di),
    .M_REQ(c30xfer_m_req),
    .M_ACK(c30xfer_m_ack),

    .MA_DI(c30xfer_ma_di),
    .MA_REQ(c30xfer_ma_req),
    .MA_ACK(c30xfer_ma_ack),

    .MB_DI(c30xfer_mb_di),
    .MB_REQ(c30xfer_mb_req),
    .MB_ACK(c30xfer_mb_ack)
    );

//////////////////////////////////////////////////////////////////////
// Per-bank multiplexers

huc6272_fabric_bank #(.CN(5)) fba
   (
    .*,

    .cm_a('{vid_ma_a, c30xfer_m_a, c71xfer_m_a, scsi_m_a, cpuif_m_a}),
    .cm_di('{vid_ma_di, c30xfer_ma_di, c71xfer_ma_di, scsi_ma_di, cpuif_ma_di}),
    .cm_do('{vid_ma_do, c30xfer_m_do, c71xfer_m_do, scsi_m_do, cpuif_m_do}),
    .cm_be('{vid_ma_be, c30xfer_m_be, c71xfer_m_be, scsi_m_be, cpuif_m_be}),
    .cm_wr('{vid_ma_wr, c30xfer_m_wr, c71xfer_m_wr, scsi_m_wr, cpuif_m_wr}),
    .cm_req('{vid_ma_req, c30xfer_ma_req, c71xfer_ma_req, scsi_ma_req, cpuif_ma_req}),
    .cm_ack('{vid_ma_ack, c30xfer_ma_ack, c71xfer_ma_ack, scsi_ma_ack, cpuif_ma_ack}),

    .dmc_m_a(dmca_m_a),
    .dmc_m_di(dmca_m_di),
    .dmc_m_do(dmca_m_do),
    .dmc_m_be(dmca_m_be),
    .dmc_m_wr(dmca_m_wr),
    .dmc_m_req(dmca_m_req),
    .dmc_m_ack(dmca_m_ack)
    );

huc6272_fabric_bank #(.CN(5)) fbb
   (
    .*,

    .cm_a('{vid_mb_a, c30xfer_m_a, c71xfer_m_a, scsi_m_a, cpuif_m_a}),
    .cm_di('{vid_mb_di, c30xfer_mb_di, c71xfer_mb_di, scsi_mb_di, cpuif_mb_di}),
    .cm_do('{vid_mb_do, c30xfer_m_do, c71xfer_m_do, scsi_m_do, cpuif_m_do}),
    .cm_be('{vid_mb_be, c30xfer_m_be, c71xfer_m_be, scsi_m_be, cpuif_m_be}),
    .cm_wr('{vid_mb_wr, c30xfer_m_wr, c71xfer_m_wr, scsi_m_wr, cpuif_m_wr}),
    .cm_req('{vid_mb_req, c30xfer_mb_req, c71xfer_mb_req, scsi_mb_req, cpuif_mb_req}),
    .cm_ack('{vid_mb_ack, c30xfer_mb_ack, c71xfer_mb_ack, scsi_mb_ack, cpuif_mb_ack}),

    .dmc_m_a(dmcb_m_a),
    .dmc_m_di(dmcb_m_di),
    .dmc_m_do(dmcb_m_do),
    .dmc_m_be(dmcb_m_be),
    .dmc_m_wr(dmcb_m_wr),
    .dmc_m_req(dmcb_m_req),
    .dmc_m_ack(dmcb_m_ack)
    );

endmodule
