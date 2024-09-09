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

$Secrets = @{
    FromEmail = "fromuser@gmail.com"
    ToEmail = "touser@hotmail.com"
    Credential = Get-Credential
}
$Secrets | Export-Clixml -Path ~\autocred.xml