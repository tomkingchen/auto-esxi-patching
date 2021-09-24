[CmdletBinding()]
Param (
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [ValidateSet('vc01','vc02')]
  [String]$vCenter
)

#Requires -Module @{ ModuleName = 'PrtgAPI'; ModuleVersion = '0.9.12' }
. ./prtg-tasks.ps1

function evacuate-host ($sourceHost, $destHost, $onVMs) {
  
    If ($onVMs){
      Foreach($VM in $onVMs){
        $vmName = $VM.Name
        Write-Host "Moving $vmName to $destHost......"
        # vMotion VM to destination host in sync mode by default
        try{
          Move-VM -VM $vmName -Destination $destHost -ErrorAction Stop
        }catch{
          Write-Host $_.Exception.Message
          Return $false
        }
      }
      Return $true
    }else{
      Write-Host "There is no VMs to be moved" -ForegroundColor Yellow
      Return $false
    }
  
}

function repopulate-host ($hostName, $onVMs) {
  Write-Host "Move VMs back onto $hostName."
  If ($onVMs){
    Foreach($VM in $onVMs){
      $vmName = $VM.Name
      Write-Host "Moving $vmName to $hostName......"
      # vMotion VM to destination host in sync mode by default
      try{
        Move-VM -VM $vmName -Destination $hostName -ErrorAction Stop
      }catch{
        Write-Host $_.Exception.Message
        Return $false
      }
    }
    Return $true
  }else{
    Write-Host "There is no VMs to be moved" -ForegroundColor Yellow
    Return $false
  }
}

function update-host ($HostName) {
  Try{
    Scan-Inventory -Entity $HostName -ErrorAction Stop
    $Compliances = Get-Compliance -Entity $HostName -ErrorAction Stop
    $Baselines = @()
    Write-Host "Staging patches on $HostName." -foreground "Green"
    ForEach ($Compliance in $Compliances){
      if ($Compliance.status -eq 'NotCompliant'){
        $Baseline = $Compliance.Baseline
        Stage-Patch -Entity $HostName -Baseline $Baseline
        $Baselines += $Baseline
        
      }
    }
    Write-Host "Remediating patches on $HostName. Host will reboot when complete" -foreground "Yellow"
    Remediate-Inventory -Entity $HostName -Baseline $Baselines -HostFailureAction FailTask -confirm:$false -ErrorAction SilentlyContinue
    Return $true
  }Catch{
    Write-Host $_.Exception.Message
    Return $false
  }
}

# Send message to Slack to notify about the patching
# Send-Slackmsg -msgtext ":warning: Kicking off VMware patching on $vcenter"

$vcenter_fqdn = $vCenter + ".contoso.com"

# Initializing tasks
$patchResult = $false
$adminCred = Get-Credential
Write-Host "Start connecting to $vcenter_fqdn"
Connect-VIServer -Server $vcenter_fqdn -Credential $adminCred
# Pause PRTG Sensors
$prtgUserName = $adminCred.UserName
$prtgUserName = $prtgUserName.Substring(0,$prtgUserName.IndexOf('@'))
$prtgCred = New-Object System.Management.Automation.PSCredential $prtgUserName,$adminCred.Password
Connect-PrtgServer -Server prtg.contoso.com -Credential $prtgCred -Force
$Hosts = Get-vmHost -Location "vCenterDCName"
if (pause-sensors -DeviceList $Hosts -vCenter $vCenter) {
  $lasthost = $Hosts.length - 1
  $i = 0
  # Move VMs off and Patch
  foreach ($esxiHost in $Hosts){
    $srcHostName = $esxiHost.Name
    # Rotate the destination host
    if ($i -lt $lasthost){
      $i += 1
      $destHostName = $Hosts[$i].Name
    }else{
      $destHostName = $Hosts[0].Name
    }
    Try {
      Write-Host "Ready to kick off vMotion from $srcHostName >>> $destHostName" -ForegroundColor Green
      $userResponse = Read-Host "Please type yes to confirm [No/yes]"
      if ($userResponse -eq 'yes'){
        # Get Live VMs currently running on the host
        $VMs = Get-VMHost -Name $srcHostName |Get-VM | Where-Object {$_.PowerState -eq 'PoweredOn'}
        # Move Live VMs off the host
        if (evacuate-host -sourceHost $srcHostName -destHost $destHostName -onVMs $VMs){
          $patchResult = update-host -HostName $srcHostName
          if ($patchResult){
            # Move Live VMs back onto the patched host
            repopulate-host -hostName $srcHostName -onVMs $VMs
          }
        }else{
          Write-Host "[ERROR]VMs migration failed with error:" + $_.Exception.Message -ForegroundColor Red
        }
      }else{
        Write-Host "You choose to skip patching $srcHostName"
      }
    }
    Catch {
      write-host "[ERROR]Patch $esxiHost.Name failed with error: " + $_.Exception.Message + " at " + $_.InvocationInfo.ScriptLineNumber
    }
  }
}else{
  Write-Host "[ERROR]Failed to pause PRTG Sensors. Exitting the pacthing script." -ForegroundColor Red
}

# Resume PRTG Sensors
if ($patchResult){
  resume-sensors -DeviceList $Hosts
}else{
  Write-Host "[ERROR]Patching process failed! Will not resume PRTG sensors." -ForegroundColor Red
}