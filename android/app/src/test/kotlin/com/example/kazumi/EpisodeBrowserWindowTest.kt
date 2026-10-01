package com.example.kazumi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EpisodeBrowserWindowTest {
    @Test fun fiftyItemSegmentsCoverEveryOriginalItemInEitherOrder() {
        for (count in listOf(0, 1, 49, 50, 51, 200, 201, 5000)) {
            for (descending in listOf(false, true)) {
                val segments = (0 until EpisodeBrowserWindow.pageCount(count)).map {
                    EpisodeBrowserWindow.indices(count, it, descending)
                }
                val expected = (0 until count).toList().let { if (descending) it.reversed() else it }
                assertEquals(expected, segments.flatten())
                assertTrue(segments.all { it.size <= 50 })
            }
        }
    }

    @Test fun locatingAndOrderChangesKeepTheSameOriginalIndex() {
        for (index in 0 until 201) {
            for (descending in listOf(false, true)) {
                val page = EpisodeBrowserWindow.pageOf(index, 201, descending)
                assertTrue(index in EpisodeBrowserWindow.indices(201, page, descending))
            }
        }
        assertEquals(150, EpisodeBrowserWindow.locate("151", 201))
        assertEquals(3, EpisodeBrowserWindow.pageOf(150, 201, false))
        assertEquals(1, EpisodeBrowserWindow.pageOf(150, 201, true))
    }

    @Test fun numericLocationCountsSpecialsAsOriginalListPositions() {
        assertEquals(0, EpisodeBrowserWindow.locate("1", 201))
        assertEquals(99, EpisodeBrowserWindow.locate("100", 201))
        assertEquals(4999, EpisodeBrowserWindow.locate("5000", 5000))
        listOf("0", "202", "-1", "SP1", "999999999999999", "").forEach {
            assertNull(EpisodeBrowserWindow.locate(it, 201))
        }
    }

    @Test fun stalePageValuesAreClampedToAnExistingSegment() {
        assertEquals((0..49).toList(), EpisodeBrowserWindow.indices(201, -100, false))
        assertEquals(listOf(200), EpisodeBrowserWindow.indices(201, 100, false))
        assertEquals(listOf(0), EpisodeBrowserWindow.indices(201, 100, true))
        assertEquals(emptyList<Int>(), EpisodeBrowserWindow.indices(0, 0, false))
    }
}
