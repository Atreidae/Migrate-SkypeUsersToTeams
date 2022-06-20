#Ultimate user move script.


#DO NOT EXECUTE THIS SCRIPT DIRECTLY. USE Migrate-SkypeUsersToTeams.ps1 INSTEAD


<#Change log

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
If ($url -notlike "http*")
{
  Write-Host '' #add a blank line
  Write-Warning "Do Not Call this script directly! Use Migrate-SkypeUsersToTeams.ps1 instead. Exiting"
  Throw "Script Called without config. Exiting"
  Return
}

#All stages

#log location
$LogFileLocation =  $PSCommandPath -replace '.ps1','.log' #Where do we store the log files? (In the same folder by default)


Write-host "INFO: Importing Functions" -ForegroundColor Green

. $UcmPsTools  #Dot Source

Write-UcmLog -message "Done." -Severity 2


##import files
cd $Folder
Try {$users = Import-CSV $File -ErrorAction Stop} 
Catch
{
  Write-Warning "Couldnt import CSV"
  return
}


#Prepare environment
##TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


#Workers

If ($step -eq "Step1")
{
  #Setup Reporting and Progress Bars
  Initialize-UcmReport -Title "Step 1" -Subtitle "Licence and Service Plan Validation/Assignment"
  $maxI = 250 
  $startTime = get-date 
  $usercount = ($users.count)
  $currentuser = 0

  #Process Each User
  Foreach ($username in $users) { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    
    Write-Progress -Activity "Step 1" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation start -PercentComplete ((($currentuser) / $usercount) * 100)
  
    
  
    #figure out of the user has voice or not.
    $voice = $true
    if ($Username.lineuri.Length -le 2) 
    {
      Write-UcmLog -message "No phone number, disabling voice features" -Severity 2
      $voice = $false
    }
    New-UCMReportItem -LineTitle "Username" -LineMessage "$usernametxt"
    Write-UcmLog -message "User $usernametxt" -Severity 2
    [hashtable]$User = @{}
    $User.UPN = "$usernametxt"
    #$VerbosePreference = Continue




    #Apps and licences
    Write-Progress -Activity "Step 1" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation Licences -PercentComplete ((($currentuser) / $usercount) * 100)
    #Licences
  
    #Meetingrooms
    #$step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOPSTNEAU2' -Country 'AU')
    #New-UcmReportStep -Stepname "Meeting Licence" -StepResult "$($Step.status) $($step.message)"

    If ($voice) 
    { 
      #Enterprise Voice
      $step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOEV' -Country 'AU')
      New-UcmReportStep -Stepname "EV Licence" -StepResult "$($Step.status) $($step.message)"

      #Telstra Calling
      $step = (Grant-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOPSTNEAU2' -Country 'AU')
      New-UcmReportStep -Stepname "TCO Licence" -StepResult "$($Step.status) $($step.message)"
    }
    else
    {
      New-UcmReportStep -Stepname "EV Licence" -StepResult "Skipped"
      New-UcmReportStep -Stepname "TCO Licence" -StepResult "Skipped"
    }

    #ServicePlans

    Write-Progress -Activity "Step 1" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation ServicePlans -PercentComplete ((($currentuser) / $usercount) * 100)

    #Teams
    $step = (Enable-UcmO365Service -upn $user.upn -ServiceName TEAMS1)
    New-UcmReportStep -Stepname "Teams Service Plan" -StepResult "$($Step.status) $($step.message)"

    if ($voice) 
    {
      #Telstra Calling
      $step = (Enable-UcmO365Service -upn $user.upn -ServiceName MCOPSTNEAU)
      New-UcmReportStep -Stepname "TCO Service Plan" -StepResult "$($Step.status) $($step.message)"
    }
    Else
    {
      New-UcmReportStep -Stepname "TCO Service Plan" -StepResult "Skipped"
    }

    #Skype for Business Online
    $step = (Enable-UcmO365Service -upn $user.upn -ServiceName MCOSTANDARD)
    New-UcmReportStep -Stepname "SFBO Service Plan" -StepResult "$($Step.status) $($step.message)"

    #Calculate Statistics
    $elapsedTime = $(get-date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString("hh\:mm\:ss"))

  }
  New-UCMReportItem -LineTitle "Username" -LineMessage "Complete"
  Export-UcmHTMLReport
  Export-UcmCSVReport
}

If ($step -eq "Step2")
{
  #Check to see if we have the Skype4B Management Tools
  $Return = (Import-UcmCsOnPremTools)
  If ($Return.status -eq "Error")
  {
    Write-Warning "Step 2 must be performed from an On-prem server with the Skype4B tools installed "
    Return
  }

  #Setup Reporting and Progress Bars
  Initialize-UcmReport -Title "Step 2" -Subtitle "Old Policy Removal/User Migration to O365"
  
  $maxI = 250 
  $startTime = get-date 
  $usercount = ($users.count)
  $currentuser = 0
  
  #Process Each User
  Foreach ($username in $users) { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    Write-Progress -CurrentOperation "Init" -Activity "Step 2" -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)

    Write-UcmLog -message "User $usernametxt" -Severity 2
    [hashtable]$User = @{}


    #AD Check
    
    Write-Progress -CurrentOperation "Find User" -Activity "Step 2" -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)


    $userad = $null
    $UserAD = (Get-csaduser -Identity $usernametxt)
    $Csuser = (Get-csaduser -Identity $usernametxt|Get-csuser)


    If ($userad -eq $null) 

    {
      Write-UcmLog -message "Cant find on prem $usernametxt" -Severity 3
      Continue Userloop #exit foreach loop

    }

    $User.UPN = $usernametxt


    Write-Progress -CurrentOperation "Clear User Attributes" -Activity "Step 2" -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)


    #Clear Local attributes
    SkypeForBusiness\Set-CsUser -Identity $csuser.sipaddress -LineUri $null -EnterpriseVoiceEnabled $False 
    #SkypeForBusiness\Set-CsUser -Identity $csuser -LineUri $null -EnterpriseVoiceEnabled $False 
    #Move the user to O365
    IF ((Get-CsAduser $usernametxt).enabled -eq $null) {Write-Warning "User is not enabled on prem"}


    #Move user

    Write-Progress -CurrentOperation "Move user" -Activity "Step 2" -Status "User $currentuser of $usercount. $Usernametxt, ETA: $eta / @ $estimatedCompletionTime"  -PercentComplete ((($currentuser) / $usercount) * 100)

    #If (NotExist $foo) {
    #$foo = (get-Credential)
    Move-CsUser -Identity $csuser.sipaddress -Target sipfed.online.lync.com -MoveToTeams -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool tccsfbpoolnsw.steel.bhpsteel.net -BypassAudioConferencingCheck -Credential $foo #-UseOAuth
    #Move-CsMeetingRoom -Identity $user.upn -Target sipfed.online.lync.com -HostedMigrationOverrideUrl $url -Confirm:$false -ProxyPool sfbfeprd.agl.com.au -UseOAuth -Credential $foo



    #Statistics for time estimate
    $elapsedTime = $(get-date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString("hh\:mm\:ss"))
  }
  New-UCMReportItem -LineTitle "Username" -LineMessage "Complete"
  Export-UcmHTMLReport
  Export-UcmCSVReport
  
}

If ($step -eq "Step3")
{
  Initialize-UcmReport -Title "Step 3" -Subtitle "Policy and Number Assignment"
  $maxI = 250 
  $startTime = get-date 
  $usercount = ($users.count)
  $currentuser = 0
  Foreach ($username in $users) { 
    $currentuser ++
    $usernametxt = $Username.UserPrincipalName #Remove the CSV header
    New-UCMReportItem -LineTitle "Username" -LineMessage "$usernametxt"
    Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation start -PercentComplete ((($currentuser) / $usercount) * 100)
    Write-UcmLog -message "User: $usernametxt" -Severity 2
    
    [hashtable]$User = @{}

    $User.UPN = "$usernametxt"
  
    #figure out of the user has voice or not.
    $voice = $true
    if ($Username.lineuri.Length -le 2) 
    {
      Write-UcmLog -message "No phone number, Skipping Voice tasks" -Severity 2
      $voice = $false
    }
  
    #Microsoft Changed something that made us need the sip address instead of a UPN!
    #get the Sip Address off the user 
    Try 
    { 
      Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation SipAddress -PercentComplete ((($currentuser) / $usercount) * 100)
      $Sip = (get-csonlineuser $User.UPN).sipaddress
      New-UcmReportStep -Stepname "Locate Sip Address" -StepResult $sip.ToString()
      Write-UcmLog -message "Sip Address: Good" -Severity 2

  
  
      #Force to Teams only mode
      Try 
      { 
        Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation TeamsOnly -PercentComplete ((($currentuser) / $usercount) * 100)
        Grant-CsTeamsUpgradePolicy -PolicyName UpgradeToTeams -Identity $sip
        New-UcmReportStep -Stepname "Upgrade Policy" -StepResult "OK"
        Write-UcmLog -message "Upgrade Policy: Good" -Severity 2
      }
      Catch
      {
        New-UcmReportStep -Stepname "Upgrade Policy" -StepResult "Error, unknown error $($error[0])"
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
        Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation DialPlan -PercentComplete ((($currentuser) / $usercount) * 100)
        #Write-Host $Username.dialplan
        If ($Username.dialplan -eq "AUS-NSW-ACT-02") {
          #Write-Host "Granting AUS-NSW-ACT-02-EXT"
        $Dialplan = "AUS-NSW-ACT-02-EXT" }

        If ($Username.dialplan -eq "AUS-VIC-TAS-03") {
          #Write-Host "Granting AUS-VIC-TAS-03-EXT"
        $Dialplan = "AUS-VIC-TAS-03-EXT" }


        If ($Username.dialplan -eq "AUS-WA-SA-NT-08") {
          #Write-Host "Granting AUS-WA-SA-NT-08"
        $Dialplan =  "AUS-WA-SA-NT-08" }

        If ($Username.dialplan -eq "AUS-QLD-07") {
          # Write-Host "Granting AUS-QLD-07"
        $Dialplan = "AUS-QLD-07" }
     
        #Grant-CsTenantDialPlan -Identity $user.upn -PolicyName "VICTasDialplan-Unrestricted"
        Try 
        { 
          Grant-CsTenantDialPlan -Identity $sip -PolicyName $Dialplan -ErrorAction Stop
          New-UcmReportStep -Stepname "Dialplan" -StepResult "OK, $dialplan"
          Write-UcmLog -message "DialPlan: Good" -Severity 2
        }
        Catch
        {
          New-UcmReportStep -Stepname "DialPlan" -StepResult "Error, unknown error $($error[0])"
          Write-UcmLog -message "DialPlan: No Good! $($error[0])" -Severity 3
        }
      }
      Else
      {
        New-UcmReportStep -Stepname "DialPlan" -StepResult "OK: Not Voice Enabled"
      }
    
      if ($voice) 
      {
        Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation LineUri -PercentComplete ((($currentuser) / $usercount) * 100)
        $Username.lineuri = ($Username.lineuri -replace "tel:", "")
        #write-host "Assigning $($Username.lineuri)"
  
        Try 
        { 
          #Set-CsOnlineVoiceUser -Identity $sip -TelephoneNumber $Username.lineuri -ErrorAction Stop   ### 2.6.0 version
          Set-CsPhoneNumberAssignment -Identity $sip -PhoneNumber $Username.lineuri  -PhoneNumberType CallingPlan -ErrorAction Stop ##Todo Direct Routing Support
          New-UcmReportStep -Stepname "LineURI" -StepResult "OK, $($Username.lineuri)"
          Write-UcmLog -message "LineURI: Good" -Severity 2
        }
        Catch
        {
          #Error Handling for Numbers 
          
          #Number Exists in AD (error thrown by Old 2.6.0 Teams Module)
          If ($error[0] -like '*in Active Directory.')
          {
            Write-UcmLog -message 'Number Already Exists in AD.. finding user' -Severity 3
            #My dodgy RegEx to capture the GUID
            $ErrorUserGUID = ([regex]::Matches($Error[0],'\w{8}-\w{4}-\w{4}-\w{4}-\w{12}').value)
            $ErrorUser = Get-CsOnlineUser -Identity $ErrorUserGUID
            Write-UcmLog -message "$($ErrorUser.userprincipalname) is already using $($username.lineuri)" -Severity 3
            New-UcmReportStep -Stepname "LineURI" -StepResult "Error $($ErrorUser.userprincipalname) is already using $($username.lineuri) Remove the Number and perform an AADSync (if required) before trying again"       
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
            New-UcmReportStep -Stepname "LineURI" -StepResult "Error $($ErrorUser.userprincipalname) is already using $($username.lineuri) Remove the Number and perform an AADSync (if required) before trying again"       
            $error.Clear()

          }
          
          
          #Unhandled Number Error
          Else
          {
            New-UcmReportStep -Stepname "LineURI" -StepResult "Error, unknown error $($error[0])"
            Write-UcmLog -message "LineURI: No Good! $($error[0])" -Severity 3
          }
        }
   
      }
      Else
      {
        New-UcmReportStep -Stepname "LineURI" -StepResult "OK: Not Voice Enabled"
      }

      get-csonlineuser $user.upn | Format-List displayname,EnterpriseVoiceEnabled,OnPremLineUriManuallySet,OnPremLineUri,Telephonenumber,LineUri, tenantdialplan,  MCOValidationError, voicepolicy ,InterpretedUserType, TeamsUpgradeEffectiveMode
    }
    Catch
    {
      New-UcmReportStep -Stepname "Locate Sip Address" -StepResult "Error, unknown error $($error[0])"
      New-UcmReportStep -Stepname "Upgrade Policy" -StepResult "Skipped"
      New-UcmReportStep -Stepname "Dialplan" -StepResult "Skipped"
      New-UcmReportStep -Stepname "LineURI" -StepResult "Skipped"
      
      Write-UcmLog -message "Cant locate user, skipping. $($error[0])" -Severity 3

    }


    #Calculate Statistics
    $elapsedTime = $(get-date) - $startTime 

    #do the ratios and "the math" to compute the Estimated Time Of Completion 
    $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
    $estimatedTotalSecondsTS = New-TimeSpan -seconds $estimatedTotalSeconds
    $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
    #Give us a human readable time
    $eta = ($estimatedTotalSecondsTS.ToString("hh\:mm\:ss"))


  }
  New-UCMReportItem -LineTitle "Username" -LineMessage "Complete"
  $finished = (get-date -DisplayHint Time)
  Write-host "Finished at $finished"
  Export-UcmHTMLReport | out-null
  Export-UcmCSVReport | out-null
  

}
