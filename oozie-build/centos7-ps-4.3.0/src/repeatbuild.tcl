# allow build failed caused by network problem to continue.
set hadoopVersion 2.7.3
set hiveVersion 2.1.1
# set hbaseVersion 1.2.4
set hbaseVersion 0.94.2


set gitUrl https://github.com/jianglibo/oozie.git
set branch my4.3.0

set repeatTimes 1
set buildParent /opt/oozie-build
regexp {([^/]+)\.git$} $gitUrl whole repoName
set buildHome [file join $buildParent $repoName]
puts $buildHome

set libext "/home/jianglibo/ooziedistro/oozie-4.3.0/libext"
set extjsUrl "http://archive.cloudera.com/gplextras/misc/ext-2.2.zip"
regexp {([^/]+)$} $extjsUrl extjs

set packages [dict create org/apache/hadoop/ 2.4.0  commons-configuration 1.8]
set startPoint [file normalize ~/.m2/repository]

proc withoutput {cmdstr} {
    set results [open "|$cmdstr" r]
    while { [gets $results line] >= 0 } {
        puts $line
    }
    if {[catch {close $results} err]} {
        puts "$cmdstr failed: $err"
        exit 1
    }
}


if {![file exists $buildParent]} {
    file mkdir [file dirname $buildParent]
}

cd $buildParent

if {[file exists $buildHome]} {
    cd $repoName
    puts [exec pwd]
    withoutput "git pull $gitUrl $branch 2>&1"
} else {
    withoutput "git clone $gitUrl"
    cd $repoName
    withoutput "git checkout $branch"
}


dict for {k v} $packages {
    set rg ".*${k}.*${v}.*\.jar"
    set results [open "|find $startPoint -iregex $rg -print" r]
    while { [gets $results line] >= 0 } {
        puts $line
    }
    if {[catch {close $results} err]} {
        puts "find command failed: $err"
    }
}

#exec curl -O $extjsUrl
#mv $extjs $libext

set success 0
for {set index 0} { $index < $repeatTimes} { incr index } {
    set customize "\"-Dhadoop.version=$hadoopVersion\" \"-Dhive.version=$hiveVersion\" \"-Dhbase.version=$hbaseVersion\""
    set cmdTorun "|[file join $buildHome bin/mkdistro.sh] -DskipTests $customize"
    puts $cmdTorun
    set results [open $cmdTorun r]
    while { [gets $results line] >= 0 } {
        if {[regexp {\[INFO\] Apache Oozie Distro .* SUCCESS} whole]} {
            set success 1
        }
        puts $line
    }
    if {[catch {close $results} err]} {
        puts "find command failed: $err"
    }
    if ($success) {
        break
    }
}

if ($success) {
    puts "OOOOOOOOOOOOOOOOOOOk!"
}