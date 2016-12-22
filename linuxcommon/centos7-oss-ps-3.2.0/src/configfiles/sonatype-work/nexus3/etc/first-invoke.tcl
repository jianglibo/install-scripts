package require Expect
package require base64

set nexusCmd [lindex $argv 0]

spawn $nexusCmd
set timeout 600
# it's important to match whole output, matched string will remove from expect(buffer), so will not match by next loop.
expect {
  "Started Sonatype Nexus OSS" {
    exp_send "$password\n"
    exp_continue
  }
  eof {}
  timeout {}
}