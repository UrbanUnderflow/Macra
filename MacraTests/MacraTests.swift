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

    func testNoraAnalysisParsesDoubleEncodedJSONContent() throws {
        let rawJSON = Self.noraAnalysisJSON()
        let encoded = try XCTUnwrap(String(
            data: JSONEncoder().encode(rawJSON),
            encoding: .utf8
        ))

        let analysis = try GPTService.parseNoraAnalysisJSON(encoded)

        XCTAssertEqual(analysis.macros.calories, 2100)
        XCTAssertEqual(analysis.macros.protein, 180)
        XCTAssertEqual(analysis.planName, "Prep day")
        XCTAssertEqual(analysis.meals.first?.items.first?.name, "Chicken breast")
    }

    func testNoraAnalysisParsesFencedJSONContent() throws {
        let raw = """
        ```json
        \(Self.noraAnalysisJSON())
        ```
        """

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.macros.carbs, 220)
        XCTAssertEqual(analysis.meals.first?.title, "Meal 1")
    }

    func testNoraAnalysisParsesOpenAIWrappedContent() throws {
        let envelope: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": Self.noraAnalysisJSON()
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [])
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.summary, "Daily target for current goal.")
        XCTAssertEqual(analysis.macros.fat, 60)
    }

    func testNoraAnalysisParsesScopedMacroTargets() throws {
        let raw = """
        {
          "summary": "Default plan with Fri/Sat substitution.",
          "macros": {
            "calories": 2400,
            "protein": 240,
            "carbs": 220,
            "fat": 70,
            "rationale": "Default plan total."
          },
          "scopedMacros": [
            {
              "label": "Fri & Sat substitution",
              "days": ["fri", "sat"],
              "macros": {
                "calories": 2520,
                "protein": 246,
                "carbs": 245,
                "fat": 74,
                "rationale": "Cream of rice substitution changes the day total."
              }
            }
          ],
          "mealPlan": {
            "name": "Prep plan",
            "meals": []
          }
        }
        """

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.macros.calories, 2400)
        XCTAssertEqual(analysis.scopedMacros.count, 1)
        XCTAssertEqual(analysis.scopedMacros.first?.days, ["fri", "sat"])
        XCTAssertEqual(analysis.scopedMacros.first?.macros.calories, 2520)
    }

    func testNoraAnalysisCorrectsCombinedPrepMealMacros() throws {
        let raw = """
        {
          "summary": "Prep meals from pasted plan.",
          "macros": {
            "calories": 2400,
            "protein": 240,
            "carbs": 220,
            "fat": 70,
            "rationale": "Default plan total."
          },
          "scopedMacros": [],
          "mealPlan": {
            "name": "Prep plan",
            "meals": [
              {
                "title": "Meal 1",
                "notes": null,
                "items": [
                  {
                    "name": "1 cup egg white + 1 whole egg, spinach, cream of rice(1 scoop)",
                    "quantity": "",
                    "calories": 210,
                    "protein": 26,
                    "carbs": 20,
                    "fat": 5
                  }
                ]
              },
              {
                "title": "Meal 3",
                "notes": null,
                "items": [
                  {
                    "name": "7 oz ground turkey + 2 oz vegetables + 250 g jasmine rice",
                    "quantity": "",
                    "calories": 740,
                    "protein": 56,
                    "carbs": 95,
                    "fat": 14
                  }
                ]
              }
            ]
          }
        }
        """

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)
        let mealOne = try XCTUnwrap(analysis.meals.first)
        let mealThree = try XCTUnwrap(analysis.meals.dropFirst().first)

        XCTAssertEqual(mealOne.items.count, 4)
        XCTAssertEqual(mealOne.totalCalories, 333)
        XCTAssertEqual(mealOne.totalProtein, 35)
        XCTAssertEqual(mealOne.totalCarbs, 31)
        XCTAssertEqual(mealOne.totalFat, 5)

        XCTAssertEqual(mealThree.items.count, 3)
        XCTAssertEqual(mealThree.totalCalories, 646)
        XCTAssertEqual(mealThree.totalProtein, 57)
        XCTAssertEqual(mealThree.totalCarbs, 75)
        XCTAssertEqual(mealThree.totalFat, 15)
    }

    func testMealAnalysisUsesSharedPrepMacroCorrection() throws {
        let raw = """
        {
          "name": "Prep breakfast",
          "calories": 210,
          "protein": 26,
          "carbs": 20,
          "fat": 5,
          "fiber": null,
          "sugarAlcohols": null,
          "ingredients": [
            {
              "name": "1 cup egg white + 1 whole egg, spinach, cream of rice(1 scoop)",
              "quantity": "",
              "calories": 210,
              "protein": 26,
              "carbs": 20,
              "fat": 5,
              "fiber": null,
              "sugarAlcohols": null
            }
          ]
        }
        """

        let analysis = try GPTService.parseMealAnalysisJSON(raw)

        XCTAssertEqual(analysis.ingredients.count, 4)
        XCTAssertEqual(analysis.calories, 333)
        XCTAssertEqual(analysis.protein, 35)
        XCTAssertEqual(analysis.carbs, 31)
        XCTAssertEqual(analysis.fat, 5)
    }

    func testNoraAnalysisRepairsControlCharactersInsideStrings() throws {
        let raw = Self.noraAnalysisJSON()
            .replacingOccurrences(
                of: "Keeps protein high while supporting training.",
                with: "Keeps protein high\nwhile supporting training."
            )

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.macros.rationale, "Keeps protein high\nwhile supporting training.")
    }

    func testNoraAnalysisParsesJSON5TrailingCommas() throws {
        let raw = """
        {
          "summary": "Daily target for current goal.",
          "macros": {
            "calories": 2100,
            "protein": 180,
            "carbs": 220,
            "fat": 60,
            "rationale": "Keeps protein high while supporting training.",
          },
          "mealPlan": {
            "name": "Prep day",
            "meals": [],
          },
        }
        """

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.macros.calories, 2100)
        XCTAssertTrue(analysis.meals.isEmpty)
    }

    func testNoraAnalysisFallsBackToMacroOnlyWhenMealPlanIsMalformed() throws {
        let raw = """
        {
          "summary": "Daily target for current goal.",
          "macros": {
            "calories": 2,100,
            "protein": 180,
            "carbs": 220,
            "fat": 60,
            "rationale": "Keeps protein high while supporting training."
          },
          "mealPlan": {
            "name": "Prep day",
            "meals": [
              {
                "title": "Meal 1",
                "items": [
                  { "name": "Chicken breast", "calories": 230g }
                ]
              }
            ]
          }
        }
        """

        let analysis = try GPTService.parseNoraAnalysisJSON(raw)

        XCTAssertEqual(analysis.macros.calories, 2100)
        XCTAssertEqual(analysis.macros.protein, 180)
        XCTAssertEqual(analysis.planName, "Prep day")
        XCTAssertTrue(analysis.meals.isEmpty)
    }

    func testNoraMacrosOnlySavesScopedDayTargets() {
        let store = InMemoryMealPlanningStore()
        let viewModel = MacroTargetsViewModel(userId: "user-1", store: store)
        let analysis = GPTService.NoraMacroAnalysis(
            summary: "Default plan with Fri/Sat substitution.",
            macros: GPTService.NoraMacroAnalysis.Macros(
                calories: 2400,
                protein: 240,
                carbs: 220,
                fat: 70,
                rationale: "Default plan total."
            ),
            scopedMacros: [
                GPTService.NoraMacroAnalysis.ScopedMacros(
                    label: "Fri & Sat substitution",
                    days: ["fri", "sat"],
                    macros: GPTService.NoraMacroAnalysis.Macros(
                        calories: 2520,
                        protein: 246,
                        carbs: 245,
                        fat: 74,
                        rationale: "Substitution total."
                    )
                )
            ],
            planName: "Prep plan",
            meals: []
        )
        let saveExpectation = expectation(description: "saved scoped macros")

        viewModel.applyNoraMacrosOnly(from: analysis) {
            store.fetchMacroRecommendations(userId: "user-1") { result in
                guard case .success(let recommendations) = result else {
                    XCTFail("Expected saved recommendations")
                    saveExpectation.fulfill()
                    return
                }

                let global = recommendations.first(where: { $0.dayOfWeek == nil })
                let friday = recommendations.first(where: { $0.dayOfWeek == "fri" })
                let saturday = recommendations.first(where: { $0.dayOfWeek == "sat" })

                XCTAssertEqual(global?.calories, 2400)
                XCTAssertEqual(friday?.calories, 2520)
                XCTAssertEqual(saturday?.carbs, 245)
                saveExpectation.fulfill()
            }
        }

        wait(for: [saveExpectation], timeout: 1)
    }

    private static func noraAnalysisJSON() -> String {
        """
        {
          "summary": "Daily target for current goal.",
          "macros": {
            "calories": 2100,
            "protein": 180,
            "carbs": 220,
            "fat": 60,
            "rationale": "Keeps protein high while supporting training."
          },
          "scopedMacros": [],
          "mealPlan": {
            "name": "Prep day",
            "meals": [
              {
                "title": "Meal 1",
                "notes": null,
                "items": [
                  {
                    "name": "Chicken breast",
                    "quantity": "5 oz",
                    "calories": 230,
                    "protein": 44,
                    "carbs": 0,
                    "fat": 5
                  }
                ]
              }
            ]
          }
        }
        """
    }

}
