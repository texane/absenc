#!/usr/bin/env sh

vlib work

vcom -quiet ../src/absenc_pkg.vhd
vcom -quiet ../src/absenc_master_biss.vhd
vcom -quiet ../src/absenc_master_ssi.vhd
vcom -quiet ../src/absenc_master_endat.vhd
vcom -quiet ../src/absenc_master.vhd
vcom -quiet ../src/absenc_slave_biss.vhd
vcom -quiet ../src/absenc_slave_ssi.vhd
vcom -quiet ../src/absenc_slave_endat.vhd
vcom -quiet ../src/absenc_slave.vhd
vcom -quiet ../src/absenc_reader_hssl.vhd
