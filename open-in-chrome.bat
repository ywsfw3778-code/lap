@echo off
setlocal

set "SITE=%~dp0chat-prototype_1.html"

set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" goto run

set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" goto run

set "CHROME=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" goto run

echo Chrome is not installed. Opening with the default browser instead.
start "" "%SITE%"
exit /b 0

:run
start "" "%CHROME%" --new-window "%SITE%"
