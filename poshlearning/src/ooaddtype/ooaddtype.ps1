function New-Ooaddtype {
    $Source = @"
    public class MyClass 
    {
       public string MyProperty { get; set; }
    }
"@
    Add-Type -TypeDefinition $Source
    New-Object MyClass
}
