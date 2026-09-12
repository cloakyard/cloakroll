import SwiftUI

private struct SamplePreview: View {
    let count: Int
    var state: DeviceViewState = .ready
    var progress = false
    @State private var model = AppModel()

    var body: some View {
        RootView().environment(model).tint(Design.accent)
            .frame(width: 1_100, height: 740)
            .task {
                await model.loadSample(count: count, state: state)
                model.sampleProgress = progress
            }
    }
}

#Preview("20 mixed items") { SamplePreview(count: 20) }
#Preview("1,200 items") { SamplePreview(count: 1_200) }
#Preview("No device") { SamplePreview(count: 0, state: .disconnected) }
#Preview("Restricted device") { SamplePreview(count: 0, state: .restricted) }
#Preview("Disconnected catalog") { SamplePreview(count: 20, state: .unavailable) }
#Preview("Backup progress sample") { SamplePreview(count: 20, progress: true) }
