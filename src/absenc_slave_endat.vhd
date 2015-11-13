--
-- endat encoder implementation
--
-- notes from endat2.2 technical information documentation
-- esp. refer to page 6, Position Values
--
-- command format:
-- send data without additional parameter
-- 2T(x2) & mode(x6) & 2T(x2) & S(x1) & F1(x1) & DATA(xlen) & CRC(x5)
--
-- recovery time:
-- 10 to 30 us for endat2.1
-- 1.25 to 3.75 us for endat2.2
--
-- samples at rising edge
--
-- data sent LSbit first


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity slave_endat is
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

end slave_endat;


architecture slave_endat_rtl of slave_endat is


--
-- default timeout value. standard says: 10 to 30 us

constant TM_VAL: integer := work.absenc_pkg.us_to_count
 (work.absenc_pkg.SLAVE_DEFAULT_TM_US, CLK_FREQ, tm_top'length);


--
-- main state machine

type endat_state_t is
(
 ENDAT_IDLE,
 ENDAT_T0,
 ENDAT_T1,
 ENDAT_MODE,
 ENDAT_T3,
 ENDAT_T4,
 
 ENDAT_T5,

 ENDAT_START,
 ENDAT_F1,
 ENDAT_DATA,
 
 ENDAT_CRC5_FIRST,
 ENDAT_CRC5_CONT
);

constant ENDAT_TMOUT: endat_state_t := ENDAT_IDLE;
constant ENDAT_ERR: endat_state_t := ENDAT_IDLE;

signal curr_state: endat_state_t;
signal next_state: endat_state_t;


--
-- serial in, parallel out (sipo) register

signal sipo_val: std_logic_vector(6 - 1 downto 0);


begin


--
-- sipo register
-- sampled at falling edge by slave

process
begin

 wait until rising_edge(clk);

 if (ma_clk_redge = '1') then
  sipo_val <= sipo_val(sipo_val'length - 2 downto 0) & mosi;
 end if;

end process;


--
-- state automaton

process
begin

 wait until rising_edge(clk);

 if (rst = '1') then
  curr_state <= ENDAT_IDLE;
 elsif (tm_match = '1') then
  curr_state <=  ENDAT_TMOUT;
 elsif (ma_clk_fedge = '1') then
  curr_state <= next_state;
 end if;

end process;


process(curr_state, count_match, sipo_val, tm_match)
begin
 
 next_state <= curr_state;

 case curr_state is

  when ENDAT_IDLE =>
   next_state <= ENDAT_T0;

  when ENDAT_T0 =>
   next_state <= ENDAT_T1;

  when ENDAT_T1 =>
   next_state <= ENDAT_MODE;

  when ENDAT_MODE =>
   -- serial register value is sampled at rising edge
   -- but next_state computed at falling edge. thus
   -- we compare here when count_match
   if count_match = '1' then
    if sipo_val(5 downto 0) = "000111" then
     next_state <= ENDAT_T3;
    else
     next_state <= ENDAT_ERR;
    end if;
   end if;
    
  when ENDAT_T3 =>
   next_state <= ENDAT_T4;

  when ENDAT_T4 =>
   next_state <= ENDAT_T5;

  when ENDAT_T5 =>
   next_state <= ENDAT_START;

  when ENDAT_START =>
   next_state <= ENDAT_F1;

  when ENDAT_F1 =>
   next_state <= ENDAT_DATA;

  when ENDAT_DATA =>
   if count_match = '1' then
    next_state <= ENDAT_CRC5_FIRST;
   end if;

  when ENDAT_CRC5_FIRST =>
   next_state <= ENDAT_CRC5_CONT;

  when ENDAT_CRC5_CONT =>
   if count_match = '1' then
    next_state <= ENDAT_IDLE;
   end if;

  when others =>
   next_state <= ENDAT_ERR;

  end case;

end process;


process
begin

 wait until rising_edge(clk);

 gate <= '0'; 
 miso <= '0';
 count_top <= (count_top'range => '0');
 count_rst <= '0';
 piso_load <= '0';

 case curr_state is

  when ENDAT_IDLE =>

  when ENDAT_T0 =>

  when ENDAT_T1 =>
   count_top <= to_unsigned(integer(6), count_top'length);
   count_rst <= '1';

  when ENDAT_MODE =>

  when ENDAT_T3 =>

  when ENDAT_T4 =>

  when ENDAT_T5 =>
   -- data line stabilization state
   gate <= '1';
   miso <= '0';

  when ENDAT_START =>
   gate <= '1';
   miso <= '1';

  when ENDAT_F1 =>
   -- error bit (F1)
   gate <= '1';
   miso <= '0';

   count_top <= len(count_top'range);
   count_rst <= '1';

   piso_ini <= data;   
   piso_load <= '1';

  when ENDAT_DATA =>
   gate <= '1';
   miso <= piso_rval(0);

  when ENDAT_CRC5_FIRST =>
   count_top <= to_unsigned(integer(5 - 1), count_top'length);
   count_rst <= '1';
   gate <= '1';
   miso <= '0';

  when ENDAT_CRC5_CONT =>
   gate <= '1';
   miso <= '0';

  when others =>

 end case;

end process;


--
-- timeout

tm_top <= to_unsigned(TM_VAL, tm_top'length);


--
-- master clock edge we are looking

ma_clk_edge <= ma_clk_fedge;


end slave_endat_rtl; 
