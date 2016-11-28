package require Expect

set password [lindex $argv 0]
set newpass [lindex $argv 1]

set result {}
spawn mysql -uroot -p

expect {
  "Enter password: $" {
    exp_send "$password\n"
    exp_continue
  }
  "Welcome to the MySQL monitor" {
    exp_send "select 1;\n"
    exp_continue
  }
  -re "You must reset your password.*$" {
    exp_send "SET PASSWORD = PASSWORD('${newpass}');\n"
    exp_continue
  }
  "Your password does not satisfy the current policy" {
    set result notsatisfy
    exp_send "exit\n"
  }
  "mysql> $" {
      exp_send "exit\n"
  }
  eof {}
  timeout {}
}
# -re cause buffer to change.
# $expect_out(buffer)

if ([string equal $result notsatisfy]) {
  puts $result
  exit 1
}
