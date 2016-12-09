package require tcltest 2.2
eval ::tcltest::configure $::argv

set ::baseDir [file join [file dirname [info script]] ..]
lappend auto_path $::baseDir

set tgzFolder [file normalize [file join $::baseDir .. .. tgzFolder]]

namespace eval ::example::test {
    namespace import ::tcltest::*
    testConstraint X [expr {1}]
    test writeto {} -constraints {} -setup {
      set argv [list -envfile placeholder -action t]
    } -body {
      source [file join $::baseDir code.tcl]
      return {}
    } -cleanup {
    } -result {}
    # match regexp, glob, exact
    cleanupTests
}

namespace delete ::example::test
