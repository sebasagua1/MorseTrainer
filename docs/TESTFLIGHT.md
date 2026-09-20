# Publicar en TestFlight

El proyecto ya está preparado: bundle ID real, icono, equipo de desarrollo y
clave de cumplimiento de cifrado. Lo que queda son los pasos que exigen tu
cuenta de Apple, y esos los ejecutas tú.

| | |
|---|---|
| Bundle ID | `com.sebasagua.MorseTrainer` |
| Team ID | `89RWP86552` |
| Versión | 1.0 |
| Build | número de commits de `git`, lo fija `release.sh` |

## Una sola vez

**1. Registrar el identificador.** En [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
crea un App ID explícito con `com.sebasagua.MorseTrainer`. No necesita ninguna
capability: la app no usa notificaciones, iCloud ni nada que haya que declarar.

**2. Crear el registro de la app.** En [App Store Connect](https://appstoreconnect.apple.com/apps)
› **+** › Nueva app. Plataforma iOS, el bundle ID del paso anterior, y un SKU
cualquiera (`morsetrainer` sirve). El nombre debe ser único en toda la App
Store; si «MorseTrainer» está cogido, cualquier variante vale — el nombre
visible se puede cambiar después.

**3. Localizar tu Issuer ID.** App Store Connect › **Usuarios y acceso** ›
**Integraciones** › Claves de App Store Connect. Es el UUID que aparece arriba,
sobre la lista de claves. Tu clave privada ya está instalada en esta máquina con
Key ID `6WPTV22NBW`.

**4. El certificado de distribución no hay que crearlo a mano.** Ahora mismo
solo tienes uno de desarrollo. El `-allowProvisioningUpdates` del guion lo pide
a Apple y lo instala en el llavero la primera vez que archives con credenciales.

## Cada build

```bash
ASC_KEY_ID=6WPTV22NBW ASC_ISSUER_ID=<tu-issuer-id> ./Scripts/release.sh --upload
```

Sin `--upload` archiva y deja el `.ipa` en `build/export/` para inspeccionarlo
antes de subir nada.

El número de build sale de `git rev-list --count HEAD`. Siempre crece, nunca se
repite —App Store Connect rechaza un build con un número ya usado para la misma
versión— y permite rastrear cualquier build que un tester reporte hasta el
commit exacto que lo generó.

Tras la subida, el procesado en App Store Connect tarda entre 5 y 30 minutos.
Cuando termine, el build aparece en la pestaña **TestFlight** y se puede repartir
a testers internos de inmediato. Los testers externos pasan por una revisión de
Apple, normalmente de un día.

## Qué avisará Apple

- **Cifrado.** Ya está resuelto: `ITSAppUsesNonExemptEncryption = NO` en el
  Info.plist, porque la app no usa criptografía. Sin esa clave, App Store
  Connect pregunta en cada build y bloquea el reparto hasta contestar.
- **Privacidad.** La app no recoge datos: todo vive en el dispositivo y no hay
  red. Aun así App Store Connect pide rellenar la ficha de privacidad — son dos
  clics contestando «No» a la recogida de datos.
- **Icono.** Resuelto. El de 1024×1024 se genera con `Scripts/make-icon.swift`.

## Lo que conviene probar en el dispositivo antes de repartir

Tres cosas que el simulador no puede verificar y que esta app usa de lleno:

1. **La háptica.** El continuo de la raya frente al impacto del punto es la
   mitad de la experiencia y nunca se ha ejecutado en un Taptic Engine real.
2. **La linterna.** Ruta completa sin probar: el simulador no tiene flash.
3. **El tono.** Que la rampa de 5 ms elimine de verdad el clic de conmutación a
   20 WPM es algo que solo se juzga con auriculares.
