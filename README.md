# FC Manager — build macOS

Repo minimo, solo codice sorgente, per compilare FC Manager come `.app` su macOS via GitHub Actions
(PyInstaller non cross-compila: la build gira su un runner `macos-latest`, hardware Apple vero in cloud).

Niente dati reali qui dentro: nessun database, nessuna presenza/rosa giocatori. Solo codice e asset grafici generici.

## Come lanciare la build

1. Push su `main` (o tag) → parte in automatico.
2. Oppure manualmente: tab **Actions** → *Build macOS app* → **Run workflow**.
3. A fine run, artifact **FC-Manager-macOS** scaricabile dalla pagina del run (zip con dentro `FC Manager.app`).

## Aggiornare il codice

Questo repo è una copia isolata delle sole parti necessarie alla build, presa dal repo di sviluppo
`LB Coaching` (locale, non pubblicato). Per aggiornare: ricopiare i file sorgente modificati e fare push.
