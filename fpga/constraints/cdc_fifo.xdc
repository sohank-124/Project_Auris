# FIFO crossing constraints: explicit XDC commands (no Tcl loops/conditionals).
# Gray pointer -> first synchronizer: 10 ns is below the fastest update
# period (96 MHz). Second synchronizer stages retain normal setup/hold.
# RAM words remain stable until consumed, with availability communicated by
# the two-stage synchronized write pointer. Bound RAM-to-consumer propagation
# to 10 ns; do not impose a synchronous BCLK/DSP edge relationship.
# Read-address -> data paths start at read-domain registers and remain timed.
# This file must be processed after arty_s7_25.xdc defines the clocks.

# u_cdc_i2s_l
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_l/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_l/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_l/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_l/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_l/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_l/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_l/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_l/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_pins -hierarchical -filter {NAME =~ u_cdc_i2s_l/mem_reg* && REF_PIN_NAME == CLK}] -to [get_clocks -of_objects [get_pins {u_cdc_i2s_l/rd_ptr_bin_reg[0]/C}]]

# u_cdc_i2s_r
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_r/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_r/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_r/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_r/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_r/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_r/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_i2s_r/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_i2s_r/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_pins -hierarchical -filter {NAME =~ u_cdc_i2s_r/mem_reg* && REF_PIN_NAME == CLK}] -to [get_clocks -of_objects [get_pins {u_cdc_i2s_r/rd_ptr_bin_reg[0]/C}]]

# u_cdc_o2i_l
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_l/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_l/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_l/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_l/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_l/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_l/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_l/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_l/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_pins -hierarchical -filter {NAME =~ u_cdc_o2i_l/mem_reg* && REF_PIN_NAME == CLK}] -to [get_clocks -of_objects [get_pins {u_cdc_o2i_l/rd_ptr_bin_reg[0]/C}]]

# u_cdc_o2i_r
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_r/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_r/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_r/wr_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_r/wr_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_r/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_r/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_bus_skew 10.0 -from [get_cells -hierarchical -regexp {u_cdc_o2i_r/rd_ptr_gray_reg\[[0-9]+\]}] -to [get_cells -hierarchical -regexp {u_cdc_o2i_r/rd_ptr_gray_a_reg\[[0-9]+\]}]
set_max_delay -datapath_only 10.0 -from [get_pins -hierarchical -filter {NAME =~ u_cdc_o2i_r/mem_reg* && REF_PIN_NAME == CLK}] -to [get_clocks -of_objects [get_pins {u_cdc_o2i_r/rd_ptr_bin_reg[0]/C}]]

# Sticky RX-drop event: bound the first-stage crossing only.
set_max_delay -datapath_only 10.0 -from [get_cells rx_drop_sticky_reg] -to [get_cells rx_drop_meta_reg]
