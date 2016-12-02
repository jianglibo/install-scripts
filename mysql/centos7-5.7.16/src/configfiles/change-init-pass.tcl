package require Expect

set password [lindex $argv 0]
set newpass [regsub -all {'} [lindex $argv 1] {\'}]

spawn mysql -uroot -p

expect {
  "Enter password: $" {
    exp_send "$password\n"
    exp_continue
  }
  "Welcome to the MySQL monitor.*mysql> $" {
    exp_send "select 1;\n"
    exp_continue
  }
  -re "You must reset your password.*mysql> $" {
    exp_send "SET PASSWORD = PASSWORD('${newpass}');\n"
    exp_continue
  }
  "Your password does not satisfy the current policy.*mysql> $" {
    puts "$expect_out(0,string)"
    exit 1
  }
  "mysql> $" {
      exp_send "exit\n"
  }
  eof {}
  timeout {}
}
# -re cause buffer to change.
# $expect_out(buffer)
