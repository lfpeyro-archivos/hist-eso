@echo off
setlocal EnableExtensions

REM Ir a la carpeta donde está este .bat (portable)
cd /d "%~dp0"

REM Guardamos la ruta sin comillas finales
set "REPO=%CD%"

REM 0) Si no hay cambios locales, sincronizar antes (multi-PC)
set "DIRTY="
for /f "delims=" %%A in ('git status --porcelain') do set "DIRTY=1"

if not defined DIRTY (
  echo.
  echo ===== Sin cambios locales: haciendo git pull --rebase =====
  git pull --rebase

  if errorlevel 1 (
    echo.
    echo [ERROR] Fallo en git pull --rebase
    echo (Si hay conflicto, resuelvelo en GitHub Desktop y vuelve a ejecutar.)
    pause
    exit /b 1
  )
) else (
  echo.
  echo ===== Hay cambios locales: salto el pull =====
)

REM 1) Generar/actualizar index.html
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\generate_index.ps1"

if errorlevel 1 (
  echo.
  echo [ERROR] Fallo al generar index.html
  pause
  exit /b 1
)

REM 2) Ver si hay cambios antes de commitear
set "HASCHANGES="
for /f "delims=" %%A in ('git status --porcelain') do set "HASCHANGES=1"

if not defined HASCHANGES (
  echo.
  echo ===== No hay cambios. Nada que publicar. =====
  pause
  exit /b 0
)

REM 3) Publicar cambios
git add .
git commit -m "Actualizacion automatica %date% %time%"
git push

if errorlevel 1 (
  echo.
  echo [ERROR] Fallo en git push
  echo (Si alguien publico justo antes, vuelve a ejecutar.)
  pause
  exit /b 1
)

echo.
echo ===== PUBLICADO EN GITHUB (con index actualizado) =====
pause