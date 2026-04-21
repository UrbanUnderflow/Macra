//
//  MacraTests.swift
//  MacraTests
//
//  Created by Tremaine Grant on 8/29/23.
//

import XCTest
@testable import MacraFoodJournal

final class MacraTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testMacroRecommendationResolverFallsBackToLatestTargetWhenNoGlobalExists() {
        let olderTarget = MacroRecommendation(
            id: "monday",
            userId: "user-1",
            calories: 2100,
            protein: 160,
            carbs: 220,
            fat: 70,
            dayOfWeek: "mon",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let latestTarget = MacroRecommendation(
            id: "wednesday",
            userId: "user-1",
            calories: 2300,
            protein: 175,
            carbs: 240,
            fat: 75,
            dayOfWeek: "wed",
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = MacroRecommendationResolver.current(from: [olderTarget, latestTarget])

        XCTAssertEqual(resolved?.id, "wednesday")
    }

    func testMacroRecommendationResolverNormalizesDayAliases() {
        let globalTarget = MacroRecommendation(
            id: "global",
            userId: "user-1",
            calories: 2200,
            protein: 170,
            carbs: 230,
            fat: 72
        )
        let tuesdayTarget = MacroRecommendation(
            id: "tuesday",
            userId: "user-1",
            calories: 2400,
            protein: 180,
            carbs: 260,
            fat: 80,
            dayOfWeek: "tue"
        )

        let resolved = MacroRecommendationResolver.current(from: [globalTarget, tuesdayTarget], dayOfWeek: "tues")

        XCTAssertEqual(resolved?.id, "tuesday")
    }

}
