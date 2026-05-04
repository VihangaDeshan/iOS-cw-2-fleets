//
//  NotificationService.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-05-04.
//

import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    /// Requests notification permission from user.
    /// Call once on app first launch.
    func requestPermission() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(
                options: [.alert, .badge, .sound])
    }

    /// Schedules service due alert 14 days before date.
    /// Identifier: "service-{vehicleId}"
    /// Replaces any existing notification with same ID.
    func scheduleServiceDue(
        vehicleRegistration: String,
        predictedDate: Date,
        vehicleId: UUID
    ) {
        let identifier = "service-\(vehicleId.uuidString)"
        let content = UNMutableNotificationContent()
        content.title = "Service Due Soon"
        content.body = "\(vehicleRegistration) is due for service in 14 days. Contact your garage to schedule."
        content.sound = .default

        guard let triggerDate = Calendar.current.date(
            byAdding: .day,
            value: -14,
            to: predictedDate)
        else { return }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
        UNUserNotificationCenter.current()
            .add(request)
    }

    /// Schedules document expiry warning.
    /// Pass daysBefore as 30 or 7.
    /// Identifier: "expiry-{documentId}-{daysBefore}"
    func scheduleExpiryWarning(
        vehicleRegistration: String,
        documentType: String,
        expiryDate: Date,
        documentId: UUID,
        daysBefore: Int
    ) {
        let identifier =
            "expiry-\(documentId.uuidString)-\(daysBefore)"
        let content = UNMutableNotificationContent()

        if daysBefore <= 7 {
            content.title = "URGENT: Document Expiring"
            content.body = "URGENT: \(vehicleRegistration) \(documentType) expires in \(daysBefore) days!"
        } else {
            content.title = "Document Expiry Warning"
            content.body = "\(vehicleRegistration) \(documentType) expires in \(daysBefore) days. Renew now to avoid fines."
        }
        content.sound = .default

        guard let triggerDate = Calendar.current.date(
            byAdding: .day,
            value: -daysBefore,
            to: expiryDate)
        else { return }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
        UNUserNotificationCenter.current()
            .add(request)
    }

    /// Cancels a pending notification.
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
    }
}
