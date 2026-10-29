function Get-DgRecipientMap {
    <#
    .SYNOPSIS
        Reads every user recipient in Exchange once per run: Entra object ID -> Exchange GUID.
    .DESCRIPTION
        Users missing from this map have no mailbox or mail user, so Exchange groups skip them
        (counted as Skipped). The map is also kept on the directory for Add/Remove.
    .EXAMPLE
        $recipients = Get-DgRecipientMap -Directory $exchange
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory
    )

    $map = @{}
    $items = if ($Directory.Kind -eq 'Custom') {
        @(& $Directory.GetRecipients)
    } else {
        @(Invoke-DgExchangeCommand -Directory $Directory -Command 'Get-EXORecipient' -Parameters @{
                ResultSize           = 'Unlimited'
                RecipientTypeDetails = @('UserMailbox', 'SharedMailbox', 'MailUser', 'GuestMailUser')
                Properties           = @('ExternalDirectoryObjectId', 'Guid')
            })
    }
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $id = [string](Get-DgFieldValue -Object $item -Name 'ExternalDirectoryObjectId')
        if ($id) { $map[$id.ToLowerInvariant()] = [string](Get-DgFieldValue -Object $item -Name 'Guid') }
    }
    $Directory.Recipients = $map
    $map
}
