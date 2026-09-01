"""ViewModel di navigazione tra le sezioni della Side Bar. Espone solo lo
stato (indice corrente, modalita' GK, se il Profilo e' attivo) — App.qml
mappa l'indice sulla sezione QML da mostrare nello StackView."""

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot


class NavigazioneVM(QObject):
    correnteCambiata = pyqtSignal()
    modalitaGkCambiata = pyqtSignal()
    profiloAttivoCambiato = pyqtSignal()
    lavagnaAttivaCambiata = pyqtSignal()
    formazioneAttivaCambiata = pyqtSignal()
    storicoCambiato = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._corrente = 0
        self._modalita_gk = False
        self._profilo_attivo = False
        self._lavagna_attiva = False
        self._formazione_attiva = False
        # History indietro/avanti stile browser: lista di stati visitati +
        # puntatore alla posizione corrente. Popolata da vaiA/vaiAProfilo/
        # vaiALavagnaEditor/vaiAFormazione (navigazione "in avanti", che
        # tronca eventuale storia successiva come farebbe un browser);
        # indietro()/avanti() si limitano a muovere il puntatore, senza
        # appendere nulla.
        self._storico = [(self._corrente, self._profilo_attivo, self._lavagna_attiva, self._formazione_attiva)]
        self._indice_storico = 0

    def _registra_stato(self):
        stato = (self._corrente, self._profilo_attivo, self._lavagna_attiva, self._formazione_attiva)
        if self._storico[self._indice_storico] == stato:
            return
        self._storico = self._storico[:self._indice_storico + 1]
        self._storico.append(stato)
        self._indice_storico = len(self._storico) - 1
        self.storicoCambiato.emit()

    def _applica_stato(self, stato):
        corrente, profilo_attivo, lavagna_attiva, formazione_attiva = stato
        if profilo_attivo != self._profilo_attivo:
            self._profilo_attivo = profilo_attivo
            self.profiloAttivoCambiato.emit()
        if lavagna_attiva != self._lavagna_attiva:
            self._lavagna_attiva = lavagna_attiva
            self.lavagnaAttivaCambiata.emit()
        if formazione_attiva != self._formazione_attiva:
            self._formazione_attiva = formazione_attiva
            self.formazioneAttivaCambiata.emit()
        if corrente != self._corrente:
            self._corrente = corrente
            self.correnteCambiata.emit()

    @pyqtProperty(int, notify=correnteCambiata)
    def corrente(self):
        return self._corrente

    @pyqtProperty(bool, notify=storicoCambiato)
    def puoIndietro(self):
        return self._indice_storico > 0

    @pyqtProperty(bool, notify=storicoCambiato)
    def puoAvanti(self):
        return self._indice_storico < len(self._storico) - 1

    @pyqtSlot()
    def indietro(self):
        if not self.puoIndietro:
            return
        self._indice_storico -= 1
        self._applica_stato(self._storico[self._indice_storico])
        self.storicoCambiato.emit()

    @pyqtSlot()
    def avanti(self):
        if not self.puoAvanti:
            return
        self._indice_storico += 1
        self._applica_stato(self._storico[self._indice_storico])
        self.storicoCambiato.emit()

    @pyqtProperty(bool, notify=modalitaGkCambiata)
    def modalitaGk(self):
        return self._modalita_gk

    @pyqtProperty(bool, notify=profiloAttivoCambiato)
    def profiloAttivo(self):
        return self._profilo_attivo

    @pyqtProperty(bool, notify=lavagnaAttivaCambiata)
    def lavagnaAttiva(self):
        return self._lavagna_attiva

    @pyqtProperty(bool, notify=formazioneAttivaCambiata)
    def formazioneAttiva(self):
        return self._formazione_attiva

    @pyqtSlot(int)
    def vaiA(self, indice):
        if self._profilo_attivo:
            self._profilo_attivo = False
            self.profiloAttivoCambiato.emit()
        if self._lavagna_attiva:
            self._lavagna_attiva = False
            self.lavagnaAttivaCambiata.emit()
        if self._formazione_attiva:
            self._formazione_attiva = False
            self.formazioneAttivaCambiata.emit()
        if indice != self._corrente:
            self._corrente = indice
            self.correnteCambiata.emit()
        self._registra_stato()

    @pyqtSlot()
    def vaiAProfilo(self):
        self._lavagna_attiva = False
        self.lavagnaAttivaCambiata.emit()
        self._formazione_attiva = False
        self.formazioneAttivaCambiata.emit()
        if not self._profilo_attivo:
            self._profilo_attivo = True
            self.profiloAttivoCambiato.emit()
        self._registra_stato()

    @pyqtSlot()
    def vaiALavagnaEditor(self):
        # Apre l'editor Coaching Board SOPRA la sezione Lavagna (l'archivio
        # HubBoard) senza cambiare voce di Side Bar attiva - stesso principio
        # di vaiAProfilo(), che sostituisce il contenuto senza toccare
        # "corrente".
        self._profilo_attivo = False
        self.profiloAttivoCambiato.emit()
        self._formazione_attiva = False
        self.formazioneAttivaCambiata.emit()
        if not self._lavagna_attiva:
            self._lavagna_attiva = True
            self.lavagnaAttivaCambiata.emit()
        self._registra_stato()

    @pyqtSlot()
    def vaiAFormazione(self):
        # Stesso principio di vaiALavagnaEditor(): apre Formazione SOPRA la
        # sezione corrente (sempre Macrociclo, in pratica) senza cambiare
        # voce di Side Bar attiva.
        self._profilo_attivo = False
        self.profiloAttivoCambiato.emit()
        self._lavagna_attiva = False
        self.lavagnaAttivaCambiata.emit()
        if not self._formazione_attiva:
            self._formazione_attiva = True
            self.formazioneAttivaCambiata.emit()
        self._registra_stato()

    @pyqtSlot(bool)
    def impostaModalitaGk(self, attiva):
        if attiva != self._modalita_gk:
            self._modalita_gk = attiva
            self.modalitaGkCambiata.emit()
