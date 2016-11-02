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
#!/bin/sh
# exp.tcl \
exec tclsh "$0" ${1+"$@"}

package require Expect
set timeout 100000
spawn {spawn-command}
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
    
    $tclf = New-TemporaryFile
    $tcls -replace "{spawn-command}",("bash",$bsf -join " ") | Set-Content -Path $tclf
    "bash", $tclf -join " " | Invoke-Expression

    Remove-Item $bsf
    Remove-Item $tclf
    }
}
