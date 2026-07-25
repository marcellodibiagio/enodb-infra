<#
Commit + push automatico della configurazione infrastrutturale enodb (repo enodb-infra).
Eseguito da Task Scheduler sul server: nessuna disciplina manuale richiesta,
qualunque modifica fatta durante la giornata in C:\mdb\enodb viene versionata
automaticamente la notte, se presente.
#>

$ErrorActionPreference = "Stop"

$repoPath = "C:\mdb\enodb"
$logPath  = "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK\git-snapshot-errors.log"

try {
    Set-Location $repoPath

    git add -A

    $status = git status --porcelain
    if ($status) {
        $msg = "snapshot automatico $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        git commit -m $msg | Out-Null
        git push | Out-Null
    }
}
catch {
    Add-Content $logPath "$(Get-Date) - ERRORE git-snapshot: $_"
}
