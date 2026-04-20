# Cargar variables del .env
if (Test-Path ".env") {
    Get-Content .env | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
        $name, $value = $_.Split('=', 2)
        [System.Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
    }
}

Write-Host "🚀 Reiniciando infraestructura de IA Local (Ollama + LiteLLM)..." -ForegroundColor Cyan
docker compose --env-file .env -f docker/docker-compose.yml down
docker compose --env-file .env -f docker/docker-compose.yml up -d --force-recreate

$LITELLM_PORT = [System.Environment]::GetEnvironmentVariable("LITELLM_PORT") -or "4000"
$OLLAMA_PORT = [System.Environment]::GetEnvironmentVariable("OLLAMA_PORT") -or "11434"

Write-Host "------------------------------------------------"
Write-Host "📡 LiteLLM Proxy: http://localhost:$LITELLM_PORT"
Write-Host "🦙 Ollama API: http://localhost:$OLLAMA_PORT"
Write-Host "------------------------------------------------"
Write-Host "✅ Servidores relanzados en segundo plano." -ForegroundColor Green
Write-Host "💡 Usa .\ollama-list-downloaded-models.ps1 para ver el progreso de carga."
