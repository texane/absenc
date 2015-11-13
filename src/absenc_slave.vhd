library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;


entity slave is

generic
(
 CLK_FREQ: integer;
 ENABLE_ENDAT: boolean;
 ENABLE_BISS: boolean;
 ENABLE_SSI: boolean
);
port
(
 -- local clock
 clk: in std_logic;
 rst: in std_logic;

 -- master clock and data
 ma_clk: in std_logic;
 miso: out std_logic;
 mosi: in std_logic;
 gate: out std_logic;

 -- data and length
 data: in std_logic_vector;
 len: in unsigned;

 -- encoder type
 enc_type: in integer;

 -- ssi specific control registers
 ssi_flags: in std_logic_vector
);

end slave;


architecture absenc_slave_rtl of slave is

constant DATA_LEN: integer := data'length;

--
-- timeout counter

constant TM_MAX: integer := work.absenc_pkg.us_to_count
 (work.absenc_pkg.MAX_TM_US, CLK_FREQ, integer'high);

constant TM_LEN: integer :=
 work.absenc_pkg.integer_length(TM_MAX);

constant DEFAULT_TM_TOP: integer := work.absenc_pkg.us_to_count
 (work.absenc_pkg.SLAVE_DEFAULT_TM_US, CLK_FREQ, TM_LEN);

signal tm_val: unsigned(TM_LEN - 1 downto 0);
signal tm_top: unsigned(tm_val'range);
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
-- parallel in, serial out (PISO) register
-- rval is the right shifted value (for lsb)
-- lval is the left shifted value (for msb)

signal piso_rval: std_logic_vector(data'range);
signal piso_lval: std_logic_vector(data'range);
signal piso_ini: std_logic_vector(data'range);
signal piso_load: std_logic;

--
-- master clock edges
-- redge is for rising edge
-- fedge is for falling edge
-- edge is the one selected by encoder

signal ma_clk_pre: std_logic;
signal ma_clk_redge: std_logic;
signal ma_clk_fedge: std_logic;
signal ma_clk_edge: std_logic;

--
-- master clock filter

signal ma_clk_buf: std_logic_vector(2 downto 0);
signal ma_clk_filt: std_logic;

--
-- encoder multiplexed signal
--
-- the mux size depends on ENABLE_xxx generics. the idea is to eliminate
-- unneeded FPGA logic by instantiating only modules enabled by the generics.
-- to do so, we have functions that translate from ENC_TYPE_xxx to ENC_MUX_xxx
-- and vice versa. ENC_TYPE_xxx represent all the possible encoders, while
-- ENC_MUX_xxx represent an encoder index in the mux, if enabled by generics.

subtype tm_val_t is unsigned(tm_val'range);
type tm_val_array_t is array(integer range<>) of tm_val_t;

subtype count_val_t is unsigned(count_val'range);
type count_val_array_t is array(integer range<>) of count_val_t;

subtype piso_val_t is std_logic_vector(data'range);
type piso_val_array_t is array(integer range<>) of piso_val_t;

constant enc_mux_to_type: work.absenc_pkg.enc_type_array_t :=
 work.absenc_pkg.gen_enc_mux_to_type(ENABLE_ENDAT, ENABLE_BISS, ENABLE_SSI);

constant ENC_MUX_COUNT: integer :=
 work.absenc_pkg.get_enc_mux_count(ENABLE_ENDAT, ENABLE_BISS, ENABLE_SSI);

constant ENC_MUX_ENDAT: integer :=
 work.absenc_pkg.get_enc_mux_endat(ENABLE_ENDAT, ENABLE_BISS, ENABLE_SSI);

constant ENC_MUX_BISS: integer :=
 work.absenc_pkg.get_enc_mux_biss(ENABLE_ENDAT, ENABLE_BISS, ENABLE_SSI);

constant ENC_MUX_SSI: integer :=
 work.absenc_pkg.get_enc_mux_ssi(ENABLE_ENDAT, ENABLE_BISS, ENABLE_SSI);

signal ma_clk_edge_mux: std_logic_vector(ENC_MUX_COUNT - 1 downto 0);
signal miso_mux: std_logic_vector(ENC_MUX_COUNT - 1 downto 0);
signal gate_mux: std_logic_vector(ENC_MUX_COUNT - 1 downto 0);
signal tm_top_mux: tm_val_array_t(ENC_MUX_COUNT - 1 downto 0);
signal count_rst_mux: std_logic_vector(ENC_MUX_COUNT - 1 downto 0);
signal count_top_mux: count_val_array_t(ENC_MUX_COUNT - 1 downto 0);
signal piso_ini_mux: piso_val_array_t(ENC_MUX_COUNT - 1 downto 0);
signal piso_load_mux: std_logic_vector(ENC_MUX_COUNT - 1 downto 0);


begin


--
-- assertions

assert (ENC_MUX_COUNT /= 0)
report "ENC_MUX_COUNT == 0" severity failure;


--
-- master clock filter
-- sometimes, slave detects fantom master clock edges
-- filtering the master clock fixes this issue

process
begin
 wait until rising_edge(clk);
 ma_clk_buf <= ma_clk & ma_clk_buf(ma_clk_buf'length - 1 downto 1);
end process;

process(ma_clk_buf, ma_clk_filt)
begin
 ma_clk_filt <= ma_clk_filt;

 if ma_clk_buf = (ma_clk_buf'range => '0') then
  ma_clk_filt <= '0';
 elsif ma_clk_buf = (ma_clk_buf'range => '1') then
  ma_clk_filt <= '1';
 end if;
end process;


--
-- master clock edge detection

process
begin
 wait until rising_edge(clk);

 if (rst = '1') then
  ma_clk_redge <= '0';
  ma_clk_fedge <= '0';
  ma_clk_pre <= ma_clk_filt;
 else
  ma_clk_redge <= (not ma_clk_pre) and ma_clk_filt;
  ma_clk_fedge <= ma_clk_pre and (not ma_clk_filt);
  ma_clk_pre <= ma_clk_filt;
 end if;

end process;


--
-- piso right shifted register

process
begin

 wait until rising_edge(clk); 

 if (piso_load = '1') then
  piso_rval <= piso_ini;
 elsif (ma_clk_edge = '1') then
  piso_rval <= '0' & piso_rval(piso_rval'length - 1 downto 1);
 end if;

end process;


--
-- piso left shifted register

process
begin

 wait until rising_edge(clk); 

 if (piso_load = '1') then
  piso_lval <= piso_ini;
 elsif (ma_clk_edge = '1') then
  piso_lval <= piso_lval(piso_lval'length - 2 downto 0) & '0';
 end if;

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
 elsif (ma_clk_edge = '1') then
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
-- tm_val reloaded at ma_clk_edge

process
begin
 wait until rising_edge(clk);

 tm_match <= '0';

 if ((rst or ma_clk_edge) = '1') then
  tm_val <= tm_top;
 elsif (tm_val = 0) then
  tm_val <= tm_top;
  tm_match <= '1';
 else
  tm_val <= tm_val - 1;
 end if;

end process;


--
-- encoder slave implementations

gen_endat: if ENABLE_ENDAT = TRUE generate
slave_endat: work.absenc_pkg.slave_endat
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 ma_clk_redge => ma_clk_redge,
 ma_clk_fedge => ma_clk_fedge,
 ma_clk_edge => ma_clk_edge_mux(ENC_MUX_ENDAT),
 miso => miso_mux(ENC_MUX_ENDAT),
 mosi => mosi,
 gate => gate_mux(ENC_MUX_ENDAT),
 data => data,
 len => len,
 tm_match => tm_match,
 tm_top => tm_top_mux(ENC_MUX_ENDAT),
 count_top => count_top_mux(ENC_MUX_ENDAT),
 count_match => count_match,
 count_rst => count_rst_mux(ENC_MUX_ENDAT),
 piso_rval => piso_rval,
 piso_lval => piso_lval,
 piso_ini => piso_ini_mux(ENC_MUX_ENDAT),
 piso_load => piso_load_mux(ENC_MUX_ENDAT)
);
end generate gen_endat;

gen_biss: if ENABLE_BISS = TRUE generate
slave_biss: work.absenc_pkg.slave_biss
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 ma_clk_redge => ma_clk_redge,
 ma_clk_fedge => ma_clk_fedge,
 ma_clk_edge => ma_clk_edge_mux(ENC_MUX_BISS),
 miso => miso_mux(ENC_MUX_BISS),
 mosi => mosi,
 gate => gate_mux(ENC_MUX_BISS),
 data => data,
 len => len,
 tm_match => tm_match,
 tm_top => tm_top_mux(ENC_MUX_BISS),
 count_top => count_top_mux(ENC_MUX_BISS),
 count_match => count_match,
 count_rst => count_rst_mux(ENC_MUX_BISS),
 piso_rval => piso_rval,
 piso_lval => piso_lval,
 piso_ini => piso_ini_mux(ENC_MUX_BISS),
 piso_load => piso_load_mux(ENC_MUX_BISS)
);
end generate gen_biss;

gen_ssi: if ENABLE_SSI = TRUE generate
slave_ssi: work.absenc_pkg.slave_ssi
generic map
(
 CLK_FREQ => CLK_FREQ
)
port map
(
 clk => clk,
 rst => rst,
 ma_clk_redge => ma_clk_redge,
 ma_clk_fedge => ma_clk_fedge,
 ma_clk_edge => ma_clk_edge_mux(ENC_MUX_SSI),
 miso => miso_mux(ENC_MUX_SSI),
 mosi => mosi,
 gate => gate_mux(ENC_MUX_SSI),
 data => data,
 len => len,
 tm_match => tm_match,
 tm_top => tm_top_mux(ENC_MUX_SSI),
 count_top => count_top_mux(ENC_MUX_SSI),
 count_match => count_match,
 count_rst => count_rst_mux(ENC_MUX_SSI),
 piso_rval => piso_rval,
 piso_lval => piso_lval,
 piso_ini => piso_ini_mux(ENC_MUX_SSI),
 piso_load => piso_load_mux(ENC_MUX_SSI),
 ssi_flags => ssi_flags
);
end generate gen_ssi;


--
-- enc_type multiplexer

process
(
 enc_type,
 ma_clk_edge_mux,
 miso_mux,
 gate_mux,
 tm_top_mux,
 count_rst_mux,
 count_top_mux,
 piso_ini_mux,
 piso_load_mux
)

begin

 ma_clk_edge <= '0';
 miso <= '0';
 gate <= '0';
 tm_top <= to_unsigned(DEFAULT_TM_TOP, tm_top'length);
 count_rst <= '0';
 count_top <= (count_top'range => '0');
 piso_ini <= (piso_ini'range => '0');
 piso_load <= '0';

 for i in 0 to ENC_MUX_COUNT - 1 loop
  if enc_mux_to_type(i) = enc_type then
   ma_clk_edge <= ma_clk_edge_mux(i);
   miso <= miso_mux(i);
   gate <= gate_mux(i);
   tm_top <= tm_top_mux(i);
   count_rst <= count_rst_mux(i);
   count_top <= count_top_mux(i);
   piso_ini <= piso_ini_mux(i);
   piso_load <= piso_load_mux(i);
  end if;
 end loop;

end process;


end absenc_slave_rtl; 
