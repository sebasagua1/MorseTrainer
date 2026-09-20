import SwiftUI

/// Mapa de progresión estilo saga. Mínimo deliberado: su trabajo aquí es
/// lanzar `LessonView` y recoger el resultado. El metajuego completo (cobre,
/// racha, tienda) vive en `AppViewModel` cuando exista `PersistenceStore`.
struct MapView: View {
    let store: PersistenceStore
    @ObservedObject var settings: GameSettings

    // El estado vive en SwiftData; estas copias existen solo para que SwiftUI
    // sepa cuándo redibujar. Se refrescan al volver de una lección.
    @State private var highestUnlocked = 1
    @State private var copper = 0
    @State private var streak = 0
    @State private var activeLevel: Level?

    var body: some View {
        ScrollView {
                LazyVStack(spacing: 28, pinnedViews: [.sectionHeaders]) {
                    ForEach(LevelPlan.worlds, id: \.self) { world in
                        Section {
                            ForEach(LevelPlan.levels(inWorld: world)) { level in
                                LevelNode(level: level,
                                          isUnlocked: level.id <= highestUnlocked,
                                          isCurrent: level.id == highestUnlocked) {
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
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
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
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .fullScreenCover(item: $activeLevel, onDismiss: refresh) { level in
            // El VM ya persiste por su cuenta (también al quedarse sin
            // corazones); aquí solo se relee lo que quedó en disco.
            LessonView(level: level, store: store, settings: settings)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        highestUnlocked = store.highestUnlockedLevel
        copper = store.copper
        streak = store.streakDays
    }
}

private struct WorldHeader: View {
    let world: Int
    let title: String
    let isUnlocked: Bool

    private static let numerals = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

    var body: some View {
        VStack(spacing: 2) {
            Text("Mundo \(Self.numerals.indices.contains(world) ? Self.numerals[world] : String(world))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(isUnlocked ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct LevelNode: View {
    let level: Level
    let isUnlocked: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 84, height: 84)
                        .shadow(color: .accentColor.opacity(isCurrent ? 0.45 : 0), radius: 18)

                    if isUnlocked {
                        Text(String(level.newCharacters.map(String.init).joined()))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        Circle().fill(.green).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 3))
                    }
                }

                Text(level.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                Text("\(Int(level.timing.characterWPM))/\(Int(level.timing.effectiveWPM)) WPM · \(level.drillCount) ítems")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityLabel("Nivel \(level.id): \(level.title)")
        .accessibilityHint(isUnlocked ? "Toca para jugar" : "Bloqueado")
    }
}

#Preview { NavigationStack { MapView(store: PersistenceStore(inMemory: true), settings: GameSettings()) } }
