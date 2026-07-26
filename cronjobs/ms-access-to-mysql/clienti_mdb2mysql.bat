net use z: /delete /N

REM Password letta da file locale non versionato (mai in chiaro nello script, mai in git).
REM Se manca su una macchina nuova: recuperala dall'ultimo ENODB-CONFIG_*.zip in Dropbox
REM (il backup zippa l'intera cartella enodb, file ignorati da git inclusi), oppure richiedila
REM al fornitore del gestionale terzo. Contenuto atteso: una riga con solo la password.
set /p ACCESS150_PWD=<"C:\mdb\enodb\cronjobs\ms-access-to-mysql\credentials.local.txt"

net use z: \\192.168.1.150\c$ %ACCESS150_PWD% /user:administrator
cd "C:\Program Files (x86)\Bullzip\MS Access to MySQL\"
msa2mys settings="C:\mdb\enodb\cronjobs\ms-access-to-mysql\msaccess2mysqlsettings2.ini" AUTORUN, HIDE
net use z: /delete /N
