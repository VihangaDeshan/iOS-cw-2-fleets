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
    case emission
}

// MARK: - Vehicle OCR Result
struct VehicleOCRResult {
    let registration: String?
    let make: String?
    let model: String?
    let year: Int16?
    let insuranceExpiry: Date?
    let licenceExpiry: Date?
    let emissionExpiry: Date?
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
        let emissionExpiry: Date?

        switch type {
        case .insurance:
            insuranceExpiry = expiryDateFromLines(normalizedLines, keywords: ["insurance", "policy", "valid until", "expires", "expiry"])
            licenceExpiry = nil
            emissionExpiry = nil
        case .licence:
            insuranceExpiry = nil
            licenceExpiry = expiryDateFromLines(normalizedLines, keywords: ["licence", "license", "revenue", "valid until", "expires", "expiry"])
            emissionExpiry = nil
        case .emission:
            insuranceExpiry = nil
            licenceExpiry = nil
            emissionExpiry = expiryDateFromLines(normalizedLines, keywords: ["emission", "emission test", "eco", "smoke", "valid until", "expires", "expiry"])
        case .registration:
            insuranceExpiry = nil
            licenceExpiry = nil
            emissionExpiry = nil
        }

        return VehicleOCRResult(
            registration: registration,
            make: makeAndModel.make,
            model: makeAndModel.model,
            year: detectedYear,
            insuranceExpiry: insuranceExpiry,
            licenceExpiry: licenceExpiry,
            emissionExpiry: emissionExpiry,
            lineCount: lines.count
        )
    }

    // MARK: - Parsing Helpers

    /// Finds the most likely vehicle registration from OCR lines.
    /// Tries label-based extraction first ("Registration Number: WP KA-5050"),
    /// then falls back to pattern scanning across all lines.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Normalized uppercase registration if found.
    private func registrationFromLines(_ lines: [String]) -> String? {
        let patterns = [
            #"\b[A-Z]{1,3}[\s-][A-Z]{1,4}[\s-]?\d{3,4}\b"#,
            #"\b[A-Z]{2,3}[\s-]?\d{4}\b"#
        ]

        func matchAndClean(_ text: String) -> String? {
            let upper = text.uppercased()
            for pattern in patterns {
                if let range = upper.range(of: pattern, options: .regularExpression) {
                    return String(upper[range])
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "  ", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        // Label-based extraction first — handles "Registration Number: WP KA-5050"
        // and split-line layouts where the value is on the next line.
        let regLabels = ["registration number", "registration no", "reg no", "plate number", "plate no"]
        for (i, _) in lines.enumerated() {
            if let labeled = extractLabeledValue(from: lines, at: i, labels: regLabels),
               let result = matchAndClean(labeled) {
                return result
            }
        }

        // Pattern-based fallback — scans every line for a plate-like token.
        for line in lines {
            if let result = matchAndClean(line) {
                return result
            }
        }

        return nil
    }

    /// Detects make and model from OCR text using known vehicle make names.
    /// Uses indexed iteration so label-only lines (e.g. "Model:") can pull the
    /// value from the following line — common in Philippines-style table layouts.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Tuple containing optional make and model.
    private func makeAndModelFromLines(_ lines: [String]) -> (make: String?, model: String?) {
        let knownMakes = [
            "Toyota", "Nissan", "Suzuki", "Honda", "Mitsubishi",
            "Mazda", "Hyundai", "Kia", "Isuzu", "Tata", "Mahindra"
        ]

        var extractedMake: String?
        var extractedModel: String?

        for (i, line) in lines.enumerated() {
            // 1. Combined label first — prevents "make" partially matching "Make/Model:"
            if let makeAndModel = extractLabeledValue(from: lines, at: i, labels: ["make & model", "make and model", "make/model"]) {
                let parsed = parseMakeAndModel(from: makeAndModel, knownMakes: knownMakes)
                if extractedMake == nil { extractedMake = parsed.make }
                if extractedModel == nil { extractedModel = parsed.model }
            }

            // 2. Individual "make" — start-of-line match avoids "Make/Model:" false hit
            if extractedMake == nil,
               let labeledMake = extractLabeledValue(from: lines, at: i, labels: ["make", "manufacturer", "brand"]) {
                let parsed = parseMakeAndModel(from: labeledMake, knownMakes: knownMakes)
                extractedMake = parsed.make ?? labeledMake
                if extractedModel == nil { extractedModel = parsed.model }
            }

            // 3. Individual "model" — skip lines starting with "year" so "Year Model: 2021"
            //    (Philippines format) never pollutes the model field with a year value.
            if extractedModel == nil {
                let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !lower.hasPrefix("year"),
                   let labeledModel = extractLabeledValue(from: lines, at: i, labels: ["model", "model no", "model number", "vehicle model"]) {
                    extractedModel = labeledModel
                }
            }

            // 4. Fallback: scan line for a known make name
            for make in knownMakes {
                if line.localizedCaseInsensitiveContains(make) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let makeRange = trimmed.range(of: make, options: .caseInsensitive)
                    let modelPart = makeRange.map { String(trimmed[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                    if extractedMake == nil { extractedMake = make }
                    if extractedModel == nil, !modelPart.isEmpty { extractedModel = modelPart }
                }
            }
        }

        return (
            make: extractedMake?.trimmingCharacters(in: .whitespacesAndNewlines),
            model: extractedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Matches a label at the start of a line and returns the value that follows it.
    /// Longest label is tried first to prevent "model" from matching "model no" lines.
    /// The character after the label must be a separator (`:`, space, or end-of-line) so
    /// "make" does not partially match "Make/Model:" and "model" does not match "Year Model:".
    private func labeledValueAtStart(in line: String, labels: [String]) -> String? {
        let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedLabels = labels.sorted { $0.count > $1.count }

        for label in sortedLabels {
            guard lower.hasPrefix(label) else { continue }

            let afterLabel = lower.dropFirst(label.count)
            let firstChar = afterLabel.first
            guard firstChar == nil || firstChar == ":" || firstChar == " " || firstChar == "\t" else { continue }

            let suffix = line.dropFirst(label.count)
            let cleaned = suffix
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleaned.isEmpty { return String(cleaned) }
        }

        return nil
    }

    /// Returns the value for a labeled field, checking the same line first,
    /// then the next line when the current line contains only the label (e.g. "Model:").
    /// This handles table layouts where OCR splits label and value across two lines.
    private func extractLabeledValue(from lines: [String], at index: Int, labels: [String]) -> String? {
        let line = lines[index]

        if let value = labeledValueAtStart(in: line, labels: labels) {
            return value
        }

        // Check if line is label-only (value may be on the next line)
        let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedLabels = labels.sorted { $0.count > $1.count }
        for label in sortedLabels {
            guard lower.hasPrefix(label) else { continue }
            let afterLabel = lower.dropFirst(label.count)
            let firstChar = afterLabel.first
            guard firstChar == nil || firstChar == ":" || firstChar == " " || firstChar == "\t" else { continue }
            let remaining = String(afterLabel).replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            guard remaining.isEmpty else { continue }
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty { return next }
            }
        }

        return nil
    }

    /// Parses a combined make/model text into separate values.
    /// - Parameters:
    ///   - text: Combined make and model candidate.
    ///   - knownMakes: Supported makes for detection.
    /// - Returns: Parsed make and optional model.
    private func parseMakeAndModel(from text: String, knownMakes: [String]) -> (make: String?, model: String?) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for make in knownMakes {
            guard let makeRange = cleaned.range(of: make, options: .caseInsensitive) else {
                continue
            }

            let modelPart = cleaned[makeRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (make: make, model: modelPart.isEmpty ? nil : String(modelPart))
        }

        return (make: nil, model: cleaned.isEmpty ? nil : cleaned)
    }

    /// Detects the vehicle manufacture/model year from OCR text.
    /// Tries labeled fields first ("Year Model:", "Year of Manufacture:") so that
    /// garbled footer text or OCR-corrected strings with a different year-like number
    /// cannot shadow the clearly labeled year field.
    /// - Parameter lines: OCR text lines.
    /// - Returns: Year between 1980 and current year + 1.
    private func yearFromLines(_ lines: [String]) -> Int16? {
        let currentYear = Calendar.current.component(.year, from: Date()) + 1
        let yearPattern = #"\b(19\d{2}|20\d{2})\b"#

        func extractYear(from text: String) -> Int16? {
            guard let range = text.range(of: yearPattern, options: .regularExpression),
                  let value = Int(text[range]),
                  (1980...currentYear).contains(value) else { return nil }
            return Int16(value)
        }

        // Label-based extraction first — "Year Model: 2018" must win over any stray year elsewhere
        let yearLabels = ["year model", "year of manufacture", "manufacture year", "model year", "year"]
        for (i, _) in lines.enumerated() {
            if let labeled = extractLabeledValue(from: lines, at: i, labels: yearLabels),
               let year = extractYear(from: labeled) {
                return year
            }
        }

        // Pattern-based fallback — scan all lines for the first plausible year
        for line in lines {
            if let year = extractYear(from: line) { return year }
        }

        return nil
    }

    /// Extracts an expiry date using optional context keywords.
    /// - Parameters:
    ///   - lines: OCR text lines.
    ///   - keywords: Priority keywords that hint expiry information.
    /// - Returns: Parsed date if present.
    private func expiryDateFromLines(_ lines: [String], keywords: [String]) -> Date? {
        let expiryLabels = ["valid until", "expires", "expiry date", "expiry", "valid to"]

        // Quick win: expiry label and its date are on the same OCR line.
        // e.g. "Valid Until: 27 OCT 2024" → return 27 OCT 2024 immediately.
        for line in lines {
            let lower = line.lowercased()
            guard expiryLabels.contains(where: { lower.contains($0) }) else { continue }
            if let date = allDates(from: line).max() { return date }
        }

        // Document-type keyword window for date ranges like
        // "Effective from 01/10/2023 to 30/09/2024" where both dates sit close together.
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard keywords.contains(where: { lower.contains($0) }) else { continue }
            let end = min(index + 8, lines.count)
            let dates = lines[index..<end].flatMap { allDates(from: $0) }
            if let latest = dates.max() { return latest }
        }

        // Final fallback: on any compliance document the expiry is always the
        // latest date present — test dates and issue dates always predate it.
        return lines.flatMap { allDates(from: $0) }.max()
    }

    /// Returns the latest date found in a single OCR line, handling date-range patterns.
    private func latestDate(from line: String) -> Date? {
        allDates(from: line).max()
    }

    /// Finds every parseable date in a single OCR line.
    private func allDates(from line: String) -> [Date] {
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
        var dates: [Date] = []
        var searchRange = line.startIndex..<line.endIndex

        while let range = line.range(of: pattern, options: .regularExpression, range: searchRange) {
            let candidate = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: candidate) {
                    dates.append(date)
                    break
                }
            }
            searchRange = range.upperBound..<line.endIndex
        }

        return dates
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
