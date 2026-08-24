// =============================================================================
// File:        tb_btn_debounce.sv
// Project:     Project Auris
// Module:      tb_btn_debounce
// Description: Self-checking testbench for the 4-button active-low debouncer
//              (btn_debounce). Verifies:
//
//                1. Bounce rejection: rapid toggling of btn_i for intervals
//                   strictly shorter than DEBOUNCE_MS produces ZERO
//                   btn_press_pulse_o pulses (no false triggers).
//                2. Stable press: holding btn_i low for strictly more than
//                   DEBOUNCE_MS produces EXACTLY ONE btn_press_pulse_o
//                   pulse (single-cycle, on the leading edge of the
//                   debounced state).
//                3. Release: returning btn_i to high after a stable press
//                   produces EXACTLY ONE btn_release_pulse_o pulse (single
//                   cycle, on the trailing edge of the debounced state).
//                4. Independence: all 4 buttons (BTN0..BTN3) can be
//                   debounced concurrently without crosstalk.
//                5. Active-low polarity: btn_pressed_o is asserted exactly
//                   while btn_i is low, after the debounce interval
//                   has elapsed.
//
//              The DUT is parameterized so the testbench uses a slow
//              1 MHz clock (period = 1000 ns) while preserving the 20 ms
//              debounce time. This keeps DEBOUNCE_CYCLES = 20,000 cycles,
//              which is tractable for xsim while still exercising the
//              real timing relationship (20 ms <-> 20,000 cycles).
//
//              Clock: 1 MHz (slowed for simulation speed; the DUT RTL is
//              otherwise identical to a 96 MHz instantiation).
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_btn_debounce;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    // 1 MHz clock means 20 ms = 20,000 cycles. This is the same time
    // relationship as 96 MHz : 20 ms = 1,920,000 cycles, just scaled.
    localparam int unsigned TB_CLK_FREQ_HZ = 1_000_000;
    localparam int unsigned TB_DEBOUNCE_MS = 20;
    localparam int unsigned TB_NUM_BUTTONS = 4;

    // -------------------------------------------------------------------------
    // DUT / testbench signals
    // -------------------------------------------------------------------------
    logic                          clk;
    logic                          rst_n;
    logic [TB_NUM_BUTTONS-1:0]     btn;          // active-low raw input
    logic [TB_NUM_BUTTONS-1:0]     btn_pressed;  // active-high debounced state
    logic [TB_NUM_BUTTONS-1:0]     press_pulse;  // 1-cycle pulse on press
    logic [TB_NUM_BUTTONS-1:0]     release_pulse;// 1-cycle pulse on release

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    btn_debounce #(
        .CLK_FREQ_HZ (TB_CLK_FREQ_HZ),
        .DEBOUNCE_MS (TB_DEBOUNCE_MS),
        .NUM_BUTTONS (TB_NUM_BUTTONS)
    ) dut (
        .clk_i              (clk),
        .rst_n_i            (rst_n),
        .btn_i              (btn),
        .btn_pressed_o      (btn_pressed),
        .btn_press_pulse_o  (press_pulse),
        .btn_release_pulse_o(release_pulse)
    );

    // -------------------------------------------------------------------------
    // Clock generation: 1 MHz (period 1000 ns)
    // -------------------------------------------------------------------------
    localparam real CLK_HALF = (1_000_000_000.0 / real'(TB_CLK_FREQ_HZ)) / 2.0;  // 500 ns at 1 MHz
    initial begin
        clk = 1'b0;
        forever #(CLK_HALF) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count  = 0;
    int fail_count  = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Pulse counters: continuously count rising-edge pulses on the
    // press_pulse / release_pulse busses across the whole simulation.
    // Each test queries these counters AFTER the relevant stimulus, then
    // resets them via the `reset_pulse_counters` task so subsequent tests
    // start with a clean count.
    // -------------------------------------------------------------------------
    int unsigned press_count [TB_NUM_BUTTONS];
    int unsigned release_count [TB_NUM_BUTTONS];

    // Pulse counting: at every posedge clk, detect any pulse bit.
    always_ff @(posedge clk) begin
        for (int i = 0; i < TB_NUM_BUTTONS; i++) begin
            if (press_pulse[i])   press_count[i]   <= press_count[i]   + 1;
            if (release_pulse[i]) release_count[i] <= release_count[i] + 1;
        end
    end

    task automatic reset_pulse_counters();
        // Wait one negedge to avoid racing the always_ff above, then
        // synchronously clear the counters.
        @(negedge clk);
        for (int i = 0; i < TB_NUM_BUTTONS; i++) begin
            press_count[i]   = 0;
            release_count[i] = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper task: drive btn_i for a deterministic number of input cycles.
    // `hold_cycles` is the number of consecutive clk cycles for which the
    // pattern should be held. 1 cycle = 1 us here, so 10 cycles = 10 us.
    // -------------------------------------------------------------------------
    task automatic drive_btn(
        input logic [TB_NUM_BUTTONS-1:0] pattern,
        input int unsigned                hold_cycles
    );
        btn = pattern;
        repeat (hold_cycles) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Self-check helper: increments total_count, increments pass_count or
    // fail_count based on `cond`, prints one PASS/FAIL line.
    // -------------------------------------------------------------------------
    task automatic check(
        input logic cond,
        input string name,
        input string detail = ""
    );
        total_count++;
        if (cond) begin
            $display("[PASS] %s%s", name, detail);
            pass_count++;
        end else begin
            $display("[FAIL] %s%s", name, detail);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_btn_debounce.vcd");
        $dumpvars(0, tb_btn_debounce);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // ---- Reset --------------------------------------------------------
        rst_n = 1'b0;
        btn   = {TB_NUM_BUTTONS{1'b1}};   // all released (active-low)
        for (int i = 0; i < TB_NUM_BUTTONS; i++) begin
            press_count[i]   = 0;
            release_count[i] = 0;
        end
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Bounce rejection on BTN0
        // Toggle BTN0 high/low with each phase held for < DEBOUNCE_MS.
        // At 1 MHz, 20 ms = 20,000 cycles. We toggle every 1000 cycles
        // (1 ms), so every transition is well below the debounce window.
        // Expected: press_count[0] remains 0 after the test.
        // =====================================================================
        $display("\n=== Test 1: Bounce rejection on BTN0 (toggle every 1 ms < 20 ms) ===");
        reset_pulse_counters();
        for (int i = 0; i < 50; i++) begin
            drive_btn(4'b1110, 1000);  // BTN0 low for 1 ms
            drive_btn(4'b1111, 1000);  // BTN0 high for 1 ms
        end
        // Wait a few extra cycles to let any spurious pulse settle
        repeat (100) @(posedge clk);
        check(press_count[0] == 0,
              "Test1-BounceRejectBTN0",
              $sformatf(": press_count[0]=%0d (expected 0)", press_count[0]));

        // =====================================================================
        // Test 2: Stable press on BTN0
        // Hold BTN0 low for > 20 ms. Expected: press_count[0] == 1.
        // =====================================================================
        $display("\n=== Test 2: Stable press on BTN0 (hold low for 25 ms > 20 ms) ===");
        reset_pulse_counters();
        drive_btn(4'b1110, 25_000);  // 25 ms < 25,000 cycles
        // Wait a few cycles for the debounce FSM to assert the pulse
        repeat (100) @(posedge clk);
        check(press_count[0] == 1,
              "Test2-StablePressBTN0",
              $sformatf(": press_count[0]=%0d (expected 1)", press_count[0]));
        // At this point BTN0 should be considered pressed (active-high)
        check(btn_pressed[0] == 1'b1,
              "Test2-PressedStateBTN0",
              $sformatf(": btn_pressed[0]=%b (expected 1)", btn_pressed[0]));

        // =====================================================================
        // Test 3: Release of BTN0
        // Bring BTN0 back high for > 20 ms. Expected: release_count[0] == 1.
        // =====================================================================
        $display("\n=== Test 3: Release of BTN0 (hold high for 25 ms) ===");
        reset_pulse_counters();
        drive_btn(4'b1111, 25_000);
        repeat (100) @(posedge clk);
        check(release_count[0] == 1,
              "Test3-ReleaseBTN0",
              $sformatf(": release_count[0]=%0d (expected 1)", release_count[0]));
        check(btn_pressed[0] == 1'b0,
              "Test3-ReleasedStateBTN0",
              $sformatf(": btn_pressed[0]=%b (expected 0)", btn_pressed[0]));

        // =====================================================================
        // Test 4: All 4 buttons concurrently (BTN0..BTN3)
        // Press each button in a distinct 4us slot, hold, then release.
        // Each press should produce exactly one press_pulse and exactly one
        // release_pulse (no crosstalk).
        // =====================================================================
        $display("\n=== Test 4: All 4 buttons pressed concurrently, then released ===");
        reset_pulse_counters();

        // Phase A: press all 4 buttons (hold for 25 ms)
        drive_btn(4'b0000, 25_000);
        repeat (100) @(posedge clk);

        // Verify 1 press per button, 0 release per button
        for (int i = 0; i < TB_NUM_BUTTONS; i++) begin
            check(press_count[i] == 1,
                  $sformatf("Test4-PressBTN%0d", i),
                  $sformatf(": press_count[%0d]=%0d (expected 1)", i, press_count[i]));
            check(release_count[i] == 0,
                  $sformatf("Test4-NoReleaseBTN%0d", i),
                  $sformatf(": release_count[%0d]=%0d (expected 0)", i, release_count[i]));
            check(btn_pressed[i] == 1'b1,
                  $sformatf("Test4-PressedStateBTN%0d", i),
                  $sformatf(": btn_pressed[%0d]=%b (expected 1)", i, btn_pressed[i]));
        end

        // Phase B: release all 4 buttons (hold for 25 ms)
        drive_btn(4'b1111, 25_000);
        repeat (100) @(posedge clk);

        // Verify 1 release per button
        for (int i = 0; i < TB_NUM_BUTTONS; i++) begin
            check(release_count[i] == 1,
                  $sformatf("Test4-ReleaseBTN%0d", i),
                  $sformatf(": release_count[%0d]=%0d (expected 1)", i, release_count[i]));
            check(btn_pressed[i] == 1'b0,
                  $sformatf("Test4-ReleasedStateBTN%0d", i),
                  $sformatf(": btn_pressed[%0d]=%b (expected 0)", i, btn_pressed[i]));
        end

        // =====================================================================
        // Test 5: Independence — BTN0 pressed while BTN1 bounces
        // Verify the LSB debouncer does not pick up bounce energy from
        // its neighbour.
        // =====================================================================
        $display("\n=== Test 5: Independence (BTN0 stable press, BTN1 bounces) ===");
        reset_pulse_counters();
        // BTN1 bounces for 50 ms (25 transitions, alternating every 1 ms)
        for (int i = 0; i < 25; i++) begin
            drive_btn(4'b1110, 1000);  // BTN0 held low (pressed), others released
            drive_btn(4'b1100, 1000);  // BTN0 low + BTN1 bouncing
        end
        // After 50 ms BTN0 should have been pressed (~30 ms ago > 20 ms),
        // BTN1 should still be 0 (bouncing never settled).
        repeat (100) @(posedge clk);
        check(press_count[0] == 1,
              "Test5-BTN0Pressed",
              $sformatf(": press_count[0]=%0d (expected 1)", press_count[0]));
        check(press_count[1] == 0,
              "Test5-BTN1DidNotPress",
              $sformatf(": press_count[1]=%0d (expected 0)", press_count[1]));

        // =====================================================================
        // Test 6: Multiple consecutive presses on BTN0
        // Press, release, press, release. Each transition should produce
        // exactly one pulse in the corresponding direction.
        // =====================================================================
        $display("\n=== Test 6: Multiple consecutive presses on BTN0 ===");
        // Ensure BTN0 starts RELEASED (Test 5 left it pressed) so every
        // press below is a genuine new edge. Reset counters AFTER this
        // hold so the release edge it generates is not counted.
        drive_btn(4'b1111, 25_000);
        reset_pulse_counters();
        // 3 press/release cycles
        for (int cyc = 0; cyc < 3; cyc++) begin
            drive_btn(4'b1110, 25_000);  // press
            drive_btn(4'b1111, 25_000);  // release
        end
        repeat (200) @(posedge clk);
        check(press_count[0] == 3,
              "Test6-ThreePressesBTN0",
              $sformatf(": press_count[0]=%0d (expected 3)", press_count[0]));
        check(release_count[0] == 3,
              "Test6-ThreeReleasesBTN0",
              $sformatf(": release_count[0]=%0d (expected 3)", release_count[0]));

        // =====================================================================
        // Test 7: Active-low polarity
        // The DUT must invert: btn_pressed_o[i] = 1 iff btn_i[i] = 0
        // (after debounce). Verify the steady-state mapping.
        // =====================================================================
        $display("\n=== Test 7: Active-low polarity (btn_pressed == ~btn after debounce) ===");
        reset_pulse_counters();
        // Drive an alternating pattern and let the debouncer settle
        drive_btn(4'b0101, 25_000);   // BTN1, BTN3 low
        repeat (100) @(posedge clk);
        check(btn_pressed[0] == 1'b0 && btn_pressed[1] == 1'b1 &&
              btn_pressed[2] == 1'b0 && btn_pressed[3] == 1'b1,
              "Test7-ActiveLowPolarity",
              $sformatf(": btn_pressed=%b (expected 0101)", btn_pressed));

        // =====================================================================
        // Test 8: Reset behaviour
        // After reset, btn_pressed_o must be 0 for all buttons.
        // =====================================================================
        $display("\n=== Test 8: Reset behaviour (btn_pressed returns to 0) ===");
        rst_n = 1'b0;
        btn   = {TB_NUM_BUTTONS{1'b1}};
        repeat (20) @(posedge clk);
        check(btn_pressed == {TB_NUM_BUTTONS{1'b0}},
              "Test8-ResetClearsBtnPressed",
              $sformatf(": btn_pressed=%b (expected 0000)", btn_pressed));
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge clk);
        $display("\n=== tb_btn_debounce Summary ===");
        $display("Total: %0d  Pass: %0d  Fail: %0d", total_count, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (250 ms — covers 5 ms of stimulus + debounce settle)
    // -------------------------------------------------------------------------
    initial begin
        #600_000_000;  // 600 ms
        $display("[%0t] TIMEOUT in tb_btn_debounce", $time);
        $finish;
    end

endmodule : tb_btn_debounce

`default_nettype wire
