import textwrap
import os
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.utils import ImageReader

from data_manager import DataManager

# Codice salvato da SeduteVM.impostaFaseBlocco (CSV di "attivazione"/"centrale"/
# "finale", vedi FASI_BLOCCO_VALIDE) -> etichetta mostrata nel PDF, stesse
# etichette dei chip in Sedute.qml.
ETICHETTE_FASE = {"attivazione": "Attivazione", "centrale": "Fase centrale", "finale": "Fase finale"}


# Aggiunto il parametro societa_stampa
def esporta_seduta_in_pdf(dati_utente, id_seduta, percorso_output, societa_stampa=None, obiettivo_principale=None):
    # FIX: la firma precedente accettava solo un flag `offline` e ricostruiva
    # un dati_utente_tmp = {"offline": offline}, perdendo il token di sessione.
    # Per gli utenti cloud (offline=False), DataManager.get_seduta_dettaglio
    # chiamava il server senza header Authorization: il server rispondeva 401,
    # get_seduta_dettaglio interpretava la mancata risposta 200 come "None", e
    # qui sotto veniva mostrato l'errore fuorviante "Seduta non trovata nel
    # database" — in realtà era sempre e solo un problema di autenticazione,
    # quindi l'esportazione PDF era rotta per OGNI utente cloud. Ora riceviamo
    # l'intero dati_utente (che include già "offline" e "token") dal chiamante
    # invece di ricostruirne uno incompleto qui.
    try:
        seduta_dati = DataManager.get_seduta_dettaglio(dati_utente, id_seduta)
        if not seduta_dati:
            return False, "Seduta non trovata nel database."
    except Exception as e:
        return False, f"Errore durante il recupero dei dati: {e}"

    data_seduta = seduta_dati.get("data_seduta", "")
    numero_seduta = seduta_dati.get("numero_seduta", "")
    categoria = seduta_dati.get("categoria", "")
    stagione = seduta_dati.get("stagione", "")
    giocatori = seduta_dati.get("giocatori", 0)
    
    try:
        anno, mese, giorno = data_seduta.split('-')
        data_formattata = f"{giorno}-{mese}-{anno}"
    except Exception:
        data_formattata = data_seduta 
        
    giocatori_testo = str(giocatori) if giocatori else "N/D"
    
    # Se il mister ha scritto qualcosa nel campo di testo, usiamo quello, 
    # altrimenti usiamo il nome della cartella (strutturale) o N/D
    if societa_stampa and societa_stampa.strip() != "":
        societa_testo = societa_stampa.strip()
    else:
        societa_strutturale = seduta_dati.get("societa", "")
        societa_testo = str(societa_strutturale) if societa_strutturale else "N/D"

    # Stesso pattern di societa_stampa: se il campo e' stato appena digitato
    # in Sedute.qml ma non ancora salvato, l'esportazione deve comunque
    # riflettere cio' che l'utente vede a schermo, non il dato su disco.
    if obiettivo_principale is not None and obiettivo_principale.strip() != "":
        obiettivo_testo = obiettivo_principale.strip()
    else:
        obiettivo_strutturale = seduta_dati.get("obiettivo_principale", "")
        obiettivo_testo = str(obiettivo_strutturale).strip() if obiettivo_strutturale else ""

    # Spazio riservato per l'obiettivo principale nell'header e' fisso (2
    # righe al massimo, sempre le stesse coordinate), cosi' l'impaginazione
    # dei blocchi sotto resta identica sia col campo vuoto sia compilato:
    # l'unico modo per garantire "1 foglio per 4 blocchi" senza dover
    # ricalcolare y_corrente in base al contenuto.
    etichetta_obiettivo = f"OBIETTIVO PRINCIPALE: {obiettivo_testo}" if obiettivo_testo else ""
    righe_obiettivo = textwrap.wrap(etichetta_obiettivo, width=95) if etichetta_obiettivo else []
    if len(righe_obiettivo) > 2:
        righe_obiettivo = righe_obiettivo[:2]
        righe_obiettivo[1] = righe_obiettivo[1].rstrip() + "…"

    # FIX: da qui in poi (creazione canvas, disegno, salvataggio su disco)
    # non c'era alcuna gestione errori, a differenza della sezione di lettura
    # dati qui sopra che è già protetta da try/except. Un percorso non
    # scrivibile (permessi, unità di rete disconnessa, nome file non valido)
    # o un errore imprevisto durante il disegno risalivano non gestiti fino
    # al chiamante (un click su un pulsante "Esporta PDF" in
    # interfaccia_seduta.py/interfaccia_seduta_gk.py, anch'essi privi di
    # try/except attorno alla chiamata): un errore imprevisto nel thread
    # dell'interfaccia grafica, invece di un messaggio d'errore leggibile.
    try:
        c = canvas.Canvas(percorso_output, pagesize=A4)
        larghezza, altezza = A4

        def disegna_header(canvas_obj):
            canvas_obj.setFont("Helvetica-Bold", 10)
            canvas_obj.setFillColor(colors.darkblue)
            for i, riga in enumerate(righe_obiettivo):
                canvas_obj.drawString(40, altezza - 22 - i * 12, riga)
            canvas_obj.setFillColor(colors.black)
            canvas_obj.drawString(40, altezza - 50, f"DATA: {data_formattata}")
            canvas_obj.drawString(140, altezza - 50, f"CAT: {categoria.upper()}")
            canvas_obj.drawString(250, altezza - 50, f"SEDUTA N°: {numero_seduta}")
            canvas_obj.drawString(345, altezza - 50, f"GIOCATORI: {giocatori_testo}")
            canvas_obj.drawString(440, altezza - 50, f"SOCIETÀ: {societa_testo}")
            canvas_obj.line(40, altezza - 63, larghezza - 40, altezza - 63)

        disegna_header(c)

        blocchi = seduta_dati.get("fasi", [])
        y_corrente = altezza - 95

        durata_totale = sum([b.get("durata_minuti", 0) for b in blocchi if b.get("durata_minuti")])

        for blocco in blocchi:
            codici_fase = [cod for cod in (blocco.get("fase") or "").split(",") if cod]
            fase_testo = " / ".join(ETICHETTE_FASE.get(cod, cod) for cod in codici_fase)
            minuti = blocco.get("durata_minuti", 0)

            es = blocco.get("esercitazione", {})
            mezzo = es.get("mezzo_allenamento", "")
            descrizione = es.get("descrizione", "")
            immagine = es.get("immagine", "")
            ob_tec = es.get("obiettivo_tecnico", "")
            ob_tat = es.get("obiettivo_tattico", "")

            if y_corrente < 170:
                c.showPage()
                disegna_header(c)
                y_corrente = altezza - 95

            c.setFont("Helvetica-Bold", 12)
            c.setFillColor(colors.darkred)
            intestazione_blocco = f"{fase_testo.upper()} - {mezzo.upper()}" if fase_testo else mezzo.upper()
            c.drawString(40, y_corrente, intestazione_blocco)

            c.setFont("Helvetica-Bold", 11)
            c.setFillColor(colors.black)
            c.drawString(larghezza - 100, y_corrente, f"Durata: {minuti}'")

            margine_titolo = 12
            box_x, box_w, box_h = 40, 210, 140
            box_y = y_corrente - margine_titolo - box_h

            if immagine and immagine.strip() != "":
                percorso = immagine.replace('\\', '/').strip()
                if os.path.exists(percorso):
                    try:
                        c.drawImage(percorso, box_x, box_y, width=box_w, height=box_h, preserveAspectRatio=False, anchor='c')
                    except Exception:
                        try:
                            img = ImageReader(percorso)
                            c.drawImage(img, box_x, box_y, width=box_w, height=box_h, preserveAspectRatio=False, anchor='c')
                        except Exception as e: print(f"Errore caricamento immagine locale: {e}")

            c.setDash()
            c.rect(box_x, box_y, box_w, box_h)

            y_obiettivi = y_corrente - 22
            c.setFont("Helvetica-Bold", 10)
            c.drawString(270, y_obiettivi, "Ob. Tecnico:")
            c.setFont("Helvetica", 10)
            c.drawString(345, y_obiettivi, f"{ob_tec if ob_tec else 'Nessuno'}")

            c.setFont("Helvetica-Bold", 10)
            c.drawString(270, y_obiettivi - 15, "Ob. Tattico:")
            c.setFont("Helvetica", 10)
            c.drawString(345, y_obiettivi - 15, f"{ob_tat if ob_tat else 'Nessuno'}")

            testo_descrizione = c.beginText(270, y_obiettivi - 40)
            testo_descrizione.setFont("Helvetica", 10)
            if descrizione:
                # BUG (segnalato da Luca): textwrap.wrap() sull'intero testo
                # tratta "\n" come un normale spazio e lo elimina, quindi gli
                # a capo manuali digitati nella TextArea "Descrizione / focus
                # esercizio" sparivano nel PDF. Si spezza prima sulle righe
                # scritte dall'utente, poi si avvolge (wrap) ciascuna
                # singolarmente.
                for riga_utente in descrizione.splitlines():
                    if riga_utente.strip() == "":
                        testo_descrizione.textLine("")
                        continue
                    for riga in textwrap.wrap(riga_utente, width=54):
                        testo_descrizione.textLine(riga)
            c.drawText(testo_descrizione)

            y_corrente -= 175

        c.setFont("Helvetica-Bold", 12)
        c.setFillColor(colors.black)
        c.drawString(larghezza - 190, 40, f"DURATA TOTALE: {durata_totale} min")

        c.save()
        return True, percorso_output
    except Exception as e:
        return False, f"Errore durante la generazione del PDF: {e}"