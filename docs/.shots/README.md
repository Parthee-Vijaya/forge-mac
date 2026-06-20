# CLI-screenshots (generator)

Genererer terminal-screenshots af `storm`-TUI'en til websitet
(`../screenshots/10-cli.png`, `11-cli-swarm.png`, `12-cli-diff.png`, `13-cli-memory.png`,
`14-cli-commands.png`).

Pipeline (ingen installation ud over Chrome):
1. Kør `storm chat` i en tmux-session og driv den til den ønskede tilstand.
2. `tmux capture-pane -e -p -t <session> > shot.ans`
3. `python3 ansi2html.py shot.ans > shot.html`
4. `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
     --force-device-scale-factor=2 --window-size=1235,810 --screenshot=shot.png shot.html`

`ansi2html.py` konverterer tmux' ANSI-dump (truecolor/256/basic + bold/dim) til en
stylet HTML-`<pre>` på mørk baggrund. Temp-filer (.ans/.html/.png) er gitignored.
