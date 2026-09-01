"""ViewModel della schermata Profilo: dati account (nome/email/ruolo/club) e,
da questa sessione in poi, il selettore di tema (Aspetto) — scelta
deliberata: il tema e' una preferenza locale, va restata utilizzabile anche
offline, quindi la card "Aspetto" in Profilo.qml non deve mai dipendere da
`offline` per abilitarsi, a differenza dei campi cloud-only di questa stessa
schermata."""

import requests
from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import INDIRIZZO_SERVER, DataManager

# Ruoli che possono gestire gli accessi al proprio club: stessa regola del
# vecchio DialogGestisciAccessi (interfaccia_macrociclo.py), che era
# raggiungibile solo dal menu contestuale "Gestisci Accessi" sul nodo
# societa' dell'albero Macrociclo - qui e' spostato in Profilo perche' la
# ricostruzione attuale non ha ancora un albero gerarchico Club/Spazio
# Personale (vedi analisi-funzionalita-perse.md), ma la funzionalita' stessa
# non deve restare irraggiungibile fino a quando quell'albero non tornera'.
RUOLI_GESTIONE_ACCESSI = ("Master", "Admin")


class ProfiloVM(QObject):
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    accountEliminato = pyqtSignal()
    logoutRichiesto = pyqtSignal()
    utentiClubCambiati = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._errore = ""
        self._messaggio = ""
        self._utenti_club = []
        if self.puoGestireAccessi:
            self.ricaricaUtentiClub()

    def _headers(self):
        token = self._dati_utente.get("token", "")
        return {"Authorization": f"Bearer {token}"} if token else {}

    @pyqtProperty(bool, constant=True)
    def offline(self):
        return bool(self._dati_utente.get("offline", False))

    @pyqtProperty(str, constant=True)
    def email(self):
        return self._dati_utente.get("email", "")

    @pyqtProperty(str, constant=True)
    def ruolo(self):
        return self._dati_utente.get("ruolo", "")

    @pyqtProperty(str, constant=True)
    def nomeCognome(self):
        return self._dati_utente.get("nome_cognome", "")

    @pyqtProperty(str, constant=True)
    def nomeSocieta(self):
        return self._dati_utente.get("nome_societa") or "Nessun club"

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    @pyqtProperty(bool, constant=True)
    def puoGestireAccessi(self):
        return self._dati_utente.get("ruolo") in RUOLI_GESTIONE_ACCESSI and bool(self._dati_utente.get("nome_societa"))

    @pyqtProperty("QVariantList", notify=utentiClubCambiati)
    def utentiClub(self):
        return self._utenti_club

    @pyqtSlot()
    def ricaricaUtentiClub(self):
        if not self.puoGestireAccessi:
            return
        try:
            self._utenti_club = DataManager.get_utenti_cartella(self._dati_utente, self._dati_utente.get("nome_societa"))
            self.utentiClubCambiati.emit()
        except Exception as e:
            self._errore = f"Impossibile caricare gli utenti del club: {e}"
            self.erroreCambiato.emit()

    @pyqtSlot(str, str)
    def invitaUtenteClub(self, email, ruolo):
        if not self.puoGestireAccessi or not email.strip():
            return
        try:
            DataManager.aggiungi_permesso_cartella(self._dati_utente, self._dati_utente.get("nome_societa"), email.strip(), ruolo)
            self._messaggio = f"Utente {email.strip()} aggiunto come {ruolo}."
            self.messaggioCambiato.emit()
            self.ricaricaUtentiClub()
        except Exception as e:
            self._errore = f"Impossibile invitare l'utente: {e}"
            self.erroreCambiato.emit()

    @pyqtSlot(str)
    def rimuoviUtenteClub(self, email):
        if not self.puoGestireAccessi:
            return
        try:
            DataManager.rimuovi_permesso_cartella(self._dati_utente, self._dati_utente.get("nome_societa"), email)
            self._messaggio = f"Accesso di {email} rimosso."
            self.messaggioCambiato.emit()
            self.ricaricaUtentiClub()
        except Exception as e:
            self._errore = f"Impossibile rimuovere l'utente: {e}"
            self.erroreCambiato.emit()

    @pyqtSlot(str)
    def salvaNome(self, nuovo_nome):
        if self.offline:
            return
        try:
            r = requests.put(
                f"{INDIRIZZO_SERVER}/utenti/{self._dati_utente['id_utente']}/profilo",
                json={"nome_cognome": nuovo_nome, "nome_societa": self._dati_utente.get("nome_societa")},
                headers=self._headers(), timeout=6,
            )
            if r.status_code == 200:
                self._dati_utente["nome_cognome"] = nuovo_nome
                self._messaggio = "Nome aggiornato."
                self.messaggioCambiato.emit()
            else:
                self._errore = "Impossibile aggiornare il nome."
                self.erroreCambiato.emit()
        except requests.exceptions.RequestException:
            self._errore = "Impossibile contattare il server."
            self.erroreCambiato.emit()

    @pyqtSlot()
    def eliminaAccount(self):
        if self.offline:
            return
        try:
            r = requests.delete(
                f"{INDIRIZZO_SERVER}/utenti/{self._dati_utente['id_utente']}",
                headers=self._headers(), timeout=6,
            )
            if r.status_code == 200:
                self.accountEliminato.emit()
            else:
                self._errore = "Impossibile eliminare l'account."
                self.erroreCambiato.emit()
        except requests.exceptions.RequestException:
            self._errore = "Impossibile contattare il server."
            self.erroreCambiato.emit()

    @pyqtSlot()
    def logout(self):
        if not self.offline:
            try:
                requests.post(f"{INDIRIZZO_SERVER}/logout", headers=self._headers(), timeout=4)
            except requests.exceptions.RequestException:
                pass
        self.logoutRichiesto.emit()
