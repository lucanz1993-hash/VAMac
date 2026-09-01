"""ViewModel Ricerca globale (barra "Cerca" della Title Bar). Cerca tra
gruppi/giocatori/sedute visibili all'utente (DataManager.cerca_globale) e,
alla scelta di un risultato, emette la richiesta di navigazione: App.qml la
traduce negli stessi meccanismi selezionaGruppoPer/selezionaSedutaPerId +
navigazioneVM.vaiA(...) già cablati per i salti Macrociclo->Sedute/Presenze,
nessuna nuova logica di deep-link da inventare."""

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager

# Indici Side Bar (root.sezioni in App.qml) — stessa convenzione manuale già
# in uso nei Connections cross-schermata esistenti in App.qml.
INDICE_ANAGRAFICA = 3
INDICE_SEDUTE = 2


class RicercaVM(QObject):
    risultatiCambiati = pyqtSignal()
    richiestaAperturaGruppo = pyqtSignal(int, str, str, str)
    richiestaAperturaSeduta = pyqtSignal(int, str, str, str, int)

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._risultati = []

    @pyqtProperty("QVariantList", notify=risultatiCambiati)
    def risultati(self):
        return self._risultati

    @pyqtSlot(str)
    def cerca(self, testo):
        try:
            self._risultati = DataManager.cerca_globale(self._dati_utente, testo)
        except Exception:
            self._risultati = []
        self.risultatiCambiati.emit()

    @pyqtSlot()
    def pulisci(self):
        if self._risultati:
            self._risultati = []
            self.risultatiCambiati.emit()

    @pyqtSlot(int)
    def apriRisultato(self, indice):
        if indice < 0 or indice >= len(self._risultati):
            return
        r = self._risultati[indice]
        cat, stag, soc = r.get("cat", ""), r.get("stag", ""), r.get("soc", "")
        if r.get("tipo") in ("gruppo", "giocatore"):
            self.richiestaAperturaGruppo.emit(INDICE_ANAGRAFICA, cat, stag, soc)
        elif r.get("tipo") == "seduta":
            self.richiestaAperturaSeduta.emit(INDICE_SEDUTE, cat, stag, soc, r.get("idSeduta", 0))
        self.pulisci()
