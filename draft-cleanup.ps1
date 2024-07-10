
#File we are working with?
$File = "C:\Users\atrei\OneDrive - Telstra\Customers\AGL\Batches\01-07-22.csv"

#Folder containing migration batches?
$Folder = "C:\Users\atrei\OneDrive - Telstra\Customers\AGL\Batches"


##import files
cd $Folder
Try {$users = Import-CSV $File -ErrorAction Stop} 
Catch
{
  Write-Warning "Couldnt import CSV, Exiting"
  return
}


#Prepare environment
##TLS fix
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


  
#Setup Reporting and Progress Bars
Initialize-UcmReport -Title "Step 1" -Subtitle "Licence and Service Plan Validation/Assignment"
$maxI = 250 
$startTime = get-date 
$usercount = ($users.count)
$currentuser = 0
  
#Check we are connected to MSOL
$return = (Test-UcmMSOLConnection)
if ($return.status -eq "Error")
{
  Write-UcmLog -message "We arent connected to MSOL Service. Please run Connect-MsolService and try again" -Severity 3
  Return
}

#Process Each User
:Step1Loop Foreach ($username in $users) 
{ 
  $currentuser ++
  $usernametxt = $Username.UserPrincipalName #Remove the CSV header
  
  New-UCMReportItem -LineTitle "Username" -LineMessage "$usernametxt"
  Write-UcmLog -message "User $usernametxt" -Severity 2
  [hashtable]$User = @{}
  $User.UPN = "$usernametxt"
  
          #Enterprise Voice
        $step = (Revoke-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOEV')
        New-UcmReportStep -Stepname "EV Licence" -StepResult "$($Step.status) $($step.message)"
        
         #Telstra Calling
          $step = (Revoke-UcmOffice365UserLicence -upn $user.upn -LicenceType 'MCOPSTNEAU2')
          New-UcmReportStep -Stepname "TCO Licence" -StepResult "$($Step.status) $($step.message)"

  $step = (disable-UcmO365Service -upn $user.upn -ServiceName MCOPSTNEAU)
  New-UcmReportStep -Stepname "TCO Service Plan" -StepResult "$($Step.status) $($step.message)"

  #Teams Service Plan
  $step = (disable-UcmO365Service -upn $user.upn -ServiceName TEAMS1)
  New-UcmReportStep -Stepname "Teams Service Plan" -StepResult "$($Step.status) $($step.message)"

    
  #Skype for Business Online Service Plan (Required to Migrate User from OnPrem to Online
  $step = (disable-UcmO365Service -upn $user.upn -ServiceName MCOSTANDARD)
  New-UcmReportStep -Stepname "SFBO Service Plan" -StepResult "$($Step.status) $($step.message)"

  #Calculate Statistics
  $elapsedTime = $(get-date) - $startTime 

  #do the ratios and "the math" to compute the Estimated Time Of Completion 
  $estimatedTotalSeconds = $usercount / $currentuser * $elapsedTime.TotalSeconds 
  $estimatedTotalSecondsTS = New-TimeSpan -seconds $estimatedTotalSeconds
  $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
  #Give us a human readable time
  $eta = ($estimatedTotalSecondsTS.ToString("hh\:mm\:ss"))
  
  
  $Sip = (get-csonlineuser $User.UPN).sipaddress
      New-UcmReportStep -Stepname "Locate Sip Address" -StepResult $sip.ToString()
      Write-UcmLog -message "Sip Address: Good" -Severity 2

  
  
      #Force to Teams only mode
       
   
        Write-Progress -Activity "Step 3" -Status "User $currentuser of $usercount. $Usernametxt ETA: $eta / @ $estimatedCompletionTime" -CurrentOperation TeamsOnly -PercentComplete ((($currentuser) / $usercount) * 100)
        Grant-CsTeamsUpgradePolicy -PolicyName Islands -Identity $sip
        New-UcmReportStep -Stepname "Upgrade Policy" -StepResult "OK"
        Write-UcmLog -message "Upgrade Policy: Good" -Severity 2
}

New-UCMReportItem -LineTitle "Username" -LineMessage "Complete"
$finished = (get-date -DisplayHint Time)
Write-host "Finished at $finished"
Export-UcmHTMLReport | out-null
Export-UcmCSVReport | out-null
