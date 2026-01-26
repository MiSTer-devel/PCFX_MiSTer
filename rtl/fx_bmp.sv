// A FX-BMP with battery-backed SRAM, connected to the Memory Card Port
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module fx_bmp
   (
    // Emulation configuration
    input         CFG_EN,
    input [2:0]   CFG_SIZE, // 0=128KB, 1=256KB, 2=512KB, .. 6=8MB

    // Memory Card port interface
    input [26:1]  MCP_A, // A24 is omitted
    input [7:0]   MCP_DI,
    output [7:0]  MCP_DO,
    input         MCP_CSn, // aka /CartSel
    input         MCP_RDn,
    input         MCP_WRn,
    output        MCP_READYn,

    // Memory interface
    output [22:0] RAM_A,
    output [7:0]  RAM_DI,
    input [7:0]   RAM_DO,
    output        RAM_CEn,
    output        RAM_WEn,
    input         RAM_READYn
    );

// Control size by masking (zeroing) RAM address bits above 128KB.
logic [22:0]    ram_a_mask;

always @* begin
    ram_a_mask[16:0] = '1;
    case (CFG_SIZE)
        3'd0:   ram_a_mask[22:17] = 'b000_000; // 128KB
        3'd1:   ram_a_mask[22:17] = 'b000_001; // 256KB
        3'd2:   ram_a_mask[22:17] = 'b000_011; // 512KB
        3'd3:   ram_a_mask[22:17] = 'b000_111; // 1MB
        3'd4:   ram_a_mask[22:17] = 'b001_111; // 2MB
        3'd5:   ram_a_mask[22:17] = 'b011_111; // 4MB
        default:ram_a_mask[22:17] = 'b111_111; // 8MB
    endcase
end

// BMP address range is E800_0000 .. EBFF_FFFF -- half the port's addressable range.
wire    bmp_sel = ~(~CFG_EN | MCP_CSn | MCP_A[26]);

// BMP memory is split down the middle:
//   E800_0000 + (0000_0000 .. 01FF_FFFE) is SRAM
//   E800_0000 + (0200_0000 .. 03FF_FFFE) is battery status
wire    sram_sel = bmp_sel & ~MCP_A[25];
wire    bat_sel  = bmp_sel & MCP_A[25];

// The battery is always "good".
wire    bat_good = '1;

assign RAM_A = MCP_A[23:1] & ram_a_mask;
assign RAM_DI = MCP_DI;
assign RAM_CEn = ~sram_sel;
assign RAM_WEn = RAM_CEn | MCP_WRn;

assign MCP_DO = {8{~bmp_sel}} | (bat_sel ? {7'h7F, bat_good} : RAM_DO);
assign MCP_READYn = MCP_CSn | (sram_sel & RAM_READYn);

endmodule
