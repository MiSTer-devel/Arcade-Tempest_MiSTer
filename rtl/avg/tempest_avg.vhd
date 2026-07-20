-- Tempest Analog Vector Generator integration.
-- written 2026 by Videodr0me
--
-- Owns vector RAM, vector ROM, and color RAM. CPU vector-memory accesses take
-- the shared memory port; the PROM sequencer waits for a tagged response to
-- its current request whenever the CPU owns that port.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tempest_avg is
	port (
		clk               : in  std_logic;
		clken             : in  std_logic;
		avg_reset         : in  std_logic;
		avg_go            : in  std_logic;

		cpu_cs            : in  std_logic;
		cpu_rw            : in  std_logic;
		cpu_addr          : in  std_logic_vector(12 downto 0);
		cpu_data_in       : in  std_logic_vector(7 downto 0);
		cpu_data_out      : out std_logic_vector(7 downto 0);

		color_wr          : in  std_logic;
		color_addr        : in  std_logic_vector(3 downto 0);
		color_data        : in  std_logic_vector(3 downto 0);

		vector_rom_wr     : in  std_logic;
		vector_rom_addr   : in  std_logic_vector(11 downto 0);
		vector_rom_data   : in  std_logic_vector(7 downto 0);
		state_prom_wr     : in  std_logic;
		state_prom_addr   : in  std_logic_vector(7 downto 0);
		state_prom_data   : in  std_logic_vector(3 downto 0);

		halted            : out std_logic;
		list_wrap         : out std_logic;
		x_out             : out std_logic_vector(14 downto 0);
		y_out             : out std_logic_vector(14 downto 0);
		z_out             : out std_logic_vector(7 downto 0);
		color_out         : out std_logic_vector(3 downto 0);
		is_dot_out        : out std_logic
	);
end entity;

architecture rtl of tempest_avg is
	type byte_memory_t is array (0 to 4095) of std_logic_vector(7 downto 0);
	type color_memory_t is array (0 to 15) of std_logic_vector(3 downto 0);

	signal vector_ram : byte_memory_t;
	signal vector_rom : byte_memory_t;
	signal color_ram  : color_memory_t := (others => (others => '1'));

	attribute ramstyle : string;
	attribute ramstyle of vector_ram : signal is "M10K";
	attribute ramstyle of vector_rom : signal is "M10K";

	signal vector_ram_q : std_logic_vector(7 downto 0);
	signal vector_rom_q : std_logic_vector(7 downto 0);

	signal memory_addr      : std_logic_vector(12 downto 0) := (others => '0');
	signal memory_owner_avg : std_logic := '0';
	signal returned_addr_d  : std_logic_vector(12 downto 0) := (others => '0');
	signal returned_addr    : std_logic_vector(12 downto 0) := (others => '0');
	signal returned_avg_d   : std_logic := '0';
	signal returned_avg     : std_logic := '0';

	signal avg_addr       : std_logic_vector(12 downto 0);
	signal avg_fetch_addr : std_logic_vector(12 downto 0);
	signal avg_data       : std_logic_vector(7 downto 0);
	signal avg_data_valid : std_logic;
	signal color_index    : std_logic_vector(3 downto 0);
	signal color_ram_q    : std_logic_vector(3 downto 0);
begin
	-- AVG byte fetches occur in hardware latch order; CPU memory remains in
	-- normal low-byte/high-byte order.
	avg_fetch_addr <= avg_addr(12 downto 1) & not avg_addr(0);

	avg_data <= vector_ram_q when returned_addr(12) = '0' else vector_rom_q;

	avg_data_valid <= '1' when cpu_cs = '0'
	                             and returned_avg = '1'
	                             and returned_addr = avg_fetch_addr
	                  else '0';

	cpu_data_out <= vector_ram_q when cpu_addr(12) = '0' else vector_rom_q;
	color_ram_q <= color_ram(to_integer(unsigned(color_index)));

	core : entity work.avg_prom_core
		port map (
			clk             => clk,
			clken           => clken,
			avg_data_valid  => avg_data_valid,
			vgrst           => avg_reset,
			vggo            => avg_go,
			halted          => halted,
			xout            => x_out,
			yout            => y_out,
			zout            => z_out,
			color_index     => color_index,
			color_data_in   => color_ram_q,
			colorout        => color_out,
			is_dot          => is_dot_out,
			list_wrap       => list_wrap,
			avg_addr_out    => avg_addr,
			avg_data_in     => avg_data,
			prom_addr       => state_prom_addr,
			prom_data       => state_prom_data,
			prom_wr         => state_prom_wr
		);

	process (clk)
	begin
		if rising_edge(clk) then
			vector_ram_q <= vector_ram(to_integer(unsigned(memory_addr(11 downto 0))));
			vector_rom_q <= vector_rom(to_integer(unsigned(memory_addr(11 downto 0))));

			if vector_rom_wr = '1' then
				vector_rom(to_integer(unsigned(vector_rom_addr))) <= vector_rom_data;
			end if;

			if color_wr = '1' then
				color_ram(to_integer(unsigned(color_addr))) <= color_data;
			end if;

			if cpu_cs = '1' and cpu_rw = '0' and cpu_addr(12) = '0' then
				vector_ram(to_integer(unsigned(cpu_addr(11 downto 0)))) <= cpu_data_in;
			end if;

			if avg_reset = '1' then
				memory_addr      <= (others => '0');
				memory_owner_avg <= '0';
				returned_addr_d  <= (others => '0');
				returned_addr    <= (others => '0');
				returned_avg_d   <= '0';
				returned_avg     <= '0';
			else
				returned_addr_d <= memory_addr;
				returned_addr   <= returned_addr_d;
				returned_avg_d  <= memory_owner_avg;
				returned_avg    <= returned_avg_d;

				if cpu_cs = '1' then
					memory_addr      <= cpu_addr;
					memory_owner_avg <= '0';
				else
					memory_addr      <= avg_fetch_addr;
					memory_owner_avg <= '1';
				end if;
			end if;
		end if;
	end process;
end architecture;
