source common.tcl

if { [ file exists user.tcl ] == 1 } {
 source user.tcl
} else {
 source endat.tcl
}

run 200 us
