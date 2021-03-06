Import-Module activedirectory
Import-Module MsOnline
Import-Module ADSync

# Get information to create the user
$firstName = Read-Host -Prompt 'Users First Name'
$surName = Read-Host -Prompt 'Users Last Name'
$fullName = $FirstName + ' ' + $Surname
$username = Read-Host -Prompt 'Login name, f.e. "john"'
$upname = $username + '@' + $activeDomain
$path = ''

# Check if the username is available
try {
    get-aduser $username -ErrorAction SilentlyContinue
    Write-Host "`n Username is not available `n"
    return
}
catch {
    Write-Host "`n user $username will be created`n"
}

# Set wich part of the company the user is part of
Write-Host "What will be the users active domain? `n 1. domainone.com `n 2. domaintwo.com `n"
do {
    $activeDomain = Switch(Read-Host) {
        1 {"domainone.com"}
        2 {"domaintwo.com"}
    } 
} until (($activeDomain -eq "domainone.com") -or ($activeDomain -eq "domaintwo.com"))

$upname = $username + '@' + $activeDomain

Write-Host "Does the user need an Office365 Subscription?"
do {
    switch(Read-Host "(Y/N)") {
        Y {$path = 'OU=Office,OU=Staff,DC=mydomain,DC=local'}
        N {$path = 'OU=Staff,DC=mydomain,DC=local'}
    }
} until (($path -eq 'OU=Office,OU=Staff,DC=mydomain,DC=local') -or ($path -eq 'OU=Staff,DC=mydomain,DC=local'))

do {
    $userGroup = switch(Read-Host "What group does the user belong to? `n 1. Finance `n 2. Sales `n 3. Marketing `n 4. Hotels `n 5. Operations `n "){
        1 {"Finance"}
        2 {"Sales"}
        3 {"Marketing"}
        4 {"Hotels"}
        5 {"Operations"}
        default {"Choose a number between 1 and 5"}
    }
} until (($userGroup -eq "Finance") -or ($userGroup -eq "Sales") -or ($userGroup -eq "Marketing") -or ($userGroup -eq "Hotels") -or ($usergroup -eq "Operations"))

# Create the user in the Active Directory
try {
    New-ADUser -Name "$fullName" `
        -GivenName $firstName `
        -Surname $surName `
        -DisplayName "$fullName" `
        -SamAccountName $username `
        -Country 'IS' `
        -Path $path `
        -UserPrincipalName $upname `
        -HomeDrive "H:" `
        -HomeDirectory "\\Fileshare\home$\$username" `
        -ProfilePath "\\Fileshare\profile$\$username" `
        -AccountPassword(ConvertTo-SecureString -AsPlainText "MySecureDefaultPassword" -Force) `
        -Enabled $true `
        -ChangePasswordAtLogon $true
    }
    catch {
    Write-Host "User not created"
    write-host $_.Exception.Message
    }

Write-Host $fullName - $upname - $path Created as AD User

# Set the user as a member of the base group
try {
    Add-ADGroupMember -Identity everyone $username
    Write-Host $upname added to everyone
    }
    catch {
    Write-Host failed adding $upname to everyone
    }

# Add the user to the correct group in active directory
do {
    switch ($userGroup) {
        'Finance' {Add-ADGroupMember -Identity Finance -Members $username; Write-Host "User added to Finance"}
        'Sales' {Add-ADGroupMember -Identity Sales -Members $username; Write-Host "User added to Sales"}
        'Marketing' {Add-ADGroupMember -Identity Marketing -Members $username; Write-Host "User added to Marketing"}
        'Hotels' {Add-ADGroupMember -Identity Hotels -Members $username; Write-Host "User added to Hotels"}
        'Operations' {Add-ADGroupMember -Identity Operations -Members $username; Write-Host "User added to Operations"}
    } 
} until (($userGroup -eq "Finance") -or ($userGroup -eq "Sales") -or ($userGroup -eq "Marketing") -or ($userGroup -eq "Hotels") -or ($userGroup -eq "Operations"))

## Adds the user to the group that is synchronized with Office 365 if applicable ##
if ($path -eq "OU=Office,OU=Staff,DC=mydomain,DC=local"){
    try {
        Start-ADSyncSyncCycle -PolicyType Delta
        Write-Host "AD Sync initialized"
        Start-Sleep -s 2
    }
    Catch {
        Write-Host "ADSyncCycle Failed..."
    }
    
    ## Check if a connection has been established with O365 ##
    function MSOLConnected {
        Get-MsolDomain -ErrorAction SilentlyContinue | out-null
        $result = $?
        return $result
    }

   if (-not (MSOLConnected)) {
            
        # Tengjast við Office 365 með Tenant Global Admin
        $UserCredential = Get-Credential host@mydomain.onmicrosoft.com
        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
        Import-PSSession $Session

    
        try {
            Connect-MsolService -Credential $UserCredential
            Write-Host "Authentication success"
        }
        catch{
            Write-Host "Authentication failed.."
        }

        Start-Sleep -s 10
    }else {
        write-host "already connected to msol"
    }
   
    # Assign the license to the user
    if($path -eq 'OU=Office,OU=Office,DC=mydomaincontroller,DC=local') {

        $User = Get-MsolUser -UserPrincipalName $upname -ErrorAction SilentlyContinue
        
        Do {
            # Check if the user exists in O365
            $User = Get-MsolUser -UserPrincipalName $upname -ErrorAction SilentlyContinue

            #Wait 10 seconds before checking again if the user exists
            Start-Sleep -s 10

        } Until ($User -ne $null)
        
        Set-MsolUser -UserPrincipalName $upname -UsageLocation "IS"
        Set-MsolUserLicense -UserPrincipalName $upname -AddLicenses mydomain:O365_BUSINESS
        Write-Host "Adding subscription to user $upname "

    }
}