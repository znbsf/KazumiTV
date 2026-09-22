package org.kazumi.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.rules.VerificationProgress

class MacCmsVerificationStateTest {
    @Test fun pendingAndRejectedUserSubmissionsCannotCountAsVerification() {
        val progress=VerificationProgress()
        val challenge=JSONObject().put("ready",true).put("challenge",true).put("acted",true)
        repeat(5) { assertFalse(progress.observe(JSONObject(challenge.toString()).put("submitting",true))) }
        repeat(5) { assertFalse(progress.observe(JSONObject(challenge.toString()).put("submitError","验证码未通过，请重新输入"))) }
        val clear=JSONObject().put("ready",true).put("challenge",false).put("done",false)
        repeat(2) { assertFalse(progress.observe(clear)) }
        assertTrue(progress.observe(clear))
    }
}
