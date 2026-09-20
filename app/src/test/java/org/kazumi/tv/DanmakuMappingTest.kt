package org.kazumi.tv

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.DanmakuMapping

class DanmakuMappingTest {
    private fun row(number:String,id:Long,season:String?=null)=JSONObject().put("episodeNumber",number).put("episodeId",id).put("episodeTitle","test").apply { if(season!=null)put("seasonId",season) }
    private fun response(vararg episodes:JSONObject, link:String="https://bangumi.tv/subject/400602",seasons:JSONArray=JSONArray()):JSONObject =
        JSONObject().put("success",true).put("errorCode",0).put("bangumi",JSONObject().put("bangumiUrl",link).put("seasons",seasons).put("episodes",JSONArray(episodes.toList())))
    @Test fun exactSubjectSingleSeasonMappingStillWorks() {
        assertEquals(901L,DanmakuMapping.automatic(response(row("1",901),row("2",902)).toString(),400602,1)?.id)
        assertEquals(901L,DanmakuMapping.automatic(response(row("1",901),link="https://bgm.tv/subject/400602/").toString(),400602,1)?.id)
    }
    @Test fun failedResponseAndDifferentSubjectCannotAutoload() {
        val valid=response(row("1",901))
        assertNull(DanmakuMapping.automatic(valid.put("success",false).toString(),400602,1))
        assertNull(DanmakuMapping.automatic(valid.put("success",true).put("errorCode",5).toString(),400602,1))
        assertNull(DanmakuMapping.automatic(response(row("1",901),link="https://bangumi.tv/subject/975").toString(),400602,1))
        assertNull(DanmakuMapping.automatic(response(row("1",901),link="https://example.org/subject/400602").toString(),400602,1))
    }
    @Test fun mixedActualSeasonsCannotBorrowUniqueEpisodeFromAnotherSeason() {
        assertNull(DanmakuMapping.automatic(response(row("1",901,"1"),row("12",912,"2")).toString(),400602,12))
        assertNull(DanmakuMapping.automatic(response(row("1",901,"1"),row("1",902,"2")).toString(),400602,1))
    }
    @Test fun seasonNavigationAloneDoesNotInvalidateOneSeasonEpisodeList() {
        val seasons=JSONArray().put(JSONObject().put("id","1")).put(JSONObject().put("id","2"))
        assertEquals(901L,DanmakuMapping.automatic(response(row("1",901,"2"),row("2",902,"2"),seasons=seasons).toString(),400602,1)?.id)
        assertEquals(901L,DanmakuMapping.automatic(response(row("1",901),seasons=seasons).toString(),400602,1)?.id)
    }
    @Test fun contradictorySingleSeasonMetadataRequiresManualChoice() {
        assertNull(DanmakuMapping.automatic(response(row("1",901,"2"),seasons=JSONArray().put(JSONObject().put("id","1"))).toString(),400602,1))
    }
    @Test fun duplicateNumbersInvalidIdsAndSpecialLabelsNeverGuess() {
        assertNull(DanmakuMapping.automatic(response(row("1",901),row("01",902)).toString(),400602,1))
        for(id in listOf(0L,-1L))assertNull(DanmakuMapping.automatic(response(row("1",id)).toString(),400602,1))
        for(label in listOf("SP1","1.5","第二季 · 1"))assertNull(DanmakuMapping.automatic(response(row(label,901)).toString(),400602,1))
        assertNull(DanmakuMapping.automatic(response(row("1",901)).toString(),0,1))
    }
}
