import SwiftUI

/// Mapa de progresión estilo saga.
///
/// Antes era una columna de círculos idénticos centrados, con los dos tercios
/// horizontales de la pantalla vacíos y sin forma de distinguir un nivel
/// superado de uno por jugar. Ahora hay un camino: los nodos se alternan a
/// izquierda y derecha, una línea los une y cada estado —superado, actual,
/// bloqueado— se ve de un vistazo.
struct MapView: View {
    let store: PersistenceStore
    @ObservedObject var settings: GameSettings

    // El estado vive en SwiftData; estas copias existen solo para que SwiftUI
    // sepa cuándo redibujar. Se refrescan al volver de una lección.
    @State private var highestUnlocked = 1
    @State private var copper = 0
    @State private var streak = 0
    @State private var activeLevel: Level?
    @State private var theme = Theme.classic

    @Environment(\.colorScheme) private var scheme
    private var palette: MorsePalette { theme.palette(scheme) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(LevelPlan.worlds, id: \.self) { world in
                    Section {
                        ForEach(LevelPlan.levels(inWorld: world)) { level in
                            LevelNode(level: level,
                                      state: state(of: level),
                                      offset: Self.offset(for: level.id),
                                      previousOffset: Self.offset(for: level.id - 1),
                                      isFirstOfWorld: LevelPlan.levels(inWorld: world).first?.id == level.id) {
                                activeLevel = level
                            }
                        }
                    } header: {
                        WorldHeader(world: world,
                                    title: LevelPlan.worldTitles[world] ?? "",
                                    isUnlocked: LevelPlan.levels(inWorld: world)
                                        .contains { $0.id <= highestUnlocked })
                    }
                }
            }
            .padding(.bottom, Space.xl)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .morseTheme(theme, scheme)
        .navigationTitle("Progreso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Label("\(copper)", systemImage: "circle.hexagongrid.fill")
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("\(copper) de cobre")
            }
        }
        .overlay(alignment: .bottom) {
            if store.isEphemeral {
                Text("Progreso no guardado en este dispositivo")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(Space.sm)
            }
        }
        .fullScreenCover(item: $activeLevel, onDismiss: refresh) { level in
            // El VM ya persiste por su cuenta (también al quedarse sin
            // corazones); aquí solo se relee lo que quedó en disco.
            LessonView(level: level, store: store, settings: settings)
        }
        .onAppear(perform: refresh)
    }

    private func state(of level: Level) -> LevelNode.State {
        if level.id < highestUnlocked { return .completed }
        if level.id == highestUnlocked { return .current }
        return .locked
    }

    /// Zigzag suave. Determinista a partir del id, así cada nodo conoce también
    /// el desplazamiento del anterior y puede dibujar el tramo que los une sin
    /// que la vista tenga que medir a sus vecinos.
    static func offset(for id: Int) -> CGFloat {
        let cycle: [CGFloat] = [0, 64, 0, -64]
        return cycle[max(0, id - 1) % cycle.count]
    }

    private func refresh() {
        highestUnlocked = store.highestUnlockedLevel
        copper = store.copper
        streak = store.streakDays
        theme = store.selectedTheme
    }
}

private struct WorldHeader: View {
    let world: Int
    let title: String
    let isUnlocked: Bool

    @Environment(\.palette) private var palette

    private static let numerals = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

    var body: some View {
        VStack(spacing: Space.xs) {
            Text("Mundo \(Self.numerals.indices.contains(world) ? Self.numerals[world] : String(world))")
                .font(.rounded(.caption, .bold))
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
                .tracking(1.4)
            Text(title)
                .font(.rounded(.title3, .bold))
                .foregroundStyle(isUnlocked ? palette.textPrimary : palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        // Opaco, no translúcido: es una cabecera fija y los nodos pasan por
        // detrás. Con opacidad se veían candados asomando dentro del título.
        .background(palette.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }
}

private struct LevelNode: View {
    enum State { case completed, current, locked }

    let level: Level
    let state: State
    let offset: CGFloat
    let previousOffset: CGFloat
    let isFirstOfWorld: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var isPressed = false

    private let diameter: CGFloat = 88
    private let connector: CGFloat = 44

    private var isUnlocked: Bool { state != .locked }

    var body: some View {
        VStack(spacing: 0) {
            // Tramo de camino hasta el nodo anterior. El primero de cada mundo
            // no lo dibuja: ahí manda la cabecera.
            if !isFirstOfWorld {
                Path { path in
                    path.move(to: CGPoint(x: 120 + previousOffset, y: 0))
                    path.addLine(to: CGPoint(x: 120 + offset, y: connector))
                }
                // Rastro, no flecha: si pesa mucho compite con los nodos, que
                // son lo que hay que pulsar.
                .stroke(isUnlocked ? palette.accent.opacity(0.30) : palette.border,
                        style: .init(lineWidth: 4, lineCap: .round,
                                     dash: isUnlocked ? [] : [6, 8]))
                .frame(width: 240, height: connector)
            }

            Button(action: action) {
                VStack(spacing: Space.sm) {
                    medallion
                    label
                }
                .frame(maxWidth: .infinity)
                .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .offset(x: offset)
        }
        .padding(.top, isFirstOfWorld ? Space.lg : 0)
        .disabled(!isUnlocked)
        .accessibilityLabel("Nivel \(level.id): \(level.title)")
        .accessibilityValue(accessibilityState)
        .accessibilityHint(isUnlocked ? "Toca para jugar" : "Bloqueado")
    }

    private var accessibilityState: String {
        switch state {
        case .completed: return "Superado"
        case .current:   return "Siguiente nivel"
        case .locked:    return "Bloqueado"
        }
    }

    private var medallion: some View {
        ZStack {
            // Halo solo en el nivel actual: es el único que queremos que el ojo
            // encuentre al abrir el mapa.
            if state == .current {
                Circle()
                    .fill(palette.accent.opacity(0.22))
                    .frame(width: diameter + 26, height: diameter + 26)
            }

            Circle()
                .fill(fill)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(stroke, lineWidth: state == .current ? 4 : 2))
                .shadow(color: palette.accent.opacity(state == .current ? 0.45 : 0), radius: 18)

            content
        }
        .overlay(alignment: .bottomTrailing) {
            if state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.rounded(.title3, .bold))
                    .foregroundStyle(palette.success)
                    .background(Circle().fill(palette.background).padding(2))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .locked:
            Image(systemName: "lock.fill")
                .font(.rounded(.title2, .semibold))
                .foregroundStyle(palette.textSecondary)
        case .current, .completed:
            VStack(spacing: Space.xs) {
                Text(level.newCharacters.map(String.init).joined())
                    .displayFont(30, .bold, relativeTo: .title2)
                    .foregroundStyle(state == .current ? palette.onAccent : palette.accent)

                // El patrón solo aparece en los niveles ya superados: se enseña
                // de oído y se gana el derecho a leerlo. Mostrarlo antes sería
                // ofrecer la chuleta justo del carácter que toca aprender.
                //
                // Y solo con **una** letra nueva: el primer nivel enseña E y T,
                // y dibujar ahí el patrón de la E debajo de "ET" dice que "ET"
                // se transmite con un punto, que es falso.
                if state == .completed,
                   level.newCharacters.count == 1,
                   let first = level.newCharacters.first,
                   let code = MorseAlphabet.code(for: first) {
                    MorseGlyph(code: code, unit: 5, tint: palette.accent.opacity(0.85))
                }
            }
        }
    }

    private var fill: Color {
        switch state {
        case .current:   return palette.accent
        case .completed: return palette.accent.opacity(0.16)
        case .locked:    return palette.surface
        }
    }

    private var stroke: Color {
        switch state {
        case .current:   return palette.accent.opacity(0.35)
        case .completed: return palette.accent.opacity(0.45)
        case .locked:    return palette.border
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Text(level.title)
                .font(.rounded(.subheadline, .semibold))
                .foregroundStyle(isUnlocked ? palette.textPrimary : palette.textSecondary)
            Text("\(Int(level.timing.characterWPM))/\(Int(level.timing.effectiveWPM)) WPM · \(level.drillCount) ítems")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview { NavigationStack { MapView(store: PersistenceStore(inMemory: true), settings: GameSettings()) } }
