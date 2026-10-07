import SwiftUI

/// The same native commands are available from date labels, assistive actions and the menu bar.
struct DateGroupSelectionActions: View {
    let model: AppModel
    let target: DateGroupSelectionTarget?
    var didSelect: () -> Void = {}

    var body: some View {
        let state = target.flatMap { model.dateGroupState(for: $0) }
        Button("Select Date Group") { apply(true) }
            .disabled(state?.canSelect != true)
        Button("Deselect Date Group") { apply(false) }
            .disabled(state?.canDeselect != true)
    }

    private func apply(_ selected: Bool) {
        guard let target else { return }
        model.setDateGroupSelected(selected, target: target)
        didSelect()
    }
}
