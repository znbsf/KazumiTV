package org.kazumi.tv

import android.app.Instrumentation
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Durable user-data guard for host-driven tests that deliberately kill the app process.
 * Test APK only. Never emits preference values, and never overwrites an existing checkpoint.
 */
object UserDataCheckpoint {
    private val names = listOf("tv_settings", "tv_library", "search_history")
    fun run(test: Instrumentation, mode: String, label: String): String {
        require(label.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        val context = test.targetContext
        if (mode == "user-data-restore-watch") {
            require(label.matches(Regex("real-watch-[0-9]+")))
            val folder = File(context.getExternalFilesDir(null), label)
            val watchNames = listOf("tv_settings", "tv_library")
            val snapshots = watchNames.associateWith { decode(JSONObject(File(folder, "$it.backup.json").readText())) }
            watchNames.forEach { restore(context.getSharedPreferences(it, 0), snapshots.getValue(it)) }
            check(watchNames.all { context.getSharedPreferences(it, 0).all == snapshots.getValue(it) })
            File(folder, "cancelled-restored.txt").writeText("CANCELLED_BY_USER\nactual_settings_and_library_restored=true\n")
            return "watch_cancelled_user_data_restored_and_equal stores=2"
        }
        val file = File(context.filesDir, "acceptance-checkpoint-$label.json")
        val stores = names.associateWith { context.getSharedPreferences(it, 0) }
        if (mode == "user-data-backup") {
            check(!file.exists()) { "Checkpoint already exists; choose another label" }
            val data = JSONObject()
            stores.forEach { (name, prefs) -> data.put(name, encode(prefs.all)) }
            val staging = File(file.path + ".tmp")
            staging.outputStream().use { it.write(data.toString().toByteArray(Charsets.UTF_8)); it.fd.sync() }
            check(staging.renameTo(file))
            check(stores.all { (name, prefs) -> decode(JSONObject(file.readText()).getJSONObject(name)) == prefs.all })
            return "user_data_checkpoint_saved stores=${names.size} label=$label"
        }
        require(mode == "user-data-restore")
        val data = JSONObject(file.readText())
        // Decode every store before making any writes; malformed checkpoints remain untouched.
        val decoded = names.associateWith { decode(data.getJSONObject(it)) }
        stores.forEach { (name, prefs) -> restore(prefs, decoded.getValue(name)) }
        check(stores.all { (name, prefs) -> prefs.all == decoded.getValue(name) })
        return "user_data_checkpoint_restored_and_equal stores=${names.size} label=$label"
    }
    private fun encode(values: Map<String, *>): JSONObject = JSONObject().apply {
        values.forEach { (key, value) ->
            val type = when (value) {
                is String -> "string"; is Boolean -> "boolean"; is Int -> "int"
                is Long -> "long"; is Float -> "float"; is Set<*> -> "set"
                else -> error("Unsupported preference type")
            }
            put(key, JSONObject().put("type", type).put("value", if (value is Set<*>) JSONArray(value.toList()) else value))
        }
    }
    private fun decode(data: JSONObject): Map<String, Any> = data.keys().asSequence().associateWith { key ->
        val row = data.getJSONObject(key)
        when (row.getString("type")) {
            "string" -> row.getString("value"); "boolean" -> row.getBoolean("value")
            "int" -> row.getInt("value"); "long" -> row.getLong("value"); "float" -> row.getDouble("value").toFloat()
            "set" -> row.getJSONArray("value").let { values -> (0 until values.length()).map { values.getString(it) }.toSet() }
            else -> error("Unsupported checkpoint type")
        }
    }
    private fun restore(prefs: SharedPreferences, values: Map<String, Any>) {
        val edit = prefs.edit().clear()
        values.forEach { (key, value) -> when (value) {
            is String -> edit.putString(key, value); is Boolean -> edit.putBoolean(key, value)
            is Int -> edit.putInt(key, value); is Long -> edit.putLong(key, value); is Float -> edit.putFloat(key, value)
            is Set<*> -> { @Suppress("UNCHECKED_CAST") edit.putStringSet(key, value as Set<String>) }
        } }
        check(edit.commit()) { "Checkpoint restoration failed" }
    }
}
