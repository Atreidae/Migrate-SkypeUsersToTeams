. C:\UcMadScientist\PowerShell-Functions\Test-ImportFunctions.ps1
$rgsWorkflows = (import-csv .\25-7-rgs.csv)
$upnsuffix = "@intgroup.onmicrosoft.com"

#create the accounts
Foreach ($rgsworkflow in $rgsWorkflows)
{
    $aaupn = $rgsworkflow.AAAccount + $upnsuffix
    $cqupn = $rgsworkflow.CQAccount + $upnsuffix
    $AADisplayName = $rgsworkflow.AADisplayName
    $CQDisplayName = $rgsworkflow.CQDisplayName


    <# Slow way of doing it, great when I have to have other actions occur after the account is created

    #check for CQ Resource Account
    Try
    {
        $CQAccount = (get-csonlineapplicationinstance -Identity $CQupn -ErrorAction Stop)
        Write-UcmLog -Message "Found Existing Resource Account, skipping creation" -Severity 2 -Component $function
        Write-UcmLog -Message $AAAccount -Severity 2 -Component $function
    }

    #we didnt find the account, make it
    Catch
    {
        Write-UcmLog -Message "Creating Required Resource Account" -Severity 2 -Component $function
        $CQAccounttemp = (New-UcmTeamsResourceAccount -upn $CQupn -ResourceType CallQueue -displayname $AADisplayName)
        Write-UcmLog -Message "waiting for account to appear in AzureAD" -Severity 2 -Component $function

        #start checking for the account
        For ($i = 0; $i -lt 7)
        {
            #Check we havent been waiting too long
            if ($i -gt 5)
            {
                Write-UcmLog -Message "Account has not appeared after 60 seconds!" -Severity 3 -Component $function
                Write-UcmLog -Message "Aborting account $CQDisplayName" -Severity 3 -Component $function
                Return
            }

            Write-UcmLog -Message "Waiting 10 seconds" -Severity 2 -Component $function
            Start-sleep -seconds 10
            Try
            {
                $CQAccount = (get-csonlineapplicationinstance -Identity $CQupn -ErrorAction stop)
                Write-UcmLog -Message "Account found" -Severity 2 -Component $function
                $i = 7
            }
            Catch
            {
                Write-UcmLog -Message "Account not found, trying again" -Severity 2 -Component $function
                $i ++
            }
        }
    }






	#Check for AA Resource Account
		#Powershell throws an error if the account isnt found, so lets trap it and use that instead

		Try
		{
			$AAAccount = (get-csonlineapplicationinstance -Identity $aaupn -ErrorAction Stop)
			Write-UcmLog -Message "Found Existing Resource Account, skipping creation" -Severity 2 -Component $function
			Write-UcmLog -Message $AAAccount -Severity 2 -Component $function
		}

		#we didnt find the account, make it
		Catch
		{
			Write-UcmLog -Message "Creating Required Resource Account" -Severity 2 -Component $function
			$AAAccounttemp = (New-UcmTeamsResourceAccount -upn $aaupn -ResourceType Autoattendant -displayname $AADisplayName)
			Write-UcmLog -Message "waiting for account to appear in AzureAD" -Severity 2 -Component $function

			#start checking for the account
			For ($i = 0; $i -lt 7)
			{
				#Check we havent been waiting too long
				if ($i -gt 5)
				{
					Write-UcmLog -Message "Account has not appeared after 60 seconds!" -Severity 3 -Component $function
					Write-UcmLog -Message "Aborting account $AADisplayName" -Severity 3 -Component $function
					Return
				}

				Write-UcmLog -Message "Waiting 10 seconds" -Severity 2 -Component $function
				Start-sleep -seconds 10
				Try
				{
					$AAAccount = (get-csonlineapplicationinstance -Identity $aaupn -ErrorAction stop)
					Write-UcmLog -Message "Account found" -Severity 2 -Component $function
					$i = 7
				}
				Catch
				{
					Write-UcmLog -Message "Account not found, trying again" -Severity 2 -Component $function
					$i ++
				}
			}
		}
 #>

    New-UcmTeamsResourceAccount -UPN $aaupn -DisplayName $rgsworkflow.aadisplayname -ResourceType AutoAttendant
    New-UcmTeamsResourceAccount -UPN $cqupn -DisplayName $rgsworkflow.cqdisplayname -ResourceType CallQueue
}