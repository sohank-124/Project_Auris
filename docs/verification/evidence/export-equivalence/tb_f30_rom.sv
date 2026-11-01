`timescale 1ns/1ps
module tb_f30_rom;
  logic clk = 0;
  logic [7:0] addr = 0;
  wire [15:0] data;
  logic test_done = 0;
  integer fd;
  always #5 clk = ~clk;
  window_rom dut (.clk_i(clk), .addr_i(addr), .data_o(data));
  initial begin
    fd = $fopen("rom_words.txt", "w");
    if (!fd) $fatal(1, "Cannot open dump");
    if (auris_pkg::FFT_LEN != 256 || auris_pkg::WINDOW_DATA_W != 16)
      $fatal(1, "Unexpected production defaults");
    for (int i=0; i<256; i++) begin
      @(negedge clk); addr = i;
      @(posedge clk); #1;
      if ($isunknown(data)) $fatal(1, "Unknown ROM word %0d", i);
      $fdisplay(fd, "%0d %04h", i, data);
    end
    $fclose(fd);
    test_done = 1;
    $display("F30_ROM_DUMP_PASS count=256 LEN=256 WIDTH=16");
    $finish;
  end
  initial begin #10000; $fatal(1, "F30 watchdog"); end
endmodule
