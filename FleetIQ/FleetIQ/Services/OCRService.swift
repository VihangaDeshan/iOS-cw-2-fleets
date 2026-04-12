//
//  OCRService.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Vision
import UIKit

// MARK: - OCR Result Model

/// Holds all fields extracted from an invoice or document.
struct OCRResult {
    var serviceDate: Date?
    var costLKR: Double?
    var mileageAtService: Double?
    var registration: String?
    var garageName: String?
    var expiryDate: Date?
}

// MARK: - OCR Service
final class OCRService {

    // MARK: - Shared
    static let shared = OCRService()

    // MARK: - Initializer

    /// Creates the singleton OCR service.
    private init() {}

    // MARK: - Text Recognition

    /// Processes a UIImage through VNRecognizeTextRequest.
    /// - Parameter image: Image to process.
    /// - Returns: Recognized text lines from top candidates.
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Invoice Field Extraction

    /// Extracts key invoice fields from OCR text lines.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Extracted invoice details.
    func extractInvoiceFields(from lines: [String]) -> OCRResult {
        var result = OCRResult()
        var costCandidates: [Double] = []
        var labeledCostCandidates: [Double] = []

        for line in lines {
            let lower = line.lowercased()

            if result.mileageAtService == nil,
               let mileage = extractMileage(from: line) {
                result.mileageAtService = mileage
            }

            let numbers = extractNumericValues(from: line)
            for number in numbers where number > 100 {
                if isLikelyCostLine(lower) {
                    labeledCostCandidates.append(number)
                } else if !isLikelyMileageLine(lower) {
                    costCandidates.append(number)
                }
            }

            if result.serviceDate == nil, let parsedDate = parseDate(from: line) {
                result.serviceDate = parsedDate
            }

            let platePattern = #"[A-Z]{1,3}[\s\-][A-Z]{0,4}[\s\-]?\d{3,4}"#
            if result.registration == nil,
               let match = line.uppercased().range(of: platePattern, options: .regularExpression) {
                result.registration = String(line.uppercased()[match]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        result.costLKR = (labeledCostCandidates.max() ?? costCandidates.max())
        result.garageName = extractGarageName(from: lines, registration: result.registration)

        return result
    }

    /// Infers service types from OCR text lines.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Detected service type labels matching app options.
    func extractServiceTypes(from lines: [String]) -> Set<String> {
        let joined = lines.joined(separator: " ").lowercased()
        var detected: Set<String> = []

        if containsAny(in: joined, keywords: ["full service", "major service", "periodic service"]) {
            detected.insert("Full Service")
        }

        if containsAny(in: joined, keywords: ["oil change", "engine oil", "oil filter", "lubricant"]) {
            detected.insert("Oil Change")
        }

        if containsAny(in: joined, keywords: ["brake", "brake pad", "brake disc", "rotor", "caliper"]) {
            detected.insert("Brake Service")
        }

        if containsAny(in: joined, keywords: ["tyre", "tire", "wheel alignment", "wheel balance"]) {
            detected.insert("Tyre")
        }

        if containsAny(in: joined, keywords: ["battery", "alternator", "terminal", "charging system"]) {
            detected.insert("Battery")
        }

        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("service type") || lower.contains("service:") else {
                continue
            }

            if containsAny(in: lower, keywords: ["oil"]) {
                detected.insert("Oil Change")
            }

            if containsAny(in: lower, keywords: ["brake"]) {
                detected.insert("Brake Service")
            }

            if containsAny(in: lower, keywords: ["full", "major"]) {
                detected.insert("Full Service")
            }

            if containsAny(in: lower, keywords: ["tyre", "tire"]) {
                detected.insert("Tyre")
            }

            if containsAny(in: lower, keywords: ["battery"]) {
                detected.insert("Battery")
            }
        }

        if detected.isEmpty && containsAny(in: joined, keywords: ["service", "garage", "workshop"]) {
            detected.insert("Other")
        }

        return detected
    }

    // MARK: - Document Expiry Extraction

    /// Extracts expiry date from OCR text lines.
    /// - Parameter lines: OCR text lines.
    /// - Returns: First best-matching expiry date.
    func extractExpiryDate(from lines: [String]) -> Date? {
        let keywords = [
            "expires", "expiry", "valid until", "valid to",
            "date of expiry", "expiration", "expire"
        ]

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let containsKeyword = keywords.contains { lower.contains($0) }

            if containsKeyword {
                if let date = parseDate(from: line) {
                    return date
                }

                if index + 1 < lines.count,
                   let date = parseDate(from: lines[index + 1]) {
                    return date
                }
            }
        }

        for line in lines {
            if let date = parseDate(from: line) {
                return date
            }
        }

        return nil
    }

    // MARK: - Date Parsing

    /// Tries multiple date formats against a text line.
    /// - Parameter line: OCR line to parse.
    /// - Returns: Parsed date if detected.
    private func parseDate(from line: String) -> Date? {
        let formats = [
            "dd/MM/yyyy", "d/M/yyyy",
            "dd-MM-yyyy", "d-M-yyyy",
            "dd.MM.yyyy",
            "dd MMM yyyy", "d MMM yyyy",
            "dd MMMM yyyy", "d MMMM yyyy",
            "yyyy-MM-dd",
            "MMM dd, yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format

            let pattern = #"\d{1,4}[\s/\-.][A-Za-z\d]{1,4}[\s/\-.]\d{2,4}"#
            if let match = line.range(of: pattern, options: .regularExpression) {
                if let date = formatter.date(from: String(line[match])) {
                    return date
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    /// Extracts all numeric values from a line, supporting comma-formatted and plain values.
    /// - Parameter line: OCR line text.
    /// - Returns: Parsed decimal values in scan order.
    private func extractNumericValues(from line: String) -> [Double] {
        let pattern = #"\d{4,7}(?:\.\d{1,2})?|\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d{1,3}(?:\.\d{1,2})?"#
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: line, options: [], range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: line) else {
                return nil
            }

            let raw = String(line[valueRange]).replacingOccurrences(of: ",", with: "")
            return Double(raw)
        }
    }

    /// Tries to detect odometer/mileage value from one OCR line.
    /// - Parameter line: OCR line.
    /// - Returns: Mileage value when confidently detected.
    private func extractMileage(from line: String) -> Double? {
        let lower = line.lowercased()
        guard isLikelyMileageLine(lower) else {
            return nil
        }

        let values = extractNumericValues(from: line)
        for value in values {
            if value >= 500, value <= 2_000_000 {
                return value.rounded()
            }
        }

        return nil
    }

    /// Picks best garage/workshop name from OCR lines using simple scoring heuristics.
    /// - Parameters:
    ///   - lines: OCR output lines.
    ///   - registration: Optional extracted vehicle registration to ignore.
    /// - Returns: Best candidate garage name.
    private func extractGarageName(from lines: [String], registration: String?) -> String? {
        var bestCandidate: String?
        var bestScore = Int.min

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else {
                continue
            }

            let lower = trimmed.lowercased()

            if parseDate(from: trimmed) != nil {
                continue
            }

            if let registration,
               trimmed.uppercased().contains(registration.uppercased()) {
                continue
            }

            // Prefer explicit labels such as "Garage: ABC Motors".
            if containsAny(in: lower, keywords: ["garage", "workshop", "service center", "service centre"]),
               let colonIndex = trimmed.firstIndex(of: ":") {
                let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 3 {
                    return value
                }
            }

            var score = 0

            if index < 6 {
                score += 2
            }

            if containsAny(in: lower, keywords: ["motors", "motor", "garage", "workshop", "auto", "automobile", "service center", "service centre", "pvt", "ltd"]) {
                score += 5
            }

            if containsAny(in: lower, keywords: ["invoice", "bill", "receipt", "customer", "vehicle", "reg", "plate", "total", "amount", "vat", "tax", "odo", "odometer", "mileage", "tel", "phone", "fax", "address", "date", "time", "cashier", "thank", "sub total"]) {
                score -= 4
            }

            if containsAny(in: lower, keywords: ["lkr", "rs", "km", "kms"]) {
                score -= 3
            }

            if trimmed.contains(where: { $0.isNumber }) {
                score -= 2
            }

            if score > bestScore {
                bestScore = score
                bestCandidate = trimmed
            }
        }

        guard bestScore > 0 else {
            return nil
        }

        return bestCandidate
    }

    /// Returns true when a line likely describes invoice total/cost values.
    private func isLikelyCostLine(_ lower: String) -> Bool {
        containsAny(in: lower, keywords: ["total", "amount", "grand total", "net total", "balance", "paid", "lkr", "rs"]) &&
            !containsAny(in: lower, keywords: ["odo", "odometer", "mileage", "km", "kms"])
    }

    /// Returns true when a line likely describes odometer reading.
    private func isLikelyMileageLine(_ lower: String) -> Bool {
        containsAny(in: lower, keywords: ["odo", "odometer", "mileage", "km", "kms", "km reading"])
    }

    /// Returns true when input text contains any given keyword.
    /// - Parameters:
    ///   - text: Normalized searchable text.
    ///   - keywords: Candidate keywords.
    /// - Returns: True if any keyword is present.
    private func containsAny(in text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - OCR Error

enum OCRError: LocalizedError {
    case invalidImage

    /// Localized error text for OCR failures.
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the selected image."
        }
    }
}
