@echo off
setlocal enabledelayedexpansion

:: Cargar variables del .env
if exist .env (
    for /f "usebackq tokens=1* delims==" %%a in (`findstr /v "^#" .env`) do (
        set %%a=%%b
    )
)

echo 📊 Estado de los modelos en Ollama:
echo ------------------------------------------------

:: Usar powershell para procesar el JSON de la API ps
powershell -Command "$resp = Invoke-RestMethod http://localhost:11434/api/ps; $found = $false; foreach ($m in $resp.models) { if ($m.name -like '*%OLLAMA_MODEL%*') { Write-Host '✅ Modelo %OLLAMA_MODEL% está CARGADO en memoria.'; Write-Host ('   - Tamaño total: {0:N2} GB' -f ($m.size/1GB)); Write-Host ('   - En VRAM: {0:N2} GB' -f ($m.size_vram/1GB)); Write-Host ('   - Expiración: ' + $m.expires_at); $found = $true } }; if (-not $found) { Write-Host '⏳ Modelo %OLLAMA_MODEL% NO está cargado (o está cargando...)' }"

echo ------------------------------------------------
endlocal
