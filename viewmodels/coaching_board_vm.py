"""ViewModel Coaching Board: editor semplificato della lavagna tattica.

Semplificazione DELIBERATA e sostanziale rispetto al vecchio editor
(interfaccia_coaching_board.py, 1829 righe + 11 file QML "lavagna/*"
cancellati con tutto il resto del vecchio prototipo): qui si possono
posizionare, trascinare e personalizzare giocatori/pallone/porta/testo
liberi sul campo (colori, numero/nome, dimensione/rotazione porta, stile
campo, z-order, duplicazione, selezione multipla, scala globale), ma NON
c'e' ancora uno strumento linee/frecce tattiche, ostacoli (coni),
ridimensionamento per-elemento, copia/incolla persistente tra sessioni, ne'
undo/redo. E' un editor funzionante e molto piu' ricco di prima, non ancora
una ricostruzione 1:1 del precedente.

Il salvataggio in due passi (percorsoImmaginePerSalvataggio() poi
confermaSalvataggio(percorso)) esiste perche' lo screenshot della lavagna
va catturato lato QML (grabToImage, l'unico posto dove esiste davvero un
frame renderizzato) mentre i dati vettoriali/il record DB restano gestiti
qui in Python."""

import json
import os
import re

from PyQt6.QtCore import QObject, QSettings, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager

ORGANIZZAZIONE = "LB Coaching"
APPLICAZIONE = "FC Manager"
PREFISSO_IMPOSTAZIONI = "lavagna/"

COLORI_SQUADRA = ["#3d5afe", "#e0544f"]
ROTAZIONI_VALIDE = (0, 45, 90, 135, 180, 225, 270, 315)
MODALITA_CAMPO_VALIDE = ("intero", "meta", "nessuna")
# Tipi "puntuali" (un solo x,y) vs "forma" (due punti x1,y1/x2,y2, disegnati
# con lo strumento "Disegna" tenendo premuto e trascinando sul campo).
TIPI_FORMA = ("freccia", "linea", "rettVuoto", "rettPieno", "ellisseV", "ellisseP", "lineaCurva", "frecciaCurva")
# Percorso di movimento (Animazione): geometria a N punti, non due come le
# forme sopra - tenuto in una tupla separata perche' ogni punto di codice
# che gia' fa branching su TIPI_FORMA (duplica/incolla/sposta multiplo)
# tratta un percorso diversamente (vedi sotto), non allo stesso modo.
TIPI_PERCORSO = ("percorso",)

DEFAULT_ELEMENTO = {
    "coloreContorno": "#ffffff",
    "testo": "",
    "numero": "",
    "nomeGiocatore": "",
    "mostraEtichetta": True,
    "dimensione": "grande",
    "rotazione": 0,
    "fontSize": 14,
    "grassetto": False,
    "coloreTesto": "#f4f6fb",
    "tratteggiato": False,
    "x1": 0.0, "y1": 0.0, "x2": 0.0, "y2": 0.0,
    # Spostamento perpendicolare del punto medio, come frazione della
    # lunghezza del segmento (0 = dritta). Solo per lineaCurva/frecciaCurva.
    "curvatura": 0.0,
    # Spessore del tratto in pixel. Solo per i tipi TIPI_FORMA e "percorso".
    "spessore": 2.0,
    # Percorso di movimento (Animazione, tipo "percorso"): punti grezzi del
    # tracciato disegnato a mano libera, in ordine, coordinate normalizzate
    # 0-1 come ogni altro x/y - MAI clampati, stessa convenzione di x1/y1.
    "punti": [],
    # Ritardo di partenza e durata del movimento, in secondi (Animazione,
    # tipo "percorso" - vedi impostaRitardoPercorso/impostaDurataPercorso).
    "ritardo": 0.0,
    "durata": 2.0,
    # Identificativo stabile (assegnato alla creazione, mai riusato) e id
    # dell'elemento a cui questo testo e' eventualmente ancorato: servono
    # a far seguire un'etichetta di testo all'elemento agganciato quando
    # viene spostato, senza rompersi se nel frattempo altri elementi
    # vengono rimossi/riordinati (un indice di array non sarebbe stabile).
    "id": None,
    "ancoraId": None,
    # Squadra di appartenenza ("a"/"b"), solo per tipo "giocatore": permette
    # di ricolorare maglia/calzettoni di tutti i giocatori della stessa
    # squadra in un colpo solo (vedi impostaColoreMagliaSquadra sotto),
    # invece di dover modificare ogni elemento singolarmente.
    "squadra": None,
    # Moltiplicatore di dimensione applicato SOPRA la scala globale
    # (scalaGiocatori/scalaOggetti): permette di ridimensionare un singolo
    # oggetto senza toccare tutti gli altri dello stesso tipo.
    "scalaIndividuale": 1.0,
}


def _leggi_impostazione(chiave, default):
    """Ultima impostazione usata (colori squadre/disegno, scala globale
    giocatori/oggetti), persistita tra sessioni con lo stesso QSettings gia'
    introdotto da theme_manager.py - qui vive solo la sua estensione a questa
    schermata, sotto il prefisso "lavagna/" per non confondersi con la
    chiave del tema."""
    valore = QSettings(ORGANIZZAZIONE, APPLICAZIONE).value(PREFISSO_IMPOSTAZIONI + chiave, default)
    return valore


def _scrivi_impostazione(chiave, valore):
    QSettings(ORGANIZZAZIONE, APPLICAZIONE).setValue(PREFISSO_IMPOSTAZIONI + chiave, valore)


def _normalizza_elemento(e):
    """Riempie le chiavi mancanti con un default: un elemento salvato PRIMA
    che esistessero questi campi di personalizzazione (o incollato da una
    versione precedente) deve continuare a caricarsi senza errori invece di
    far mancare una proprieta' attesa dal QML."""
    normalizzato = dict(DEFAULT_ELEMENTO)
    normalizzato.update(e)
    return normalizzato


class CoachingBoardVM(QObject):
    elementiCambiati = pyqtSignal()
    metaCambiata = pyqtSignal()
    campoCambiato = pyqtSignal()
    scalaCambiata = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    salvataggioCompletato = pyqtSignal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._id_board = None
        self._titolo = ""
        self._mezzo_allenamento = ""
        self._descrizione = ""
        self._elementi = []  # [{tipo, x, y, colore, coloreContorno, testo, numero, nomeGiocatore, mostraEtichetta, dimensione, rotazione, fontSize, grassetto, coloreTesto}]
        self._messaggio = ""
        self._modalita_campo = "intero"
        self._colore_campo = "#1e7d32"
        self._colore_linee = "#ffffff"
        self._scala_giocatori = float(_leggi_impostazione("scalaGiocatori", 1.0))
        self._scala_oggetti = float(_leggi_impostazione("scalaOggetti", 1.0))
        # Visibilita' etichette: impostazione di sessione come
        # modalita'/colori/scala campo sopra, non salvata per singola
        # lavagna - stesso limite gia' esistente per quelle, non nuovo qui.
        self._mostra_etichette_globali = True
        # Archivio locale (stessa scelta gia' documentata per HubBoardVM):
        # nessun dati_utente disponibile qui, il vocabolario Mezzi e' letto
        # sempre in locale.
        self._menu_mezzi = DataManager.carica_liste_menu(True).get("Mezzi", [])
        self._prossimo_id = 1
        # Cronologia per Ctrl+Z: uno snapshot JSON di _elementi per ogni
        # azione che modifica la lavagna, salvato PRIMA di applicare la
        # modifica - annulla() ripristina l'ultimo. Limitata a 200 passi
        # (trascinare uno slider puo' generare piu' passi di fila, uno per
        # ogni variazione di valore) per non far crescere la memoria
        # all'infinito in una sessione lunga.
        self._pila_annulla = []
        # Appunti per Ctrl+C/Ctrl+V: copie indipendenti (dict, non riferimenti)
        # degli elementi selezionati al momento della copia.
        self._appunti = []

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    def _nuovo_id(self):
        id_ = self._prossimo_id
        self._prossimo_id += 1
        return id_

    def _salva_stato_annullamento(self):
        self._pila_annulla.append(json.dumps(self._elementi))
        if len(self._pila_annulla) > 200:
            self._pila_annulla.pop(0)

    def _sposta_ancorati(self, id_elemento, dx, dy):
        # Ogni testo con ancoraId == id_elemento segue lo stesso spostamento
        # (in coordinate normalizzate) dell'elemento a cui e' agganciato -
        # nessuna linea di collegamento disegnata, solo posizione che si
        # aggiorna insieme. Se l'elemento ancora viene rimosso in seguito,
        # ancoraId resta semplicemente orfano (nessun match, innocuo): il
        # testo smette di seguire ma resta al suo posto.
        if id_elemento is None or (dx == 0 and dy == 0):
            return
        for el in self._elementi:
            if el.get("tipo") == "percorso":
                # Un percorso ancorato ad un giocatore/pallone rappresenta il
                # movimento catturato una volta al disegno, non un'etichetta
                # da far seguire: se l'ancora viene poi trascinata altrove il
                # percorso resta esattamente dov'e' stato disegnato (limite
                # dichiarato: elimina e ridisegna per correggerlo).
                continue
            if el.get("ancoraId") == id_elemento:
                el["x"] = el["x"] + dx
                el["y"] = el["y"] + dy

    @pyqtProperty(str, notify=metaCambiata)
    def titolo(self):
        return self._titolo

    @pyqtProperty(str, notify=metaCambiata)
    def mezzoAllenamento(self):
        return self._mezzo_allenamento

    @pyqtProperty(str, notify=metaCambiata)
    def descrizione(self):
        return self._descrizione

    @pyqtProperty("QVariantList", constant=True)
    def listaMezzi(self):
        return self._menu_mezzi

    @pyqtProperty("QVariantList", notify=elementiCambiati)
    def elementi(self):
        return self._elementi

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    @pyqtProperty(str, notify=campoCambiato)
    def modalitaCampo(self):
        return self._modalita_campo

    @pyqtProperty(str, notify=campoCambiato)
    def coloreCampo(self):
        return self._colore_campo

    @pyqtProperty(str, notify=campoCambiato)
    def coloreLinee(self):
        return self._colore_linee

    @pyqtProperty(float, notify=scalaCambiata)
    def scalaGiocatori(self):
        return self._scala_giocatori

    @pyqtProperty(float, notify=scalaCambiata)
    def scalaOggetti(self):
        return self._scala_oggetti

    @pyqtProperty(bool, notify=campoCambiato)
    def mostraEtichetteGlobali(self):
        return self._mostra_etichette_globali

    @pyqtSlot()
    def nuovaLavagna(self):
        self._id_board = None
        self._titolo = "Nuova lavagna"
        self._mezzo_allenamento = ""
        self._descrizione = ""
        self._elementi = []
        self._modalita_campo = "intero"
        self._colore_campo = "#1e7d32"
        self._colore_linee = "#ffffff"
        self._scala_giocatori = float(_leggi_impostazione("scalaGiocatori", 1.0))
        self._scala_oggetti = float(_leggi_impostazione("scalaOggetti", 1.0))
        self._mostra_etichette_globali = True
        self._prossimo_id = 1
        self._pila_annulla = []
        self._appunti = []
        self.metaCambiata.emit()
        self.elementiCambiati.emit()
        self.campoCambiato.emit()
        self.scalaCambiata.emit()
        self._imposta_messaggio("")

    @pyqtSlot(int, str, str, str, str, str, str, str)
    def caricaLavagna(self, id_board, titolo, mezzo_allenamento, dati_vettoriali_json, descrizione="",
                       modalita_campo="intero", colore_campo="#1e7d32", colore_linee="#ffffff"):
        # id_board<=0 e' la sentinella usata da HubBoardVM.duplicaBoard:
        # carica il contenuto ma si comporta come una lavagna NUOVA, quindi
        # il prossimo salvataggio crea una riga invece di sovrascrivere
        # l'originale.
        self._id_board = id_board if id_board and id_board > 0 else None
        self._titolo = titolo
        self._mezzo_allenamento = mezzo_allenamento
        self._descrizione = descrizione or ""
        try:
            grezzi = json.loads(dati_vettoriali_json) if dati_vettoriali_json else []
        except (ValueError, TypeError):
            grezzi = []
        self._elementi = [_normalizza_elemento(e) for e in grezzi]
        # Lavagne salvate prima che esistesse il testo ancorato non hanno
        # "id": ne assegniamo uno al volo, cosi' possono comunque diventare
        # bersaglio di un'ancora da questo momento in poi.
        prossimo = 1
        for el in self._elementi:
            if el.get("id") is None:
                el["id"] = prossimo
                prossimo += 1
            else:
                prossimo = max(prossimo, el["id"] + 1)
        self._prossimo_id = prossimo
        self._pila_annulla = []
        self._appunti = []
        # FIX: prima erano sempre azzerati a "intero"/colori di default -
        # riaprire una lavagna salvata con "Metà campo" mostrava sempre
        # "Campo intero" (segnalato da Luca). Ora arrivano da DB (vedi
        # DataManager.get_dati_vettoriali_board/salva_coaching_board).
        self._modalita_campo = modalita_campo if modalita_campo in MODALITA_CAMPO_VALIDE else "intero"
        self._colore_campo = colore_campo or "#1e7d32"
        self._colore_linee = colore_linee or "#ffffff"
        self._scala_giocatori = float(_leggi_impostazione("scalaGiocatori", 1.0))
        self._scala_oggetti = float(_leggi_impostazione("scalaOggetti", 1.0))
        self._mostra_etichette_globali = True
        self.metaCambiata.emit()
        self.elementiCambiati.emit()
        self.campoCambiato.emit()
        self.scalaCambiata.emit()
        self._imposta_messaggio("")

    @pyqtSlot(str)
    def impostaTitolo(self, valore):
        # Guardia necessaria ora che il campo Titolo lo richiama da
        # onTextChanged (vedi CoachingBoard.qml): senza, un cambio
        # programmatico di titolo (caricaLavagna/nuovaLavagna) fa riemettere
        # metaCambiata, che riassegna text: coachingBoardVM.titolo, che fa
        # scattare di nuovo onTextChanged con lo stesso valore - un loop di
        # binding (stesso principio gia' documentato altrove in questo
        # programma per gli stessi motivi).
        if self._titolo == valore:
            return
        self._titolo = valore
        self.metaCambiata.emit()

    @pyqtSlot(str)
    def impostaMezzoAllenamento(self, valore):
        self._mezzo_allenamento = valore
        self.metaCambiata.emit()

    @pyqtSlot(str)
    def impostaDescrizione(self, valore):
        self._descrizione = valore
        self.metaCambiata.emit()

    @pyqtSlot(str)
    def impostaModalitaCampo(self, valore):
        if valore not in MODALITA_CAMPO_VALIDE:
            return
        self._modalita_campo = valore
        self.campoCambiato.emit()

    @pyqtSlot(str)
    def impostaColoreCampo(self, valore):
        self._colore_campo = valore
        self.campoCambiato.emit()

    @pyqtSlot(str)
    def impostaColoreLinee(self, valore):
        self._colore_linee = valore
        self.campoCambiato.emit()

    @pyqtSlot(float)
    def impostaScalaGiocatori(self, valore):
        self._scala_giocatori = max(0.5, min(2.0, valore))
        _scrivi_impostazione("scalaGiocatori", self._scala_giocatori)
        self.scalaCambiata.emit()

    @pyqtSlot(float)
    def impostaScalaOggetti(self, valore):
        self._scala_oggetti = max(0.5, min(2.0, valore))
        _scrivi_impostazione("scalaOggetti", self._scala_oggetti)
        self.scalaCambiata.emit()

    @pyqtSlot(str, result=str)
    def leggiImpostazione(self, chiave):
        """Ultimo valore usato per un controllo di sola-UI non gestito dal
        ViewModel (colori squadre/disegno, spessore disegno): il QML lo
        legge a Component.onCompleted e lo riscrive ad ogni cambio, cosi'
        restano ricordati alla riapertura del programma."""
        return str(_leggi_impostazione(chiave, ""))

    @pyqtSlot(str, str)
    def scriviImpostazione(self, chiave, valore):
        _scrivi_impostazione(chiave, valore)

    @pyqtSlot(bool)
    def impostaMostraEtichetteGlobali(self, valore):
        self._mostra_etichette_globali = valore
        self.campoCambiato.emit()

    def _posizione_a_cascata(self):
        # Ogni nuovo elemento nasce con un piccolo offset dal precedente
        # (stesso comportamento del vecchio editor): senza questo, aggiungere
        # piu' elementi di fila li impila esattamente al centro campo, uno
        # sopra l'altro, e sembra che il click non abbia avuto effetto.
        offset = 0.02 * (len(self._elementi) % 8)
        return 0.5 + offset, 0.5 + offset

    @pyqtSlot(str, float, float, str, str)
    def aggiungiElemento(self, tipo, x, y, colore, squadra=""):
        self._salva_stato_annullamento()
        if x == 0.5 and y == 0.5:
            x, y = self._posizione_a_cascata()
        nuovo = _normalizza_elemento({
            "tipo": tipo, "x": x, "y": y,
            "colore": colore or (COLORI_SQUADRA[len([e for e in self._elementi if e["tipo"] == "giocatore"]) % len(COLORI_SQUADRA)] if tipo == "giocatore" else "#ffffff"),
            "testo": "Testo" if tipo == "testo" else "",
            "id": self._nuovo_id(),
            "squadra": squadra or None,
        })
        self._elementi.append(nuovo)
        self.elementiCambiati.emit()

    @pyqtSlot(int, float, float)
    def spostaElemento(self, indice, x, y):
        if 0 <= indice < len(self._elementi):
            self._salva_stato_annullamento()
            el = self._elementi[indice]
            dx, dy = x - el["x"], y - el["y"]
            el["x"] = x
            el["y"] = y
            self._sposta_ancorati(el.get("id"), dx, dy)
            self.elementiCambiati.emit()

    @pyqtSlot(str, float, float, float, float, str, bool, float)
    def aggiungiForma(self, tipo, x1, y1, x2, y2, colore, tratteggiato, spessore=2.0):
        # Le "forme" dello strumento Disegna (frecce/linee/rettangoli/ellissi)
        # sono definite da due punti, non da un centro + dimensione fissa
        # come gli altri elementi: coordinate normalizzate (0-1) sul campo,
        # stessa convenzione di x/y per restare indipendenti dalla
        # dimensione a schermo.
        if tipo not in TIPI_FORMA:
            return
        self._salva_stato_annullamento()
        nuovo = _normalizza_elemento({
            "tipo": tipo, "x": (x1 + x2) / 2, "y": (y1 + y2) / 2,
            "x1": x1, "y1": y1, "x2": x2, "y2": y2,
            "colore": colore or "#f4f6fb", "tratteggiato": bool(tratteggiato),
            "spessore": max(1.0, min(8.0, spessore)),
            "id": self._nuovo_id(),
        })
        self._elementi.append(nuovo)
        self.elementiCambiati.emit()

    @pyqtSlot(int, float, float, float, float)
    def spostaForma(self, indice, x1, y1, x2, y2):
        if 0 <= indice < len(self._elementi) and self._elementi[indice].get("tipo") in TIPI_FORMA:
            self._salva_stato_annullamento()
            e = self._elementi[indice]
            vecchia_x, vecchia_y = e["x"], e["y"]
            e["x1"], e["y1"], e["x2"], e["y2"] = x1, y1, x2, y2
            e["x"], e["y"] = (x1 + x2) / 2, (y1 + y2) / 2
            self._sposta_ancorati(e.get("id"), e["x"] - vecchia_x, e["y"] - vecchia_y)
            self.elementiCambiati.emit()

    @pyqtSlot(int, bool)
    def impostaTratteggiatoForma(self, indice, tratteggiato):
        self._imposta_campo_elemento(indice, "tratteggiato", tratteggiato)

    @pyqtSlot(int, float)
    def impostaCurvaturaForma(self, indice, curvatura):
        self._imposta_campo_elemento(indice, "curvatura", max(-1.0, min(1.0, curvatura)))

    @pyqtSlot(int, float)
    def impostaSpessoreForma(self, indice, spessore):
        self._imposta_campo_elemento(indice, "spessore", max(1.0, min(8.0, spessore)))

    @pyqtSlot("QVariantList", int, str, bool, float, result=int)
    def aggiungiPercorso(self, punti, ancoraId, colore, tratteggiato, spessore=2.0):
        """Animazione: crea un percorso di movimento a partire dal disegno a
        mano libera catturato in CoachingBoard.qml (drag iniziato su un
        giocatore/pallone). Ricostruisce i punti in modo difensivo (whitelist
        chiavi, coercizione tipo) invece di fidarsi dei dict grezzi in arrivo
        da QML - stessa cautela di aggiungiForma/aggiungiElemento verso
        l'input dell'interfaccia. Ritorna il nuovo indice (-1 se rifiutato)
        cosi' il QML puo' selezionare subito il percorso appena creato."""
        if len(punti) < 2:
            return -1
        ancora = next((e for e in self._elementi if e.get("id") == ancoraId and e.get("tipo") in ("giocatore", "pallone")), None)
        if ancora is None:
            return -1
        try:
            punti_puliti = [{"x": float(p["x"]), "y": float(p["y"])} for p in punti]
        except (KeyError, TypeError, ValueError):
            return -1
        self._salva_stato_annullamento()
        xs = [p["x"] for p in punti_puliti]
        ys = [p["y"] for p in punti_puliti]
        nuovo = _normalizza_elemento({
            "tipo": "percorso",
            "x": (min(xs) + max(xs)) / 2, "y": (min(ys) + max(ys)) / 2,
            "punti": punti_puliti,
            "ancoraId": ancoraId,
            "colore": colore or "#f4f6fb", "tratteggiato": bool(tratteggiato),
            "spessore": max(1.0, min(8.0, spessore)),
            "id": self._nuovo_id(),
        })
        self._elementi.append(nuovo)
        self.elementiCambiati.emit()
        return len(self._elementi) - 1

    @pyqtSlot(int, float)
    def impostaRitardoPercorso(self, indice, ritardo):
        self._imposta_campo_elemento(indice, "ritardo", max(0.0, min(30.0, ritardo)))

    @pyqtSlot(int, float)
    def impostaDurataPercorso(self, indice, durata):
        self._imposta_campo_elemento(indice, "durata", max(0.2, min(30.0, durata)))

    @pyqtSlot(int, str)
    def impostaTestoElemento(self, indice, testo):
        if 0 <= indice < len(self._elementi) and self._elementi[indice].get("testo", "") != testo:
            self._salva_stato_annullamento()
            self._elementi[indice]["testo"] = testo
            self.elementiCambiati.emit()

    def _imposta_campo_elemento(self, indice, campo, valore):
        if 0 <= indice < len(self._elementi) and self._elementi[indice].get(campo) != valore:
            self._salva_stato_annullamento()
            self._elementi[indice][campo] = valore
            self.elementiCambiati.emit()

    @pyqtSlot(int, float)
    def impostaScalaIndividualeElemento(self, indice, valore):
        self._imposta_campo_elemento(indice, "scalaIndividuale", max(0.3, min(3.0, valore)))

    @pyqtSlot(int, str)
    def impostaColoreElemento(self, indice, colore):
        self._imposta_campo_elemento(indice, "colore", colore)

    @pyqtSlot(int, str)
    def impostaColoreContornoElemento(self, indice, colore):
        self._imposta_campo_elemento(indice, "coloreContorno", colore)

    @pyqtSlot(str, str)
    def impostaColoreMagliaSquadra(self, squadra, colore):
        """Ricolora la maglia di TUTTI i giocatori gia' piazzati con questa
        squadra in un colpo solo, invece di doverli modificare uno a uno."""
        cambiato = any(e.get("tipo") == "giocatore" and e.get("squadra") == squadra for e in self._elementi)
        if cambiato:
            self._salva_stato_annullamento()
            for e in self._elementi:
                if e.get("tipo") == "giocatore" and e.get("squadra") == squadra:
                    e["colore"] = colore
            self.elementiCambiati.emit()

    @pyqtSlot(str, str)
    def impostaColoreCalzeSquadra(self, squadra, colore):
        """Come sopra, per pantaloncini+calzettoni (stesso campo
        coloreContorno: i calzettoni ne condividono il colore)."""
        cambiato = any(e.get("tipo") == "giocatore" and e.get("squadra") == squadra for e in self._elementi)
        if cambiato:
            self._salva_stato_annullamento()
            for e in self._elementi:
                if e.get("tipo") == "giocatore" and e.get("squadra") == squadra:
                    e["coloreContorno"] = colore
            self.elementiCambiati.emit()

    @pyqtSlot(int, str)
    def impostaNumeroGiocatore(self, indice, numero):
        self._imposta_campo_elemento(indice, "numero", numero)

    @pyqtSlot(int, str)
    def impostaNomeGiocatore(self, indice, nome):
        self._imposta_campo_elemento(indice, "nomeGiocatore", nome)

    @pyqtSlot(int, bool)
    def impostaMostraEtichetta(self, indice, mostra):
        self._imposta_campo_elemento(indice, "mostraEtichetta", mostra)

    @pyqtSlot(int, str)
    def impostaDimensionePorta(self, indice, dimensione):
        if dimensione in ("grande", "piccola"):
            self._imposta_campo_elemento(indice, "dimensione", dimensione)

    @pyqtSlot(int, int)
    def impostaRotazioneElemento(self, indice, rotazione):
        """Ruota un oggetto piazzato (giocatore/pallone/porta/cono/conetto/
        palo/scaletta/cerchio) a passi di 45 gradi - non solo la porta come
        prima (limitata a 0/45)."""
        if rotazione in ROTAZIONI_VALIDE:
            self._imposta_campo_elemento(indice, "rotazione", rotazione)

    @pyqtSlot(int, int)
    def impostaFontSizeTesto(self, indice, dimensione):
        self._imposta_campo_elemento(indice, "fontSize", max(8, min(72, dimensione)))

    @pyqtSlot(int, bool)
    def impostaGrassettoTesto(self, indice, grassetto):
        self._imposta_campo_elemento(indice, "grassetto", grassetto)

    @pyqtSlot(int, str)
    def impostaColoreTesto(self, indice, colore):
        self._imposta_campo_elemento(indice, "coloreTesto", colore)

    @pyqtSlot(int)
    def aggiungiTestoAncorato(self, indice_ancora):
        # Crea un'etichetta di testo agganciata all'elemento a indice_ancora:
        # segue il suo spostamento (vedi _sposta_ancorati), senza alcuna
        # linea di collegamento disegnata - un normale elemento "testo",
        # stesso editor/rendering di un testo libero.
        if not (0 <= indice_ancora < len(self._elementi)):
            return
        self._salva_stato_annullamento()
        ancora = self._elementi[indice_ancora]
        nuovo = _normalizza_elemento({
            "tipo": "testo",
            "x": min(0.98, max(0.02, ancora["x"])),
            "y": max(0.02, ancora["y"] - 0.05),
            "testo": "Testo",
            "ancoraId": ancora.get("id"),
            "id": self._nuovo_id(),
        })
        self._elementi.append(nuovo)
        self.elementiCambiati.emit()

    @pyqtSlot(int)
    def rimuoviElemento(self, indice):
        if 0 <= indice < len(self._elementi):
            self._salva_stato_annullamento()
            self._elementi.pop(indice)
            self.elementiCambiati.emit()

    @pyqtSlot("QVariantList")
    def rimuoviElementi(self, indici):
        # Ordine decrescente: rimuovere dal basso in alto lascia invariati
        # gli indici delle voci ancora da eliminare in questa stessa chiamata.
        self._salva_stato_annullamento()
        for indice in sorted((int(i) for i in indici), reverse=True):
            if 0 <= indice < len(self._elementi):
                self._elementi.pop(indice)
        self.elementiCambiati.emit()

    @pyqtSlot(int)
    def duplicaElemento(self, indice):
        if 0 <= indice < len(self._elementi):
            self._salva_stato_annullamento()
            copia = dict(self._elementi[indice])
            copia["id"] = self._nuovo_id()  # id sempre nuovo, mai duplicato
            copia["x"] = min(0.98, copia["x"] + 0.03)
            copia["y"] = min(0.98, copia["y"] + 0.03)
            if copia.get("tipo") in TIPI_FORMA:
                copia["x1"] = min(0.98, copia["x1"] + 0.03)
                copia["y1"] = min(0.98, copia["y1"] + 0.03)
                copia["x2"] = min(0.98, copia["x2"] + 0.03)
                copia["y2"] = min(0.98, copia["y2"] + 0.03)
            if copia.get("tipo") == "percorso":
                # dict(originale) e' una copia shallow: senza questo,
                # copia["punti"] resterebbe la STESSA lista dell'originale
                # (mutare uno muterebbe l'altro, e il duplicato non si
                # sposterebbe mai visivamente nonostante x/y sopra).
                copia["punti"] = [{"x": min(0.98, p["x"] + 0.03), "y": min(0.98, p["y"] + 0.03)} for p in copia["punti"]]
            self._elementi.append(copia)
            self.elementiCambiati.emit()

    @pyqtSlot(int, result=int)
    def portaAvanti(self, indice):
        # Davanti a TUTTI gli altri elementi, non un passo solo: z-order
        # segue l'ordine nella lista (z: index nel delegate), quindi "in
        # cima" = ultima posizione. Ritorna il nuovo indice dell'elemento
        # spostato cosi' il QML puo' mantenere la selezione su di lui invece
        # di lasciarla puntare, per indice, a un elemento diverso.
        if not (0 <= indice < len(self._elementi)):
            return -1
        if indice == len(self._elementi) - 1:
            return indice
        self._salva_stato_annullamento()
        el = self._elementi.pop(indice)
        self._elementi.append(el)
        self.elementiCambiati.emit()
        return len(self._elementi) - 1

    @pyqtSlot(int, result=int)
    def portaIndietro(self, indice):
        # Dietro a TUTTI gli altri (prima posizione = z piu' bassa).
        if not (0 <= indice < len(self._elementi)):
            return -1
        if indice == 0:
            return indice
        self._salva_stato_annullamento()
        el = self._elementi.pop(indice)
        self._elementi.insert(0, el)
        self.elementiCambiati.emit()
        return 0

    @pyqtSlot("QVariantList", float, float)
    def spostaElementi(self, indici, dx, dy):
        """Sposta piu' elementi selezionati (lazo o Ctrl+click) della stessa
        quantita' dx/dy (coordinate normalizzate), in un solo passo di
        annullamento - controparte multi-elemento di spostaElemento."""
        indici_validi = sorted(set(int(i) for i in indici if 0 <= int(i) < len(self._elementi)))
        if not indici_validi or (dx == 0 and dy == 0):
            return
        self._salva_stato_annullamento()
        id_mossi = set()
        for i in indici_validi:
            el = self._elementi[i]
            el["x"] += dx
            el["y"] += dy
            if el.get("tipo") in TIPI_FORMA:
                el["x1"] += dx
                el["y1"] += dy
                el["x2"] += dx
                el["y2"] += dy
            if el.get("tipo") == "percorso":
                for p in el["punti"]:
                    p["x"] += dx
                    p["y"] += dy
            if el.get("id") is not None:
                id_mossi.add(el["id"])
        if id_mossi:
            # Un testo ancorato a un elemento gia' incluso nello spostamento
            # non va spostato una seconda volta da _sposta_ancorati.
            for el in self._elementi:
                if el.get("ancoraId") in id_mossi and el.get("id") not in id_mossi:
                    el["x"] += dx
                    el["y"] += dy
        self.elementiCambiati.emit()

    @pyqtSlot()
    def annulla(self):
        """Ctrl+Z: ripristina l'ultimo stato salvato in _pila_annulla. Nessun
        redo (non richiesto): annullare non impila lo stato corrente, e' una
        pila a senso unico."""
        if not self._pila_annulla:
            return
        self._elementi = json.loads(self._pila_annulla.pop())
        self.elementiCambiati.emit()

    @pyqtSlot("QVariantList")
    def copiaElementi(self, indici):
        self._appunti = [dict(self._elementi[int(i)]) for i in indici if 0 <= int(i) < len(self._elementi)]

    @pyqtSlot(result="QVariantList")
    def incollaElementi(self):
        """Ctrl+V: incolla una copia indipendente di ogni elemento negli
        appunti, con id nuovo e un piccolo offset (stesso spostamento usato
        da duplicaElemento) cosi' non si sovrappone esattamente all'originale.
        Ritorna gli indici dei nuovi elementi, cosi' il QML puo' selezionarli
        subito dopo l'incolla."""
        if not self._appunti:
            return []
        self._salva_stato_annullamento()
        nuovi_indici = []
        for originale in self._appunti:
            copia = dict(originale)
            copia["id"] = self._nuovo_id()
            copia["x"] = min(0.98, copia["x"] + 0.03)
            copia["y"] = min(0.98, copia["y"] + 0.03)
            if copia.get("tipo") in TIPI_FORMA:
                copia["x1"] = min(0.98, copia["x1"] + 0.03)
                copia["y1"] = min(0.98, copia["y1"] + 0.03)
                copia["x2"] = min(0.98, copia["x2"] + 0.03)
                copia["y2"] = min(0.98, copia["y2"] + 0.03)
            if copia.get("tipo") == "percorso":
                copia["punti"] = [{"x": min(0.98, p["x"] + 0.03), "y": min(0.98, p["y"] + 0.03)} for p in copia["punti"]]
            self._elementi.append(copia)
            nuovi_indici.append(len(self._elementi) - 1)
        self.elementiCambiati.emit()
        return nuovi_indici

    def _nome_file_sicuro(self, testo):
        pulito = re.sub(r'[\\/:*?"<>|]', "_", testo or "Senza Titolo").strip()
        return pulito or "Senza Titolo"

    @pyqtSlot(result=str)
    def percorsoImmaginePerSalvataggio(self):
        cartella = DataManager.cartella_grafiche_board()
        mezzo = self._nome_file_sicuro(self._mezzo_allenamento)
        tit = self._nome_file_sicuro(self._titolo)
        base = f"{mezzo} - {tit}"
        candidato = os.path.join(cartella, f"{base}.png")
        # FIX: due lavagne diverse con lo stesso mezzo+titolo (es. entrambe
        # "Senza Titolo") calcolavano lo STESSO file: salvare la seconda
        # sovrascriveva silenziosamente l'anteprima PNG della prima, e la
        # ricerca dei dati vettoriali per percorso (vedi
        # DataManager.get_dati_vettoriali_board, corretta a parte) poteva
        # restituire la riga sbagliata - "miniatura corretta ma contenuto
        # vuoto all'apertura", segnalato da Luca.
        suffisso = 2
        while DataManager.percorso_board_in_uso_da_altro(candidato, self._id_board):
            candidato = os.path.join(cartella, f"{base} ({suffisso}).png")
            suffisso += 1
        return candidato

    @pyqtSlot(str)
    def confermaSalvataggio(self, percorso_immagine):
        try:
            dati_json = json.dumps(self._elementi)
            self._id_board = DataManager.salva_coaching_board(
                self._id_board, self._titolo, self._mezzo_allenamento,
                self._descrizione, percorso_immagine, dati_json,
                self._modalita_campo, self._colore_campo, self._colore_linee,
            )
            self._imposta_messaggio("Lavagna salvata.")
            self.salvataggioCompletato.emit(percorso_immagine)
        except Exception as e:
            self._imposta_messaggio(f"Impossibile salvare: {e}")

    @pyqtSlot(int, result=str)
    def percorsoFotogrammaTemporaneo(self, indice):
        """Animazione: percorso di un PNG temporaneo per il fotogramma
        indice-esimo dell'export GIF (vedi esportaAnimazioneGif sotto). Il
        ciclo di cattura vive in QML (grabToImage esiste solo li'), ma il
        percorso su disco resta deciso qui, stessa separazione gia' usata da
        percorsoImmaginePerSalvataggio per il salvataggio statico."""
        cartella = os.path.join(DataManager.cartella_grafiche_board(), "_temp_animazione")
        os.makedirs(cartella, exist_ok=True)
        return os.path.join(cartella, f"frame_{indice:04d}.png")

    @pyqtSlot("QVariantList", float, str)
    def esportaAnimazioneGif(self, percorsi_frame, fps, percorso_output):
        """Assembla i fotogrammi PNG catturati da QML (uno alla volta, vedi
        catturaProssimoFotogramma in CoachingBoard.qml) in una GIF animata
        con Pillow - nessun encoder video esterno (ffmpeg) necessario, per
        non appesantire l'eseguibile PyInstaller gia' in uso."""
        try:
            from PIL import Image

            if not percorsi_frame:
                self._imposta_messaggio("Nessun fotogramma da esportare.")
                return
            fotogrammi = [Image.open(p) for p in percorsi_frame]
            durata_ms = max(20, round(1000 / fps)) if fps > 0 else 100
            fotogrammi[0].save(
                percorso_output, save_all=True, append_images=fotogrammi[1:],
                duration=durata_ms, loop=0,
            )
            for f in fotogrammi:
                f.close()
            self._imposta_messaggio(f"Animazione esportata: {percorso_output}")
        except Exception as e:
            self._imposta_messaggio(f"Impossibile esportare l'animazione: {e}")
        finally:
            # I PNG temporanei vanno rimossi comunque, anche se l'export e'
            # fallito a meta' - non devono accumularsi ad ogni tentativo.
            for p in percorsi_frame:
                try:
                    os.remove(p)
                except OSError:
                    pass
