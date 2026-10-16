"""ViewModel della Dashboard: riepilogo reale (prossima seduta, presenze da
registrare) tramite DataManager.get_riepilogo_dashboard.

NOTA: questa funzione esiste in data_manager.py da prima di questa sessione,
gia' funzionante e aggiornata (considera anche le celle di macrociclo non
ancora collegate a una seduta reale) - semplicemente nessuna schermata la
richiamava piu' dopo il redesign. La card "Dashboard" mostrava solo un
placeholder ("Nessun dato ancora disponibile"). Qui si ricollega la UI a un
dato gia' pronto, non si inventa nulla di nuovo lato dati."""

from datetime import date

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager


class DashboardVM(QObject):
    riepilogoCambiato = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._prossima_seduta = None
        self._sedute_da_registrare = 0
        self._sedute_mancanti = []
        self._errore = ""
        self.ricarica()

    @pyqtProperty(str, constant=True)
    def nomeUtente(self):
        return self._dati_utente.get("nome_cognome", "")

    @pyqtProperty(str, constant=True)
    def nomeSocieta(self):
        return self._dati_utente.get("nome_societa") or "Nessun club configurato"

    @pyqtProperty(bool, notify=riepilogoCambiato)
    def haProssimaSeduta(self):
        return self._prossima_seduta is not None

    @pyqtProperty(str, notify=riepilogoCambiato)
    def prossimaSedutaEtichetta(self):
        if not self._prossima_seduta:
            return ""
        p = self._prossima_seduta
        base = f"{p['cat']} — {p['stag']}"
        gruppo = f"{p['soc']} · {base}" if p.get("soc") else base
        return f"{p.get('numero', '')} — {gruppo}"

    @pyqtProperty(str, notify=riepilogoCambiato)
    def prossimaSedutaData(self):
        if not self._prossima_seduta:
            return ""
        try:
            anno, mese, giorno = self._prossima_seduta["data"].split("-")
            return f"{giorno}-{mese}-{anno}"
        except Exception:
            return self._prossima_seduta["data"]

    @pyqtProperty(str, notify=riepilogoCambiato)
    def prossimaSedutaConteggio(self):
        if not self._prossima_seduta:
            return ""
        try:
            differenza = (date.fromisoformat(self._prossima_seduta["data"]) - date.today()).days
        except Exception:
            return ""
        if differenza <= 0:
            return "OGGI"
        if differenza == 1:
            return "DOMANI"
        return f"tra {differenza} giorni"

    @pyqtProperty(int, notify=riepilogoCambiato)
    def sedutePresenzeMancanti(self):
        return self._sedute_da_registrare

    @pyqtProperty("QVariantList", notify=riepilogoCambiato)
    def sedutePresenzeMancantiElenco(self):
        # Stesso stile di prossimaSedutaData/prossimaSedutaEtichetta sopra:
        # i dati grezzi (data ISO, cat/stag/soc) restano in data_manager,
        # l'etichetta pronta per la UI si costruisce qui.
        elenco = []
        for s in self._sedute_mancanti:
            try:
                anno, mese, giorno = s["data"].split("-")
                data_it = f"{giorno}-{mese}-{anno}"
            except Exception:
                data_it = s["data"]
            base = f"{s['cat']} — {s['stag']}"
            gruppo = f"{s['soc']} · {base}" if s.get("soc") else base
            elenco.append({"idSeduta": s["idSeduta"], "etichetta": f"{data_it} — {gruppo}"})
        return elenco

    @pyqtProperty(str, notify=riepilogoCambiato)
    def errore(self):
        return self._errore

    @pyqtSlot()
    def ricarica(self):
        riepilogo = DataManager.get_riepilogo_dashboard(self._dati_utente)
        self._prossima_seduta = riepilogo.get("prossima_seduta")
        self._sedute_da_registrare = riepilogo.get("sedute_da_registrare", 0)
        self._sedute_mancanti = riepilogo.get("sedute_mancanti", [])
        self._errore = riepilogo.get("errore") or ""
        self.riepilogoCambiato.emit()
