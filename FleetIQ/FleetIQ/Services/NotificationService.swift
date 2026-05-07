
import Foundation
import UserNotifications
import UIKit

final class NotificationService {
    static let shared = NotificationService()
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppBackground() {
        resetSessionState()
    }

    /// Clears session-based deduplication so all notifications can re-fire.
    /// Called on app background and on Face ID unlock.
    func resetSessionState() {
        firedSessionExpiries.removeAll()
        firedSessionFaults.removeAll()
        hasFiredDriverWelcome = false
        hasFiredManagerWelcome = false
        nextNotificationDelay = 2.0
    }

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
            daysBefore: 14
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

    // MARK: - Expiry Reschedule on App Open

    /// Call this whenever a document is loaded from CoreData or Firestore.
    /// Fires an immediate "EXPIRED" push if the date is already past (at most once per day),
    /// or reschedules the standard 30/7/0-day calendar warnings for future dates.
    // Tracks which expiry warnings have fired during this specific app session.
    // Maps the session key to the exact expiry date that fired it.
    // This resets when the app is fully closed and reopened.
    private var firedSessionExpiries: [String: Date] = [:]
    private var firedSessionFaults = Set<String>()

    func fireManagerFaultIfNeeded(
        vehicleReg: String,
        description: String,
        urgency: String,
        faultId: UUID
    ) {
        let sessionKey = "fault-\(faultId.uuidString)"
        if !firedSessionFaults.contains(sessionKey) {
            firedSessionFaults.insert(sessionKey)
            sendNewFaultToManager(
                vehicleReg: vehicleReg,
                description: description,
                urgency: urgency
            )
        }
    }

    func rescheduleExpiryIfNeeded(
        vehicleRegistration: String,
        documentType: String,
        expiryDate: Date,
        vehicleId: UUID
    ) {
        let daysUntil = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: expiryDate)).day ?? Int.min

        let sessionKey = "expiry-\(vehicleId.uuidString)-\(documentType)"

        if daysUntil <= 30 {
            // Ensure this specific notification only fires ONCE per app session for a specific date.
            let lastFiredDate = firedSessionExpiries[sessionKey]
            
            if lastFiredDate != expiryDate {
                firedSessionExpiries[sessionKey] = expiryDate
                
                if daysUntil < 0 {
                    sendImmediate(
                        title: "Document Expired 🚨",
                        body: "\(vehicleRegistration) \(documentType) has EXPIRED \(abs(daysUntil)) day(s) ago! Renew immediately.",
                        identifier: sessionKey)
                } else if daysUntil <= 7 {
                    sendImmediate(
                        title: "URGENT: Document Expiring",
                        body: "URGENT: \(vehicleRegistration) \(documentType) expires in \(daysUntil) days!",
                        identifier: sessionKey)
                } else if daysUntil <= 14 {
                    sendImmediate(
                        title: "Document Expiring Soon",
                        body: "\(vehicleRegistration) \(documentType) expires in \(daysUntil) days. Please arrange renewal.",
                        identifier: sessionKey)
                } else {
                    sendImmediate(
                        title: "Document Expiry Warning",
                        body: "\(vehicleRegistration) \(documentType) expires in \(daysUntil) days. Renew now to avoid fines.",
                        identifier: sessionKey)
                }
            }
        } else {
            // If the user updates the document to a healthy future date, clear the session lock.
            // This allows the push notification to fire again if they set it back to an expired date for testing/demos.
            firedSessionExpiries.removeValue(forKey: sessionKey)
        }

        // Reschedule standard background warnings.
        // Past-dated calendar triggers are silently dropped by iOS, so this is safe.
        scheduleAllExpiryWarnings(
            vehicleRegistration: vehicleRegistration,
            documentType: documentType,
            expiryDate: expiryDate,
            vehicleId: vehicleId)
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Immediate Notifications (UNTimeIntervalNotificationTrigger)

    private var hasFiredDriverWelcome = false
    private var hasFiredManagerWelcome = false

    /// Fires 2 seconds after driver logs in via Face ID or email/password.
    func sendDriverWelcome(name: String) {
        guard !hasFiredDriverWelcome else { return }
        hasFiredDriverWelcome = true
        
        let first = name.split(separator: " ")
            .first.map(String.init) ?? name
        let display = first.isEmpty ? "Driver" : first
        sendImmediate(
            title: "Welcome back, \(display) 👋",
            body: "Your vehicle status and fault history are ready.",
            identifier: "welcome-driver")
    }

    /// Fires 2 seconds after manager logs in via Face ID or email/password.
    func sendManagerWelcome(name: String) {
        guard !hasFiredManagerWelcome else { return }
        hasFiredManagerWelcome = true
        
        let first = name.split(separator: " ")
            .first.map(String.init) ?? name
        let display = first.isEmpty ? "Manager" : first
        sendImmediate(
            title: "Welcome back, \(display) 👋",
            body: "Your fleet dashboard and critical alerts are ready.",
            identifier: "welcome-manager")
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

    /// Internal helper: fires a notification sequentially.
    private var nextNotificationDelay: TimeInterval = 2.0

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
            timeInterval: nextNotificationDelay,
            repeats: false)
            
        nextNotificationDelay += 1.5 // Stagger multiple notifications

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [identifier])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(
                withIdentifiers: [identifier])
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger))
    }
}
