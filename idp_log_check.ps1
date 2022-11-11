## Configuration variables
$too_old_threshold = (86400 * 3)
$PreVstaFilePath = "C:\Documents and Settings\All Users\Application Data\Intuit\Intuit Data Protect\" 
$PostVstaFilePath = "C:\ProgramData\Intuit\Intuit Data Protect\"

## Declaration of variables
[datetime]$origin = '1970-01-01 00:00:00'
[datetime]$last_successful_time = $origin
[datetime]$last_completion_time = $origin
[datetime]$last_failure_time = $origin.AddSeconds(-1)

## Creates an array of "events" from the log file
#Look for EventLog First
  Remove-EventLog -Source IntuitDataProtect
  try {Get-EventLog -LogName Application -Source IntuitDataProtect}
  Catch {
    New-EventLog -LogName Application -Source IntuitDataProtect
    Write-Output "Log not found, creating Cartwheel log"
    Write-EventLog -LogName Application -Source IntuitDataProtect -Message "Initialization Complete" -EventID 1001 -EntryType Information
    }
  finally {
    Write-Output "Moving On"
    }
Function Get-IntuitLog {
    Param([Parameter(Mandatory=$true)]$logname)
    if ($env:ProgramData) {
        if (Test-Path ($PostVstaFilePath + $logname + ".0")) {$logfile = $PostVstaFilePath + $logname + ".0"}
        elseif (Test-Path ($PostVstaFilePath + $logname)) {$logfile = $PostVstaFilePath + $logname}
        else {
			$error_msg = "The file " + $logname + " does not exist."
      Write-EventLog -LogName Application -Source IntuitDataProtect -Message $error_msg -EventID 3 -EntryType Critical
			Write-Host $error_msg 
			exit 1001
		}
    }
    else {
        if (Test-Path ($PreVstaFilePath + $logname + ".0")) {$logfile = $PreVstaFilePath + $logname + ".0"}
        elseif (Test-Path ($PreVstaFilePath + $logname)) {$logfile = $PreVstaFilePath + $logname}
        else {
			$error_msg = "The file " + $logname + " does not exist."
      Write-EventLog -LogName Application -Source IntuitDataProtect -Message $error_msg -EventID 3 -EntryType Critical
			Write-Host $error_msg
			exit 1001
		}
    }
    return $logfile
}

Function Parse-DateTime {
    Param([Parameter(Mandatory=$true)]$event)
    $event_array = $event.split(" ")
    $event_datestring = $event_array[1] + " " + $event_array[2] + ", " + $event_array[4].Replace(":","") + " " + $event_array[3]
    $event_date = Get-Date $event_datestring
    return $event_date
}


$events = Get-Content (Get-IntuitLog -logname "IBuEng.log")
if ($events -eq $null){Write-EventLog -LogName Application -Source IntuitDataProtect -Message $"Backup has never attempted to start." -EventID 3 -EntryType Critical; exit 1001}

## Validates and parses date/time strings in the format of "%m/%d/%y %I:%M%p".
$last_snapshot = Parse-DateTime -event ($events | ? {$_ -match "Result DoSnapshot: 0"})[-1]
$last_prepareforVSS = Parse-DateTime -event ($events | ? {$_ -match "Result PrepareForShadowCopy: 0"})[-1]
$last_prepareVSS = Parse-DateTime -event ($events | ? {$_ -match "Result PrepareShadowCopy: 0"})[-1]
$last_cleanupsnapshot = Parse-DateTime -event ($events | ? {$_ -match "Result CleanupSnapshot: 0"})[-1]
$last_cleanupVSS = Parse-DateTime -event ($events | ? {$_ -match "Result CleanShadowCopy: 0"})[-1]

$dates = $last_prepareforVSS, $last_cleanupsnapshot, $last_cleanupVSS, $last_prepareVSS, $last_snapshot
$last_successful_time = $dates | Sort-Object | Select-Object -First 1
$last_completion_time = $last_successful_time


## Determines success/failure based on completion, success, and failure times
if ($last_completion_time -eq $origin){
  $output_msg = "Backup has never completed."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 3 -EntryType Critical
  Write-Host $output_msg
  exit 1001
}
elseif ($last_successful_time -eq $origin){
  $output_msg = "Backup has never been successful. Last completion: " + $last_completion_time.ToString("yyyy-MM-dd, HH:mm:ss") + "."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 3 -EntryType Critical
  Write-Host $output_msg
  exit 1001
}
elseif (((Get-Date) - $last_completion_time).TotalSeconds -gt $too_old_threshold){
  $output_msg = "Last backup is old. Last completion: " + $last_completion_time.ToString("yyyy-MM-dd, HH:mm:ss") + "."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 2 -EntryType Warning
  Write-Host $output_msg
  exit 1001
}
elseif (((Get-Date) - $last_successful_time).TotalSeconds -gt $too_old_threshold){
  $output_msg = "Last successful backup is old. Last success: " + $last_successful_time.ToString("yyyy-MM-dd, HH:mm:ss") + "."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 2 -EntryType Warning
  Write-Host $output_msg
  exit 1001
}
elseif ($last_completion_time -gt $last_successful_time){
  $output_msg = "Last backup had errors. Last success: " + $last_successful_time.ToString("yyyy-MM-dd, HH:mm:ss") + "."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 2 -EntryType Warning
  Write-Host $output_msg
  exit 0
}
else {
  $output_msg = "Last backup was successful. Last success:" + $last_successful_time.ToString("yyyy-MM-dd, HH:mm:ss") + "."
  Write-EventLog -LogName Application -Source IntuitDataProtect -Message $output_msg -EventID 1 -EntryType Information
  Write-Host $output_msg
  exit 0
}