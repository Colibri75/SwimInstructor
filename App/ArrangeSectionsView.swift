import SwiftUI
import SwimInstructorCore

/// Letzter Abschnitt jeder Liste eines Tabs: "Bereiche anpassen" öffnet das Blatt zum Umsortieren, Ausblenden und
/// Hinzufügen. Steht unten in der Liste statt in der Toolbar, damit rechts oben nur die Aktionen des Tabs bleiben.
struct CustomizeSectionsRow: View {
    let screen: LayoutScreen

    @State private var showsSheet = false

    var body: some View {
        Section {
            Button {
                showsSheet = true
            } label: {
                Label("Bereiche anpassen", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .sheet(isPresented: $showsSheet) {
                ArrangeSectionsSheet(screen: screen)
            }
        }
    }
}

/// Die Bereiche eines Bildschirms: angezeigte ziehen zum Umsortieren, entfernen blendet aus (Pflichtbereiche bleiben),
/// ausgeblendete mit Plus wieder hinzufügen. Jede Änderung gilt sofort und bleibt auf dem Gerät gespeichert.
struct ArrangeSectionsSheet: View {
    let screen: LayoutScreen

    @EnvironmentObject private var layouts: ScreenLayouts
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                    visibleSection
                    hiddenSection
                    Section {
                        Button("Standard wiederherstellen", role: .destructive) {
                            confirmsReset = true
                        }
                        .disabled(layouts.isStandard(screen))
                    }
                }
                .cardRows()
            }
            .themedList()
            // Immer im Bearbeiten: Griffe zum Ziehen und Minus sind sofort da.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("\(screen.displayName) anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Reihenfolge und Auswahl zurücksetzen?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Standard wiederherstellen", role: .destructive) {
                    withAnimation { layouts.reset(screen) }
                }
            }
        }
    }

    private var visibleSection: some View {
        Section {
            ForEach(layouts.visible(screen)) { section in
                SectionLine(section: section)
                    .deleteDisabled(section.isRequired)
                    .accessibilityAction(named: "Nach oben") { layouts.move(screen, section: section.id, by: -1) }
                    .accessibilityAction(named: "Nach unten") { layouts.move(screen, section: section.id, by: 1) }
            }
            .onMove { source, destination in
                layouts.move(screen, fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                withAnimation { layouts.hide(screen, atOffsets: offsets) }
            }
        } header: {
            Text("Angezeigt")
        } footer: {
            Text("Ziehen ändert die Reihenfolge. Minus blendet einen Bereich aus. Bereiche mit Schloss gehören zum Tab und lassen sich nur verschieben.")
        }
    }

    private var hiddenSection: some View {
        Section {
            let hidden = layouts.hidden(screen)
            if hidden.isEmpty {
                Text("Alle Bereiche werden angezeigt.")
                    .foregroundStyle(.secondary)
            }
            ForEach(hidden) { section in
                Button {
                    withAnimation { layouts.show(screen, section: section.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        SectionLine(section: section)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title) hinzufügen")
            }
        } header: {
            Text("Ausgeblendet")
        } footer: {
            Text("Plus fügt den Bereich unten wieder an.")
        }
    }
}

/// Ein Bereich in der Liste: Symbol, Name, kurz was er zeigt, Schloss bei Pflichtbereichen.
private struct SectionLine: View {
    let section: LayoutSection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.body.weight(.semibold))
                Text(section.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if section.isRequired {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Lässt sich nicht ausblenden")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
