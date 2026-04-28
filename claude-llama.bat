@echo off
setlocal enabledelayedexpansion

echo.
echo # CLAUDE CODE LOCAL
echo --------------------------------------------

:: --- Configuration Loading ---
if exist .env for /f "usebackq tokens=1* delims==" %%a in (`findstr /v /b "#" .env`) do set "%%a=%%b"

:: Configuration
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=12345"
set "MODEL=claude_local"

set "ANTHROPIC_BASE_URL=http://%LLAMA_HOST%:%LLAMA_PORT%"
set "ANTHROPIC_API_KEY=sk-local"
set "ANTHROPIC_MODEL=%MODEL%"
set "CLAUDE_CODE_ATTRIBUTION_HEADER=0"

echo   - Host:  %ANTHROPIC_BASE_URL%
echo   - Model: %ANTHROPIC_MODEL%
echo.
echo   Press Ctrl+C to exit
echo --------------------------------------------
echo.

:: Verificar si 'claude' está instalado
where claude >nul 2>&1
if errorlevel 1 goto :no_claude

:: Execution
claude --model "%ANTHROPIC_MODEL%" --dangerously-skip-permissions %*
goto :eof

:no_claude
echo ERROR: 'claude' (Claude Code) no esta instalado o no esta en el PATH.
echo Instalalo con: npm install -g @anthropic-ai/claude-code
exit /b 1
