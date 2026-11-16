#
# 03-New-ADUsersFromCSV.ps1
# Bulk-provisions user accounts in lab.local from a CSV file.
#
# For each row in users.csv (FirstName, LastName, Department, Title) it:
#   1. Builds a username: first initial + last name (e.g. Amara Okafor -> aokafor),
#      adding a number if that name is already taken (drivera -> drivera2)
#   2. Creates the account in OU=<Department>,OU=Users,OU=_CORP
#   3. Sets display name, UPN, title, department and company
#   4. Sets a temporary password and forces a change at first sign-in
#   5. Adds the user to the department group (GG_<Department>)
#   6. Writes a log of what was created to .\logs\ (no passwords are logged)
#
# Safety: the temporary password is checked against the domain password policy
# before anything is created, and if any step fails for a user, that user's
# account is removed again (rollback) so no half-created accounts are left.
#
# Usage (on DC01 as LAB\Administrator):
#   .\03-New-ADUsersFromCSV.ps1
#   .\03-New-ADUsersFromCSV.ps1 -CsvPath .\new-hires.csv
#
# Run 02-Create-OUStructure.ps1 first.
#

#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot 'users.csv'),
    [string]$Company = 'Lab Corp'
)

Import-Module ActiveDirectory

$Domain    = Get-ADDomain
$DomainDN  = $Domain.DistinguishedName
$UpnSuffix = $Domain.DNSRoot                     # lab.local
$UsersOU   = "OU=Users,OU=_CORP,$DomainDN"

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
$rows = Import-Csv $CsvPath
Write-Host "`nLoaded $($rows.Count) users from $CsvPath" -ForegroundColor Cyan

# One temporary password for this batch, typed at run time, never stored.
# It is checked against the domain password policy BEFORE any account is created,
# so a weak password can't leave half-created accounts behind.
$Policy = Get-ADDefaultDomainPasswordPolicy
while ($true) {
    $TempPassword = Read-Host "Enter a temporary password for the new accounts" -AsSecureString
    $Confirm      = Read-Host "Confirm the temporary password" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new('', $TempPassword).Password
    $plain2 = [System.Net.NetworkCredential]::new('', $Confirm).Password

    $classes = @('[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]' | Where-Object { $plain -cmatch $_ }).Count
    $problems = @()
    if ($plain -cne $plain2)                           { $problems += 'the two entries do not match' }
    if ($plain.Length -lt $Policy.MinPasswordLength)   { $problems += "it must be at least $($Policy.MinPasswordLength) characters" }
    if ($Policy.ComplexityEnabled -and $classes -lt 3) { $problems += 'it needs 3 of: uppercase, lowercase, number, symbol' }
    $plain = $null; $plain2 = $null

    if (-not $problems) { break }
    Write-Host "  Password rejected: $($problems -join '; '). Try again." -ForegroundColor Yellow
}
Write-Host "  (Note: Windows also rejects a password that contains part of the user's name.)" -ForegroundColor DarkGray

function Get-UniqueSam {
    param([string]$First, [string]$Last)
    $base = ($First.Substring(0,1) + $Last).ToLower() -replace '[^a-z0-9]', ''
    if ($base.Length -gt 18) { $base = $base.Substring(0,18) }   # sAMAccountName max is 20
    $sam = $base; $n = 2
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $sam = "$base$n"; $n++
    }
    return $sam
}

$log = @()
foreach ($r in $rows) {
    $first = $r.FirstName.Trim(); $last = $r.LastName.Trim()
    $dept  = $r.Department.Trim(); $title = $r.Title.Trim()
    $ou    = "OU=$dept,$UsersOU"
    $group = "GG_$dept"
    $name  = "$first $last"

    try {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue)) {
            throw "OU for department '$dept' does not exist ($ou)"
        }

        # Skip if someone with this exact name already exists in that department OU
        if (Get-ADUser -Filter "Name -eq '$name'" -SearchBase $ou -ErrorAction SilentlyContinue) {
            Write-Host "  skipped  $name (already exists in $dept)" -ForegroundColor DarkGray
            $log += [pscustomobject]@{ Name=$name; Username=''; Department=$dept; Result='Skipped - exists' }
            continue
        }

        $sam = Get-UniqueSam -First $first -Last $last

        # Create disabled first, then set password, enable and add to group.
        # If any step fails, the half-created account is removed again (rollback).
        $newUser = New-ADUser -Name $name -GivenName $first -Surname $last `
            -DisplayName $name -SamAccountName $sam -UserPrincipalName "$sam@$UpnSuffix" `
            -Title $title -Department $dept -Company $Company `
            -Path $ou -Enabled $false -PassThru
        try {
            Set-ADAccountPassword -Identity $newUser -NewPassword $TempPassword -Reset
            Set-ADUser            -Identity $newUser -ChangePasswordAtLogon $true
            Enable-ADAccount      -Identity $newUser
            Add-ADGroupMember     -Identity $group -Members $newUser
        }
        catch {
            Remove-ADUser -Identity $newUser -Confirm:$false
            throw "$($_.Exception.Message) (account rolled back)"
        }

        Write-Host ("  created  {0,-12} {1,-20} {2,-10} {3}" -f $sam, $name, $dept, $title) -ForegroundColor Green
        $log += [pscustomobject]@{ Name=$name; Username=$sam; Department=$dept; Result='Created' }
    }
    catch {
        Write-Host "  FAILED   $name : $($_.Exception.Message)" -ForegroundColor Red
        $log += [pscustomobject]@{ Name=$name; Username=''; Department=$dept; Result="Failed - $($_.Exception.Message)" }
    }
}

$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$logFile = Join-Path $logDir ("provisioning-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$log | Export-Csv $logFile -NoTypeInformation

$created = ($log | Where-Object Result -eq 'Created').Count
Write-Host "`n$created created, $($log.Count - $created) skipped/failed. Log: $logFile`n" -ForegroundColor Cyan
