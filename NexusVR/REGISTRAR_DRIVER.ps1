param([Parameter(Mandatory=$true)][string]$DriverFolder,[switch]$Remove)
$ErrorActionPreference='Stop'
$folder=(Resolve-Path $DriverFolder).Path
if (!(Test-Path (Join-Path $folder 'bin\win64\driver_nexushands.dll'))) {throw 'Falta el DLL compilado. Extrae el artefacto de GitHub Actions primero.'}
if (!(Test-Path (Join-Path $folder 'driver.vrdrivermanifest'))) {throw 'Falta el manifiesto del driver.'}
$config=Join-Path $env:LOCALAPPDATA 'openvr\openvrpaths.vrpath'
$runtime=(Get-Content $config -Raw|ConvertFrom-Json).runtime | Select-Object -First 1
$tool=Join-Path $runtime 'bin\win64\vrpathreg.exe'
if (!(Test-Path $tool)) {throw 'No se encontró vrpathreg.exe. Instala y abre SteamVR una vez.'}
if (Get-Process vrserver -ErrorAction SilentlyContinue) {throw 'Cierra SteamVR antes de continuar.'}
if ($Remove) { & $tool removedriver $folder } else { & $tool adddriver $folder }
if ($LASTEXITCODE -ne 0) {throw 'No se pudo registrar el controlador.'}
& $tool show
