derive_pll_clocks
derive_clock_uncertainty

# Treat the control, machine, and renderer domains as asynchronous at their
# boundaries; explicit synchronizers and asynchronous FIFOs implement the CDC.
set emu_clk_50  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_12  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_125 [get_clocks {emu|pll|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]

set_clock_groups -asynchronous \
	-group $emu_clk_50 \
	-group $emu_clk_12 \
	-group $emu_clk_125
