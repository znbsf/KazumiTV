package org.kazumi.tv

import android.app.Instrumentation
import android.content.Intent
import android.os.Parcel
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.*
import org.kazumi.tv.data.*
import org.kazumi.tv.ui.NavigationStateSavers
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Real Parcel marshalling catches Android 9's nested Serializable class-loader failure.
 * This is deliberately distinct from the separate normal-entry OS process-kill test.
 */
object NavigationParcelRegression {
    fun run(test: Instrumentation): String {
        fun diagnostic(message:String) {
            test.sendStatus(0,android.os.Bundle().apply { putString("stream","NavigationParcel fixture: $message\n") })
        }
        val activity=test.startActivitySync(Intent(test.targetContext,MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val subject=Subject(400602,"恢复样片","https://fixture.invalid/cover","简介",SubjectMetadata(originalTitle="original"))
        val entry=HistoryEntry("source|https://fixture.invalid/12",subject,"第12集",65000,140000,
            PlaybackOrigin("source","节目","https://fixture.invalid/show","线路二"),1234)
        val credits=arrayListOf(CreditEntry(1,"角色","https://fixture.invalid/a",character=true,
            actors=listOf(CreditEntry(2,"声优","https://fixture.invalid/b",job="配音"))))
        val paths=arrayListOf(subject,subject.copy(id=400603,title="关联作品"))
        val observed=AtomicReference<List<Any?>>(emptyList())
        fun mount(registry: SaveableStateRegistry, seed:Boolean) {
            val composed=CountDownLatch(1)
            test.runOnMainSync { activity.setContent {
                CompositionLocalProvider(LocalSaveableStateRegistry provides registry) {
                    val selected by rememberSaveable(stateSaver=NavigationStateSavers.subject) { mutableStateOf(if(seed)subject else null) }
                    val history by rememberSaveable(stateSaver=NavigationStateSavers.history) { mutableStateOf(if(seed)entry else null) }
                    val path by rememberSaveable(stateSaver=NavigationStateSavers.subjects) { mutableStateOf(if(seed)paths else arrayListOf()) }
                    val people by rememberSaveable(stateSaver=NavigationStateSavers.credits) { mutableStateOf(if(seed)credits else arrayListOf()) }
                    SideEffect { observed.set(listOf(selected,history,path,people)); composed.countDown() }
                }
            } }
            check(composed.await(10,TimeUnit.SECONDS)) { "Navigation fixture did not compose seed=$seed" }
            test.waitForIdleSync()
        }
        try {
            val scope=object:SaverScope { override fun canBeSaved(value:Any)=true }
            fun <T> checkCodec(name:String,saver:Saver<T,String>,value:T) {
                val encoded=with(saver) { scope.save(value) }!!
                val decoded=saver.restore(encoded)
                diagnostic("codec=$name equal=${decoded==value}")
                check(decoded==value) { "$name codec mismatch expected=$value actual=$decoded" }
            }
            checkCodec("subject",NavigationStateSavers.subject,subject)
            checkCodec("history",NavigationStateSavers.history,entry)
            checkCodec("related_path",NavigationStateSavers.subjects,paths)
            checkCodec("credit_path",NavigationStateSavers.credits,credits)
            val registry=SaveableStateRegistry(null) { true }
            mount(registry,true)
            var saved:Map<String,List<Any?>> = emptyMap()
            test.runOnMainSync { saved=registry.performSave() }
            // SaveableStateRegistry permits several providers under the same key;
            // it consumes their values in registration order on restoration.
            val valueCount=saved.values.sumOf { it.size }
            diagnostic("savedKeyCount=${saved.size} savedValueCount=$valueCount entries="+
                saved.entries.joinToString { (key,values) -> "$key:${values.size}:"+values.joinToString { value ->
                    val state=value as? State<*>
                    "${value?.javaClass?.simpleName}(valueType=${state?.value?.javaClass?.simpleName})"
                } })
            diagnostic("seedObserved="+observed.get().map { it?.javaClass?.simpleName })
            check(valueCount==4) { "Expected four registered navigation values, got $valueCount" }
            val disposed=CountDownLatch(1)
            test.runOnMainSync { activity.setContent { SideEffect { disposed.countDown() } } }
            check(disposed.await(10,TimeUnit.SECONDS)) { "Navigation fixture was not disposed" }
            test.waitForIdleSync()
            val writer=Parcel.obtain()
            val bytes=try { writer.writeMap(saved); writer.marshall() } finally { writer.recycle() }
            val reader=Parcel.obtain()
            val restored=try {
                reader.unmarshall(bytes,0,bytes.size); reader.setDataPosition(0)
                @Suppress("UNCHECKED_CAST", "DEPRECATION")
                (reader.readHashMap(MainActivity::class.java.classLoader) as Map<String,List<Any?>>)
            } finally { reader.recycle() }
            diagnostic("restoredKeyCount=${restored.size} restoredValueCount=${restored.values.sumOf { it.size }} keys=${restored.keys}")
            mount(SaveableStateRegistry(restored) { true },false)
            val expected=listOf(subject,entry,paths,credits)
            val actual=observed.get()
            listOf("subject","history","related_path","credit_path").forEachIndexed { index,name ->
                diagnostic("parcel=$name equal=${actual.getOrNull(index)==expected[index]} expected=${expected[index]} actual=${actual.getOrNull(index)}")
                check(actual.getOrNull(index)==expected[index]) {
                    "$name Parcel mismatch expected=${expected[index]} actual=${actual.getOrNull(index)} savedKeys=${saved.keys} restoredKeys=${restored.keys}"
                }
            }
            return "navigation_parcel=PASS subject=PASS history=PASS related_path=PASS credit_path=PASS"
        } finally { test.runOnMainSync { activity.finish() }; test.waitForIdleSync() }
    }
}
