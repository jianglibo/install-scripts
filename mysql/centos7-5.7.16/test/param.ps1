Param(
    [parameter(ValueFromRemainingArguments)]$remainingArguments
)

$remainingArguments.Count

function Get-ThisFile {
  $MyInvocation.MyCommand.Path
}

function Get-CommandPath {
  $PSCommandPath
}

function Get-Psscriptroot {
  $PSScriptRoot
}
