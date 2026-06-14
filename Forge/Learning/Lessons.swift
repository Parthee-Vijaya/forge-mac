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
        Fejl er helt normale, også for professionelle. Forge opdagede en error i \
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
        link. Først laver Forge en commit (et gemt øjebliksbillede af din kode) og en \
        push (uploader den til GitHub — en online tjeneste hvor kode gemmes i et \
        repository). Derefter sender den koden til Vercel, som hoster appen, altså \
        kører den på en rigtig webadresse. Du klikker bare på Deploy — Forge ordner resten.
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

    /// The full glossary (every term across all lessons + a couple of extras),
    /// shown in the always-available "Lær"/book panel. De-duplicated by term.
    static let glossary: [Term] = {
        var seen = Set<String>()
        var result: [Term] = []
        let extras = [
            Term(term: "checkpoint", explanation: "Forges egen fortryd-funktion — et øjebliksbillede taget før hver ændring, så du kan rulle tilbage"),
            Term(term: "dependency", explanation: "en færdig kodepakke din app bruger (fx et ikon-bibliotek)"),
            Term(term: "plan mode", explanation: "lad AI'en lægge en plan og stille spørgsmål før den bygger"),
        ]
        for term in all.flatMap(\.terms) + extras where seen.insert(term.term).inserted {
            result.append(term)
        }
        return result.sorted { $0.term.lowercased() < $1.term.lowercased() }
    }()
}
