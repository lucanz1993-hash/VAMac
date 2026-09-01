pragma Singleton
import QtQuick

/*
 * Design system centralizzato, ispirato a Football Manager: sidebar scura,
 * card con intestazione oro/ambra, azioni primarie blu-viola, verde/rosso
 * riservati agli indicatori di stato (mai come colore di brand).
 *
 * "colors" non e' piu' un blocco di readonly property letterali: e' un
 * binding verso ThemeManager.activePalette (Python). Ogni file che scrive
 * "Theme.colors.X" si aggiorna da solo quando l'utente cambia skin, senza
 * dover essere riscritto — lo swap di tema e' quindi "gratis" per ogni nuovo
 * componente scritto da qui in avanti, esattamente come cambiare
 * elevationTokens in base a una property fa gia' in questo stesso progetto.
 */
QtObject {
    id: theme

    readonly property var _p: ThemeManager.activePalette

    readonly property QtObject colors: QtObject {
        readonly property color bgMain: theme._p.bgMain
        readonly property color bgSurface: theme._p.bgSurface
        readonly property color bgSurface2: theme._p.bgSurface2
        readonly property color bgSurface3: theme._p.bgSurface3

        readonly property color accent: theme._p.accent
        readonly property color accentHover: theme._p.accentHover
        readonly property color accentPressed: theme._p.accentPressed
        readonly property color accentSoft: theme._p.accentSoft

        readonly property color primario: theme._p.primario
        readonly property color primarioHover: theme._p.primarioHover
        readonly property color primarioPressed: theme._p.primarioPressed

        // Quarta tinta (viola), distinta da oro (accent/Campionato) e blu
        // (primario/Test Match): serve a Torneo Amichevole in Macrociclo,
        // che con "warning" (giallo-oro) risultava troppo simile a
        // Campionato - identica in Alto Contrasto (#ffd400 == #ffd400).
        readonly property color terziario: theme._p.terziario

        readonly property color textPrimary: theme._p.textPrimary
        readonly property color textSecondary: theme._p.textSecondary
        readonly property color textTertiary: theme._p.textTertiary

        readonly property color border: theme._p.border
        readonly property color borderStrong: theme._p.borderStrong

        readonly property color positive: theme._p.positive
        readonly property color negative: theme._p.negative
        readonly property color negativeHover: theme._p.negativeHover
        readonly property color neutral: theme._p.neutral

        readonly property color success: theme._p.success
        readonly property color successHover: theme._p.successHover
        readonly property color danger: theme._p.danger
        readonly property color dangerHover: theme._p.dangerHover
        readonly property color warning: theme._p.warning
        readonly property color warningHover: theme._p.warningHover
    }

    // --- Tipografia, motion, elevazione, spaziatura, raggi: condivisi da
    // tutte le skin (le skin FM cambiano colore, non geometria).
    readonly property QtObject typography: QtObject {
        readonly property string family: "Segoe UI"
        readonly property int display: 32
        readonly property int title: 20
        readonly property int subtitle: 15
        readonly property int body: 13
        readonly property int small: 12
        readonly property int caption: 11
    }

    readonly property QtObject motion: QtObject {
        readonly property int micro: 90
        readonly property int transition: 220
        readonly property int reveal: 350
        readonly property int easeStandard: Easing.OutCubic
        readonly property int easeEmphasized: Easing.OutBack
        readonly property int easeLinear: Easing.Linear
    }

    readonly property QtObject elevation: QtObject {
        readonly property QtObject level1: QtObject {
            readonly property int blurRadius: 18
            readonly property int offsetY: 3
            readonly property real opacity: 0.35
        }
        readonly property QtObject level2: QtObject {
            readonly property int blurRadius: 28
            readonly property int offsetY: 6
            readonly property real opacity: 0.45
        }
    }

    readonly property QtObject spacing: QtObject {
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32
    }

    readonly property QtObject radius: QtObject {
        readonly property int sm: 4
        readonly property int md: 6
        readonly property int lg: 8
    }
}
