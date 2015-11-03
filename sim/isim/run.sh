#!/usr/bin/env bash

if [ -z "$1" ]; then
 main_tcl='main.tcl'
else
 main_tcl="$1"
fi ;

./main -gui -tclbatch $main_tcl
