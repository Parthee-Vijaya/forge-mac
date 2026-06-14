import Foundation

/// A starting point on the launch screen (B6): a named, pre-written brief the
/// user can build with one click. Each `prompt` is a real, detailed spec so the
/// very first build lands somewhere impressive instead of on a blank page —
/// especially valuable for beginners who don't yet know what to ask for.
struct StarterTemplate: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let prompt: String
}

enum StarterTemplates {
    static let all: [StarterTemplate] = [
        StarterTemplate(
            id: "landing", title: "Landingsside", subtitle: "Hero, features, priser, CTA",
            icon: "sparkles.rectangle.stack",
            prompt: "Byg en moderne, responsiv landingsside for et SaaS-produkt: en hero med overskrift, undertekst og to call-to-action-knapper, en feature-sektion med tre kort med ikoner, en sektion med tre prisplaner, et par kundeudtalelser og en footer. Brug et rent, professionelt design med god typografi og rigeligt med luft."),
        StarterTemplate(
            id: "dashboard", title: "Dashboard", subtitle: "Sidebar, stat-kort, graf, tabel",
            icon: "chart.bar.xaxis",
            prompt: "Byg et admin-dashboard med en venstre sidebar-navigation, en topbar, fire stat-kort øverst (tal med en lille trend-indikator), en linjegraf over tid og en datatabel med sortérbare rækker. Brug realistisk eksempel-data og et moderne, roligt design."),
        StarterTemplate(
            id: "todo", title: "Todo-app", subtitle: "Tilføj, fuldfør, filtrér, gem",
            icon: "checklist",
            prompt: "Byg en todo-app: tilføj opgaver, marker som fuldført, slet, filtrér (alle / aktive / fuldførte), vis antal tilbage, og gem i localStorage så listen overlever en genindlæsning. Minimalistisk, venligt design."),
        StarterTemplate(
            id: "portfolio", title: "Portfolio", subtitle: "Hero, projekter, om, kontakt",
            icon: "person.crop.square",
            prompt: "Byg en personlig portfolio-side: en hero med navn og titel, et galleri af projekter som kort med billede og beskrivelse, en om-mig-sektion og en kontakt-sektion. Elegant, moderne design med bløde animationer."),
        StarterTemplate(
            id: "blog", title: "Blog", subtitle: "Forside, artikler, læsevisning",
            icon: "doc.richtext",
            prompt: "Byg en blog: en forside med en liste af artikel-kort (titel, uddrag, dato) og en læsevisning for en enkelt artikel med god typografi. Brug eksempel-indhold. Rent, læsevenligt design."),
        StarterTemplate(
            id: "pomodoro", title: "Pomodoro-timer", subtitle: "Arbejde/pause, start/nulstil",
            icon: "timer",
            prompt: "Byg en pomodoro-timer: 25 minutters arbejdsinterval og 5 minutters pause, store cifre, start/pause/nulstil-knapper, automatisk skift mellem arbejde og pause, og en tæller over fuldførte runder. Fokuseret, roligt design."),
    ]
}
