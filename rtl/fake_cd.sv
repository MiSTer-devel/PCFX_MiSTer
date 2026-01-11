// Fake an empty CD drive on the SCSI-CD bridge
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module fake_cd
   (
    input            CLK,
    input            RESn,

    output reg       STAT_GET,
    input [95:0]     COMMAND,
    input            COMM_SEND,
    output reg [7:0] STATUS,
    output reg [7:0] CD_DATA,
    output reg       CD_WR
    );

logic       req_sense;
logic [4:0] req_st;

always @(posedge CLK) begin
    if (~RESn) begin
        STAT_GET <= '0;
        STATUS <= '0;
        CD_DATA <= 8'h00;
        CD_WR <= '0;
        req_sense <= '0;
        req_st <= '0;
    end
    else begin
        if (COMM_SEND) begin
            case (COMMAND[7:0] )
                /*8'h00,*/                   // TEST UNIT READY
                default: begin
                    STAT_GET <= '1;
                    STATUS <= 8'h02; // CHECK CONDITION
                end
                8'h03: req_sense <= '1;      // REQUEST SENSE
            endcase
        end

        if (req_sense) begin
            case (req_st)
                'd0: CD_DATA <= 8'h70;
                'd2: CD_DATA <= 8'h02; // Sense key: NOT READY
                'd7: CD_DATA <= 8'h0A; // Additional sense length
                'd12:CD_DATA <= 8'h0B; // Additional sense code: ABORTED COMMAND
                default: CD_DATA <= 8'h00;
            endcase
            if (req_st == 'd18) begin
                STAT_GET <= '1;
                STATUS <= 8'h00; // GOOD
                CD_WR <= '0;
                req_sense <= '0;
                req_st <= '0;
            end
            else begin
                CD_WR <= ~CD_WR;
                if (CD_WR)
                    req_st <= req_st + 1'd1;
            end
        end

        if (STAT_GET) begin
            STAT_GET <= '0;
        end
    end
end

endmodule
