# Publicar en TestFlight

Queda **un solo paso manual**. Todo lo demás está hecho y verificado.

| | |
|---|---|
| Bundle ID | `com.sebasagua.MorseTrainer` |
| Team ID | `89RWP86552` |
| Versión | 1.0 · build = número de commits |
| App ID en el portal | ✅ registrado |
| Certificado de distribución | ✅ creado y en el llavero que gestiona Xcode |
| Perfil de tienda | ✅ `iOS Team Store Provisioning Profile: com.sebasagua.MorseTrainer` |
| Icono y cumplimiento de cifrado | ✅ |
| **Registro de la app en App Store Connect** | ❌ **pendiente** |

## El paso que falta

El registro de la app **no se puede automatizar**. La documentación de Apple lo
dice explícitamente:

> Don't use this API to create new apps; instead, create new apps on the App
> Store Connect website.

En [App Store Connect](https://appstoreconnect.apple.com/apps) › **+** ›
**Nueva app**:

- **Plataforma:** iOS
- **Bundle ID:** `com.sebasagua.MorseTrainer` (ya aparece en el desplegable)
- **Nombre:** debe ser único en toda la App Store. Si «MorseTrainer» está
  cogido, cualquier variante sirve; el nombre visible se cambia después.
- **SKU:** cualquiera, por ejemplo `morsetrainer`
- **Idioma principal:** el que prefieras

Dos minutos. No hay que tocar precios, capturas ni ficha de la App Store: nada
de eso hace falta para repartir por TestFlight.

## Subir

```bash
./Scripts/release.sh --upload
```

Sin argumentos ni variables de entorno: usa la cuenta que Xcode ya tiene
iniciada, que es la misma que registró el App ID y el certificado.

Si algún día lo necesitas desde CI, donde no hay sesión de Xcode, exporta
`ASC_KEY_ID` y `ASC_ISSUER_ID` y el guion usará la clave de API en su lugar. Tu
clave privada ya está instalada con Key ID `6WPTV22NBW`; el Issuer ID está en
App Store Connect › Usuarios y acceso › Integraciones.

Tras subir, el procesado tarda entre 5 y 30 minutos. Cuando termine, el build
aparece en la pestaña **TestFlight** y se reparte a testers internos de
inmediato. Los externos pasan por una revisión de Apple, normalmente de un día.

## Probar en tu iPhone antes de repartir

El `.ipa` de tienda **no se puede instalar en un dispositivo**: un perfil de
tienda no lleva lista de dispositivos. Para eso está el modo de desarrollo:

```bash
./Scripts/release.sh --dev
```

Produce `build/export-dev/MorseTrainer.ipa`, firmado con tu certificado de
desarrollo y autorizado en los 5 dispositivos registrados de tu equipo. Se
instala arrastrándolo sobre el dispositivo en Xcode › Window › Devices and
Simulators, o con:

```bash
xcrun devicectl device install app --device <UDID> build/export-dev/MorseTrainer.ipa
```

Vale la pena hacerlo antes de dar el build a nadie. **Tres cosas centrales de
esta app no se han ejecutado nunca en hardware**, porque el simulador no puede:

1. **La háptica.** El continuo de la raya frente al impacto seco del punto es
   la mitad de la experiencia.
2. **La linterna.** Ruta completa sin probar; el simulador no tiene flash.
3. **El tono.** Que la rampa de 5 ms elimine de verdad el clic de conmutación a
   20 WPM solo se juzga con auriculares.

## Lo que preguntará App Store Connect

- **Cifrado:** ya resuelto con `ITSAppUsesNonExemptEncryption = NO`. Sin esa
  clave, pregunta en cada build y bloquea el reparto hasta contestar.
- **Privacidad:** hay que rellenar la ficha. La app no recoge nada —todo vive
  en el dispositivo y no hay red— así que son dos clics contestando «No».
