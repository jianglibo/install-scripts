Describe "code" {
    It "should catch exception" {
        $c = 0
        try {
            $j = "aaa,xx" | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch [System.ArgumentException] {
            $j | Should Be $null
            $c = 1
        }

        $c | Should Be 1
    }
    It "should parse json" {
       $j = "{aaa:`"xx`"}" | ConvertFrom-Json -ErrorAction SilentlyContinue
       $j = "{aaa:'xx'}" | ConvertFrom-Json -ErrorAction SilentlyContinue

       $j = "   " | ConvertFrom-Json -ErrorAction SilentlyContinue

       $j | Should Be $null
    }
}
