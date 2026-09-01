"""ViewModel Statistiche: per il gruppo selezionato, quattro viste di analisi
(Presenze Allenamenti, Convocazioni Partite, Risultati e Goal, Obiettivi e
Mezzi Allenamento), un filtro per periodo (default: l'intera stagione) e uno
per tipo di impegno (Campionato/Test/Torneo), ordinamento per vista ed
esportazione PDF - stessa copertura funzionale del vecchio
interfaccia_statistiche.py, con due semplificazioni deliberate:

1. Le distribuzioni sono barre orizzontali (component FMBarraStat), non
   grafici a torta/istogrammi matplotlib: il resto di questa ricostruzione
   evita gia' quella dipendenza (vedi il vecchio docstring di questo stesso
   file), e la scelta resta coerente qui.
2. Il PDF esporta sempre tutte e 4 le viste in un unico file (niente dialogo
   di selezione pagine): la selezione granulare del vecchio
   DialogSelezioneExport non e' stata ricostruita, ma il contenuto
   informativo del report e' lo stesso.

Risultati e Goal legge i dati "Board Partita" (macrociclo.nota_<gg>, JSON)
con la STESSA identica logica del vecchio widget: vittorie/pareggi/sconfitte
dal campo risultato (invertito se la partita era in trasferta), goal e
partite giocate per giocatore, sommando anche le sotto-partite di un torneo.
"""

import json
import os
from collections import defaultdict

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from data_manager import DataManager

GIORNI = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]
TIPI_IMPEGNO_PARTITA = ["C", "TM", "TA"]
MAPPA_VECCHI_STATI = {"Presente": "P", "Assente": "A", "Infortunato": "A", "Malato": "A", "P": "P", "A": "A", "C": "C", "NC": "NC"}

ORDINAMENTI_PER_VISTA = {
    0: ["Alfabetico (A-Z)", "Più Presenze", "Più Assenze"],
    1: ["Alfabetico (A-Z)", "Più Convocazioni", "Più Non Convocazioni"],
    2: ["Alfabetico (A-Z)", "+ Goal Fatti", "- Goal Fatti", "+ Media Goal/Partita", "- Media Goal/Partita"],
    3: [],
}


def _esito_partita(risultato, luogo="C"):
    """Ritorna 'V'/'P'/'S' dal campo risultato ("2-1"/"2:1"), invertendo i
    gol se la partita era in trasferta - stessa logica del vecchio widget."""
    sep = "-" if "-" in risultato else (":" if ":" in risultato else None)
    if not sep:
        return None
    parti = risultato.split(sep)
    if len(parti) != 2 or not parti[0].strip().isdigit() or not parti[1].strip().isdigit():
        return None
    nostri, avversari = int(parti[0]), int(parti[1])
    if luogo == "T":
        nostri, avversari = avversari, nostri
    if nostri > avversari:
        return "V"
    if nostri < avversari:
        return "S"
    return "P"


class StatisticheVM(QObject):
    gruppiCambiati = pyqtSignal()
    gruppoSelezionatoCambiato = pyqtSignal()
    statisticheCambiate = pyqtSignal()
    filtriCambiati = pyqtSignal()
    erroreCambiato = pyqtSignal()
    messaggioCambiato = pyqtSignal()

    def __init__(self, dati_utente, parent=None):
        super().__init__(parent)
        self._dati_utente = dati_utente
        self._gruppi = []
        self._indice_gruppo = -1
        self._data_inizio = ""
        self._data_fine = ""
        self._tipi_selezionati = list(TIPI_IMPEGNO_PARTITA)
        self._vista_corrente = 0
        self._ordinamento_corrente = "Alfabetico (A-Z)"
        self._presenze_per_giocatore = []
        self._convocazioni_per_giocatore = []
        self._goal_per_giocatore = []
        self._vittorie = 0
        self._pareggi = 0
        self._sconfitte = 0
        self._minuti_per_mezzo = []
        self._minuti_per_tecnico = []
        self._minuti_per_tattico = []
        self._numero_sedute = 0
        self._errore = ""
        self._messaggio = ""
        self.ricaricaGruppi()

    def _etichetta_gruppo(self, g):
        base = f"{g['cat']} — {g['stag']}"
        return f"{g['soc']} · {base}" if g.get("soc") else base

    def _imposta_errore(self, testo):
        self._errore = testo
        self.erroreCambiato.emit()

    def _imposta_messaggio(self, testo):
        self._messaggio = testo
        self.messaggioCambiato.emit()

    @pyqtProperty("QVariantList", notify=gruppiCambiati)
    def gruppi(self):
        return [{"label": self._etichetta_gruppo(g)} for g in self._gruppi]

    @pyqtProperty(int, notify=gruppoSelezionatoCambiato)
    def indiceGruppo(self):
        return self._indice_gruppo

    @pyqtProperty(int, notify=statisticheCambiate)
    def numeroSedute(self):
        return self._numero_sedute

    @pyqtProperty(str, notify=filtriCambiati)
    def dataInizio(self):
        return self._data_inizio

    @pyqtProperty(str, notify=filtriCambiati)
    def dataFine(self):
        return self._data_fine

    @pyqtProperty("QVariantList", notify=filtriCambiati)
    def tipiSelezionati(self):
        return self._tipi_selezionati

    @pyqtProperty(int, notify=filtriCambiati)
    def vistaCorrente(self):
        return self._vista_corrente

    @pyqtProperty(str, notify=filtriCambiati)
    def ordinamentoCorrente(self):
        return self._ordinamento_corrente

    @pyqtProperty("QVariantList", notify=filtriCambiati)
    def opzioniOrdinamento(self):
        return ORDINAMENTI_PER_VISTA.get(self._vista_corrente, [])

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def presenzePerGiocatore(self):
        return self._presenze_per_giocatore

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def convocazioniPerGiocatore(self):
        return self._convocazioni_per_giocatore

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def goalPerGiocatore(self):
        return self._goal_per_giocatore

    @pyqtProperty(int, notify=statisticheCambiate)
    def vittorie(self):
        return self._vittorie

    @pyqtProperty(int, notify=statisticheCambiate)
    def pareggi(self):
        return self._pareggi

    @pyqtProperty(int, notify=statisticheCambiate)
    def sconfitte(self):
        return self._sconfitte

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def minutiPerMezzo(self):
        return self._minuti_per_mezzo

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def minutiPerTecnico(self):
        return self._minuti_per_tecnico

    @pyqtProperty("QVariantList", notify=statisticheCambiate)
    def minutiPerTattico(self):
        return self._minuti_per_tattico

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
                        self._ricalcola()
                else:
                    # FIX: l'indice non e' cambiato, ma i dati dietro
                    # potrebbero essere completamente diversi (es. gruppo
                    # eliminato e ricreato identico altrove, stessa
                    # categoria/stagione/societa' quindi stessa posizione in
                    # elenco): ricarica SEMPRE i dipendenti quando
                    # gruppiCambiati scatta, non solo se l'indice si sposta -
                    # altrimenti le statistiche restavano quelle del gruppo
                    # vecchio, gia' cancellato (bug segnalato).
                    self.selezionaGruppo(nuovo_indice)
            elif gruppi and self._indice_gruppo == -1:
                self.selezionaGruppo(0)
        except Exception as e:
            self._imposta_errore(f"Impossibile caricare i gruppi: {e}")

    def _gruppo_corrente(self):
        if 0 <= self._indice_gruppo < len(self._gruppi):
            return self._gruppi[self._indice_gruppo]
        return None

    def _periodo_default(self, stagione):
        try:
            anno_inizio, anno_fine = stagione.split("/")
            return f"{anno_inizio}-07-01", f"{anno_fine}-06-30"
        except (ValueError, AttributeError):
            return "", ""

    @pyqtSlot()
    def aggiorna(self):
        """Ricalcola le statistiche del gruppo corrente. La schermata
        Statistiche non ricalcolava piu' nulla dopo la selezione iniziale del
        gruppo: le sedute/presenze/board-partita create o modificate altrove
        (Sedute, Presenze, Macrociclo) restavano invisibili qui finche' non
        si cambiava manualmente periodo/tipo/gruppo. Va richiamato da
        Component.onCompleted della schermata, che viene ricreata da zero
        (stack.replace) ogni volta che la si apre."""
        self._ricalcola()

    @pyqtSlot(int)
    def selezionaGruppo(self, indice):
        if indice < 0 or indice >= len(self._gruppi):
            return
        self._indice_gruppo = indice
        self.gruppoSelezionatoCambiato.emit()
        gruppo = self._gruppi[indice]
        self._data_inizio, self._data_fine = self._periodo_default(gruppo["stag"])
        self._tipi_selezionati = list(TIPI_IMPEGNO_PARTITA)
        self._vista_corrente = 0
        self._ordinamento_corrente = "Alfabetico (A-Z)"
        self.filtriCambiati.emit()
        self._ricalcola()

    @pyqtSlot(str, str)
    def impostaPeriodo(self, data_inizio, data_fine):
        self._data_inizio = data_inizio
        self._data_fine = data_fine
        self.filtriCambiati.emit()
        self._ricalcola()

    @pyqtSlot(str, bool)
    def impostaTipoSelezionato(self, tipo, selezionato):
        if tipo not in TIPI_IMPEGNO_PARTITA:
            return
        attivi = set(self._tipi_selezionati)
        if selezionato:
            attivi.add(tipo)
        else:
            attivi.discard(tipo)
        self._tipi_selezionati = [t for t in TIPI_IMPEGNO_PARTITA if t in attivi]
        self.filtriCambiati.emit()
        self._ricalcola()

    @pyqtSlot(int)
    def selezionaVista(self, indice):
        if indice < 0 or indice > 3:
            return
        self._vista_corrente = indice
        self._ordinamento_corrente = "Alfabetico (A-Z)"
        self.filtriCambiati.emit()
        self._applica_ordinamento()

    @pyqtSlot(str)
    def impostaOrdinamento(self, ordinamento):
        self._ordinamento_corrente = ordinamento
        self.filtriCambiati.emit()
        self._applica_ordinamento()

    def _applica_ordinamento(self):
        # Riordina solo le liste gia' calcolate (nessuna nuova query):
        # cambiare vista/ordinamento non deve rifare i conti da capo.
        vista, ordinamento = self._vista_corrente, self._ordinamento_corrente
        if vista == 0:
            if ordinamento == "Più Presenze":
                self._presenze_per_giocatore.sort(key=lambda r: (-r["presenze"], r["nome"]))
            elif ordinamento == "Più Assenze":
                self._presenze_per_giocatore.sort(key=lambda r: (-r["assenze"], r["nome"]))
            else:
                self._presenze_per_giocatore.sort(key=lambda r: r["nome"])
        elif vista == 1:
            if ordinamento == "Più Convocazioni":
                self._convocazioni_per_giocatore.sort(key=lambda r: (-r["convocazioni"], r["nome"]))
            elif ordinamento == "Più Non Convocazioni":
                self._convocazioni_per_giocatore.sort(key=lambda r: (-r["nonConvocazioni"], r["nome"]))
            else:
                self._convocazioni_per_giocatore.sort(key=lambda r: r["nome"])
        elif vista == 2:
            if ordinamento == "+ Goal Fatti":
                self._goal_per_giocatore.sort(key=lambda r: (-r["goal"], r["nome"]))
            elif ordinamento == "- Goal Fatti":
                self._goal_per_giocatore.sort(key=lambda r: (r["goal"], r["nome"]))
            elif ordinamento == "+ Media Goal/Partita":
                self._goal_per_giocatore.sort(key=lambda r: (-r["mediaGoal"], r["nome"]))
            elif ordinamento == "- Media Goal/Partita":
                self._goal_per_giocatore.sort(key=lambda r: (r["mediaGoal"], r["nome"]))
            else:
                self._goal_per_giocatore.sort(key=lambda r: r["nome"])
        self.statisticheCambiate.emit()

    def _righe_distribuzione(self, conteggio):
        max_v = max(conteggio.values()) if conteggio else 1
        righe = [
            {"nome": chiave, "valore": v, "percentuale": round(100 * v / max(max_v, 1))}
            for chiave, v in conteggio.items()
        ]
        righe.sort(key=lambda r: -r["valore"])
        return righe

    def _ricalcola(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._presenze_per_giocatore = []
            self._convocazioni_per_giocatore = []
            self._goal_per_giocatore = []
            self._vittorie = self._pareggi = self._sconfitte = 0
            self._minuti_per_mezzo = self._minuti_per_tecnico = self._minuti_per_tattico = []
            self._numero_sedute = 0
            self.statisticheCambiate.emit()
            return
        try:
            cat, stag, soc = gruppo["cat"], gruppo["stag"], gruppo["soc"]
            d_in, d_fi = self._data_inizio, self._data_fine

            # includi_eliminati=True: un giocatore eliminato durante la
            # stagione resta nelle statistiche con i suoi dati storici
            # (presenze/convocazioni/goal registrati mentre era in squadra).
            giocatori_db = DataManager.get_giocatori(self._dati_utente, cat, stag, soc, includi_eliminati=True)
            sedute_tutte = DataManager.get_sedute_lista_completa(self._dati_utente, cat, stag, soc)
            sedute_nel_periodo = {s["id_seduta"] for s in sedute_tutte if d_in <= (s.get("data_seduta") or "") <= d_fi}

            righe_macrociclo = DataManager.get_macrociclo(self._dati_utente, cat, stag, soc)
            sedute_attive = {}  # {id_seduta: tipo}
            note_per_seduta = {}
            for riga in righe_macrociclo:
                for gg in GIORNI:
                    id_s = riga.get(f"id_seduta_{gg}")
                    tipo = (riga.get(gg) or "").strip()
                    if id_s and id_s in sedute_nel_periodo and tipo in ("A", "C", "TM", "TA"):
                        sedute_attive[id_s] = tipo
                        nota = riga.get(f"nota_{gg}")
                        if nota and "{" in nota:
                            note_per_seduta[id_s] = nota

            # FIX: una seduta creata direttamente in Sedute e mai collegata a
            # una cella Macrociclo restava invisibile qui - mezzo/obiettivi
            # dei suoi blocchi non comparivano mai nelle statistiche
            # (segnalato da Luca, un mezzo personalizzato appena aggiunto
            # risultava sempre assente). Non collegata = Allenamento per
            # definizione, stesso principio gia' usato da SeduteVM per
            # escludere le sedute-ancoraggio delle Partite dal proprio elenco.
            for id_s in sedute_nel_periodo:
                if id_s not in sedute_attive:
                    sedute_attive[id_s] = "A"

            id_sedute_valide = list(sedute_attive.keys())
            self._numero_sedute = len(id_sedute_valide)

            stat_g = {
                g["id_giocatore"]: {"nome": f"{g['cognome']} {g['nome']}", "attivo": g["attivo"], "P": 0, "A": 0, "C": 0, "NC": 0, "goal": 0, "partite_giocate": 0}
                for g in giocatori_db
            }
            if id_sedute_valide:
                for id_g, id_s, stato in DataManager.get_presenze_multi_sedute(self._dati_utente, id_sedute_valide):
                    if id_g not in stat_g:
                        continue
                    tipo_s = sedute_attive.get(id_s, "")
                    stato_pulito = MAPPA_VECCHI_STATI.get(stato, stato)
                    if tipo_s == "A" and stato_pulito in ("P", "A"):
                        stat_g[id_g][stato_pulito] += 1
                    elif tipo_s in TIPI_IMPEGNO_PARTITA and tipo_s in self._tipi_selezionati and stato_pulito in ("C", "NC"):
                        stat_g[id_g][stato_pulito] += 1

            vittorie = pareggi = sconfitte = 0
            for id_s, tipo in sedute_attive.items():
                if tipo not in TIPI_IMPEGNO_PARTITA or tipo not in self._tipi_selezionati:
                    continue
                nota_json = note_per_seduta.get(id_s)
                if not nota_json:
                    continue
                try:
                    board = json.loads(nota_json)
                except (ValueError, TypeError):
                    continue
                if not board:
                    continue

                if board.get("tipo") in ("C", "TM"):
                    esito = _esito_partita(board.get("risultato", ""), board.get("luogo", "C"))
                    if esito == "V":
                        vittorie += 1
                    elif esito == "P":
                        pareggi += 1
                    elif esito == "S":
                        sconfitte += 1
                    for str_id, dati_g in board.get("giocatori", {}).items():
                        id_g = int(str_id) if str_id.isdigit() else None
                        if id_g in stat_g:
                            stat_g[id_g]["goal"] += dati_g.get("goal", 0) or 0
                            stat_g[id_g]["partite_giocate"] += 1
                elif board.get("tipo") == "TA":
                    for partita in board.get("partite", []):
                        esito = _esito_partita(partita.get("risultato", ""))
                        if esito == "V":
                            vittorie += 1
                        elif esito == "P":
                            pareggi += 1
                        elif esito == "S":
                            sconfitte += 1
                    for str_id, dati_g in board.get("giocatori", {}).items():
                        id_g = int(str_id) if str_id.isdigit() else None
                        if id_g in stat_g:
                            goal_lista = dati_g.get("goal", []) or []
                            stat_g[id_g]["goal"] += sum(goal_lista)
                            stat_g[id_g]["partite_giocate"] += 1

            self._vittorie, self._pareggi, self._sconfitte = vittorie, pareggi, sconfitte

            self._presenze_per_giocatore = [
                {"nome": v["nome"], "attivo": v["attivo"], "presenze": v["P"], "assenze": v["A"], "percentuale": round(100 * v["P"] / max(v["P"] + v["A"], 1)) if (v["P"] + v["A"]) > 0 else -1}
                for v in stat_g.values()
            ]
            self._convocazioni_per_giocatore = [
                {"nome": v["nome"], "attivo": v["attivo"], "convocazioni": v["C"], "nonConvocazioni": v["NC"], "percentuale": round(100 * v["C"] / max(v["C"] + v["NC"], 1)) if (v["C"] + v["NC"]) > 0 else -1}
                for v in stat_g.values()
            ]
            max_goal = max((v["goal"] for v in stat_g.values()), default=0) or 1
            self._goal_per_giocatore = [
                {
                    "nome": v["nome"], "attivo": v["attivo"], "goal": v["goal"], "partiteGiocate": v["partite_giocate"],
                    "mediaGoal": round(v["goal"] / v["partite_giocate"], 2) if v["partite_giocate"] > 0 else 0.0,
                    "percentualeGoal": round(100 * v["goal"] / max_goal),
                }
                for v in stat_g.values()
            ]
            max_media = max((r["mediaGoal"] for r in self._goal_per_giocatore), default=0) or 1
            for r in self._goal_per_giocatore:
                r["percentualeMedia"] = round(100 * r["mediaGoal"] / max_media)

            distribuzione_mezzi, distribuzione_tecnici, distribuzione_tattici = defaultdict(int), defaultdict(int), defaultdict(int)
            if id_sedute_valide:
                for blocco in DataManager.get_dati_allenamento_periodo(self._dati_utente, id_sedute_valide):
                    durata = blocco.get("durata_minuti") or 0
                    if blocco.get("mezzo_allenamento"):
                        distribuzione_mezzi[blocco["mezzo_allenamento"]] += durata
                    # "Nessuno" e' una voce standard della tendina Obiettivo
                    # tecnico/tattico (nessun obiettivo specifico per quel
                    # blocco), non un vero obiettivo: contarla qui la faceva
                    # comparire tra le statistiche come se lo fosse
                    # (segnalato da Luca).
                    if blocco.get("obiettivo_tecnico") and blocco["obiettivo_tecnico"] != "Nessuno":
                        distribuzione_tecnici[blocco["obiettivo_tecnico"]] += durata
                    if blocco.get("obiettivo_tattico") and blocco["obiettivo_tattico"] != "Nessuno":
                        distribuzione_tattici[blocco["obiettivo_tattico"]] += durata
            self._minuti_per_mezzo = self._righe_distribuzione(distribuzione_mezzi)
            self._minuti_per_tecnico = self._righe_distribuzione(distribuzione_tecnici)
            self._minuti_per_tattico = self._righe_distribuzione(distribuzione_tattici)

            self._applica_ordinamento()
            self.statisticheCambiate.emit()
        except Exception as e:
            self._imposta_errore(f"Impossibile calcolare le statistiche: {e}")

    @pyqtSlot()
    def esportaReportPdf(self):
        gruppo = self._gruppo_corrente()
        if not gruppo:
            self._imposta_errore("Seleziona prima un gruppo.")
            return
        try:
            from statistiche_pdf import esporta_statistiche_in_pdf

            cartella = DataManager.cartella_report_presenze()
            nome_file = f"Statistiche_{gruppo['cat']}_{self._data_inizio}_{self._data_fine}.pdf".replace("/", "-")
            percorso = os.path.join(cartella, nome_file)
            esporta_statistiche_in_pdf(self, gruppo, percorso)
            self._imposta_messaggio(f"Report PDF esportato in: {percorso}")
            self._imposta_errore("")
        except Exception as e:
            self._imposta_errore(f"Impossibile esportare il report PDF: {e}")
