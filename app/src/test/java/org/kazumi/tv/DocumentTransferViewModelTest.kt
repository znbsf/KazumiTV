package org.kazumi.tv

import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.ui.DocumentTransferViewModel

class DocumentTransferViewModelTest {
    @Test fun exportSnapshotIsConsumedOnceAndRejectsOverlappingLaunches() {
        val model=DocumentTransferViewModel()
        assertTrue(model.beginExport("original snapshot"))
        assertEquals(DocumentTransferViewModel.Operation.EXPORT,model.operation)
        assertFalse(model.beginExport("replacement"))
        assertFalse(model.beginImport())
        assertEquals("original snapshot",model.takeExport())
        assertNull(model.operation)
        assertNull(model.takeExport())
    }
    @Test fun cancellationReleasesImportOrExportForRetry() {
        val model=DocumentTransferViewModel()
        assertTrue(model.beginImport()); model.finish()
        assertNull(model.operation)
        assertTrue(model.beginExport("cancelled")); model.finish()
        assertNull(model.takeExport())
        model.beginExport("retry")
        assertEquals("retry",model.takeExport())
    }
    @Test fun absentSnapshotAfterProcessRecreationIsExplicitlyMissing() {
        assertNull(DocumentTransferViewModel().takeExport())
    }
}
