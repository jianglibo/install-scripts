package require tcltest 2.2

eval ::tcltest::configure $::argv

set ::baseDir [file join [file dirname [info script]] ..]

set ::yamlFile [file normalize [file join $::baseDir fixtures envforcodeexec.yaml]]

lappend auto_path $::baseDir

namespace eval ::example::test {
    namespace import ::tcltest::*
    testConstraint X [expr {1}]

    test filesToUpload {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [CommonNoLib::getUpload]
        } -cleanup {
        } -result {/opt/easyinstaller/zookeeper-3.4.9.tar.gz}

    test topDict {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [dict size $CommonNoLib::topDict]
        } -cleanup {
        } -result {4}

    test boxLines {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [llength [dict get $CommonNoLib::topDict box]]
        } -cleanup {
        } -result {8}
    
    test myboxSize {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [dict size [CommonNoLib::mybox]]
        } -cleanup {
        } -result {8}
    test myboxIp {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [dict get [CommonNoLib::mybox] ip]
        } -cleanup {
        } -result {192.168.2.14}        
    test myboxName {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [dict get [CommonNoLib::mybox] name]
        } -cleanup {
        } -result {box3"}

    test boxes {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            return [llength [dict get [CommonNoLib::boxGroup] boxes]]
        } -cleanup {
        } -result {3}

    test boxesOb {} -constraints {X} -setup {
        } -body {
            source [file normalize [file join $::baseDir tclcommon-nolib.tcl]]
            CommonNoLib::initialize $::yamlFile
            set boxes [dict get [CommonNoLib::boxGroup] boxes]
            set ips {}
            foreach box $boxes {
                lappend ips [dict get $box ip]
            }
            return $ips
        } -cleanup {
        } -result {192.168.2.14 192.168.2.11 192.168.2.10}
    cleanupTests
}

namespace delete ::example::test
