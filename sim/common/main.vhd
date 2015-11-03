--
-- delayed signal
-- delay time resolution is 1 / CLK_FREQ


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


library work;


entity delay is
generic
(
 CLK_FREQ: integer;
 DELAY_NS: real := 0.0
);
port
(
 -- local clock
 clk: in std_logic;

 -- signal to be delayed
 sin: in std_logic;

 -- delayed signal
 sout: out std_logic
);

end delay;


architecture delay_rtl of delay is


--
-- convert nanoseconds to count at freq

function ns_to_count
(
 freq: real;
 ns: real
)
return integer is
begin
 -- ns = count * (1 / freq) * 1000000000
 -- count = (ns * freq) / 1000000000
 return integer(ceil((ns * freq) / 1000000000.0));
end ns_to_count;


--
-- delay buffer
-- delay_count the buffer depth
-- add a small constant to allow DELAY_NS to be 0

constant DELAY_COUNT: integer := ns_to_count(DELAY_NS + 0.01, real(CLK_FREQ));
signal delay_buf: std_logic_vector(DELAY_COUNT - 1 downto 0);


begin


gen_zero: if DELAY_NS = 0.0 generate
 delay_buf(0) <= sin;
end generate gen_zero;


gen_one: if ((DELAY_NS /= 0.0) and (DELAY_COUNT = 1)) generate
 process
 begin
  wait until rising_edge(clk);
  delay_buf(0) <= sin;
 end process;
end generate gen_one;


gen_not_one: if DELAY_COUNT /= 1 generate
 process
 begin
  wait until rising_edge(clk);
  delay_buf <= sin & delay_buf(delay_buf'length - 1 downto 1);
 end process;
end generate gen_not_one;


sout <= delay_buf(0);


end delay_rtl;


--
-- main

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;


library work;


entity main is end main;


architecture rtl of main is


--
-- cable length to nanoseconds

function cable_len_to_ns
(
 -- cable length in meters
 len: real
)
return real is
 -- light speed in m/s
 constant C: real := 299792458.0;
 -- propagation delay in ns/m (around 5ns/m)
 constant PROP_DELAY_NS: real := 1000000000.0 / (0.64 * C);
begin
 return len * PROP_DELAY_NS;
end cable_len_to_ns;


--
-- configuration constants

constant CLK_FREQ: integer := 50000000;

constant DATA_LEN: integer := 16;
constant LEN_WIDTH: integer := work.absenc_pkg.integer_length(DATA_LEN);

--
-- local clock and reset

signal rst: std_ulogic;
signal clk: std_ulogic;

--
-- data sent by slave to master

constant partial_data: std_logic_vector := "1001010001";

constant partial_zeros:
 std_logic_vector(DATA_LEN - 1 downto partial_data'length) :=
 (others => '0');

constant slave_data: std_logic_vector(DATA_LEN - 1 downto 0) :=
 partial_zeros & partial_data;

constant len: unsigned := to_unsigned(partial_data'length, LEN_WIDTH);

--
-- data read by master from slave

signal master_data: std_logic_vector(DATA_LEN - 1 downto 0);

--
-- master clock frequency divider
-- 1MHz clock

constant ma_fdiv: unsigned := to_unsigned(integer(50), 8);

--
-- selected encoder type

signal enc_type: integer;

--
-- master slave outputs

signal mosi: std_logic;
signal miso: std_logic;

signal ma_clk: std_logic;


--
-- delayed master clock

signal ma_delayed_clk: std_logic;


begin


delay: entity work.delay
generic map
(
 CLK_FREQ => CLK_FREQ,
 DELAY_NS => cable_len_to_ns(30.0)
)
port map
(
 clk => clk,
 sin => ma_clk,
 sout => ma_delayed_clk
);


slave: work.absenc_pkg.slave
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 ma_clk => ma_delayed_clk,
 miso => miso,
 mosi => mosi,
 gate => open,
 data => slave_data,
 len => len,
 enc_type => enc_type,
 ssi_flags => work.absenc_pkg.SSI_DEFAULT_FLAGS
);


master: work.absenc_pkg.master
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 ma_fdiv => ma_fdiv,
 ma_clk => ma_clk,
 mosi => mosi,
 miso => miso,
 gate => open,
 data => master_data,
 len => len,
 enc_type => enc_type,
 ssi_flags => work.absenc_pkg.SSI_DEFAULT_FLAGS,
 ssi_delay_fdiv => work.absenc_pkg.SSI_DEFAULT_DELAY_FDIV
);


end rtl;
