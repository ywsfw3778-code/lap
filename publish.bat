@echo off
setlocal

where git >nul 2>nul
if errorlevel 1 (
  echo Git is not installed. Please install Git for Windows first.
  exit /b 1
)

for /f "tokens=1-3 delims=/ " %%a in ("%date%") do set d=%%c-%%a-%%b
for /f "tokens=1-2 delims=: " %%a in ("%time%") do set t=%%a-%%b
set "msg=auto update %d% %t%"

git add .
git commit -m "%msg%" >nul 2>nul
git push

if errorlevel 1 (
  echo Push failed. Check your Git remote and login.
  exit /b 1
)

echo Site update pushed successfully.
