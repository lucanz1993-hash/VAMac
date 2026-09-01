"""ViewModel Formazione: disposizione dei convocati in campo per un evento
partita (C/TM/TA), aperta da una cella di Macrociclo gia' collegata (vedi
MacrocicloVM.apriFormazioneCollegata), mai sfogliata autonomamente - a
differenza di Presenze/Sedute non ha una propria selezione gruppo/seduta,
riceve sempre categoria/stagione/societa/id_seduta gia' risolti da chi apre
lo schermo.

Offline/cloud-aware come MacrocicloVM/PresenzeVM (prende dati_utente), NON
come CoachingBoardVM (che non lo prende): la Formazione e' legata a un
id_seduta reale, entita' sincronizzabile della stessa famiglia di
Presenze/Board Partita, non un archivio personale locale scollegato come la
Lavagna tattica.

I convocati (roster) sono sempre ricalcolati dal vivo da giocatori/presenze,
mai congelati: solo la POSIZIONE di chi e' stato piazzato in campo (x/y/
squadra/portiere) e' dati persistiti, in una riga per seduta (tabella
formazione, UNIQUE su id_seduta - sovrascritta ad ogni salva(), nessuna
cronologia)."""

import json
import os
import re

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager

SQUADRE_VALIDE = ("sq1", "sq2")

DEFAULT_PIAZZATO = {
    "idGiocatore": None,
    "x": 0.5,
    "y": 0.5,
    "squadra": None,
    "portiere": False,
}


def _normalizza_piazzato(p):
    """Riempie le chiavi mancanti con un default: una formazione salvata
    prima che esistesse un campo (es. 'portiere') deve continuare a
    caricarsi senza eccezioni, stesso principio di _normalizza_elemento in
    coaching_board_vm.py."""
    normalizzato = dict(DEFAULT_PIAZZATO)
    normalizzato.update(p)
    return normalizzato


class FormazioneVM(QObject):
    rosterCambiato = pyqtSignal()
    piazzatiCambiato = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._cat = ""
        self._stag = ""
        self._soc = ""
        self._id_seduta = None
        self._giocatori = []  # [{"id_giocatore","nome","cognome"}], solo i convocati di questa seduta
        self._piazzati = []  # [{"idGiocatore","x","y","squadra","portiere"}]
        self._errore = ""
        self._messaggio = ""

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    @pyqtSlot(str, str, str, int)
    def apriPer(self, cat, stag, soc, id_seduta):
        self._cat, self._stag, self._soc, self._id_seduta = cat, stag, soc, id_seduta
        self._errore = ""
        self._messaggio = ""
        try:
            # Stesso calcolo di MacrocicloVM.convocatiPerCella: tutti i
            # giocatori del gruppo (inclusi gli eliminati, la loro
            # convocazione storica resta valida) incrociati con lo stato
            # presenze di questa seduta, filtrati a stato=="C".
            tutti = DataManager.get_giocatori(self._dati_utente, cat, stag, soc, includi_eliminati=True)
            presenze = DataManager.get_presenze_seduta(self._dati_utente, id_seduta)
            self._giocatori = [g for g in tutti if presenze.get(g["id_giocatore"]) == "C"]
            id_convocati = {g["id_giocatore"] for g in self._giocatori}

            grezzo = DataManager.get_formazione(self._dati_utente, id_seduta)
            try:
                lista_grezza = json.loads(grezzo) if grezzo else []
            except (ValueError, TypeError):
                lista_grezza = []
            # Un giocatore piazzato che nel frattempo non risulta piu'
            # convocato per questa seduta (convocazione tolta altrove, dopo
            # l'ultimo salvataggio della formazione) non resta come
            # marcatore orfano - stesso principio "sempre live" gia' seguito
            # dal resto del programma per lo stato presenze/convocazione.
            self._piazzati = [
                _normalizza_piazzato(p) for p in lista_grezza
                if isinstance(p, dict) and p.get("idGiocatore") in id_convocati
            ]
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare la formazione: {e}")
            self._giocatori = []
            self._piazzati = []
        self.rosterCambiato.emit()
        self.piazzatiCambiato.emit()

    @pyqtProperty("QVariantList", notify=rosterCambiato)
    def roster(self):
        piazzati_id = {p["idGiocatore"] for p in self._piazzati}
        return [
            {"id": g["id_giocatore"], "nome": g["nome"], "cognome": g["cognome"], "piazzato": g["id_giocatore"] in piazzati_id}
            for g in self._giocatori
        ]

    @pyqtProperty("QVariantList", notify=piazzatiCambiato)
    def piazzati(self):
        mappa_nomi = {g["id_giocatore"]: g for g in self._giocatori}
        risultato = []
        for p in self._piazzati:
            g = mappa_nomi.get(p["idGiocatore"], {"nome": "", "cognome": "?"})
            risultato.append({**p, "nome": g["nome"], "cognome": g["cognome"]})
        return risultato

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    @pyqtSlot(int, float, float)
    def piazzaGiocatore(self, id_giocatore, x, y):
        # Non piu' idempotente (Luca: "ogni giocatore deve poter essere
        # trascinato in campo anche due volte" - es. per mostrare un cambio
        # modulo/cambio ruolo con due marcatori dello stesso giocatore):
        # ogni drag dalla sidebar aggiunge SEMPRE un nuovo marcatore, mai
        # bloccato da uno gia' presente. Le operazioni sul singolo marcatore
        # (sposta/rimuovi/squadra/portiere) identificano quindi la riga per
        # INDICE in _piazzati, non piu' per idGiocatore (che ora puo'
        # comparire piu' volte).
        if not any(g["id_giocatore"] == id_giocatore for g in self._giocatori):
            return
        self._piazzati.append(_normalizza_piazzato({
            "idGiocatore": id_giocatore,
            "x": max(0.0, min(1.0, x)),
            "y": max(0.0, min(1.0, y)),
        }))
        self.rosterCambiato.emit()
        self.piazzatiCambiato.emit()

    @pyqtSlot(int, float, float)
    def spostaGiocatore(self, indice, x, y):
        if not (0 <= indice < len(self._piazzati)):
            return
        self._piazzati[indice]["x"] = max(0.0, min(1.0, x))
        self._piazzati[indice]["y"] = max(0.0, min(1.0, y))
        self.piazzatiCambiato.emit()

    @pyqtSlot(int)
    def rimuoviDalCampo(self, indice):
        if not (0 <= indice < len(self._piazzati)):
            return
        self._piazzati.pop(indice)
        self.rosterCambiato.emit()
        self.piazzatiCambiato.emit()

    @pyqtSlot(int, str)
    def impostaSquadra(self, indice, squadra):
        if squadra not in SQUADRE_VALIDE or not (0 <= indice < len(self._piazzati)):
            return
        self._piazzati[indice]["squadra"] = squadra
        self.piazzatiCambiato.emit()

    @pyqtSlot(int, bool)
    def impostaPortiere(self, indice, valore):
        if not (0 <= indice < len(self._piazzati)):
            return
        self._piazzati[indice]["portiere"] = bool(valore)
        self.piazzatiCambiato.emit()

    @pyqtSlot()
    def salva(self):
        try:
            dati_json = json.dumps(self._piazzati)
            DataManager.salva_formazione(self._dati_utente, self._id_seduta, self._cat, self._stag, self._soc, dati_json)
            self._imposta_messaggio("Formazione salvata.")
            self._imposta_errore("")
        except Exception as e:
            self._imposta_errore(f"Impossibile salvare la formazione: {e}")

    def _nome_file_sicuro(self, testo):
        pulito = re.sub(r'[\\/:*?"<>|]', "_", testo or "Formazione").strip()
        return pulito or "Formazione"

    @pyqtSlot(result=str)
    def percorsoImmaginePerSalvataggio(self):
        # Un solo file per seduta (nome = id_seduta): a differenza di
        # CoachingBoardVM.percorsoImmaginePerSalvataggio non serve alcuna
        # logica di collisione-nome, ogni Formazione ha gia' un id_seduta
        # univoco a fare da chiave.
        cartella = DataManager.cartella_grafiche_board()
        nome = self._nome_file_sicuro(f"Formazione - seduta {self._id_seduta}")
        return os.path.join(cartella, f"{nome}.png")

    @pyqtSlot(str)
    def confermaSalvataggio(self, percorso_immagine):
        self._imposta_messaggio(f"Immagine esportata: {percorso_immagine}")
