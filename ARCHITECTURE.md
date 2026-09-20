# Arquitectura — Juego de Código Morse (SwiftUI + MVVM)

## Principio rector

Una sola **línea de tiempo Morse** (`[MorseEvent]`) alimenta los tres canales de
salida: audio, Taptic Engine y linterna. Nada vuelve a calcular temporizaciones
por su cuenta, así que la vibración jamás se desincroniza del sonido y el modo
accesible es gratis.

```
Modelo puro (sin SwiftUI)  →  Servicios (efectos)  →  ViewModels (@MainActor)  →  Vistas
```

## Capas

### 1. Model — Swift puro, testeable sin simulador

| Tipo | Rol |
|---|---|
| `MorseSymbol`, `MorseCode` | Punto/raya y patrón de un carácter |
| `MorseAlphabet` | Tablas directa e inversa, orden Koch y orden del GDD |
| `FarnsworthTiming` | `characterWPM` / `effectiveWPM` → duraciones (fórmula ARRL) |
| `MorseEvent` | Tramo on/off; unidad de la línea de tiempo |
| `Level`, `DrillMix`, `MasteryRule` | Definición declarativa de un nivel |
| `CharacterStat`, `ConfusionPair` | Memoria del aprendizaje por carácter y por par |
| `DrillScheduler` | Repetición espaciada ponderada (`struct`, determinista con RNG inyectado) |
| `PlayerProfile`, `Wallet`, `Streak` | Metajuego: cobre, racha, corazones, cosméticos |

### 2. Services — efectos y hardware (clases, algunas `@MainActor`)

| Servicio | Responsabilidad |
|---|---|
| `Sidetone` | Oscilador senoidal con envolvente de 4 ms (sin clics) |
| `TelegraphFeedback` | Core Haptics: continuo para raya, transitorio para punto |
| `TorchTransmitter` | Reproduce la línea de tiempo con el flash |
| `MorseTransmitter` | Orquesta audio+háptica+linterna sobre el mismo `[MorseEvent]` |
| `PersistenceStore` | SwiftData: `@Model` para perfil, estadísticas y sesiones |
| `ThemeCatalog`, `SoundBank` | Cosméticos desbloqueables |

Todos se exponen tras un protocolo (`TelegraphFeedbackProviding`, …) para poder
inyectar dobles en tests y en `#Preview`.

### 3. ViewModel — `@MainActor`, `ObservableObject` (o `@Observable` en iOS 17+)

| ViewModel | Estado que posee |
|---|---|
| `AppViewModel` | Router, perfil cargado, racha diaria |
| `MapViewModel` | Nodos del mapa, nivel desbloqueado, progreso |
| `LessonViewModel` | Cola de ejercicios, corazones, resultados móviles, dominio |
| `TelegraphKeyViewModel` | Buffer de símbolos, umbral adaptativo punto/raya |
| `ReceptionDrillViewModel` | Prompt actual, teclado dinámico, cronómetro |
| `ShopViewModel` | Cobre, catálogo, compras |

`LessonViewModel` es el único dueño del `DrillScheduler`; los VM de ejercicio le
reportan hacia arriba mediante *closures*, no al revés.

### 4. View — SwiftUI, sin lógica

```
RootView
├── OnboardingView
├── MapView                    ← saga de mundos, nodo por nivel
│   └── WorldNodeView
├── LessonView                 ← corazones, barra de progreso, salida
│   ├── ReceptionDrillView     ← escucha → teclado dinámico
│   │   └── DynamicKeyboardView
│   ├── TransmissionDrillView  ← letra → manipulador
│   │   ├── TelegraphKeyView
│   │   └── MorseBufferStrip
│   └── WordRoundView
├── ResultsView                ← cobre ganado, pares confundidos, racha
├── ShopView
└── SettingsView               ← linterna, silencio, frecuencia del tono, daltonismo
```

## Persistencia (SwiftData)

```swift
@Model final class PlayerProfileEntity {
    var highestLevel: Int
    var copper: Int
    var streakDays: Int
    var lastPlayed: Date
    @Relationship(deleteRule: .cascade) var stats: [CharacterStatEntity]
}
```

Las estadísticas por carácter persisten **entre niveles**: un fallo en la A del
nivel 2 sigue pesando en la cola del nivel 7. Es lo que hace que la repetición
espaciada sea real y no un adorno por sesión.

## Feedback "jugoso"

| Evento | Audio | Háptica | Visual |
|---|---|---|---|
| Punto enviado | tono 600 Hz, 1 unidad | `.rigid` transitorio | glifo `•`, anillo vacío |
| Raya enviada | tono sostenido | continuo 0.85/0.75 | glifo `—`, anillo lleno |
| Acierto | acorde ascendente | `.success` | zoom 1.04, partículas, +cobre |
| Fallo | tono grave corto | `.error` | screen shake 6 pt, borde rojo, −1 corazón |
| Nivel superado | fanfarria | secuencia rítmica | confeti, contador de cobre animado |

## Rendimiento y accesibilidad

- El bucle de render del oscilador no asigna memoria ni toma locks.
- Respeta `Reduce Motion` (sin shake, sin zoom) y `Reduce Transparency`.
- La linterna es una alternativa completa al audio, no un extra.
- Etiquetas VoiceOver en el manipulador y en el teclado dinámico.
- Modo Oscuro por tokens semánticos; nunca color como único portador de estado.
