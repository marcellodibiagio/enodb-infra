# Disaster Recovery — enodb

Procedura di emergenza per il gestionale enodb (negozio). Obiettivo: RTO ~8h (rientrare entro la giornata), RPO = ultimo backup notturno. Pensata per essere eseguita da Marcello da solo, anche sotto stress (es. durante le feste).

**Tieni una copia di questo file offline** (PDF stampato o salvato localmente, non solo su GitHub): se il guasto coinvolge anche rete/VPN, l'unica copia della procedura non deve dipendere dalla rete per essere consultata.

## Checklist pre-volo (verifica che tu abbia accesso a questo, PRIMA che serva)

- [ ] Credenziali VPN per raggiungere la rete del negozio da remoto
- [ ] Credenziali dell'account Windows `augusto` (usato per login sul PC/server e da cui dipendono le attività pianificate)
- [ ] Accesso all'account Dropbox che sincronizza `ENOTECA\IT\BCK` (dove vivono i dump DB e lo zip di config)
- [ ] Accesso al repo GitHub privato `enodb-infra` (config Docker, cronjobs, questo runbook)
- [ ] Accesso al repo GitHub `enodb-app` (frontend Vue)
- [ ] Contatto del fornitore delle stampanti fiscali (per assistenza su riconfigurazione/certificati se necessario)
- [ ] Password per `\\192.168.1.150\c$` (macchina del gestionale terzo, sorgente del DB MS Access `brainfat.mdb`): vive in `cronjobs\ms-access-to-mysql\credentials.local.txt`, escluso da git — recuperabile dall'ultimo `ENODB-CONFIG_*.zip` in Dropbox, che include anche i file esclusi da git

## Cosa serve per ricostruire tutto

| Cosa | Dove si trova |
|---|---|
| Config Docker (docker-compose.yml, Dockerfile, conf/, oracle/) | Repo `enodb-infra` su GitHub, oppure ultimo `ENODB-CONFIG_*.zip` in Dropbox `ENOTECA\IT\BCK` (contiene anche `.env` e i certificati SSL, esclusi dal repo) |
| Cronjobs (`dump-db.bat`, `analisi-venduto-del-giorno.bat`, tool ETL MS Access → MySQL) | Cartella `cronjobs/` dentro il repo `enodb-infra` (`C:\mdb\enodb\cronjobs`) — consolidati qui, non più sparsi tra Dropbox e `C:\mdb\MS Access to MySQL` |
| Dump del database MySQL | Ultimo `ENODB_*.zip` in Dropbox `ENOTECA\IT\BCK` |
| Frontend Vue (dist da buildare) | Repo `enodb-app` su GitHub |
| Backend PHP | Copia dev in `C:\Dropbox\_DEV\htdocs` (sincronizzata via Dropbox) — verifica se ci sono hotfix fatti solo in prod non riportati lì |
| Definizione delle 3+ attività pianificate | Ultimo `ENODB-CONFIG_*.zip` (cartella `scheduled-tasks`, file XML) — dopo l'import, aggiorna comunque l'Action di ciascuna task perché punti a `C:\mdb\enodb\cronjobs\...` |

## Scenario A — Guasto hardware totale del server

1. **Procurati una macchina Windows.** Va bene anche un PC d'ufficio già disponibile (il server attuale non è hardware dedicato) o un PC nuovo. Requisiti minimi: Windows 10/11, spazio disco sufficiente per Docker Desktop + volumi.
2. **Installa Docker Desktop** (con backend WSL2).
3. **Recupera la config**: clona il repo `enodb-infra` da GitHub in `C:\mdb\enodb` (o percorso equivalente), poi scompatta l'ultimo `ENODB-CONFIG_*.zip` da Dropbox sopra la stessa cartella per recuperare `.env`, i certificati SSL (`enodb-volumes-ssl`) e gli installer Oracle (`oracle/*.zip`, esclusi dal repo).
4. **Ricrea la struttura volumi**: assicurati che esista `C:\mdb\enodb-volumes\` con le sottocartelle `mysql\data` (vuota, la popolerà MySQL), `www` (dist frontend + PHP backend), `ssl` (certificati recuperati al punto 3), `log`.
5. **Deploya il codice applicativo**: build del frontend (`npm run build` da `enodb-app`) copiato in `enodb-volumes\www\vuenodb`; copia il backend PHP da `C:\Dropbox\_DEV\htdocs` in `enodb-volumes\www`.
6. **Avvia i container**: da `C:\mdb\enodb`, `docker compose up -d --build`.
7. **Ripristina il database**: scompatta l'ultimo `ENODB_*.zip` da Dropbox, poi:
   ```
   docker exec -i enodb-mysql-server mysql -uroot -p<password> enodb < ENODB_ggmmaaaa.sql
   ```
   (recupera la password da `.env`, chiave `MYSQL_ROOT_PASSWORD` — vedi nota di sicurezza sotto).
8. **Ricrea le 3+ attività pianificate**: importa gli XML da `scheduled-tasks/` (Task Scheduler → Importa attività), sotto l'account `augusto`, poi aggiorna l'Action di ciascuna perché punti a `C:\mdb\enodb\cronjobs\...` (vedi tabella sopra). Per `clienti da ms access a mysql` serve anche: reinstallare il software Bullzip "MS Access to MySQL" e ricreare `cronjobs\ms-access-to-mysql\credentials.local.txt` con la password (recuperabile dall'ultimo `ENODB-CONFIG_*.zip`, che include i file esclusi da git).
9. **Verifica** (non saltare questo passo, vedi sezione dedicata sotto).

## Scenario B — Ransomware / compromissione

1. **Isola subito la macchina dalla rete** (stacca il cavo di rete / disattiva il Wi-Fi). Non tentare di "ripulire" e riusare la stessa installazione.
2. **Non pagare, non ripristinare in place.** Procurati hardware pulito (vedi Scenario A) e ripristina da un backup precedente all'infezione, verificato manualmente (apri lo zip, controlla che il `.sql` non sia vuoto/corrotto e che la data abbia senso).
3. Segui gli step 2-9 dello Scenario A su hardware pulito.
4. **Dopo il ripristino, cambia tutte le credenziali**: password MySQL root (oggi `root` in chiaro — da cambiare comunque, vedi nota sotto), password dell'account Windows `augusto`, eventuali credenziali VPN se si sospetta compromissione.
5. Verifica se il piano Dropbox in uso offre "version history"/cestino esteso: può essere una rete di sicurezza aggiuntiva se anche i file su Dropbox risultano cifrati/modificati dal ransomware prima che la macchina venisse isolata.

## Verifica post-ripristino (da fare sempre, in entrambi gli scenari)

- [ ] `docker compose ps` mostra `enodb-web-server` e `enodb-mysql-server` in stato `Up`
- [ ] L'app è raggiungibile su `https://<IP-server>/vuenodb` e il login PIN funziona
- [ ] Le stampanti fiscali rispondono (prova un'operazione di Foglio Cassa)
- [ ] Le 3+ attività pianificate sono presenti in Task Scheduler **e risultano eseguite con successo almeno una volta** (non basta che siano importate — verifica lo storico esecuzioni)
- [ ] `dump-db-daily`, `backup-config`, `git-snapshot` producono un nuovo file la notte successiva al ripristino

## Nota di sicurezza

La password MySQL root **risulta di fatto vuota** (confermato dal tool ETL, che si connette con `destinationusername=root`, `destinationpassword=` vuota su `localhost:3306`): il `.env` dichiara `MYSQL_ROOT_PASSWORD=root`, ma quella variabile ha effetto solo alla primissima inizializzazione del DB — se il DB esisteva già prima di quell'impostazione, non ha mai avuto effetto reale. Da correggere appena possibile (non solo in emergenza): impostare davvero una password su root e aggiornare sia `.env` che l'utenza nel container che il tool ETL.

## Test periodico

Pianificare un test di ripristino completo (su un secondo PC o VM) almeno una volta l'anno, idealmente **prima delle feste natalizie** — per validare che questa procedura funzioni davvero e misurare il tempo reale impiegato contro l'RTO di 8h. Aggiornare questo file con l'esito e la data dell'ultimo test:

- Ultimo test eseguito: _(nessuno ancora — pianificare il primo)_

## Dipendenze esterne non coperte da questo runbook

- **Database MS Access sorgente** (`brainfat.mdb`): vive su un'altra macchina, `\\192.168.1.150\c$\brainfat\brainfat.mdb` (macchina del gestionale terzo "Brainfat", non gestita da Marcello). La responsabilità del suo backup non è ancora chiarita — verificare con il fornitore. Il tool ETL su questa macchina richiede accesso amministrativo a quella condivisione (vedi checklist pre-volo) e il software Bullzip "MS Access to MySQL" installato in `C:\Program Files (x86)\Bullzip\MS Access to MySQL\` — software di terze parti da reinstallare su una macchina nuova, non recuperabile da backup file.
- **Script `analisi-venduto-del-giorno.bat`**: verificato — fa solo `curl http://192.168.1.31/_analisivendutodelgiorno`, nessuna dipendenza locale oltre all'app enodb stessa (già coperta dal ripristino). Vive in Dropbox (`ENOTECA\IT\crontab`), già con copia offsite. Nessuna azione necessaria.
