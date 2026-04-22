@echo off

REM Variables para Claude Code
set ANTHROPIC_BASE_URL=http://127.0.0.1:12345/v1
set ANTHROPIC_API_KEY=sk-local
set ANTHROPIC_MODEL=Qwopus3.5-9B
set CLAUDE_CODE_ATTRIBUTION_HEADER=0

echo 🚀 Iniciando Claude Code directo a llama-server (Puerto 12345)
claude --model "%ANTHROPIC_MODEL%" --dangerously-skip-permissions %*

pause
