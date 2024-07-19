#Migrate-SkypeUsersToTeams Config file. See Migrate-SkypeUsersToTeamsWorker.ps1 for full instructions and changelog.
#This is just the config, Migrate-SkypeUsersToTeamsWorker.ps1 must be present in the same folder for this script to function

##Configuration Section##

###Per Run Settings###

#Step to run (Step1, Step2, Step3 currently supported)
$Step = "Step1" 

#File we are working with?
$File = "C:\Users\atrei\OneDrive - Telstra\Customers\Programmed\Batches\25-07-24a.csv"

#User Type that we are migrating (Users or MeetingRooms currently supported)
$UserType = "Users"


###Per Customer Settings###

#Folder containing migration batches?
$Folder = "C:\Kloud\Batches"

#Mode (DirectRouting or TCO (Operator Connect and Calling Plans in the future))
$Mode = "MSOC"

#Hosted Migration URL
$url="https://adminau1.online.lync.com/HostedMigration/hostedmigrationService.svc"

#FrontEnd server (Step 2 only)
$frontEnd = "sfb-fe-au-east.programmed.com.au"

#Step2 Authentcation Method (OAuth or Credentials)
$AuthMethod = "prompt"

#UcmPSTools Location 
$UcmPsTools = "C:\Kloud\PowerShell-Functions\Test-ImportFunctions.ps1"

#Skip Assignment of Licences / Service Plan(Step 1 only)?
$ReportOnly = $true

#How much debug info do you want? (SilentlyContinue = not much, Continue = Boatload )
$VerbosePreference = "SilentlyContinue"


####### You shouldnt need to edit under this line unless you know what you are doing #######

#Now call the main script

Invoke-Expression ($PSCommandPath -replace 'Migrate-SkypeUsersToTeams-programmed.ps1','Migrate-SkypeUsersToTeamsWorker.ps1')

#Clear the variables in memory so the direct run check fails.
Remove-Variable url, step, file, usertype, folder, mode, frontend, authmethod, UcmPsTools

