@echo off
REM ============================================================================
REM  Interviewer web build + deploy
REM
REM  Two flags are mandatory. Without them the deployed app is broken in ways
REM  the build never warns about:
REM
REM  1) --base-href /interviewer/
REM     The app is served under /interviewer/. The default base is "/", which
REM     makes every asset resolve to the domain root and 404 -> blank page.
REM
REM  2) --no-web-resources-cdn
REM     CanvasKit is fetched from gstatic.com by default. School LANs usually
REM     have no internet access, so that turns into a blank page. With this
REM     flag CanvasKit is loaded from the local canvaskit/ directory.
REM
REM  MSYS_NO_PATHCONV=1: under Git Bash a leading /interviewer/ gets rewritten
REM  to C:/Program Files/Git/interviewer/ and the base-href check fails.
REM
REM  NOTE: keep this file ASCII-only. cmd.exe reads .bat with the active code
REM  page; UTF-8 Chinese comments shift the byte offsets and corrupt parsing.
REM ============================================================================

setlocal
set MSYS_NO_PATHCONV=1
cd /d "%~dp0" || exit /b 1

where flutter >nul 2>nul
if errorlevel 1 (
	echo [ERROR] Flutter not found on PATH.
	exit /b 1
)

echo [1/3] Fetching dependencies...
call flutter pub get || goto :err

echo [2/3] Building web bundle...
call flutter build web --release --base-href /interviewer/ --no-web-resources-cdn || goto :err

echo [3/3] Publishing to backend\public\interviewer...
if not exist "..\backend\public\interviewer" mkdir "..\backend\public\interviewer"
xcopy /E /I /Y /Q "build\web\*" "..\backend\public\interviewer\" >nul || goto :err

echo.
echo Done. Output: ..\backend\public\interviewer
echo To change the server address on site, edit config.json there and
echo reload the browser. No rebuild needed.
exit /b 0

:err
echo.
echo [ERROR] Build failed. See the output above.
exit /b 1
