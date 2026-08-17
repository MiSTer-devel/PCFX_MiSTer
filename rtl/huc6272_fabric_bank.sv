// Memory fabric for a single bank
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_fabric_bank #(parameter CN = 8)
   (
    input         CLK,
    input         RESn,
    input         DCK,

    // Client interfaces
    // Index 0 is highest priority
    input [17:0]  cm_a [0:CN-1],
    output [15:0] cm_di [0:CN-1],
    input [15:0]  cm_do [0:CN-1],
    input [1:0]   cm_be [0:CN-1],
    input         cm_wr [0:CN-1], 
    input         cm_req [0:CN-1], 
    output        cm_ack [0:CN-1],

    // DRAM memory controller interface
    output [17:0] dmc_m_a,
    input [15:0]  dmc_m_di, 
    output [15:0] dmc_m_do,
    output [1:0]  dmc_m_be,
    output        dmc_m_wr, 
    output        dmc_m_req, 
    input         dmc_m_ack
    );

//////////////////////////////////////////////////////////////////////

localparam PN = $clog2(CN);

logic           dck_d;
logic           req, ack;
logic           ack_d, ack_pend, ack_pend_d;

logic [PN-1:0]  prio_hi, prio_sel, prio_sel_d;
logic           prio_hi_valid;
logic           prio_act, prio_act_d;
logic           prio_act_clr, prio_act_set;

always @* begin
    prio_hi = '0;
    prio_hi_valid = '0;
    for (int i = 0; i < CN; i++) begin
        if (~prio_hi_valid & cm_req[i]) begin
            prio_hi_valid = '1;
            prio_hi = i[PN-1:0];
        end
    end
end

always @* begin
    prio_sel = prio_sel_d;
    if (dck_d & ~prio_act_d & prio_hi_valid)
        prio_sel = prio_hi;
end

// Force request and completion to be DCK-aligned
assign req = dck_d & cm_req[prio_sel];
assign ack = (ack_d | ack_pend) & DCK;
assign ack_pend = (ack_pend_d | dmc_m_ack) & ~ack_d;

assign prio_act_clr = ack;
assign prio_act_set = req;
assign prio_act = (prio_act_d & ~prio_act_clr) | prio_act_set;

always @(posedge CLK) begin
    if (~RESn) begin
        prio_sel_d <= '0;
        prio_act_d <= '0;
        ack_d <= '0;
        ack_pend_d <= '0;
    end
    else begin
        prio_sel_d <= prio_sel;
        prio_act_d <= prio_act;
        ack_d <= ack;
        ack_pend_d <= ack_pend;
    end
    dck_d <= DCK;
end

//////////////////////////////////////////////////////////////////////

assign dmc_m_a = cm_a[prio_sel];
assign dmc_m_do = cm_do[prio_sel];
assign dmc_m_be = cm_be[prio_sel];
assign dmc_m_wr = cm_wr[prio_sel];
assign dmc_m_req = prio_act & ~prio_act_d; // ctlr watches rising edge

genvar          g;
generate
    for (g = 0; g < CN; g++) begin :cm_out
        assign cm_di[g] = dmc_m_di;
        assign cm_ack[g] = (g == prio_sel) & ack;
    end
endgenerate

endmodule
