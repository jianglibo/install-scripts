$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.TestsNix\.', '.'
. "$here\$sut"

. "$here\Centos7Util.ps1"

Describe "PsCommon" {

    It "should save to xml" {
        [xml]$doc = "<a></a>"

        $tf = New-TemporaryFile
        Save-Xml -doc $doc -FilePath $tf -encoding ascii

        (Get-Content $tf) -match "<a>" | Should Be $True
        (Get-Content $tf) -match "utf-8" | Should Be $True
        (Get-Content $tf) -match "utf-16" | Should Be $null
        Remove-Item $tf
    }

    It "should hand over environment to bash" {
        $shf = Join-Path $here -ChildPath "fixtures/myenvtest.sh"
        Test-Path $shf -PathType Leaf | Should Be $True

        $cmd = "bash $shf"

        ($cmd | Invoke-Expression | Out-String ).Trim() | Should Be ""

        Set-Content env:J_HOME "hello"

        ($cmd | Invoke-Expression | Out-String).Trim() | Should Be "hello"

        Set-Content env:J_HOME "hello1"

        ($cmd | Invoke-Expression | Out-String).Trim() | Should Be "hello1"

        "runuser -s /bin/bash -c $shf zookeeper" | Invoke-Expression | Should Be "hello1"
    }

    It "can work with tcl expect" {
        $bs = @'
echo "Do you wish to install this program?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "install"; break;;
        No ) exit;;
    esac
done
'@
        $bsf = New-TemporaryFile
        $bs | Set-Content -Path $bsf

        $tcls = @'
package require Expect
set timeout 100000
spawn -noecho {spawn-command}
expect {
		"Enter password: $" {
			exp_send "$password\r"
			exp_continue
    }
	   "#\? $" {
			    exp_send "1"
      }
      eof {}
      timeout {}
}
'@
        $tcls -replace "{spawn-command}",("bash",$bsf -join " ") | Run-String -execute "tclsh" | Select-Object -First 1 | Should Be "Do you wish to install this program?"
        Remove-Item $bsf
    }

    # runuser -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc
    # su -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc
    It "should run as user" {
        $bs = 'echo "hello$USER"'
        $bsf = New-TemporaryFile

        $bs | Out-File -FilePath $bsf -Encoding ascii
    
        $r = Centos7-Run-User -scriptfile $bsf -user "abc"

        Centos7-UserManager -username "abc" -action remove
        Remove-Item $bsf
        $r | Should Be "helloabc"
    }

    It "handle run-string" {
        $bs = 'echo "hello$1"'
        Run-String -execute bash -content $bs -others "abc" | Should Be "helloabc"

        $bs = 'echo "hello$1$2"'
        Run-String -execute bash -content $bs "abc" "def" | Should Be "helloabcdef"

        Run-String -execute bash -content $bs -others "abc","def" | Should Be "helloabcdef"
    }
}
