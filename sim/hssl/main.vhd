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
-- configuration constants

constant CLK_FREQ: integer := 50000000;

constant DATA_LEN: integer := 8;
constant LEN_WIDTH: integer := work.absenc_pkg.integer_length(1 + DATA_LEN);

--
-- local clock and reset

signal rst: std_ulogic;
signal clk: std_ulogic;

--
-- sender data

constant partial_data: std_logic_vector := "01100101";

-- constant partial_zeros:
--  std_logic_vector(DATA_LEN - 1 downto partial_data'length) :=
--  (others => '0');

-- constant sender_data: std_logic_vector(DATA_LEN - 1 downto 0) :=
-- partial_zeros & partial_data;

constant sender_data: std_logic_vector(DATA_LEN - 1 downto 0) :=
 partial_data;

constant len: unsigned := to_unsigned(partial_data'length, LEN_WIDTH);

--
-- reader writer data

signal reader_data: std_logic_vector(DATA_LEN - 1 downto 0);

--
-- master clock frequency divider
-- 1MHz clock

constant sclk_fdiv: unsigned := to_unsigned(integer(50), 8);

--
-- clock data signals

signal sori: std_logic;


--
-- timeout counter

constant TM_MAX: integer := work.absenc_pkg.us_to_count
 (100, CLK_FREQ, integer'high);

constant TM_LEN: integer :=
 work.absenc_pkg.integer_length(TM_MAX);

constant DEFAULT_TM_GAP: integer := work.absenc_pkg.us_to_count
 (5, CLK_FREQ, TM_LEN);

signal tm_val: unsigned(TM_LEN - 1 downto 0);
signal tm_top: unsigned(tm_val'range);
signal tm_match: std_logic;
signal tm_en: std_logic;

signal tm_gap: unsigned(TM_LEN - 1 downto 0);


--
-- general counter

signal count_val: unsigned(LEN_WIDTH - 1 downto 0);
signal count_top: unsigned(count_val'range);
signal count_top_latched: unsigned(count_val'range);
signal count_rst: std_logic;
signal count_match: std_logic;


--
-- parallel in, serial out (PISO) register

signal piso_val: std_logic_vector(sender_data'range);
signal piso_ini: std_logic_vector(sender_data'range);
signal piso_load: std_logic;


--
-- sender clock

signal sclk_rst_en: std_logic;

signal sclk_val: std_logic;
signal sclk_en: std_logic;

signal sclk_half_fdiv: unsigned(sclk_fdiv'length - 1 downto 0);
signal sclk_half_count: unsigned(sclk_half_fdiv'length - 1 downto 0);
signal sclk_half_match: std_logic;

signal sclk_redge: std_logic;
signal sclk_fedge: std_logic;


--
-- hssl sender state machine

type hssl_state_t is
(
 HSSL_IDLE,
 HSSL_DATA,
 HSSL_TP
);

constant HSSL_TMOUT: hssl_state_t := HSSL_IDLE;
constant HSSL_ERR: hssl_state_t := HSSL_IDLE;

signal curr_state: hssl_state_t;
signal next_state: hssl_state_t;


begin


--
-- sender clock generation
-- sender clock frequency is clk divided by sclk_fdiv
-- generate edges using a counter from sclk_fdiv/2 to 0

sclk_half_fdiv <= sclk_fdiv srl 1;
sclk_half_match <= '1' when sclk_half_count = 1 else '0';

process
begin
 wait until rising_edge(clk);

 if ((rst or sclk_rst_en or sclk_half_match) = '1') then
  sclk_half_count <= sclk_half_fdiv;
 else
  sclk_half_count <= sclk_half_count - 1;
 end if;

end process;

process
begin
 wait until rising_edge(clk);

 if ((rst or sclk_rst_en) = '1') then
  sclk_val <= '0';
 else
  sclk_val <= sclk_val xor sclk_half_match;
 end if;

end process;

process
begin
 wait until rising_edge(clk);
 sclk_redge <= sclk_half_match and (not sclk_val);
end process;

process
begin
 wait until rising_edge(clk);
 sclk_fedge <= sclk_half_match and sclk_val;
end process;


--
-- general purpose counter
-- monotically incrementing
-- increment every master edge
-- starts from 1

process
begin

 wait until rising_edge(clk);

 if (count_rst = '1') then
  count_val <= to_unsigned(integer(1), count_val'length);
 elsif (sclk_fedge = '1') then
  count_val <= count_val + 1;
 end if;

end process;

count_match <= '1' when (count_val = count_top) else '0';


--
-- timeout counter
-- tm_val decrement from tm_top to 0
-- tm_val reloaded at sclk_edge

tm_top <= to_unsigned(DEFAULT_TM_GAP, tm_top'length);

process
begin
 wait until rising_edge(clk);

 tm_match <= '0';

 if (rst = '1') then
  tm_val <= tm_top;
 elsif (tm_val = 0) then
  tm_val <= tm_top;
  tm_match <= '1';
 elsif (tm_en = '1') then
  tm_val <= tm_val - 1;
 end if;

end process;


--
-- hssl reader

tm_gap <= to_unsigned(DEFAULT_TM_GAP, tm_top'length);

hssl_reader: work.absenc_pkg.reader_hssl
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 sclk => sclk_en,
 sori => sori,
 data => reader_data,
 len => len,
 tm_gap => tm_gap
);


--
-- piso right shifted register

process
begin

 wait until rising_edge(clk); 

 if (piso_load = '1') then
  piso_val <= piso_ini;
 elsif (sclk_redge = '1') then
  piso_val <= '0' & piso_val(piso_val'length - 1 downto 1);
 end if;

end process;


--
-- HSSL sender

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  curr_state <= HSSL_IDLE;
 elsif (tm_match = '1') then
  curr_state <= HSSL_TMOUT;
 elsif (sclk_redge = '1') then
  curr_state <= next_state;
 end if;

end process;

process(curr_state, count_match)
begin
 
 next_state <= curr_state;

 case curr_state is

  when HSSL_IDLE =>
   next_state <= HSSL_DATA;

  when HSSL_DATA =>
   if count_match = '1' then
    next_state <= HSSL_TP;
   else
    next_state <= HSSL_DATA;
   end if;

  when HSSL_TP =>

  when others =>
   next_state <= HSSL_ERR;

 end case;

end process;


count_top <= len;

process
begin
 wait until rising_edge(clk);

 count_rst <= '0';
 piso_load <= '0';
 piso_ini <= (piso_ini'range => '0');
 sori <= '0';
 tm_en <= '0';
 sclk_en <= sclk_val;

 case curr_state is

  when HSSL_IDLE =>
   count_rst <= '1';
   piso_load <= '1';
   piso_ini <= sender_data(piso_ini'range);

  when HSSL_DATA =>
   sori <= piso_val(0);

  when HSSL_TP =>
   sori <= '0';
   tm_en <= '1';
   sclk_en <= '0';

  when others =>

 end case;

end process;


end rtl;
