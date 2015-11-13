-- BISS automaton notes
-- point to point configuration
-- http://biss-interface.com/files/Bissinterface_c5es.pdf, figure 1
-- slave idle state (SLO = 1)
-- first rising edge of MA is for slave sync
-- second rising edge of MA is for slave ack (SLO = 0)
-- start bit (SLO = 1)
-- CDS bit
-- data bits
-- stop bit (SLO = 0) and CDM bit (MA)


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity slave_biss is
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
 piso_load: out std_logic
);

end slave_biss;


architecture slave_biss_rtl of slave_biss is

--
-- default timeout value. standard says:
-- http://biss-interface.com/files/Bissinterface_c5es.pdf, page 18

constant TM_VAL: integer := work.absenc_pkg.us_to_count
 (work.absenc_pkg.SLAVE_DEFAULT_TM_US, CLK_FREQ, tm_top'length);

--
-- state machine

type biss_state_t is
(
 BISS_SYNC0,
 BISS_SYNC1,
 BISS_ACK,
 BISS_START,
 BISS_CDS,
 BISS_DATA,
 BISS_STOP
);

constant BISS_TMOUT: biss_state_t := BISS_SYNC0;
constant BISS_ERR: biss_state_t := BISS_SYNC0;

signal curr_state: biss_state_t;
signal next_state: biss_state_t;


begin


--
-- state automaton

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  curr_state <= BISS_SYNC0;
 elsif (tm_match = '1') then
  curr_state <= BISS_TMOUT;
 elsif (ma_clk_redge = '1') then
  curr_state <= next_state;
 end if;

end process;


process(curr_state, count_match, tm_match)
begin
 
 next_state <= curr_state;

 case curr_state is

  when BISS_SYNC0 =>
   next_state <= BISS_SYNC1;

  when BISS_SYNC1 =>
   next_state <= BISS_ACK;

  when BISS_ACK =>
   next_state <= BISS_START;

  when BISS_START =>
   next_state <= BISS_CDS;

  when BISS_CDS =>
   next_state <= BISS_DATA;

  when BISS_DATA =>
   if count_match = '1' then
    next_state <= BISS_STOP;
   else
    next_state <= BISS_DATA;
   end if;

  when BISS_STOP =>
   if (tm_match = '1') then
    next_state <= BISS_SYNC0;
   end if;

  when others =>
   next_state <= BISS_ERR;

 end case;

end process;


process
begin
 wait until rising_edge(clk);
 
 miso <= '0';
 count_top <= (count_top'range => '0');
 count_rst <= '0';
 piso_load <= '0';

 case curr_state is

  when BISS_SYNC0 =>
   miso <= '1';
   count_rst <= '1';

  when BISS_SYNC1 =>
   miso <= '1';
   count_rst <= '1';

  when BISS_ACK =>
   miso <= '0';

  when BISS_START =>
   miso <= '1';

  when BISS_CDS =>
   -- TODO: output CDS bit
   miso <= '0';

   count_top <= len(count_top'range);
   count_rst <= '1';

   piso_ini <= data;
   piso_load <= '1';

  when BISS_DATA =>
   -- dynamic shift registers, ug901-vivado-synthesis.pdf, p.84
   miso <= piso_lval(to_integer(len) - 1);

  when BISS_STOP =>
   -- TODO: capture CDM
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


end slave_biss_rtl; 
