const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";          // 13.33 x 7.5
pres.author = "Stormbreaker";
pres.title = "Stormbreaker CLI — Arkitektur";

// ---- palette (dark, terminal/storm-themed) ----
const C = {
  bg: "0E1217", bg2: "0B0F14", panel: "1A222C", panel2: "232E3A",
  line: "303D4A", text: "E8EEF4", muted: "9AA9B8", faint: "67747F",
  blue: "46B1FF", amber: "F5B748", green: "5DD39E", purple: "B98BFF", red: "FF7A7A",
};
const HEAD = "Consolas", BODY = "Calibri";
const M = 0.6, CW = 13.33 - 2 * M;     // margin + content width

const sh = () => ({ type: "outer", color: "000000", blur: 9, offset: 3, angle: 135, opacity: 0.30 });

function bg(s, dark) { s.background = { color: dark || C.bg }; }
function kicker(s, t) { s.addText(t, { x: M, y: 0.40, w: CW, h: 0.3, fontFace: HEAD, fontSize: 12, color: C.blue, bold: true, charSpacing: 3, margin: 0 }); }
function title(s, t) { s.addText(t, { x: M, y: 0.70, w: CW, h: 0.7, fontFace: HEAD, fontSize: 29, color: C.text, bold: true, margin: 0 }); }
function footer(s, n) {
  s.addText("Stormbreaker CLI · arkitektur", { x: M, y: 7.06, w: 8, h: 0.3, fontFace: BODY, fontSize: 9, color: C.faint, margin: 0 });
  s.addText(String(n).padStart(2, "0"), { x: 13.33 - M - 0.6, y: 7.06, w: 0.6, h: 0.3, fontFace: HEAD, fontSize: 9, color: C.faint, align: "right", margin: 0 });
}
function hex(s, x, y, size, color, trans) {
  s.addShape(pres.shapes.HEXAGON, { x, y, w: size, h: size * 0.88, fill: { color, transparency: trans == null ? 0 : trans } });
}
function card(s, x, y, w, h, fill, border) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fill || C.panel }, line: { color: border || C.line, width: 1 }, shadow: sh() });
}
function dot(s, x, y, color, sz) { s.addShape(pres.shapes.RECTANGLE, { x, y, w: sz || 0.17, h: sz || 0.17, fill: { color } }); }
function arrow(s, x, y, w, h, color) { s.addShape(pres.shapes.LINE, { x, y, w, h, line: { color: color || C.faint, width: 1.5, endArrowType: "triangle" } }); }

// ============================================================ 1 · TITLE
let s = pres.addSlide(); bg(s, C.bg2);
hex(s, 11.7, 0.7, 1.5, C.blue, 78);
hex(s, 12.3, 4.9, 1.1, C.amber, 84);
s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.16, h: 7.5, fill: { color: C.blue } });
s.addText("STORMBREAKER · ARKITEKTUR", { x: M + 0.3, y: 1.55, w: 10, h: 0.4, fontFace: HEAD, fontSize: 14, color: C.blue, bold: true, charSpacing: 4, margin: 0 });
s.addText([{ text: "storm", options: { color: C.text } }, { text: " — CLI'en", options: { color: C.muted } }],
  { x: M + 0.25, y: 2.0, w: 12, h: 1.2, fontFace: HEAD, fontSize: 60, bold: true, margin: 0 });
s.addText("En lokal-først vibecoding-agent der bygger web-apps — direkte i terminalen.",
  { x: M + 0.3, y: 3.35, w: 11.5, h: 0.5, fontFace: BODY, fontSize: 20, color: C.text, margin: 0 });
s.addText("zero dependencies   ·   én motor, to overflader   ·   224 tests grønne",
  { x: M + 0.3, y: 3.95, w: 11.5, h: 0.4, fontFace: BODY, fontSize: 14, color: C.muted, italic: true, margin: 0 });
// faux terminal line
card(s, M + 0.3, 4.95, 7.6, 0.85, C.panel, C.line);
s.addText([{ text: "$ ", options: { color: C.green } }, { text: "storm chat --project ./min-app", options: { color: C.text } }, { text: "  ▍", options: { color: C.blue } }],
  { x: M + 0.55, y: 4.95, w: 7.2, h: 0.85, fontFace: HEAD, fontSize: 17, valign: "middle", margin: 0 });
s.addText("Parthee-Vijaya/stormbreaker-mac   ·   2026", { x: M + 0.3, y: 6.7, w: 11, h: 0.3, fontFace: BODY, fontSize: 11, color: C.faint, margin: 0 });

// ============================================================ 2 · HVAD ER STORM
s = pres.addSlide(); bg(s);
kicker(s, "OVERBLIK"); title(s, "Hvad er storm?");
s.addText([
  { text: "Du beskriver hvad du vil have. ", options: { bold: true, color: C.text, breakLine: true } },
  { text: "Agenten skriver filerne, installerer afhængigheder, starter dev-serveren, læser fejlene og retter sig selv — mens du følger med live i terminalen.", options: { color: C.muted, breakLine: true } },
  { text: "" , options: { breakLine: true, fontSize: 6 } },
  { text: "Bygger React / Svelte / Vue / Next + Vite + Tailwind. Samme motor som Mac-appen.", options: { color: C.muted } },
], { x: M, y: 1.7, w: 6.9, h: 2.4, fontFace: BODY, fontSize: 16, lineSpacingMultiple: 1.15, margin: 0, valign: "top" });

const stats = [["0", "eksterne\nafhængigheder", C.blue], ["13", "undersystemer\ni motoren", C.green], ["7", "model-\nproviders", C.amber]];
stats.forEach((d, i) => {
  const x = 7.61 + i * 1.76;          // right-aligned block, ends exactly at the 0.6" margin
  card(s, x, 1.7, 1.6, 1.7, C.panel);
  s.addText(d[0], { x, y: 1.78, w: 1.6, h: 0.9, fontFace: HEAD, fontSize: 40, bold: true, color: d[2], align: "center", margin: 0 });
  s.addText(d[1], { x, y: 2.62, w: 1.6, h: 0.7, fontFace: BODY, fontSize: 11.5, color: C.muted, align: "center", margin: 0 });
});

const princ = [
  ["Zero dependencies", "Hele TUI'en er håndbygget på termios + ANSI — ingen ncurses, intet tredjeparts-TUI-bibliotek. Motoren har heller ingen eksterne deps.", C.blue],
  ["Én motor, to overflader", "Præcis samme StormbreakerKit driver både Mac-appen og CLI'en. Kun præsentationslaget er forskelligt — adfærd er identisk.", C.amber],
];
princ.forEach((p, i) => {
  const x = M + i * 6.27;
  card(s, x, 3.95, 5.86, 1.95, C.panel);
  dot(s, x + 0.3, 4.22, p[2]);
  s.addText(p[0], { x: x + 0.6, y: 4.12, w: 5.0, h: 0.4, fontFace: HEAD, fontSize: 17, bold: true, color: C.text, margin: 0 });
  s.addText(p[1], { x: x + 0.3, y: 4.62, w: 5.26, h: 1.2, fontFace: BODY, fontSize: 13, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.1 });
});
footer(s, 2);

// ============================================================ 3 · TARGETS
s = pres.addSlide(); bg(s);
kicker(s, "SWIFT PACKAGE"); title(s, "Tre targets");
const targets = [
  ["storm", "executable", "Terminal-klienten: arg-parsing, subkommandoer (new · build · chat · skills · mcp) og den @MainActor fuld-skærms-TUI der tegner alt.", C.blue],
  ["storm-mcp", "executable", "En MCP-server med 5 værktøjer (list/read/write_file · run_command · get_errors) — så Claude Code og andre agenter kan drive et projekt.", C.green],
  ["StormbreakerKit", "library", "Den delte motor (zero-dep): agent-loop, parser, providers, proces-styring, hukommelse, prompt-bygning, render-primitiver. Deles med Mac-appen.", C.amber],
];
targets.forEach((t, i) => {
  const x = M + i * 4.11;
  card(s, x, 1.7, 3.85, 4.6, C.panel);
  s.addShape(pres.shapes.RECTANGLE, { x, y: 1.7, w: 3.85, h: 0.12, fill: { color: t[3] } });
  s.addText(t[0], { x: x + 0.3, y: 2.05, w: 3.3, h: 0.5, fontFace: HEAD, fontSize: 21, bold: true, color: C.text, margin: 0 });
  s.addText(t[1].toUpperCase(), { x: x + 0.3, y: 2.55, w: 3.3, h: 0.3, fontFace: HEAD, fontSize: 11, bold: true, color: t[3], charSpacing: 2, margin: 0 });
  s.addText(t[2], { x: x + 0.3, y: 3.0, w: 3.3, h: 3.1, fontFace: BODY, fontSize: 14, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.2 });
});
footer(s, 3);

// ============================================================ 4 · LAGDELT ARKITEKTUR
s = pres.addSlide(); bg(s);
kicker(s, "OVERBLIK"); title(s, "Lagdelt arkitektur");
// top band: storm CLI + storm-mcp
card(s, M, 1.55, 8.05, 1.95, C.panel);
s.addText("storm — CLI executable", { x: M + 0.25, y: 1.65, w: 6, h: 0.35, fontFace: HEAD, fontSize: 14, bold: true, color: C.blue, margin: 0 });
// inner: main + TUI
s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M + 0.25, y: 2.08, w: 2.4, h: 1.18, rectRadius: 0.06, fill: { color: C.panel2 }, line: { color: C.line, width: 1 } });
s.addText([{ text: "main.swift", options: { bold: true, color: C.text, breakLine: true } }, { text: "subkommandoer ·\narg-parsing · Engine", options: { color: C.muted, fontSize: 10 } }], { x: M + 0.4, y: 2.2, w: 2.15, h: 0.95, fontFace: HEAD, fontSize: 12, margin: 0, valign: "top" });
s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M + 2.85, y: 2.08, w: 5.0, h: 1.18, rectRadius: 0.06, fill: { color: C.panel2 }, line: { color: C.line, width: 1 } });
s.addText([{ text: "TUI-lag  (terminal-bundet)", options: { bold: true, color: C.text, breakLine: true } }, { text: "App.swift @MainActor event-loop · Terminal/Output/StdinReader · Theme/Diff/Quotes · Session", options: { color: C.muted, fontSize: 10 } }], { x: M + 3.0, y: 2.2, w: 4.7, h: 0.95, fontFace: HEAD, fontSize: 12, margin: 0, valign: "top" });

card(s, M + 8.45, 1.55, 3.68, 1.95, C.panel);
s.addText("storm-mcp — MCP-server", { x: M + 8.7, y: 1.65, w: 3.3, h: 0.35, fontFace: HEAD, fontSize: 14, bold: true, color: C.green, margin: 0 });
s.addText("5 værktøjer over stdio JSON-RPC:\nlist/read/write_file ·\nrun_command · get_errors", { x: M + 8.7, y: 2.12, w: 3.2, h: 1.1, fontFace: HEAD, fontSize: 11, color: C.muted, margin: 0, valign: "top" });

// connectors down
arrow(s, M + 4.0, 3.5, 0, 0.55, C.blue);
arrow(s, M + 10.3, 3.5, 0, 0.55, C.green);

// kit band
card(s, M, 4.15, CW, 2.55, C.bg2, C.blue);
s.addText("StormbreakerKit — delt motor (zero deps)", { x: M + 0.25, y: 4.25, w: 8, h: 0.35, fontFace: HEAD, fontSize: 14, bold: true, color: C.text, margin: 0 });
const subs = ["Agent", "Artifact", "Execution", "Prompt", "Provider", "Router", "Process", "Feedback", "MCP", "Review", "Skills", "Template"];
const cols = 6, cw = (CW - 0.5 - (cols - 1) * 0.16) / cols, chh = 0.78;
subs.forEach((name, i) => {
  const r = Math.floor(i / cols), col = i % cols;
  const x = M + 0.25 + col * (cw + 0.16), y = 4.7 + r * (chh + 0.14);
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: chh, rectRadius: 0.05, fill: { color: C.panel }, line: { color: C.line, width: 1 } });
  s.addText(name, { x, y, w: cw, h: chh, fontFace: HEAD, fontSize: 12.5, bold: true, color: C.blue, align: "center", valign: "middle", margin: 0 });
});
s.addText("+ Highlight (SyntaxRules) · TUI render-core (Surface · Cell · Layout · Diff · TextWidth)", { x: M, y: 6.36, w: CW, h: 0.28, fontFace: BODY, fontSize: 10.5, color: C.faint, align: "center", margin: 0 });
footer(s, 4);

// ============================================================ 5 · ENGINE
s = pres.addSlide(); bg(s);
kicker(s, "PR. PROJEKT"); title(s, "Engine — det der wires sammen");
s.addText("main.swift samler én Engine med de levende komponenter for ét projekt. Hver tur bygges en frisk AgentLoop.Dependencies oven på den.",
  { x: M, y: 1.55, w: CW, h: 0.55, fontFace: BODY, fontSize: 14, color: C.muted, margin: 0 });
const eng = [
  ["workspace", "ProjectWorkspace — læs/skriv filer + fil-map", C.blue],
  ["devServer", "DevServerManager — Vite + log-tailing + tsc", C.green],
  ["collector", "ErrorCollector — samler build/runtime-fejl pr. tur", C.amber],
  ["config", "ModelConfig (var) — /model skifter model midt i en session", C.blue],
  ["mcp", "MCPManager — klient til eksterne MCP-værktøjer", C.green],
  ["checkpoints", "CheckpointManager — shadow-git → /diff /undo /restore", C.amber],
];
const ec = 3, ecw = (CW - (ec - 1) * 0.3) / ec, ech = 1.55;
eng.forEach((e, i) => {
  const r = Math.floor(i / ec), col = i % ec;
  const x = M + col * (ecw + 0.3), y = 2.3 + r * (ech + 0.3);
  card(s, x, y, ecw, ech, C.panel);
  dot(s, x + 0.3, y + 0.32, e[2]);
  s.addText(e[0], { x: x + 0.6, y: 0.22 + y, w: ecw - 0.8, h: 0.4, fontFace: HEAD, fontSize: 17, bold: true, color: C.text, margin: 0 });
  s.addText(e[1], { x: x + 0.3, y: y + 0.72, w: ecw - 0.6, h: 0.7, fontFace: BODY, fontSize: 13, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.1 });
});
footer(s, 5);

// ============================================================ 6 · DATA-FLOW
s = pres.addSlide(); bg(s);
kicker(s, "EN BYGGEOPGAVE"); title(s, "Sådan flyder en tur gennem systemet");
const steps = [
  ["1", "Snapshot", "checkpoint før turen"],
  ["2", "Compaction", "summarér hvis over budget"],
  ["3", "Hent URL'er", "pastede links → indhold"],
  ["4", "Byg prompt", "base + regler + hukommelse"],
  ["5", "AgentLoop", "stream → parse → skriv"],
  ["6", "Selv-ret", "≤ 3 fejl-forsøg"],
  ["7", "Clean ✓", "appen kører rent"],
];
const sw = 1.56, sgap = (CW - steps.length * sw) / (steps.length - 1);
steps.forEach((st, i) => {
  const x = M + i * (sw + sgap);
  const accent = i === 6 ? C.green : C.blue;
  card(s, x, 1.75, sw, 1.5, C.panel, i === 6 ? C.green : C.line);
  s.addShape(pres.shapes.OVAL, { x: x + sw / 2 - 0.22, y: 1.92, w: 0.44, h: 0.44, fill: { color: accent } });
  s.addText(st[0], { x: x + sw / 2 - 0.22, y: 1.92, w: 0.44, h: 0.44, fontFace: HEAD, fontSize: 16, bold: true, color: C.bg, align: "center", valign: "middle", margin: 0 });
  s.addText(st[1], { x, y: 2.45, w: sw, h: 0.35, fontFace: HEAD, fontSize: 13, bold: true, color: C.text, align: "center", margin: 0 });
  s.addText(st[2], { x: x + 0.08, y: 2.8, w: sw - 0.16, h: 0.4, fontFace: BODY, fontSize: 10, color: C.muted, align: "center", margin: 0 });
  if (i < steps.length - 1) arrow(s, x + sw + 0.02, 2.5, sgap - 0.04, 0, C.faint);
});
// loop callout
card(s, M, 3.95, CW, 2.45, C.bg2, C.amber);
s.addText("Inde i AgentLoop — runder der IKKE tæller som fejl-forsøg", { x: M + 0.3, y: 4.12, w: 10, h: 0.4, fontFace: HEAD, fontSize: 15, bold: true, color: C.amber, margin: 0 });
const rounds = [
  ["Læse-fil", "modellen beder om en fils indhold → sendes tilbage", C.blue],
  ["MCP-værktøj", "kalder et eksternt MCP-værktøj, fodrer resultatet ind", C.green],
  ["Web (søg/hent)", "DuckDuckGo-søg eller URL/README — utroværdig reference", C.purple],
  ["Todo → PLAN", "modellens plan vises live som tjekliste i sidebjælken", C.amber],
];
const rc = 4, rcw = (CW - 0.5 - (rc - 1) * 0.2) / rc;
rounds.forEach((rd, i) => {
  const x = M + 0.25 + i * (rcw + 0.2), y = 4.6;
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: rcw, h: 1.0, rectRadius: 0.05, fill: { color: C.panel }, line: { color: C.line, width: 1 } });
  dot(s, x + 0.2, y + 0.2, rd[2], 0.13);
  s.addText(rd[0], { x: x + 0.42, y: y + 0.12, w: rcw - 0.6, h: 0.3, fontFace: HEAD, fontSize: 12.5, bold: true, color: C.text, margin: 0 });
  s.addText(rd[1], { x: x + 0.2, y: y + 0.45, w: rcw - 0.4, h: 0.5, fontFace: BODY, fontSize: 10.5, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.05 });
});
s.addText("Repair-loopet er KUN for ægte build/runtime-fejl (tsc + console), maks. 3 forsøg med en ingen-fremgang-vagt.", { x: M, y: 6.5, w: CW, h: 0.3, fontFace: BODY, fontSize: 11, color: C.faint, align: "center", italic: true, margin: 0 });
footer(s, 6);

// ============================================================ 7 · UNDERSYSTEMER (grouped)
s = pres.addSlide(); bg(s);
kicker(s, "MOTOREN"); title(s, "Undersystemer, grupperet");
const groups = [
  ["Modellen", C.blue, [
    ["Provider", "Anthropic · OpenAI-kompat · Ollama · SSE"],
    ["Router", "ModelConfig · ModelRouter · Discovery"],
    ["Prompt", "SystemPrompt · MessageBuilder · Context · Memory"],
    ["Agent", "Loop · tilstand · compaction · todos"],
  ]],
  ["Handling & filer", C.green, [
    ["Artifact", "Streaming-parser · ParserEvent · actions"],
    ["Execution", "ActionExecutor · ShellRules · gate"],
    ["Process", "Workspace · DevServer · Checkpoints · Git · Web"],
    ["Feedback", "ErrorCollector · Classifier · Report"],
  ]],
  ["Udvidelser & UI", C.purple, [
    ["MCP", "Klient til eksterne værktøjer (stdio)"],
    ["Review", "4 parallelle gennemgangs-agenter"],
    ["Skills", "Bruger-presets i markdown"],
    ["Template", "React · Svelte · Vue · Next"],
  ]],
];
const gcw = (CW - 2 * 0.4) / 3;
groups.forEach((g, gi) => {
  const x = M + gi * (gcw + 0.4);
  dot(s, x, 1.62, g[1], 0.2);
  s.addText(g[0], { x: x + 0.3, y: 1.52, w: gcw - 0.3, h: 0.4, fontFace: HEAD, fontSize: 15, bold: true, color: g[1], margin: 0 });
  g[2].forEach((it, ii) => {
    const y = 2.05 + ii * 1.12;
    card(s, x, y, gcw, 1.0, C.panel);
    s.addText(it[0], { x: x + 0.25, y: y + 0.13, w: gcw - 0.5, h: 0.32, fontFace: HEAD, fontSize: 14, bold: true, color: C.text, margin: 0 });
    s.addText(it[1], { x: x + 0.25, y: y + 0.46, w: gcw - 0.5, h: 0.5, fontFace: BODY, fontSize: 11, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.05 });
  });
});
s.addText("Render-kerne: Surface · Cell · Layout · Diff · TextWidth · SyntaxRules — rene, CI-testbare primitiver, delt med Mac-appen.", { x: M, y: 6.65, w: CW, h: 0.3, fontFace: BODY, fontSize: 11, color: C.faint, align: "center", italic: true, margin: 0 });
footer(s, 7);

// ============================================================ 8 · SYSTEM-PROMPT LAG
s = pres.addSlide(); bg(s);
kicker(s, "KONTEKST"); title(s, "System-prompten bygges i lag");
s.addText("For hver tur stabler makeDeps konteksten oppefra:", { x: M, y: 1.55, w: CW, h: 0.4, fontFace: BODY, fontSize: 14, color: C.muted, margin: 0 });
const layers = [
  ["Base-prompt", "SystemPrompt.storm — format, few-shot, web/todo-sektioner", C.blue],
  ["+ MCP-værktøjer", "liste over tilgængelige eksterne værktøjer (hvis konfigureret)", C.green],
  ["+ Projekt-regler", "AGENTS.md / AI_RULES.md (RulesLoader, læses hver tur)", C.amber],
  ["+ Hukommelse", "StormMemory.promptBlock — token-budgetteret, aktive fakta", C.purple],
];
layers.forEach((l, i) => {
  const y = 2.2 + i * 0.92;
  const w = CW - 3.0;
  card(s, M, y, w, 0.78, C.panel, l[2]);
  dot(s, M + 0.28, y + 0.31, l[2]);
  s.addText(l[0], { x: M + 0.6, y: y + 0.08, w: 3.0, h: 0.6, fontFace: HEAD, fontSize: 15, bold: true, color: C.text, valign: "middle", margin: 0 });
  s.addText(l[1], { x: M + 3.7, y: y, w: w - 3.9, h: 0.78, fontFace: BODY, fontSize: 12.5, color: C.muted, valign: "middle", margin: 0 });
  if (i < layers.length - 1) arrow(s, M + w / 2, y + 0.78, 0, 0.14, C.faint);
});
// result box on the right
card(s, M + CW - 2.7, 2.2, 2.7, 3.7, C.bg2, C.blue);
s.addText("=", { x: M + CW - 2.7, y: 3.1, w: 2.7, h: 0.6, fontFace: HEAD, fontSize: 30, bold: true, color: C.faint, align: "center", margin: 0 });
s.addText("Endelig\nsystem-prompt", { x: M + CW - 2.7, y: 3.7, w: 2.7, h: 0.8, fontFace: HEAD, fontSize: 16, bold: true, color: C.text, align: "center", margin: 0 });
s.addText("→ AgentLoop.run", { x: M + CW - 2.7, y: 4.5, w: 2.7, h: 0.4, fontFace: HEAD, fontSize: 12, color: C.blue, align: "center", margin: 0 });
s.addText("Stærke cloud-modeller får line-replace (målrettede diffs); svage lokale modeller bliver på hele-fil-skrivning. Plan-mode bruger en separat prompt der forbyder kode.", { x: M, y: 6.15, w: CW - 2.9, h: 0.8, fontFace: BODY, fontSize: 12, color: C.faint, italic: true, margin: 0, valign: "top" });
footer(s, 8);

// ============================================================ 9 · PERSISTENS
s = pres.addSlide(); bg(s);
kicker(s, "HVAD GEMMES HVOR"); title(s, "Persistens");
const stores = [
  ["~/.config/storm/", "Om dig + maskinen", C.blue, [
    ["config.json", "provider · model · tema (0600)"],
    ["memory.json", "globale fakta om dig"],
    ["skills/*.md", "globale skills"],
  ]],
  ["<projekt>/.forge/", "Om denne kodebase", C.green, [
    ["session.json", "transcript (--resume) — ALDRIG apiKey"],
    ["memory.json", "projekt-fakta"],
    ["checkpoints.git", "shadow-repo, ét snapshot pr. tur"],
    [".mcp.json", "eksterne MCP-servere"],
  ]],
  ["<projekt>/", "I selve repoet", C.amber, [
    ["AGENTS.md", "projekt-regler (læses hver tur)"],
    ["AI_RULES.md", "Stormbreaker-specifikke regler"],
  ]],
];
const pcw = (CW - 2 * 0.4) / 3;
stores.forEach((st, i) => {
  const x = M + i * (pcw + 0.4);
  card(s, x, 1.6, pcw, 4.7, C.panel);
  s.addShape(pres.shapes.RECTANGLE, { x, y: 1.6, w: pcw, h: 0.12, fill: { color: st[2] } });
  s.addText(st[0], { x: x + 0.25, y: 1.85, w: pcw - 0.5, h: 0.35, fontFace: HEAD, fontSize: 15, bold: true, color: C.text, margin: 0 });
  s.addText(st[1].toUpperCase(), { x: x + 0.25, y: 2.2, w: pcw - 0.5, h: 0.3, fontFace: HEAD, fontSize: 10, bold: true, color: st[2], charSpacing: 1.5, margin: 0 });
  st[3].forEach((f, fi) => {
    const y = 2.7 + fi * 0.84;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x + 0.22, y, w: pcw - 0.44, h: 0.72, rectRadius: 0.05, fill: { color: C.panel2 }, line: { color: C.line, width: 1 } });
    s.addText(f[0], { x: x + 0.4, y: y + 0.08, w: pcw - 0.7, h: 0.3, fontFace: HEAD, fontSize: 12.5, bold: true, color: st[2], margin: 0 });
    s.addText(f[1], { x: x + 0.4, y: y + 0.38, w: pcw - 0.7, h: 0.3, fontFace: BODY, fontSize: 10.5, color: C.muted, margin: 0 });
  });
});
s.addText("API-nøgler gemmes ALDRIG — de genskabes fra config/env/--api-key ved opstart.", { x: M, y: 6.5, w: CW, h: 0.3, fontFace: BODY, fontSize: 12, color: C.red, align: "center", bold: true, margin: 0 });
footer(s, 9);

// ============================================================ 10 · DET DER BLEV BYGGET
s = pres.addSlide(); bg(s);
kicker(s, "SENESTE FUNKTIONER"); title(s, "Det der blev bygget");
const feats = [
  ["Per-kommando shell-tilladelser", "Sikre kommandoer kører uden prompt; katastrofale (rm -rf /, sudo, curl|sh) afvises; resten spørger.", C.blue],
  ["Web som agent-værktøj", "Modellen kan selv søge (DuckDuckGo) og hente URL'er/READMEs midt i en build i stedet for at gætte.", C.green],
  ["Live todo-checklist", "Modellens plan vises som et PLAN-panel (✓/spinner/○) mens koden streames.", C.amber],
  ["Samtale-compaction", "Summerer ældste ture når historikken bliver for stor — små lokale kontekstvinduer løber ikke over.", C.purple],
  ["Cross-session hukommelse", "Husker dig + projektet mellem sessioner (/remember, /memory). Lånt fra iai-pme, native uden daemon.", C.red],
];
// first row 3, second row 2 (centered-ish)
const fcw = (CW - 2 * 0.3) / 3, fch = 2.0;
feats.forEach((f, i) => {
  let x, y;
  if (i < 3) { x = M + i * (fcw + 0.3); y = 1.7; }
  else { const j = i - 3; x = M + (fcw + 0.3) * 0.5 + j * (fcw + 0.3); y = 3.85; }
  card(s, x, y, fcw, fch, C.panel);
  dot(s, x + 0.28, y + 0.3, f[2]);
  s.addText(f[0], { x: x + 0.56, y: y + 0.2, w: fcw - 0.8, h: 0.6, fontFace: HEAD, fontSize: 14, bold: true, color: C.text, margin: 0, valign: "top" });
  s.addText(f[1], { x: x + 0.28, y: y + 0.85, w: fcw - 0.56, h: 1.0, fontFace: BODY, fontSize: 12.5, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.12 });
});
footer(s, 10);

// ============================================================ 11 · SLASH-KOMMANDOER
s = pres.addSlide(); bg(s);
kicker(s, "I TUI'EN"); title(s, "Slash-kommandoer");
const cmdGroups = [
  ["Byg & ret", C.blue, [["/diff [n]", "ændringer fra tur n"], ["/undo · /restore", "rul filer tilbage"], ["/checkpoints", "liste over ture"], ["/review · /fix", "4 agenter · ret fund"]]],
  ["Model & kontekst", C.green, [["/model", "skift AI-model"], ["/compact", "komprimér historik"], ["/remember [tekst]", "husk / lær af session"], ["/memory", "vis · glem fakta"]]],
  ["Projekt & Git", C.amber, [["/init · /theme", "AGENTS.md · tema"], ["/github · /pr", "udgiv · pull request"], ["/push · /pull · /commit", "git-arbejdsgang"], ["/kø <opgave>", "byg-kø (én ad gangen)"]]],
];
const ccw = (CW - 2 * 0.4) / 3;
cmdGroups.forEach((g, gi) => {
  const x = M + gi * (ccw + 0.4);
  card(s, x, 1.65, ccw, 4.6, C.panel);
  s.addShape(pres.shapes.RECTANGLE, { x, y: 1.65, w: ccw, h: 0.12, fill: { color: g[1] } });
  s.addText(g[0], { x: x + 0.28, y: 1.92, w: ccw - 0.5, h: 0.4, fontFace: HEAD, fontSize: 16, bold: true, color: g[1], margin: 0 });
  g[2].forEach((c, ci) => {
    const y = 2.55 + ci * 0.9;
    s.addText(c[0], { x: x + 0.28, y, w: ccw - 0.56, h: 0.32, fontFace: HEAD, fontSize: 14, bold: true, color: C.text, margin: 0 });
    s.addText(c[1], { x: x + 0.28, y: y + 0.32, w: ccw - 0.56, h: 0.3, fontFace: BODY, fontSize: 11.5, color: C.muted, margin: 0 });
  });
});
s.addText("Fuld-skærms-TUI tænder kun på en interaktiv terminal — --plain / --no-tui giver byte-identisk linje-output (CI/scripting).", { x: M, y: 6.45, w: CW, h: 0.35, fontFace: BODY, fontSize: 11.5, color: C.faint, align: "center", italic: true, margin: 0 });
footer(s, 11);

// ============================================================ 12 · DESIGNVALG + OUTRO
s = pres.addSlide(); bg(s, C.bg2);
s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.16, h: 7.5, fill: { color: C.blue } });
hex(s, 11.9, 5.3, 1.3, C.blue, 80);
kicker(s, "AFRUNDING"); title(s, "Designvalg værd at kende");
const choices = [
  ["Flicker-fri render", "Hele rammen komponeres i én ScreenBuffer, row-diffes, og skrives som ÉN write(2) pr. frame (≤60fps).", C.blue],
  ["Swift 6 strict concurrency", "App er @MainActor; baggrunds-callbacks er eksplicit @Sendable for at undgå actor-traps.", C.green],
  ["Ikke-blokerende tilladelser", "Permission-gaten suspenderer på en continuation der løses på et tastetryk — UI'en animerer videre.", C.amber],
  ["CI/scripting-sikker", "TUI kun på interaktiv TTY; --plain/--no-tui er byte-identisk. forge-cross røres aldrig.", C.purple],
];
choices.forEach((c, i) => {
  const x = M + (i % 2) * 6.27, y = 1.7 + Math.floor(i / 2) * 1.7;
  card(s, x, y, 5.86, 1.5, C.panel);
  dot(s, x + 0.3, y + 0.28, c[2]);
  s.addText(c[0], { x: x + 0.6, y: y + 0.18, w: 5.1, h: 0.4, fontFace: HEAD, fontSize: 15, bold: true, color: C.text, margin: 0 });
  s.addText(c[1], { x: x + 0.3, y: y + 0.62, w: 5.3, h: 0.8, fontFace: BODY, fontSize: 12, color: C.muted, margin: 0, valign: "top", lineSpacingMultiple: 1.1 });
});
card(s, M, 5.25, CW, 1.0, C.panel, C.green);
s.addText([{ text: "$ ", options: { color: C.green } }, { text: "curl -fsSL https://parthee-vijaya.github.io/stormbreaker-mac/install.sh | sh", options: { color: C.text } }], { x: M + 0.3, y: 5.25, w: CW - 0.6, h: 1.0, fontFace: HEAD, fontSize: 15, valign: "middle", margin: 0 });
s.addText("docs/CLI-ARCHITECTURE.md  ·  fuld arkitektur med diagrammer", { x: M, y: 6.45, w: CW, h: 0.3, fontFace: BODY, fontSize: 11, color: C.faint, margin: 0 });

pres.writeFile({ fileName: "/Users/parthee/Desktop/Claude/projekter/aktive/forge/docs/Stormbreaker-CLI-Arkitektur.pptx" }).then(f => console.log("WROTE", f));
