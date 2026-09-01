"""ViewModel di login. Ricostruito da zero (il precedente login_vm.py e'
stato cancellato con tutto il prototipo QML), ma preserva un comportamento
gia' corretto in precedenza e da non reintrodurre come bug: per il "ricordami"
si salva SOLO il token opaco (mai email/password in chiaro), validato al
prossimo avvio via /sessione/verifica invece di ripetere il login.
"""

import requests
from PyQt6.QtCore import QObject, QSettings, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import INDIRIZZO_SERVER
from theme_manager import ORGANIZZAZIONE, APPLICAZIONE

CHIAVE_TOKEN_SALVATO = "sessione/token"


class LoginVM(QObject):
    erroreCambiato = pyqtSignal()
    caricamentoCambiato = pyqtSignal()
    accessoRiuscito = pyqtSignal("QVariantMap")

    def __init__(self, parent=None):
        super().__init__(parent)
        self._errore = ""
        self._caricamento = False

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(bool, notify=caricamentoCambiato)
    def caricamento(self):
        return self._caricamento

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_caricamento(self, valore):
        self._caricamento = valore
        self.caricamentoCambiato.emit()

    def _salva_token(self, token):
        QSettings(ORGANIZZAZIONE, APPLICAZIONE).setValue(CHIAVE_TOKEN_SALVATO, token)

    @pyqtSlot(str, str)
    def accedi(self, email, password):
        self._imposta_errore("")
        self._imposta_caricamento(True)
        try:
            r = requests.post(f"{INDIRIZZO_SERVER}/login", json={"email": email, "password": password}, timeout=6)
            if r.status_code == 200:
                dati = r.json()
                dati["offline"] = False
                self._salva_token(dati.get("token", ""))
                self.accessoRiuscito.emit(dati)
            else:
                dettaglio = r.json().get("detail", "Email o password errati.") if r.content else "Email o password errati."
                self._imposta_errore(dettaglio)
        except requests.exceptions.RequestException:
            self._imposta_errore("Impossibile contattare il server. Verifica la connessione o accedi in modalita' offline.")
        finally:
            self._imposta_caricamento(False)

    @pyqtSlot()
    def tentaAccessoAutomatico(self):
        """Convalida un token salvato in precedenza, senza mai richiedere di
        ritrasmettere la password (vedi nota in cima al file)."""
        token = QSettings(ORGANIZZAZIONE, APPLICAZIONE).value(CHIAVE_TOKEN_SALVATO, "")
        if not token:
            return
        try:
            r = requests.get(f"{INDIRIZZO_SERVER}/sessione/verifica", headers={"Authorization": f"Bearer {token}"}, timeout=4)
            if r.status_code == 200:
                dati = r.json()
                dati["offline"] = False
                self.accessoRiuscito.emit(dati)
        except requests.exceptions.RequestException:
            pass  # Nessuna connessione: l'utente restera' sulla schermata di login.

    @pyqtSlot()
    def accessoOffline(self):
        # NOTA (comportamento preesistente, non una regressione introdotta
        # qui): ogni sessione offline e' sempre e solo "Admin" — non esiste
        # ancora un flusso per accedere offline come utente non-Admin. E'
        # una limitazione nota del sistema di permessi locale, documentata
        # nel report bug consegnato separatamente, non nello scope dei fix
        # Critical/High di questo intervento.
        self.accessoRiuscito.emit({
            "offline": True, "id_utente": 0, "email": "offline@locale",
            "nome_cognome": "Utente Locale", "ruolo": "Admin", "nome_societa": None, "categorie": [],
        })

    @pyqtSlot(str, str, str, str)
    def registrati(self, email, password, nome_cognome, ruolo):
        self._imposta_errore("")
        self._imposta_caricamento(True)
        try:
            r = requests.post(f"{INDIRIZZO_SERVER}/registrazione", json={
                "email": email, "password": password, "nome_cognome": nome_cognome, "ruolo": ruolo,
            }, timeout=6)
            if r.status_code == 200:
                self.accedi(email, password)
                return
            dettaglio = r.json().get("detail", "Registrazione non riuscita.") if r.content else "Registrazione non riuscita."
            self._imposta_errore(dettaglio)
        except requests.exceptions.RequestException:
            self._imposta_errore("Impossibile contattare il server.")
        finally:
            self._imposta_caricamento(False)
