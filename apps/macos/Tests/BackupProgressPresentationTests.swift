import BackupEngine
import DeviceCapture
import Foundation
import Testing
@testable import CloakRoll

@Suite("Measured backup progress presentation")
struct BackupProgressPresentationTests {
    @Test("A known total starts at zero percent before any byte callback")
    func knownTotalStartsAtZero() {
        let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .downloading, totalAssets: 2, expectedBytes: 1_000,
            currentResourceExpectedBytes: 600
        ))
        #expect(progress.processedBytes == 0)
        #expect(progress.fraction == 0)
        #expect(progress.percentage == "0%")
        #expect(progress.byteSummary != nil)
        #expect(progress.title == "Backing Up…")
        #expect(progress.showsActivityIndicator)
    }

    @Test("An unknown or invalid total has no invented fraction or percentage")
    func unknownTotal() {
        let totals: [Int64] = [0, -1, .min]
        for total in totals {
            let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
                phase: .preparing, expectedBytes: total, verifiedBytes: 200,
                currentResourceBytes: 100, currentResourceExpectedBytes: 100
            ))
            #expect(progress.processedBytes == 0)
            #expect(progress.fraction == nil)
            #expect(progress.percentage == nil)
            #expect(progress.byteSummary == nil)
            #expect(progress.title == "Backing Up…")
            #expect(!progress.showsActivityIndicator)
        }
    }

    @Test("Mid-file data progress combines prior verified originals with actual received bytes")
    func measuredMidFile() {
        let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .downloading, totalAssets: 4, expectedBytes: 1_000, completedAssets: 1,
            verifiedBytes: 200, transferredBytes: 150,
            currentResourceBytes: 150, currentResourceExpectedBytes: 400
        ))
        #expect(progress.processedBytes == 350)
        #expect(progress.fraction == 0.35)
        #expect(progress.percentage == "35%")
        #expect(progress.itemSummary == "1 of 4 items backed up")
    }

    @Test("Entering verification retains measured data progress and the stable heading")
    func verificationRetainsReceivedBytes() {
        var snapshot = BackupSnapshot(
            phase: .downloading, totalAssets: 3, expectedBytes: 1_000, completedAssets: 1,
            verifiedBytes: 200, transferredBytes: 300,
            currentResourceBytes: 300, currentResourceExpectedBytes: 300
        )
        let downloading = BackupProgressPresentation(snapshot: snapshot)
        snapshot.phase = .verifying
        let verifying = BackupProgressPresentation(snapshot: snapshot)
        #expect(downloading.processedBytes == 500)
        #expect(verifying.processedBytes == downloading.processedBytes)
        #expect(verifying.fraction == downloading.fraction)
        #expect(verifying.percentage == "50%")
        #expect(verifying.title == downloading.title)
        #expect(verifying.title == "Backing Up…")
        #expect(verifying.showsActivityIndicator == downloading.showsActivityIndicator)
        #expect(verifying.showsActivityIndicator)
        #expect(verifying.itemSummary == "1 of 3 items backed up")
    }

    @Test("Moving a received original into verified bytes neither regresses nor counts it twice")
    func atomicRecordTransition() {
        let before = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, expectedBytes: 1_000, verifiedBytes: 200,
            currentResourceBytes: 300, currentResourceExpectedBytes: 300
        ))
        let after = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, expectedBytes: 1_000, verifiedBytes: 500,
            currentResourceBytes: 0, currentResourceExpectedBytes: 0
        ))
        let nextOriginal = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .downloading, expectedBytes: 1_000, verifiedBytes: 500,
            currentResourceBytes: 0, currentResourceExpectedBytes: 500
        ))
        #expect(before.processedBytes == 500)
        #expect(after.processedBytes == before.processedBytes)
        #expect(after.fraction == before.fraction)
        #expect(nextOriginal.fraction == after.fraction)
        #expect(nextOriginal.percentage == "50%")
        #expect(Set([before, after, nextOriginal].map(\.title)) == ["Backing Up…"])
        #expect([before, after, nextOriginal].allSatisfy { $0.showsActivityIndicator })
    }

    @Test("Reused originals advance progress without claiming new transferred bytes")
    func reusedOriginals() {
        let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, totalAssets: 4, expectedBytes: 1_000, completedAssets: 3,
            verifiedBytes: 750, transferredBytes: 0
        ))
        #expect(progress.processedBytes == 750)
        #expect(progress.percentage == "75%")
        #expect(progress.snapshot.transferredBytes == 0)
        #expect(progress.itemSummary == "3 of 4 items backed up")
        #expect(progress.showsActivityIndicator)
    }

    @Test("A full data meter still distinguishes verification and finalization from completion")
    func fullDataIsNotBackupCompletion() {
        let verifying = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, totalAssets: 1, expectedBytes: 1_000, completedAssets: 0,
            currentResourceBytes: 1_000, currentResourceExpectedBytes: 1_000
        ))
        #expect(verifying.percentage == "100%")
        #expect(verifying.title == "Backing Up…")
        #expect(verifying.itemSummary == "0 of 1 item backed up")
        #expect(verifying.showsActivityIndicator)
        let finishing = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .completed, totalAssets: 1, expectedBytes: 1_000, completedAssets: 1, verifiedBytes: 1_000
        ))
        #expect(finishing.percentage == "100%")
        #expect(finishing.title == "Backing Up…")
        #expect(finishing.showsActivityIndicator)
    }

    @Test("Stopping takes priority over phase text without discarding measured progress")
    func stoppingOverride() {
        for phase in [BackupPhase.preparing, .downloading, .verifying, .completed, .failed, .cancelled] {
            let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
                phase: phase, expectedBytes: 1_000, verifiedBytes: 200,
                currentResourceBytes: 150, currentResourceExpectedBytes: 400
            ), isStopping: true)
            #expect(progress.title == "Stopping Backup…")
            #expect(progress.showsActivityIndicator)
            #expect(progress.percentage == "35%")
        }
        let cancelling = BackupProgressPresentation(snapshot: BackupSnapshot(phase: .cancelling))
        #expect(cancelling.title == "Stopping Backup…")
        #expect(!cancelling.showsActivityIndicator)
    }

    @Test("Negative and oversized byte counters cannot escape the data meter bounds")
    func boundedCounters() {
        let cases: [(verified: Int64, received: Int64, resourceTotal: Int64, expected: Int64)] = [
            (-20, -10, 100, 0),
            (100, 200, 50, 150),
            (100, 200, -1, 100),
            (2_000, 400, 400, 1_000),
            (900, 400, 400, 1_000),
            (.min, .min, .min, 0)
        ]
        for values in cases {
            let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
                phase: .downloading, expectedBytes: 1_000, verifiedBytes: values.verified,
                currentResourceBytes: values.received, currentResourceExpectedBytes: values.resourceTotal
            ))
            #expect(progress.processedBytes == values.expected)
            #expect(progress.fraction.map { (0...1).contains($0) } == true)
        }
    }

    @Test("Combining counters at Int64.max does not overflow")
    func integerLimits() {
        let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, expectedBytes: .max, verifiedBytes: .max - 5,
            currentResourceBytes: .max, currentResourceExpectedBytes: .max
        ))
        #expect(progress.processedBytes == Int64.max)
        #expect(progress.fraction == 1)
        #expect(progress.percentage == "100%")
    }

    @Test("Whole percentages round down and remaining bytes never display one hundred percent")
    func floorPercentage() {
        let cases: [(Int64, String)] = [(1, "0%"), (999, "99%"), (1_000, "100%")]
        for (bytes, percentage) in cases {
            let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
                phase: .verifying, expectedBytes: 1_000, verifiedBytes: bytes
            ))
            #expect(progress.percentage == percentage)
        }
        let almostMaximum = BackupProgressPresentation(snapshot: BackupSnapshot(
            phase: .verifying, expectedBytes: .max, verifiedBytes: .max - 1
        ))
        #expect(almostMaximum.processedBytes == Int64.max - 1)
        // These adjacent Int64 values map to the same Double; byte equality still distinguishes them.
        #expect(almostMaximum.fraction == 1)
        #expect(almostMaximum.percentage == "99%")
    }

    @Test("Item counts are bounded, handle one item, and do not fabricate an unknown total")
    func boundedItemCounts() {
        let cases: [(total: Int, completed: Int, expected: String)] = [
            (0, 10, "Preparing items…"),
            (-5, 10, "Preparing items…"),
            (1, 0, "0 of 1 item backed up"),
            (1, 5, "1 of 1 item backed up"),
            (4, -1, "0 of 4 items backed up"),
            (4, 50, "4 of 4 items backed up")
        ]
        for values in cases {
            let progress = BackupProgressPresentation(snapshot: BackupSnapshot(
                totalAssets: values.total, completedAssets: values.completed
            ))
            #expect(progress.itemSummary == values.expected)
        }
    }

    @Test("Illustrative progress remains visible in History and disappears when disabled")
    @MainActor
    func sampleProgressVisibilityInHistory() {
        let model = AppModel(
            makeBrowser: { MockDeviceBrowserService() }, backup: LibraryBackupController()
        )
        model.navigation = .backupHistory
        #expect(!model.showsBackupBar)
        model.sampleProgress = true
        #expect(model.showsBackupBar)
        #expect(!model.backup.isBusy)
        #expect(model.backup.snapshot == nil)
        model.sampleProgress = false
        #expect(!model.showsBackupBar)
    }
}
