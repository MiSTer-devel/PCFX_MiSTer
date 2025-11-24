module mach
  (
   input         CLK,
   input         CE,
   input         RESn,

   output [31:0] A
   );

logic [31:0]    dut_ia, dut_da;
logic [31:0]    dut_id;
logic           dut_ireq, dut_iack;
wire [31:0]     dut_dd_i, dut_dd_o;
wire [1:0]      dut_dbc;
wire [3:0]      dut_dbe;
wire            dut_dwr;
wire            dut_dmrq;
wire [1:0]      dut_dst;
wire            dut_dreq, dut_dack;

wire [31:0]     mem_a;
logic [31:0]    mem_d_i;
wire [31:0]     mem_d_o;
wire [3:0]      mem_ben;
wire            mem_dan;
wire            mem_mrqn;
wire            mem_rw;
wire            mem_bcystn;
wire            mem_readyn;
wand            mem_szrqn;

logic           rom_cen;
logic [15:0]    rom_do;

logic           ram_cen;
wire [31:0]     ram_do;

logic           unk_cen;

initial begin
    $timeformat(-9, 0, " ns", 1);

`ifndef VERILATOR
    $dumpfile("bios_tb.vcd");
    $dumpvars();
`else
    $dumpfile("bios_tb.verilator.fst");
    $dumpvars();
`endif
end

v810_exec dut
  (
   .RESn(RESn),
   .CLK(CLK),
   .CE(CE),

   .IA(dut_ia),
   .ID(dut_id),
   .IREQ(dut_ireq),
   .IACK(dut_iack),

   .DA(dut_da),
   .DD_I(dut_dd_i),
   .DD_O(dut_dd_o),
   .DBC(dut_dbc),
   .DBE(dut_dbe),
   .DWR(dut_dwr),
   .DMRQ(dut_dmrq),
   .DST(dut_dst),
   .DREQ(dut_dreq),
   .DACK(dut_dack),

   .ST()
   );

v810_mem dut_mem
  (
   .RESn(RESn),
   .CLK(CLK),
   .CE(CE),

   .EUDA(dut_da),
   .EUDD_I(dut_dd_i),
   .EUDD_O(dut_dd_o),
   .EUDBC(dut_dbc),
   .EUDBE(dut_dbe),
   .EUDWR(dut_dwr),
   .EUDMRQ(dut_dmrq),
   .EUDST(dut_dst),
   .EUDREQ(dut_dreq),
   .EUDACK(dut_dack),

   .EUIA(dut_ia),
   .EUID(dut_id),
   .EUIREQ(dut_ireq),
   .EUIACK(dut_iack),

   .A(mem_a),
   .D_I(mem_d_i),
   .D_O(mem_d_o),
   .BEn(mem_ben),
   .ST(),
   .DAn(mem_dan),
   .MRQn(mem_mrqn),
   .RW(mem_rw),
   .BCYSTn(mem_bcystn),
   .READYn(mem_readyn),
   .SZRQn(mem_szrqn)
   );

always @* begin
    if (~rom_cen)
        mem_d_i = {16'b0, rom_do};
    else if (~ram_cen)
        mem_d_i = ram_do;
    else
        mem_d_i = '0;
end

assign mem_readyn = unk_cen & rom_cen & ram_cen;
assign mem_szrqn = ~unk_cen | rom_cen;

ram #(4, 16) rombios
  (
   .CLK(CLK),
   .nCE(rom_cen),
   .nWE('1),
   .nOE('0),
   .nBE('1),
   .A(mem_a[4:1]),
   .DI('Z),
   .DO(rom_do)
   );

ram #(4, 32) dmem
  (
   .CLK(CLK),
   .nCE(ram_cen),
   .nWE(mem_rw),
   .nOE(~mem_rw),
   .nBE(mem_ben),
   .A(mem_a[5:2]),
   .DI(mem_d_o),
   .DO(ram_do)
   );

assign ram_cen = ~(~mem_mrqn & ~mem_a[31]);
assign rom_cen = ~(~mem_mrqn & (mem_a[31:20] == 12'hFFF));
assign unk_cen = ~(ram_cen & rom_cen);

assign A = mem_a;

endmodule
