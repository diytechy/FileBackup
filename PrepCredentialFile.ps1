#If using gmail, you must setup gmail to accept low security application smtp reqeusts:
#https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=&ved=2ahUKEwiemvzirciHAxXYhIkEHQO3AjcQFnoECBkQAQ&url=https%3A%2F%2Fknowledge.workspace.google.com%2Fkb%2Fhow-to-create-app-passwords-000009237&usg=AOvVaw0XTi4ejHyhkIASe-Pqircz&opi=89978449
$Secrets = @{
    FromEmail = "fromuser@gmail.com"
    ToEmail = "touser@hotmail.com"
    Credential = Get-Credential
}
$Secrets | Export-Clixml -Path ~\autocred.xml