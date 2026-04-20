# Cargar variables del .env
if (Test-Path ".env") {
    Get-Content .env | Where-Object { $_ -match '=' -and $_ -notmatch '^#' } | ForEach-Object {
        $name, $value = $_.Split('=', 2)
        [System.Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), "Process")
    }
}

$LITELLM_PORT = [System.Environment]::GetEnvironmentVariable("LITELLM_PORT") -or "4000"
$env:ANTHROPIC_BASE_URL = "http://localhost:$LITELLM_PORT"
$env:ANTHROPIC_API_KEY = "sk-dummy-key"

Write-Host "🤖 Iniciando Claude Code apuntando a Ollama ($env:ANTHROPIC_BASE_URL)..." -ForegroundColor Cyan
Write-Host "------------------------------------------------"

# Ejecutar claude con todos los argumentos pasados al script
claude $args
