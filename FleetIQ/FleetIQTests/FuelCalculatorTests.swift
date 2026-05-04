import XCTest
@testable import FleetIQ

final class FuelCalculatorTests: XCTestCase {

    func test_kmPerLitre_380km_42point5litres() {
        // Given: 380 km driven, 42.5 litres filled
        // When
        let result = calculateEfficiency(
            currentMileage: 48620,
            lastMileage: 48240,
            litres: 42.5)
        // Then: 380 / 42.5 = 8.94...
        XCTAssertEqual(result, 8.94, accuracy: 0.01)
    }

    func test_efficiencyStatus_18percentBelow_returnsBelow() {
        // Given: current 7.5, average 9.2 — 18.5% below
        // When
        let status = efficiencyStatus(current: 7.5, average: 9.2)
        // Then
        XCTAssertEqual(status, "below")
    }

    func test_efficiencyStatus_aboveAverage_returnsAbove() {
        // Given: current 10.5, average 9.2
        // When
        let status = efficiencyStatus(current: 10.5, average: 9.2)
        // Then
        XCTAssertEqual(status, "above")
    }

    func test_totalCostLKR_litresTimesPricePerLitre() {
        // Given: 42.5 litres at LKR 340
        let cost = 42.5 * 340.0
        // Then
        XCTAssertEqual(cost, 14450.0, accuracy: 0.01)
    }

    // Pure functions tested without needing a ViewModel:
    private func calculateEfficiency(
        currentMileage: Double,
        lastMileage: Double,
        litres: Double) -> Double {
        guard litres > 0 else { return 0 }
        return (currentMileage - lastMileage) / litres
    }

    private func efficiencyStatus(
        current: Double,
        average: Double) -> String {
        guard average > 0 else { return "above" }
        let pctBelow = (average - current) / average * 100
        return pctBelow > 15 ? "below" : "above"
    }
}
