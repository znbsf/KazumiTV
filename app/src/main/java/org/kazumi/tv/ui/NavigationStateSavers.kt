package org.kazumi.tv.ui

import androidx.compose.runtime.saveable.Saver
import org.json.JSONArray
import org.json.JSONObject
import org.kazumi.tv.data.*

/** Only framework String values cross the saved-state Parcel boundary on old Android. */
object NavigationStateSavers {
    val subject = Saver<Subject?, String>(
        save = { it?.let { value -> LibraryCodec.subjectJson(value).toString() } ?: "" },
        restore = { if(it.isEmpty())null else runCatching { LibraryCodec.subject(JSONObject(it)) }.getOrNull() }
    )
    val history = Saver<HistoryEntry?, String>(
        save = { it?.let { value -> LibraryCodec.historyJson(value).toString() } ?: "" },
        restore = { if(it.isEmpty())null else runCatching { LibraryCodec.history(JSONObject(it)) }.getOrNull() }
    )
    val subjects = Saver<ArrayList<Subject>, String>(
        save = { LibraryCodec.write(it.map(LibraryCodec::subjectJson)) },
        restore = { raw -> LibraryCodec.read(raw,LibraryCodec::subject).records.takeIf { it.isNotEmpty() }?.let { ArrayList(it) } }
    )
    private fun creditJson(value: CreditEntry): JSONObject = JSONObject()
        .put("id",value.id).put("name",value.name).put("images",JSONObject().put("large",value.image))
        .put("relation",value.job).put("eps",value.episodes).put("summary",value.summary)
        .put("character",value.character).put("actors",JSONArray(value.actors.map(::creditJson)))
    val credits = Saver<ArrayList<CreditEntry>, String>(
        save = { JSONArray(it.map(::creditJson)).toString() },
        restore = { raw -> runCatching {
            val array=JSONArray(raw)
            ArrayList((0 until array.length()).map { index ->
                val row=array.getJSONObject(index)
                CreditCodec.entry(row,row.optBoolean("character"))
            })
        }.getOrNull() }
    )
}
