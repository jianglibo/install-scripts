package require Expect

set password [lindex $argv 0]
set sql [lindex $argv 1]

if {! [string equal ";" [string index $sql end]]} {
  set sql "${sql};"
}

spawn -noecho mysql -uroot -p

# it's important to match whole output, matched string will remove from expect(buffer), so will not match by next loop.
expect {
  "Enter password: $" {
    exp_send "$password\n"
    exp_continue
  }
  "Welcome to the MySQL monitor.*mysql> $" {
    exp_send "${sql}\n"
    exp_continue
  }
  "You have an error in your SQL syntax.*mysql> $" {
    puts  $expect_out(0,string)
    exit 1
  }
  "mysql> $" {
      exp_send "exit\n"
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
