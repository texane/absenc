--
-- https://en.wikipedia.org/wiki/Synchronous_Serial_Interface


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity slave_ssi is
generic
(
 CLK_FREQ: integer
);
port
(
 -- local clock
 clk: in std_logic;
 rst: in std_logic;

 -- master clock edges
 ma_clk_redge: in std_logic;
 ma_clk_fedge: in std_logic;

 -- the edge we are interested in
 ma_clk_edge: out std_logic;

 -- master data input, output
 miso: out std_logic;
 mosi: in std_logic;

 -- gate to drive output (1 to drive it)
 gate: out std_logic;

 -- actual data to send and length
 data: in std_logic_vector;
 len: in unsigned;

 -- timeout counter
 tm_match: in std_logic;
 tm_top: out unsigned;

 -- general purpose counter
 count_top: out unsigned;
 count_match: in std_logic;
 count_rst: out std_logic;

 -- piso register
 piso_rval: in std_logic_vector;
 piso_lval: in std_logic_vector;
 piso_ini: out std_logic_vector;
 piso_load: out std_logic;

 -- refer to package for comments
 ssi_flags: in std_logic_vector
);

end slave_ssi;


architecture slave_ssi_rtl of slave_ssi is

constant DATA_WITH: integer := data'length;

--
-- default timeout value. standard says:
-- https://upload.wikimedia.org/wikipedia/commons/8/8d/Ssisingletransmission.jpg

constant TM_VAL: integer := work.absenc_pkg.us_to_count
 (work.absenc_pkg.SLAVE_DEFAULT_TM_US, CLK_FREQ, tm_top'length);


--
-- state machine

type ssi_state_t is
(
 SSI_IDLE,
 SSI_DATA,
 SSI_DOT,
 SSI_TP
);

constant SSI_TMOUT: ssi_state_t := SSI_IDLE;
constant SSI_ERR: ssi_state_t := SSI_IDLE;

signal curr_state: ssi_state_t;
signal next_state: ssi_state_t;


--
-- terminating pattern bits

signal is_dot_bit: std_logic;


begin


--
-- state automaton

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  curr_state <= SSI_IDLE;
 elsif (tm_match = '1') then
  curr_state <= SSI_TMOUT;
 elsif (ma_clk_redge = '1') then
  curr_state <= next_state;
 end if;

end process;


process(curr_state, count_match, tm_match, is_dot_bit)
begin
 
 next_state <= curr_state;

 case curr_state is

  when SSI_IDLE =>
   next_state <= SSI_DATA;

  when SSI_DATA =>
   if count_match = '1' then
    if is_dot_bit = '1' then
     next_state <= SSI_DOT;
    else
     next_state <= SSI_TP;
    end if;
   else
    next_state <= SSI_DATA;
   end if;

  when SSI_DOT =>
   next_state <= SSI_TP;

  when SSI_TP =>
   if (tm_match = '1') then
    next_state <= SSI_IDLE;
   end if;

  when others =>
   next_state <= SSI_ERR;

 end case;

end process;


process
begin
 wait until rising_edge(clk);
 
 miso <= '0';
 count_top <= (count_top'range => '0');
 count_rst <= '0';
 piso_load <= '0';
 piso_ini <= (piso_ini'range => '0');
 is_dot_bit <= is_dot_bit;

 case curr_state is

  when SSI_IDLE =>
   miso <= '1';
   piso_load <= '1';
   piso_ini <= data;
   count_top <= len(count_top'range);
   count_rst <= '1';
   is_dot_bit <= ssi_flags(2) or ssi_flags(3) or ssi_flags(4);

  when SSI_DATA =>
   -- dynamic shift registers, ug901-vivado-synthesis.pdf, p.84
   miso <= piso_lval(to_integer(len) - 1);

  when SSI_DOT =>
   miso <= '0';

  when SSI_TP =>
   miso <= '0';

  when others =>

 end case;

end process;


--
-- timeout

tm_top <= to_unsigned(TM_VAL, tm_top'length);


--
-- master clock edge we are looking

ma_clk_edge <= ma_clk_redge;


--
-- gate always enabled

gate <= '1';


end slave_ssi_rtl; 
