@echo off
REM iniciar_webodm.bat
REM Inicia WebODM en el nodo remoto desde Git Bash
REM Ejecutar en el PC del servidor (146.155.38.81)

echo [>>] Iniciando WebODM...
echo      (La primera vez puede tardar 10-20 minutos mientras descarga las imagenes Docker)
echo.

REM Verificar que Docker este corriendo
docker info >nul 2>&1
if errorlevel 1 (
    echo [!] Docker no esta corriendo. Abre Docker Desktop primero y espera que este activo.
    pause
    exit /b 1
)

echo [OK] Docker esta activo.
echo.
echo [>>] Lanzando WebODM en puerto 8000...

REM Usar Git Bash para ejecutar webodm.sh
"C:\Program Files\Git\bin\bash.exe" -c "cd /c/WebODM/WebODM && ./webodm.sh start"

pause
