"""ViewModel Macrociclo: griglia settimanale (periodo/obiettivi + tipo
impegno lun-dom) per il gruppo selezionato.

Il collegamento cella<->seduta (crea/apri/scollega) e la "Board Partita"
(risultato e goal per giocatore convocato) esistevano nel vecchio widget e
nel prototipo QML scartato, ed erano stati segnalati come mancanti
nell'analisi di ripristino (docs/analisi-funzionalita-perse.md): sono
ripristinati qui, sopra le stesse funzioni di DataManager (mai cancellate
lato dati, solo scollegate dalla UI in precedenza).

I campi testuali (periodo/obiettivi/giorni) restano SOLO in memoria fino a
"Salva tutto" (batch, invariato); le operazioni di collegamento/scollegamento
e la Board Partita invece scrivono subito su database, perche' comportano
la creazione/modifica di una seduta reale, non solo di metadati testuali."""

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager, _data_cella_macrociclo, _periodo_predefinito_settimana

GIORNI = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]
CAMPI_TESTO = ["periodo", "obiettivo_tecnico", "obiettivo_tattico", "obiettivo_condizionale", "note"]
TIPI_PARTITA = ("C", "TM", "TA")


class MacrocicloVM(QObject):
    gruppiCambiati = pyqtSignal()
    gruppoSelezionatoCambiato = pyqtSignal()
    settimaneCambiate = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    richiestaAperturaSeduta = pyqtSignal(str, str, str, int)
    richiestaAperturaPresenze = pyqtSignal(str, str, str, int)
    richiestaAperturaFormazione = pyqtSignal(str, str, str, int)

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._gruppi = []
        self._indice_gruppo = -1
        self._righe_complete = []  # righe originali di DataManager, con eventuali modifiche utente applicate sopra
        self._errore = ""
        self._messaggio = ""
        self.ricaricaGruppi()

    def _etichetta_gruppo(self, g):
        base = f"{g['cat']} — {g['stag']}"
        return f"{g['soc']} · {base}" if g.get("soc") else base

    def _conteggio_gruppo(self, g):
        try:
            return len(DataManager.get_macrociclo(self._dati_utente, g["cat"], g["stag"], g.get("soc") or ""))
        except Exception:
            return 0

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    @pyqtProperty("QVariantList", notify=gruppiCambiati)
    def gruppi(self):
        return [
            {
                "label": self._etichetta_gruppo(g), "cat": g["cat"], "stag": g["stag"], "soc": g.get("soc") or "",
                "isAttivo": g["is_attivo"], "conteggio": self._conteggio_gruppo(g),
            }
            for g in self._gruppi
        ]

    @pyqtProperty(int, notify=gruppoSelezionatoCambiato)
    def indiceGruppo(self):
        return self._indice_gruppo

    @pyqtProperty("QVariantList", notify=settimaneCambiate)
    def settimane(self):
        # Vista per la QML: i campi testuali/giorno editabili, piu' (per ogni
        # giorno) l'eventuale id_seduta collegato e la nota Board Partita,
        # cosi' la UI puo' mostrare lo stato di collegamento senza dover
        # rileggere _righe_complete (privata) da fuori.
        viste = []
        for r in self._righe_complete:
            v = {"id_settimana": r["id_settimana"]}
            for campo in CAMPI_TESTO:
                v[campo] = r.get(campo) or ""
            for gg in GIORNI:
                v[gg] = (r.get(gg) or "").strip()
                v[f"idSeduta_{gg}"] = r.get(f"id_seduta_{gg}") or 0
                v[f"notaSeduta_{gg}"] = r.get(f"nota_{gg}") or ""
            viste.append(v)
        return viste

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
                # agganciato al gruppo SBAGLIATO.
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
                        self._righe_complete = []
                        self.settimaneCambiate.emit()
                else:
                    # FIX: l'indice non e' cambiato, ma i dati dietro
                    # potrebbero essere comunque cambiati (es. riapertura
                    # della schermata dopo un'eliminazione+ricreazione dello
                    # stesso gruppo, stessa categoria/stagione/societa'
                    # quindi stessa posizione in elenco): ricarica SEMPRE i
                    # dipendenti quando gruppiCambiati scatta, non solo se
                    # l'indice si sposta - stessa correzione applicata alle
                    # altre 4 ViewModel per lo stesso difetto.
                    self.selezionaGruppo(nuovo_indice)
            elif gruppi and self._indice_gruppo == -1:
                self.selezionaGruppo(0)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i gruppi: {e}")

    def _gruppo_corrente(self):
        if 0 <= self._indice_gruppo < len(self._gruppi):
            return self._gruppi[self._indice_gruppo]
        return None

    @pyqtSlot(str, str, str)
    def creaGruppo(self, cat, stag, soc):
        # UNICO punto del programma dove si puo' creare un gruppo (prima
        # esisteva una copia gemella in AnagraficaVM, rimossa): a differenza
        # di prima, "creare" ora scrive subito su DB tutte le settimane
        # della stagione (crea_gruppo_con_settimane), non solo un gruppo
        # vuoto in memoria in attesa di "Aggiungi settimana" + "Salva tutto".
        cat, stag, soc = cat.strip(), stag.strip(), soc.strip()
        if not cat or not stag:
            return
        for i, g in enumerate(self._gruppi):
            if g["cat"] == cat and g["stag"] == stag and (g.get("soc") or "") == soc:
                self.selezionaGruppo(i)
                return
        try:
            numero_settimane = DataManager.crea_gruppo_con_settimane(self._dati_utente, cat, stag, soc)
        except Exception as e:
            self._imposta_errore(f"Impossibile creare il gruppo: {e}")
            return
        self._imposta_errore("")
        self.ricaricaGruppi()
        nuovo_indice = next((i for i, g in enumerate(self._gruppi) if g["cat"] == cat and g["stag"] == stag and (g.get("soc") or "") == soc), -1)
        if nuovo_indice != -1:
            self.selezionaGruppo(nuovo_indice)
        # Impostato PER ULTIMO: selezionaGruppo() azzera sempre il messaggio
        # (vedi il suo commento sopra), quindi impostarlo prima verrebbe
        # subito cancellato dalla stessa chiamata.
        self._imposta_messaggio(f"Gruppo creato con {numero_settimane} settimane per la stagione {stag}.")

    @pyqtSlot()
    def eliminaGruppoCorrente(self):
        # UNICO punto del programma dove si puo' eliminare un gruppo (prima
        # esisteva una copia gemella in AnagraficaVM, rimossa): elimina ora a
        # cascata sedute/esercitazioni/presenze/giocatori oltre alle
        # settimane di macrociclo, non piu' solo queste ultime - altrimenti
        # un gruppo "eliminato" qui resterebbe comunque visibile ovunque
        # tramite i giocatori/sedute rimasti.
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        try:
            DataManager.elimina_gruppo_completo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._imposta_messaggio(f"Gruppo {gruppo['cat']} ({gruppo['stag']}) eliminato: macrociclo, sedute e giocatori.")
            self._imposta_errore("")
            self._indice_gruppo = -1
            self.ricaricaGruppi()
        except Exception as e:
            self._imposta_errore(f"Impossibile eliminare: {e}")

    @pyqtSlot(int)
    def selezionaGruppo(self, indice):
        if indice < 0 or indice >= len(self._gruppi):
            return
        self._indice_gruppo = indice
        self.gruppoSelezionatoCambiato.emit()
        # Il messaggio "salvato" va cancellato solo qui, cambiando gruppo -
        # NON dentro _ricarica_settimane(), che viene richiamata anche subito
        # dopo salva() per rileggere lo stato scritto: cancellarlo li' avrebbe
        # vanificato la conferma di salvataggio nello stesso istante in cui
        # veniva impostata (bug trovato con lo smoke test dedicato).
        self._imposta_messaggio("")
        self._ricarica_settimane()

    def _ricarica_settimane(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._righe_complete = []
            self.settimaneCambiate.emit()
            return
        try:
            righe = DataManager.get_macrociclo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            righe = sorted(righe, key=lambda r: r.get("id_settimana") or 0)
            self._righe_complete = righe
            self.settimaneCambiate.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare il macrociclo: {e}")

    def _trova_riga(self, id_settimana):
        for r in self._righe_complete:
            if r["id_settimana"] == id_settimana:
                return r
        return None

    @pyqtSlot(int, str, str)
    def impostaCampo(self, id_settimana, campo, valore):
        riga = self._trova_riga(id_settimana)
        if riga is None or campo not in CAMPI_TESTO:
            return
        riga[campo] = valore
        self.settimaneCambiate.emit()

    @pyqtSlot(int, str, str)
    def impostaGiorno(self, id_settimana, giorno, valore):
        riga = self._trova_riga(id_settimana)
        if riga is None or giorno not in GIORNI:
            return
        riga[giorno] = valore
        self.settimaneCambiate.emit()

    @pyqtSlot(int, str, result=bool)
    def cellaHaSedutaCollegata(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        return bool(riga and giorno in GIORNI and riga.get(f"id_seduta_{giorno}"))

    @pyqtSlot()
    def aggiungiSettimana(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        prossimo_id = max([r.get("id_settimana") or 0 for r in self._righe_complete], default=0) + 1
        nuova = {
            "id_settimana": prossimo_id, "stagione": gruppo["stag"], "categoria": gruppo["cat"],
            "periodo": _periodo_predefinito_settimana(gruppo["stag"], prossimo_id),
            "obiettivo_tecnico": "", "obiettivo_tattico": "", "obiettivo_condizionale": "", "note": "",
        }
        for gg in GIORNI:
            nuova[gg] = ""
        self._righe_complete.append(nuova)
        self.settimaneCambiate.emit()

    @pyqtSlot(int)
    def eliminaSettimana(self, id_settimana):
        self._righe_complete = [r for r in self._righe_complete if r["id_settimana"] != id_settimana]
        self.settimaneCambiate.emit()

    @pyqtSlot()
    def salva(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        payload = []
        for r in self._righe_complete:
            riga = dict(r)
            riga.pop("id_record", None)  # lasciare che l'INSERT assegni un nuovo id_record: non serve preservarlo.
            riga.pop("societa", None)    # impostati centralmente da salva_macrociclo_batch in base a "soc".
            riga.pop("id_societa", None)
            payload.append(riga)
        try:
            DataManager.salva_macrociclo_batch(self._dati_utente, payload, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._imposta_messaggio("Macrociclo salvato.")
            self._imposta_errore("")
            self._ricarica_settimane()
        except Exception as e:
            self._imposta_errore(f"Impossibile salvare: {e}")

    # ------------------------------------------------------------------
    # Collegamento cella <-> seduta
    # ------------------------------------------------------------------

    @pyqtSlot(int, str)
    def creaEColrgaSeduta(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI:
            return
        if riga.get(f"id_seduta_{giorno}"):
            return  # gia' collegata: usare scollegaSeduta prima di ricrearne un'altra
        tipo = (riga.get(giorno) or "").strip()
        if not tipo:
            self._imposta_errore("Imposta prima un tipo di impegno per questo giorno (es. A, TM, TA, C).")
            return
        data_cella = _data_cella_macrociclo(gruppo["stag"], id_settimana, giorno)
        if data_cella is None:
            self._imposta_errore("Impossibile calcolare la data di questa cella.")
            return
        numero = "Da Def." if tipo == "A" else "Partita"
        try:
            # FIX: passava tipo=None assumendo che il tipo impegno fosse gia'
            # su DB da un precedente "Salva tutto" - se l'utente cambiava il
            # tipo e collegava la seduta SENZA salvare prima, la colonna
            # macrociclo.<giorno> restava vuota su DB, get_mappa_tipi_seduta
            # non trovava alcun tipo per la seduta appena creata e Presenze
            # mostrava P/A invece di C/NC per un evento partita. Il tipo e'
            # gia' disponibile qui in memoria (letto sopra): passarlo scrive
            # subito la colonna corretta, senza dipendere dall'ordine delle
            # azioni dell'utente.
            DataManager.crea_seduta_e_collega_macrociclo(
                self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"],
                data_cella.isoformat(), numero, id_settimana, giorno, tipo,
            )
            self._imposta_messaggio("Seduta creata e collegata a questa cella.")
            self._imposta_errore("")
            self._ricarica_settimane()
        except Exception as e:
            self._imposta_errore(f"Impossibile creare la seduta: {e}")
            # La cella puo' risultare gia' collegata su DB da un'altra azione
            # (vedi guardia IS NULL in crea_seduta_e_collega_macrociclo):
            # ricaricare subito mostra lo stato vero invece di lasciare la
            # riga com'era prima del tentativo fallito.
            self._ricarica_settimane()

    @pyqtSlot(int, str, result="QVariantList")
    def sedutePerCollegamento(self, id_settimana, giorno):
        """Elenco delle sedute gia' esistenti nel gruppo corrente, per il
        pop-up "Collega seduta esistente": prima "Crea e collega seduta" era
        l'UNICA scelta, quindi collegare una seduta gia' creata a parte (es.
        in Sedute) o ne creava una nuova duplicata, o non c'era proprio modo
        di farlo - segnalato da Luca.

        FIX: prima elencava TUTTE le sedute del gruppo, comprese quelle gia'
        collegate a un'altra cella (es. le sedute "Partita" ancorate a un
        giorno di partita gia' salvato) - selezionandole si sarebbe rubato
        il collegamento a quella cella, lasciandola orfana, e/o trasformato
        un ancoraggio presenze di una partita in una seduta di allenamento
        (segnalato da Luca: "compaiono sedute collegate/Partita che non
        devono esistere" nell'elenco). Le sedute "Partita" sono create solo
        come ancora presenze per un giorno di impegno C/TM/TA (vedi
        creaEColrgaSeduta) e non vanno mai proposte per un giorno "A".
        Si escludono quindi sia le sedute gia' agganciate a QUALSIASI cella
        del gruppo (lette da _righe_complete, gia' in memoria) sia quelle
        con numero_seduta == "Partita" anche se per qualche motivo orfane."""
        gruppo = self._gruppo_corrente()
        if not gruppo or giorno not in GIORNI:
            return []
        gia_collegate = set()
        for r in self._righe_complete:
            for gg in GIORNI:
                id_collegato = r.get(f"id_seduta_{gg}")
                if id_collegato:
                    gia_collegate.add(id_collegato)
        try:
            sedute = DataManager.get_sedute_lista_completa(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
        except Exception:
            return []
        risultato = []
        for s in sedute:
            if s["id_seduta"] in gia_collegate:
                continue
            if (s.get("numero_seduta") or "") == "Partita":
                continue
            try:
                anno, mese, giorno_data = (s.get("data_seduta") or "").split("-")
                data_it = f"{giorno_data}-{mese}-{anno}" if len(anno) == 4 else (s.get("data_seduta") or "")
            except ValueError:
                data_it = s.get("data_seduta") or ""
            risultato.append({"id_seduta": s["id_seduta"], "label": f"{data_it} — {s.get('numero_seduta', '')}"})
        return risultato

    @pyqtSlot(int, str, int)
    def collegaSedutaEsistente(self, id_settimana, giorno, id_seduta):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI or not id_seduta:
            return
        if riga.get(f"id_seduta_{giorno}"):
            return  # gia' collegata: usare scollegaSeduta prima di ricollegare
        try:
            DataManager.collega_seduta_esistente_a_macrociclo(
                self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], id_settimana, giorno, id_seduta,
            )
            self._imposta_messaggio("Seduta esistente collegata a questa cella.")
            self._imposta_errore("")
            self._ricarica_settimane()
        except Exception as e:
            self._imposta_errore(f"Impossibile collegare la seduta: {e}")
            self._ricarica_settimane()

    @pyqtSlot(int, str)
    def scollegaSeduta(self, id_settimana, giorno):
        gruppo = self._gruppo_corrente()
        if not gruppo or giorno not in GIORNI:
            return
        try:
            DataManager.scollega_seduta_da_macrociclo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], id_settimana, giorno)
            self._imposta_messaggio("Seduta scollegata (non eliminata: resta consultabile in Sedute/Presenze).")
            self._imposta_errore("")
            self._ricarica_settimane()
        except Exception as e:
            self._imposta_errore(f"Impossibile scollegare: {e}")

    @pyqtSlot(int, str)
    def apriSedutaCollegata(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI:
            return
        id_seduta = riga.get(f"id_seduta_{giorno}")
        if id_seduta:
            self.richiestaAperturaSeduta.emit(gruppo["cat"], gruppo["stag"], gruppo.get("soc") or "", id_seduta)

    @pyqtSlot(int, str)
    def apriPresenzeCollegate(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI:
            return
        id_seduta = riga.get(f"id_seduta_{giorno}")
        if id_seduta:
            self.richiestaAperturaPresenze.emit(gruppo["cat"], gruppo["stag"], gruppo.get("soc") or "", id_seduta)

    @pyqtSlot(int, str)
    def apriFormazioneCollegata(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI:
            return
        id_seduta = riga.get(f"id_seduta_{giorno}")
        if id_seduta:
            self.richiestaAperturaFormazione.emit(gruppo["cat"], gruppo["stag"], gruppo.get("soc") or "", id_seduta)

    # ------------------------------------------------------------------
    # Board Partita (risultato + goal/note per giocatore convocato)
    # ------------------------------------------------------------------

    @pyqtSlot(int, str, result=str)
    def datiBoardPartita(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        if riga is None or giorno not in GIORNI:
            return "{}"
        return riga.get(f"nota_{giorno}") or "{}"

    @pyqtSlot(int, str, result="QVariantList")
    def convocatiPerCella(self, id_settimana, giorno):
        riga = self._trova_riga(id_settimana)
        gruppo = self._gruppo_corrente()
        if riga is None or not gruppo or giorno not in GIORNI:
            return []
        id_seduta = riga.get(f"id_seduta_{giorno}")
        if not id_seduta:
            return []
        try:
            # includi_eliminati=True: un giocatore nel frattempo eliminato ma
            # gia' convocato per QUESTA seduta (storico) deve restare
            # visibile qui, altrimenti il suo risultato/goal gia' registrato
            # in Board Partita sparirebbe dalla vista pur restando nei dati.
            giocatori = DataManager.get_giocatori(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], includi_eliminati=True)
            presenze = DataManager.get_presenze_seduta(self._dati_utente, id_seduta)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i convocati: {e}")
            return []
        return [
            {"id": g["id_giocatore"], "nome": g["nome"], "cognome": g["cognome"]}
            for g in giocatori if presenze.get(g["id_giocatore"]) == "C"
        ]

    @pyqtSlot(int, str, str)
    def salvaBoardPartita(self, id_settimana, giorno, dati_json):
        gruppo = self._gruppo_corrente()
        riga = self._trova_riga(id_settimana)
        if not gruppo or riga is None or giorno not in GIORNI:
            return
        try:
            DataManager.salva_board_partita(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], id_settimana, giorno, dati_json)
            self._imposta_messaggio("Board Partita salvata.")
            self._imposta_errore("")
            # FIX: chiamava _ricarica_settimane() (rilettura completa da DB),
            # che rigenera _righe_complete e con essa la QVariantList di
            # "settimane": il Repeater dentro il Flickable di Macrociclo.qml
            # distruggeva e ricreava TUTTI i delegate FMCard ad ogni salvataggio
            # Board Partita, riportando lo scroll in cima alla settimana 1.
            # Nessuna cella della griglia legge "notaSeduta_<giorno>" (solo il
            # dialog Board Partita, che rilegge sempre al volo via
            # datiBoardPartita()/convocatiPerCella()): basta aggiornare la riga
            # in memoria SENZA emettere settimaneCambiate, a differenza di
            # impostaGiorno/impostaCampo (che invece emettono perche' quei
            # campi sono davvero renderizzati nella griglia).
            riga[f"nota_{giorno}"] = dati_json
        except Exception as e:
            self._imposta_errore(f"Impossibile salvare la Board Partita: {e}")
