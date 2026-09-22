package org.kazumi.tv

import android.app.Instrumentation
import android.os.Bundle
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** Production parser and file boundaries only; no network, UI, or RuleStore writes. */
object CandidateRuleRegression {
    fun run(test: Instrumentation, args: Bundle): String {
        val path = requireNotNull(args.getString("candidateFile")) { "candidateFile required" }
        val name = requireNotNull(args.getString("source")) { "source required" }
        val rule = CandidateRuleFile.read(test.targetContext, path, name)
        val root = requireNotNull(test.targetContext.getExternalFilesDir(null))
        val temporary = File(root, "candidate-boundary-${System.nanoTime()}")
        check(temporary.mkdir())
        var rejected = 0
        fun reject(block: () -> Unit) {
            check(runCatching(block).isFailure) { "candidate boundary accepted invalid input" }
            rejected++
        }
        val fixture = File(temporary, "rule.json")
        try {
            fixture.writeText(rule.json.toString())
            check(CandidateRuleFile.read(temporary, "rule.json", name).name == name)
            reject { CandidateRuleFile.read(temporary, "rule.json", "$name-mismatch") }
            reject { CandidateRuleFile.read(temporary, fixture.absolutePath, name) }
            reject { CandidateRuleFile.read(temporary, "../rule.json", name) }
            reject { CandidateRuleFile.read(temporary, "nested/../../rule.json", name) }
            reject { CandidateRuleFile.read(temporary, "nested\\rule.json", name) }
            reject { CandidateRuleFile.read(temporary, "missing.json", name) }
            fixture.writeText("{}")
            reject { CandidateRuleFile.read(temporary, "rule.json", name) }
            val second = JSONObject(rule.json.toString()).put("name", "$name-second")
            fixture.writeText(JSONArray().put(rule.json).put(second).toString())
            reject { CandidateRuleFile.read(temporary, "rule.json", name) }
            fixture.writeText(JSONArray().put(rule.json).put(rule.json).toString())
            reject { CandidateRuleFile.read(temporary, "rule.json", name) }
        } finally {
            fixture.delete()
            temporary.delete()
        }
        return "candidate_rule_structure=PASS production_parser=true path_boundaries=$rejected imported=false network=false playback_unverified=true"
    }
}
