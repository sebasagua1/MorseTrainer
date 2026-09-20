import SwiftUI

struct HomeView: View {
    let store: PersistenceStore
    @StateObject private var settings = GameSettings()

    @State private var highestUnlocked = 1
    @State private var copper = 0
    @State private var streak = 0
    @State private var freeSession: GameSession?
    @State private var showingMap = false
    @State private var showingSettings = false

    private var alphabet: [Character] { GameSession.unlockedAlphabet(upTo: highestUnlocked) }
    private var timing: FarnsworthTiming { GameSession.startingTiming(forUnlockedLevel: highestUnlocked) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    CampaignCard(level: LevelPlan.level(id: highestUnlocked),
                                 completed: highestUnlocked - 1,
                                 total: LevelPlan.levels.count) {
                        showingMap = true
                    }

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
            .background(Color(.systemGroupedBackground))
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
        .navigationDestination(isPresented: $showingMap) {
            MapView(store: store, settings: settings)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
        .fullScreenCover(item: $freeSession, onDismiss: refresh) { session in
            LessonView(session: session, store: store, settings: settings)
        }
        .onAppear(perform: refresh)
    }

    private var header: some View {
        HStack(spacing: 12) {
            StatChip(symbol: "flame.fill", value: "\(streak)", tint: .orange,
                     label: "Racha de \(streak) días")
            StatChip(symbol: "circle.hexagongrid.fill", value: "\(copper)", tint: .orange,
                     label: "\(copper) de cobre")
            Spacer()
        }
        .padding(.top, 4)
    }

    private func start(_ mode: GameSession.Mode) {
        switch mode {
        case .practice:   freeSession = .practice(alphabet: alphabet, timing: timing)
        case .timeAttack: freeSession = .timeAttack(alphabet: alphabet, timing: timing)
        case .survival:   freeSession = .survival(alphabet: alphabet, timing: timing)
        case .level:      showingMap = true
        }
    }

    private func refresh() {
        highestUnlocked = store.highestUnlockedLevel
        copper = store.copper
        streak = store.streakDays
    }
}

// MARK: - Piezas

private struct StatChip: View {
    let symbol: String
    let value: String
    let tint: Color
    let label: String

    var body: some View {
        Label(value, systemImage: symbol)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            .accessibilityLabel(label)
    }
}

private struct CampaignCard: View {
    let level: Level?
    let completed: Int
    let total: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(GameSession.Mode.level.title,
                          systemImage: GameSession.Mode.level.symbol)
                        .font(.headline)
                    Spacer()
                    Text("\(completed)/\(total)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let level {
                    Text(level.title)
                        .font(.title2.weight(.bold))
                    Text("Aprende \(level.newCharacters.map(String.init).joined(separator: " y "))  ·  \(Int(level.timing.characterWPM))/\(Int(level.timing.effectiveWPM)) WPM")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Campaña completa")
                        .font(.title2.weight(.bold))
                }

                ProgressView(value: Double(completed), total: Double(total))
                    .tint(.accentColor)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(PressableCard())
        .accessibilityHint("Abre el mapa de niveles")
    }
}

private struct ModeCard: View {
    let mode: GameSession.Mode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.accentColor.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title).font(.headline)
                    Text(mode.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(PressableCard())
        .accessibilityElement(children: .combine)
    }
}

private struct LockedModesNote: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            Text("Supera el primer nivel para abrir los demás modos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
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
