package org.kazumi.tv

import android.content.Context
import org.kazumi.tv.rules.RuleImport
import org.kazumi.tv.rules.SourceRule
import java.io.File

/** Explicit test-only candidate; never imports or changes installed rules. */
internal object CandidateRuleFile {
    fun read(context: Context, relativePath: String, sourceName: String): SourceRule {
        val root = requireNotNull(context.getExternalFilesDir(null)) { "external files unavailable" }
        return read(root, relativePath, sourceName)
    }

    internal fun read(root: File, relativePath: String, sourceName: String): SourceRule {
        require(relativePath.isNotBlank() && relativePath.length <= 512) { "candidate path invalid" }
        require(!File(relativePath).isAbsolute && '\\' !in relativePath && ':' !in relativePath) { "candidate requires relative path" }
        require(relativePath.split('/').all { it.isNotEmpty() && it != "." && it != ".." }) { "candidate traversal rejected" }
        require(sourceName.isNotBlank() && sourceName.none { it == '/' || it == '\\' || it == ':' || it.isISOControl() }) { "candidate source invalid" }
        val directory = root.canonicalFile
        val file = File(directory, relativePath).canonicalFile
        require(file.path.startsWith(directory.path + File.separator)) { "candidate outside external files" }
        require(file.isFile && file.length() in 1..(RuleImport.MAX_CHARS.toLong() * 4)) { "candidate file missing or oversized" }
        val raw = file.bufferedReader(Charsets.UTF_8).use { reader ->
            val chars = CharArray(RuleImport.MAX_CHARS + 1)
            var used = 0
            while (used < chars.size) {
                val count = reader.read(chars, used, chars.size - used)
                if (count < 0) break
                used += count
            }
            require(used <= RuleImport.MAX_CHARS) { "candidate exceeds character limit" }
            String(chars, 0, used)
        }
        val report = RuleImport.parse(raw)
        require(report.failures.isEmpty() && report.duplicates == 0 && report.rules.size == 1) { "candidate must contain exactly one valid rule" }
        return report.rules.single().also {
            require(it.name == sourceName) { "candidate source mismatch" }
            it.validateImport()
        }
    }
}
