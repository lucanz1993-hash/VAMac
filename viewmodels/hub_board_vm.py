"""ViewModel HubBoard: archivio locale delle lavagne tattiche salvate
(tabella coaching_board, sempre locale - nessun ramo cloud, come nel
codice precedente: e' un archivio personale sul disco del mister, non un
dato di squadra condiviso).

"apriBoard" emette apriLavagnaRichiesta con i dati gia' pronti per
CoachingBoardVM.caricaLavagna: main.py collega questo segnale sia al
caricamento sia alla navigazione verso la sezione Lavagna, cosi' i due
ViewModel restano indipendenti (nessuno dei due conosce l'altro
direttamente, come per ogni altra coppia di schermate di questa app)."""

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager


class HubBoardVM(QObject):
    boardsCambiate = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    # FIX: modalita_campo/colore_campo/colore_linee aggiunti in coda -
    # prima non venivano proprio propagati, quindi riaprire una lavagna
    # mostrava sempre "Campo intero" e i colori di default (segnalato da
    # Luca).
    apriLavagnaRichiesta = pyqtSignal(int, str, str, str, str, str, str, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._boards = []
        self._messaggio = ""
        self.ricarica()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    @pyqtProperty("QVariantList", notify=boardsCambiate)
    def boards(self):
        return self._boards

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    @pyqtSlot()
    def ricarica(self):
        righe = DataManager.get_archivio_coaching_board()
        self._boards = [
            {"id_board": r[0], "mezzo_allenamento": r[1] or "", "percorso_immagine": r[2] or "", "titolo": r[3] or ""}
            for r in righe
        ]
        self.boardsCambiate.emit()

    @pyqtSlot(int)
    def eliminaBoard(self, id_board):
        try:
            DataManager.elimina_coaching_board(id_board)
            self._imposta_messaggio("Lavagna eliminata.")
            self.ricarica()
        except Exception as e:
            self._imposta_messaggio(f"Impossibile eliminare: {e}")

    @pyqtSlot(int)
    def apriBoard(self, id_board):
        board = next((b for b in self._boards if b["id_board"] == id_board), None)
        if not board:
            return
        # FIX: prima cercava per percorso_immagine, che due lavagne diverse
        # possono calcolare identico (stesso mezzo+titolo, es. entrambe
        # "Senza Titolo") - apriva percio' a volte i dati della lavagna
        # SBAGLIATA (miniatura giusta, contenuto vuoto o di un'altra -
        # segnalato da Luca). id_board e' sempre univoco.
        riga = DataManager.get_dati_vettoriali_board(id_board)
        dati_vettoriali = riga[0] if riga else "[]"
        descrizione = (riga[1] if riga and len(riga) > 1 else "") or ""
        modalita_campo = (riga[2] if riga and len(riga) > 2 else "") or "intero"
        colore_campo = (riga[3] if riga and len(riga) > 3 else "") or "#1e7d32"
        colore_linee = (riga[4] if riga and len(riga) > 4 else "") or "#ffffff"
        self.apriLavagnaRichiesta.emit(
            id_board, board.get("titolo", ""), board["mezzo_allenamento"], dati_vettoriali or "[]", descrizione,
            modalita_campo, colore_campo, colore_linee,
        )

    @pyqtSlot(int)
    def duplicaBoard(self, id_board):
        """Apre l'editor precaricato con lo stesso contenuto della grafica
        scelta ma SENZA il suo id_board (sentinella -1): il primo "Salva"
        nell'editor crea percio' una riga nuova invece di sovrascrivere
        l'originale - prima non esisteva alcun modo di creare una nuova
        grafica a partire da una gia' salvata (segnalato da Luca)."""
        board = next((b for b in self._boards if b["id_board"] == id_board), None)
        if not board:
            return
        riga = DataManager.get_dati_vettoriali_board(id_board)
        dati_vettoriali = riga[0] if riga else "[]"
        descrizione = (riga[1] if riga and len(riga) > 1 else "") or ""
        modalita_campo = (riga[2] if riga and len(riga) > 2 else "") or "intero"
        colore_campo = (riga[3] if riga and len(riga) > 3 else "") or "#1e7d32"
        colore_linee = (riga[4] if riga and len(riga) > 4 else "") or "#ffffff"
        titolo_copia = (board.get("titolo") or "Senza titolo") + " (copia)"
        self.apriLavagnaRichiesta.emit(
            -1, titolo_copia, board["mezzo_allenamento"], dati_vettoriali or "[]", descrizione,
            modalita_campo, colore_campo, colore_linee,
        )
