package require Expect

set password [lindex $argv 0]
set newpass [lindex $argv 1]

set resetpass 0
spawn -noecho mysql -uroot -p

expect {
  "Enter password: $" {
    exp_send "$password\r"
    exp_continue
  }
  "You must reset your password" {
    set resetpass 1
    exp_send "SET PASSWORD = PASSWORD('${newpass}');\r"
    exp_continue
  }
  "mysql> $" {
      exp_send "exit\r"
  }
  eof {}
  timeout {}
}
