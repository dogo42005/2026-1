# Instrucciones de instalación — PCs trabajadores (NodeODM)

Contexto completo del proyecto en `contexto_chat.md`.

---

## PC .81 (146.155.38.81) — Convertir WebODM a NodeODM

Ejecutar en PowerShell como administrador.

**Paso 1 — Bajar WebODM:**
```powershell
wsl -d Ubuntu -u root -- bash -c "cd ~/WebODM && ./webodm.sh down"
```

**Paso 2 — Instalar NodeODM:**
```powershell
wsl -d Ubuntu -u root -- bash -c "docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm"
```

**Paso 3 — Abrir firewall:**
```powershell
New-NetFirewallRule -DisplayName "NodeODM-3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

**Paso 4 — WSL-KeepAlive (evita que la VM de WSL2 se apague sola):**
```powershell
$accion = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$disparador1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$disparador2 = New-ScheduledTaskTrigger -AtStartup
$config = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-KeepAlive" -Action $accion -Trigger @($disparador1,$disparador2) -Settings $config -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName "WSL-KeepAlive"
```

**Paso 5 — Verificar NodeODM (esperar 15 segundos):**
```powershell
Start-Sleep 15
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```
Debe devolver `200`.

**Paso 6 — Si devuelve `000` (crash loop), aplicar fix de systemd:**
```powershell
wsl -d Ubuntu -u root -- bash -c "printf '[boot]\nsystemd=true\n' > /etc/wsl.conf"
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nnetworkingMode=mirrored`nvmIdleTimeout=-1`n" -Encoding UTF8
wsl --shutdown
Start-Sleep 15
wsl -d Ubuntu -u root -- bash -c "systemctl enable docker && systemctl start docker && sleep 5 && docker start nodeodm && sleep 10 && curl -s -o /dev/null -w '%{http_code}' http://localhost:3000"
```

**Paso 7 — Agregar en WebODM maestro (.80):**

Abrir `http://146.155.38.80:8000` → Nodos de procesamiento → Agregar nuevo:
- Nombre de host: `146.155.38.81`
- Puerto: `3000`
- Token: (vacío)
- Etiqueta: `PC-81`

---

## PC .82 (146.155.38.82) — Arreglar crash loop de NodeODM

NodeODM ya está instalado pero cae en loop a pesar de que systemd está activo.

**Paso 1 — Verificar estado actual:**
```powershell
wsl -d Ubuntu -u root -- docker logs nodeodm --tail 20
wsl -d Ubuntu -u root -- systemctl status docker --no-pager
```

**Paso 2 — Probar en modo test para aislar el problema:**
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm && docker rm nodeodm && docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm --test && sleep 15 && curl -s -o /dev/null -w '%{http_code}' http://localhost:3000"
```
- Si devuelve `200` en modo `--test` → el problema es ODM internamente, pero NodeODM responde y puede agregarse al maestro.
- Si devuelve `000` incluso en `--test` → hay otro problema.

**Paso 3 — Reconstruir contenedor limpio (si sigue fallando):**
```powershell
wsl -d Ubuntu -u root -- bash -c "docker stop nodeodm; docker rm nodeodm; docker pull opendronemap/nodeodm; docker run -d --name nodeodm --restart always -p 3000:3000 opendronemap/nodeodm"
Start-Sleep 20
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```

**Paso 4 — WSL-KeepAlive (igual que .81):**
```powershell
$accion = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- bash -c `"while true; do sleep 3600; done`""
$disparador1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$disparador2 = New-ScheduledTaskTrigger -AtStartup
$config = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RunOnlyIfNetworkAvailable:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "WSL-KeepAlive" -Action $accion -Trigger @($disparador1,$disparador2) -Settings $config -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName "WSL-KeepAlive"
```

**Paso 5 — Port proxy permanente (si mirrored no propaga el puerto):**

Verificar primero si hace falta:
```powershell
# Desde otro PC, probar: http://146.155.38.82:3000
# Si no responde, aplicar port proxy:
$wslIp = (wsl -d Ubuntu hostname -I).Trim().Split(' ')[0]
netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
```

Para hacerlo permanente (la IP de WSL2 cambia con cada reinicio):
```powershell
$cmd = '& { $ip = (wsl -d Ubuntu hostname -I).Trim().Split('' '')[0]; netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0; netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$ip }'
$a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -Command `"$cmd`""
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
Register-ScheduledTask -TaskName "NodeODM-PortProxy" -Action $a -Trigger $t -Settings (New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable:$false) -Principal $p -Force | Out-Null
```

**Paso 6 — Agregar en WebODM maestro (.80):**

Abrir `http://146.155.38.80:8000` → Nodos de procesamiento → Agregar nuevo:
- Nombre de host: `146.155.38.82`
- Puerto: `3000`
- Token: (vacío)
- Etiqueta: `PC-82`

---

## Diagnóstico rápido (cualquier PC worker)

```powershell
# Estado del contenedor
wsl -d Ubuntu -u root -- docker ps

# Logs de NodeODM
wsl -d Ubuntu -u root -- docker logs nodeodm --tail 20

# NodeODM responde desde dentro de WSL2
wsl -d Ubuntu -u root -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000

# Docker activo con systemd
wsl -d Ubuntu -u root -- systemctl status docker --no-pager

# Keep-alive de WSL2 sigue viva
Get-ScheduledTask -TaskName "WSL-KeepAlive" | Get-ScheduledTaskInfo

# Reiniciar NodeODM manualmente
wsl -d Ubuntu -u root -- bash -c "systemctl start docker && sleep 5 && docker start nodeodm"
```
