<#
.SYNOPSIS  Export results to JUnit XML for CI consumption.
#>
function Export-JUnitReport {
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Results,
        [Parameter(Mandatory)][string]$Path
    )

    $suites = $Results | Group-Object Suite, Group

    $xw = New-Object System.Xml.XmlTextWriter($Path, [System.Text.Encoding]::UTF8)
    $xw.Formatting = 'Indented'
    $xw.WriteStartDocument()
    $xw.WriteStartElement('testsuites')

    foreach ($s in $suites) {
        $cases = $s.Group
        $failures = @($cases | Where-Object Status -eq 'FAIL').Count
        $skipped  = @($cases | Where-Object Status -eq 'SKIP').Count
        $xw.WriteStartElement('testsuite')
        $xw.WriteAttributeString('name',     $s.Name)
        $xw.WriteAttributeString('tests',    $cases.Count)
        $xw.WriteAttributeString('failures', $failures)
        $xw.WriteAttributeString('skipped',  $skipped)
        foreach ($c in $cases) {
            $xw.WriteStartElement('testcase')
            $xw.WriteAttributeString('classname', "$($c.Suite).$($c.Group)")
            $xw.WriteAttributeString('name',      ("{0} {1}" -f $c.ScenarioId, $c.TestName))
            switch ($c.Status) {
                'FAIL' {
                    $xw.WriteStartElement('failure')
                    $xw.WriteAttributeString('message', $c.Detail)
                    $xw.WriteEndElement()
                }
                'SKIP' {
                    $xw.WriteStartElement('skipped')
                    if ($c.Detail) { $xw.WriteAttributeString('message', $c.Detail) }
                    $xw.WriteEndElement()
                }
            }
            $xw.WriteEndElement()
        }
        $xw.WriteEndElement()
    }

    $xw.WriteEndElement()
    $xw.WriteEndDocument()
    $xw.Flush()
    $xw.Close()
}
