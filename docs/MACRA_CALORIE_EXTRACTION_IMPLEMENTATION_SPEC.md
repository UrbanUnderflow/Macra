# Macra / Calorie AI Extraction Implementation Spec

## Objective

Create a standalone nutrition product by extracting the calorie-tracking and nutrition surface from `Fit With Pulse` into:

- `Macra` for iOS
- `Android-Macra` for Android

This extraction should preserve the production nutrition feature set while avoiding destructive moves inside the current Pulse codebases. Phase 1 is a copy-and-isolate effort, not a shared-module refactor.

## Working Assumptions

- `Macra` is the repo and implementation surface name for now.
- The customer-facing brand can be `Calorie AI` without requiring the repo to be renamed immediately.
- We should preserve existing nutrition user data by keeping the current Firebase/Firestore contract in Phase 1.
- We should copy all nutrition features that make sense in a standalone calorie product.
- We should not carry over club/challenge/community-only nutrition surfaces into the standalone app.
- We should not delete or move source files out of `QuickLifts` or `Pulse-Android` during the first extraction pass.

## Source-of-Truth Findings

### Primary source app

The production nutrition implementation currently lives in `QuickLifts` iOS, not in `Macra`.

Key source files:

- `QuickLifts/QuickLifts/Models/Meal.swift`
- `QuickLifts/QuickLifts/Models/IngredientNutrition.swift`
- `QuickLifts/QuickLifts/Models/MealPlan.swift`
- `QuickLifts/QuickLifts/Models/MacroRecommendation.swift`
- `QuickLifts/QuickLifts/Models/ScannedLabel.swift`
- `QuickLifts/QuickLifts/Models/LoggedSupplement.swift`
- `QuickLifts/QuickLifts/Services/UserService/MealService.swift`
- `QuickLifts/QuickLifts/Services/UserService/UserService.swift`
- `QuickLifts/QuickLifts/Services/GPTService.swift`
- `QuickLifts/QuickLifts/Services/LabelScanService.swift`
- `QuickLifts/QuickLifts/View/Screens/FoodTrackerView/*`
- `QuickLifts/QuickLifts/View/Screens/MealPlanningView/*`

### Current Macra state

`Macra` is an old lightweight food-journal shell and is not feature-parity with the production nutrition stack.

Current Macra indicators:

- `Macra/Macra/View/Screens/Home/FoodJournalView.swift` is a text-only journaling flow.
- `Macra/Macra/Services/GPTService.swift` uses an outdated direct OpenAI client and should not be the long-term base.
- `Macra/Macra/Services/EntryService.swift` writes `users/{uid}/entry`, which is not the production meal contract.
- `Macra/Macra.xcodeproj/project.pbxproj` already has a standalone bundle/product shell:
  - `PRODUCT_BUNDLE_IDENTIFIER = Tremaine.Macra`
  - `PRODUCT_NAME = MacraFoodJournal`

Conclusion: `Macra` should be repurposed as the new shell, but the nutrition feature set should be copied from `QuickLifts`, not evolved from the old `Macra` implementation.

### Current Android state

`Pulse-Android` already contains a substantial nutrition implementation:

- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/ui/nutrition/*`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/ui/mealplanning/*`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/model/Meal.kt`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/repository/MealRepositoryImpl.kt`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/repository/MacroProfileRepositoryImpl.kt`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/repository/MealPlanRepositoryImpl.kt`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/repository/LabelScanRepository.kt`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/data/repository/SupplementRepositoryImpl.kt`

Conclusion: `Android-Macra` should be cloned from `Pulse-Android` and stripped down to the nutrition product, not built from scratch.

## Critical Contract Risks Found During Inventory

These are the most important extraction blockers.

### 1. Android meal collection is not aligned with production

Production iOS and web use:

- `users/{uid}/mealLogs/{mealId}`

Android currently uses:

- `users/{uid}/meals/{mealId}`

Evidence:

- `QuickLifts/QuickLifts/Services/UserService/UserService.swift`
- `QuickLifts-Web/src/api/firebase/meal/service.ts`
- `Pulse-Android/app/src/main/java/ai/fitwithpulse/pulse/util/Constants.kt`

Required action:

- `Android-Macra` must be changed to `mealLogs`, not `meals`.

### 2. Android meal document IDs are not aligned with production

Production iOS creates meal doc IDs as:

- `MMddyyyy + meal.id`

Android currently writes:

- `document(meal.id)`

Required action:

- `Android-Macra` must adopt the production meal document ID strategy to preserve cross-platform parity and same-day dedupe behavior.

### 3. Android `generateMealMacros` write payload does not match iOS

iOS writes:

- `image`
- `caption`
- `timestamp`
- `retryCount`

Android currently writes a different payload shape.

Required action:

- `Android-Macra` must align to the iOS-triggered Cloud Function contract before launch.

### 4. Legacy Macra GPT stack should not be reused

Required action:

- Replace the old `Macra` text-journal GPT layer with the production nutrition AI stack from `QuickLifts`.

## Product Scope for Standalone Macra

### Carry over into Macra v1

These should be included in the standalone nutrition product.

#### Core meal logging

- Photo meal scan and AI nutrition analysis
- Manual text meal entry and AI analysis
- Voice meal entry and transcription-based analysis
- Meal confirmation/edit before save
- Meal CRUD in daily journal
- Meal detail screen
- Edit meal title
- Edit meal time
- Delete meal
- Re-log meal / eat again

#### Daily and calendar nutrition surfaces

- Day-based food journal
- Month calendar journal
- Daily macro totals
- Daily detailed nutrition totals
- Daily meal breakdown
- Daily nutrition share/export surface
- Photo food history grid
- Add-from-history flow

#### Macro targets and nutrition intelligence

- Daily macro targets
- AI macro recommendation flow
- Per-day or global macro recommendation storage
- Daily AI insights / day analysis prompts

#### Quick-log and retention features

- Pinned meals
- Reorder pinned meals
- Lock/unlock pinned meal reorder state
- One-tap "log all pinned meals"

#### Meal planning

- Meal plan CRUD
- Add meals from journal to plan
- Reorder planned meals
- Combine/separate planned meals
- Log planned meals back into journal
- Create meal plan from a day's meals

#### Packaged-food label intelligence

- Scan label
- Label grade result
- Flagged ingredients and source-backed explanation
- Label scan history
- Label detail view
- Persisted Q&A on a label
- Deep dive research
- Healthier alternatives

#### Supplement tracking

- Logged supplements for a day
- Saved supplement library
- Quick-log saved supplements
- Scan supplement label
- Supplement detail/edit sheet
- Supplement macro and micronutrient contribution to daily totals

### Explicitly exclude from standalone Macra v1

These are nutrition-adjacent, but they are not part of the standalone calorie app surface.

- Challenge meal-tracking participants
- Nutrition challenge detail views
- Public/shared meal challenge views
- Round/challenge meal-plan selection UI
- Club leaderboard or challenge-specific nutrition overlays
- Pulse home-tab integrations unrelated to nutrition

These can remain in `QuickLifts`.

## Standalone App Architecture

## iOS: Macra

### Strategy

Repurpose `Macra` as the app shell, but copy the nutrition domain from `QuickLifts`.

### Recommended iOS extraction structure

- Keep:
  - `Macra/MacraApp.swift`
  - `Macra/Macra/ContentView.swift`
  - auth shell, paywall shell, settings shell, asset catalog as needed
- Replace or retire:
  - `Macra/Macra/Services/GPTService.swift`
  - `Macra/Macra/Services/EntryService.swift`
  - `Macra/Macra/Models/FoodJournalFeedback.swift`
  - `Macra/Macra/Models/EntryAssessment.swift`
  - current text-only `FoodJournalView`
- Copy from `QuickLifts`:
  - nutrition models
  - nutrition services
  - food tracker screens
  - meal planning screens
  - label scan screens
  - supplement tracking screens
  - nutrition-specific reusable components/assets

### iOS shell changes required

- Convert `Macra` navigation into nutrition-first navigation.
- Make the home surface the day journal, not the old text-entry prompt.
- Replace the current tab bar destinations with standalone nutrition destinations.
- Preserve login, registration, settings, and paywall where still useful.
- Keep bundle id and product shell in `Macra` unless branding requires a separate target.

### iOS integrations to preserve

- Firebase Auth
- Firestore
- Firebase Storage
- RevenueCat
- Camera permissions
- Microphone + speech permissions
- HealthKit meal sync behavior from the production nutrition flow

## Android: Android-Macra

### Strategy

Create `Android-Macra` by copying `Pulse-Android`, then remove everything that is not needed for the nutrition product.

### Recommended Android keep set

- auth flow
- nutrition UI package
- meal planning UI package
- nutrition models
- nutrition repositories
- Firebase/Hilt/Compose app foundation

### Recommended Android remove set

- workout flows
- round/challenge flows
- club flows
- home dashboard not needed by nutrition
- social/chat features
- non-nutrition bottom-nav destinations

### Android shell changes required

- Rename project root:
  - current: `rootProject.name = "Pulse"`
  - target: `Android-Macra`
- Rename namespace and app id:
  - current namespace: `ai.fitwithpulse.pulse`
  - current applicationId: `ai.fitwithpulse.pulse`
  - recommended target namespace/applicationId: `ai.fitwithpulse.macra`
- Update strings, icons, package folders, and app label to the new product.
- Replace multi-product bottom navigation with nutrition-only standalone navigation.

## Shared Data Contract to Preserve

Phase 1 should reuse the current backend contract so users do not lose data.

### Firestore

- `users/{uid}/mealLogs/{datePrefix+mealId}`
- `users/{uid}/pinnedMeals/{sanitizedMealName}`
- `users/{uid}/savedSupplements/{supplementId}`
- `users/{uid}/supplementLogs/{datePrefix+supplementId}`
- `users/{uid}/labelScans/{scanId}`
- `macro-profile/{uid}/macro-recommendations/{id}`
- `meal-plan/{planId}`
- `generateMealMacros/{mealId}`

### Storage

- `food/meal-{mealId}.jpg`
- `label-scans/{uid}/{scanId}.jpg`
- `supplements/supplement-{supplementId}.jpg`

### Key rule

Do not invent a new backend schema for v1. First achieve product extraction with the live schema. Schema separation can happen later if the product needs its own backend.

## Migration Strategy

### Phase 1: Safe extraction

- Copy source files into `Macra` and `Android-Macra`
- Do not remove or rename source files inside `QuickLifts` or `Pulse-Android`
- Keep shared backend contract
- Verify standalone behavior

### Phase 2: Hardening

- Remove leftover Pulse-specific dependencies from the extracted apps
- Normalize Android contract mismatches
- Replace old Macra services fully
- Add missing tests

### Phase 3: Optional consolidation

- Extract shared nutrition modules only after both standalone apps are stable
- Consider a shared backend or shared package only when parity is proven

## Platform Implementation Plan

### iOS work plan

1. Create a new `Nutrition` feature area inside `Macra`.
2. Copy models from `QuickLifts`.
3. Copy services from `QuickLifts`.
4. Copy food tracker UI from `QuickLifts`.
5. Copy meal planning UI from `QuickLifts`.
6. Copy label scan and supplement flows from `QuickLifts`.
7. Rewire `Macra` app coordinator and tab shell around nutrition-first navigation.
8. Remove old text-only journal flow from the default path.
9. Rebrand visible copy to `Macra` / `Calorie AI`.
10. Verify same-user read/write parity against the current backend.

### Android work plan

1. Copy `Pulse-Android` into a new `Android-Macra` project.
2. Rename package, app id, resources, and labels.
3. Strip workout/round/club/social surfaces.
4. Keep nutrition and meal planning modules.
5. Fix data contract mismatches:
   - `meals` -> `mealLogs`
   - meal doc id strategy
   - `generateMealMacros` request payload
6. Rebuild navigation as a nutrition-only app.
7. Rebrand visible copy to `Macra` / `Calorie AI`.
8. Verify same-user read/write parity against the current backend.

## QA Acceptance Criteria

The extraction is not complete until all of the following are true.

### Meal logging

- User can scan a meal photo and receive AI nutrition.
- User can log from text.
- User can log from voice.
- User can edit meal title and save.
- User can adjust meal time.
- User can view, update, and delete a meal.

### Journal

- Day journal renders meals in the correct day bucket.
- Month journal renders meal counts correctly.
- Shared user data appears in both Pulse and Macra during transition.
- Daily totals match meal totals.

### Macro system

- Macro targets save and load correctly.
- AI macro recommendations save and reload correctly.
- Daily day-analysis insights persist correctly.

### Quick add and planning

- Pinned meals load, reorder, and quick-log correctly.
- Meal plans save, reorder, combine, separate, and log correctly.

### Label and supplement flows

- Label scans persist to history.
- Label detail Q&A, deep dive, and alternatives persist across reopen.
- Supplements contribute to daily totals and can be quick-logged from library.

### Platform integrity

- iOS camera and speech permissions work.
- Android camera and speech permissions work.
- No data loss occurs when using the same account across Pulse and Macra.

## Recommended Launch Sequencing

### Recommended order

1. Finish this spec and lock the feature contract.
2. Extract iOS into `Macra` first.
3. Validate backend parity and data integrity.
4. Create `Android-Macra` from `Pulse-Android`.
5. Fix Android contract mismatches before Android UI polish.
6. Run side-by-side QA with the same test accounts.
7. Only after parity, decide whether to rename the app-facing brand to `Calorie AI`.

This order is safer because the iOS production implementation is the strongest source of truth.

## Decisions Locked By This Spec

- We will use `Macra` as the iOS extraction shell.
- We will create a new `Android-Macra` surface from `Pulse-Android`.
- We will copy the nutrition stack from production Pulse code, not from old Macra code.
- We will preserve the existing Firestore/Storage contract in Phase 1.
- We will include meal logging, macro tracking, meal planning, label scanning, and supplement tracking in the standalone product.
- We will exclude challenge- and club-specific nutrition surfaces from the standalone product.

## Immediate Next Step

Start the extraction with iOS `Macra` by copying the production nutrition models, services, and primary food tracker screens from `QuickLifts`, while leaving `QuickLifts` untouched.
