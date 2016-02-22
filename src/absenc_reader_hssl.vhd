--
-- HSSL reader implementation
-- sampling is done on the falling edge
-- state is updated on the rising edge
-- data sent MSb first, encoded using 2's complement


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity reader_hssl is
generic
(
 CLK_FREQ: integer
);
port
(
 -- local clock
 clk: in std_logic;
 rst: in std_logic;

 -- master clock
 sclk: in std_logic;

 -- sender out, reader in
 sori: in std_logic;

 -- actual data to send and length
 data: out std_logic_vector;

 -- configuration
 len: in unsigned;
 tm_gap: in unsigned
);

end entity;


architecture reader_hssl_rtl of reader_hssl is

constant DATA_LEN: integer := data'length;


--
-- hssl state machine

type hssl_state_t is
(
 HSSL_IDLE,
 HSSL_DATA,
 HSSL_LATCH,
 HSSL_TP
);

constant HSSL_TMOUT: hssl_state_t := HSSL_IDLE;
constant HSSL_ERR: hssl_state_t := HSSL_IDLE;

signal curr_state: hssl_state_t;
signal next_state: hssl_state_t;


--
-- conversion pipeline

type conv_state_t is
(
 CONV_WAIT_LATCH,
 CONV_EXTEND_SIGN,
 CONV_DONE
);

constant CONV_ERR: conv_state_t := CONV_WAIT_LATCH;

signal conv_curr_state: conv_state_t;
signal conv_next_state: conv_state_t;

signal latched_data: std_logic_vector(data'range);
signal signed_data: std_logic_vector(data'range);
signal conv_data: std_logic_vector(data'range);
signal len_mask: std_logic_vector(data'range);


--
-- timeout counter

signal tm_val: unsigned(tm_gap'length - 1 downto 0);
alias tm_top: unsigned(tm_val'range) is tm_gap(tm_gap'range);
signal tm_match: std_logic;


--
-- general counter

signal count_val:
 unsigned(work.absenc_pkg.integer_length(DATA_LEN) - 1 downto 0);
signal count_top: unsigned(count_val'range);
signal count_top_latched: unsigned(count_val'range);
signal count_rst: std_logic;
signal count_match: std_logic;


--
-- sender clock edges
-- redge is for rising edge
-- fedge is for falling edge
-- edge is the one selected by encoder

signal sclk_pre: std_logic;
signal sclk_redge: std_logic;
signal sclk_fedge: std_logic;
signal sclk_edge: std_logic;


--
-- master clock filter

signal sclk_buf: std_logic_vector(2 downto 0);
signal sclk_filt: std_logic;


--
-- serial in, parallel out (SIPO) register

signal sipo_val: std_logic_vector(DATA_LEN - 1 downto 0);
signal sipo_latch: std_logic;


begin


--
-- master clock filter
-- sometimes, slave detects fantom master clock edges
-- filtering the master clock fixes this issue

process
begin
 wait until rising_edge(clk);
 sclk_buf <= sclk & sclk_buf(sclk_buf'length - 1 downto 1);
end process;

process(sclk_buf, sclk_filt)
begin
 sclk_filt <= sclk_filt;

 if sclk_buf = (sclk_buf'range => '0') then
  sclk_filt <= '0';
 elsif sclk_buf = (sclk_buf'range => '1') then
  sclk_filt <= '1';
 end if;
end process;


--
-- master clock edge detection

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  sclk_redge <= '0';
  sclk_fedge <= '0';
  sclk_pre <= sclk_filt;
 else
  sclk_redge <= (not sclk_pre) and sclk_filt;
  sclk_fedge <= sclk_pre and (not sclk_filt);
  sclk_pre <= sclk_filt;
 end if;

end process;

sclk_edge <= sclk_redge;


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
 elsif (sclk_edge = '1') then
  count_val <= count_val + 1;
 end if;

end process;


--
-- general purpose counter comparator
-- count_match set to one when count_val = count_top

process
begin

 wait until rising_edge(clk);

 if (count_rst = '1') then
  count_top_latched <= count_top;
 end if;

end process;

count_match <= '1' when (count_val = count_top_latched) else '0';


--
-- timeout counter
-- tm_val decrement from tm_top to 0
-- tm_val reloaded at sclk_edge

process
begin
 wait until rising_edge(clk);

 tm_match <= '0';

 if ((rst or sclk_edge) = '1') then
  tm_val <= tm_top;
 elsif (tm_val = 0) then
  tm_val <= tm_top;
  tm_match <= '1';
 else
  tm_val <= tm_val - 1;
 end if;

end process;


--
-- sipo register

process
begin

 wait until rising_edge(clk);

 if (sclk_fedge = '1') then
  sipo_val <= sipo_val(sipo_val'length - 2 downto 0) & sori;
 end if;

end process;


--
-- data conversion pipeline. ordering:
-- data read (latched at sipo_latch redge from sipo_val)
-- extend_sign
-- latched to data
-- bin_to_sfixed (implemented in top)

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  conv_curr_state <= CONV_WAIT_LATCH;
 else
  conv_curr_state <= conv_next_state;
 end if;

end process;


process(conv_curr_state, sipo_latch)
begin
 
 conv_next_state <= conv_curr_state;

 case conv_curr_state is

  when CONV_WAIT_LATCH =>
   if (sipo_latch = '1') then
    conv_next_state <= CONV_EXTEND_SIGN;
   end if;

  when CONV_EXTEND_SIGN =>
   conv_next_state <= CONV_DONE;

  when CONV_DONE =>
   conv_next_state <= CONV_WAIT_LATCH;

  when others =>
   conv_next_state <= CONV_ERR;

 end case;

end process;


process
begin
 wait until rising_edge(clk);

 latched_data <= latched_data;
 conv_data <= conv_data;

 case conv_curr_state is

  when CONV_WAIT_LATCH =>
   latched_data <= sipo_val and len_mask;

  when CONV_EXTEND_SIGN =>

  when CONV_DONE =>
   conv_data <= signed_data;

  when others =>

 end case;

end process;

data <= conv_data;


len_to_mask: work.absenc_pkg.len_to_mask
port map
(
 len => len,
 mask => len_mask
);


extend_sign: work.absenc_pkg.extend_sign
port map
(
 data_len => len,
 data_in => latched_data,
 data_out => signed_data,
 len_mask => len_mask
);


--
-- state automaton

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


process(curr_state, count_match, tm_match)
begin
 
 next_state <= curr_state;

 case curr_state is

  when HSSL_IDLE =>
   next_state <= HSSL_DATA;

  when HSSL_DATA =>
   if count_match = '1' then
    next_state <= HSSL_LATCH;
   else
    next_state <= HSSL_DATA;
   end if;

  when HSSL_LATCH =>
   next_state <= HSSL_TP;

  when HSSL_TP =>
   if (tm_match = '1') then
    next_state <= HSSL_IDLE;
   end if;

  when others =>
   next_state <= HSSL_ERR;

 end case;

end process;


process
begin
 wait until rising_edge(clk);

 count_top <= (count_top'range => '0');
 count_rst <= '0';
 sipo_latch <= '0';

 case curr_state is

  when HSSL_IDLE =>
   count_top <= len(count_top'range);
   count_rst <= '1';

  when HSSL_DATA =>

  when HSSL_LATCH =>
   sipo_latch <= '1';

  when HSSL_TP =>

  when others =>

 end case;

end process;


end reader_hssl_rtl; 
