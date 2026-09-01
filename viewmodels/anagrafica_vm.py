"""ViewModel Anagrafica: elenco gruppi (categoria+stagione+societa) e
giocatori del gruppo selezionato. Semplificazione deliberata rispetto al
vecchio schermo widget: la struttura a cartelle annidate per societa'
(raggruppamenti/indipendenti restituita da DataManager.get_anagrafica_gruppi)
viene appiattita in un'unica lista con etichetta "societa' — categoria
stagione", piu' adatta a un ComboBox piatto stile FM che a un albero; la
struttura dati sotto (get_giocatori/add/update/delete) resta quella di
DataManager, invariata."""

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager


class AnagraficaVM(QObject):
    gruppiCambiati = pyqtSignal()
    giocatoriCambiati = pyqtSignal()
    gruppoSelezionatoCambiato = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._gruppi = []
        self._giocatori = []
        self._indice_gruppo = -1
        self._errore = ""
        self._messaggio = ""
        self.ricaricaGruppi()

    def _etichetta_gruppo(self, g):
        base = f"{g['cat']} — {g['stag']}"
        return f"{g['soc']} · {base}" if g.get("soc") else base

    def _conteggio_gruppo(self, g):
        try:
            return len(DataManager.get_giocatori(self._dati_utente, g["cat"], g["stag"], g.get("soc") or ""))
        except Exception:
            return 0

    @pyqtProperty("QVariantList", notify=gruppiCambiati)
    def gruppi(self):
        return [
            {
                "label": self._etichetta_gruppo(g), "attivo": g["is_attivo"],
                "cat": g["cat"], "stag": g["stag"], "soc": g.get("soc") or "",
                "isAttivo": g["is_attivo"], "conteggio": self._conteggio_gruppo(g),
            }
            for g in self._gruppi
        ]

    @pyqtProperty(int, notify=gruppoSelezionatoCambiato)
    def indiceGruppo(self):
        return self._indice_gruppo

    @pyqtProperty("QVariantList", notify=giocatoriCambiati)
    def giocatori(self):
        return self._giocatori

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

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
                # agganciato al gruppo SBAGLIATO: l'etichetta mostrata
                # cambiava ma i giocatori restavano quelli di prima.
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
                        self._giocatori = []
                        self.giocatoriCambiati.emit()
                else:
                    # FIX: l'indice non e' cambiato, ma i dati dietro
                    # potrebbero essere completamente diversi (es. gruppo
                    # eliminato e ricreato identico altrove, stessa
                    # categoria/stagione/societa' quindi stessa posizione in
                    # elenco): ricarica SEMPRE i dipendenti quando
                    # gruppiCambiati scatta, non solo se l'indice si sposta -
                    # altrimenti l'elenco giocatori restava quello del
                    # gruppo vecchio, gia' cancellato (bug segnalato).
                    self.selezionaGruppo(nuovo_indice)
            elif gruppi and self._indice_gruppo == -1:
                self.selezionaGruppo(0)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i gruppi: {e}")

    @pyqtSlot(str, str, str)
    def selezionaGruppoPer(self, cat, stag, soc):
        """Seleziona il gruppo per categoria/stagione/societa', usato per
        navigare qui da un'altra schermata (es. ricerca globale)."""
        for i, g in enumerate(self._gruppi):
            if g["cat"] == cat and g["stag"] == stag and (g.get("soc") or "") == (soc or ""):
                self.selezionaGruppo(i)
                return

    @pyqtSlot(int)
    def selezionaGruppo(self, indice):
        if indice < 0 or indice >= len(self._gruppi):
            return
        self._indice_gruppo = indice
        self.gruppoSelezionatoCambiato.emit()
        self._ricarica_giocatori()

    def _gruppo_corrente(self):
        if 0 <= self._indice_gruppo < len(self._gruppi):
            return self._gruppi[self._indice_gruppo]
        return None

    def _ricarica_giocatori(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._giocatori = []
            self.giocatoriCambiati.emit()
            return
        try:
            # DataManager.get_giocatori restituisce sempre dict semplici (sia
            # offline che online costruiscono esplicitamente {"id_giocatore",
            # "nome", "cognome"}), quindi qui basta un accesso a chiave.
            righe = DataManager.get_giocatori(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._giocatori = [
                {"id": r["id_giocatore"], "nome": r["nome"], "cognome": r["cognome"]}
                for r in righe
            ]
            self.giocatoriCambiati.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i giocatori: {e}")

    @pyqtSlot(str, str)
    def aggiungiGiocatore(self, nome, cognome):
        gruppo = self._gruppo_corrente()
        if not gruppo or not nome.strip() or not cognome.strip():
            return
        try:
            DataManager.add_giocatore(self._dati_utente, nome.strip(), cognome.strip(), gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._ricarica_giocatori()
        except Exception as e:
            self._imposta_errore(f"Impossibile aggiungere il giocatore: {e}")

    @pyqtSlot(int, str, str)
    def modificaGiocatore(self, id_giocatore, nome, cognome):
        if not nome.strip() or not cognome.strip():
            return
        try:
            DataManager.update_giocatore(self._dati_utente, id_giocatore, nome.strip(), cognome.strip())
            self._ricarica_giocatori()
        except Exception as e:
            self._imposta_errore(f"Impossibile modificare il giocatore: {e}")

    @pyqtSlot(int)
    def eliminaGiocatore(self, id_giocatore):
        try:
            DataManager.delete_giocatore(self._dati_utente, id_giocatore)
            self._ricarica_giocatori()
        except Exception as e:
            self._imposta_errore(f"Impossibile eliminare il giocatore: {e}")
