@echo off
cls
cd /Users/augusto/Dropbox/ENOTECA/IT/BCK/
set filename=ENODB_%date:~-10,2%%date:~-7,2%%date:~-4,4%
set day=%date:~-10,2%
echo %filename%

docker exec -i enodb-mysql-server mysqldump -uroot --single-transaction --databases enodb --skip-comments > %filename%.sql
set dumpresult=%ERRORLEVEL%

if not "%dumpresult%"=="0" (
    echo %DATE% %TIME% - ERRORE mysqldump, errorlevel %dumpresult% >> dump-db-errors.log
    if exist %filename%.sql del /F %filename%.sql
    goto :eof
)

for %%A in (%filename%.sql) do set dumpsize=%%~zA
if "%dumpsize%"=="0" (
    echo %DATE% %TIME% - ERRORE dump vuoto 0 byte >> dump-db-errors.log
    del /F %filename%.sql
    goto :eof
)

IF EXIST %filename%.zip DEL /F %filename%.zip
tar.exe -a -c -f %filename%.zip %filename%.sql
IF EXIST %filename%.sql (IF EXIST %filename%.zip DEL /F %filename%.sql)

REM copia a lungo termine il giorno 1 del mese, in una sottocartella dedicata (retention 365gg separata da quella dei giornalieri)
if "%day%"=="01" (
    if not exist archivio-mensile mkdir archivio-mensile
    copy /Y %filename%.zip archivio-mensile\%filename%.zip >nul
)

REM pulizia: giornalieri (solo cartella corrente, NON ricorsiva: non deve toccare archivio-mensile) tenuti 20 giorni
forfiles -p "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK" -m *.zip /d -20 -c "cmd /c del @path" 2>nul
REM eventuali .sql residui da run falliti in passato
forfiles -p "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK" -m *.sql /d -1 -c "cmd /c del @path" 2>nul
REM archivio mensile tenuto 365 giorni
if exist archivio-mensile forfiles -p "C:\Users\augusto\Dropbox\ENOTECA\IT\BCK\archivio-mensile" -m *.zip /d -365 -c "cmd /c del @path" 2>nul
