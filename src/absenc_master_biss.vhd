library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity master_biss is

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
 ma_clk_fedge: in std_logic;
 ma_clk_redge: in std_logic;

 -- the edges we are interested in
 ma_clk_edge: out std_logic;

 -- master clock reset
 -- if ma_clk_rst_en, use ma_clk_rst_level
 ma_clk_rst_en: out std_logic;
 ma_clk_rst_val: out std_logic;

 -- master out, slave in
 mosi: out std_logic;
 miso: in std_logic;

 -- gate to drive output (1 to drive it)
 gate: out std_logic;

 -- desired data length
 len: in unsigned;

 -- timeout counter
 tm_match: in std_logic;
 tm_top: out unsigned;

 -- general purpose counter
 count_top: out unsigned;
 count_match: in std_logic;
 count_rst: out std_logic;

 -- sipo register
 sipo_val: in std_logic_vector;
 sipo_latch: out std_logic;

 -- enable data conversion stages
 gray_to_bin_en: out std_logic;
 lsb_to_msb_en: out std_logic
);

end entity;


architecture absenc_master_biss_rtl of master_biss is


--
-- default timeout value. standard says:
-- http://biss-interface.com/files/Bissinterface_c5es.pdf, page 18

constant TM_VAL: integer := work.absenc_pkg.us_to_count
 (15, CLK_FREQ, tm_top'length);


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
 elsif ((ma_clk_redge or tm_match) = '1') then
  curr_state <= next_state;
 end if;

end process;


process(curr_state, count_match, tm_match, miso)
begin
 
 next_state <= curr_state;

 case curr_state is

  when BISS_SYNC0 =>
   next_state <= BISS_SYNC1;

  when BISS_SYNC1 =>
   next_state <= BISS_ACK;

  when BISS_ACK =>
   -- TODO: check miso == 0
   next_state <= BISS_START;

  when BISS_START =>
   if miso = '1' then
    next_state <= BISS_CDS;
   end if;

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

 ma_clk_rst_en <= '0';
 count_top <= (count_top'range => '0');
 count_rst <= '0';
 sipo_latch <= '0';

 case curr_state is

  when BISS_SYNC0 =>

  when BISS_SYNC1 =>

  when BISS_ACK =>

  when BISS_START =>

  when BISS_CDS =>
   -- TODO: capture CDS
   count_top <= len(count_top'range);
   count_rst <= '1';

  when BISS_DATA =>

  when BISS_STOP =>
   sipo_latch <= '1';
   ma_clk_rst_en <= '1';

  when others =>

 end case;

end process;


--
-- clock reset or idle value

ma_clk_rst_val <= '1';


--
-- timeout

tm_top <= to_unsigned(TM_VAL, tm_top'length);


--
-- gray to binary disabled

gray_to_bin_en <= '0';


--
-- lsb to msb disabled

lsb_to_msb_en <= '0';


--
-- gate always disabled

gate <= '0';
mosi <= '0';


--
-- use rising edge

ma_clk_edge <= ma_clk_redge;


end architecture;
