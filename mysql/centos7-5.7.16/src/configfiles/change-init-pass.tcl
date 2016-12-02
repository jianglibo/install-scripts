package require Expect
package require base64

set password [lindex $argv 0]
set newpass [lindex $argv 1]

set password [::base64::decode $password]
set newpass [::base64::decode $newpass]

set newpass [regsub {'} $newpass {\'}]

spawn mysql -uroot -p

expect {
  "Enter password: $" {
    exp_send "$password\n"
    exp_continue
  }
  -re "Welcome to the MySQL monitor.*mysql> $" {
    exp_send "select 1;\n"
    exp_continue
  }
  -re "You have an error in your SQL syntax.*mysql> $" {
    puts "*************************"
    puts "syntax Error."
    puts "SET PASSWORD = PASSWORD('${newpass}');"
    puts "*************************"
    exit 1
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
