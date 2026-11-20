@echo off
setlocal EnableExtensions

rem ===========================================================================
rem  Doctum RPA - Iniciador para Windows (.bat)
rem
rem  Uso:
rem    iniciar-doctum-rpa.bat              desenvolvimento: backend (5678) + Vite (8080)
rem    iniciar-doctum-rpa.bat --producao   producao: somente backend (5678)
rem    iniciar-doctum-rpa.bat --parar      para os servidores
rem    iniciar-doctum-rpa.bat --status     mostra o estado dos servidores
rem    iniciar-doctum-rpa.bat --help       mostra esta ajuda
rem
rem  O projeto e localizado automaticamente (ou defina DOCTUM_RPA_DIR).
rem  Uma unidade virtual Z: e criada para evitar problemas com acentos/esacos
rem  no caminho do projeto.
rem ===========================================================================

set "PORT_BACKEND=5678"
set "PORT_FRONTEND=8080"
set "MODE=dev"
set "SCRIPT_DIR=%~dp0"

rem ---------------------------------------------------------------- argumentos
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--producao" goto arg_prod
if /i "%~1"=="--production" goto arg_prod
if /i "%~1"=="-p" goto arg_prod
if /i "%~1"=="--dev" goto arg_dev
if /i "%~1"=="-d" goto arg_dev
if /i "%~1"=="--parar" goto arg_stop
if /i "%~1"=="--stop" goto arg_stop
if /i "%~1"=="--status" goto arg_status
if /i "%~1"=="--help" goto usage
if /i "%~1"=="-h" goto usage
echo [ERRO] Opcao desconhecida: %~1
goto usage

:arg_prod
set "MODE=prod"
shift
goto parse_args

:arg_dev
set "MODE=dev"
shift
goto parse_args

:arg_stop
set "MODE=stop"
shift
goto parse_args

:arg_status
set "MODE=status"
shift
goto parse_args

:args_done
if /i "%MODE%"=="stop" goto do_stop
if /i "%MODE%"=="status" goto do_status
goto do_start

rem -------------------------------------------------------------------- ajuda
:usage
echo Doctum RPA - Iniciador ^(Windows^)
echo.
echo Uso:
echo   iniciar-doctum-rpa.bat                 Inicia backend ^(5678^) + Vite ^(8080^)
echo   iniciar-doctum-rpa.bat --producao      Inicia somente o backend ^(5678^)
echo   iniciar-doctum-rpa.bat --parar         Para os servidores
echo   iniciar-doctum-rpa.bat --status        Mostra o estado dos servidores
echo   iniciar-doctum-rpa.bat --help          Mostra esta ajuda
echo.
echo Variavel opcional:
echo   DOCTUM_RPA_DIR=C:\caminho\do\projeto   Forca a pasta do projeto
exit /b 0

rem ------------------------------------------------------------------- status
:do_status
echo === Doctum RPA - status ===
call :port_open %PORT_BACKEND%
if "%PORT_OPEN%"=="1" (echo [ATIVO ] backend  :%PORT_BACKEND%) else (echo [PARADO] backend  :%PORT_BACKEND%)
call :port_open %PORT_FRONTEND%
if "%PORT_OPEN%"=="1" (echo [ATIVO ] frontend :%PORT_FRONTEND%) else (echo [PARADO] frontend :%PORT_FRONTEND%)
exit /b 0

rem -------------------------------------------------------------------- parar
:do_stop
echo [...] Parando servidores do Doctum RPA...
for %%P in (%PORT_FRONTEND% %PORT_BACKEND%) do (
  for /f "tokens=5" %%I in ('netstat -ano -p tcp ^| findstr /C:":%%P " ^| findstr /I "LISTENING"') do (
    echo [OK] Parando PID %%I ^(porta %%P^)...
    taskkill /PID %%I /T /F >nul 2>&1
  )
)
echo [OK] Pronto.
exit /b 0

rem ------------------------------------------------------------------ iniciar
:do_start
echo ================================================
if /i "%MODE%"=="prod" goto banner_prod
echo   Doctum RPA - DESENVOLVIMENTO ^(backend + Vite^)
echo   Acesso: http://localhost:%PORT_FRONTEND%
goto banner_done
:banner_prod
echo   Doctum RPA - PRODUCAO ^(sem Vite^)
echo   Acesso: http://localhost:%PORT_BACKEND%
:banner_done
echo ================================================

call :find_project
if not defined PROJ goto no_project
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"
echo [OK] Projeto: %PROJ%

call :ensure_drive
echo [OK] Raiz de execucao: %ROOT%

where node >nul 2>&1
if errorlevel 1 goto no_node

if /i "%MODE%"=="prod" goto prod_check
goto start_backend

:prod_check
if not exist "%ROOT%packages\frontend\editor-ui\dist\index.html" goto no_dist

:start_backend
call :port_open %PORT_BACKEND%
if "%PORT_OPEN%"=="1" goto backend_ok
echo [...] Iniciando backend n8n ^(porta %PORT_BACKEND%^)...
start "Doctum RPA - Backend %PORT_BACKEND%" /d "%ROOT%packages\cli" cmd /k node bin\n8n start
:backend_ok
if "%PORT_OPEN%"=="1" echo [OK] Backend ^(%PORT_BACKEND%^) ja esta rodando.

if /i "%MODE%"=="prod" goto wait_backend
goto start_frontend

:start_frontend
call :port_open %PORT_FRONTEND%
if "%PORT_OPEN%"=="1" goto frontend_ok
echo [...] Iniciando frontend Vite ^(porta %PORT_FRONTEND%^)...
start "Doctum RPA - Frontend %PORT_FRONTEND%" /d "%ROOT%packages\frontend\editor-ui" cmd /k node node_modules\vite\bin\vite.js dev --port %PORT_FRONTEND%
:frontend_ok
if "%PORT_OPEN%"=="1" echo [OK] Frontend ^(%PORT_FRONTEND%^) ja esta rodando.

:wait_backend
echo [...] Aguardando http://localhost:%PORT_BACKEND% responder 200 ^(ate 5 min^)...
call :wait_http "http://localhost:%PORT_BACKEND%/" 300
if errorlevel 1 goto backend_fail
echo [OK] Backend no ar! ^(http://localhost:%PORT_BACKEND%^)

if /i "%MODE%"=="prod" goto open_browser

:wait_frontend
echo [...] Aguardando http://localhost:%PORT_FRONTEND% responder 200 ^(ate 3 min^)...
call :wait_http "http://localhost:%PORT_FRONTEND%/" 180
if errorlevel 1 goto frontend_fail
echo [OK] Frontend no ar! ^(http://localhost:%PORT_FRONTEND%^)

:open_browser
if /i "%MODE%"=="prod" goto open_prod
start "" "http://localhost:%PORT_FRONTEND%"
echo [OK] Navegador aberto em http://localhost:%PORT_FRONTEND%
goto end_ok
:open_prod
start "" "http://localhost:%PORT_BACKEND%"
echo [OK] Navegador aberto em http://localhost:%PORT_BACKEND%

:end_ok
echo.
echo Servidores rodando em janelas proprias.
echo   Parar : iniciar-doctum-rpa.bat --parar
echo   Status: iniciar-doctum-rpa.bat --status
exit /b 0

rem ------------------------------------------------------------------ erros
:no_project
echo [ERRO] Pasta do projeto nao encontrada.
echo        Defina DOCTUM_RPA_DIR=C:\caminho\do_projeto e tente de novo.
exit /b 1

:no_node
echo [ERRO] Node.js nao encontrado no PATH. Instale Node.js 24+.
exit /b 1

:no_dist
echo [ERRO] Interface nao compilada ^(dist ausente^).
echo        Compile uma vez: cd /d "%ROOT%packages\frontend\editor-ui" ^&^& pnpm run build
exit /b 3

:backend_fail
echo [ERRO] Backend nao respondeu HTTP 200 em 5 minutos.
echo        Verifique a janela "Doctum RPA - Backend %PORT_BACKEND%".
exit /b 2

:frontend_fail
echo [ERRO] Frontend nao respondeu HTTP 200 em 3 minutos.
echo        Verifique a janela "Doctum RPA - Frontend %PORT_FRONTEND%".
exit /b 2

rem --------------------------------------------------------------- rotinas
:port_open
rem %1 = porta; define PORT_OPEN=1 se houver listener
set "PORT_OPEN=0"
netstat -ano -p tcp | findstr /C:":%~1 " | findstr /I "LISTENING" >nul 2>&1
if not errorlevel 1 set "PORT_OPEN=1"
exit /b 0

:wait_http
rem %1 = url, %2 = timeout em segundos; retorna 0 se HTTP 200
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%~1'; $t=%~2; $s=0; while($s -lt $t){ try { $r=Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 5; if([int]$r.StatusCode -eq 200){ exit 0 } } catch {}; Start-Sleep -Seconds 3; $s+=3; if(($s %% 30) -eq 0){ Write-Host ('  ... ' + $s + 's') } }; exit 1"
set "RC=%errorlevel%"
exit /b %RC%

:find_project
set "PROJ="
if defined DOCTUM_RPA_DIR if exist "%DOCTUM_RPA_DIR%\packages\cli\bin\n8n" set "PROJ=%DOCTUM_RPA_DIR%"
if defined PROJ goto :eof
if exist "%SCRIPT_DIR%packages\cli\bin\n8n" set "PROJ=%SCRIPT_DIR%"
if defined PROJ goto :eof
if exist "%SCRIPT_DIR%n8n-master\packages\cli\bin\n8n" set "PROJ=%SCRIPT_DIR%n8n-master"
if defined PROJ goto :eof
for /d %%D in ("%USERPROFILE%\Documents\Projeto*") do (
  if exist "%%~fD\packages\cli\bin\n8n" set "PROJ=%%~fD"
  if exist "%%~fD\n8n-master\packages\cli\bin\n8n" set "PROJ=%%~fD\n8n-master"
)
if defined PROJ goto :eof
for %%P in ("%USERPROFILE%\doctum-rpa" "%USERPROFILE%\Desktop\doctum-rpa" "%USERPROFILE%\Documents\doctum-rpa" "%USERPROFILE%\n8n-master" "%USERPROFILE%\Documents\n8n-master") do (
  if exist "%%~fP\packages\cli\bin\n8n" set "PROJ=%%~fP"
)
goto :eof

:ensure_drive
set "ROOT="
if exist "Z:\package.json" set "ROOT=Z:\"
if defined ROOT goto :eof
subst Z: /d >nul 2>&1
subst Z: "%PROJ%" >nul 2>&1
if exist "Z:\package.json" (set "ROOT=Z:\") else (set "ROOT=%PROJ%\")
goto :eof
