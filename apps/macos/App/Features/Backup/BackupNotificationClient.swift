import Foundation
import UserNotifications

enum BackupNotificationPermission: Sendable { case unknown, allowed, denied }

struct BackupNotice: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
    var deliveryDate: Date?
}

struct BackupNotificationClient: Sendable {
    var permission: @Sendable () async -> BackupNotificationPermission
    var authorize: @Sendable () async throws -> Bool
    var add: @Sendable (BackupNotice) async throws -> Void
    var remove: @Sendable ([String]) async -> Void

    static let system = Self(
        permission: {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional: .allowed
            case .denied: .denied
            default: .unknown
            }
        },
        authorize: { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) },
        add: { notice in
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            let trigger = notice.deliveryDate.map {
                UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false)
            }
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger)
            )
        },
        remove: { ids in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    )

    static let disabled = Self(permission: { .denied }, authorize: { false }, add: { _ in }, remove: { _ in })
}
