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

    func testUpdateModalTreatsLeadingZeroVersionSegmentsAsOlder() throws {
        XCTAssertEqual(MacraVersionService.compareVersionStrings("6.01", "6.1"), .orderedAscending)

        XCTAssertTrue(
            MacraVersionService.shouldShowUpdate(
                installedVersion: "6.01",
                installedBuild: "1",
                latestVersion: "6.1",
                latestBuild: nil,
                lastSeenReleaseKey: "6.01 (1)",
                isCriticalUpdate: false
            )
        )

        XCTAssertFalse(
            MacraVersionService.shouldShowUpdate(
                installedVersion: "6.1",
                installedBuild: "1",
                latestVersion: "6.01",
                latestBuild: nil,
                lastSeenReleaseKey: "6.0",
                isCriticalUpdate: true
            )
        )
    }

    func testUpdateModalDoesNotShowWhenInstalledReleaseMatchesLatestRelease() throws {
        XCTAssertFalse(
            MacraVersionService.shouldShowUpdate(
                installedVersion: "6.01",
                installedBuild: "12",
                latestVersion: "6.01",
                latestBuild: "12",
                lastSeenReleaseKey: "6.0",
                isCriticalUpdate: true
            )
        )
    }

    func testUpdateModalUsesBuildNumberWhenVersionMatches() throws {
        XCTAssertTrue(
            MacraVersionService.shouldShowUpdate(
                installedVersion: "6.01",
                installedBuild: "12",
                latestVersion: "6.01",
                latestBuild: "13",
                lastSeenReleaseKey: "6.01 (12)",
                isCriticalUpdate: false
            )
        )

        XCTAssertFalse(
            MacraVersionService.shouldShowUpdate(
                installedVersion: "6.01",
                installedBuild: "14",
                latestVersion: "6.01",
                latestBuild: "13",
                lastSeenReleaseKey: "6.0",
                isCriticalUpdate: true
            )
        )
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

    func testPlanHubImageMatcherRejectsFishPhotoForChickenMeal() async {
        let tilapiaPhotoMeal = Self.matchCandidateMeal(
            name: "Tilapia",
            ingredients: ["jasmine rice", "asparagus"],
            image: "https://example.com/tilapia.jpg"
        )
        let indexed = [(meal: tilapiaPhotoMeal, tokens: Set(["tilapia", "jasmine", "rice", "asparagu"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["chicken", "breast", "jasmine", "rice"]),
                in: indexed
            )
        }

        XCTAssertNil(match)
    }

    func testPlanHubImageMatcherAllowsTilapiaForWhiteFishMeal() async {
        let tilapiaPhotoMeal = Self.matchCandidateMeal(
            name: "Tilapia",
            ingredients: [],
            image: "https://example.com/tilapia.jpg"
        )
        let indexed = [(meal: tilapiaPhotoMeal, tokens: Set(["tilapia"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["white", "fish"]),
                in: indexed
            )
        }

        XCTAssertEqual(match?.image, "https://example.com/tilapia.jpg")
    }

    func testPlanHubImageMatcherAllowsPartialCleanMealPhotoWhenSideIsMissing() async {
        let fishAsparagusPhotoMeal = Self.matchCandidateMeal(
            name: "10.2 oz grouper with 2 oz asparagus",
            ingredients: ["grouper", "asparagus"],
            image: "https://example.com/fish-asparagus.jpg"
        )
        let indexed = [(meal: fishAsparagusPhotoMeal, tokens: Set(["grouper", "asparagu"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["white", "fish", "asparagu", "almond"]),
                in: indexed
            )
        }

        XCTAssertEqual(match?.image, "https://example.com/fish-asparagus.jpg")
    }

    func testPlanHubItemMatcherUsesQuantityFoodTextForGenericMealNames() async {
        let tilapiaPhotoMeal = Self.matchCandidateMeal(
            name: "Tilapia",
            ingredients: ["jasmine rice", "asparagus"],
            image: "https://example.com/tilapia.jpg"
        )
        let indexed = [(meal: tilapiaPhotoMeal, tokens: Set(["tilapia", "jasmine", "rice", "asparagu"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findItemMatch(
                tokens: Set(["pre", "workout", "meal", "chicken", "breast", "jasmine", "rice"]),
                in: indexed
            )
        }

        XCTAssertNil(match)
    }

    func testPlanHubImageMatcherRejectsChickenEggPhotoForChickenPotatoMeal() async {
        let chickenEggPhotoMeal = Self.matchCandidateMeal(
            name: "Egg whites, whole egg, spinach, chicken breast",
            ingredients: ["egg whites", "whole egg", "spinach", "chicken breast"],
            image: "https://example.com/chicken-egg.jpg"
        )
        let indexed = [(meal: chickenEggPhotoMeal, tokens: Set(["egg", "white", "spinach", "chicken", "breast"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["post", "workout", "meal", "chicken", "breast", "white", "potato"]),
                in: indexed
            )
        }

        XCTAssertNil(match)
    }

    func testPlanHubImageMatcherAllowsChickenRicePhotoForChickenRiceMeal() async {
        let chickenRicePhotoMeal = Self.matchCandidateMeal(
            name: "6 oz Chicken Breast with Rice",
            ingredients: ["chicken breast", "rice"],
            image: "https://example.com/chicken-rice.jpg"
        )
        let indexed = [(meal: chickenRicePhotoMeal, tokens: Set(["chicken", "breast", "rice"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["pre", "workout", "meal", "chicken", "breast", "jasmine", "rice"]),
                in: indexed
            )
        }

        XCTAssertEqual(match?.image, "https://example.com/chicken-rice.jpg")
    }

    func testPlanHubImageMatcherRejectsChickenRicePhotoWithUnplannedAsparagus() async {
        let chickenRiceAsparagusPhotoMeal = Self.matchCandidateMeal(
            name: "6 oz Chicken Breast with Rice and Asparagus",
            ingredients: ["chicken breast", "rice", "asparagus"],
            image: "https://example.com/chicken-rice-asparagus.jpg"
        )
        let indexed = [(meal: chickenRiceAsparagusPhotoMeal, tokens: Set(["chicken", "breast", "rice", "asparagu"]))]

        let match = await MainActor.run {
            MacraPlanHubViewModel.findMealMatch(
                tokens: Set(["pre", "workout", "meal", "chicken", "breast", "jasmine", "rice"]),
                in: indexed
            )
        }

        XCTAssertNil(match)
    }

    func testPlanHubImageMatcherBuildsCompositeForSplitBreakfast() async {
        let eggPhotoMeal = Self.matchCandidateMeal(
            name: "Egg whites, whole egg, spinach",
            ingredients: ["egg whites", "whole egg", "spinach"],
            image: "https://example.com/eggs.jpg"
        )
        let riceCakePhotoMeal = Self.matchCandidateMeal(
            name: "Plain rice cakes",
            ingredients: ["rice cakes"],
            image: "https://example.com/rice-cakes.jpg"
        )
        let indexed = [
            (meal: eggPhotoMeal, tokens: Set(["egg", "white", "spinach"])),
            (meal: riceCakePhotoMeal, tokens: Set(["rice", "cake"]))
        ]

        let matches = await MainActor.run {
            MacraPlanHubViewModel.findCompositeMealMatches(
                tokens: Set(["egg", "white", "spinach", "rice", "cake"]),
                in: indexed
            )
        }

        XCTAssertEqual(matches.map(\.image), [
            "https://example.com/eggs.jpg",
            "https://example.com/rice-cakes.jpg"
        ])
    }

    func testPlanHubImageMatcherRejectsCompositeWhenCarbIsMissing() async {
        let eggPhotoMeal = Self.matchCandidateMeal(
            name: "Egg whites, whole egg, spinach",
            ingredients: ["egg whites", "whole egg", "spinach"],
            image: "https://example.com/eggs.jpg"
        )
        let indexed = [(meal: eggPhotoMeal, tokens: Set(["egg", "white", "spinach"]))]

        let matches = await MainActor.run {
            MacraPlanHubViewModel.findCompositeMealMatches(
                tokens: Set(["egg", "white", "spinach", "rice", "cake"]),
                in: indexed
            )
        }

        XCTAssertTrue(matches.isEmpty)
    }

    func testPlanHubImageMatcherRejectsCompositeCandidateWithExtraFoods() async {
        let steakEggPancakeMeal = Self.matchCandidateMeal(
            name: "NY Strip Steak, Eggs, Keto Pancakes, and Salad",
            ingredients: ["strip steak", "eggs", "keto pancakes", "salad"],
            image: "https://example.com/steak-eggs-pancakes.jpg"
        )
        let riceCakePhotoMeal = Self.matchCandidateMeal(
            name: "Plain rice cakes",
            ingredients: ["rice cakes"],
            image: "https://example.com/rice-cakes.jpg"
        )
        let indexed = [
            (meal: steakEggPancakeMeal, tokens: Set(["strip", "steak", "egg", "keto", "pancake", "salad"])),
            (meal: riceCakePhotoMeal, tokens: Set(["rice", "cake"]))
        ]

        let matches = await MainActor.run {
            MacraPlanHubViewModel.findCompositeMealMatches(
                tokens: Set(["egg", "white", "spinach", "rice", "cake"]),
                in: indexed
            )
        }

        XCTAssertTrue(matches.isEmpty)
    }

    func testPlanHubImageMatcherRejectsCompositeSideWithUnplannedAlmondButter() async {
        let eggPhotoMeal = Self.matchCandidateMeal(
            name: "Egg whites, whole egg, spinach",
            ingredients: ["egg whites", "whole egg", "spinach"],
            image: "https://example.com/eggs.jpg"
        )
        let riceCakeAlmondButterMeal = Self.matchCandidateMeal(
            name: "Rice cake with almond butter",
            ingredients: ["rice cake", "almond butter"],
            image: "https://example.com/rice-cake-almond-butter.jpg"
        )
        let indexed = [
            (meal: eggPhotoMeal, tokens: Set(["egg", "white", "spinach"])),
            (meal: riceCakeAlmondButterMeal, tokens: Set(["rice", "cake", "almond", "butter"]))
        ]

        let matches = await MainActor.run {
            MacraPlanHubViewModel.findCompositeMealMatches(
                tokens: Set(["egg", "white", "spinach", "rice", "cake"]),
                in: indexed
            )
        }

        XCTAssertTrue(matches.isEmpty)
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

    private static func matchCandidateMeal(name: String, ingredients: [String], image: String) -> Meal {
        Meal(
            name: name,
            ingredients: ingredients,
            caption: "",
            calories: 400,
            protein: 50,
            fat: 8,
            carbs: 30,
            image: image
        )
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

    func testBuddyShareURLUsesFirstPartyUniversalLinkUntilOneLinkAASAIsAssociated() {
        let token = "AbCdEfGh23456789"

        XCTAssertEqual(
            BuddyInvite.shareURL(forToken: token)?.absoluteString,
            "https://fitwithpulse.ai/macra/buddy/\(token)"
        )
    }

    func testBuddyURLParserReadsFirstPartyUniversalLink() {
        XCTAssertEqual(
            BuddyURLParser.token(from: "https://fitwithpulse.ai/macra/buddy/AbCdEfGh23456789"),
            "AbCdEfGh23456789"
        )
    }

    func testBuddyURLParserReadsCustomSchemeFallback() {
        XCTAssertEqual(
            BuddyURLParser.token(from: "macra://buddy/AbCdEfGh23456789"),
            "AbCdEfGh23456789"
        )
    }

    func testBuddyURLParserReadsOneLinkQueryPayloads() {
        XCTAssertEqual(
            BuddyURLParser.token(from: "https://macra.onelink.me/iwHk?deep_link_value=buddy&buddy_token=AbCdEfGh23456789"),
            "AbCdEfGh23456789"
        )

        XCTAssertEqual(
            BuddyURLParser.token(from: "https://macra.onelink.me/iwHk?deep_link_value=buddy&deep_link_sub1=ZYXwvuTS76543210"),
            "ZYXwvuTS76543210"
        )
    }

    func testBuddyURLParserReadsNestedOneLinkFallbacks() {
        XCTAssertEqual(
            BuddyURLParser.token(from: "https://macra.onelink.me/iwHk?af_dp=macra%3A%2F%2Fbuddy%2FAbCdEfGh23456789"),
            "AbCdEfGh23456789"
        )

        XCTAssertEqual(
            BuddyURLParser.token(from: "https://macra.onelink.me/iwHk?af_r=https%3A%2F%2Ffitwithpulse.ai%2Fmacra%2Fbuddy%2FZYXwvuTS76543210"),
            "ZYXwvuTS76543210"
        )
    }

    func testBuddyURLParserDoesNotTreatOneLinkShortCodeAsInviteToken() {
        XCTAssertNil(BuddyURLParser.token(from: "https://macra.onelink.me/iwHk/5kdshl1e"))
    }

    func testPurchaseFlowDecisionPurchasesSelectedPlanWhenReady() {
        let plan = Self.testSubscriptionPlan(id: "rc_annual")

        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: false,
            packageLoadError: nil,
            selectedPlan: plan
        ))

        guard case .purchase(let resolvedPlan) = decision else {
            XCTFail("Expected purchase decision when a selected plan is ready.")
            return
        }

        XCTAssertEqual(resolvedPlan.id, "rc_annual")
    }

    func testPurchaseFlowDecisionBlocksWhilePlansAreLoading() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: true,
            packageLoadError: nil,
            selectedPlan: nil
        ))

        Self.assertBlocked(decision, reason: .plansLoading)
    }

    func testPurchaseFlowDecisionBlocksPackageLoadErrorsBeforeAttemptingPurchase() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: false,
            packageLoadError: "RevenueCat returned no supported packages.",
            selectedPlan: Self.testSubscriptionPlan(id: "rc_annual")
        ))

        Self.assertBlocked(decision, reason: .packageLoadError)
    }

    func testPurchaseFlowDecisionBlocksMissingSelectedPlan() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: false,
            packageLoadError: nil,
            selectedPlan: nil
        ))

        Self.assertBlocked(decision, reason: .selectedPlanMissing)
    }

    func testPurchaseFlowDecisionContinuesExistingSubscriberWithoutPurchase() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: true,
            isLoadingPackages: true,
            packageLoadError: "Packages are broken but subscriber already has access.",
            selectedPlan: nil
        ))

        guard case .continueExistingAccess = decision else {
            XCTFail("Expected existing subscribers to bypass purchase.")
            return
        }
    }

    func testPurchaseFlowDecisionBypassesLivePurchaseInScreenDemoMode() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: false,
            isDemoMode: true,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: false,
            packageLoadError: nil,
            selectedPlan: nil
        ))

        guard case .continueDemoAccess = decision else {
            XCTFail("Expected screen demo mode to bypass live purchase.")
            return
        }
    }

    func testPurchaseFlowDecisionIgnoresRepeatedTapWhileAlreadyPurchasing() {
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: true,
            isDemoMode: false,
            usesLivePurchasesInDemo: false,
            hasExistingSubscriptionAccess: false,
            isLoadingPackages: false,
            packageLoadError: nil,
            selectedPlan: Self.testSubscriptionPlan(id: "rc_annual")
        ))

        guard case .ignoreAlreadyPurchasing = decision else {
            XCTFail("Expected repeat taps during purchase to be ignored.")
            return
        }
    }

    private static func testSubscriptionPlan(id: String) -> SubscriptionPlanOption {
        .local(LocalSubscriptionPlanViewModel(
            id: id,
            displayTitle: "Annual",
            localizedPriceString: "$39.99",
            price: Decimal(39.99),
            periodKind: .year,
            trialDays: 3,
            product: nil
        ))
    }

    private static func assertBlocked(
        _ decision: MacraPurchaseFlowDecision,
        reason expectedReason: MacraPurchaseFlowBlockReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .blocked(let reason, let message) = decision else {
            XCTFail("Expected blocked decision.", file: file, line: line)
            return
        }

        XCTAssertEqual(reason, expectedReason, file: file, line: line)
        XCTAssertFalse(message.isEmpty, file: file, line: line)
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
