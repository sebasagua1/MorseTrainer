import SwiftUI

struct HomeView: View {
    let store: PersistenceStore
    @StateObject private var settings = GameSettings()

    @State private var highestUnlocked = 1
    @State private var copper = 0
    @State private var streak = 0
    @State private var freeSession: GameSession?
    @State private var showingSettings = false
    @State private var showingShop = false
    @State private var showingOnboarding = false
    @State private var theme = Theme.classic
    @Environment(\.colorScheme) private var scheme

    private var alphabet: [Character] { GameSession.unlockedAlphabet(upTo: highestUnlocked) }
    private var timing: FarnsworthTiming { GameSession.startingTiming(forUnlockedLevel: highestUnlocked) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    // NavigationLink y no un Button con `isPresented`: el
                    // modificador `navigationDestination(isPresented:)` es
                    // frágil sobre contenedores perezosos y se quedaba sin
                    // hacer nada al pulsar.
                    NavigationLink {
                        MapView(store: store, settings: settings)
                    } label: {
                        CampaignCard(level: LevelPlan.level(id: highestUnlocked),
                                     completed: highestUnlocked - 1,
                                     total: LevelPlan.levels.count)
                    }
                    .buttonStyle(PressableCard())

                    // Los modos libres solo tienen sentido con material que
                    // repasar. Con dos letras no hay nada que medir todavía.
                    if highestUnlocked > 1 {
                        ForEach(GameSession.Mode.freeModes) { mode in
                            ModeCard(mode: mode) { start(mode) }
                        }
                    } else {
                        LockedModesNote()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(theme.palette(scheme).background)
            .navigationTitle("Morse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
        .sheet(isPresented: $showingShop, onDismiss: refresh) {
            ShopView(store: store)
                .tint(theme.accent(scheme))
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(settings: settings) { showingOnboarding = false }
        }
        .fullScreenCover(item: $freeSession, onDismiss: refresh) { session in
            LessonView(session: session, store: store, settings: settings)
        }
        .morseTheme(theme, scheme)
        .onAppear {
            refresh()
            if !settings.hasSeenOnboarding { showingOnboarding = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            StatChip(symbol: "flame.fill", value: "\(streak)", tint: .orange,
                     label: "Racha de \(streak) días")
            Button { showingShop = true } label: {
                StatChip(symbol: "circle.hexagongrid.fill", value: "\(copper)", tint: .orange,
                         label: "\(copper) de cobre. Abre la tienda")
            }
            .buttonStyle(PressableCard())
            Spacer()
        }
        .padding(.top, 4)
    }

    private func start(_ mode: GameSession.Mode) {
        switch mode {
        case .practice:   freeSession = .practice(alphabet: alphabet, timing: timing)
        case .timeAttack: freeSession = .timeAttack(alphabet: alphabet, timing: timing)
        case .survival:   freeSession = .survival(alphabet: alphabet, timing: timing)
        case .level:      break   // la campaña entra por NavigationLink
        }
    }

    private func refresh() {
        highestUnlocked = store.highestUnlockedLevel
        copper = store.copper
        streak = store.streakDays
        theme = store.selectedTheme
    }
}

// MARK: - Piezas

private struct StatChip: View {
    let symbol: String
    let value: String
    let tint: Color
    let label: String

    @Environment(\.palette) private var palette

    var body: some View {
        Label(value, systemImage: symbol)
            .font(.rounded(.subheadline, .bold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + 2)
            .background(
                Capsule()
                    .fill(palette.surface)
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
            )
            .accessibilityLabel(label)
    }
}

/// La acción principal de la app. Antes pesaba visualmente lo mismo que los
/// tres modos secundarios —cuatro rectángulos grises iguales— y no había forma
/// de saber dónde tocar para seguir jugando. Ahora lleva el color del tema, la
/// letra que toca aprender y su ritmo dibujado al fondo.
private struct CampaignCard: View {
    let level: Level?
    let completed: Int
    let total: Int

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    private var nextCode: MorseCode? {
        guard let first = level?.newCharacters.first else { return nil }
        return MorseAlphabet.code(for: first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Label(GameSession.Mode.level.title,
                      systemImage: GameSession.Mode.level.symbol)
                    .font(.rounded(.subheadline, .bold))
                    // A tamaños de accesibilidad "Campaña" se partía en dos
                    // líneas y empujaba el contador fuera de sitio.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: Space.sm)
                Text("\(completed)/\(total)")
                    .font(.rounded(.subheadline, .bold).monospacedDigit())
            }
            .foregroundStyle(palette.onAccent.opacity(0.85))

            if let level {
                Text(level.title)
                    .font(.rounded(.title, .bold))
                    .foregroundStyle(palette.onAccent)

                Text("Aprende \(level.newCharacters.map(String.init).joined(separator: " y "))  ·  \(Int(level.timing.characterWPM))/\(Int(level.timing.effectiveWPM)) WPM")
                    .font(.subheadline)
                    .foregroundStyle(palette.onAccent.opacity(0.8))
            } else {
                Text("Campaña completa")
                    .font(.rounded(.title, .bold))
                    .foregroundStyle(palette.onAccent)
            }

            // Progreso propio: el `ProgressView` del sistema se teñía del
            // acento sobre el acento y desaparecía.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.onAccent.opacity(0.25))
                    Capsule().fill(palette.onAccent)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 8)

            HStack(spacing: Space.sm) {
                Text(level == nil ? "Repasar" : "Continuar")
                    .font(.rounded(.subheadline, .bold))
                Image(systemName: "arrow.right")
                    .font(.rounded(.footnote, .bold))
            }
            .foregroundStyle(palette.onAccent)
            .padding(.top, Space.xs)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(colors: [palette.accent.lighter(0.12), palette.accent.darker(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(alignment: .bottomTrailing) {
                    // El ritmo de la letra que toca, en grande y al fondo, como
                    // una marca al pie. Es el motivo gráfico que la app nunca
                    // había usado. Abajo a la derecha porque es la única zona
                    // de la tarjeta sin texto: arriba se comía el título.
                    // Con letra de accesibilidad el texto ocupa la tarjeta
                    // entera: la decoración se aparta, que para eso es
                    // decoración.
                    if let nextCode, !typeSize.isAccessibilitySize {
                        MorseGlyph(code: nextCode, unit: 15, tint: palette.onAccent.opacity(0.22))
                            .padding(.trailing, Space.lg)
                            .padding(.bottom, Space.lg)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .shadow(color: palette.accent.opacity(0.35), radius: 18, y: 8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el mapa de niveles")
    }

    private var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

private struct ModeCard: View {
    let mode: GameSession.Mode
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.symbol)
                    .font(.rounded(.title3, .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(palette.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(mode.title).font(.rounded(.headline, .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(mode.tagline)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.rounded(.footnote, .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableCard())
        .accessibilityElement(children: .combine)
    }
}

private struct LockedModesNote: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "lock.fill").foregroundStyle(palette.textSecondary)
            Text("Supera el primer nivel para abrir los demás modos")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.border, style: .init(lineWidth: 1.5, dash: [6, 6]))
                )
        )
    }
}

/// Hundido sutil al pulsar. `.plain` deja las tarjetas sin ninguna respuesta
/// táctil, y una tarjeta grande que no reacciona no parece pulsable.
struct PressableCard: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }
}

#Preview { HomeView(store: PersistenceStore(inMemory: true)) }
