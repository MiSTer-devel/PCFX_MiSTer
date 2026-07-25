// Emulate a CD drive on the SCSI-CD bridge
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - https://www.staff.uni-mainz.de/tacke/scsi/SCSI2.html
// - https://github.com/libretro-mirrors/mednafen-git/blob/master/src/cdrom/scsicd.cpp

module fake_cd
   (
    input             CLK,
    input             RESn,

    output reg        STAT_GET,
    input [95:0]      COMMAND,
    input             COMM_SEND,
    output reg        DOUT_REQ,
    input [79:0]      DOUT,
    input             DOUT_SEND,
    output reg [7:0]  STATUS,
    output reg [7:0]  CD_DATA,
    output reg        CD_WR,
    input             CD_READY,
    input             CD_DATA_END,
    input             MSGOUT_PEND,
    input [7:0]       MSGOUT,
    input             MSGOUT_SEND,

    input             MEDIUM_EMPTY,
    output reg [31:0] SD_LBA,
    output reg        SD_RD,
    input             SD_ACK,
    output [12:0]     SDBUF_ADDR,
    input [15:0]      SDBUF_DOUT
    );

typedef enum bit [7:0]
{
    CMDOP_TEST_UNIT_READY = 8'h00,
    CMDOP_REQUEST_SENSE = 8'h03,
    CMDOP_MODE_SELECT = 8'h15,
    CMDOP_PREVENT_ALLOW_MEDIUM_REMOVAL = 8'h1e,
    CMDOP_READ_10 = 8'h28,
    CMDOP_READ_TOC = 8'h43,
    CMDOP_READ_HEADER = 8'h44
} _cmdop_t;

typedef enum bit [7:0]
{
    STATUS_GOOD = 8'h00,
    STATUS_CHECK_CONDITION = 8'h02
} _status_t;

localparam DATA_SENSE_LEN = 18;

typedef enum bit [7:0]
{
    SENSE_KEY_NO_SENSE = 8'h00,
    SENSE_KEY_NOT_READY = 8'h02,
    SENSE_KEY_ILLEGAL_REQUEST = 8'h05
} _sense_key_t;

typedef enum bit [15:0]
{
    ASC_NO_ADDITIONAL_SENSE_CODE = 16'h0000,
    ASC_NO_DISC = 16'h000b, // NEC-specific
    ASC_INVALID_COMMAND_OPERATION_CODE = 16'h0020
} _asc_t;

typedef enum bit [2:0]
{
    TS_IDLE,
    TS_CMD,
    TS_DATA_OUT, // initiator to target
    TS_DATA_IN, // target to initiator
    TS_DATA_IN_END,
    TS_STAT,
    TS_MSG_OUT // initiator to target
} tst_t;

tst_t           tst;
logic           cmd_start, cmd_cont, cmd_done;
logic           medium_req;
logic [7:0]     sense_key;
logic [15:0]    asc; // additional sense code and code qualifier
logic [7:0]     sense_do;
logic           data_out;
logic [11:0]    datalen, datapos, sdbuf_off;
logic [15:0]    blkcnt;
logic           dataloop;
logic [11:0]    sdbuf_baddr;
logic [12:0]    sdbuf_addr;
logic [7:0]     sdbuf_dbout;
logic           sd_ack_d;
logic           cd_wr_d;

wire            dataend = ((datapos + 1'd1) == datalen);
wire            blkend = (blkcnt == '0);

always @* begin
    sense_do = '0;
    case (datapos)
        'd0:  sense_do = 8'h70;
        'd2:  sense_do = sense_key;
        'd7:  sense_do = 8'h0A;     // Additional sense length
        'd12: sense_do = asc[7:0];  // Additional sense code
        'd13: sense_do = asc[15:8]; // Additional sense code qualifier
        default: ;
    endcase
end

assign sdbuf_baddr = datapos + sdbuf_off;
assign sdbuf_addr = 13'(sdbuf_baddr >> 1);

always @* begin
    sdbuf_off = '0;
    case (COMMAND[0+:8])
        CMDOP_READ_10: begin
            sdbuf_off = 12'd16; // skip header
        end
        CMDOP_READ_TOC: ;
        CMDOP_READ_HEADER: begin
            if (datapos == 12'd0) // Data mode
                sdbuf_off = 12'd15;
            else if (datapos >= 12'd5) // address
                sdbuf_off = 12'(12 - 5);
        end
        default: ;
    endcase
end

assign SDBUF_ADDR = sdbuf_addr;

always @* begin
    if (sdbuf_baddr[0])
        sdbuf_dbout = SDBUF_DOUT[8+:8];
    else
        sdbuf_dbout = SDBUF_DOUT[0+:8];
end

always @* begin
    CD_DATA = '0;
    if (tst == TS_DATA_IN) begin
        CD_DATA = sdbuf_dbout;
        case (COMMAND[0+:8])
            CMDOP_REQUEST_SENSE: begin
                CD_DATA = sense_do;
            end
            CMDOP_READ_HEADER: begin
                if (datapos >= 12'd1 && datapos <= 12'd4) // reserved
                    CD_DATA = '0;
            end
            default: ;
        endcase
    end
end

always @* begin
    medium_req = '0;
    case (COMMAND[0+:8])
        CMDOP_TEST_UNIT_READY:
            medium_req = '1;
        default: ;
    endcase
end

always @(posedge CLK) begin
    cmd_start <= '0;
    cmd_cont <= '0;
    cmd_done <= '0;
    STAT_GET <= '0;
    DOUT_REQ <= '0;
    sd_ack_d <= SD_ACK;
    cd_wr_d <= CD_WR;

    if (~RESn) begin
        STATUS <= '0;
        CD_WR <= '0;
        SD_LBA <= '0;
        SD_RD <= '0;

        tst <= TS_IDLE;
        datalen <= '0;
        sense_key <= SENSE_KEY_NO_SENSE;
        asc <= ASC_NO_ADDITIONAL_SENSE_CODE;
    end
    else begin
        if (~sd_ack_d & SD_ACK)
            SD_RD <= '0;

        case (tst)
            TS_IDLE:
                if (COMM_SEND) begin
                    $display("fake_cd: COMMAND=%x", COMMAND);
                    blkcnt <= '0;
                    datapos <= '0;
                    data_out <= '0;
                    cmd_start <= '1;
                    tst <= TS_CMD;
                end
            TS_CMD:
                if (cmd_done) begin
                    if (datalen != 0) begin
                        if (data_out) begin
                            DOUT_REQ <= '1;
                            tst <= TS_DATA_OUT;
                        end
                        else
                            tst <= TS_DATA_IN;
                    end
                    else
                        tst <= TS_STAT;
                end
            TS_DATA_OUT: begin // initiator to target
                if (DOUT_SEND)
                    tst <= TS_STAT;
            end
            TS_DATA_IN: begin // target to initiator
                if (MSGOUT_PEND) // early termination by ATN
                    tst <= TS_MSG_OUT;
                else if (CD_WR) begin
                    datapos <= datapos + 1'd1;
                    if (dataend) begin
                        if (~blkend) begin
                            blkcnt <= blkcnt - 1'd1;
                            datapos <= '0;
                            cmd_cont <= '1;
                            tst <= TS_CMD;
                        end
                        else begin
                            tst <= TS_DATA_IN_END;
                        end
                    end
                end
            end
            TS_DATA_IN_END: begin
                // To close a race between us finishing sending data
                // to the SCSI bridge and the initiator asserting ATN,
                // we wait here for the bridge to finish sending data
                // to the initiator.
                if (CD_DATA_END) begin
                    if (MSGOUT_PEND) // early termination by ATN
                        tst <= TS_MSG_OUT;
                    else // normal completion
                        tst <= TS_STAT;
                end
            end
            TS_STAT: begin
                STAT_GET <= '1;
                tst <= TS_IDLE;
            end
            TS_MSG_OUT: begin
                if (MSGOUT_SEND) begin
                    // Error handling (ie retry) would go here.
                    $display("fake_cd: MSGOUT=%x", MSGOUT);
                    tst <= TS_IDLE;
                end
            end
            default: ;
        endcase

        if ((tst == TS_CMD) & cmd_start) begin
            STATUS <= STATUS_GOOD;
            datalen <= '0;

            if (medium_req & MEDIUM_EMPTY) begin
                STATUS <= STATUS_CHECK_CONDITION;
                sense_key <= SENSE_KEY_NOT_READY;
                asc <= ASC_NO_DISC;
                cmd_done <= '1;
            end
            else begin
                case (COMMAND[0+:8])
                    CMDOP_TEST_UNIT_READY: begin
                        cmd_done <= '1;
                    end
                    CMDOP_REQUEST_SENSE: begin
                        datalen <= $size(datalen)'(COMMAND[32+:8]);
                        cmd_done <= '1;
                    end
                    CMDOP_MODE_SELECT: begin
                        data_out <= '1;
                        datalen <= $size(datalen)'(COMMAND[4*8+:8]);
                        cmd_done <= '1;
                    end
                    CMDOP_PREVENT_ALLOW_MEDIUM_REMOVAL: begin
                        cmd_done <= '1;
                    end
                    CMDOP_READ_10: begin
                        // TODO: 2336 for Mode 2 blocks
                        datalen <= $size(datalen)'(2048);
                        if (COMMAND[(7*8)+:16] != '0) begin
                            blkcnt <= $size(blkcnt)'
                                      ({COMMAND[(7*8)+:8], COMMAND[(8*8)+:8]}
                                       - 1'd1);
                            SD_LBA <= {COMMAND[(2*8)+:8], COMMAND[(3*8)+:8],
                                       COMMAND[(4*8)+:8], COMMAND[(5*8)+:8]};
                            SD_RD <= '1;
                        end
                        else
                            cmd_done <= '1;
                    end
                    CMDOP_READ_TOC: begin
                        datalen <= $size(datalen)'
                                   ({COMMAND[(7*8)+:8], COMMAND[(8*8)+:8]});
                        SD_LBA <= 32'(-65536 + COMMAND[(6*8)+:8]);
                        SD_RD <= '1;
                    end
                    CMDOP_READ_HEADER: begin
                        datalen <= $size(datalen)'
                                   ({COMMAND[(7*8)+:8], COMMAND[(8*8)+:8]});
                        SD_LBA <= {COMMAND[(2*8)+:8], COMMAND[(3*8)+:8],
                                   COMMAND[(4*8)+:8], COMMAND[(5*8)+:8]};
                        SD_RD <= '1;
                    end
                    default: begin
                        STATUS <= STATUS_CHECK_CONDITION;
                        sense_key <= SENSE_KEY_ILLEGAL_REQUEST;
                        asc <= ASC_INVALID_COMMAND_OPERATION_CODE;
                        cmd_done <= '1;
                    end
                endcase
            end
        end

        if ((tst == TS_CMD) & cmd_cont) begin
            case (COMMAND[0+:8])
                CMDOP_READ_10: begin
                    SD_LBA <= SD_LBA + 1'd1;
                    SD_RD <= '1;
                end
                default: ;
            endcase
        end

        if ((tst == TS_CMD) & ~(cmd_start | cmd_cont)) begin
            case (COMMAND[0+:8])
                CMDOP_READ_10,
                CMDOP_READ_TOC,
                CMDOP_READ_HEADER: begin
                    cmd_done <= sd_ack_d & ~SD_ACK;
                end
                default: ;
            endcase
        end

        if ((tst == TS_DATA_OUT) & DOUT_SEND) begin
            $display("fake_cd: DOUT=%x", DOUT);
            case (COMMAND[0+:8])
                CMDOP_MODE_SELECT: begin
                    // TODO
                end
                default: ;
            endcase
        end

        if (tst == TS_DATA_IN) begin
            // Due to FIFO pipeline delays in the SCSI module, CD_WR
            // must stay low for at least 2x clocks after falling.
            CD_WR <= ~(CD_WR | cd_wr_d) & CD_READY;

            case (COMMAND[0+:8])
                CMDOP_REQUEST_SENSE: begin
                    if (CD_WR & dataend) begin
                        sense_key <= SENSE_KEY_NO_SENSE;
                        asc <= ASC_NO_ADDITIONAL_SENSE_CODE;
                    end
                end
                default: ;
            endcase

            if (CD_WR & (COMMAND[0+:8] != CMDOP_READ_10))
                $display("fake_cd: TS_DATA_IN: [%x] = %x", datapos, CD_DATA);
        end
        else
            CD_WR <= '0;
    end
end

endmodule
