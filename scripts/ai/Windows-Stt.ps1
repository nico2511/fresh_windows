#Requires -Version 5.1
<#
  STT via API Windows (System.Speech) — alternative locale a CyberScribe.
  Phase 3 : push-to-talk depuis le menu agent.
#>

function Test-WindowsSpeechRecognitionAvailable {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $engines = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
        foreach ($e in $engines) {
            if ($e.Culture.Name -eq $culture.Name) { return $true }
        }
        if ($engines.Count -gt 0) { return $true }
    }
    catch { }
    return $false
}

function Get-WindowsSttStatusMessage {
    if (Test-WindowsSpeechRecognitionAvailable) {
        return 'Reconnaissance Windows disponible (fr-FR ou fallback EN).'
    }
    return 'Reconnaissance Windows indisponible sur cette machine (pack langue / parametres).'
}
