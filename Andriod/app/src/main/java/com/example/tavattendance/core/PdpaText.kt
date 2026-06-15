package com.example.tavattendance.core

/**
 * Client-side helpers for PDPA free-text hygiene.
 *
 * Mirrors the server-side guard in `011_pdpa_compliance.sql` (`reject_nric_in_notes`):
 *   `\m[STFGM][0-9]{7}[A-Z]\M`
 * so the UI can warn the admin *before* the DB rejects the write. The DB remains the
 * source of truth — this is advisory only.
 */
object PdpaText {
    // \m / \M are Postgres word boundaries; \b is the Java/Kotlin equivalent.
    private val NRIC_REGEX = Regex("""\b[STFGMstfgm][0-9]{7}[A-Za-z]\b""")

    const val NRIC_WARNING =
        "Do not enter NRIC/FIN or other national identifiers. Storing them breaches PDPA purpose limitation."

    /** True if the text appears to contain an NRIC/FIN. */
    fun containsNric(text: String?): Boolean =
        !text.isNullOrBlank() && NRIC_REGEX.containsMatchIn(text)
}
