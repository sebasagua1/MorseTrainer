import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sonido", isOn: $settings.audioEnabled)
                    Toggle("Vibración", isOn: $settings.hapticsEnabled)
                    Toggle("Linterna", isOn: $settings.torchEnabled)
                } header: {
                    Text("Canales de salida")
                } footer: {
                    if settings.hasAnyChannel {
                        Text("El Morse se transmite por todos los canales activos a la vez. La linterna permite jugar en silencio y sustituye al sonido si no oyes.")
                    } else {
                        Label("Sin ningún canal activo no se puede recibir Morse.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("Frecuencia", selection: $settings.toneFrequency) {
                        ForEach(GameSettings.toneChoices, id: \.self) { hertz in
                            Text(hertz == 0 ? "Automática" : "\(Int(hertz)) Hz").tag(hertz)
                        }
                    }
                    .disabled(!settings.audioEnabled)
                } header: {
                    Text("Tono")
                } footer: {
                    Text("En automática manda el banco de sonido que tengas puesto. Elegirla a mano ayuda si tienes pérdida auditiva en alguna frecuencia, y entonces el ajuste gana al cosmético.")
                }

                Section {
                    Toggle("Mostrar el patrón al fallar", isOn: $settings.revealPatternOnError)
                } footer: {
                    Text("Ver puntos y rayas escritos enseña a leerlos, no a oírlos. Úsalo como apoyo puntual, no de continuo.")
                }

                Section {
                    LabeledContent("Velocidad de carácter", value: "18–25 WPM")
                    LabeledContent("Método", value: "Koch + Farnsworth")
                } header: {
                    Text("Cómo enseña")
                } footer: {
                    Text("Los caracteres suenan siempre rápido y lo que se alarga es el silencio entre ellos. Así aprendes el ritmo en vez de contar elementos, que es el hábito más difícil de corregir después.")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}

#Preview { SettingsView(settings: GameSettings()) }
