// Return To Zork, first still frame during startup

task load_vce_reg();
    io_sel = VCE;
    reg_write(7'h00, 16'h4700); // CR
    reg_write(7'h04, 16'h8080); // CPO1
    reg_write(7'h05, 16'h0000); // CPO2
    reg_write(7'h06, 16'h0000); // CPO3
    reg_write(7'h07, 16'h0000); // CPO4
    reg_write(7'h08, 16'h0176); // PR1
    reg_write(7'h09, 16'h2345); // PR2
    reg_write(7'h0d, 16'h0088); // CCR
    reg_write(7'h0e, 16'hc000); // BLE
    reg_write(7'h0f, 16'h0000); // SPBL
    reg_write(7'h10, 16'h0000); // BL1A
    reg_write(7'h11, 16'h0888); // BL1B
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
    reg_write(7'h09, 16'h0050); // MWR
    reg_write(7'h0a, 16'h0202); // HSR
    reg_write(7'h0b, 16'h041f); // HDR
    reg_write(7'h0c, 16'h1102); // VPR
    reg_write(7'h0d, 16'h00ef); // VDR
    reg_write(7'h0e, 16'h0002); // VCR
    reg_write(7'h13, 16'h7f00); // DVSSR
endtask

task load_vdc1_reg();
    io_sel = VDC1;
    reg_write(7'h05, 16'h00c0); // CR
    reg_write(7'h06, 16'h0000); // RCR
    reg_write(7'h07, 16'h0000); // BXR
    reg_write(7'h08, 16'hfff8); // BYR
    reg_write(7'h09, 16'h0050); // MWR
    reg_write(7'h0a, 16'h0202); // HSR
    reg_write(7'h0b, 16'h041f); // HDR
    reg_write(7'h0c, 16'h1102); // VPR
    reg_write(7'h0d, 16'h00ef); // VDR
    reg_write(7'h0e, 16'h0002); // VCR
    reg_write(7'h13, 16'h7f00); // DVSSR
endtask

task load_kreg();
    // KING BG
    io_sel = MMC;
    reg_write(7'h10, 16'h000b); // Mode
    reg_write(7'h12, 16'h0004); // Prio
    reg_write(7'h16, 16'h0000); // ScrM
    // KBG0
    reg_write(7'h2c, 16'h9898); // Size
    reg_write(7'h20, 16'h0080); // BAT
    reg_write(7'h21, 16'h0000); // CG
    reg_write(7'h22, 16'h0080); // SubBAT
    reg_write(7'h23, 16'h0000); // SubCG
    reg_write(7'h30, 16'h0000); // XScr
    reg_write(7'h31, 16'h0000); // YScr
    // KBG1
    reg_write(7'h2d, 16'h0033); // Size
    reg_write(7'h24, 16'h0000); // BAT
    reg_write(7'h25, 16'h0000); // CG
    reg_write(7'h32, 16'h0000); // XScr
    reg_write(7'h33, 16'h0000); // YScr
    // KBG2
    reg_write(7'h2e, 16'h0033); // Size
    reg_write(7'h28, 16'h0000); // BAT
    reg_write(7'h29, 16'h0000); // CG
    reg_write(7'h34, 16'h0000); // XScr
    reg_write(7'h35, 16'h0000); // YScr
    // KBG3
    reg_write(7'h2f, 16'h0033); // Size
    reg_write(7'h2a, 16'h0000); // BAT
    reg_write(7'h2b, 16'h0000); // CG
    reg_write(7'h36, 16'h0000); // XScr
    reg_write(7'h37, 16'h0000); // YScr
    // AFFIN
    reg_write(7'h38, 16'h0000); // A
    reg_write(7'h39, 16'h0000); // B
    reg_write(7'h3a, 16'h0000); // C
    reg_write(7'h3b, 16'h0000); // D
    reg_write(7'h3c, 16'h0000); // X
    reg_write(7'h3d, 16'h0000); // Y
    // RAINBOW
    reg32_write(7'h41, 32'h00000000); // RKRAMA
    reg_write(7'h42, 16'h0006); // RSTART
    reg_write(7'h43, 16'h000f); // RCOUNT
    reg_write(7'h44, 16'h0000); // RIRQLINE
    reg_write(7'h40, 16'h0001); // RTCTRL
    // MPROG
    reg_write(7'h13, 16'h0000); // uAddr=0
    reg_write(7'h14, 16'h0028); // 0
    reg_write(7'h14, 16'h0028); // 1
    reg_write(7'h14, 16'h0028); // 2
    reg_write(7'h14, 16'h0028); // 3
    reg_write(7'h14, 16'h0028); // 4
    reg_write(7'h14, 16'h0028); // 5
    reg_write(7'h14, 16'h0028); // 6
    reg_write(7'h14, 16'h0028); // 7
    reg_write(7'h14, 16'h0030); // 8
    reg_write(7'h14, 16'h0030); // 9
    reg_write(7'h14, 16'h0030); // A
    reg_write(7'h14, 16'h0030); // B
    reg_write(7'h14, 16'h0030); // C
    reg_write(7'h14, 16'h0030); // D
    reg_write(7'h14, 16'h0030); // E
    reg_write(7'h14, 16'h0030); // F
    reg_write(7'h15, 16'h0001); // MPSW=1
endtask

task load_rreg();
endtask

task load_vmem();
    $readmemh("vce_cp-rtz0.hex", vce.cpram.mem);
    vram_load_file("kram0-rtz0.bin", 0);
endtask

