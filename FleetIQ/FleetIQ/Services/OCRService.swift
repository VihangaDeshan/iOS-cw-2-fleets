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
        var allNumbers: [Double] = []

        for line in lines {
            let costPattern = #"\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#
            if let match = line.range(of: costPattern, options: .regularExpression) {
                let value = String(line[match]).replacingOccurrences(of: ",", with: "")
                if let number = Double(value), number > 100 {
                    allNumbers.append(number)
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

        result.costLKR = allNumbers.max()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 3 {
                continue
            }

            if trimmed.contains(where: { $0.isNumber }) {
                continue
            }

            if parseDate(from: trimmed) != nil {
                continue
            }

            if result.registration != nil,
               trimmed.uppercased().contains(result.registration!.uppercased()) {
                continue
            }

            result.garageName = trimmed
            break
        }

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
