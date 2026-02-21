@echo off
setlocal EnableExtensions

cd /d "%~dp0"
echo.
echo ===== Repo: %cd% =====

if not exist ".git" (
  echo [ERROR] Este .bat debe estar en la raiz del repo (no veo .git).
  pause
  exit /b 1
)

set "DIDSTASH=0"

REM 1) Detectar cambios (tracked/unstaged, staged, untracked)
echo.
echo ===== 1) Comprobando cambios locales =====

git diff --quiet
if errorlevel 1 goto DO_STASH
git diff --cached --quiet
if errorlevel 1 goto DO_STASH

for /f "delims=" %%A in ('git ls-files --others --exclude-standard') do goto DO_STASH

goto DO_PULL

:DO_STASH
echo.
echo ===== Guardando cambios (stash -u) =====
git stash push -u -m "auto-stash"
if errorlevel 1 (
  echo [ERROR] No se pudo hacer stash.
  pause
  exit /b 1
)
set "DIDSTASH=1"

:DO_PULL
echo.
echo ===== 2) Sincronizando (git pull --rebase) =====
git pull --rebase
if errorlevel 1 (
  echo.
  echo [ERROR] Fallo en git pull --rebase.
  echo Abre GitHub Desktop para resolver si hay conflictos.
  pause
  exit /b 1
)

REM 3) Si se hizo stash, lo recuperamos
if "%DIDSTASH%"=="1" (
  echo.
  echo ===== 3) Recuperando cambios (stash pop) =====
  git stash pop
  if errorlevel 1 (
    echo.
    echo [ERROR] Conflicto al aplicar stash.
    echo Abre GitHub Desktop, resuelve conflictos y vuelve a ejecutar el .bat.
    pause
    exit /b 1
  )
)

REM 4) Generar index
echo.
echo ===== 4) Generando index.html =====
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%cd%\generate_index.ps1"
if errorlevel 1 (
  echo [ERROR] Fallo al ejecutar generate_index.ps1
  pause
  exit /b 1
)

REM 5) Si no hay cambios, salir
echo.
echo ===== 5) Comprobando cambios tras generar index =====
for /f "delims=" %%A in ('git status --porcelain') do goto DO_COMMIT

echo.
echo ===== No hay cambios. Nada que publicar. =====
pause
exit /b 0

:DO_COMMIT
echo.
echo ===== 6) Publicando (add/commit/push) =====
git add -A
git commit -m "Actualizacion automatica"
git push

if errorlevel 1 (
  echo.
  echo [ERROR] Fallo en git push (credenciales o cambios remotos).
  echo Prueba a ejecutar otra vez el .bat.
  pause
  exit /b 1
)

echo.
echo ===== PUBLICADO EN GITHUB (con index actualizado) =====
pause