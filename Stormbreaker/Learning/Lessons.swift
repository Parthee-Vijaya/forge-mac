import Foundation

/// One beginner explainer shown in learning mode. `id` is a stable key used to
/// show each lesson only once (Preferences.learnedLessons).
struct Lesson: Identifiable, Equatable {
    let id: String
    let icon: String       // SF Symbol
    let title: String      // Danish
    let body: String       // Danish, plain language
    let terms: [Term]      // English terms taught here, with a Danish gloss
}

/// A technical term shown in English with a short Danish explanation — so a
/// beginner learns the real word *and* what it means.
struct Term: Identifiable, Equatable {
    var id: String { term }
    let term: String          // English, e.g. "commit"
    let explanation: String   // Danish gloss
}

/// The learning-mode content: milestone lessons + the full glossary. Danish copy
/// with English technical terms (the user's chosen style).
enum Lessons {

    static let welcome = Lesson(
        id: "welcome",
        icon: "sparkles",
        title: "Nu bygger vi din app",
        body: """
        Du har lige skrevet en prompt — en besked til AI'en om hvad du vil have. \
        Nu skriver AI'en koden for dig, og du følger med live. Det her kaldes \
        vibecoding: du beskriver i almindeligt sprog, og værktøjet bygger det. \
        Du behøver ikke kunne kode — bare beskrive hvad du ønsker.
        """,
        terms: [
            Term(term: "prompt", explanation: "den besked/instruktion du skriver til AI'en"),
            Term(term: "vibecoding", explanation: "at bygge software ved at beskrive det i almindeligt sprog i stedet for at skrive kode selv"),
        ])

    static let appRunning = Lesson(
        id: "app-running",
        icon: "play.circle",
        title: "Din app kører nu — live",
        body: """
        Til højre ser du din app køre rigtigt. Den kører på en dev server — et lille \
        program på din egen computer der viser appen mens du arbejder. Hver gang \
        noget ændres, opdateres preview med det samme; det kaldes hot reload (HMR). \
        Du behøver ikke gemme eller genstarte noget — det sker automatisk.
        """,
        terms: [
            Term(term: "preview", explanation: "live-vinduet til højre der viser din app, som den ser ud lige nu"),
            Term(term: "dev server", explanation: "et lille program der kører din app lokalt på din computer mens du bygger"),
            Term(term: "hot reload (HMR)", explanation: "ændringer vises straks i preview uden at genstarte appen"),
        ])

    static let errorsFixing = Lesson(
        id: "errors-fixing",
        icon: "wand.and.stars",
        title: "Der opstod en fejl — og den bliver rettet",
        body: """
        Fejl er helt normale, også for professionelle. Stormbreaker opdagede en error i \
        koden og er nu i gang med at rette den selv ud fra fejlmeddelelsen — det \
        kaldes self-correction. Du behøver ikke gøre noget; bliver den ved, kan du \
        altid beskrive problemet med dine egne ord, så prøver den igen.
        """,
        terms: [
            Term(term: "error", explanation: "en fejl i koden der forhindrer appen i at køre rigtigt"),
            Term(term: "runtime error", explanation: "en fejl der sker mens appen kører (modsat en fejl der fanges før)"),
            Term(term: "self-correction", explanation: "AI'en læser fejlen og retter den automatisk"),
        ])

    static let codeView = Lesson(
        id: "code-view",
        icon: "chevron.left.forwardslash.chevron.right",
        title: "Det her er koden bag din app",
        body: """
        Du kigger nu på source code — selve teksten der bestemmer hvordan appen ser \
        ud og virker. Til venstre er file tree, listen af filer i projektet. Appen er \
        bygget af components: genbrugelige byggeklodser som en knap eller et kort. Du \
        behøver ikke redigere noget her — men det er rart at vide hvor det bor. Ændrer \
        du noget, opdaterer preview automatisk.
        """,
        terms: [
            Term(term: "source code", explanation: "selve koden der udgør din app"),
            Term(term: "file", explanation: "et dokument med kode; et projekt består af flere filer"),
            Term(term: "component", explanation: "en genbrugelig byggeklods af brugerfladen (fx en knap eller et kort)"),
        ])

    static let deployGit = Lesson(
        id: "deploy-git",
        icon: "globe",
        title: "At lægge din app på internettet",
        body: """
        At deploye betyder at lægge din app ud på nettet, så andre kan åbne den med et \
        link. Først laver Stormbreaker en commit (et gemt øjebliksbillede af din kode) og en \
        push (uploader den til GitHub — en online tjeneste hvor kode gemmes i et \
        repository). Derefter sender den koden til Vercel, som hoster appen, altså \
        kører den på en rigtig webadresse. Du klikker bare på Deploy — Stormbreaker ordner resten.
        """,
        terms: [
            Term(term: "deploy", explanation: "at lægge din app ud på internettet så andre kan bruge den"),
            Term(term: "commit", explanation: "et gemt øjebliksbillede af din kode på et bestemt tidspunkt"),
            Term(term: "push", explanation: "at uploade dine commits til GitHub (i skyen)"),
            Term(term: "repository (repo)", explanation: "et projekt/mappe hvor din kode og dens historik gemmes"),
            Term(term: "GitHub", explanation: "en online tjeneste til at gemme, versionere og dele kode"),
            Term(term: "Vercel", explanation: "en tjeneste der hoster din app, så den kører på en rigtig webadresse"),
        ])

    /// All milestone lessons, looked up by id at the trigger points.
    static let all: [Lesson] = [welcome, appRunning, errorsFixing, codeView, deployGit]

    static func lesson(_ id: String) -> Lesson? { all.first { $0.id == id } }

    /// A richer, plain-language explanation + a concrete example for a glossary
    /// term — shown when the user taps a term. Pre-written so it always works,
    /// even without a model running; the AI "uddyb" button goes deeper on demand.
    struct Detail: Equatable { let detail: String; let example: String }
    static func detail(for term: String) -> Detail? { details[term] }

    static let details: [String: Detail] = [
        "prompt": .init(
            detail: "En prompt er din besked til AI'en, skrevet i helt almindeligt sprog. Jo tydeligere du beskriver hvad du vil have, jo bedre rammer den. Tænk på det som at give en dygtig hjælper en klar instruktion.",
            example: "“Byg en to-do liste hvor jeg kan tilføje og afkrydse opgaver.”"),
        "vibecoding": .init(
            detail: "At bygge software ved at beskrive det i almindeligt sprog, i stedet for selv at skrive kode. Du siger hvad du vil have; AI'en laver koden. Som at fortælle en håndværker hvad du drømmer om i stedet for selv at svinge hammeren.",
            example: "Du skriver “lav en grøn knap der tæller klik” → AI'en bygger den."),
        "preview": .init(
            detail: "Det levende vindue til højre der viser din app præcis som den ser ud lige nu. Det er ikke et billede — det er den rigtige app, du kan klikke rundt i.",
            example: "Tilføjer du en knap, dukker den op i preview med det samme."),
        "dev server": .init(
            detail: "En lille motor der kører din app lokalt på din egen computer mens du bygger. Den serverer appen på en localhost-adresse, så preview kan vise den. Den kører kun for dig — ikke ude på nettet.",
            example: "http://localhost:5173 — din app, kun synlig på din egen maskine."),
        "hot reload (HMR)": .init(
            detail: "Når noget ændres, opdaterer preview sig selv på et splitsekund — uden at genstarte eller miste hvor du var. HMR står for Hot Module Replacement.",
            example: "Skift en farve i koden → preview skifter farve øjeblikkeligt."),
        "error": .init(
            detail: "En fejl i koden der forhindrer appen i at virke som den skal. Helt normalt — selv professionelle får dem hele tiden. Stormbreaker prøver at rette dem automatisk.",
            example: "Et glemt komma kan give en error, så siden bliver hvid."),
        "runtime error": .init(
            detail: "En fejl der først sker mens appen kører (når du klikker eller bruger den), modsat fejl der fanges før. Ofte noget der går galt ved en bestemt handling.",
            example: "Appen crasher først når du trykker på “Gem”."),
        "self-correction": .init(
            detail: "Stormbreaker læser fejlmeddelelsen og retter koden selv, helt automatisk — og prøver igen indtil den virker. Du behøver ikke gøre noget.",
            example: "Build fejler → Stormbreaker læser fejlen → retter → preview virker igen."),
        "source code": .init(
            detail: "Selve teksten/instruktionerne der udgør din app — “opskriften” computeren følger. Du behøver ikke læse den, men den bor i Kode-visningen hvis du vil kigge.",
            example: "App.tsx er en kodefil med din app's logik."),
        "file": .init(
            detail: "Et dokument der indeholder kode. Et projekt består typisk af mange filer, organiseret i mapper — ligesom kapitler i en bog.",
            example: "src/App.tsx og src/index.css er to filer i dit projekt."),
        "component": .init(
            detail: "En genbrugelig byggeklods af brugerfladen — fx en knap, et kort eller en menu. Apps bygges af komponenter, du kan bruge igen og igen.",
            example: "En Button-component kan genbruges ti steder på siden."),
        "deploy": .init(
            detail: "At lægge din app ud på internettet, så andre kan åbne den med et link. Indtil da kører den kun lokalt hos dig. Stormbreaker klarer hele turen med ét klik.",
            example: "Tryk Deploy → din app får en rigtig adresse som min-app.vercel.app."),
        "commit": .init(
            detail: "Et gemt øjebliksbillede af din kode på et bestemt tidspunkt, med en kort besked om hvad der skete. Som at sætte et bogmærke du altid kan vende tilbage til.",
            example: "“Tilføjede login-knap” er en typisk commit-besked."),
        "push": .init(
            detail: "At uploade dine commits (dine gemte øjebliksbilleder) op til GitHub i skyen, så de er sikret og kan deles.",
            example: "Efter en commit: push den til GitHub, så den ligger online."),
        "repository (repo)": .init(
            detail: "Et projekt/mappe hvor al din kode og dens historik bor — både den nuværende version og alle tidligere commits. Kan være privat eller offentligt.",
            example: "github.com/dit-navn/min-app er et repository."),
        "GitHub": .init(
            detail: "En online tjeneste hvor man gemmer, versionerer og deler kode i repositories. Verdens største sted for kode — gratis at bruge.",
            example: "Du pusher din kode til GitHub, så den er sikret online."),
        "Vercel": .init(
            detail: "En tjeneste der hoster din app — altså kører den på en rigtig webadresse, så andre kan åbne den. Gratis til små projekter.",
            example: "Vercel giver din app en adresse som min-app.vercel.app."),
        "checkpoint": .init(
            detail: "Stormbreakers egen fortryd-knap: før hver ændring tager den et øjebliksbillede, så du altid kan rulle tilbage hvis noget går galt. Trygt at eksperimentere.",
            example: "Fortrød du sidste ændring? Gendan til checkpointet før den."),
        "dependency": .init(
            detail: "En færdig kodepakke som din app låner og bruger, i stedet for at bygge alt fra bunden. Som at bruge færdige Lego-klodser.",
            example: "lucide-react er en dependency der giver dig pæne ikoner."),
        "plan mode": .init(
            detail: "I stedet for at bygge med det samme lægger AI'en først en plan og stiller opklarende spørgsmål. Godt til større ting, så I er enige før koden skrives.",
            example: "Slå Plan til → AI'en spørger “skal opgaver kunne slettes?” før den bygger."),
    ]

    /// The full glossary (every term across all lessons + a couple of extras),
    /// shown in the always-available "Lær"/book panel. De-duplicated by term.
    static let glossary: [Term] = {
        var seen = Set<String>()
        var result: [Term] = []
        let extras = [
            Term(term: "checkpoint", explanation: "Stormbreakers egen fortryd-funktion — et øjebliksbillede taget før hver ændring, så du kan rulle tilbage"),
            Term(term: "dependency", explanation: "en færdig kodepakke din app bruger (fx et ikon-bibliotek)"),
            Term(term: "plan mode", explanation: "lad AI'en lægge en plan og stille spørgsmål før den bygger"),
        ]
        for term in all.flatMap(\.terms) + extras where seen.insert(term.term).inserted {
            result.append(term)
        }
        return result.sorted { $0.term.lowercased() < $1.term.lowercased() }
    }()
}
