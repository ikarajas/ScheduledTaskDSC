<#
A simple DSC Scheduled Task resource. 
Only one Action permitted at present
Only one Trigger permitted at present

        xScheduledTask TestTask
        {
            Ensure = "Present"
            Name = "Test ScheduledTask"
            Arguments = " -noprofile -command `"Get-Website`""
            Execute = "powershell.exe"
            At = "9:30AM"
            Repeat = "Custom"
            IntervalMinutes = 20
            UserName = "SYSTEM"
        }     

#>

Function Get-TargetResource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        [ValidateSet("Absent", "Present")]
        $Ensure,
        [string]
        [ValidateScript({
            # maybe check if the path is resolvable?
            $true # temporary
        })]
        $Execute,
        $Arguments,
        [ValidateScript({
            [datetime]$_
        })]
        $At,
        [string]
        [ValidateSet("Daily", "Weekly", "Once", "DaysOfWeek", "Hourly", "Custom")]
        $Repeat,  
        [string[]]
        $Days,  # days of week for when "DaysOfWekk" is used
        [parameter(Mandatory=$false)]
        [int]
        [ValidateRange(0,1339)] # one minute to one day minus one minute
        $IntervalMinutes, # Only usable if Repeat is Custom
        $UserName = "SYSTEM", #  Always runs as a BUILTIN principal. ValidateSet should ideally allow LocalSystem, LocalService or NetworkService
        $TaskPath = "\ScheduledTaskDSC\"
    )
    
    if(($Repeat -eq "Custom") -and ($IntervalMinutes -eq "" -or $IntervalMinutes -eq "")) {
        throw "`r`nIf using Custom Repetition, you must supply the `$intervalMinutes parameter"
    }

    $Tasks = Get-ScheduledTask | ? { $_.TaskName -eq $Name -and $_.TaskPath -eq $TaskPath }

    if(($Tasks | measure | select -expand count) -gt 0)
    {
        # task exists
        Write-Verbose "Task exists, returning Task details as hashtable"
        $ensureResult = "Present"
        $Task = $Tasks | select -first 1
        $getTargetResourceResult = @{
                                        Name = $Task.TaskName
                                        Ensure = $ensureResult
                                        Execute = ($Task.Actions | select -First 1 | select -ExpandProperty Execute)
                                        Arguments = ($Task.Actions | select -First 1 | select -ExpandProperty Arguments)
                                        At = ($Task.Triggers | select -first 1 | select -ExpandProperty StartBoundary) 
                                        Repeat = ($Task.Triggers | select -first 1 | select -ExpandProperty Repetition | select -expand Interval)
                                        IntervalMinutes = $null
                                        UserName = $Task.Principal.UserId
                                        TaskPath = $TaskPath
                                    }
    }
    else
    {
        # no task exists
        Write-Verbose "No task exists, returning DSC Arguments as hashtable"
        $ensureResult = "Absent"
        $getTargetResourceResult = @{
                                        Name = $Name
                                        Ensure = $ensureResult
                                        Execute = $Execute
                                        Arguments = $arguments
                                        At = $At
                                        Repeat = $Repeat
                                        IntervalMinutes = $IntervalMinutes
                                        UserName = $UserName
                                        TaskPath = $TaskPath
                                    }
    }


    return $getTargetResourceResult

}

Function Test-TargetResource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        [ValidateSet("Absent", "Present")]
        $Ensure,
        [string]
        [ValidateScript({
            # maybe check if the path is resolvable?
            $true # temporary
        })]
        $Execute,
        $Arguments,
        [ValidateScript({
            [datetime]$_
        })]
        $At,
        [string]
        [ValidateSet("Daily", "Weekly", "Once", "DaysOfWeek", "Hourly", "Custom")]
        $Repeat,  
        [string[]]
        $Days,  # days of week for when "DaysOfWekk" is used
        [parameter(Mandatory=$false)]
        [int]
        [ValidateRange(0,1339)] # one minute to one day minus one minute
        $IntervalMinutes, # Only useful if $Repeat is "Custom"
        $UserName = "SYSTEM", #  ValidateSet should ideally allow LocalSystem, LocalService or NetworkService
        $TaskPath = "\ScheduledTaskDSC\"
    )

    Write-Verbose "Running Test-TargetResource now"

    # need to Trim() all our arguments

    if(($Repeat -eq "Custom") -and ($IntervalMinutes -eq "" -or $IntervalMinutes -eq "")) {
        throw "`r`nIf using Custom Repetition, you must supply the `$intervalMinutes parameter"
    }

    $Task = Get-TargetResource  -Name $Name `
                                -Ensure $Ensure `
                                -Execute $execute `
                                -Arguments $Arguments `
                                -at $at `
                                -Repeat $Repeat `
                                -IntervalMinutes $IntervalMinutes `
                                -UserName $UserName `
                                -Verbose

    $taskOK = $true # assume it's OK

    $taskName = $Task.Name

    Write-Verbose "Examining Task name $Name ($TaskName)"

    if(($ensure -eq $Task.Ensure) -and 
        ($Execute -eq $Task.Execute) -and 
        ($Arguments -eq $Task.Arguments)
      )
    {
        # things match, to the extent that we're checking them. no worries, McFlurries.

        Write-Verbose "Test-TargetResource has detected no drift"
    }
    else
    {
        
        Write-Verbose "Test-TargetResource has detected variance from desired state"

        $TaskExecute = $Task.Execute 
        $TaskEnsure = $Task.Ensure 
        $TaskArguments = $Task.Arguments

        Write-Verbose "Execute requested: $Execute "
        Write-Verbose "Execute in service: $TaskExecute "

        Write-Verbose "Ensure requested: $Ensure "
        Write-Verbose "Ensure in service: $TaskEnsure "

        Write-Verbose "Arguments requested: $arguments"
        Write-Verbose "Arguments in service: $TaskArguments"

        $TaskOK = $false # it either exists when it shouldn't, or it doesn't exist when it should
                         # return false here and let Set-TargetResource do its job
    }

    return $taskOK
}

Function Set-TargetResource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $Name,
        [ValidateSet("Absent", "Present")]
        $Ensure,
        [string]
        [ValidateScript({
            # maybe check if the path is resolvable?
            $true # temporary
        })]
        $Execute,
        $Arguments,
        [ValidateScript({
            [datetime]$_
        })]
        $At,
        [string]
        [ValidateSet("Daily", "Weekly", "Once", "DaysOfWeek", "Hourly", "Custom")]
        $Repeat, 
        [string[]]
        $Days,  # days of week for when "DaysOfWeek" is used
        [parameter(Mandatory=$false)]
        [int]
        [ValidateRange(0,1339)] # one minute to one day minus one minute
        $IntervalMinutes, # Only usable if Repeat is Custom
        $UserName = "SYSTEM", #  Always runs as a BUILTIN principal. ValidateSet should ideally allow LocalSystem, LocalService or NetworkService
        $TaskPath = "\ScheduledTaskDSC\"
    )
    
    if(($Repeat -eq "Custom") -and ($IntervalMinutes -eq "" -or $IntervalMinutes -eq "")) {
        throw "`r`nIf using Custom Repetition, you must supply the `$intervalMinutes parameter"
    }

    Write-Verbose "Running Set-TargetResource"

    if($Ensure -eq "Present")
    {
        

        # prep our objects for creation or updating
        $trigger = $null

        switch($Repeat)
        {
            "Daily" {
                $trigger = New-ScheduledTaskTrigger -At $At -Daily
            }
            "Weekly" {
                $dttmp = Get-Date -Date $At 
                $dayofweek = $dttmp.DayOfWeek
                Write-Verbose "Detected $dayofweek as target day"
                $trigger = New-ScheduledTaskTrigger -At $At -Weekly -DaysOfWeek @($dayofweek) # does it expect an array?
                # bug - prompts for "DaysOfWeek"
            }
            "DaysOfWeek" {
                $trigger = New-ScheduledTaskTrigger -At $At -DaysOfWeek 
                # bug, so far doesn't take input
            }
            "Once" {
                $trigger = New-ScheduledTaskTrigger -At $At -Once
            }
            "Hourly" {
                $trigger = New-ScheduledTaskTrigger -At $At `
                                                    -RepetitionInterval (New-TimeSpan -Hours 1) `
                                                    -RepetitionDuration ([timespan]::MaxValue) `
                                                    -Once # [timespan]::MaxValue disables the expiry of repetitions
            }
            "Custom" {
                $trigger = New-ScheduledTaskTrigger -At $At `
                                                    -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) `
                                                    -RepetitionDuration ([timespan]::MaxValue) `
                                                    -Once 
            }
            Default { # also once 
                $trigger = New-ScheduledTaskTrigger -At $At -Once 
            }
        }

        $action = $null

        # TODO: add WorkingDirectory
        if($Arguments -eq $null -or $Arguments -eq "")
        {
            Write-Verbose "Arguments not provided"
            $action = New-ScheduledTaskAction -Execute $Execute -Verbose 
        }
        else
        {
            Write-Verbose "Arguments provided"
            $action = New-ScheduledTaskAction -Execute $Execute -Argument $Arguments -Verbose 
        }

        $date = Get-Date -Format g 

        # TODO: enable options
        $settings = New-ScheduledTaskSettingsSet -Verbose 

        if((Get-ScheduledTask | ? {$_.TaskName -eq $Name -and $_.TaskPath -eq $TaskPath } | measure | select -expand Count) -gt 0)
        {
            Write-Verbose "Task exists and must be updated"

            $taskXML = Set-ScheduledTask   -TaskName $name `
                                -User $UserName `
                                -Action $action `
                                -Trigger $trigger `
                                -Settings $settings `
                                -TaskPath $TaskPath `
                                -Verbose 

         }
        else
        {
            # create the task now
            Write-Verbose "Task does not exist, creating"
            $taskXML = Register-ScheduledTask  -TaskName $name `
                                    -User $UserName `
                                    -Action $action `
                                    -Trigger $trigger `
                                    -Settings $settings `
                                    -Description "Added by DSC $date" `
                                    -TaskPath $TaskPath `
                                    -RunLevel 1 `
                                    -Verbose 
        }                     

    }
    else
    {
        # delete the thing, I guess
        Write-Verbose "Ensure=`"Absent`" was requested, removing task"
        Unregister-ScheduledTask -TaskName $Name -Verbose
    }
}