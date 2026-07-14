@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

echo =====================================================
echo   ACADEMIA BOMBEIRO CIVIL - CONFIGURACAO AUTOMATICA
echo =====================================================
echo.
echo Cole abaixo a Publishable Key completa do Supabase.
echo Ela comeca com: sb_publishable_
echo NAO use a chave sb_secret_.
echo.
set /p SUPABASE_KEY=Publishable Key: 

if "%SUPABASE_KEY%"=="" (
  echo.
  echo ERRO: nenhuma chave foi informada.
  pause
  exit /b 1
)

echo %SUPABASE_KEY% | findstr /b /c:"sb_publishable_" >nul
if errorlevel 1 (
  echo.
  echo ERRO: a chave precisa comecar com sb_publishable_
  pause
  exit /b 1
)

(
  echo NEXT_PUBLIC_SUPABASE_URL=https://xqeseqijwzwpkimvocgz.supabase.co
  echo NEXT_PUBLIC_SUPABASE_ANON_KEY=%SUPABASE_KEY%
  echo NEXT_PUBLIC_PIX_KEY=85994213560
  echo NEXT_PUBLIC_PIX_HOLDER=Jonathan Francelino
  echo NEXT_PUBLIC_WHATSAPP=5585994213560
  echo NEXT_PUBLIC_SITE_URL=http://localhost:3000
) > .env.local

echo.
echo Arquivo .env.local criado com sucesso.

if exist .next (
  echo Limpando cache antigo...
  rmdir /s /q .next
)

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo ERRO: Node.js nao foi encontrado.
  echo Instale a versao LTS em https://nodejs.org e abra este arquivo novamente.
  pause
  exit /b 1
)

if not exist node_modules (
  echo Instalando dependencias. Isso pode demorar alguns minutos...
  call npm install
  if errorlevel 1 (
    echo.
    echo ERRO durante npm install.
    pause
    exit /b 1
  )
)

echo.
echo Iniciando o site em http://localhost:3000
echo Nao feche esta janela enquanto estiver usando o site.
echo.
start "" http://localhost:3000
call npm run dev
