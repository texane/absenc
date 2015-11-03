# system clock

isim force add {/main/clk} \
 1 -value 0 -radix bin -time 10 ns -repeat 20 ns

isim force add {/main/rst} \
 1 -value 0 -time 2 us


# main
wave add /main/mosi
wave add /main/miso
wave add /main/master_data

# master clock
wave add /main/master/ma_clk
