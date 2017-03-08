fac$adminUPN="boring@usip.org"
$orgName="USIP"
$ADMINcred = Get-Credential -UserName $adminUPN -Message "Type the password."
$MSX13 = 'msx13hybrid.usip.local'

# welcome sctript

$global:foregroundColor = 'white'
$time = Get-Date
$psVersion= $host.Version.Major
$curUser= (Get-ChildItem Env:\USERNAME).Value
$curComp= (Get-ChildItem Env:\COMPUTERNAME).Value

Write-Host "Greetings, $curUser!" -foregroundColor $foregroundColor
Write-Host "It is: $($time.ToLongDateString())"
Write-Host "You're running PowerShell version: $psVersion" -foregroundColor Green
#Write-Host "Your computer name is: $curComp" -foregroundColor Green
Write-Host "Happy scripting!" `n

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function prompt {
    $realLASTEXITCODE = $LASTEXITCODE
    
    Write-Host

    # Reset color, which can be messed up by Enable-GitColors
    $Host.UI.RawUI.ForegroundColor = $GitPromptSettings.DefaultForegroundColor

    if (Test-Administrator) {  # Use different username if elevated
        Write-Host "(Elevated) " -NoNewline -ForegroundColor White
    }

    Write-Host "$ENV:USERNAME@" -NoNewline -ForegroundColor DarkYellow
    Write-Host "$ENV:COMPUTERNAME" -NoNewline -ForegroundColor Magenta

    if ($s -ne $null) {  # color for PSSessions
        Write-Host " (`$s: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($s.Name)" -NoNewline -ForegroundColor Yellow
        Write-Host ") " -NoNewline -ForegroundColor DarkGray
    }

    Write-Host " : " -NoNewline -ForegroundColor DarkGray
    Write-Host $($(Get-Location) -replace ($env:USERPROFILE).Replace('\','\\'), "~")-NoNewline -ForegroundColor DarkGreen
    Write-Host " : " -NoNewline -ForegroundColor DarkGray
    Write-Host (Get-Date -Format d) -NoNewline -ForegroundColor DarkMagenta
    Write-Host " : " -NoNewline -ForegroundColor DarkGray

    $global:LASTEXITCODE = $realLASTEXITCODE

    #Write-VcsStatus
    $curtime = Get-Date

    Write-Host ""
    Write-Host -NoNewLine "[" -foregroundColor Yellow
    Write-Host -NoNewLine ("{0:HH}:{0:mm}:{0:ss}" -f (Get-Date)) -foregroundColor $foregroundColor
    Write-Host -NoNewLine "]" -foregroundColor Yellow
    Write-Host -NoNewLine ">" -foregroundColor Red
      
    Return " "
}


Function Test-ADCredentials {
	Param($username, $password, $domain)
	Add-Type -AssemblyName System.DirectoryServices.AccountManagement
	$ct = [System.DirectoryServices.AccountManagement.ContextType]::Domain
	$pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($ct, $domain)
	New-Object PSObject -Property @{
		UserName = $username;
		IsValid = $pc.ValidateCredentials($username, $password).ToString()
	} 
}
Set-Alias -Name pass -Value Test-ADCredentials

Function Find-ADComputer ([string[]]$query){
    $filter = "*$query*"
    Get-ADComputer -Filter {name -like $filter} #-Properties 
}
Set-Alias -Name fac -Value Find-ADComputer

function Find-AD {
Param(         
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $Name
    )
    
Find-ADComputer -query $Name
Find-ADuser -query $Name

}
Set-Alias fad Find-AD

function Test-Admin{
  $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $prp = New-Object System.Security.Principal.WindowsPrincipal($wid)
  $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
  $prp.IsInRole($adm)  
}


function Find-ADuser([string[]]$query){

$filter = "*$query*"
Get-ADUser -Filter {Name -like $filter}  -Properties whenChanged, whenCreated, LastBadPasswordAttempt,`
badPwdCount, BadLogonCount, Enabled, LockedOut, physicalDeliveryOfficeName, ipphone

}
Set-Alias fau -Value Find-ADuser



Function AD-Sync {
Invoke-Command -ComputerName hq-aadsync -Credential $ADMINcred -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta } 
    }


Function connect-MSOL {
$livecred = $ADMINcred
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://pod51045psh.outlook.com/powershell-liveid?PSVersion=5.0.9883.0' -Credential $livecred -Authentication Basic -AllowRedirection
import-pssession $Session
}
set-alias msol -value connect-MSOL

function New-OnlineDL {

    [CmdletBinding()]
    param(
 
        # parameter options
        # validation
        # cast
        # name and default value
 
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DisplayName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $EmailAddress,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DLOwner,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $Members,

        [System.Management.Automation.CredentialAttribute()]
        $o365AdminCredential = $ADMINcred
                       
    )# param end
     #Connect to Exchange Online
  $exchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri 'https://outlook.office365.com/powershell-liveid/?proxymethod=rps' -Credential $o365adminCredential -Authentication Basic -AllowRedirection
  
  Invoke-Command -Session $exchangeSession -ArgumentList $DisplayName,$DLOwner,$EmailAddress,$Members -ScriptBlock {
  new-distributiongroup -Type Distribution -RequireSenderAuthenticationEnabled $true `
  -Name $args[0] -ManagedBy $args[1] -CopyOwnerToMember -PrimarySmtpAddress $args[2] -Members $args[3] -Verbose
  }
   Remove-PSSession $exchangeSession
}

Function Replicate-AD { 
    if (!($localcredentials)){$localcredentials=$ADMINcred}
    $DC = 'dc1colo','dc2colo','hq-dc01','hq-dc5'
    foreach ($controller in $DC)
    { 
        $controller
        $x=0
        start-sleep -Seconds 3

        while ($x -lt 3)
        {   $x = $x+1
            #write-host -ForegroundColor red $x
            Invoke-Command -ComputerName $controller -Credential $localcredentials -ScriptBlock { cmd /c "repadmin /syncall /AdeP" }
        }
    }
}
Set-Alias repad -Value Replicate-AD | Out-Null

function invoke-MSX13hybrid {
Invoke-Command -ComputerName $MSX13 -Credential $ADMINcred -ScriptBlock

}

function connect-ExchOnPrem {
$cred = $ADMINcred
$so = New-PSSessionOption -SkipCACheck:$true -SkipCNCheck:$true -SkipRevocationCheck:$true
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://msx13hybrid.usip.local/powershell/ -Credential $cred -SessionOption $so
Import-PSSession $Session
}
Set-Alias msx13 -Value connect-ExchOnPrem

Import-Module -Name RemoteDesktop
Import-Module -Name PrintManagement
Import-Module -Name ServerManager
Import-Module -Name ServerManagerTasks
Import-Module -Name PSWorkflow
Import-Module -Name PSWorkflowUtility
Import-Module -Name SmbShare
Import-Module -Name SmbWitness
Import-Module -Name ActiveDirectory 
Import-Module -Name DirectAccessClientComponents
Import-Module -Name RemoteAccess
Import-Module -Name RemoteDesktop
Import-Module -Name PSWorkflow
Import-Module -Name PSWorkflowUtility

ise $PROFILE.CurrentUserAllHosts
