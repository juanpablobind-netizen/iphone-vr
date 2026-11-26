# Nexus VR · PCVR Lab 0.1

**Equipo objetivo:** iPhone 13, Windows 10/11, RTX 2050. Juegos objetivo a futuro: Roblox VR y Five Nights at Freddy's: Help Wanted.

Este paquete contiene código fuente de un prototipo, no un juego ni un instalador final. El servidor y el protocolo se han probado con datos sintéticos en Linux. El código de Swift pasó el análisis sintáctico, pero no se compiló con el SDK iOS. El DLL no se ha compilado ni probado en SteamVR. No hay IPA firmado ni EXE. No se ha probado con un iPhone físico.

## 1. Windows: iniciar el laboratorio

1. Extrae todo el ZIP a una carpeta normal (no ejecutes desde el ZIP).
2. Instala Python 3 para Windows desde https://www.python.org/downloads/windows/ (con el Python Launcher `py`).
3. Haz doble clic en `INICIAR_WINDOWS.bat`. Permite el acceso de Python solamente a redes privadas si Windows lo solicita. Mantén abierta la consola.
4. El navegador abre http://127.0.0.1:8765. Copia la dirección y la clave de sesión que aparecen. La clave cambia al reiniciar.
5. El iPhone y el PC deben estar en la misma red local; desactiva la red de invitados/aislamiento de clientes. No abras puertos en el router. No se transmite la cámara al PC: solo puntos y pose. La comunicación es HTTP sin cifrar, para red privada de confianza únicamente. Cierra el servidor cuando termines.

## 2. Compilar la aplicación desde Windows

1. Crea un repositorio **privado** vacío en https://github.com/new. No agregues un README inicial.
2. Sube el contenido completo de esta carpeta, incluyendo `.github/workflows/build.yml`. Si usas GitHub Desktop, la carpeta raíz es la que contiene `ios`, `driver`, `windows` y `.github`. No subas contraseñas ni credenciales. Alternativa con Git instalado, desde esta carpeta:

   ```powershell
   git init -b main
   git add .
   git commit -m "Nexus VR 0.1"
   git remote add origin https://github.com/TU_USUARIO/TU_REPOSITORIO.git
   git push -u origin main
   ```

3. Abre la pestaña **Actions** del repositorio y selecciona **Compilar Nexus VR**. El flujo se inicia al subir a main/master; también permite ejecución manual. GitHub utilizará macOS y Windows. Puede consumir minutos de tu cuenta. Revisa cualquier error de compilación antes de continuar: el flujo no se ha ejecutado en este entorno.
4. Si termina correctamente, descarga `NexusVR-iOS-sin-firmar` y `nexushands-driver-win64` desde Artifacts. Extrae el ZIP de cada artefacto.
5. Para instalar el IPA sin firmar desde Windows, utiliza una herramienta de firma compatible como https://sideloadly.io/ siguiendo sus instrucciones oficiales. Conecta el iPhone por USB, confía en el PC si iOS lo solicita y autoriza el Modo desarrollador si es necesario. Una cuenta gratuita normalmente requiere renovar la firma cada siete días. No compartas tu Apple ID ni contraseñas con nadie. La instalación depende de tu versión de iOS y de las restricciones de firma. El modo desarrollador reduce algunas protecciones de iOS; desactívalo si dejas de necesitarlo.

## 3. Primera prueba de manos

Abre Nexus VR, mantén el iPhone horizontal con el conector Lightning a la derecha, concede permisos de cámara y red local, escribe la dirección y clave del panel, y toca Conectar. Prueba primero sosteniendo el teléfono, no dentro de un visor. Usa buena iluminación, evita cruzar las manos y mantén dedos y palma visibles. En modo Manos verás la cámara y el esqueleto superpuesto. El panel de Windows debe indicar iPhone conectado y dibujar las manos. El pellizco de índice/pulgar es trigger; el puño es agarre; el pellizco de pulgar/medio es menú. Estos gestos son heurísticos, pueden necesitar ajustes. La posición usa una anchura de palma estimada de 7,5 cm; no es una medición real de profundidad. La orientación de cada mano solo se aproxima por giro en el plano de la cámara. ARKit registra pose de cabeza relativa a un origen; no controla por sí mismo SteamVR.

## 4. Vista remota opcional (NO es PCVR)

Cierra el servidor anterior y abre `VISTA_PC.bat`. Instala las dependencias en un entorno local Python y activa capturas JPEG del monitor principal. Cualquier contenido visible en ese monitor puede llegar al iPhone autenticado: cierra información privada. En Nexus VR el modo PC muestra la imagen 2D; SBS duplica la misma imagen para ambos ojos. No es renderizado estereoscópico, no tiene audio ni codificación NVENC. No tiene objetivo medido de 60 FPS. No uses esta vista para juegos rápidos o para caminar con el visor puesto. Puedes limitar a una región de captura ejecutando ` .venv\Scripts\python.exe windows\server.py --capture --region X Y ANCHO ALTO ` desde PowerShell sin espacios iniciales.

## 5. SteamVR: controlador de manos experimental

Requiere **un visor ya reconocido por SteamVR con pose válida**. El driver no implementa un HMD, ni captura las imágenes de SteamVR, ni emula completamente Valve Index. No puede iniciar una sesión VR por sí solo. Usa los datos de mano relativos a la cámara y los coloca en la pose del HMD existente. Para un teléfono montado en la cabeza, eso exigiría que el visor y la cámara correspondan físicamente y que la aplicación de seguimiento pueda funcionar simultáneamente con el software de visualización; este último punto no está resuelto en iOS.

Con SteamVR instalado y cerrado, tras compilar correctamente, abre PowerShell en la carpeta NexusVR y ejecuta:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\REGISTRAR_DRIVER.ps1 -DriverFolder "C:\ruta\nexushands"
```

Usa la carpeta que contiene `driver.vrdrivermanifest` y `bin\win64\driver_nexushands.dll`, no el ZIP. `-ExecutionPolicy Bypass` se limita al proceso de este script; revisa el código antes de ejecutarlo. Inicia el servidor, conecta Nexus VR y abre SteamVR con tu HMD existente. El driver pretende registrar dos controladores con perfil propio `nexushand`; debes configurar enlaces de SteamVR Input cuando estén disponibles. Si se pierde el seguimiento, libera las acciones y marca la pose inválida. No incluye esqueleto OpenVR de 31 huesos, joystick, háptica ni enlaces listos para Roblox/FNAF; los juegos podrían no admitir este perfil. Para retirar el driver, cierra SteamVR y repite el comando con `-Remove` al final. Si SteamVR lo bloquea, no desactives protecciones: desregístralo.

## 6. Ruta para llegar a PCVR real

- iVRy: https://apps.apple.com/us/app/ivry/id1210129937 y https://store.steampowered.com/app/992490/iVRy_Driver_for_SteamVR/ son una alternativa existente para transmitir VR al iPhone. No está integrada en Nexus ni se ha comprobado que pueda coexistir con la cámara de esta app; puedes probarla separadamente con controles compatibles.
- iPhoneVR: https://github.com/yanyantukebo1224/iphoneVR describe un proyecto experimental con Moonlight, ARKit y driver SteamVR. No se redistribuye código de ese proyecto ni se ha verificado su funcionamiento o licencia. Es una referencia técnica para una futura integración nativa.
- Apple Vision: https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision
- Valve Driver API: https://github.com/ValveSoftware/openvr/blob/master/docs/Driver_API_Documentation.md

Pendiente para jugar sin mandos: HMD SteamVR y streaming estereoscópico de baja latencia con NVENC/VideoToolbox y audio; calibración óptica y espacial; orientación 3D robusta; 31 huesos y bindings compatibles; validación con hardware real. Para la RTX 2050 empezar con calidad baja y 60 Hz si el sistema logra sostenerlos, sin garantía de rendimiento.

## Pruebas reproducibles

Desde la raíz: `py -3 -m unittest discover -s tests -v`. Comprueba HTTP, clave errónea, validación de datos, panel y puente UDP. Las pruebas no demuestran rendimiento de tracking o juegos. El protocolo de pose es JSON HTTP y el driver consume `NVR1` más 11 campos por mano en UDP local 9945; ver `windows/server.py` y `driver/driver.cpp`.

**Seguridad física:** prueba sentado, despeja el entorno, no uses escaleras ni te desplaces con el teléfono en el visor. No hay sistema de límites Guardian. Detente si hay mareo o latencia notable. Deja la cámara libre y evita sobrecalentar el teléfono.
