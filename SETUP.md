# Setup iniziale (una tantum) — enodb-infra

Passi da eseguire **in locale sul server** (PowerShell come amministratore, utente `augusto`): non sono automatizzabili da remoto perché richiedono accesso al Task Scheduler e a git della macchina, non solo alla cartella condivisa.

## 1. Verifica prerequisiti

```powershell
git --version   # se manca, installare Git for Windows
```

Se `git-snapshot.ps1` deve fare `push` senza interazione (gira da Task Scheduler, nessuna sessione interattiva vera), serve un credential helper configurato per l'account `augusto` con un Personal Access Token GitHub già salvato (es. Git Credential Manager, `git config --global credential.helper manager`). Verificare con:

```powershell
cd C:\mdb\enodb
git push   # deve funzionare senza chiedere credenziali interattivamente
```

## 2. Crea il repo GitHub `enodb-infra` (se non già fatto)

Su github.com, account `marcellodibiagio`: **New repository** → nome `enodb-infra` → **Private** → non inizializzare con README (il repo locale ha già i file). Poi:

```powershell
cd C:\mdb\enodb
git remote add origin https://github.com/marcellodibiagio/enodb-infra.git
git push -u origin master
```

## 3. Crea le due nuove attività pianificate

```powershell
$principal = New-ScheduledTaskPrincipal -UserId "augusto" -LogonType Interactive -RunLevel Least

# backup-config: dopo dump-db-daily (20:30), prima di git-snapshot
$actionCfg  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\mdb\enodb\backup-config.ps1"'
$triggerCfg = New-ScheduledTaskTrigger -Daily -At 20:45
Register-ScheduledTask -TaskName "backup-config" -Action $actionCfg -Trigger $triggerCfg -Principal $principal -Description "Backup config Docker/ETL/task pianificati verso Dropbox"

# git-snapshot: dopo backup-config
$actionGit  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\mdb\enodb\git-snapshot.ps1"'
$triggerGit = New-ScheduledTaskTrigger -Daily -At 21:00
Register-ScheduledTask -TaskName "git-snapshot" -Action $actionGit -Trigger $triggerGit -Principal $principal -Description "Commit+push automatico config enodb-infra"
```

## 4. (Opzionale, consigliato nei periodi di alto volume) secondo dump DB infragiornaliero

Costo trascurabile (il dump di questo DB impiega secondi), riduce la finestra di perdita dati potenziale. Può restare attivo tutto l'anno o essere abilitato solo Nov-Gen:

```powershell
$actionMid  = New-ScheduledTaskAction -Execute "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK\dump-db.bat"
$triggerMid = New-ScheduledTaskTrigger -Daily -At 13:00
Register-ScheduledTask -TaskName "dump-db-midday" -Action $actionMid -Trigger $triggerMid -Principal $principal -Description "Secondo dump DB infragiornaliero (periodi di picco)"
```

## 5. Verifica finale

- `Get-ScheduledTask | Where-Object TaskName -in @("backup-config","git-snapshot","dump-db-midday")` mostra le task come `Ready`.
- Esegui manualmente ciascuna task (`Start-ScheduledTask -TaskName "backup-config"`) e controlla che produca l'output atteso (zip in Dropbox, commit visibile su GitHub) prima di lasciarle allo scheduler.
- Dopo il primo `backup-config` riuscito, ri-esegui `backup-config.ps1` includendo anche i nomi delle nuove task nell'elenco `$taskNames` (già presente nello script) così l'export XML resta aggiornato.
