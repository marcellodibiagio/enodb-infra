<#
Backup della configurazione infrastrutturale enodb (Docker, cronjobs, task pianificati).
Eseguito da Task Scheduler sul server, deposita uno zip nella stessa cartella
Dropbox dei dump DB (C:\Users\augusto\Dropbox\ENOTECA\IT\BCK).

Copre: cartella C:\mdb\enodb (docker-compose, Dockerfile, conf, oracle installer,
cronjobs/ con tutti gli script pianificati incluso il tool ETL MS Access -> MySQL)
e i certificati SSL live (C:\mdb\enodb-volumes\ssl) - nulla di tutto questo ha
oggi altra copia offsite oltre a questo zip e al repo git enodb-infra.
#>

$ErrorActionPreference = "Stop"

$destDir = "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK"
$stamp   = Get-Date -Format "ddMMyyyy"
$workDir = Join-Path $env:TEMP "enodb-config-backup-$stamp"
$zipPath = Join-Path $destDir "ENODB-CONFIG_$stamp.zip"
$logPath = Join-Path $destDir "backup-config-errors.log"

try {
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -ItemType Directory -Path $workDir | Out-Null

    Copy-Item "C:\mdb\enodb" (Join-Path $workDir "enodb") -Recurse -Force

    if (Test-Path "C:\mdb\enodb-volumes\ssl") {
        Copy-Item "C:\mdb\enodb-volumes\ssl" (Join-Path $workDir "enodb-volumes-ssl") -Recurse -Force
    }

    $tasksDir = Join-Path $workDir "scheduled-tasks"
    New-Item -ItemType Directory -Path $tasksDir | Out-Null
    $taskNames = @(
        "dump-db-daily",
        "analisi venduto del giorno",
        "clienti da ms access a mysql",
        "backup-config",
        "git-snapshot"
    )
    foreach ($t in $taskNames) {
        try {
            Export-ScheduledTask -TaskName $t | Out-File (Join-Path $tasksDir "$t.xml") -Encoding unicode
        } catch {
            Add-Content $logPath "$(Get-Date) - impossibile esportare task '$t': $_"
        }
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $workDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

    Remove-Item $workDir -Recurse -Force

    # retention: 30 giorni di zip di config (piu leggero del DB, footprint minimo)
    Get-ChildItem $destDir -Filter "ENODB-CONFIG_*.zip" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
}
catch {
    Add-Content $logPath "$(Get-Date) - ERRORE backup-config: $_"
}
