import MediaModels
import SwiftUI

struct CaptureDateFilterButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Button { model.dateFilterPresented.toggle() } label: {
            Label("Filter by Capture Date", systemImage: model.captureDateRange == nil ? "calendar" : "calendar.badge.checkmark")
        }
        .help(model.captureDateRange.map { "Capture date: \($0.displayTitle)" } ?? "Filter by capture date")
        .accessibilityValue(model.captureDateRange?.displayTitle ?? "All dates")
        .popover(isPresented: $model.dateFilterPresented, arrowEdge: .bottom) {
            CaptureDateFilterView(range: model.captureDateRange) { range in
                model.captureDateRange = range
                model.dateFilterPresented = false
            }
        }
    }
}

private struct CaptureDateFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var through: Date
    let range: CaptureDateRange?
    let apply: (CaptureDateRange?) -> Void

    init(range: CaptureDateRange?, apply: @escaping (CaptureDateRange?) -> Void) {
        self.range = range
        self.apply = apply
        let today = Calendar.current.startOfDay(for: Date())
        _from = State(initialValue: range?.from ?? Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today)
        _through = State(initialValue: range?.through ?? today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture Date").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("From")
                    DatePicker("From", selection: $from, displayedComponents: .date).labelsHidden()
                }
                GridRow {
                    Text("Through")
                    DatePicker("Through", selection: $through, displayedComponents: .date).labelsHidden()
                }
            }
            HStack {
                Menu("Quick Dates") {
                    Button("Today") { choose(days: 1) }
                    Button("Last 7 Days") { choose(days: 7) }
                    Button("Last 30 Days") { choose(days: 30) }
                    Button("This Month") {
                        through = Date()
                        from = Calendar.current.dateInterval(of: .month, for: through)?.start ?? through
                    }
                }
                .fixedSize()
                Spacer()
                if range != nil { Button("Clear Filter") { apply(nil) } }
            }
            Text(candidate == nil
                 ? "Choose an end date on or after the start date."
                 : "Includes both dates. Items without a capture date are hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { if let candidate { apply(candidate) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(candidate == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var candidate: CaptureDateRange? { CaptureDateRange(from: from, through: through) }

    private func choose(days: Int) {
        through = Date()
        from = Calendar.current.date(byAdding: .day, value: 1 - days, to: through) ?? through
    }
}

extension CaptureDateRange {
    var displayTitle: String {
        if from == through { return from.formatted(date: .abbreviated, time: .omitted) }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: from, to: through)
    }
}
