package require Expect
package require base64

set password [lindex $argv 0]
set sqls [lrange $argv 1 end]
set i 0

set newsqls {}
set password [::base64::decode $password]
foreach sql $sqls {
  lappend newsqls [::base64::decode $sql]
}

set sqls $newsqls

spawn -noecho mysql -uroot -p

# it's important to match whole output, matched string will remove from expect(buffer), so will not match by next loop.
expect {
  "Enter password: $" {
    exp_send "$password\n"
    exp_continue
  }
  "You have an error in your SQL syntax.*mysql> $" {
    if {[info exists sql]} {
      puts "*******got sql syntax error: $sql ******"
    }
    puts  $expect_out(0,string)
    exit 1
  }
  "mysql> $" {
        set sql [lindex $sqls $i]
        if {[string length $sql] > 0} {
          if {! [string equal ";" [string index $sql end]]} {
            set sql "${sql};"
          }
          incr i
          exp_send "$sql\n"
          exp_continue
        } else {
          exp_send "exit\n"
        }
  }
  eof {}
  timeout {}
}
# http://www.tcl.tk/man/expect5.31/expect.1.html
# -re cause buffer to change.
# if a process has produced output of "abcdefgh\n"
# set expect_out(0,string) cd
# set expect_out(buffer) abcd
# $expect_out(buffer)
