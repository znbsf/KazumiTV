@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import kotlinx.coroutines.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.playback.MediaResolutionFailure
import org.kazumi.tv.rules.SourceVerificationRequired

/** Owns one selection's resolver. Removing/changing the selection cancels its work. */
@Composable
fun ResolvingPlayback(selectionKey: String, title: String, resolve: suspend () -> PlaybackRequest,
                      verification: (@Composable (SourceVerificationRequired, () -> Unit) -> Unit)? = null,
                      onClose: () -> Unit, closeLabel:String="返回选集 / 换源", content: @Composable (PlaybackRequest) -> Unit) {
    key(selectionKey) {
        var media by remember { mutableStateOf<PlaybackRequest?>(null) }
        var error by remember { mutableStateOf<String?>(null) }
        var attempt by remember { mutableIntStateOf(0) }
        var verificationChallenge by remember { mutableStateOf<SourceVerificationRequired?>(null) }
        var showVerification by remember { mutableStateOf(false) }
        val currentResolver by rememberUpdatedState(resolve)
        val closeFocus = remember { FocusRequester() }
        LaunchedEffect(attempt) {
            error = null; verificationChallenge = null
            try {
                val result = currentResolver()
                currentCoroutineContext().ensureActive()
                media = result
            } catch (_: TimeoutCancellationException) {
                error = "解析超时，请重试或返回更换线路。"
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: SourceVerificationRequired) { error = failure.message; verificationChallenge = failure }
            catch (failure: org.kazumi.tv.rules.SourceRateLimited) { error = failure.message }
            catch (failure: MediaResolutionFailure) { error = failure.message }
            catch (_: Exception) { error = "解析失败，请重试或返回更换来源。" }
        }
        val request = media
        if (showVerification && verificationChallenge != null && verification != null) {
            BackHandler { showVerification = false }
            verification(verificationChallenge!!) { showVerification = false; attempt++ }
        } else if (request != null) content(request)
        else {
            BackHandler(onBack = onClose)
            LaunchedEffect(Unit) { withFrameNanos { }; closeFocus.requestFocus() }
            Box(Modifier.fillMaxSize().background(Color.Black).padding(40.dp), contentAlignment = Alignment.Center) {
                Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Text(title, style = KazumiType.heading)
                    Text(error ?: "正在解析播放地址…", style = KazumiType.body)
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Button(onClick = onClose, modifier = Modifier.focusRequester(closeFocus)) { Text(closeLabel) }
                        if (error != null) Button(onClick = { attempt++ }) { Text("重新解析") }
                        if (verificationChallenge != null && verification != null) Button(onClick = { showVerification = true }) { Text("网页验证") }
                    }
                }
            }
        }
    }
}
