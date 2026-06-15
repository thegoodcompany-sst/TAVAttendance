package com.example.tavattendance.core

import com.example.tavattendance.data.models.StudentInsert

/**
 * Parses pasted CSV text into [StudentInsert] rows. Mirrors the iOS importer:
 * the first non-blank row is treated as a header and skipped; columns are
 * full_name, school, year_of_study. Handles quoted fields with embedded commas.
 */
object CsvStudentParser {
    data class Result(val rows: List<StudentInsert>, val warnings: List<String>)

    fun parse(raw: String): Result {
        val rows = mutableListOf<StudentInsert>()
        val warnings = mutableListOf<String>()
        val lines = raw.split("\n", "\r\n", "\r")
        lines.forEachIndexed { idx, line ->
            if (idx == 0 || line.isBlank()) return@forEachIndexed // skip header + blanks
            val cols = parseLine(line)
            val name = cols.getOrNull(0)?.trim().orEmpty()
            if (name.isEmpty()) {
                warnings.add("Row ${idx + 1}: empty name, skipped.")
                return@forEachIndexed
            }
            rows.add(
                StudentInsert(
                    fullName = name,
                    school = cols.getOrNull(1)?.trim()?.ifBlank { null },
                    yearOfStudy = cols.getOrNull(2)?.trim()?.ifBlank { null }
                )
            )
        }
        return Result(rows, warnings)
    }

    /** Minimal RFC-4180–aware line splitter: supports quoted fields and "" escaping. */
    private fun parseLine(line: String): List<String> {
        val out = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false
        var i = 0
        val chars = line.toCharArray()
        while (i < chars.size) {
            val c = chars[i]
            when {
                c == '"' && inQuotes && i + 1 < chars.size && chars[i + 1] == '"' -> {
                    current.append('"'); i++
                }
                c == '"' -> inQuotes = !inQuotes
                c == ',' && !inQuotes -> {
                    out.add(current.toString()); current.clear()
                }
                else -> current.append(c)
            }
            i++
        }
        out.add(current.toString())
        return out
    }
}
