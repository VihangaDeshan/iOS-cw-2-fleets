//
//  VehicleOCRService.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import UIKit
import Vision

// MARK: - Vehicle OCR Document Type
enum VehicleOCRDocumentType {
    case registration
    case insurance
    case licence
}

// MARK: - Vehicle OCR Result
struct VehicleOCRResult {
    let registration: String?
    let make: String?
    let model: String?
    let year: Int16?
    let insuranceExpiry: Date?
    let licenceExpiry: Date?
    let lineCount: Int
}

// MARK: - Vehicle OCR Service
final class VehicleOCRService {
    // MARK: - Shared
    static let shared = VehicleOCRService()

    // MARK: - Initializer
    /// Creates the singleton OCR service.
    private init() {}

    // MARK: - Public API

    /// Reads visible text lines from an image using Apple Vision OCR.
    /// - Parameter image: Source image selected by user.
    /// - Returns: Array of recognized text lines.
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw VehicleOCRError.invalidImage
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

    /// Extracts vehicle fields from OCR lines based on the scanned document type.
    /// - Parameters:
    ///   - lines: OCR-recognized text lines.
    ///   - type: Type of scanned vehicle document.
    /// - Returns: Structured extracted values.
    func extractVehicleData(from lines: [String], type: VehicleOCRDocumentType) -> VehicleOCRResult {
        let normalizedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let registration = registrationFromLines(normalizedLines)
        let makeAndModel = makeAndModelFromLines(normalizedLines)
        let detectedYear = yearFromLines(normalizedLines)

        let insuranceExpiry: Date?
        let licenceExpiry: Date?

        switch type {
        case .insurance:
            insuranceExpiry = expiryDateFromLines(normalizedLines, keywords: ["insurance", "policy", "valid until", "expires", "expiry"])
            licenceExpiry = nil
        case .licence:
            insuranceExpiry = nil
            licenceExpiry = expiryDateFromLines(normalizedLines, keywords: ["licence", "license", "revenue", "valid until", "expires", "expiry"])
        case .registration:
            insuranceExpiry = nil
            licenceExpiry = nil
        }

        return VehicleOCRResult(
            registration: registration,
            make: makeAndModel.make,
            model: makeAndModel.model,
            year: detectedYear,
            insuranceExpiry: insuranceExpiry,
            licenceExpiry: licenceExpiry,
            lineCount: lines.count
        )
    }

    // MARK: - Parsing Helpers

    /// Finds the most likely Sri Lankan vehicle registration from OCR lines.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Normalized uppercase registration if found.
    private func registrationFromLines(_ lines: [String]) -> String? {
        let patterns = [
            #"\b[A-Z]{1,3}[\s-][A-Z]{1,4}[\s-]?\d{3,4}\b"#,
            #"\b[A-Z]{2,3}[\s-]?\d{4}\b"#
        ]

        for line in lines {
            let upper = line.uppercased()

            for pattern in patterns {
                if let range = upper.range(of: pattern, options: .regularExpression) {
                    let cleaned = String(upper[range])
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "  ", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned
                }
            }
        }

        return nil
    }

    /// Detects make and model from OCR text using known vehicle make names.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Tuple containing optional make and model.
    private func makeAndModelFromLines(_ lines: [String]) -> (make: String?, model: String?) {
        let knownMakes = [
            "Toyota", "Nissan", "Suzuki", "Honda", "Mitsubishi",
            "Mazda", "Hyundai", "Kia", "Isuzu", "Tata", "Mahindra"
        ]

        for line in lines {
            for make in knownMakes {
                if line.localizedCaseInsensitiveContains(make) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let makeRange = trimmed.range(of: make, options: .caseInsensitive)
                    let modelPart = makeRange.map { String(trimmed[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                    return (make: make, model: modelPart.isEmpty ? nil : modelPart)
                }
            }
        }

        return (make: nil, model: nil)
    }

    /// Detects a likely vehicle year from OCR text.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Year between 1980 and current year + 1.
    private func yearFromLines(_ lines: [String]) -> Int16? {
        let currentYear = Calendar.current.component(.year, from: Date()) + 1

        for line in lines {
            let pattern = #"\b(19\d{2}|20\d{2})\b"#
            guard let range = line.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let text = String(line[range])
            guard let yearValue = Int(text), (1980...currentYear).contains(yearValue) else {
                continue
            }

            return Int16(yearValue)
        }

        return nil
    }

    /// Extracts an expiry date using optional context keywords.
    /// - Parameters:
    ///   - lines: OCR text lines.
    ///   - keywords: Priority keywords that hint expiry information.
    /// - Returns: Parsed date if present.
    private func expiryDateFromLines(_ lines: [String], keywords: [String]) -> Date? {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let hasKeyword = keywords.contains { lower.contains($0) }

            guard hasKeyword else {
                continue
            }

            if let date = parseDate(from: line) {
                return date
            }

            if index + 1 < lines.count, let nextDate = parseDate(from: lines[index + 1]) {
                return nextDate
            }
        }

        for line in lines {
            if let date = parseDate(from: line) {
                return date
            }
        }

        return nil
    }

    /// Parses a date from mixed OCR text using multiple known formats.
    /// - Parameter line: OCR line to inspect.
    /// - Returns: Parsed date if recognized.
    private func parseDate(from line: String) -> Date? {
        let formats = [
            "dd/MM/yyyy", "d/M/yyyy",
            "dd-MM-yyyy", "d-M-yyyy",
            "dd.MM.yyyy",
            "dd MMM yyyy", "d MMM yyyy",
            "dd MMMM yyyy", "d MMMM yyyy",
            "yyyy-MM-dd", "MMM dd, yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let pattern = #"\d{1,4}[\s/\-.][A-Za-z\d]{1,4}[\s/\-.]\d{2,4}"#

        for format in formats {
            formatter.dateFormat = format

            if let range = line.range(of: pattern, options: .regularExpression) {
                let candidate = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let date = formatter.date(from: candidate) {
                    return date
                }
            }

            let full = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = formatter.date(from: full) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Vehicle OCR Error
enum VehicleOCRError: LocalizedError {
    case invalidImage

    /// Localized error description for invalid OCR image input.
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the selected image."
        }
    }
}
