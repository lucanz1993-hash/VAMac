"""ViewModel Presenze: selezione gruppo -> selezione seduta -> stato di
ogni giocatore del gruppo per quella seduta. Vocabolario stati ('P'
Presente, 'A' Assente, 'C' Convocato, 'NC' Non Convocato) preso dai valori
gia' effettivamente salvati nel database esistente (`SELECT DISTINCT stato
FROM presenze`), non reinventato: i widget che lo mostravano sono stati
cancellati insieme al resto della vecchia UI, ma i dati restano compatibili.

NOTA: usa DataManager.get_sedute_lista_completa (non get_sedute_lista) per
poter mostrare e selezionare anche le sedute di tipo "Partita" collegate da
Macrociclo - il docstring di get_sedute_lista_completa in data_manager.py
dice letteralmente "usata dal registro presenze/calendario, che deve poter
mostrare e collegare anche quelle": era gia' pensata per questo schermo, ma
la versione precedente di questo file usava per errore la variante che le
esclude, mostrando sempre tutti e 4 gli stati (P/A/C/NC) indipendentemente
dal tipo di seduta invece di limitarli a quelli pertinenti."""

import calendar
import csv
import os
from datetime import date

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QGuiApplication

from data_manager import DataManager, _data_cella_macrociclo, _id_settimana_giorno_da_data

STATI = ["P", "A", "C", "NC"]
ETICHETTE_STATI = {"P": "Presente", "A": "Assente", "C": "Convocato", "NC": "Non convocato", "": "—"}
# Tipo impegno (colonna macrociclo lun..dom) -> stati applicabili in Presenze:
# per un allenamento (A, o nessun collegamento) si segna solo chi c'era
# davvero; per una partita/torneo (C/TM/TA) si registra solo la convocazione,
# non presenza fisica agli "allenamenti" (concetto diverso).
STATI_PER_TIPO = {"C": ["C", "NC"], "TM": ["C", "NC"], "TA": ["C", "NC"]}
STATI_DEFAULT = ["P", "A"]

# Conversione da vecchi stati testuali (dati storici, stessa mappa gia'
# presente nel widget cancellato interfaccia_presenze.py) ai codici attuali:
# un DB reale usato da anni puo' avere ancora righe scritte prima
# dell'introduzione dei codici brevi P/A/C/NC.
MAPPA_VECCHI_STATI = {"Presente": "P", "Assente": "A", "Infortunato": "A", "Malato": "A", "P": "P", "A": "A", "C": "C", "NC": "NC"}

MESI_NOMI = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]


class PresenzeVM(QObject):
    gruppiCambiati = pyqtSignal()
    gruppoSelezionatoCambiato = pyqtSignal()
    seduteCambiate = pyqtSignal()
    sedutaSelezionataCambiata = pyqtSignal()
    presenzeCambiate = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    calendarioCambiato = pyqtSignal()
    grigliaMensileCambiata = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._gruppi = []
        self._sedute = []
        self._righe = []  # [{id, nome, cognome, stato}]
        self._mappa_tipi = {}  # {id_seduta: tipo_impegno}
        self._indice_gruppo = -1
        self._indice_seduta = -1
        self._errore = ""
        self._messaggio = ""
        self._eventi_calendario = []
        oggi = date.today()
        self._mese_report = oggi.month
        self._anno_report = oggi.year
        self._griglia_mensile = {"giorniTotali": 0, "tipiGiorno": [], "righe": [], "totalePresentiGiorno": [], "percPresentiGiorno": []}
        self.ricaricaGruppi()

    def _etichetta_gruppo(self, g):
        base = f"{g['cat']} — {g['stag']}"
        return f"{g['soc']} · {base}" if g.get("soc") else base

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    @pyqtProperty("QVariantList", notify=gruppiCambiati)
    def gruppi(self):
        return [{"label": self._etichetta_gruppo(g)} for g in self._gruppi]

    @pyqtProperty(int, notify=gruppoSelezionatoCambiato)
    def indiceGruppo(self):
        return self._indice_gruppo

    @pyqtProperty("QVariantList", notify=seduteCambiate)
    def sedute(self):
        risultato = []
        for s in self._sedute:
            tipo = self._mappa_tipi.get(s["id_seduta"], "")
            etichetta_tipo = " (Partita)" if tipo in ("C", "TM", "TA") else ""
            risultato.append({"label": f"{s['data_seduta']} — {s['numero_seduta']}{etichetta_tipo}"})
        return risultato

    @pyqtProperty(int, notify=sedutaSelezionataCambiata)
    def indiceSeduta(self):
        return self._indice_seduta

    @pyqtProperty("QVariantList", notify=presenzeCambiate)
    def righe(self):
        return self._righe

    @pyqtProperty("QVariantList", notify=sedutaSelezionataCambiata)
    def statiPerSedutaCorrente(self):
        seduta = self._seduta_corrente()
        if not seduta:
            return STATI_DEFAULT
        tipo = self._mappa_tipi.get(seduta["id_seduta"], "")
        return STATI_PER_TIPO.get(tipo, STATI_DEFAULT)

    @pyqtProperty(str, notify=sedutaSelezionataCambiata)
    def dataSedutaCorrente(self):
        seduta = self._seduta_corrente()
        return seduta["data_seduta"] if seduta else ""

    @pyqtProperty("QVariantList", notify=calendarioCambiato)
    def eventiCalendario(self):
        return self._eventi_calendario

    @pyqtProperty(int, notify=grigliaMensileCambiata)
    def meseReport(self):
        return self._mese_report

    @pyqtProperty(int, notify=grigliaMensileCambiata)
    def annoReport(self):
        return self._anno_report

    @pyqtProperty("QVariantList", constant=True)
    def mesiNomi(self):
        return MESI_NOMI

    @pyqtProperty("QVariant", notify=grigliaMensileCambiata)
    def grigliaMensile(self):
        return self._griglia_mensile

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    @pyqtSlot()
    def ricaricaGruppi(self):
        try:
            gruppo_corrente = self._gruppo_corrente()
            identita_corrente = (
                (gruppo_corrente["cat"], gruppo_corrente["stag"], gruppo_corrente.get("soc") or "")
                if gruppo_corrente else None
            )
            _, raggruppamenti, indipendenti = DataManager.get_anagrafica_gruppi(self._dati_utente)
            gruppi = list(indipendenti)
            for lista in raggruppamenti.values():
                gruppi.extend(lista)
            gruppi.sort(key=lambda g: (g.get("soc") or "", g["cat"], g["stag"]))
            self._gruppi = gruppi
            self.gruppiCambiati.emit()
            if identita_corrente is not None:
                # FIX: prima si richiamava selezionaGruppo(0) solo se
                # _indice_gruppo == -1, quindi un indice "valido" ma ormai
                # spostato dal riordino (es. un gruppo creato altrove che si
                # inserisce prima nell'ordinamento) restava silenziosamente
                # agganciato al gruppo SBAGLIATO: la tendina mostrava
                # l'etichetta nuova ma sedute/presenze restavano quelle di
                # prima - il bug di sincronizzazione segnalato per Presenze.
                nuovo_indice = next(
                    (i for i, g in enumerate(gruppi) if (g["cat"], g["stag"], g.get("soc") or "") == identita_corrente),
                    -1,
                )
                if nuovo_indice == -1:
                    # Il gruppo selezionato e' stato eliminato altrove.
                    self._indice_gruppo = -1
                    if gruppi:
                        self.selezionaGruppo(0)
                    else:
                        self.gruppoSelezionatoCambiato.emit()
                        self._indice_seduta = -1
                        self._sedute = []
                        self._mappa_tipi = {}
                        self._righe = []
                        self.seduteCambiate.emit()
                        self.sedutaSelezionataCambiata.emit()
                        self.presenzeCambiate.emit()
                        self.ricaricaEventiCalendario()
                        self.calcolaGrigliaMensile()
                else:
                    # FIX: l'indice non e' cambiato, ma i dati dietro
                    # potrebbero essere completamente diversi (es. gruppo
                    # eliminato e ricreato identico altrove, stessa
                    # categoria/stagione/societa' quindi stessa posizione in
                    # elenco): ricarica SEMPRE i dipendenti quando
                    # gruppiCambiati scatta, non solo se l'indice si sposta -
                    # altrimenti calendario/sedute restavano quelli del
                    # macrociclo vecchio, gia' cancellato (bug segnalato:
                    # Presenze mostrava eventi non piu' presenti in
                    # Macrociclo dopo elimina+ricrea dello stesso gruppo).
                    # FIX 2: NON richiamare selezionaGruppo() qui (come si
                    # faceva prima) - azzera sempre la seduta selezionata e
                    # ricade sull'ultima in elenco. Component.onCompleted di
                    # Presenze.qml richiama ricaricaGruppi() ad ogni apertura
                    # schermata, quindi "Apri presenze" da Macrociclo
                    # (che seleziona la seduta giusta PRIMA di navigare qui)
                    # veniva sistematicamente sovrascritto con l'ultima
                    # seduta del gruppo invece di quella richiesta (bug
                    # segnalato da Luca: si apriva un evento diverso da
                    # quello cliccato). Si preserva quindi la seduta gia'
                    # selezionata se esiste ancora dopo il reload, stesso
                    # pattern gia' in uso in sedute_vm.py.
                    id_seduta_da_preservare = None
                    seduta_corrente = self._seduta_corrente()
                    if seduta_corrente:
                        id_seduta_da_preservare = seduta_corrente["id_seduta"]
                    self._indice_gruppo = nuovo_indice
                    self._ricarica_sedute(id_seduta_da_preservare)
            elif gruppi and self._indice_gruppo == -1:
                self.selezionaGruppo(0)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i gruppi: {e}")

    def _gruppo_corrente(self):
        if 0 <= self._indice_gruppo < len(self._gruppi):
            return self._gruppi[self._indice_gruppo]
        return None

    def _seduta_corrente(self):
        if 0 <= self._indice_seduta < len(self._sedute):
            return self._sedute[self._indice_seduta]
        return None

    @pyqtSlot(int)
    def selezionaGruppo(self, indice):
        if indice < 0 or indice >= len(self._gruppi):
            return
        self._indice_gruppo = indice
        self.gruppoSelezionatoCambiato.emit()
        self._indice_seduta = -1
        self._ricarica_sedute()

    @pyqtSlot(str, str, str)
    def selezionaGruppoPer(self, cat, stag, soc):
        """Seleziona il gruppo corrispondente a categoria/stagione/societa',
        usato per navigare qui da un'altra schermata (es. Macrociclo,
        "Apri presenze" su una cella collegata a una seduta)."""
        for i, g in enumerate(self._gruppi):
            if g["cat"] == cat and g["stag"] == stag and (g.get("soc") or "") == (soc or ""):
                self.selezionaGruppo(i)
                return

    @pyqtSlot(int)
    def selezionaSedutaPerId(self, id_seduta):
        for i, s in enumerate(self._sedute):
            if s["id_seduta"] == id_seduta:
                self.selezionaSeduta(i)
                return

    def _ricarica_sedute(self, id_da_preservare=None):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._sedute = []
            self._mappa_tipi = {}
            self.seduteCambiate.emit()
            return
        try:
            tutte = DataManager.get_sedute_lista_completa(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._mappa_tipi = DataManager.get_mappa_tipi_seduta(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            # FIX: qui va mostrato solo l'EVENTO inserito nel macrociclo, non
            # ogni riga "sedute" mai creata - una seduta libera creata da
            # Sedute (o rimasta orfana dopo uno scollega/ricrea) altrimenti
            # compariva come una seconda voce per la stessa data, con stati
            # P/A invece di C/NC perche' non risultava di alcun tipo (bug
            # segnalato: piu' eventi collegati alla stessa data, presenze
            # incoerenti tra un giocatore e l'altro).
            self._sedute = [s for s in tutte if s["id_seduta"] in self._mappa_tipi]
            self.seduteCambiate.emit()
            if not self._sedute:
                self._indice_seduta = -1
                self._righe = []
                self.presenzeCambiate.emit()
            elif id_da_preservare is not None and any(s["id_seduta"] == id_da_preservare for s in self._sedute):
                self.selezionaSedutaPerId(id_da_preservare)
            else:
                self.selezionaSeduta(len(self._sedute) - 1)  # l'ultima seduta in ordine cronologico, di default
            self.ricaricaEventiCalendario()
            self.calcolaGrigliaMensile()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare le sedute: {e}")

    @pyqtSlot(int)
    def selezionaSeduta(self, indice):
        if indice < 0 or indice >= len(self._sedute):
            return
        self._indice_seduta = indice
        self.sedutaSelezionataCambiata.emit()
        self._ricarica_presenze()

    @pyqtSlot()
    def aggiornaTutto(self):
        """Rilegge sedute/tipi/calendario/griglia per il gruppo corrente
        senza spostare la selezione di seduta attiva. La schermata Presenze
        viene ricreata da zero (stack.replace) ogni volta che la si apre da
        un'altra schermata: chiamare questo slot da Component.onCompleted la'
        garantisce dati sempre freschi anche quando la modifica e' avvenuta
        altrove (es. una seduta creata/collegata da Macrociclo)."""
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        try:
            self._mappa_tipi = DataManager.get_mappa_tipi_seduta(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            tutte = DataManager.get_sedute_lista_completa(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._sedute = [s for s in tutte if s["id_seduta"] in self._mappa_tipi]
            self.seduteCambiate.emit()
            if self._sedute and not (0 <= self._indice_seduta < len(self._sedute)):
                self.selezionaSeduta(len(self._sedute) - 1)
            elif self._sedute:
                self._ricarica_presenze()
            else:
                self._indice_seduta = -1
                self._righe = []
                self.presenzeCambiate.emit()
            self.ricaricaEventiCalendario()
            self.calcolaGrigliaMensile()
        except Exception as e:
            self._imposta_errore(f"Impossibile aggiornare: {e}")

    def _ricarica_presenze(self):
        gruppo = self._gruppo_corrente()
        seduta = self._seduta_corrente()
        if not gruppo or not seduta:
            self._righe = []
            self.presenzeCambiate.emit()
            return
        try:
            # includi_eliminati=True: un giocatore eliminato dopo questa
            # seduta deve restare visibile qui con lo stato gia' registrato
            # (o "Null"/vuoto se non era ancora in squadra o gia' uscito) -
            # sparire dall'anagrafica attiva non deve cancellare lo storico.
            giocatori = DataManager.get_giocatori(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], includi_eliminati=True)
            stati = DataManager.get_presenze_seduta(self._dati_utente, seduta["id_seduta"])
            # FIX: uno stato gia' salvato che non e' piu' tra quelli
            # applicabili al tipo di questa seduta (es. cambiato il tipo
            # impegno dopo aver gia' segnato presenze) resta visibile
            # com'era invece di sparire silenziosamente: la lista di stati
            # mostrati in QML e' solo un suggerimento, non un filtro sui dati.
            self._righe = [
                {"id": g["id_giocatore"], "nome": g["nome"], "cognome": g["cognome"], "stato": stati.get(g["id_giocatore"], ""), "attivo": g["attivo"]}
                for g in giocatori
            ]
            self.presenzeCambiate.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare le presenze: {e}")

    @pyqtSlot(int, str)
    def impostaStato(self, id_giocatore, stato):
        for riga in self._righe:
            if riga["id"] == id_giocatore:
                riga["stato"] = stato
                break
        self.presenzeCambiate.emit()

    @pyqtSlot(str, result=bool)
    def esportaConvocatiTesto(self, percorso):
        """Scrive un file .txt con l'elenco dei convocati (stato 'C') per la
        seduta corrente - stesso contenuto del "Copia Convocazioni" del
        vecchio widget (interfaccia_presenze.py, copia_convocati_clipboard),
        ma su file anziche' negli appunti, come richiesto da Luca. Ha senso
        solo per sedute di tipo Partita/Torneo/Test Match (C/TM/TA): sono le
        uniche con lo stato 'Convocato' - per un Allenamento non esiste
        nulla da esportare qui (si usano P/A, non C/NC)."""
        seduta = self._seduta_corrente()
        if not seduta:
            self._imposta_errore("Nessun evento selezionato.")
            return False
        convocati = [f"{r['cognome']} {r['nome']}".strip() for r in self._righe if r["stato"] == "C"]
        if not convocati:
            self._imposta_errore("Nessun giocatore risulta convocato per questo evento.")
            return False
        try:
            anno, mese, giorno = seduta["data_seduta"].split("-")
            data_it = f"{giorno}-{mese}-{anno}" if len(anno) == 4 else seduta["data_seduta"]
        except ValueError:
            data_it = seduta["data_seduta"]
        righe_testo = [f"Convocazioni del {data_it}", ""] + convocati
        try:
            with open(percorso, "w", encoding="utf-8") as f:
                f.write("\n".join(righe_testo))
        except OSError as e:
            self._imposta_errore(f"Impossibile scrivere il file: {e}")
            return False
        self._imposta_messaggio(f"Lista convocati esportata in {percorso}")
        self._imposta_errore("")
        return True

    @pyqtSlot()
    def impostaTuttiPositivi(self):
        """Precompila tutte le righe con lo stato "positivo" di default (P
        per Allenamento, C per Partita/Torneo/Test Match): il caso comune e'
        che quasi tutti siano presenti/convocati, poi si corregge solo chi
        non lo e' - prima bisognava impostare ogni singolo giocatore a mano
        anche per il caso piu' frequente (segnalato da Luca)."""
        stati = self.statiPerSedutaCorrente
        if not stati or not self._righe:
            return
        positivo = stati[0]
        for riga in self._righe:
            riga["stato"] = positivo
        self.presenzeCambiate.emit()

    @pyqtSlot()
    def salva(self):
        seduta = self._seduta_corrente()
        if not seduta:
            return
        mappa = {r["id"]: r["stato"] for r in self._righe if r["stato"]}
        ok, err = DataManager.salva_presenze_seduta(self._dati_utente, seduta["id_seduta"], mappa)
        if ok:
            self._imposta_messaggio("Presenze salvate.")
            self._imposta_errore("")
            # FIX: la Griglia Mensile viveva sulla stessa schermata ma non si
            # ricalcolava da sola dopo aver salvato le presenze di una singola
            # seduta - restava visibile con i numeri di prima finche' l'utente
            # non premeva manualmente "Aggiorna" nel pannello.
            self.calcolaGrigliaMensile()
        else:
            self._imposta_errore(f"Impossibile salvare: {err}")

    @pyqtSlot()
    def copiaConvocati(self):
        # Funzione ad altissimo uso quotidiano nel vecchio widget (copiare la
        # lista convocati per incollarla su WhatsApp ai genitori/giocatori),
        # persa nella ricostruzione da zero. QGuiApplication.clipboard() e'
        # lo stesso meccanismo nativo usato da qualunque altra applicazione
        # desktop, non serve alcun modulo QML aggiuntivo.
        seduta = self._seduta_corrente()
        if not seduta:
            return
        try:
            anno, mese, giorno = seduta["data_seduta"].split("-")
            data_leggibile = f"{giorno}-{mese}-{anno}"
        except Exception:
            data_leggibile = seduta["data_seduta"]
        convocati = [r for r in self._righe if r["stato"] == "C"]
        righe_testo = [f"{r['cognome']} {r['nome']}" for r in sorted(convocati, key=lambda r: (r["cognome"], r["nome"]))]
        intestazione = f"Convocati - {data_leggibile} ({seduta['numero_seduta']})"
        testo = intestazione + ("\n" + "\n".join(righe_testo) if righe_testo else "\nNessun giocatore convocato.")
        QGuiApplication.clipboard().setText(testo)
        self._imposta_messaggio(f"Convocazioni copiate negli appunti ({len(convocati)} giocatori).")
        self._imposta_errore("")

    # ==========================================
    # CALENDARIO & EVENTI
    # ==========================================
    # Ricostruisce, per ogni cella lun..dom pianificata a Macrociclo, la data
    # reale (via _data_cella_macrociclo) e il suo stato: gia' collegata a una
    # seduta reale (idSeduta valorizzato) oppure solo pianificata (tipo
    # presente, idSeduta=-1). Stessa fonte dati di MacrocicloVM/get_macrociclo,
    # letta qui per poter cliccare direttamente su un giorno del calendario
    # invece di passare dalla schermata Macrociclo.
    @pyqtSlot()
    def ricaricaEventiCalendario(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._eventi_calendario = []
            self.calendarioCambiato.emit()
            return
        try:
            righe_macro = DataManager.get_macrociclo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            eventi = {}
            for riga in righe_macro:
                id_settimana = riga["id_settimana"]
                for giorno in ("lun", "mar", "mer", "gio", "ven", "sab", "dom"):
                    tipo = (riga.get(giorno) or "").strip()
                    if not tipo:
                        continue
                    data_cella = _data_cella_macrociclo(gruppo["stag"], id_settimana, giorno)
                    if not data_cella:
                        continue
                    id_seduta = riga.get(f"id_seduta_{giorno}")
                    eventi[data_cella.isoformat()] = {
                        "data": data_cella.isoformat(), "tipo": tipo, "idSeduta": id_seduta if id_seduta else -1,
                    }
            self._eventi_calendario = list(eventi.values())
            self.calendarioCambiato.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare il calendario: {e}")

    @pyqtSlot(str)
    def creaEventoProgrammato(self, data_str):
        # Una cella gia' pianificata a Macrociclo (ha un tipo) ma senza
        # ancora una seduta reale collegata: crea la seduta e la collega,
        # senza toccare il tipo impegno gia' scelto in fase di piano.
        self._crea_e_collega_evento(data_str, "Programmato", tipo=None)

    @pyqtSlot(str, str)
    def creaEventoExtra(self, data_str, tipo):
        # Nessuna pianificazione a Macrociclo per questa data: evento "fuori
        # piano", scritto sia come seduta reale sia come cella di macrociclo
        # con il tipo scelto dall'utente (stesso comportamento del vecchio
        # DialogCalendario - "Nuovo Evento Extra").
        if tipo not in ("A", "C", "TM", "TA"):
            return
        self._crea_e_collega_evento(data_str, "Extra", tipo=tipo)

    def _crea_e_collega_evento(self, data_str, numero_seduta, tipo):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        risultato = _id_settimana_giorno_da_data(gruppo["stag"], data_str)
        if not risultato:
            self._imposta_errore("Data fuori dalla stagione corrente: impossibile collegarla al calendario.")
            return
        id_settimana, giorno = risultato
        try:
            nuovo_id = DataManager.crea_seduta_e_collega_macrociclo(
                self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"],
                data_str, numero_seduta, id_settimana, giorno, tipo=tipo,
            )
            self._ricarica_sedute()
            self.selezionaSedutaPerId(nuovo_id)
            self._imposta_messaggio("Evento creato e collegato al calendario.")
        except Exception as e:
            self._imposta_errore(f"Impossibile creare l'evento: {e}")
            # Vedi guardia IS NULL in crea_seduta_e_collega_macrociclo: la
            # cella puo' essere gia' stata collegata da un'altra azione nel
            # frattempo (es. da Macrociclo) - ricaricare il calendario mostra
            # subito il collegamento vero invece di uno stantio.
            self.ricaricaEventiCalendario()

    # ==========================================
    # GRIGLIA MENSILE
    # ==========================================
    @pyqtSlot(int, int)
    def impostaMeseAnnoReport(self, mese, anno):
        if mese < 1 or mese > 12:
            return
        self._mese_report = mese
        self._anno_report = anno
        self.calcolaGrigliaMensile()

    @pyqtSlot()
    def calcolaGrigliaMensile(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._griglia_mensile = {"giorniTotali": 0, "tipiGiorno": [], "righe": [], "totalePresentiGiorno": [], "percPresentiGiorno": []}
            self.grigliaMensileCambiata.emit()
            return
        try:
            mese, anno = self._mese_report, self._anno_report
            gg_tot = calendar.monthrange(anno, mese)[1]
            # includi_eliminati=True: un giocatore eliminato durante la
            # stagione resta nella griglia mensile con le sue presenze
            # storiche, "Null" (cella vuota, non conteggiata) per i giorni
            # in cui non era in squadra.
            giocatori = DataManager.get_giocatori(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], includi_eliminati=True)
            sedute_tutte = DataManager.get_sedute_lista_completa(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            mappa_tipi = DataManager.get_mappa_tipi_seduta(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            target = f"{anno}-{mese:02d}"
            sed_mese = [s for s in sedute_tutte if s["data_seduta"].startswith(target) and s["id_seduta"] in mappa_tipi]

            presenze = {}
            if sed_mese:
                id_sedute = [s["id_seduta"] for s in sed_mese]
                for id_g, id_s, stato in DataManager.get_presenze_multi_sedute(self._dati_utente, id_sedute):
                    presenze[(id_g, id_s)] = stato

            evento_del_giorno = {}
            for s in sed_mese:
                try:
                    giorno_num = int(s["data_seduta"].split("-")[2])
                    evento_del_giorno[giorno_num] = s["id_seduta"]
                except (ValueError, IndexError):
                    continue

            tipi_giorno = [mappa_tipi.get(evento_del_giorno.get(g), "") if g in evento_del_giorno else "" for g in range(1, gg_tot + 1)]

            giorno_presenti = {g: 0 for g in range(1, gg_tot + 1)}
            giorno_totale_ev = {g: 0 for g in range(1, gg_tot + 1)}
            righe = []
            for g in giocatori:
                id_g = g["id_giocatore"]
                giorni = []
                t_p = t_a = c_c = c_nc = 0
                for gg in range(1, gg_tot + 1):
                    if gg not in evento_del_giorno:
                        giorni.append("")
                        continue
                    id_s = evento_del_giorno[gg]
                    st = MAPPA_VECCHI_STATI.get(presenze.get((id_g, id_s), ""), presenze.get((id_g, id_s), ""))
                    giorni.append(st)
                    if st == "P":
                        t_p += 1; giorno_presenti[gg] += 1; giorno_totale_ev[gg] += 1
                    elif st == "A":
                        t_a += 1; giorno_totale_ev[gg] += 1
                    elif st == "C":
                        c_c += 1; giorno_presenti[gg] += 1; giorno_totale_ev[gg] += 1
                    elif st == "NC":
                        c_nc += 1; giorno_totale_ev[gg] += 1
                righe.append({
                    "nome": g["nome"], "cognome": g["cognome"], "attivo": g["attivo"], "giorni": giorni,
                    "totalePresenze": t_p, "totaleAssenze": t_a,
                    "percPresenza": round(t_p / (t_p + t_a) * 100) if (t_p + t_a) > 0 else -1,
                    "totaleConvocazioni": c_c, "totaleRiposo": c_nc,
                    "percConvocazioni": round(c_c / (c_c + c_nc) * 100) if (c_c + c_nc) > 0 else -1,
                })

            totale_presenti_giorno = []
            perc_presenti_giorno = []
            for gg in range(1, gg_tot + 1):
                if gg in evento_del_giorno:
                    pc, tot = giorno_presenti[gg], giorno_totale_ev[gg]
                    totale_presenti_giorno.append(pc)
                    perc_presenti_giorno.append(round(pc / tot * 100) if tot > 0 else -1)
                else:
                    totale_presenti_giorno.append(-1)
                    perc_presenti_giorno.append(-1)

            self._griglia_mensile = {
                "giorniTotali": gg_tot, "tipiGiorno": tipi_giorno, "righe": righe,
                "totalePresentiGiorno": totale_presenti_giorno, "percPresentiGiorno": perc_presenti_giorno,
            }
            self.grigliaMensileCambiata.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile calcolare la griglia mensile: {e}")

    @pyqtSlot()
    def esportaGrigliaCsv(self):
        gruppo = self._gruppo_corrente()
        if not gruppo or not self._griglia_mensile["righe"]:
            self._imposta_errore("Nessun dato da esportare per questo mese.")
            return
        try:
            cartella = DataManager.cartella_report_presenze()
            nome_mese = MESI_NOMI[self._mese_report - 1]
            nome_file = f"Presenze_{gruppo['cat']}_{nome_mese}_{self._anno_report}.csv".replace("/", "-")
            percorso = os.path.join(cartella, nome_file)
            griglia = self._griglia_mensile
            with open(percorso, mode="w", newline="", encoding="utf-8-sig") as f:
                writer = csv.writer(f, delimiter=";")
                intestazione = ["Nome", "Cognome"] + [str(g) for g in range(1, griglia["giorniTotali"] + 1)] + [
                    "Totale Presenze", "Totale Assenze", "% Presenza", "Totale Convocazioni", "Totale Riposo", "% Convocazioni",
                ]
                writer.writerow(intestazione)
                writer.writerow(["Tipologia Impegno", ""] + griglia["tipiGiorno"])
                for r in griglia["righe"]:
                    perc_p = f"{r['percPresenza']}%" if r["percPresenza"] >= 0 else "-"
                    perc_c = f"{r['percConvocazioni']}%" if r["percConvocazioni"] >= 0 else "-"
                    writer.writerow([r["nome"], r["cognome"]] + r["giorni"] + [r["totalePresenze"], r["totaleAssenze"], perc_p, r["totaleConvocazioni"], r["totaleRiposo"], perc_c])
                riga_num = ["Presenti / Convocati", ""] + [v if v >= 0 else "" for v in griglia["totalePresentiGiorno"]]
                writer.writerow(riga_num)
                riga_perc = ["% Pres/Conv Giornaliera", ""] + [f"{v}%" if v >= 0 else "-" for v in griglia["percPresentiGiorno"]]
                writer.writerow(riga_perc)
            self._imposta_messaggio(f"Report esportato in: {percorso}")
            self._imposta_errore("")
        except Exception as e:
            self._imposta_errore(f"Impossibile esportare il report: {e}")
