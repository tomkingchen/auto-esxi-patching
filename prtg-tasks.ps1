# Pause sensor before patching
function pause-sensors {
  Param(
    [Parameter(Mandatory)]
    [Object[]]$DeviceList,
    [Parameter(Mandatory)]
    [String]$vcenter
  )
  write-host "Pausing PRTG sensors."
  try{
    Get-Device -Name $vcenter | Pause-Object -Duration 180 -Message "Vmware Patching." -ErrorAction SilentlyContinue
    foreach ($esxiHost in $DeviceList){
      $HostName = $esxiHost.Name
      $HostName = $HostName.Substring(0, $HostName.IndexOf('.'))
        Get-Device -Name $HostName | Pause-Object -Duration 180 -Message "Vmware Patching." -ErrorAction SilentlyContinue
    }
  }Catch{
    Write-Host "[ERROR]Pause PRTG Sensors failed with error:" -ForegroundColor Red
        Write-Host $_.Exception.Message
        Return $False
  }
  Return $True
}

# Resume sensors after patching
function resume-sensors {
  Param(
    [Parameter(Mandatory)]
    [Object[]]$DeviceList
  )
  write-host "Resume PRTG sensors."
  foreach ($esxiHost in $DeviceList){
    $HostName = $esxiHost.Name
    $HostName = $HostName.Substring(0, $HostName.IndexOf('.'))
    Try {
      Get-Device -Name $HostName | Resume-Object -ErrorAction SilentlyContinue
      Return $True
    }Catch{
      Write-Host "[ERROR] Pause PRTG Sensors failed with error:" -ForegroundColor Red
      Write-Host $_.Exception.Message
      Return $False
    }
  }
}