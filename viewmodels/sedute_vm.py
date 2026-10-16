"""ViewModel Sedute: elenco sedute del gruppo selezionato, editor dei blocchi
di allenamento (fasi_seduta + esercitazione collegata) della seduta aperta.

Il flag modalitaGk sceglie il vocabolario Mezzi/Tecnici/Tattici da
DataManager.carica_liste_menu_gk invece che carica_liste_menu (stesse
categorie di dati, valori diversi per il preparatore portieri) - questa e'
l'unica differenza reale tra le due "versioni" del vecchio schermo
duplicato (interfaccia_seduta.py / interfaccia_seduta_gk.py), quindi qui
diventa un semplice toggle invece di due file separati.

Semplificazione deliberata: l'immagine dell'esercitazione resta un campo
testo (percorso file), senza drag-and-drop; il collegamento automatico
cella-macrociclo (DataManager.crea_seduta_e_collega_macrociclo) non e'
ancora esposto da questa schermata - le sedute create qui restano
"libere" finche' Macrociclo non guadagna, in una fase successiva, un modo
per agganciarle a una cella.

NOTA: esportazione PDF e gestione voci menu (Mezzi/Tecnici/Tattici) esistono
in DataManager/esporta_pdf da prima del redesign ma erano rimaste senza
alcun punto d'accesso in UI dopo la ricostruzione da zero (nessuna schermata
le richiamava piu'): aggiunte qui durante il giro di test completo, perche'
altrimenti erano funzioni presenti nel codice ma di fatto irraggiungibili
per l'utente."""

import os

from PyQt6.QtCore import QObject, QSettings, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import GIORNI, DataManager, _id_settimana_giorno_da_data
from esporta_pdf import esporta_seduta_in_pdf

ORGANIZZAZIONE = "LB Coaching"
APPLICAZIONE = "FC Manager"
CHIAVE_CARTELLA_PDF = "sedute/cartellaEsportazionePdf"


def _iso_a_it(data_iso):
    """AAAA-MM-GG (formato di salvataggio, invariato) -> GG-MM-AAAA (formato
    mostrato/digitato in questa schermata)."""
    try:
        anno, mese, giorno = (data_iso or "").split("-")
        if len(anno) == 4 and len(mese) == 2 and len(giorno) == 2:
            return f"{giorno}-{mese}-{anno}"
    except (ValueError, AttributeError):
        pass
    return data_iso or ""


def _it_a_iso(data_it):
    """GG-MM-AAAA -> AAAA-MM-GG. Ritorna None se il testo non rispetta il
    formato atteso, cosi' il chiamante puo' segnalare un errore invece di
    salvare una data storpiata."""
    try:
        giorno, mese, anno = (data_it or "").strip().split("-")
        if len(giorno) == 2 and len(mese) == 2 and len(anno) == 4 and giorno.isdigit() and mese.isdigit() and anno.isdigit():
            from datetime import date
            date(int(anno), int(mese), int(giorno))  # valida che la data esista davvero
            return f"{anno}-{mese}-{giorno}"
    except (ValueError, AttributeError):
        pass
    return None


# "Nome blocco" e' diventato "Fase" a selezione multipla (Attivazione/Fase
# centrale/Fase finale): salvata come CSV di codici in fase["fase"], stesso
# principio del multi-select "tipi impegno" gia' in StatisticheVM
# (impostaTipoSelezionato), qui applicato per-blocco invece che globale.
FASI_BLOCCO_VALIDE = ["attivazione", "centrale", "finale"]


class SeduteVM(QObject):
    gruppiCambiati = pyqtSignal()
    gruppoSelezionatoCambiato = pyqtSignal()
    seduteCambiate = pyqtSignal()
    sedutaSelezionataCambiata = pyqtSignal()
    dettaglioCambiato = pyqtSignal()
    modalitaGkCambiata = pyqtSignal()
    menuCambiato = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()
    richiestaAperturaLavagnaPerBlocco = pyqtSignal(int)

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._gruppi = []
        self._indice_gruppo = -1
        self._sedute = []
        self._indice_seduta = -1
        self._id_seduta_corrente = None
        self._data_seduta = ""
        self._numero_seduta = ""
        self._giocatori = 0
        self._societa_stampa = ""
        self._obiettivo_principale = ""
        self._fasi = []
        self._modalita_gk = False
        self._menu = {"Mezzi": [], "Tecnici": [], "Tattici": []}
        self._errore = ""
        self._messaggio = ""
        # Consumato una tantum da Sedute.qml al Component.onCompleted: se
        # true, la schermata (che di norma apre sull'elenco sedute, non piu'
        # direttamente sul dettaglio - vedi vistaElenco) entra invece subito
        # nel dettaglio gia' caricato da selezionaSedutaPerId. Impostato SOLO
        # li' (navigazione da Macrociclo/ricerca globale verso una seduta
        # specifica), mai durante l'uso normale della schermata.
        self._salta_landing = False
        self._ricarica_menu()
        self.ricaricaGruppi()

    def _etichetta_gruppo(self, g):
        base = f"{g['cat']} — {g['stag']}"
        return f"{g['soc']} · {base}" if g.get("soc") else base

    def _conteggio_gruppo(self, g):
        try:
            return len(DataManager.get_sedute_lista_completa(self._dati_utente, g["cat"], g["stag"], g.get("soc") or ""))
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

    @pyqtProperty("QVariantList", notify=seduteCambiate)
    def sedute(self):
        return [{"label": f"{_iso_a_it(s['data_seduta'])} — {s['numero_seduta']}"} for s in self._sedute]

    @pyqtProperty(int, notify=sedutaSelezionataCambiata)
    def indiceSeduta(self):
        return self._indice_seduta

    @pyqtProperty(bool, notify=dettaglioCambiato)
    def sedutaCaricata(self):
        return self._id_seduta_corrente is not None

    @pyqtProperty(str, notify=dettaglioCambiato)
    def dataSeduta(self):
        return _iso_a_it(self._data_seduta)

    @pyqtProperty(str, notify=dettaglioCambiato)
    def numeroSeduta(self):
        return self._numero_seduta

    @pyqtProperty(int, notify=dettaglioCambiato)
    def giocatoriPresenti(self):
        return self._giocatori

    @pyqtProperty(str, notify=dettaglioCambiato)
    def societaStampa(self):
        return self._societa_stampa

    @pyqtProperty(str, notify=dettaglioCambiato)
    def obiettivoPrincipale(self):
        return self._obiettivo_principale

    @pyqtProperty("QVariantList", notify=dettaglioCambiato)
    def fasi(self):
        return self._fasi

    @pyqtProperty(bool, notify=modalitaGkCambiata)
    def modalitaGk(self):
        return self._modalita_gk

    @pyqtProperty("QVariantList", notify=menuCambiato)
    def listaMezzi(self):
        return self._menu.get("Mezzi", [])

    @pyqtProperty("QVariantList", notify=menuCambiato)
    def listaTecnici(self):
        return self._menu.get("Tecnici", [])

    @pyqtProperty("QVariantList", notify=menuCambiato)
    def listaTattici(self):
        return self._menu.get("Tattici", [])

    @pyqtProperty(str, notify=erroreCambiato)
    def errore(self):
        return self._errore

    @pyqtProperty(str, notify=messaggioCambiato)
    def messaggio(self):
        return self._messaggio

    def _ricarica_menu(self):
        offline = self._dati_utente.get("offline", False)
        self._menu = DataManager.carica_liste_menu_gk(offline) if self._modalita_gk else DataManager.carica_liste_menu(offline)
        self.menuCambiato.emit()

    @pyqtSlot(bool)
    def impostaModalitaGk(self, attiva):
        if attiva == self._modalita_gk:
            return
        self._modalita_gk = attiva
        self.modalitaGkCambiata.emit()
        self._ricarica_menu()

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
                        self._indice_seduta = -1
                        self._sedute = []
                        self.seduteCambiate.emit()
                        self.sedutaSelezionataCambiata.emit()
                        self._svuota_dettaglio()
                else:
                    # FIX: l'indice non e' cambiato - NON richiamare
                    # selezionaGruppo() qui (come si faceva prima): azzera
                    # sempre seduta/dettaglio correnti, quindi ogni volta che
                    # questa schermata viene ricreata (es. rientro dalla
                    # Lavagna Tattica dopo aver disegnato una grafica per un
                    # blocco: Sedute.qml richiama sempre ricaricaGruppi() al
                    # Component.onCompleted) la seduta su cui si stava
                    # lavorando veniva ricaricata da DB, perdendo ogni
                    # modifica non ancora salvata (segnalato da Luca).
                    # Si aggiorna solo l'elenco sedute - gestisce comunque il
                    # caso limite che aveva motivato il reload forzato
                    # (gruppo eliminato e ricreato identico altrove) - senza
                    # toccare il dettaglio se la seduta aperta esiste ancora.
                    self._indice_gruppo = nuovo_indice
                    self._ricarica_sedute(self._id_seduta_corrente)
            elif gruppi and self._indice_gruppo == -1:
                self.selezionaGruppo(0)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i gruppi: {e}")

    def _gruppo_corrente(self):
        if 0 <= self._indice_gruppo < len(self._gruppi):
            return self._gruppi[self._indice_gruppo]
        return None

    @pyqtSlot(int)
    def selezionaGruppo(self, indice):
        if indice < 0 or indice >= len(self._gruppi):
            return
        # Catturato PRIMA di _svuota_dettaglio() (che azzera
        # _id_seduta_corrente subito sotto): se il gruppo e' lo stesso di
        # prima (es. ricaricaGruppi() che ricarica sempre i dipendenti anche
        # a indice invariato) e quella seduta esiste ancora, _ricarica_sedute
        # la riseleziona invece di saltare silenziosamente all'ultima -
        # altrimenti "Apri seduta collegata" da Macrociclo/ricerca globale
        # apriva sempre l'ultima seduta del gruppo, non quella richiesta,
        # perche' Sedute.qml richiama ricaricaGruppi() al proprio
        # Component.onCompleted DOPO che la selezione corretta era gia'
        # stata impostata.
        id_da_preservare = self._id_seduta_corrente
        self._indice_gruppo = indice
        self.gruppoSelezionatoCambiato.emit()
        self._indice_seduta = -1
        self._svuota_dettaglio()
        self._ricarica_sedute(id_da_preservare)

    @pyqtSlot(str, str, str)
    def selezionaGruppoPer(self, cat, stag, soc):
        """Seleziona il gruppo per categoria/stagione/societa', usato per
        navigare qui da un'altra schermata (es. Macrociclo, "Apri seduta"
        su una cella collegata)."""
        for i, g in enumerate(self._gruppi):
            if g["cat"] == cat and g["stag"] == stag and (g.get("soc") or "") == (soc or ""):
                self.selezionaGruppo(i)
                return

    @pyqtSlot(int)
    def selezionaSedutaPerId(self, id_seduta):
        for i, s in enumerate(self._sedute):
            if s["id_seduta"] == id_seduta:
                self.selezionaSeduta(i)
                self._salta_landing = True
                return

    @pyqtSlot(result=bool)
    def consumaSaltaLanding(self):
        """Letta una tantum da Sedute.qml al Component.onCompleted: vedi
        commento su _salta_landing in __init__."""
        valore = self._salta_landing
        self._salta_landing = False
        return valore

    @pyqtSlot()
    def segnalaSaltaLanding(self):
        """Richiamato da App.qml prima di ri-navigare su questa schermata da
        un punto che lascia gia' una seduta aperta sensata da mostrare
        subito (es. rientro dalla Lavagna Tattica dopo aver disegnato una
        grafica per un blocco): senza, si tornava sempre sull'elenco invece
        che sul dettaglio su cui si stava lavorando (segnalato da Luca)."""
        self._salta_landing = True

    def _ricarica_sedute(self, id_da_preservare=None):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._sedute = []
            self.seduteCambiate.emit()
            return
        try:
            grezze = DataManager.get_sedute_lista_completa(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            # "Crea evento e apri presenze/Board Partita" in Macrociclo crea
            # una seduta-ancoraggio anche per celle NON di tipo Allenamento
            # (Campionato/Test Match/Torneo Amichevole): serve solo per
            # agganciare presenze/risultato, non e' una vera seduta di
            # allenamento e non deve comparire qui (segnalato da Luca).
            # get_mappa_tipi_seduta legge il tipo impegno reale dalla cella
            # macrociclo collegata; una seduta non collegata a nessuna cella
            # (creata direttamente qui) non compare in quella mappa ed e'
            # sempre trattata come Allenamento.
            mappa_tipi = DataManager.get_mappa_tipi_seduta(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            self._sedute = [s for s in grezze if mappa_tipi.get(s["id_seduta"], "A") == "A"]
            self.seduteCambiate.emit()
            if not self._sedute:
                return
            if id_da_preservare is not None:
                for i, s in enumerate(self._sedute):
                    if s["id_seduta"] == id_da_preservare:
                        if id_da_preservare == self._id_seduta_corrente:
                            # E' gia' la seduta aperta: NON ricaricarla da DB
                            # (si perderebbero modifiche non ancora salvate,
                            # vedi ricaricaGruppi sopra), basta tenere
                            # l'indice coerente con l'elenco appena
                            # ricaricato.
                            self._indice_seduta = i
                            self.sedutaSelezionataCambiata.emit()
                        else:
                            self.selezionaSeduta(i)
                        return
            self.selezionaSeduta(len(self._sedute) - 1)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare le sedute: {e}")

    def _svuota_dettaglio(self):
        self._id_seduta_corrente = None
        self._data_seduta = ""
        self._numero_seduta = ""
        self._giocatori = 0
        self._societa_stampa = ""
        self._obiettivo_principale = ""
        self._fasi = []
        self.dettaglioCambiato.emit()

    @pyqtSlot(int)
    def selezionaSeduta(self, indice):
        if indice < 0 or indice >= len(self._sedute):
            return
        self._indice_seduta = indice
        self.sedutaSelezionataCambiata.emit()
        id_s = self._sedute[indice]["id_seduta"]
        try:
            dettaglio = DataManager.get_seduta_dettaglio(self._dati_utente, id_s)
            if not dettaglio:
                self._imposta_errore("Impossibile aprire la seduta selezionata.")
                return
            self._id_seduta_corrente = dettaglio["id_seduta"]
            self._data_seduta = dettaglio["data_seduta"]
            self._numero_seduta = dettaglio["numero_seduta"]
            self._giocatori = dettaglio.get("giocatori") or 0
            self._societa_stampa = dettaglio.get("societa_stampa") or ""
            self._obiettivo_principale = dettaglio.get("obiettivo_principale") or ""
            self._fasi = dettaglio.get("fasi") or []
            self.dettaglioCambiato.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare il dettaglio seduta: {e}")

    @pyqtSlot(str)
    def nuovaSeduta(self, data_seduta):
        gruppo = self._gruppo_corrente()
        if not gruppo or not data_seduta.strip():
            return
        data_iso = _it_a_iso(data_seduta)
        if data_iso is None:
            self._imposta_errore("Formato data non valido. Usa GG-MM-AAAA (es. 28-07-2026).")
            return
        try:
            nuovo_id = DataManager.salva_seduta_strutturata(
                self._dati_utente, None, data_iso, "Da Def.",
                gruppo["cat"], gruppo["stag"], 0, gruppo["soc"], "", [], "",
            )
            self._collega_a_macrociclo_se_possibile(gruppo, data_iso, nuovo_id)
            self._imposta_messaggio("Seduta creata.")
            self._imposta_errore("")
            self._ricarica_sedute()
        except Exception as e:
            self._imposta_errore(f"Impossibile creare la seduta: {e}")

    def _collega_a_macrociclo_se_possibile(self, gruppo, data_iso, id_seduta):
        # FIX (segnalato da Luca): una seduta creata qui restava sempre
        # "libera" - nessun collegamento automatico alla cella del
        # macrociclo corrispondente, invisibile alla Griglia Mensile di
        # Presenze (che mostra solo sedute collegate) finche' qualcuno non
        # passava da Macrociclo a collegarla a mano, passo facile da
        # dimenticare (una seduta del genere e' finita orfana e con le
        # presenze del giorno "invisibili" in griglia). Se la data cade in
        # una cella libera e non ancora pianificata come partita (TM/TA/C -
        # quelle restano riservate al flusso "Crea evento e apri
        # Presenze/Board Partita" di Macrociclo, con semantica diversa), la
        # si collega da sola, pianificandola come Allenamento se la cella era
        # ancora completamente vuota. Un fallimento qui (nessuna riga per
        # quella settimana, cella gia' occupata, collegata nel frattempo...)
        # e' catturato e ignorato: la seduta e' comunque gia' stata creata
        # sopra, resta "libera" esattamente come prima di questo fix.
        try:
            risultato = _id_settimana_giorno_da_data(gruppo["stag"], data_iso)
            if not risultato:
                return
            id_settimana, giorno = risultato
            righe = DataManager.get_macrociclo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            riga = next((r for r in righe if r["id_settimana"] == id_settimana), None)
            if riga is None or riga.get(f"id_seduta_{giorno}"):
                return
            tipo_attuale = (riga.get(giorno) or "").strip()
            if tipo_attuale not in ("", "A"):
                return
            DataManager.collega_seduta_esistente_a_macrociclo(
                self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], id_settimana, giorno, id_seduta,
                tipo=("A" if tipo_attuale == "" else None),
            )
        except Exception:
            pass

    def _riallinea_collegamento_macrociclo(self, gruppo, nuova_data_iso):
        # Usato da spostaSedutaCorrente: se la seduta e' collegata a una
        # cella (qualunque giorno), la si scollega prima di ritentare
        # l'aggancio sulla cella giusta per la nuova data - altrimenti
        # resterebbe agganciata al vecchio giorno anche dopo lo spostamento
        # (vedi FIX nel commento di spostaSedutaCorrente). Un fallimento in
        # una qualunque delle due meta' (nessuna cella trovata da scollegare,
        # aggancio nuovo non possibile) e' catturato e ignorato: la seduta
        # resta comunque spostata, al peggio senza alcun collegamento -
        # esattamente come una seduta creata "libera".
        try:
            righe = DataManager.get_macrociclo(self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"])
            for r in righe:
                for gg in GIORNI:
                    if r.get(f"id_seduta_{gg}") == self._id_seduta_corrente:
                        DataManager.scollega_seduta_da_macrociclo(
                            self._dati_utente, gruppo["cat"], gruppo["stag"], gruppo["soc"], r["id_settimana"], gg,
                        )
                        break
                else:
                    continue
                break
        except Exception:
            pass
        self._collega_a_macrociclo_se_possibile(gruppo, nuova_data_iso, self._id_seduta_corrente)

    @pyqtSlot()
    def eliminaSedutaCorrente(self):
        if self._id_seduta_corrente is None:
            return
        try:
            DataManager.elimina_singola_seduta(self._dati_utente, self._id_seduta_corrente)
            self._imposta_messaggio("Seduta eliminata.")
            self._indice_seduta = -1
            self._svuota_dettaglio()
            self._ricarica_sedute()
        except Exception as e:
            self._imposta_errore(f"Impossibile eliminare la seduta: {e}")

    @pyqtSlot(str)
    def impostaNumeroSeduta(self, valore):
        if self._id_seduta_corrente is None or self._numero_seduta == valore:
            return
        self._numero_seduta = valore
        self.dettaglioCambiato.emit()

    @pyqtSlot(str)
    def impostaGiocatoriPresenti(self, valore):
        if self._id_seduta_corrente is None:
            return
        try:
            nuovo = int(valore)
        except ValueError:
            return
        if self._giocatori == nuovo:
            return
        self._giocatori = nuovo
        self.dettaglioCambiato.emit()

    @pyqtSlot(str)
    def impostaSocietaStampa(self, valore):
        if self._id_seduta_corrente is None or self._societa_stampa == valore:
            return
        self._societa_stampa = valore
        self.dettaglioCambiato.emit()

    @pyqtSlot(str)
    def impostaObiettivoPrincipale(self, valore):
        if self._id_seduta_corrente is None or self._obiettivo_principale == valore:
            return
        self._obiettivo_principale = valore
        self.dettaglioCambiato.emit()

    @pyqtSlot()
    def duplicaSedutaCorrente(self):
        gruppo = self._gruppo_corrente()
        if not gruppo or self._id_seduta_corrente is None:
            return
        try:
            DataManager.salva_seduta_strutturata(
                self._dati_utente, None, self._data_seduta, self._numero_seduta,
                gruppo["cat"], gruppo["stag"], self._giocatori, gruppo["soc"], self._societa_stampa, self._fasi, self._obiettivo_principale,
            )
            self._imposta_messaggio("Seduta duplicata.")
            self._ricarica_sedute()
        except Exception as e:
            self._imposta_errore(f"Impossibile duplicare la seduta: {e}")

    @pyqtSlot(str)
    def spostaSedutaCorrente(self, nuova_data):
        if self._id_seduta_corrente is None or not nuova_data.strip():
            return
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        data_iso = _it_a_iso(nuova_data)
        if data_iso is None:
            self._imposta_errore("Formato data non valido. Usa GG-MM-AAAA (es. 28-07-2026).")
            return
        try:
            DataManager.salva_seduta_strutturata(
                self._dati_utente, self._id_seduta_corrente, data_iso, self._numero_seduta,
                gruppo["cat"], gruppo["stag"], self._giocatori, gruppo["soc"], self._societa_stampa, self._fasi, self._obiettivo_principale,
            )
            # FIX (segnalato da Luca): spostare la data qui non toccava il
            # collegamento macrociclo - la cella restava agganciata al
            # VECCHIO giorno della settimana, mentre la Griglia Mensile di
            # Presenze colonna sul NUMERO del giorno letto dalla data della
            # seduta (non dal giorno della cella collegata, vedi
            # calcolaGrigliaMensile in presenze_vm.py): il risultato era una
            # seduta che compariva sotto la data nuova nella griglia ma
            # restava ancorata, per Macrociclo/Presenze-calendario, al
            # vecchio giorno - due viste in contraddizione sulla stessa
            # seduta, con la colonna del giorno "vero" vuota. Ci si scollega
            # dalla cella vecchia (se c'era) e si ritenta l'aggancio
            # automatico sulla cella giusta per la nuova data, stessa logica
            # best-effort gia' usata da nuovaSeduta.
            self._riallinea_collegamento_macrociclo(gruppo, data_iso)
            # Aggiornato qui in memoria (non tramite il reload sotto, che ora
            # non ricarica piu' da DB una seduta gia' aperta - vedi
            # _ricarica_sedute): altrimenti la data mostrata restava quella
            # vecchia nonostante il salvataggio fosse andato a buon fine.
            self._data_seduta = data_iso
            self.dettaglioCambiato.emit()
            self._imposta_messaggio(f"Seduta spostata al {nuova_data.strip()}.")
            self._imposta_errore("")
            self._ricarica_sedute(self._id_seduta_corrente)
        except Exception as e:
            self._imposta_errore(f"Impossibile spostare la seduta: {e}")

    @pyqtSlot()
    def eliminaTutteLeSeduteDelGruppo(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            return
        try:
            for s in list(self._sedute):
                DataManager.elimina_singola_seduta(self._dati_utente, s["id_seduta"])
            self._imposta_messaggio("Tutte le sedute del gruppo sono state eliminate.")
            self._indice_seduta = -1
            self._svuota_dettaglio()
            self._ricarica_sedute()
        except Exception as e:
            self._imposta_errore(f"Impossibile eliminare le sedute: {e}")

    @pyqtSlot(int)
    def apriLavagnaPerBlocco(self, indice):
        if 0 <= indice < len(self._fasi):
            self.richiestaAperturaLavagnaPerBlocco.emit(indice)

    @pyqtSlot()
    def aggiungiBlocco(self):
        self._fasi.append({
            "ordine_blocco": len(self._fasi) + 1, "nome_blocco": "", "fase": "", "durata_minuti": 10,
            "esercitazione": {"nome_esercizio": "", "mezzo_allenamento": "", "obiettivo_tecnico": "", "obiettivo_tattico": "", "descrizione": "", "immagine": ""},
        })
        self.dettaglioCambiato.emit()

    @pyqtSlot(int)
    def rimuoviBlocco(self, indice):
        if 0 <= indice < len(self._fasi):
            self._fasi.pop(indice)
            for i, f in enumerate(self._fasi):
                f["ordine_blocco"] = i + 1
            self.dettaglioCambiato.emit()

    @pyqtSlot(int)
    def spostaBloccoSu(self, indice):
        # Segnalato da Luca: prima non c'era modo di riordinare i blocchi
        # gia' aggiunti (es. inserire un blocco analitico prima di uno gia'
        # creato per la partitella) senza cancellare e ricreare tutto da
        # capo. Scambio con il precedente + rinumerazione di ordine_blocco,
        # stesso schema gia' usato da rimuoviBlocco per tenere la sequenza
        # coerente (persistita cosi' com'e' da salva_seduta_strutturata).
        if 0 < indice < len(self._fasi):
            self._fasi[indice - 1], self._fasi[indice] = self._fasi[indice], self._fasi[indice - 1]
            for i, f in enumerate(self._fasi):
                f["ordine_blocco"] = i + 1
            self.dettaglioCambiato.emit()

    @pyqtSlot(int)
    def spostaBloccoGiu(self, indice):
        if 0 <= indice < len(self._fasi) - 1:
            self._fasi[indice], self._fasi[indice + 1] = self._fasi[indice + 1], self._fasi[indice]
            for i, f in enumerate(self._fasi):
                f["ordine_blocco"] = i + 1
            self.dettaglioCambiato.emit()

    @pyqtSlot(int, str, str)
    def impostaCampoBlocco(self, indice, campo, valore):
        # FIX (loop di binding): un ComboBox editabile con editText legato a
        # una property live (vedi Sedute.qml, mezzo/tecnico/tattico) puo'
        # emettere onEditTextChanged anche alla sua STESSA creazione, quando
        # editText viene impostato la prima volta dal binding - non solo
        # quando l'utente digita davvero. Se qui riemettessimo sempre
        # dettaglioCambiato, il Repeater che genera quel ComboBox (model:
        # seduteVM.fasi) verrebbe ri-valutato MENTRE sta ancora creando i
        # propri delegate, cioe' esattamente un binding loop rilevato da Qt
        # (visto con lo smoke test: decine di warning non appena si aggiunge
        # un blocco). Riemettere il segnale solo se il valore e' davvero
        # cambiato spezza la reazione a catena alla radice.
        if not (0 <= indice < len(self._fasi)):
            return
        fase = self._fasi[indice]
        if campo == "nome_blocco":
            if fase["nome_blocco"] == valore:
                return
            fase["nome_blocco"] = valore
        elif campo == "durata_minuti":
            try:
                nuovo = int(valore)
            except ValueError:
                return
            if fase["durata_minuti"] == nuovo:
                return
            fase["durata_minuti"] = nuovo
        else:
            return
        self.dettaglioCambiato.emit()

    @pyqtSlot(int, str, bool)
    def impostaFaseBlocco(self, indice, codice, selezionato):
        if not (0 <= indice < len(self._fasi)) or codice not in FASI_BLOCCO_VALIDE:
            return
        fase = self._fasi[indice]
        attivi = set(f for f in (fase.get("fase") or "").split(",") if f)
        if selezionato:
            attivi.add(codice)
        else:
            attivi.discard(codice)
        nuovo_valore = ",".join(c for c in FASI_BLOCCO_VALIDE if c in attivi)
        if fase.get("fase", "") == nuovo_valore:
            return
        fase["fase"] = nuovo_valore
        self.dettaglioCambiato.emit()

    @pyqtSlot(int, str, str)
    def impostaCampoEsercitazione(self, indice, campo, valore):
        # FIX: stesso motivo di impostaCampoBlocco sopra.
        if not (0 <= indice < len(self._fasi)):
            return
        if campo not in ("nome_esercizio", "mezzo_allenamento", "obiettivo_tecnico", "obiettivo_tattico", "descrizione", "immagine"):
            return
        esercitazione = self._fasi[indice]["esercitazione"]
        # None-safe: .get(campo, "") non protegge da una chiave gia' presente
        # con valore None (dato legacy letto da colonna NULL) - vedi fix
        # gemello in data_manager.get_seduta_dettaglio.
        if (esercitazione.get(campo) or "") == valore:
            return
        esercitazione[campo] = valore
        self.dettaglioCambiato.emit()

    @pyqtSlot()
    def salvaSeduta(self):
        gruppo = self._gruppo_corrente()
        if not gruppo or self._id_seduta_corrente is None:
            return
        try:
            DataManager.salva_seduta_strutturata(
                self._dati_utente, self._id_seduta_corrente, self._data_seduta, self._numero_seduta,
                gruppo["cat"], gruppo["stag"], self._giocatori, gruppo["soc"], self._societa_stampa, self._fasi, self._obiettivo_principale,
            )
            self._imposta_messaggio("Seduta salvata.")
            self._imposta_errore("")
        except Exception as e:
            self._imposta_errore(f"Impossibile salvare: {e}")

    @pyqtSlot(result=str)
    def cartellaEsportazionePdfDefault(self):
        """Cartella da proporre come punto di partenza del selettore
        cartella di 'Esporta PDF': l'ultima usata con successo, se esiste
        ancora sul disco, altrimenti la cartella predefinita del programma -
        prima l'esportazione scriveva SEMPRE nella cartella fissa, senza
        possibilita' di scegliere ne' di ricordare l'ultima scelta."""
        valore = QSettings(ORGANIZZAZIONE, APPLICAZIONE).value(CHIAVE_CARTELLA_PDF, "")
        if valore and os.path.isdir(valore):
            return valore
        return DataManager.cartella_pdf_sedute()

    @pyqtSlot(str)
    def esportaPdfInCartella(self, cartella):
        if self._id_seduta_corrente is None or not cartella:
            return
        nome_file = f"Seduta {self._data_seduta} - {self._numero_seduta}.pdf".replace("/", "-")
        percorso = os.path.join(cartella, nome_file)
        try:
            ok, risultato = esporta_seduta_in_pdf(self._dati_utente, self._id_seduta_corrente, percorso, self._societa_stampa, self._obiettivo_principale)
            if ok:
                QSettings(ORGANIZZAZIONE, APPLICAZIONE).setValue(CHIAVE_CARTELLA_PDF, cartella)
                self._imposta_messaggio(f"PDF esportato in: {risultato}")
                self._imposta_errore("")
            else:
                self._imposta_errore(risultato)
        except Exception as e:
            self._imposta_errore(f"Impossibile esportare il PDF: {e}")

    def _categoria_menu_reale(self, categoria):
        # DataManager.aggiungi_voce_menu/rimuovi_voce_menu scrivono sempre
        # nella categoria letterale ricevuta: in modalita' Portieri le liste
        # sono lette da carica_liste_menu_gk sotto le categorie DISTINTE
        # "MezziGK"/"TecniciGK"/"TatticiGK" (vedi quel metodo), quindi va
        # applicata qui la stessa mappa gia' usata dal vecchio dialogo
        # "Personalizza Voci Menu" di interfaccia_seduta_gk.py, altrimenti una
        # voce aggiunta in modalita' Portieri finirebbe nella lista standard
        # e non comparirebbe mai nel menu da cui e' stata creata.
        if self._modalita_gk:
            return {"Mezzi": "MezziGK", "Tecnici": "TecniciGK", "Tattici": "TatticiGK"}[categoria]
        return categoria

    @pyqtSlot(str, str)
    def aggiungiVoceMenu(self, categoria, valore):
        if categoria not in ("Mezzi", "Tecnici", "Tattici") or not valore.strip():
            return
        try:
            DataManager.aggiungi_voce_menu(self._dati_utente, self._categoria_menu_reale(categoria), valore.strip())
            self._ricarica_menu()
        except Exception as e:
            self._imposta_errore(f"Impossibile aggiungere la voce: {e}")

    @pyqtSlot(str, str)
    def rimuoviVoceMenu(self, categoria, valore):
        if categoria not in ("Mezzi", "Tecnici", "Tattici"):
            return
        try:
            DataManager.rimuovi_voce_menu(self._dati_utente, self._categoria_menu_reale(categoria), valore)
            self._ricarica_menu()
        except Exception as e:
            self._imposta_errore(f"Impossibile rimuovere la voce: {e}")
