#Requires -Version 5.1
function Get-FreshWindowsFunctionAstText {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$FunctionName
    )
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw ("Parse error in {0}: {1}" -f $FilePath, ($parseErrors[0].Message))
    }
    $found = $ast.FindAll({
            param($node)
            return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $FunctionName)
        }, $true)
    if (-not $found -or $found.Count -lt 1) {
        throw "Function $FunctionName not found in $FilePath"
    }
    return $found[0].Extent.Text
}
