#!/bin/sh
# exp.tcl \
exec tclsh "$0" ${1+"$@"}

package require Expect
set timeout 100000
spawn ./exptest.sh
expect {
		"Enter password: $" {
			exp_send "$password\r"
			exp_continue
    }
	   "#\? $" {
			    exp_send "1"
      }
      eof {}
      timeout {}
}
