# PHP 7.4.33 con el parche PHP2Shell para Windows

**Estado: primera compilación completada; corregida la comprobación del compilador para repetir la validación. Aún no hay un paquete validado disponible.**

[Ejecución de GitHub Actions](https://github.com/4itec/php-7.4.3.3-patch/actions/runs/39813282800).

Compilación propia de **PHP 7.4.33-pl1, x64, Thread Safe, VC15**.
Parte de la etiqueta oficial PHP 7.4.33 y aplica exclusivamente el parche oficial
para CVE-2026-109618 y CVE-2026-109619, además de identificar la versión compilada.

Destino previsto: Windows Server 2019, Apache 2.4 y Wampserver 3.2.6.
La compilación se realiza en Windows Server 2022 de GitHub Actions.
**La compatibilidad con la instalación concreta de Wampserver y la aplicación
debe verificarse en una copia del servidor antes de instalar en producción.**

## Procedencia y límites

- Código: [php/php-src](https://github.com/php/php-src), etiqueta oficial php-7.4.33.
- Parche: [712e60f9edfd03f0960fc4fc3c2c375f42b90aa2](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2).
- Constructor: [php/php-windows-builder](https://github.com/php/php-windows-builder).
- Revisiones exactas: [sources.lock.json](sources.lock.json).
- Aviso: https://www.php.net/archive/2026.php#2026-10-21-5

No es una distribución oficial de PHP ni de Wampserver. PHP 7.4 está fuera de
soporte y el propio cambio de PHP se describe como una mitigación mínima para
una rama EOL. Este trabajo no corrige otras vulnerabilidades ni actualiza todas
las bibliotecas históricas de PHP 7.4. El uso de fuentes oficiales no garantiza
ausencia de riesgos. Es una medida transitoria durante la migración.

El parche termina inmediatamente el proceso de PHP cuando se agota la memoria.
Con mod_php, PHP se ejecuta dentro de Apache: ese cierre puede interrumpir otras
solicitudes del mismo proceso y afectar temporalmente a la disponibilidad. También
desactiva el seguimiento de progreso de subidas mediante sesiones; las subidas
normales se prueban por separado. Estos cambios deben revisarse con la aplicación.

El proceso usa herramientas y dependencias de sus proveedores originales.
Los scripts de automatización de este repositorio son propios y revisables.
Las bibliotecas de compilación se obtienen del servicio oficial de PHP; sus
versiones efectivas y los hashes de las DLL entregadas quedan inventariados.
La repetición del procedimiento no implica un ZIP idéntico byte a byte.

## Ejecución

En Actions, ejecutar "Build patched PHP 7.4". Los cambios en scripts, pruebas,
el lock o el propio workflow también lo ejecutan en main. No se necesita subir
la aplicación, credenciales ni datos del cliente.

El workflow comprueba los commits de entrada, aplica el parche sin resolución
automática de conflictos y compara cada archivo parcheado con el blob oficial.
Guarda el diff de seguridad, el cambio separado de identidad y el árbol de
fuentes exacto. Luego usa el constructor oficial para generar el ZIP TS x64.

La compilación y la validación se ejecutan en trabajos separados. El artefacto
intermedio `php74-build-inputs` conserva los binarios como entrada para las pruebas;
no acredita que hayan pasado. El paquete validado se llama `php-7.4.33-pl1-x64-ts`.
Los hashes se comprueban al pasar del trabajo de compilación al de validación.

Las pruebas incluyen:

- Identidad, arquitectura, Thread Safety, módulo Apache y extensiones requeridas.
- Carga de extensiones mediante las pruebas del constructor oficial.
- JSON/Unicode, OpenSSL, GD, ICU, ZIP, SQLite y sesiones.
- Formularios HTTP normales y multipart en un servidor de pruebas ligado a 127.0.0.1.
- El seguimiento de subidas permanece desactivado por el parche aunque la prueba
  lo solicite en el INI.
- Un proceso CLI aislado que excede 16 MB verifica que no se ejecutan callbacks
  de cierre tras el error de memoria, comportamiento introducido por el parche.

Estas pruebas no son una auditoría exhaustiva ni acreditan todos los vectores
de explotación. No se ejecutan contra producción.

## Descargas y evidencias

Solo si pasan la compilación y las pruebas se publica el artefacto de binarios
con su manifiesto, hashes, fuentes exactas y certificación de procedencia.
Los registros de diagnóstico se conservan también si una fase falla.
Descargar el artefacto de una ejecución marcada como correcta y verificar
SHA256SUMS antes de utilizar el ZIP.

La certificación vincula el archivo al proceso de GitHub Actions. No acredita
por sí sola la seguridad del software. Puede comprobarse con GitHub CLI:
~~~powershell
gh attestation verify .\php-7.4.33-pl1-Win32-vc15-x64.zip --repo 4itec/php-7.4.3.3-patch
~~~

El paquete conserva las licencias incorporadas por el constructor de PHP.

## Incorporación a Wampserver

Realizar primero una copia recuperable y trabajar en una copia del entorno.
Crear una carpeta PHP nueva y extraer el ZIP completo; conservar la configuración
anterior y adaptar php.ini, phpForApache.ini y wampserver.conf. Usar las DLL
incluidas en el paquete y revisar la compatibilidad de extensiones externas.
El nombre de carpeta y el registro en el menú deben comprobarse con Wampserver
3.2.6; no se modifica automáticamente ningún servidor.

Verificar la compilación desde cada VirtualHost, además de la consola. Revisar
que Apache utiliza php7apache2_4.dll y php7ts.dll de este paquete, reiniciar todos
sus procesos y probar los flujos de la aplicación antes del cambio definitivo.

Mantener la protección WAF de Cloudflare y comprobar que no hay acceso público
directo al origen que la evite. Ajustar session.upload_progress.enabled=0 y los
límites de solicitudes a la aplicación. Estas medidas no sustituyen la migración.
