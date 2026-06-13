// PC-FX File Manager

task load_vce_reg();
    io_sel = VCE;
    reg_write(7'h00, 16'h0348); // CR
    reg_write(7'h04, 16'h0000); // CPO1
    reg_write(7'h05, 16'h2828); // CPO2
    reg_write(7'h06, 16'h2828); // CPO3
    reg_write(7'h07, 16'h0028); // CPO4
    reg_write(7'h08, 16'h0576); // PR1
    reg_write(7'h09, 16'h4321); // PR2
    reg_write(7'h0d, 16'h0088); // CCR
    reg_write(7'h0e, 16'h0000); // BLE
    reg_write(7'h0f, 16'h0000); // SPBL
    reg_write(7'h10, 16'h0444); // BL1A
    reg_write(7'h11, 16'h0444); // BL1B
    reg_write(7'h12, 16'h0444); // BL2A
    reg_write(7'h13, 16'h0444); // BL2B
    reg_write(7'h14, 16'h0444); // BL3A
    reg_write(7'h15, 16'h0444); // BL3B
endtask

task load_vdc0_reg();
    io_sel = VDC0;
    reg_write(7'h05, 16'h00c8); // CR
    reg_write(7'h06, 16'h0000); // RCR
    reg_write(7'h07, 16'h0000); // BXR
    reg_write(7'h08, 16'h0000); // BYR
    reg_write(7'h09, 16'h0010); // MWR
    reg_write(7'h0a, 16'h0503); // HSR
    reg_write(7'h0b, 16'h0227); // HDR
    reg_write(7'h0c, 16'h1002); // VPR
    reg_write(7'h0d, 16'h00ff); // VDR
    reg_write(7'h0e, 16'h001b); // VCR
    reg_write(7'h0f, 16'h0010); // DCR
    reg_write(7'h13, 16'h0800); // DVSSR
endtask

task load_vdc1_reg();
    io_sel = VDC1;
    reg_write(7'h05, 16'h0040); // CR
    reg_write(7'h06, 16'h0000); // RCR
    reg_write(7'h07, 16'h0000); // BXR
    reg_write(7'h08, 16'h0000); // BYR
    reg_write(7'h09, 16'h0010); // MWR
    reg_write(7'h0a, 16'h0503); // HSR
    reg_write(7'h0b, 16'h0227); // HDR
    reg_write(7'h0c, 16'h1002); // VPR
    reg_write(7'h0d, 16'h00ff); // VDR
    reg_write(7'h0e, 16'h001b); // VCR
    reg_write(7'h0f, 16'h0010); // DCR
    reg_write(7'h13, 16'h0800); // DVSSR
endtask

task load_kreg();
    // KING BG
    io_sel = MMC;
    reg_write(7'h10, 16'h000B); // Mode
    reg_write(7'h12, 16'h1004); // Prio
    reg_write(7'h16, 16'h0001); // ScrM
    // KBG0
    reg_write(7'h2c, 16'h9898); // Size
    reg_write(7'h20, 16'h00C0); // BAT
    reg_write(7'h21, 16'h0000); // CG
    reg_write(7'h22, 16'h00C0); // SubBAT
    reg_write(7'h23, 16'h0000); // SubCG
    reg_write(7'h30, 16'h0000); // XScr
    reg_write(7'h31, 16'h0000); // YScr
    // KBG1
    reg_write(7'h2d, 16'h0000); // Size
    reg_write(7'h24, 16'h0000); // BAT
    reg_write(7'h25, 16'h0000); // CG
    reg_write(7'h32, 16'h0000); // XScr
    reg_write(7'h33, 16'h0000); // YScr
    // KBG2
    reg_write(7'h2e, 16'h0000); // Size
    reg_write(7'h28, 16'h0000); // BAT
    reg_write(7'h29, 16'h0000); // CG
    reg_write(7'h34, 16'h0000); // XScr
    reg_write(7'h35, 16'h0000); // YScr
    // KBG3
    reg_write(7'h2f, 16'h0000); // Size
    reg_write(7'h2a, 16'h0000); // BAT
    reg_write(7'h2b, 16'h0000); // CG
    reg_write(7'h34, 16'h0000); // XScr
    reg_write(7'h35, 16'h0000); // YScr
    // AFFIN
    reg_write(7'h38, 16'h0100); // A
    reg_write(7'h39, 16'h0000); // B
    reg_write(7'h3a, 16'h0000); // C
    reg_write(7'h3b, 16'h0100); // D
    reg_write(7'h3c, 16'h0080); // X
    reg_write(7'h3d, 16'h0080); // Y
    // MPROG
    reg_write(7'h13, 16'h0000); // uAddr=0
    reg_write(7'h14, 16'h0000); // 0
    reg_write(7'h14, 16'h0000); // 1
    reg_write(7'h14, 16'h0000); // 2
    reg_write(7'h14, 16'h0000); // 3
    reg_write(7'h14, 16'h0000); // 4
    reg_write(7'h14, 16'h0000); // 5
    reg_write(7'h14, 16'h0000); // 6
    reg_write(7'h14, 16'h0038); // 7
    reg_write(7'h14, 16'h0038); // 8
    reg_write(7'h14, 16'h0038); // 9
    reg_write(7'h14, 16'h0038); // A
    reg_write(7'h14, 16'h0038); // B
    reg_write(7'h14, 16'h0038); // C
    reg_write(7'h14, 16'h0038); // D
    reg_write(7'h14, 16'h0038); // E
    reg_write(7'h14, 16'h0038); // F
    reg_write(7'h15, 16'h0001); // MPSW=1
endtask

task load_rreg();
endtask

task load_vmem();
    $readmemh("vram0-filemgr.hex", vram0.mem);
    $readmemh("vram1-filemgr.hex", vram1.mem);
    $readmemh("vce_cp-filemgr.hex", vce.cpram.mem);
endtask

