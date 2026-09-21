import SwiftUI

struct ShopView: View {
    let store: PersistenceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// El cobre y lo comprado viven en SwiftData; esto solo fuerza el redibujo.
    @State private var copper = 0
    @State private var owned: Set<String> = []
    @State private var themeID = Theme.classic.id
    @State private var bankID = SoundBank.sine.id
    @State private var previewing: SoundBank?

    // @StateObject y no `let`: como propiedad de un struct View, el motor de
    // audio se construiría de nuevo en cada redibujo, dejando engines
    // huérfanos. Se crea una sola vez y vive lo que viva la pantalla.
    @StateObject private var previewer = MorseTransmitter()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Section2(title: "Temas") {
                        ForEach(Theme.all) { theme in
                            CosmeticRow(
                                name: theme.name,
                                detail: theme.detail,
                                price: theme.price,
                                owned: owned.contains(theme.id),
                                selected: themeID == theme.id,
                                affordable: copper >= theme.price,
                                swatch: AnyView(ThemeSwatch(theme: theme, scheme: scheme))
                            ) { act(on: theme.id) }
                        }
                    }

                    Section2(title: "Bancos de sonido",
                             note: "Tócalos para oírlos antes de comprar.") {
                        ForEach(SoundBank.all) { bank in
                            CosmeticRow(
                                name: bank.name,
                                detail: bank.detail,
                                price: bank.price,
                                owned: owned.contains(bank.id),
                                selected: bankID == bank.id,
                                affordable: copper >= bank.price,
                                swatch: AnyView(BankSwatch(bank: bank,
                                                           playing: previewing == bank))
                            ) { act(on: bank.id) }
                            .simultaneousGesture(TapGesture().onEnded { preview(bank) })
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(store.selectedTheme.palette(scheme).background)
            .morseTheme(store.selectedTheme, scheme)
            .navigationTitle("Tienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label("\(copper)", systemImage: "circle.hexagongrid.fill")
                        // En una barra, Label se colapsa a solo icono y el
                        // saldo desaparece justo donde más falta hace.
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(copper) de cobre")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .onAppear(perform: refresh)
        .onDisappear { previewer.cancel() }
    }

    /// Un toque compra si no se tiene y pone si ya se tiene. Dos acciones en un
    /// mismo sitio, pero nunca ambiguas: el estado de la fila dice cuál toca.
    private func act(on id: String) {
        if owned.contains(id) {
            store.select(id)
        } else {
            _ = store.buy(id)
            if store.owns(id) { store.select(id) }   // lo recién comprado se pone
        }
        refresh()
    }

    private func preview(_ bank: SoundBank) {
        previewing = bank
        previewer.soundBank = bank
        previewer.toneFrequency = bank.frequency
        previewer.channels = [.audio]
        Task {
            await previewer.play(text: "M", timing: .comfortable)
            if previewing == bank { previewing = nil }
        }
    }

    private func refresh() {
        copper = store.copper
        owned = store.ownedCosmetics
        themeID = store.selectedTheme.id
        bankID = store.selectedSoundBank.id
    }
}

// MARK: - Piezas

private struct Section2<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold))
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CosmeticRow: View {
    let name: String
    let detail: String
    let price: Int
    let owned: Bool
    let selected: Bool
    let affordable: Bool
    let swatch: AnyView
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                swatch
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(PressableCard())
        // Sin cobre suficiente la fila se apaga y no responde: mejor que
        // dejar pulsar algo que va a fallar en silencio.
        .disabled(!owned && !affordable)
        .opacity(!owned && !affordable ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var trailing: some View {
        if selected {
            // El estado no viaja solo en el borde de color: también hay texto.
            Label("Puesto", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        } else if owned {
            Text("Poner").font(.subheadline.weight(.semibold))
        } else {
            Label("\(price)", systemImage: "circle.hexagongrid.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(affordable ? .orange : .secondary)
        }
    }

    private var accessibilityText: String {
        if selected { return "\(name), puesto" }
        if owned { return "\(name), comprado. Tocar para poner" }
        if affordable { return "\(name), cuesta \(price) de cobre" }
        return "\(name), bloqueado. Cuesta \(price) de cobre"
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let scheme: ColorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(theme.keyFace(scheme))
            .frame(width: 44, height: 44)
            .overlay(
                HStack(spacing: 3) {
                    Circle().frame(width: 7, height: 7)
                    Capsule().frame(width: 19, height: 7)
                }
                .foregroundStyle(theme.accent(scheme))
            )
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.08)))
    }
}

private struct BankSwatch: View {
    let bank: SoundBank
    let playing: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            Image(systemName: playing ? "speaker.wave.3.fill" : "waveform")
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 44, height: 44)
    }
}

#Preview { ShopView(store: PersistenceStore(inMemory: true)) }
