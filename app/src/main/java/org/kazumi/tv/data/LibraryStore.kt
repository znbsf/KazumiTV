package org.kazumi.tv.data

import android.content.Context
import org.json.JSONObject

/** Versioned writes retain a pre-migration snapshot and quarantine damaged data before replacing it. */
class LibraryStore(context: Context) {
    private val settings=TvPreferences(context)
    private val preferences = context.getSharedPreferences("tv_library", Context.MODE_PRIVATE)
    companion object { private val lock = Any() }
    private fun <T> read(name: String, decode: (JSONObject) -> T): List<T> {
        val raw = preferences.getString(name, "[]") ?: "[]"
        val parsed = LibraryCodec.read(raw, decode)
        if (parsed.damagedContainer || parsed.rejected > 0) {
            val editor = preferences.edit().putString("warning", "部分本地记录损坏，已保留原始副本；可用记录仍可读取。")
            if (!preferences.contains("${name}_damaged")) editor.putString("${name}_damaged", raw)
            editor.apply()
            if (parsed.damagedContainer) {
                val backup = preferences.getString("${name}_previous", null)
                if (backup != null) return LibraryCodec.read(backup, decode).records
            }
        }
        return parsed.records
    }
    private fun write(name: String, rows: List<JSONObject>, extra: (android.content.SharedPreferences.Editor) -> Unit = {}): Boolean {
        val old = preferences.getString(name, "[]") ?: "[]"
        if (old.trimStart().startsWith("{") && runCatching { JSONObject(old).optInt("version", 1) > 1 }.getOrDefault(false)) {
            preferences.edit().putString("warning", "本地数据来自较新版本，已停止写入以保留数据。请升级应用后再试。").apply()
            return false
        }
        val editor = preferences.edit()
        if (!preferences.contains("${name}_migration_backup")) editor.putString("${name}_migration_backup", old)
        val decoded = LibraryCodec.read(old) { it }
        if (!decoded.damagedContainer && decoded.rejected == 0) editor.putString("${name}_previous", old)
        editor.putString(name, LibraryCodec.write(rows))
        extra(editor)
        editor.apply()
        return true
    }
    fun collectionChanges():List<CollectionChange> = synchronized(lock) {
        val raw=preferences.getString("collection_changes",null)
        if(raw!=null) CollectionChanges.read(raw)
        else collections().sortedBy { it.subject.id }.map { entry ->
            val id=java.util.UUID.nameUUIDFromBytes(CollectionCodec.write(entry).toString().toByteArray(Charsets.UTF_8)).toString()
            CollectionChange(id,entry.subject.id,CollectionAction.ADD,entry.updatedAt,entry)
        }
    }
    private fun changesFor(before:List<CollectionEntry>,after:List<CollectionEntry>):String =
        CollectionChanges.write(CollectionChanges.append(collectionChanges(),before,after,System.currentTimeMillis()))
    private fun writeCollections(before:List<CollectionEntry>,after:List<CollectionEntry>):Boolean {
        val changes=try { changesFor(before,after) } catch(e:Exception) {
            preferences.edit().putString("warning","收藏变更记录无法安全保存，已停止修改：${e.message}").apply()
            return false
        }
        return write("favorites",after.map(CollectionCodec::write)) { it.putString("collection_changes",changes) }
    }
    fun collectionSyncSnapshot():CollectionSnapshot = synchronized(lock) {
        val parsed=LibraryCodec.read(raw("favorites"),CollectionCodec::read)
        require(!parsed.damagedContainer && parsed.rejected==0) { "本地收藏损坏或版本不兼容，已停止同步" }
        CollectionSnapshot(parsed.records,collectionChanges()).also { CollectionSnapshotCodec.write(it) }
    }
    fun applyCollectionSync(expected:CollectionSnapshot,merged:CollectionSnapshot):Boolean = synchronized(lock) {
        if(collectionSyncSnapshot()!=expected)return@synchronized false
        val journal=CollectionChanges.write(merged.changes)
        CollectionSnapshotCodec.write(merged)
        preferences.edit().putString("favorites_previous",raw("favorites"))
            .putString("favorites",LibraryCodec.write(merged.collections.map(CollectionCodec::write)))
            .putString("collection_changes",journal).commit()
    }
    fun warning(): String? = preferences.getString("warning", null)
    fun collections(): List<CollectionEntry> = synchronized(lock) { read("favorites", CollectionCodec::read).distinctBy { it.subject.id } }
    fun favorites(): List<Subject> = collections().map { it.subject }
    fun setCollection(subject: Subject, type: CollectionType?): Boolean = synchronized(lock) {
        val current=collections()
        val rest=current.filterNot { it.subject.id==subject.id }
        // Do not evict an unrelated favorite to make room for a new one.
        if(type!=null && rest.size>=200) {
            preferences.edit().putString("warning","收藏已达200条，请先整理后再添加。").apply()
            return@synchronized false
        }
        val updated=if(type==null)rest else listOf(CollectionEntry(subject,type,System.currentTimeMillis()))+rest
        writeCollections(current,updated)
    }
    fun changeCollections(ids: Set<Int>, type: CollectionType?): Int = synchronized(lock) {
        val current=collections()
        val matched=current.filter { it.subject.id in ids }
        if(matched.isEmpty())return@synchronized 0
        val now=System.currentTimeMillis()
        val updated=current.mapNotNull { if(it.subject.id !in ids)it else type?.let { target -> it.copy(type=target,updatedAt=now) } }
        if(writeCollections(current,updated))matched.size else 0
    }
    fun toggleFavorite(subject: Subject): Boolean = synchronized(lock) {
        setCollection(subject,if(collections().any { it.subject.id==subject.id })null else CollectionType.PLANNED)
    }
    fun history(): List<HistoryEntry> = synchronized(lock) { read("history", LibraryCodec::history).distinctBy { it.key } }
    fun save(entry: HistoryEntry) = synchronized(lock) {
        if (settings.incognito || entry.position <= 0 || entry.key.isBlank()) return@synchronized
        val current = history()
        val previous = current.firstOrNull { it.key == entry.key }
        val saved = entry.copy(origin = entry.origin ?: previous?.origin, updatedAt = System.currentTimeMillis())
        write("history", (listOf(saved) + current.filterNot { it.key == entry.key }).take(100).map(LibraryCodec::historyJson))
    }
    fun deleteHistory(key: String): Int = deleteHistory(setOf(key))
    fun deleteHistory(keys: Set<String>): Int = synchronized(lock) {
        val current=history()
        val removed=current.filter { it.key in keys }
        if(removed.isEmpty())return@synchronized 0
        if(write("history",current.filterNot { it.key in keys }.map(LibraryCodec::historyJson)) {
            it.putString("history_trash",LibraryCodec.write(removed.map(LibraryCodec::historyJson)))
        }) removed.size else 0
    }
    fun deletedHistoryCount(): Int = synchronized(lock) {
        LibraryCodec.read(preferences.getString("history_trash","[]") ?: "[]",LibraryCodec::history).records.size
    }
    fun undoHistoryDeletion(): Int = synchronized(lock) {
        val deleted=LibraryCodec.read(preferences.getString("history_trash","[]") ?: "[]",LibraryCodec::history).records
        val current=history()
        val existing=current.map { it.key }.toSet()
        val missing=deleted.filterNot { it.key in existing }
        val restored=(current+missing).sortedByDescending { it.updatedAt }.take(100)
        val count=restored.count { it.key !in existing }
        if(write("history",restored.map(LibraryCodec::historyJson)) { it.remove("history_trash") })count else 0
    }
    private fun raw(name:String)=preferences.getString(name,"[]") ?: "[]"
    fun backupFingerprint():String = synchronized(lock) { LibraryArchiveCodec.fingerprint(raw("favorites"),raw("history")) }
    fun exportBackup():String = synchronized(lock) {
        val collections=LibraryCodec.read(raw("favorites"),CollectionCodec::read)
        val history=LibraryCodec.read(raw("history"),LibraryCodec::history)
        require(!collections.damagedContainer && collections.rejected==0 && !history.damagedContainer && history.rejected==0) { "本地记录有损坏或版本不兼容，请先检查，未生成不完整备份" }
        LibraryArchiveCodec.write(LibraryArchive(collections.records,history.records,System.currentTimeMillis()))
    }
    fun restoreBackup(rawBackup:String,expectedFingerprint:String) = synchronized(lock) {
        val backup=LibraryArchiveCodec.read(rawBackup)
        require(expectedFingerprint==backupFingerprint()) { "预览后本地数据有变化，请重新预览" }
        for(name in listOf("favorites","history")) {
            val old=raw(name)
            require(!old.trimStart().startsWith("{") || runCatching { JSONObject(old).optInt("version",1)<=1 }.getOrDefault(true)) { "本地数据来自更高版本，禁止覆盖" }
        }
        val favorites=LibraryCodec.write(backup.collections.map(CollectionCodec::write)); val history=LibraryCodec.write(backup.history.map(LibraryCodec::historyJson))
        val changes=changesFor(collections(),backup.collections)
        val before=JSONObject().put("favorites",raw("favorites")).put("history",raw("history")).toString()
        check(preferences.edit().putString("restore_before",before)
            .putString("restore_after",LibraryArchiveCodec.fingerprint(favorites,history))
            .putString("collection_changes",changes).putString("favorites",favorites).putString("history",history).remove("history_trash").remove("warning").commit()) { "保存失败，请保留备份文件后重试" }
    }
    fun canUndoRestore() = synchronized(lock) { preferences.contains("restore_before") }
    fun undoRestore() = synchronized(lock) {
        require(preferences.getString("restore_after",null)==backupFingerprint()) { "恢复后已有新记录，已阻止撤销覆盖新数据" }
        val before=JSONObject(preferences.getString("restore_before",null) ?: error("没有可撤销的恢复"))
        val target=LibraryCodec.read(before.getString("favorites"),CollectionCodec::read)
        require(!target.damagedContainer && target.rejected==0) { "撤销副本的收藏损坏，已停止撤销" }
        val historyTarget=LibraryCodec.read(before.getString("history"),LibraryCodec::history)
        require(!historyTarget.damagedContainer && historyTarget.rejected==0) { "撤销副本的历史损坏，已停止撤销" }
        val changes=changesFor(collections(),target.records)
        check(preferences.edit().putString("collection_changes",changes).putString("favorites",before.getString("favorites")).putString("history",before.getString("history"))
            .remove("restore_before").remove("restore_after").remove("history_trash").commit()) { "撤销保存失败" }
    }

}
