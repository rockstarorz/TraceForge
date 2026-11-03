@echo off
setlocal
if defined OFFICIAL_BRIDGE_PYTHON (
  set "BRIDGE_PYTHON=%OFFICIAL_BRIDGE_PYTHON%"
) else (
  set "BRIDGE_PYTHON=python"
)

"%BRIDGE_PYTHON%" -c "import PyInstaller, pywinauto, win32api, win32con, win32gui"
if errorlevel 1 (
  echo Missing bridge build dependencies. Run: python -m pip install -r requirements.txt pyinstaller
  exit /b 1
)

"%BRIDGE_PYTHON%" -m PyInstaller --noconfirm --clean --onefile --noconsole --name official_bridge bridge.py ^
  --hidden-import win32api --hidden-import win32con --hidden-import win32gui ^
  --collect-all pywinauto --collect-all comtypes
if errorlevel 1 exit /b %errorlevel%

start /wait "" dist\official_bridge.exe self-check
if errorlevel 1 (
  echo Frozen bridge dependency self-check failed.
  exit /b 1
)
echo Built dist\official_bridge.exe
