"""Esportazione PDF del report Statistiche: stesso contenuto informativo del
vecchio "ESPORTA REPORT PDF" di interfaccia_statistiche.py, con le viste
disegnate come barre orizzontali (reportlab, disegno vettoriale semplice)
invece che grafici a torta/istogrammi matplotlib - stessa semplificazione
deliberata gia' documentata in statistiche_vm.py, per non reintrodurre una
dipendenza pesante che il resto di questa ricostruzione evita di proposito.

Esporta sempre tutte e 4 le viste in un unico file: la selezione granulare
delle pagine del vecchio DialogSelezioneExport non e' stata ricostruita."""

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

LARGHEZZA, ALTEZZA = A4
MARGINE = 40
COLORE_BARRA = colors.HexColor("#3d5afe")
COLORE_BARRA_2 = colors.HexColor("#e0544f")


def _intestazione(c, titolo_gruppo, titolo_vista):
    c.setFont("Helvetica-Bold", 14)
    c.setFillColor(colors.black)
    c.drawString(MARGINE, ALTEZZA - 50, titolo_gruppo)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(MARGINE, ALTEZZA - 70, titolo_vista)
    c.line(MARGINE, ALTEZZA - 80, LARGHEZZA - MARGINE, ALTEZZA - 80)


def _disegna_barre(c, y_inizio, righe, chiave_valore, chiave_percentuale, colore=COLORE_BARRA, unita=""):
    larg_etichetta = 150
    larg_barra_max = LARGHEZZA - MARGINE * 2 - larg_etichetta - 60
    y = y_inizio
    for riga in righe:
        if y < 60:
            c.showPage()
            y = ALTEZZA - 50
        c.setFont("Helvetica", 9)
        c.setFillColor(colors.black)
        c.drawString(MARGINE, y, str(riga["nome"])[:26])
        perc = max(0, min(100, riga.get(chiave_percentuale, 0) or 0))
        larg_barra = larg_barra_max * perc / 100
        c.setFillColor(colore)
        c.rect(MARGINE + larg_etichetta, y - 3, larg_barra, 10, fill=1, stroke=0)
        c.setFillColor(colors.black)
        c.drawString(MARGINE + larg_etichetta + larg_barra_max + 8, y, f"{riga[chiave_valore]}{unita}")
        y -= 18
    return y


def esporta_statistiche_in_pdf(vm, gruppo, percorso_output):
    titolo_gruppo = f"Statistiche — {gruppo['cat']} ({gruppo['stag']})" + (f" — {gruppo['soc']}" if gruppo.get("soc") else "")
    c = canvas.Canvas(percorso_output, pagesize=A4)

    _intestazione(c, titolo_gruppo, "1. Presenze Allenamenti")
    c.setFont("Helvetica", 9)
    c.drawString(MARGINE, ALTEZZA - 95, f"Periodo: {vm.dataInizio} — {vm.dataFine}  ·  Sedute considerate: {vm.numeroSedute}")
    _disegna_barre(c, ALTEZZA - 120, vm.presenzePerGiocatore, "presenze", "percentuale", COLORE_BARRA, " pres.")

    c.showPage()
    _intestazione(c, titolo_gruppo, "2. Convocazioni Partite")
    c.setFont("Helvetica", 9)
    c.drawString(MARGINE, ALTEZZA - 95, "Tipi impegno considerati: " + (", ".join(vm.tipiSelezionati) or "nessuno"))
    _disegna_barre(c, ALTEZZA - 120, vm.convocazioniPerGiocatore, "convocazioni", "percentuale", COLORE_BARRA, " conv.")

    c.showPage()
    _intestazione(c, titolo_gruppo, "3. Risultati e Goal (Partite/Tornei)")
    c.setFont("Helvetica-Bold", 11)
    c.setFillColor(colors.black)
    c.drawString(MARGINE, ALTEZZA - 100, f"Vittorie: {vm.vittorie}    Pareggi: {vm.pareggi}    Sconfitte: {vm.sconfitte}")
    c.setFont("Helvetica-Bold", 10)
    c.drawString(MARGINE, ALTEZZA - 125, "Goal fatti per giocatore")
    y = _disegna_barre(c, ALTEZZA - 145, vm.goalPerGiocatore, "goal", "percentualeGoal", COLORE_BARRA, " goal")
    if y < 200:
        c.showPage()
        y = ALTEZZA - 50
    c.setFont("Helvetica-Bold", 10)
    c.setFillColor(colors.black)
    c.drawString(MARGINE, y - 15, "Media goal / partite giocate")
    _disegna_barre(c, y - 35, vm.goalPerGiocatore, "mediaGoal", "percentualeMedia", COLORE_BARRA_2)

    c.showPage()
    _intestazione(c, titolo_gruppo, "4. Obiettivi e Mezzi Allenamento")
    c.setFont("Helvetica-Bold", 10)
    c.setFillColor(colors.black)
    c.drawString(MARGINE, ALTEZZA - 100, "Mezzi di allenamento (minuti totali)")
    y = _disegna_barre(c, ALTEZZA - 120, vm.minutiPerMezzo, "valore", "percentuale", COLORE_BARRA, "'")
    if y < 200:
        c.showPage()
        y = ALTEZZA - 50
    c.setFont("Helvetica-Bold", 10)
    c.drawString(MARGINE, y - 15, "Obiettivi tecnici (minuti totali)")
    y = _disegna_barre(c, y - 35, vm.minutiPerTecnico, "valore", "percentuale", COLORE_BARRA, "'")
    if y < 200:
        c.showPage()
        y = ALTEZZA - 50
    c.setFont("Helvetica-Bold", 10)
    c.drawString(MARGINE, y - 15, "Obiettivi tattici (minuti totali)")
    _disegna_barre(c, y - 35, vm.minutiPerTattico, "valore", "percentuale", COLORE_BARRA, "'")

    c.save()
