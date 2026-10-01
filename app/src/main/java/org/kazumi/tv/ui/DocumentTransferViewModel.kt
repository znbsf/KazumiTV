package org.kazumi.tv.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import org.kazumi.tv.data.LibraryArchiveCodec

/** Keeps a bounded export snapshot across Activity recreation, without placing it in a Bundle. */
class DocumentTransferViewModel : ViewModel() {
    enum class Operation { IMPORT, EXPORT }
    var operation by mutableStateOf<Operation?>(null)
        private set
    private var exportRaw: String? = null

    fun beginExport(raw: String): Boolean {
        if(operation!=null)return false
        require(raw.length<=LibraryArchiveCodec.MAX_CHARS)
        exportRaw=raw
        operation=Operation.EXPORT
        return true
    }

    fun beginImport(): Boolean {
        if(operation!=null)return false
        operation=Operation.IMPORT
        return true
    }

    fun takeExport(): String? {
        val raw=exportRaw
        finish()
        return raw
    }

    fun finish() { exportRaw=null; operation=null }
}
