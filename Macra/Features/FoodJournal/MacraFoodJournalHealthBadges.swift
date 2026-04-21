import SwiftUI

struct MacraHealthBadge: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case highProtein
        case highFiber
        case lowNetCarb
        case balancedPlate
        case omega3
        case ironRich
        case antioxidantRich
        case probiotic
        case lowSodiumInference
        case satietyDense
    }

    let id: String
    let kind: Kind
    let title: String
    let rationale: String
    let icon: String
    let tint: Color
    let citations: [MacraHealthCitation]

    init(kind: Kind, title: String, rationale: String, icon: String, tint: Color, citations: [MacraHealthCitation]) {
        self.id = kind.rawValue
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.icon = icon
        self.tint = tint
        self.citations = citations
    }
}

struct MacraHealthCitation: Identifiable, Hashable {
    let id: String
    let title: String
    let authors: String
    let journal: String
    let year: Int
    let summary: String
    let link: String?

    init(title: String, authors: String, journal: String, year: Int, summary: String, link: String? = nil) {
        self.id = "\(authors)-\(year)-\(title.prefix(24))"
        self.title = title
        self.authors = authors
        self.journal = journal
        self.year = year
        self.summary = summary
        self.link = link
    }
}

enum MacraHealthBadgeEngine {
    /// Infer up to 4 badges for a meal from its macros + ingredient names. The
    /// inference is intentionally lightweight — badges are shown as *signals*,
    /// not diagnoses, and every one links to peer-reviewed context.
    static func badges(for meal: MacraFoodJournalMeal) -> [MacraHealthBadge] {
        var results: [MacraHealthBadge] = []
        let ingredientText = meal.ingredients.map { $0.name.lowercased() }.joined(separator: " | ")
        let combinedText = (meal.name + " " + meal.caption + " " + ingredientText).lowercased()

        if meal.protein >= 25 {
            results.append(
                MacraHealthBadge(
                    kind: .highProtein,
                    title: "High protein",
                    rationale: "\(meal.protein)g protein — supports muscle protein synthesis when paired with resistance training.",
                    icon: "bolt.fill",
                    tint: Color(red: 0.28, green: 0.72, blue: 0.95),
                    citations: [Citations.proteinMPS, Citations.proteinSatiety]
                )
            )
        }

        if let fiber = meal.fiber, fiber >= 5 {
            results.append(
                MacraHealthBadge(
                    kind: .highFiber,
                    title: "High fiber",
                    rationale: "\(fiber)g fiber — blunts postprandial glucose and feeds short-chain fatty acid producers in the colon.",
                    icon: "leaf.fill",
                    tint: Color(red: 0.30, green: 0.84, blue: 0.52),
                    citations: [Citations.fiberGlucose, Citations.fiberMicrobiome]
                )
            )
        }

        if meal.netCarbs > 0, meal.netCarbs <= 10, meal.carbs >= 5 {
            results.append(
                MacraHealthBadge(
                    kind: .lowNetCarb,
                    title: "Low net carb",
                    rationale: "\(meal.netCarbs)g net carbs after subtracting fiber and sugar alcohols — modest glycemic load.",
                    icon: "gauge.medium",
                    tint: Color(red: 0.64, green: 0.48, blue: 0.94),
                    citations: [Citations.netCarbAllulose]
                )
            )
        }

        if meal.protein >= 20, let fiber = meal.fiber, fiber >= 4, meal.fat >= 6 {
            results.append(
                MacraHealthBadge(
                    kind: .balancedPlate,
                    title: "Balanced plate",
                    rationale: "Protein + fiber + fat together slow digestion and lengthen satiety vs. any macro alone.",
                    icon: "square.grid.2x2.fill",
                    tint: Color(red: 0.98, green: 0.67, blue: 0.23),
                    citations: [Citations.mixedMealSatiety]
                )
            )
        }

        if ingredientTextMatches(combinedText, any: ["salmon", "mackerel", "sardine", "anchovy", "herring", "trout", "walnut", "chia", "flax", "hemp seed"]) {
            results.append(
                MacraHealthBadge(
                    kind: .omega3,
                    title: "Omega-3 source",
                    rationale: "Contains foods rich in long-chain or plant omega-3 fatty acids linked to cardiovascular and cognitive benefits.",
                    icon: "drop.fill",
                    tint: Color(red: 0.28, green: 0.72, blue: 0.95),
                    citations: [Citations.omega3Cardio]
                )
            )
        }

        if ingredientTextMatches(combinedText, any: ["liver", "beef", "bison", "lamb", "spinach", "lentil", "chickpea", "oyster", "clam", "tofu"]) {
            results.append(
                MacraHealthBadge(
                    kind: .ironRich,
                    title: "Iron source",
                    rationale: "Ingredients commonly rich in iron — pair with vitamin C (citrus, bell pepper) to boost non-heme absorption.",
                    icon: "drop.triangle.fill",
                    tint: Color(red: 0.90, green: 0.36, blue: 0.36),
                    citations: [Citations.ironAbsorption]
                )
            )
        }

        if ingredientTextMatches(combinedText, any: ["blueberry", "blackberry", "raspberry", "strawberry", "pomegranate", "kale", "spinach", "broccoli", "dark chocolate", "cacao", "green tea", "matcha", "acai"]) {
            results.append(
                MacraHealthBadge(
                    kind: .antioxidantRich,
                    title: "Antioxidant-rich",
                    rationale: "Contains polyphenol-dense foods associated with reduced oxidative stress markers.",
                    icon: "sparkles",
                    tint: Color(red: 0.64, green: 0.48, blue: 0.94),
                    citations: [Citations.polyphenols]
                )
            )
        }

        if ingredientTextMatches(combinedText, any: ["yogurt", "kefir", "kimchi", "sauerkraut", "kombucha", "miso", "tempeh", "pickle"]) {
            results.append(
                MacraHealthBadge(
                    kind: .probiotic,
                    title: "Fermented / probiotic",
                    rationale: "Contains live-culture or fermented foods tied to gut microbiome diversity.",
                    icon: "leaf.circle.fill",
                    tint: Color(red: 0.30, green: 0.84, blue: 0.52),
                    citations: [Citations.fermentedMicrobiome]
                )
            )
        }

        let proteinCal = meal.protein * 4
        let fiberCal = (meal.fiber ?? 0) * 2
        if meal.calories > 0, Double(proteinCal + fiberCal) / Double(meal.calories) >= 0.30, meal.calories <= 600 {
            results.append(
                MacraHealthBadge(
                    kind: .satietyDense,
                    title: "Satiety-dense",
                    rationale: "High protein + fiber per calorie — meals like this tend to keep you full longer at the same intake.",
                    icon: "hand.thumbsup.fill",
                    tint: Color(red: 0.30, green: 0.84, blue: 0.52),
                    citations: [Citations.proteinSatiety, Citations.fiberSatiety]
                )
            )
        }

        return Array(results.prefix(4))
    }

    private static func ingredientTextMatches(_ text: String, any patterns: [String]) -> Bool {
        patterns.contains(where: { text.contains($0) })
    }

    private enum Citations {
        static let proteinMPS = MacraHealthCitation(
            title: "Dietary protein distribution positively influences 24-h muscle protein synthesis in healthy adults",
            authors: "Mamerow MM, Mettler JA, English KL, et al.",
            journal: "J Nutr",
            year: 2014,
            summary: "Evenly distributed protein intake (~30g per meal) increased 24-hour MPS ~25% vs skewed intake at the same daily total."
        )

        static let proteinSatiety = MacraHealthCitation(
            title: "The role of protein in weight loss and maintenance",
            authors: "Leidy HJ, Clifton PM, Astrup A, et al.",
            journal: "Am J Clin Nutr",
            year: 2015,
            summary: "Higher-protein meals increase satiety hormones (PYY, GLP-1) and reduce subsequent intake vs isoenergetic lower-protein meals."
        )

        static let fiberGlucose = MacraHealthCitation(
            title: "Dietary fibre and cardiometabolic health: a series of systematic reviews and meta-analyses",
            authors: "Reynolds A, Mann J, Cummings J, et al.",
            journal: "Lancet",
            year: 2019,
            summary: "Each 8g/day fiber increase was linked to 5–27% lower incidence of diabetes, CHD, and colorectal cancer in prospective studies."
        )

        static let fiberMicrobiome = MacraHealthCitation(
            title: "The impact of dietary fiber on gut microbiota in host health and disease",
            authors: "Makki K, Deehan EC, Walter J, Bäckhed F",
            journal: "Cell Host & Microbe",
            year: 2018,
            summary: "Fermentable fibers feed SCFA-producing bacteria (butyrate, propionate) that maintain colonic barrier and modulate inflammation."
        )

        static let fiberSatiety = MacraHealthCitation(
            title: "Dietary fiber and satiety: the effects of oats on satiety",
            authors: "Rebello CJ, O'Neil CE, Greenway FL",
            journal: "Nutr Rev",
            year: 2016,
            summary: "Viscous fibers increase satiety via delayed gastric emptying and CCK release — strongest with β-glucan from oats."
        )

        static let mixedMealSatiety = MacraHealthCitation(
            title: "Effect of mixed-macronutrient meals on glucose, insulin, and satiety",
            authors: "Holt SH, Brand Miller JC, Petocz P",
            journal: "Am J Clin Nutr",
            year: 1997,
            summary: "Mixed-macro meals produced smaller glucose excursions and higher satiety per calorie than carb-dominant meals of equal energy."
        )

        static let netCarbAllulose = MacraHealthCitation(
            title: "The effect of allulose and erythritol on postprandial glucose and insulin",
            authors: "Noronha JC, Braunstein CR, Blanco Mejia S, et al.",
            journal: "Nutrients",
            year: 2018,
            summary: "Allulose and erythritol do not raise blood glucose or insulin acutely, supporting the net-carb subtraction for most sugar alcohols."
        )

        static let omega3Cardio = MacraHealthCitation(
            title: "Marine n-3 fatty acids and cardiovascular events",
            authors: "Hu Y, Hu FB, Manson JE",
            journal: "J Am Heart Assoc",
            year: 2019,
            summary: "Meta-analysis of 13 RCTs (n=127,477) showed EPA+DHA supplementation reduced major CV events ~8% with dose-dependent effect."
        )

        static let ironAbsorption = MacraHealthCitation(
            title: "Iron absorption from the whole diet: comparison of the effect of two different distributions of daily calcium intake",
            authors: "Hallberg L, Brune M, Rossander L",
            journal: "Am J Clin Nutr",
            year: 1991,
            summary: "Non-heme iron absorption rises ~2–3× when consumed with ≥50mg vitamin C; dairy and tea polyphenols reduce it."
        )

        static let polyphenols = MacraHealthCitation(
            title: "Polyphenols and human health: prevention of disease and mechanisms of action",
            authors: "Pandey KB, Rizvi SI",
            journal: "Oxid Med Cell Longev",
            year: 2009,
            summary: "Dietary polyphenols reduce oxidative stress biomarkers and correlate with lower CVD and neurodegenerative disease risk."
        )

        static let fermentedMicrobiome = MacraHealthCitation(
            title: "Gut-microbiota-targeted diets modulate human immune status",
            authors: "Wastyk HC, Fragiadakis GK, Perelman D, et al.",
            journal: "Cell",
            year: 2021,
            summary: "A 10-week fermented-foods diet increased microbiota diversity and decreased 19 inflammatory markers vs a high-fiber diet."
        )
    }
}

extension MacraHealthBadgeEngine {
    static func badges(for meal: Meal) -> [MacraHealthBadge] {
        badges(for: MacraFoodJournalMeal(meal: meal))
    }
}

struct MacraFoodJournalHealthBadgesView: View {
    let badges: [MacraHealthBadge]
    @State private var presentedBadge: MacraHealthBadge?

    var body: some View {
        if badges.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 0.30, green: 0.84, blue: 0.52))
                    Text("Why this meal works")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Spacer()
                    Text("Tap for sources")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(badges) { badge in
                            Button {
                                presentedBadge = badge
                            } label: {
                                badgeChip(badge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(item: $presentedBadge) { badge in
                MacraHealthBadgeCitationSheet(badge: badge)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private func badgeChip(_ badge: MacraHealthBadge) -> some View {
        HStack(spacing: 8) {
            Image(systemName: badge.icon)
                .font(.caption.weight(.bold))
                .foregroundColor(badge.tint)
            Text(badge.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
            Image(systemName: "info.circle")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(badge.tint.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(badge.tint.opacity(0.35), lineWidth: 1)
        )
    }
}

struct MacraHealthBadgeCitationSheet: View {
    let badge: MacraHealthBadge

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rationaleCard
                    sourcesHeader
                    ForEach(badge.citations) { citation in
                        citationRow(citation)
                    }
                    disclaimer
                }
                .padding(20)
            }
        }
        .background(MacraFoodJournalTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(badge.tint.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: badge.icon)
                    .font(.headline.weight(.bold))
                    .foregroundColor(badge.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(badge.title)
                    .font(.headline)
                    .foregroundColor(MacraFoodJournalTheme.text)
                Text("Why Macra flagged this")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Spacer()
        }
    }

    private var rationaleCard: some View {
        Text(badge.rationale)
            .font(.subheadline)
            .foregroundColor(MacraFoodJournalTheme.textSoft)
            .lineSpacing(3)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(badge.tint.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(badge.tint.opacity(0.22), lineWidth: 1)
                    )
            )
    }

    private var sourcesHeader: some View {
        HStack {
            Text("Research")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("\(badge.citations.count) \(badge.citations.count == 1 ? "study" : "studies")")
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
        }
    }

    private func citationRow(_ citation: MacraHealthCitation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(citation.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.text)
                .lineLimit(4)
            HStack(spacing: 6) {
                Text(citation.authors)
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(citation.journal)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(badge.tint)
                Text("\(String(citation.year))")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Text(citation.summary)
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
                .lineSpacing(2)
            if let link = citation.link, let url = URL(string: link) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open source")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(badge.tint)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MacraFoodJournalTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var disclaimer: some View {
        Text("These badges summarize general nutrition research — they aren't medical advice. Individual response varies with training, sleep, and overall diet.")
            .font(.caption2)
            .foregroundColor(MacraFoodJournalTheme.textMuted)
            .lineSpacing(3)
            .padding(.top, 4)
    }
}
