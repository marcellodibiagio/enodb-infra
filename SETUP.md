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

Se compare `fatal: detected dubious ownership in repository` (capita perché il repo è stato inizializzato da un altro account Windows, es. `marcello` invece di `augusto`, o durante un ripristino da disastro su una macchina nuova), è normale: basta aggiungere l'eccezione con l'account che effettivamente esegue git-snapshot.ps1 (`augusto`):

```powershell
git config --global --add safe.directory C:/mdb/enodb
```

## 2. Crea il repo GitHub `enodb-infra` (se non già fatto)

Su github.com, account `marcellodibiagio`: **New repository** → nome `enodb-infra` → **Private** → non inizializzare con README (il repo locale ha già i file). Poi:

```powershell
cd C:\mdb\enodb
git remote add origin https://github.com/marcellodibiagio/enodb-infra.git
git push -u origin master
```

## 3. Aggiorna le 3 attività pianificate esistenti (consolidamento in `cronjobs/`)

Gli script `dump-db.bat`, `analisi-venduto-del-giorno.bat` e `clienti_mdb2mysql.bat` sono stati spostati dentro `C:\mdb\enodb\cronjobs\` (versionati in git, invece che sparsi tra Dropbox e `C:\mdb\MS Access to MySQL`). Le vecchie copie sono state rimosse: aggiorna il percorso nell'Action delle 3 task esistenti, altrimenti puntano a file che non esistono più.

```powershell
Set-ScheduledTask -TaskName "dump-db-daily" -Action (New-ScheduledTaskAction -Execute "C:\mdb\enodb\cronjobs\dump-db.bat")
Set-ScheduledTask -TaskName "analisi venduto del giorno" -Action (New-ScheduledTaskAction -Execute "C:\mdb\enodb\cronjobs\analisi-venduto-del-giorno.bat")
Set-ScheduledTask -TaskName "clienti da ms access a mysql" -Action (New-ScheduledTaskAction -Execute "C:\mdb\enodb\cronjobs\ms-access-to-mysql\clienti_mdb2mysql.bat")
```

**Prerequisito per `clienti da ms access a mysql`**: il `.bat` non contiene più la password in chiaro per l'accesso a `\\192.168.1.150\c$` (era hardcoded prima di essere versionato su git). **Non usiamo `cmdkey`** (renderebbe `\\192.168.1.150\c$` raggiungibile senza password da qualunque processo giri come `augusto` su questa macchina, malware incluso — rischio di movimento laterale). La password vive invece in un file locale non versionato:

```
C:\mdb\enodb\cronjobs\ms-access-to-mysql\credentials.local.txt
```
(una riga con solo la password, escluso da git via `.gitignore`). Su questa macchina esiste già. Su una macchina ricostruita da zero, recuperalo dall'ultimo `ENODB-CONFIG_*.zip` in Dropbox (lo zippa per intero, file esclusi da git compresi) — vedi `DISASTER-RECOVERY.md`.

**Nota per il futuro**: la vera correzione non è "dove sta la password" ma il fatto che questa credenziale è un account amministratore locale su `.150` con accesso a tutto il disco (`C$`), quando probabilmente serve solo leggere una cartella. Da valutare con chi gestisce `.150`: un utente dedicato a permessi minimi e una condivisione scoped solo su `brainfat\` invece di `C$`.

Verifica poi con un run manuale (`Start-ScheduledTask -TaskName "clienti da ms access a mysql"`) che il collegamento a `\\192.168.1.150\c$` funzioni ancora.

## 4. Crea le due nuove attività pianificate

```powershell
$principal = New-ScheduledTaskPrincipal -UserId "augusto" -LogonType Interactive -RunLevel Limited

# backup-config: dopo dump-db-daily (20:30), prima di git-snapshot
$actionCfg  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\mdb\enodb\cronjobs\backup-config.ps1"'
$triggerCfg = New-ScheduledTaskTrigger -Daily -At 20:45
Register-ScheduledTask -TaskName "backup-config" -Action $actionCfg -Trigger $triggerCfg -Principal $principal -Description "Backup config Docker/ETL/task pianificati verso Dropbox"

# git-snapshot: dopo backup-config
$actionGit  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\mdb\enodb\cronjobs\git-snapshot.ps1"'
$triggerGit = New-ScheduledTaskTrigger -Daily -At 21:00
Register-ScheduledTask -TaskName "git-snapshot" -Action $actionGit -Trigger $triggerGit -Principal $principal -Description "Commit+push automatico config enodb-infra"
```

## 5. (Opzionale, consigliato nei periodi di alto volume) secondo dump DB infragiornaliero

Costo trascurabile (il dump di questo DB impiega secondi), riduce la finestra di perdita dati potenziale. Può restare attivo tutto l'anno o essere abilitato solo Nov-Gen:

```powershell
$actionMid  = New-ScheduledTaskAction -Execute "C:\mdb\enodb\cronjobs\dump-db.bat"
$triggerMid = New-ScheduledTaskTrigger -Daily -At 13:00
Register-ScheduledTask -TaskName "dump-db-midday" -Action $actionMid -Trigger $triggerMid -Principal $principal -Description "Secondo dump DB infragiornaliero (periodi di picco)"
```

## 6. Verifica finale

- `Get-ScheduledTask | Where-Object TaskName -in @("backup-config","git-snapshot","dump-db-midday")` mostra le task come `Ready`.
- Esegui manualmente ciascuna task (`Start-ScheduledTask -TaskName "backup-config"`) e controlla che produca l'output atteso (zip in Dropbox, commit visibile su GitHub) prima di lasciarle allo scheduler.
- Dopo il primo `backup-config` riuscito, ri-esegui `backup-config.ps1` includendo anche i nomi delle nuove task nell'elenco `$taskNames` (già presente nello script) così l'export XML resta aggiornato.
