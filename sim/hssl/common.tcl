# system clock

isim force add {/main/clk} \
 1 -value 0 -radix bin -time 10 ns -repeat 20 ns

isim force add {/main/rst} \
 1 -value 0 -time 2 us


# main
wave add /main/rst
wave add /main/reader_data
