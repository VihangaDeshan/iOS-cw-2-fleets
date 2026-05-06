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
        _ = try? await UNUserNotificationCenter.current()
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
        vehicleId: UUID,
        daysBefore: Int
    ) {
        let identifier =
            "expiry-\(vehicleId.uuidString)-\(documentType)-\(daysBefore)"
        let content = UNMutableNotificationContent()

        if daysBefore <= 0 {
            content.title = "Document Expired 🚨"
            content.body = "CRITICAL: \(vehicleRegistration) \(documentType) has EXPIRED! Immediate action required."
        } else if daysBefore <= 7 {
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

    /// Schedules 30-day, 7-day, and day-of expiry warnings.
    func scheduleAllExpiryWarnings(
        vehicleRegistration: String,
        documentType: String,
        expiryDate: Date,
        vehicleId: UUID
    ) {
        scheduleExpiryWarning(
            vehicleRegistration: vehicleRegistration,
            documentType: documentType,
            expiryDate: expiryDate,
            vehicleId: vehicleId,
            daysBefore: 30
        )
        scheduleExpiryWarning(
            vehicleRegistration: vehicleRegistration,
            documentType: documentType,
            expiryDate: expiryDate,
            vehicleId: vehicleId,
            daysBefore: 7
        )
        scheduleExpiryWarning(
            vehicleRegistration: vehicleRegistration,
            documentType: documentType,
            expiryDate: expiryDate,
            vehicleId: vehicleId,
            daysBefore: 0
        )
    }


    /// Cancels a pending notification.
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
    }

    // MARK: - Immediate Notifications (UNTimeIntervalNotificationTrigger)

    /// Fires 2 seconds after driver logs in via Face ID or email/password.
    func sendDriverWelcome(name: String) {
        let first = name.split(separator: " ")
            .first.map(String.init) ?? name
        let display = first.isEmpty ? "Driver" : first
        sendImmediate(
            title: "Welcome back, \(display) 👋",
            body: "Your vehicle status and fault history are ready.",
            identifier: "welcome-driver")
    }

    /// Fires to driver when manager updates their fault status.
    func sendFaultStatusUpdate(
        newStatus: String,
        description: String,
        faultId: UUID
    ) {
        let snippet = description.isEmpty
            ? "your fault report"
            : String(description.prefix(50))

        let normalized = newStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let title: String
        let body: String

        switch normalized {
        case "acknowledged":
            title = "Fault Acknowledged ✓"
            body  = "Your manager has seen: \(snippet)"
        case "workshop_booked", "workshop booked":
            title = "Workshop Booked 🔧"
            body  = "Manager booked a garage for: \(snippet)"
        case "in_progress", "in progress":
            title = "Repair In Progress 🛠"
            body  = "Your fault is being fixed: \(snippet)"
        case "resolved":
            title = "Fault Resolved ✅"
            body  = "Manager closed the fault: \(snippet)"
        default:
            return
        }

        sendImmediate(
            title: title,
            body: body,
            identifier: "fault-status-\(faultId.uuidString)")
    }

    /// Fires to manager when a driver submits a new fault report.
    func sendNewFaultToManager(
        vehicleReg: String,
        description: String,
        urgency: String
    ) {
        let snippet = description.isEmpty
            ? "A fault was submitted"
            : String(description.prefix(60))
        let urgencyText = urgency.lowercased() == "high"
            || urgency.lowercased() == "critical"
            ? "🚨 CRITICAL" : "⚠️ New"

        sendImmediate(
            title: "\(urgencyText) Fault — \(vehicleReg)",
            body: snippet,
            identifier: "new-fault-\(UUID().uuidString)")
    }

    /// Internal helper: fires a notification after 2 seconds.
    private func sendImmediate(
        title: String,
        body: String,
        identifier: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 2,
            repeats: false)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger))
    }
}
