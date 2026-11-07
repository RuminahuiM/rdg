function Invoke-DgApiValidateRule {
    <#
    .SYNOPSIS
        POST /api/rules/validate: checks rule text with the engine and returns every error with
        its position, the referenced group IDs and those that don't exist. Always 200 for a
        well-formed request.
    .EXAMPLE
        Invoke-DgApiValidateRule -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Common handler signature.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $body = Read-DgRequestBody -Request $Request -Schema RuleValidationInput
    $rule = [string]$body['rule']
    $check = Test-DgRule -Rule $rule
    $errors = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in (Get-DgRuleErrorList -Check $check)) { $errors.Add($entry) }
    $referenced = [string[]]@($check.ReferencedGroupIds | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    $unknown = [string[]]@()
    if ($check.Valid -and $referenced.Count) {
        $unknown = [string[]]@(Get-DgUnknownGroupId -Context $Context -GroupIds $referenced -Data (Get-DgApiStoreData -Context $Context))
        foreach ($id in $unknown) {
            $position = [Math]::Max($rule.IndexOf($id, [System.StringComparison]::OrdinalIgnoreCase), 0)
            $before = $rule.Substring(0, $position)
            $errors.Add([ordered]@{
                    position = $position
                    line     = [regex]::Matches($before, "`n").Count + 1
                    column   = $position - $before.LastIndexOf("`n")
                    length   = $id.Length
                    message  = "the memberOf group $id doesn't exist"
                })
        }
    }
    New-DgApiResponse -Status 200 -Body ([ordered]@{
            valid              = $errors.Count -eq 0
            errors             = $errors.ToArray()
            referencedGroupIds = $referenced
            unknownGroupIds    = $unknown
        })
}
