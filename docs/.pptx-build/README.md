# CLI-arkitektur-deck (generator)

Genererer [`../Stormbreaker-CLI-Arkitektur.pptx`](../Stormbreaker-CLI-Arkitektur.pptx) —
en visuel præsentation af `storm`-CLI'ens arkitektur (samme indhold som
[`../CLI-ARCHITECTURE.md`](../CLI-ARCHITECTURE.md), bare som slides).

## Byg igen

```bash
cd docs/.pptx-build
npm install        # henter pptxgenjs
npm run build      # skriver ../Stormbreaker-CLI-Arkitektur.pptx
```

Alt indhold + layout bor i `gen.js` (ren pptxgenjs, ingen template). Rediger dér og
kør `npm run build` igen. Mørkt terminal-tema; 12 slides; dansk.
