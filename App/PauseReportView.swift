import SwiftUI
import SwimInstructorCore

/// Pause melden (krank, verletzt, Urlaub). Ab 7 Tagen schreibt die App den Gesamtplan außer der Reihe fort: Er steigt
/// danach vom Ist aus wieder ein, statt dort weiterzumachen, wo er vor der Pause stand.
struct PauseReportView: View {
    @EnvironmentObject private var todayLoader: MultiSportTodayLoader
    @EnvironmentObject private var reviewRunner: MacroReviewRunner
    @Environment(\.dismiss) private var dismiss

    private let store: PauseReportStoring

    @State private var kind = PauseReport.Kind.sick
    @State private var from = Date()
    @State private var isOngoing = true
    @State private var to = Date()
    @State private var existing: PauseReport?

    init(store: PauseReportStoring = UserDefaultsPauseReportStore()) {
        self.store = store
    }

    private var draft: PauseReport {
        PauseReport(
            kind: kind,
            from: PlanFormatting.isoDay(from),
            to: isOngoing ? nil : PlanFormatting.isoDay(to),
            reportedAt: Date()
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Grund", selection: $kind) {
                    ForEach(PauseReport.Kind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                DatePicker("Ab", selection: $from, displayedComponents: .date)
                Toggle("Dauert noch an", isOn: $isOngoing)
                if !isOngoing {
                    DatePicker("Bis einschließlich", selection: $to, in: from..., displayedComponents: .date)
                }
            } footer: {
                Text(footer)
            }

            Section {
                Button("Pause melden") { save() }
                    .disabled(draft.problem != nil)
                if let problem = draft.problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
            }

            if let existing {
                Section("Zuletzt gemeldet") {
                    LabeledContent(existing.kind.title, value: period(existing))
                    Button("Meldung löschen", role: .destructive) {
                        store.setReport(nil)
                        self.existing = nil
                    }
                }
            }
        }
        .navigationTitle("Pause melden")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { existing = store.report() }
    }

    private var footer: String {
        let days = draft.days()
        if draft.triggersReview() {
            return "Ab \(PauseReport.reviewDays) Tagen schreibt die App den Gesamtplan gleich fort. Das dauert ein bis drei Minuten, danach kommt eine Mitteilung."
        }
        return "\(days) Tage: Kürzere Pausen fängt der Plan der nächsten sieben Tage auf. Ab \(PauseReport.reviewDays) Tagen schreibt die App den Gesamtplan fort."
    }

    private func period(_ report: PauseReport) -> String {
        if let to = report.to { return "\(report.from) bis \(to)" }
        return "seit \(report.from)"
    }

    private func save() {
        let report = draft
        store.setReport(report)
        existing = store.report()
        if report.triggersReview(), let reading = todayLoader.reading {
            reviewRunner.startIfDue(reading: reading)
        }
        dismiss()
    }
}
