@echo off
setlocal

echo 📚 Modelos descargados en Ollama:
echo ------------------------------------------------

:: Intentar usar curl y formatear mínimamente con powershell para no depender de python en CMD
powershell -Command "$resp = Invoke-RestMethod http://localhost:11434/api/tags; if ($resp.models) { printf '   %-30s %-10s %-15s`n' 'NOMBRE' 'TAMAÑO' 'ID'; foreach ($m in $resp.models) { printf '   %-30s %7.2f GB   %s`n' $m.name ($m.size/1GB) $m.digest.Substring(7,12) } } else { '   (Ninguno)' }"

echo ------------------------------------------------
endlocal
