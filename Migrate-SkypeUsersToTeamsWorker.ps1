﻿#Ultimate user move script.


#DO NOT EXECUTE THIS SCRIPT DIRECTLY. USE Migrate-SkypeUsersToTeams.ps1 INSTEAD


<#Change log
    19/07/24
    Step 0 support
    Added pre migration checking, checks number ranges for missing users, and validates that the acounts are good to move.

    15/09/22
    Fixed reporting for Step 1 reporting simply "Skipped" for non-voice users.


    20/06/22
    Split Config and Worker to allow for Github sync without wiping out "per customer" settings
    Added Tools checking
    Intergrated On-prem and O365 tasks in one script


    19/06/22
    Added Error handling for numbers in use

    Teams Module 2.6.0 is no longer supported by Microsoft.
    Updated Number assignment logic to use Set-CsPhoneNumberAssignment as Set-CsOnlineVoiceUser is deprecated.
#>

#Check to see if we were called directly or not)
If ($url -notlike 'http*')
{
  Write-Host '' #add a blank line
  Write-Warning 'Do Not Call this script directly! Use Migrate-SkypeUsersToTeams.ps1 instead. Exiting'
  Throw 'Script Called without config. Exiting'
  Return
}

#All stages

##log file location
$LogFileLocation = $PSCommandPath -replace '.ps1', '.log' #Where do we store the log files? (In the same folder by default)


Write-Host 'INFO: Importing UcmPsTools Functions' -ForegroundColor Green

. $UcmPsTools  #Dot Source

Write-UcmLog -message 'Done.' -Severity 2


##import files
Set-Location -Path $Folder
Try { $users = Import-Csv $File -ErrorAction Stop } 
Catch
{
  Write-Warning 'Couldnt import CSV, Exiting'
  return
}


#Prepare environment
##TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


#Workers


if ($Step -eq 'Step0')
{
  #Setup Reporting and Progress Bars
  Initialize-UcmReport -Title 'Step 0' -Subtitle 'Number Range Validation' 
  $startTime = Get-Date 
  $usercount = ($users.count)
  $currentuser = 0


  #Okay first we need to calculate the number ranges from the supplied spreadsheet
  $ranges = @()
  $FoundonpremUsers = @()
  $MissingonpremUsers = @()

  Foreach ($user in $users) 
  {
    $ranges += ($user.lineuri.substring(5,($user.lineuri.Length - 7)))
  }
  #prune the duplicates
  $ranges = $ranges | Select-Object -Unique
  Write-UcmLog -message "Number Ranges: $($ranges -join ', ')" -Severity 2

  #search the on-prem environment for the ranges
  Foreach ($range in $ranges)
  {
    Write-UcmLog -message "Locating Onprem Users for $range" -Severity 2
    $Start = ("$range"+"00")
    $End = ("$range"+"99")

    $return = (Search-UcmCsOnPremNumberRange -start $start -end $end -usersonly)
    If ($return.status -eq 'Error')
    {
      Write-UcmLog -message "Something went wrong pulling the number range from onprem" -Severity 3
      
    }
    Else
    {
      <#$Return.Status
			$Return.Message
			$Return.Users
			$Return.PrivateLines
			$Return.AnalogDevices
			$Return.CommonAreaPhones
			$Return.ExchangeUM
			$Return.DialInConf
			$Return.ResponseGroups
			$Return.All
      #>
      $onpremUsers += $return.Users
    }
  }
  
  #Now, compare the on-prem users to the users in the CSV
  Initialize-UcmReport -Title 'Step 0' -Subtitle 'Onprem Account Prechecks' 
  $startTime = Get-Date 
  $usercount = ($onpremusers.count)
  $currentuser = 0

  foreach ($onpremuser in $onpremusers)
  { 
  #This isnt effecent, but it works
  $currentuser ++
  $usernametxt = $onpremuser.sipuri #Remove the CSV header
  New-UCMReportItem -LineTitle 'Username' -LineMessage "$usernametxt"
  Write-Progress -Activity 'Step 1' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation start -PercentComplete ((($currentuser) / $usercount) * 100)  
  Write-UcmLog -message "Checking On-Prem User $usernametxt" -Severity 1

  #dodgy loop to see if the user exists in the CSV
    $found = $false
    :Step0Loop foreach ($user in $users)
    {
      if ($onpremuser.LineURI -eq $user.LineURI)
      {
        $found = $true
        New-UcmReportStep -Stepname 'CSV File' -StepResult "OK: User in CSV"
        Write-UcmLog -message "Found!" -Severity 1
        Continue Step0Loop
      }
    }
    if ($found -eq $false)
    {
      New-UcmReportStep -Stepname 'CSV File' -StepResult "Error: User Not Present in CSV File!"
      Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) not found in CSV!" -Severity 3
      $MissingonpremUsers += $onpremuser
    }

    #Okay, now check the user is enabled in AD
    $Aduser = $null
    $Aduser = (Get-CsAdUser -Identity $usernametxt)

    if ($Aduser.UserAccountControl -match 'AccountDisabled') 
    {
      New-UcmReportStep -Stepname 'AD Account' -StepResult 'Error: AD Account Disabled'
      Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is disabled in AD!" -Severity 3
    }
    else
    {
      New-UcmReportStep -Stepname 'AD Account' -StepResult 'OK: AD Account Enabled'
      Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is enabled in AD!" -Severity 1
    }
    
    #Check they are enabled in Skype
    
    Try
    {
        $CsUser = (Get-CsAdUser -Identity $onpremuser.sipuri | Get-CsUser)

        if ($null -eq $CsUser.enabled) 
        {
          New-UcmReportStep -Stepname 'Skype Account' -StepResult 'Error: Skype Account Disabled'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is disabled in Skype!" -Severity 3
        }
        else
        {
          New-UcmReportStep -Stepname 'Skype Account' -StepResult 'OK: Skype Account Enabled'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is enabled in Skype!" -Severity 1
        }

        #and check they are homed on-prem
        if ($CsUser.hostingprovider -NE 'SRV:')
        {
          if ($IgnoreSRVCheckWarning)
          {
            New-UcmReportStep -Stepname 'S4B Account Location' -StepResult 'OK: User not homed on-prem'
            Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is not homed on-prem - Ignoring as 'IgnoreSRVCheckWarning' is True" -Severity 2
          }
          else
          {
            New-UcmReportStep -Stepname 'S4B Account Location' -StepResult 'Warning: User not homed on-prem'
            Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is not homed on-prem!" -Severity 3
          }
        }
        else
        {
          New-UcmReportStep -Stepname 'S4B Account Location' -StepResult 'OK: User Homed on-prem'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) is homed on-prem!" -Severity 1
        }
    }
    Catch
    {
          New-UcmReportStep -Stepname 'Skype Account' -StepResult 'Error: Not Found, Meeting Room?'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) Not Found, Meeting Room?" -Severity 3
          New-UcmReportStep -Stepname 'S4B Account Location' -StepResult 'Error: Not Found, Meeting Room?'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) Not Found, Meeting Room?" -Severity 3
          New-UcmReportStep -Stepname 'Skype Account' -StepResult 'Error: Not Found, Meeting Room?'
          Write-UcmLog -message "On-Prem User $($onpremuser.displayname) $($onpremuser.sipuri) Not Found, Meeting Room?" -Severity 3

    }




    #Calculate Statistics
    $elapsedTime = $(Get-Date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -Seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString('hh\:mm\:ss'))
}# end of Foreach User look

# now display the results
Write-Host 'On-Prem Users not found in CSV'
$MissingonpremUsers | Format-Table displayname, samaccountname, lineuri

# now display the results
Write-Host 'On-Prem Users not found in CSV'
$MissingonpremUsers | Format-Table displayname, sipaddress, lineuri

  New-UCMReportItem -LineTitle 'Username' -LineMessage 'Complete'
  $finished = (Get-Date -DisplayHint Time)
  Write-Host "Finished at $finished"
  Export-UcmHTMLReport | Out-Null
  Export-UcmCSVReport | Out-Null

}#end of step0

If ($step -eq 'Step1')
{
  #Setup Reporting and Progress Bars
  Initialize-UcmReport -Title 'Step 1' -Subtitle 'Licence and Service Plan Validation/Assignment' 
  $startTime = Get-Date 
  $usercount = ($users.count)
  $currentuser = 0
  
  #Check we are connected to MSOL
  $return = (Test-UcmMSOLConnection)
  if ($return.status -eq 'Error')
  {
    Write-UcmLog -message 'We arent connected to MSOL Service. Please run Connect-MsolService and try again' -Severity 3
    Return
  }

  #Process Each User
  :Step1Loop Foreach ($username in $users) 
  { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    
    Write-Progress -Activity 'Step 1' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation start -PercentComplete ((($currentuser) / $usercount) * 100)  
  
    #Figure out of the user has voice or not.
    $voice = $true
    if ($Username.lineuri.Length -le 2) 
    {
      Write-UcmLog -message 'No phone number, skipping voice features' -Severity 2
      $voice = $false
    }
    
    New-UCMReportItem -LineTitle 'Username' -LineMessage "$usernametxt"
    Write-UcmLog -message "User $usernametxt" -Severity 2
    [hashtable]$User = @{}
    $User.UPN = "$usernametxt"
    
    
    ##Todo## Add a check to see if the user exists and exit early if not.
    ##Continue Step1Loop


    #Apps and licences
    Write-Progress -Activity 'Step 1' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation Licences -PercentComplete ((($currentuser) / $usercount) * 100)
    #Licences
    If ($UserType -eq 'Users')
    {
    
      If ($voice) 
      { 
        #Enterprise Voice
        $step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOEV' -Country 'AU' -ReportOnly $ReportOnly)
        New-UcmReportStep -Stepname 'EV Licence' -StepResult "$($Step.status) $($step.message)"

        If ($mode -eq 'TCO')
        {
          #Telstra Calling
          $step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOPSTNEAU2' -Country 'AU' -ReportOnly $ReportOnly)
          New-UcmReportStep -Stepname 'TCO Licence' -StepResult "$($Step.status) $($step.message)"
        }
      }
      
      Else
      {
        New-UcmReportStep -Stepname 'EV Licence' -StepResult 'OK: No Voice, Skipped'
        New-UcmReportStep -Stepname 'TCO Licence' -StepResult 'OK: No Voice, Skipped'
      }
    }
    
    ElseIf ($UserType -eq 'MeetingRooms')
    {
      $step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOPSTNEAU2' -Country 'AU' -ReportOnly $ReportOnly)
      New-UcmReportStep -Stepname 'Meeting Licence' -StepResult "$($Step.status) $($step.message)"
    }
  
  
    #ServicePlans

    Write-Progress -Activity 'Step 1' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation ServicePlans -PercentComplete ((($currentuser) / $usercount) * 100)
    If ($UserType -eq 'Users')
    {
      #Teams Service Plan
      $step = (Enable-UcmO365Service -upn $user.upn -ServiceName TEAMS1 -ReportOnly $ReportOnly)
      New-UcmReportStep -Stepname 'Teams Service Plan' -StepResult "$($Step.status) $($step.message)"

    
      #Skype for Business Online Service Plan (Required to Migrate User from OnPrem to Online
      $step = (Enable-UcmO365Service -upn $user.upn -ServiceName MCOSTANDARD -ReportOnly $ReportOnly)
      New-UcmReportStep -Stepname 'SFBO Service Plan' -StepResult "$($Step.status) $($step.message)"

      #We check the voice mode before checking if we are doing voice at all so we can inject the skipped message in the right header.

      #Telstra Calling
      if ($mode -eq 'TCO') 
      {
        #Voice Licence
        if ($voice) 
        {
          $step = (Enable-UcmO365Service -upn $user.upn -ServiceName MCOPSTNEAU -ReportOnly $ReportOnly)
          New-UcmReportStep -Stepname 'TCO Service Plan' -StepResult "$($Step.status) $($step.message)"
        }
        Else
        {
          New-UcmReportStep -Stepname 'TCO Service Plan' -StepResult 'Skipped'
        }
      }

      if ($mode -eq 'DirectRouting') 
      {
        Write-UcmLog -message 'Direct Routing - Skip Voice Service Plan' -Severity 1
      }

      if ($mode -eq 'MSOC') 
      {
        Write-UcmLog -message 'Operator Connect - Skip Voice Service Plan' -Severity 1
      }

    }

    #Calculate Statistics
    $elapsedTime = $(Get-Date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -Seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString('hh\:mm\:ss'))
  }

  New-UCMReportItem -LineTitle 'Username' -LineMessage 'Complete'
  $finished = (Get-Date -DisplayHint Time)
  Write-Host "Finished at $finished"
  Export-UcmHTMLReport | Out-Null
  Export-UcmCSVReport | Out-Null
}

If ($step -eq 'Step2')
{
  #Check to see if we have the Skype4B Management Tools
  $Return = (Import-UcmCsOnPremTools)
  If ($Return.status -eq 'Error')
  {
    Write-Warning 'Step 2 must be performed from an On-prem server with the Skype4B tools installed '
    Return
  }

  #Setup Reporting and Progress Bars
  Initialize-UcmReport -Title 'Step 2' -Subtitle 'Old Policy Removal/User Migration to O365'
  
  $maxI = 250 
  $startTime = Get-Date 
  $usercount = ($users.count)
  $currentuser = 0
  
  #Setup Authentication
  
  #Used when the customers environment doesnt support OAUTH and the FrontEnd sever doesnt have access to the Office365 login pages. 
  #Can also store creds in a local file
  #Does not Support MFA!
  If ($AuthMethod -eq 'Credentials')
  {
    #Check we have creds in memory, if not check for cred.xml, failing that prompt the user and store them.
    If ($null -eq $Global:Config.SignInAddress)
    {
      Write-UcmLog -Message 'No Credentials stored in Memory, checking for Creds file' -Severity 2 -Component $function
      $CredsPath = $PSCommandPath -replace 'Migrate-SkypeUsersToTeamsWorker.ps1', 'cred.xml'
      If (!(Test-Path $CredsPath)) 
      {
        Write-UcmLog -component $function -Message 'Could not locate creds file' -severity 2

        #Create a new creds variable
        $null = (Remove-Variable -Name Config -Scope Global -ErrorAction SilentlyContinue)
        $global:Config = @{}

        #Prompt user for creds
        $Global:Config.SignInAddress = (Read-Host -Prompt 'Username')
        $Global:Config.Password = (Read-Host -Prompt 'Password')
        $Global:Config.Override = (Read-Host -Prompt 'OverrideDomain (Blank for none)')

        #Encrypt the creds
        $global:Config.Credential = ($Global:Config.Password | ConvertTo-SecureString -AsPlainText -Force)
        Remove-Variable -Name 'Config.Password' -Scope 'Global' -ErrorAction SilentlyContinue

        #write a secure creds file
        $Global:Config | Export-Clixml -Path $CredsPath
      }
      Else
      {
        Write-UcmLog -component $function -Message 'Importing Credentials File' -severity 2
        $global:Config = @{}
        $global:Config = (Import-Clixml -Path $CredsPath)
        Write-UcmLog -component $function -Message 'Creds Loaded' -severity 2
      }
    }

    #Get the creds ready for the module

    $global:StoredPsCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($global:Config.SignInAddress, $global:Config.Credential)
	($global:StoredPsCred).Password.MakeReadOnly() #Stop modules deleting the variable.
  
  
  }
  #Used when we want to force O365 to use OAuth, will attempt to authenticate using SSO, then failback to a login prompt
  Elseif ($AuthMethod -eq 'OAuth')
  {
  
  }
  #Dont specify anything in the move-Csuser cmdlet. Invokes the O365 Login prompt (supports MFA)
  Elseif ($AuthMethod -eq 'Prompt')
  {
  
  }
  #Process Each User
  :Step2Loop Foreach ($username in $users)
  { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    New-UCMReportItem -LineTitle 'Username' -LineMessage "$usernametxt"
    Write-Progress -CurrentOperation 'Init' -Activity 'Step 2' -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)

    Write-UcmLog -message "User $usernametxt" -Severity 2
    [hashtable]$User = @{}


    #AD Check
    Write-Progress -CurrentOperation 'Find User' -Activity 'Step 2' -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)
   
    $UserAD = $null
    $UserAD = (Get-CsAdUser -Identity $usernametxt)
    $CsUser = (Get-CsAdUser -Identity $usernametxt | Get-CsUser)
    
    If ($null -eq $UserAD) 

    {
      Write-UcmLog -message "Cant find on prem $usernametxt" -Severity 3
      New-UcmReportStep -Stepname 'AD Account' -StepResult 'Error: Couldnt Locate AD Account'
      New-UcmReportStep -Stepname 'Skype Account Check' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'Move User to O365' -StepResult 'Skipped'
      Continue Step2loop #exit foreach loop

    }
    Elseif ($UserAD.UserAccountControl -match 'AccountDisabled') 
    {
     Write-UcmLog -message "$usernametxt has a disabled AD account" -Severity 3
      New-UcmReportStep -Stepname 'AD Account' -StepResult 'Error: Account Disabled'
      New-UcmReportStep -Stepname 'Skype Account Check' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'Move User to O365' -StepResult 'Skipped'
      Continue Step2loop #exit foreach loop
    }

    Else
    { 
      New-UcmReportStep -Stepname 'AD Account' -StepResult 'OK: AD Account Found'
      $User.UPN = $usernametxt
    }

    #Check to see if the user is actually on prem

    If ($CsUser.hostingprovider -NE 'SRV:')
    {
      Write-UcmLog -message 'User doesnt appear to be homed in Skype4B on-prem' -Severity 3
      New-UcmReportStep -Stepname 'Skype Account Check' -StepResult 'Error: User doesnt appear to be hosted on-prem'

      Try
      {
        Write-UcmLog -message 'Removing Skype Policies from user' -Severity 2
        #Supress all the "We didnt change anything warnings (Store the old preference so we respect the users setting)
        $OldWarningpref = $WarningPreference
        $WarningPreference = 'SilentlyContinue'
        SkypeForBusiness\Set-CsUser -Identity $csuser.sipaddress -LineURI $null -EnterpriseVoiceEnabled $False 
        #Restore the old Warning Perference
        $WarningPreference = $OldWarningpref
        New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult 'OK'
      }
      Catch
      {
        New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult "Error: $error[0]"
        Write-UcmLog -message "Something went wrong stripping Skype Policies from user $usernametxt" -Severity 3
        Write-UcmLog -message "$Error[0]" -Severity 3
      }
      New-UcmReportStep -Stepname 'Move User to O365' -StepResult 'Skipped'
      Continue Step2Loop
    }
    Else
    {
      Write-UcmLog -message 'Found Skype Account On-Prem' -Severity 2
      New-UcmReportStep -Stepname 'Skype Account Check' -StepResult 'OK'
    }

    #Remove all those pesky policies that can only be set on-prem before moving the user to the cloud
    Write-Progress -CurrentOperation 'Clear Skype Policies' -Activity 'Step 2' -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)
        
    #Clear Skype4B attributes that can be difficult to remove later. 
    #These dont affect Teams and can stop a Skype4B FrontEnd from being decommisioned.
    Try
    {
      Write-UcmLog -message 'Removing Skype Policies from user' -Severity 2
      #Supress all the "We didnt change anything warnings (Store the old preference so we respect the users setting)
      $OldWarningpref = $WarningPreference
      $WarningPreference = 'SilentlyContinue'
      SkypeForBusiness\Set-CsUser -Identity $csuser.sipaddress -LineURI $null -EnterpriseVoiceEnabled $False 
      SkypeForBusiness\Grant-CsPresencePolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsLocationPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsClientPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsClientVersionPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsArchivingPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsPinPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsExternalAccessPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsMobilityPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsPersistentChatPolicy -Identity $csuser.sipaddress -PolicyName $null
      SkypeForBusiness\Grant-CsCallViaWorkPolicy -Identity $csuser.sipaddress -PolicyName $null
      
      #Restore the old Warning Perference
      $WarningPreference = $OldWarningpref
      New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult 'OK'
    }
    Catch
    {
      New-UcmReportStep -Stepname 'Clear Skype Policies' -StepResult "Error: $error[0]"
      Write-UcmLog -message "Something went wrong stripping Skype Policies from user $usernametxt" -Severity 3
      Write-UcmLog -message "$Error[0]" -Severity 3
    }
    


    #Move the user to O365
    IF ($null -eq (Get-CsAdUser $usernametxt).enabled) { Write-Warning 'User is not enabled on prem' }


    #Move user

    Write-Progress -CurrentOperation 'Move user' -Activity 'Step 2' -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)

    Try
    {
    
      #Used when the customers environment doesnt support OAUTH and the FrontEnd sever doesnt have access to the Office365 login pages. 
      #Can also store creds in a local file
      #Does not Support MFA!
      If ($AuthMethod -eq 'Credentials')
      {
        Move-CsUser -Identity $csuser.sipaddress -Target sipfed.online.lync.com -MoveToTeams -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool $FrontEnd -BypassAudioConferencingCheck -Credential $global:StoredPsCred -force
      }
      #Used when we want to force O365 to use OAuth, will attempt to authenticate using SSO, then failback to a login prompt
      Elseif ($AuthMethod -eq 'OAuth')
      {
           Move-CsUser -Identity $csuser.sipaddress -Target sipfed.online.lync.com -MoveToTeams -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool $FrontEnd -BypassAudioConferencingCheck -UseLegacyMode -force
      }
      #Dont specify anything in the move-Csuser cmdlet. Invokes the O365 Login prompt (supports MFA)
      Elseif ($AuthMethod -eq 'Prompt')
      {
        Move-CsUser -Identity $csuser.sipaddress -Target sipfed.online.lync.com -MoveToTeams -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool $FrontEnd -BypassAudioConferencingCheck -force
      }

      New-UcmReportStep -Stepname 'Move User to O365' -StepResult 'OK'
    }
    Catch
    {
    
      New-UcmReportStep -Stepname 'Move User to O365' -StepResult "Error: $error[0]"
      Write-UcmLog -message "Something went wrong moving user $usernametxt to Office365" -Severity 3
      Write-UcmLog -message "$Error[0]" -Severity 3
    
    }
    
    #Move-CsMeetingRoom -Identity $user.upn -Target sipfed.online.lync.com -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool sfbfeprd.agl.com.au -UseOAuth -Credential $foo



    #Statistics for time estimate
    $elapsedTime = $(Get-Date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -Seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString('hh\:mm\:ss'))
  }
  New-UCMReportItem -LineTitle 'Username' -LineMessage 'Complete'
  $finished = (Get-Date -DisplayHint Time)
  Write-Host "Finished at $finished"
  Export-UcmHTMLReport | Out-Null
  Export-UcmCSVReport | Out-Null
  
}

If ($step -eq 'Step3')
{
  Initialize-UcmReport -Title 'Step 3' -Subtitle 'Policy and Number Assignment'
  $maxI = 250 
  $startTime = Get-Date 
  $usercount = ($users.count)
  $currentuser = 0
  Foreach ($username in $users)
  { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    New-UCMReportItem -LineTitle 'Username' -LineMessage "$usernametxt"
    Write-Progress -Activity 'Step 3' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation start -PercentComplete ((($currentuser) / $usercount) * 100)
    Write-UcmLog -message "User: $usernametxt" -Severity 2
    
    [hashtable]$User = @{}

    $User.UPN = "$usernametxt"
  
    #figure out of the user has voice or not.
    $voice = $true
    if ($Username.lineuri.Length -le 2) 
    {
      Write-UcmLog -message 'No phone number, Skipping Voice tasks' -Severity 2
      $voice = $false
    }
  
    #Microsoft Changed something that made us need the sip address instead of a UPN!
    #get the Sip Address off the user 
    Try 
    { 
      Write-Progress -Activity 'Step 3' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation SipAddress -PercentComplete ((($currentuser) / $usercount) * 100)
      $Sip = (Get-CsOnlineUser $User.UPN).sipaddress
      New-UcmReportStep -Stepname 'Locate Sip Address' -StepResult $sip.ToString()
      Write-UcmLog -message 'Sip Address: Good' -Severity 2

  
  
      #Force to Teams only mode
      Try 
      { 
        Write-Progress -Activity 'Step 3' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation TeamsOnly -PercentComplete ((($currentuser) / $usercount) * 100)
        Grant-CsTeamsUpgradePolicy -PolicyName UpgradeToTeams -Identity $sip
        New-UcmReportStep -Stepname 'Upgrade Policy' -StepResult 'OK'
        Write-UcmLog -message 'Upgrade Policy: Good' -Severity 2
      }
      Catch
      {
        New-UcmReportStep -Stepname 'Upgrade Policy' -StepResult "Error, unknown error $($error[0])"
        Write-UcmLog -message "Upgrade Policy: No Good! $($error[0])" -Severity 3
      }
 

      #Set Dialplan
      #VicTasDialplan-Unrestricted
      #NSWACTDialplan-Unrestricted
      #QLDDialplan-Unrestricted

      #AUS-NSW-ACT-02 > NSWACTDialplan-Standard
      #AUS-VIC-TAS-03 > VicTasDialplan-Standard
      #AUS-WA-SA-NT-08 >WASANTDialPlan-Standard
      #AUS-QLD-07 > QLDDialplan-Standard
     
      <# Rafat  Dialplans
          Write-Host "Dialplan"
          Write-Host $Username.dialplan
          If ($Username.dialplan -eq "AUS-NSW-ACT-02") {
          Write-Host "Granting NSWACTDialplan-Standard"
          $Dialplan = "NSWACTDialplan-Standard" }

          If ($Username.dialplan -eq "AUS-VIC-TAS-03") {
          Write-Host "Granting VicTasDialplan-Standard "
          $Dialplan = "VicTasDialplan-Standard" }


          If ($Username.dialplan -eq "AUS-WA-SA-NT-08") {
          Write-Host "Granting WASANTDialPlan-Standard "
          $Dialplan =  "WASANTDialPlan-Standard" }

          If ($Username.dialplan -eq "AUS-QLD-07") {
          Write-Host "Granting QLDDialplan-Standard "
          $Dialplan = "QLDDialplan-Standard" }
      #>

               
      if ($voice) 
      {
        Write-Progress -Activity 'Step 3' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation DialPlan -PercentComplete ((($currentuser) / $usercount) * 100)
        #Write-Host $Username.dialplan
        If ($Username.dialplan -eq 'AUS-NSW-ACT-02')
        {
          #Write-Host "Granting AUS-NSW-ACT-02-EXT"
          $Dialplan = 'AUS-NSW-ACT-02-EXT' 
        }

        If ($Username.dialplan -eq 'AUS-VIC-TAS-03')
        {
          #Write-Host "Granting AUS-VIC-TAS-03-EXT"
          $Dialplan = 'AUS-VIC-TAS-03-EXT' 
        }


        If ($Username.dialplan -eq 'AUS-WA-SA-NT-08')
        {
          #Write-Host "Granting AUS-WA-SA-NT-08"
          $Dialplan = 'AUS-WA-SA-NT-08' 
        }

        If ($Username.dialplan -eq 'AUS-QLD-07')
        {
          # Write-Host "Granting AUS-QLD-07"
          $Dialplan = 'AUS-QLD-07' 
        }
     
        #Grant-CsTenantDialPlan -Identity $user.upn -PolicyName "VICTasDialplan-Unrestricted"
        Try 
        { 
          Grant-CsTenantDialPlan -Identity $sip -PolicyName $Dialplan -ErrorAction Stop
          New-UcmReportStep -Stepname 'Dialplan' -StepResult "OK, $dialplan"
          Write-UcmLog -message 'DialPlan: Good' -Severity 2
        }
        Catch
        {
          New-UcmReportStep -Stepname 'DialPlan' -StepResult "Error, unknown error $($error[0])"
          Write-UcmLog -message "DialPlan: No Good! $($error[0])" -Severity 3
        }
      }
      Else
      {
        New-UcmReportStep -Stepname 'DialPlan' -StepResult 'OK: Not Voice Enabled'
      }
    
      if ($voice) 
      {
        Write-Progress -Activity 'Step 3' -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation LineUri -PercentComplete ((($currentuser) / $usercount) * 100)
        $Username.lineuri = ($Username.lineuri -replace 'tel:', '')
        #write-host "Assigning $($Username.lineuri)"
  
        Try 
        { 
          #Set-CsOnlineVoiceUser -Identity $sip -TelephoneNumber $Username.lineuri -ErrorAction Stop   ### 2.6.0 version
          if ($mode -eq 'TCO') 
          {
            Write-UcmLog -message 'Assigning TCO Number' -Severity 1
            
            Set-CsPhoneNumberAssignment -Identity $sip -PhoneNumber $Username.lineuri  -PhoneNumberType CallingPlan -ErrorAction Stop 
          }
          if ($mode -eq 'DirectRouting') 
          {
            Write-UcmLog -message 'Assigning Direct Routing Number' -Severity 1
            Set-CsPhoneNumberAssignment -Identity $sip -PhoneNumber $Username.lineuri  -PhoneNumberType DirectRouting -ErrorAction Stop 
          }
    
          if ($mode -eq 'MSOC') 
          {
            Write-UcmLog -message 'Assigning Operator Connect Number' -Severity 1
            Set-CsPhoneNumberAssignment -Identity $sip -PhoneNumber $Username.lineuri  -PhoneNumberType OperatorConnect -ErrorAction Stop 
          }
          
          New-UcmReportStep -Stepname 'LineURI' -StepResult "OK, $($Username.lineuri)"
          Write-UcmLog -message 'LineURI: Good' -Severity 2
        }
        Catch
        {
          #Error Handling for Numbers 
          
          #Number Exists in AD (error thrown by Old 2.6.0 Teams Module)
          If ($error[0] -like '*in Active Directory.')
          {
            Write-UcmLog -message 'Number Already Exists in AD.. finding user' -Severity 3
            #My dodgy RegEx to capture the GUID
            $ErrorUserGUID = ([regex]::Matches($Error[0], '\w{8}-\w{4}-\w{4}-\w{4}-\w{12}').value)
            $ErrorUser = Get-CsOnlineUser -Identity $ErrorUserGUID
            Write-UcmLog -message "$($ErrorUser.userprincipalname) is already using $($username.lineuri)" -Severity 3
            New-UcmReportStep -Stepname 'LineURI' -StepResult "Error $($ErrorUser.userprincipalname) is already using $($username.lineuri) Remove the Number and perform an AADSync (if required) before trying again"       
            $error.Clear()
          }
          #Number Already Assigned (Teams Module 4.x.x.x and greater)
          ElseIf ($error[0] -like '* has already been assigned to another user')
          {
            Write-UcmLog -message 'Number Already Assigned... Finding offending user' -Severity 3
            #Find the guid of the match
            $ErrorUserGUID = (Get-CsPhoneNumberAssignment -TelephoneNumber $username.lineuri).AssignedPstnTargetId
            #Now find the user
            $ErrorUser = Get-CsOnlineUser -Identity $ErrorUserGUID

            Write-UcmLog -message "$($ErrorUser.userprincipalname) is already using $($username.lineuri)" -Severity 3
            New-UcmReportStep -Stepname 'LineURI' -StepResult "Error $($ErrorUser.userprincipalname) is already using $($username.lineuri) Remove the Number and perform an AADSync (if required) before trying again"       
            $error.Clear()

          }
          
          
          #Unhandled Number Error
          Else
          {
            New-UcmReportStep -Stepname 'LineURI' -StepResult "Error, unknown error $($error[0])"
            Write-UcmLog -message "LineURI: No Good! $($error[0])" -Severity 3
          }
        }
   
      }
      Else
      {
        New-UcmReportStep -Stepname 'LineURI' -StepResult 'OK: Not Voice Enabled'
      }

      Get-CsOnlineUser $user.upn | Format-List displayname, EnterpriseVoiceEnabled, OnPremLineUriManuallySet, OnPremLineUri, Telephonenumber, LineUri, tenantdialplan, MCOValidationError, voicepolicy , InterpretedUserType, TeamsUpgradeEffectiveMode
    }
    Catch
    {
      New-UcmReportStep -Stepname 'Locate Sip Address' -StepResult "Error, unknown error $($error[0])"
      New-UcmReportStep -Stepname 'Upgrade Policy' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'Dialplan' -StepResult 'Skipped'
      New-UcmReportStep -Stepname 'LineURI' -StepResult 'Skipped'
      
      Write-UcmLog -message "Cant locate user, skipping. $($error[0])" -Severity 3

    }


    #Calculate Statistics
    $elapsedTime = $(Get-Date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -Seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString('hh\:mm\:ss'))


  }
  New-UCMReportItem -LineTitle 'Username' -LineMessage 'Complete'
  $finished = (Get-Date -DisplayHint Time)
  Write-Host "Finished at $finished"
  Export-UcmHTMLReport | Out-Null
  Export-UcmCSVReport | Out-Null
  

}
