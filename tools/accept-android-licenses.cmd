@echo off
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
(for /l %%i in (1,1,300) do @echo y) | "C:\Users\opena\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=C:\Users\opena\AppData\Local\Android\Sdk --licenses
exit /b %errorlevel%
