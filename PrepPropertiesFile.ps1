#If using gmail, you must setup gmail to accept low security application smtp reqeusts.
#This will only work if 2FA is turned on!
#As of the time of this writing:
#1. Go to your Google Account.
#2. On the left navigation panel, choose Security.
#3. On the 'How you sign in to Google' panel, choose '2-Step Verification'
#4. At the bottom, hit the jump link to view all App passwords.
#5. Create a new app password.
#Choose Generate.
#https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&ved=2ahUKEwiemvzirciHAxXYhIkEHQO3AjcQFnoECBkQAQ&url=https%3A%2F%2Fknowledge.workspace.google.com%2Fkb%2Fhow-to-create-app-passwords-000009237&usg=AOvVaw0XTi4ejHyhkIASe-Pqircz&opi=89978449

$PriVolLbl = "Library"
$BkpVolLbl = "PriBackup"
$BkpVolLbl2 = "LPBackup"
$ErrPathStr = "A:\FileBackupLastError.txt"

#Warning: changing the path below will require the main FileBackup script to also be updated to look for it in the same location.
$PropsInfoPath = "~\FileBackupProps.xml"

#Customize these structure element values below per your configuration.
$Secrets = @{
	FromEmail = "fromuser@gmail.com"
	ToEmail = "touser@hotmail.com"
	Credential = Get-Credential
}
$BkpSets = @( @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "~\SharedFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl;
RepFldrLbl = "BackedUpReports";
ChkFldrLbl = "Shared";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
}, @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "~\PrivateFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl;
RepFldrLbl = "BackedUpReports";
ChkFldrLbl = "Private";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
}, @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "~\NonDocsFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl;
RepFldrLbl = "NonDocReports";
ChkFldrLbl = "NonDocs";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
})

if (-not (Test-Path -Path $PropsInfoPath -PathType Leaf)) {
	#Note, the from / to elements here are overwritten by the user definition above.
	$SecretPrep = @{
		FromEmail = "fromuser@gmail.com"
		ToEmail = "touser@hotmail.com"
		Credential = Get-Credential
	}
} else {
	Write-Host "Properties file already detected, importing encrypted authentication definition."
	Write-Host "If you would like to redefine the authentication definition, please delete " + $PropsInfoPath +" and rerun this script."
	$ImportProps = Import-Clixml -Path $PropsInfoPath
	$SecretPrep   = $ImportProps.Secrets
}
#Overwrite with the latest user definition.
$SecretPrep.FromEmail = Secrets.FromEmail;
$SecretPrep.ToEmail   = Secrets.ToEmail;

$AllProps = @{
	ErrPath = $ErrPathStr;
	Secrets = $SecretPrep;
	BkpSets = $BkpSets;
}
$AllProps | Export-Clixml -Path $PropsInfoPath -Force