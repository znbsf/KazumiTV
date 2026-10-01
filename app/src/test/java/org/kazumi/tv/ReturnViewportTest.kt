package org.kazumi.tv

import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.*

class ReturnViewportTest {
    @Test fun returnKeepsViewportRatherThanMovingSelectedCardToTop() {
        assertEquals(ReturnPosition(12,37,19),ReturnViewport.resolve((0..39).toList(),19,12,12,37))
    }
    @Test fun windowEvictionOrReorderingUsesStableAnchor() {
        assertEquals(ReturnPosition(3,37,10),ReturnViewport.resolve((20..59).toList(),30,23,23,37))
        assertEquals(ReturnPosition(2,37,0),ReturnViewport.resolve(listOf(30,40,23,50),30,23,23,37))
    }
    @Test fun removedSelectedItemFallsBackNearViewport() {
        assertEquals(ReturnPosition(1,37,1),ReturnViewport.resolve(listOf(10,20,30),99,20,7,37))
        assertEquals(ReturnPosition(2,0,2),ReturnViewport.resolve(listOf(10,20,30),99,88,7,37))
    }
    @Test fun historyGroupHeadersNeverReceiveFocus() {
        val keys=listOf("group-a","record-a","group-b","record-b")
        assertEquals(ReturnPosition(2,12,3),ReturnViewport.resolve(keys,"removed","group-b",2,12,setOf("record-a","record-b")))
        assertEquals(ReturnPosition(3,0,1),ReturnViewport.resolve(keys,"removed","missing",9,12,setOf("record-a")))
    }
    @Test fun emptyOrNonActionableResultsReturnNoTarget() {
        assertNull(ReturnViewport.resolve(emptyList<Int>(),1,2,0,0))
        assertNull(ReturnViewport.resolve(listOf("header"),"removed","header",0,0,emptySet()))
        assertEquals(ReturnPosition(0,0,0),ReturnViewport.resolve(listOf(1),1,1,-2,-4))
    }
}
