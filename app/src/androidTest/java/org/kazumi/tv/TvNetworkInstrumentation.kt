package org.kazumi.tv

import okhttp3.MediaType.Companion.toMediaType
import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import kotlinx.coroutines.runBlocking
import org.kazumi.tv.data.*
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Explicit opt-in real-device smoke test; never logs credentials or response bodies. */
class TvNetworkInstrumentation : Instrumentation() {
    private var mode = "network"
    private var runnerArgs = Bundle()
    private var auditName: String? = null
    private var auditRun = "baseline"
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); runnerArgs=arguments ?: Bundle(); mode = arguments?.getString("mode") ?: "network"; auditName=arguments?.getString("source"); auditRun=arguments?.getString("run") ?: "baseline"; start() }
    override fun onStart() {
        val output = Bundle()
        try {
            if(mode == "mac-cms-verification") {
                MacCmsVerificationRegression.run(this)
                output.putString("stream", "mac_cms_verification=PASS\n")
                finish(Activity.RESULT_OK, output); return
            }
            if(mode == "recent-watch-navigation") {
                RecentWatchNavigationRegression.run(this)
                output.putString("stream", "recent_watch_navigation=PASS\n")
                finish(Activity.RESULT_OK, output); return
            }
            if(mode == "verification-layout") {
                VerificationLayoutRegression.run(this)
                output.putString("stream", "verification_layout=PASS\n")
                finish(Activity.RESULT_OK, output); return
            }
            if(mode == "navigation-parcel") {
                output.putString("stream", NavigationParcelRegression.run(this) + "\n")
                finish(Activity.RESULT_OK, output); return
            }
            if(mode in setOf("user-data-backup", "user-data-restore", "user-data-restore-watch")) {
                output.putString("stream", UserDataCheckpoint.run(this, mode, auditRun) + "\n")
                finish(Activity.RESULT_OK, output); return
            }
            if(mode=="licenses-ui") {
                LicenseUiRegression.run(this);output.putString("stream","bundled_licenses_GPL_scroll_back=OK\n");finish(Activity.RESULT_OK,output);return
            }
            if(mode=="automatic-danmaku-ui") {
                AutomaticDanmakuUiRegression.run(this); output.putString("stream","real_service_automatic_mapping_comments_overlay=OK\n");finish(Activity.RESULT_OK,output);return
            }
            if(mode in setOf("source-inventory","source-import","source-audit")) {
                FullSourceAudit.run(this,mode,auditName,auditRun); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="source-page") {
                SourcePageDiagnostic.run(this,runnerArgs); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="real-watch") {
                RealWatchRegression.run(this,runnerArgs); output.putString("stream","real_time_episode_and_auto_next=OK\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="playback-recovery") {
                PlaybackRecoveryRegression.run(this); output.putString("stream","road_cancel_pause_and_play, verification_POST_resume=OK\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="playback-restore") {
                output.putString("stream",PlaybackRestoreRegression.run(this)+"\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="playback-expired") {
                ExpiredPlaybackRegression.run(this); output.putString("stream","expired_media_position_intent_retry_cancel=OK\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="playback-background") {
                BackgroundPlaybackRegression.run(this); output.putString("stream","HOME_pause_session_disconnect_return_resume=OK\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="episode-session") {
                output.putString("stream",EpisodeMediaSessionRegression.run(this)+"\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="player-controls") {
                PlayerControlsRegression.run(this); output.putString("stream","player_controls=OK\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="web-discovery") {
                output.putString("stream",WebDiscoveryRegression.run(targetContext)+"\n"); finish(Activity.RESULT_OK,output); return
            }
            if(mode=="real-ui-storage") {
                val isolated=object:android.content.ContextWrapper(targetContext) {
                    override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("real_ui_test_$name",mode)
                }
                val actualRows=LibraryStore(targetContext).history().filter { it.subject.id==99000916 }
                val isolatedRows=LibraryStore(isolated).history().filter { it.subject.id==99000916 }
                output.putString("stream","UI fixture storage: actual=${actualRows.map { it.position to it.duration }}, isolated=${isolatedRows.map { it.position to it.duration }}, actual_incognito=${TvPreferences(targetContext).incognito}\n")
                finish(Activity.RESULT_OK,output);return
            }
            if(mode=="real-play-ui") {
                try { RealPlaybackUiRegression.run(this) }
                catch(failure:Exception) { output.putString("stream","Real playback UI FAILED: ${failure.javaClass.simpleName} ${failure.message}\n");finish(Activity.RESULT_CANCELED,output);return }
                output.putString("stream","Real playback UI: search, select_episode12, auto_enter_player, rendered_progress, back_to_episodes, resume, user_history_preserved=OK\n")
                finish(Activity.RESULT_OK,output);return
            }
            if(mode=="verification-live") {
                VerificationLiveRegression.run(this,runnerArgs)
                output.putString("stream","Real verification run complete.\n")
                finish(Activity.RESULT_OK,output);return
            }
            if(mode=="verification") {
                try { VerificationRegression.run(this) }
                catch(failure:Exception) {
                    output.putString("stream","Verification FAILED: ${failure.javaClass.simpleName}: ${failure.message}; ${failure.stackTrace.take(4).joinToString()}\n")
                    finish(Activity.RESULT_CANCELED,output);return
                }
                output.putString("stream","Verification: button, async_script, manual_image_submit, false_success_guards, cancellation, exact_POST_cookie_retry=OK\n")
                finish(Activity.RESULT_OK,output);return
            }
            if(mode=="real-sources" || mode=="real-pages" || mode=="real-play") {
                RealSourceRegression.run(this,mode=="real-pages",mode=="real-play")
                output.putString("stream","Real source diagnosis finished; per-source results above are not playback acceptance.\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="release-danmaku") {
                check(targetContext.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE==0)
                val isolated=object:android.content.ContextWrapper(targetContext) {
                    override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("release_bundle_probe_"+name,mode)
                }
                val credentials=checkNotNull(DanmakuCredentialStore(isolated).read())
                val comments=runBlocking {
                    val repository=DanmakuRepository(credentials)
                    val episode=checkNotNull(repository.automaticEpisode(400602,1))
                    repository.comments(episode.id)
                }
                check(comments.isNotEmpty())
                output.putString("stream","Release APK: non_debuggable, bundled_danmaku_mapping_and_comments=OK, comments=${comments.size}\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="external-playback") {
                ExternalPlaybackRegression.run(this)
                output.putString("stream","External playback: intent_guards, MX_launch_return, paused_UI, user_data_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="download-manifests") {
                DownloadManifestRegression.run(this)
                output.putString("stream","Download manifests: VOD_policy, failure_reasons, cancel_socket, AES_offline_frame=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode in listOf("download-recovery","download-recovery-stage","download-recovery-reopen")) {
                DownloadRecoveryRegression.run(this,mode)
                output.putString("stream","Download recovery: ${mode}=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode in listOf("downloads-adaptive","downloads-pause-restart","downloads-resume-restart")) {
                AdaptiveDownloadRegression.run(this,mode)
                output.putString("stream","Adaptive downloads: ${mode}=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="downloads" || mode=="downloads-reopen") {
                DownloadRegression.run(this,mode=="downloads-reopen")
                output.putString("stream","Downloads: ${mode}, cache_bytes_equal, user_data_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="capabilities") {
                CapabilityRegression.run(this)
                output.putString("stream","Capabilities: real_display_audio_read, unknown_empty_semantics, UI_reentry_listener_disposal=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="display-modes") {
                DisplayModeRegression.run(this)
                output.putString("stream","Display modes: real_capabilities, overlapping_window_owners, persistence_reopen, simulated_missing_fallback, 15s_timeout, UI_confirm_back_cancel, real_video_Dialog_window_scope_restore, actual_settings_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="source-transfer") {
                SourceTransferRegression.run(this)
                output.putString("stream","Source transfer: real_video_A_to_B_position, chapters_failure_retry, cancel_returns_B_position, ambiguous_C_manual_zero_overrides_history, source_namespaced_history, actual_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="webdav-collections") {
                WebDavRegression.run(this)
                output.putString("stream","WebDAV: loopback_conditional_create_update, remote_merge_delete, 412_local_retained, auth_weak_bad_redirect_guard, local_changes_before_during_commit, cancellation_socket_closed, encrypted_credentials, UI_retry_preview_cancel_commit, actual_library_credentials_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="collection-journal") {
                CollectionJournalRegression.run(this)
                output.putString("stream","Collection journal: batch_update_delete, reopen, idempotent_merge, restore_and_undo_events, future_guard, legacy_seed, actual_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="library-backup") {
                LibraryBackupRegression.run(this)
                output.putString("stream","Library backup: five_atomic_files, roundtrip, changed_preview_guard, future_version_guard, undo_new_data_guard, UI_preview_cancel_restore_undo, actual_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="sleep-timer") {
                SleepTimerRegression.run(this)
                output.putString("stream","Sleep timer: real_media_pause, survives_engine_replacement, expired_open_stays_paused, manual_resume, cancel_no_pause, expiry_UI=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="road-selection") {
                RoadSelectionRegression.run(this)
                output.putString("stream","Road selection: matched_progress, ambiguous_100th_zero_progress, reverse_stable_index, duplicate_episode_manual_choice, nested_back, empty_road_cancel, user_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="rule-import-cancel") {
                RuleImportCancellationRegression.run(this)
                output.putString("stream","Rule import: cancel_button, back_cancel, two_sockets_closed, no_cancelled_write, immediate_retry_success, actual_rules_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-credits" || mode=="credits-live") {
                S4CreditsRegression.run(this,mode=="credits-live")
                output.putString("stream",if(mode=="credits-live") "Credits live: characters_staff_nonempty_and_screenshots=OK\n" else "Credits: list_retry, detail_retry, actor_detail, nested_back, staff_episodes, tabs=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-relations" || mode=="relations-live") {
                S4RelationsRegression.run(this,mode=="relations-live")
                output.putString("stream",if(mode=="relations-live") "Relations live: sequel_loaded_and_screenshot=OK\n" else "Relations: failure_retry, child_detail, back_to_relations, back_to_root_detail=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-calendar" || mode=="calendar-live" || mode=="season-live") {
                try { S4CalendarRegression.run(this,mode!="s4-calendar",mode=="season-live") } catch(failure:Exception) {
                    output.putString("stream","Calendar failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream",if(mode=="season-live") "Season live: nonempty_season_and_screenshot=OK\n" else if(mode=="calendar-live") "Calendar live: nonempty_week_and_screenshot=OK\n" else "Calendar: failure_retry, watching_filter, exact_selection, season_failure_clears_old, season_retry, current_return=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-setup") {
                try { S4SetupRegression.run(this) } catch(failure:Exception) {
                    output.putString("stream","S4 setup failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream","S4 setup: four_steps, directory_retry, install_failure_preserved_retry, zero_sources_explicit_browse, finish_only_at_end, reentry_cancel, actual_rules_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-danmaku-network") {
                val count=java.util.concurrent.atomic.AtomicInteger()
                val client=okhttp3.OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).addInterceptor { chain ->
                    val request=chain.request(); val first=count.incrementAndGet()==1
                    if(first) {
                        check(request.header("X-AppId")=="fixture")
                        check(request.header("X-Signature")!=null)
                    } else {
                        check(request.url.host=="fixture.invalid")
                        check(request.header("X-AppId")==null && request.header("X-Signature")==null && request.header("X-Timestamp")==null)
                    }
                    okhttp3.Response.Builder().request(request).protocol(okhttp3.Protocol.HTTP_1_1)
                        .code(if(first)302 else 200).message("fixture")
                        .header("Location","https://fixture.invalid/comments")
                        .body(okhttp3.ResponseBody.create("application/json".toMediaType(),if(first) "" else "{\"comments\":[{\"p\":\"1,1,16777215\",\"m\":\"fixture\"}]}" )).build()
                }.build()
                val comments=runBlocking { DanmakuRepository(DanmakuCredentials("fixture","test-only"),client).comments(1) }
                check(count.get()==2 && comments.single().text=="fixture")
                output.putString("stream","S4 danmaku network: signed_request, redirect_without_credentials, async_comment_decode=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if(mode=="s4-danmaku-selection") {
                val isolated=object:android.content.ContextWrapper(targetContext) {
                    override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("s4_mapping_fixture",0)
                }
                val raw=isolated.getSharedPreferences("ignored",0); raw.edit().clear().commit()
                try {
                    val store=DanmakuSelectionStore(isolated)
                    store.save(1,"rule|page1",DanmakuSelection(DanmakuEpisode(100,"fixture"),5000))
                    check(DanmakuSelectionStore(isolated).read(1,"rule|page1").episode?.id==100L)
                    check(store.read(1,"rule|page2")==DanmakuSelection())
                    check(store.read(2,"rule|page1")==DanmakuSelection())
                    store.save(1,"rule|page1",store.read(1,"rule|page1").copy(offset=Long.MAX_VALUE))
                    check(store.read(1,"rule|page1").offset==120000L)
                    store.clear(1,"rule|page1"); check(store.read(1,"rule|page1")==DanmakuSelection())
                    repeat(105) { store.save(1,"page$it",DanmakuSelection(offset=1000)) }
                    check(raw.all.size==100)
                    output.putString("stream","S4 mapping: reopen, episode_and_subject_isolation, offset_bounds, clear, 100_record_limit=OK\n")
                } finally { raw.edit().clear().commit() }
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s3-tracks") {
                try { S3TracksRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S3 tracks failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S3 tracks: real_video_frame, Japanese_audio_subtitle, subtitles_off_reopen, missing_language_English_fallback, auto_tracks, four_picture_screenshots, user_settings_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s3-options") {
                try { S3PlaybackOptionsRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S3 options failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S3 options: settings_UI_reopen, engine_speed_seek_language_subtitles, no_track_indices, four_three_view_geometry, user_preferences_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-episodes") {
                try { S4EpisodeBrowserRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S4 episodes failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S4 episodes: current_100, reverse_exact_index, special_list_position, invalid_position, user_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-history-groups") {
                try { S4HistoryGroupsRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S4 history groups failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S4 history groups: latest_exact_resume, kind_filter, filtered_delete_undo, source_search, real_library_unchanged=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-collection") {
                try { S4CollectionRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S4 collection failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S4 collection: legacy_snapshot, all_types_reopen, future_write_protection, batch_UI_change_filter_sort_remove_cancel, detail_picker, history_and_user_library_preserved=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-history") {
                try { S4HistoryRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S4 history failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S4 history: incognito_no_writes, batch_delete_reopen_undo, newer_progress_preserved, future_schema_preserved, UI_cancel_delete_undo, user_library_unchanged=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-cache") {
                try { S4CacheRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S4 cache failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S4 cache: bounded_HTTP, cancelled_socket_closed, active_search_reload, mirror_reload_restore, library_preserved, cover_failure_retry=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-search" || mode == "s4-search-default") {
                try { S4SearchRegression.run(this,mode=="s4-search-default") } catch (failure: Exception) {
                    output.putString("stream", "S4 search failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", if(mode=="s4-search-default") "S4 default SavedState ViewModel factory=OK\n" else "S4 search: history_bound_clear_reopen, production_search_detail_return, auto_next_page, saved_intent_reconstruction=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "search-live") {
                val result=runBlocking {
                    val repo=CatalogRepository()
                    val pages=mutableListOf<List<Subject>>()
                    val status=listOf(0,20).map { offset ->
                        try { val page=repo.search("魔法",offset,"score"); pages.add(page); "offset=$offset size=${page.size}" }
                        catch(e:Exception) { "offset=$offset failed=${e.javaClass.simpleName}" }
                    }
                    status.joinToString("; ") + if(pages.size==2) "; overlap=${pages[0].map { it.id }.intersect(pages[1].map { it.id }.toSet()).size}" else ""
                }
                output.putString("stream",result+"\n"); finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s4-details" || mode == "detail-ui") {
                try { S4DetailsRegression.run(this,mode=="detail-ui") } catch (failure: Exception) {
                    output.putString("stream", "S4 details failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "$mode: passed; inspect detail screenshot\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s3-resource") {
                try { output.putString("stream", S3ResourceRegression.run(this) + "\n") } catch (failure: Exception) {
                    output.putString("stream", "S3 resources failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED, output); return
                }
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "s3-media") {
                try { S3MediaRegression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S3 media failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED, output); return
                }
                output.putString("stream", "S3 media: local_audio, overlapping_sessions, remote_metadata_pause_seek_play, audio_focus_loss, foreground_session_lifecycle, idempotent_release=OK\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "resolver-live") {
                val evidence = runBlocking {
                    val repo=org.kazumi.tv.rules.RuleRepository(targetContext)
                    val rule=repo.rules.first { it.name=="7sefun" }
                    val match=repo.search(rule,"葬送的芙莉莲").first { it.title.trim()=="葬送的芙莉莲" }
                    repo.chapters(rule,match).take(2).mapIndexed { index, road ->
                        try {
                            val ep=road.episodes.first()
                            val result=org.kazumi.tv.playback.WebMediaResolver(targetContext, diagnostic = { diagnostic ->
                                android.util.Log.i("KazumiResolverTest", "road${index+1}: $diagnostic")
                            }).resolve(ep.pageUrl,rule,ep.title)
                            "road${index+1}=resolved:${result.mimeType}"
                        } catch(cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                        catch(failure:Exception) { "road${index+1}=${if(failure is org.kazumi.tv.playback.MediaResolutionFailure) failure.message else failure.javaClass.simpleName}" }
                    }.joinToString("; ")
                }
                output.putString("stream", "live resolver only: $evidence\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "s2-resolver") {
                try { S2ResolverRegression.run(targetContext) } catch(failure: Exception) {
                    output.putString("stream", "S2 resolver fixture failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED,output); return
                }
                output.putString("stream", "S2 resolver: delayed_DOM, extensionless_XHR_HLS, fake_media_rejected, challenge_page, HTTP503_stage, cancellation=OK\n")
                finish(Activity.RESULT_OK,output); return
            }
            if (mode == "rules-ui") {
                val activity = startActivitySync(android.content.Intent(targetContext, MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
                runOnMainSync { activity.setContent { org.kazumi.tv.ui.KazumiTheme(false) {
                    Box(Modifier.fillMaxSize().background(org.kazumi.tv.ui.KazumiColors.background).padding(30.dp)) { org.kazumi.tv.ui.RulesScreen() }
                } } }
                Thread.sleep(5000)
                val screenshot = uiAutomation.takeScreenshot()
                java.io.File(targetContext.getExternalFilesDir(null), "rules-management.png").outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
                screenshot.recycle()
                output.putString("stream", "rules management displayed; inspect screenshot\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "s2-rules") {
                S2RulesRegression.run(targetContext)
                output.putString("stream", "S2 rules: partial_import, invalid_update_preserved, rollback, reorder, enable_disable, delete_restore, corruption_isolation=OK\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "s1-storage") {
                S1StorageRegression.run(targetContext)
                output.putString("stream", "S1 storage: legacy_read, damaged_row_isolation, snapshot_migration, reopen_context, damaged_container_recovery=OK\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "s0-regression") {
                try { S0Regression.run(this) } catch (failure: Exception) {
                    output.putString("stream", "S0 regression failed: ${failure.stackTraceToString()}\n")
                    finish(Activity.RESULT_CANCELED, output); return
                }
                output.putString("stream", "S0: same_view_rebind, detach, pending_shell, failure_retry, cancellation_late_result=OK\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "catalog") {
                runBlocking {
                    val catalog = org.kazumi.tv.rules.RuleCatalog()
                    val entries = catalog.list()
                    val entry = entries.first { it.name == "7sefun" }
                    val store = org.kazumi.tv.rules.RuleStore(targetContext)
                    check(catalog.install(entry, store) == 1)
                    check(org.kazumi.tv.rules.RuleStore(targetContext).all().first { it.name == entry.name }.json.optString("version") == entry.version)
                    output.putString("stream", "catalog=${entries.size}; rule_download_install_and_reload=OK\n")
                }
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "player-ui" || mode == "source-ui") {
                val subject = runBlocking { CatalogRepository().search("frieren").first { it.title == "葬送的芙莉莲" } }
                val request = if (mode == "player-ui") runBlocking {
                    val repository = org.kazumi.tv.rules.RuleRepository(targetContext)
                    val rule = repository.rules.first { it.name == "7sefun" }
                    val match = repository.search(rule, subject.title).first { it.title.trim() == subject.title }
                    val episode = repository.chapters(rule, match).last().episodes.first()
                    val danmaku = DanmakuRepository(checkNotNull(DanmakuCredentialStore(targetContext).read()))
                    val mapping = checkNotNull(danmaku.automaticEpisode(subject.id, 1))
                    check(danmaku.comments(mapping.id).isNotEmpty())
                    output.putString("mapping", "official_subject_episode=OK")
                    org.kazumi.tv.playback.WebMediaResolver(targetContext).resolve(episode.pageUrl, rule, "${subject.title} · ${episode.title}")
                } else null
                val activity = startActivitySync(android.content.Intent(targetContext, MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
                runOnMainSync { activity.setContent { org.kazumi.tv.ui.KazumiTheme(false) {
                    if (request != null) org.kazumi.tv.ui.PlayerScreen(request, subject, episodes = listOf("第01集"), currentEpisode = 0, onClose = { activity.finish() })
                    else Box(Modifier.fillMaxSize().background(org.kazumi.tv.ui.KazumiColors.background).padding(30.dp)) { org.kazumi.tv.ui.SourceScreen(subject) }
                } } }
                Thread.sleep(18000)
                if (request != null) {
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_MEDIA_PAUSE)
                    Thread.sleep(1000)
                }
                val screenshot = uiAutomation.takeScreenshot()
                java.io.File(targetContext.getExternalFilesDir(null), "$mode.png").outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                screenshot.recycle()
                if (request == null) {
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_DOWN)
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_CENTER)
                    Thread.sleep(12000)
                    val roadsImage = uiAutomation.takeScreenshot()
                    java.io.File(targetContext.getExternalFilesDir(null), "source-roads.png").outputStream().use { roadsImage.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    roadsImage.recycle()
                    // Enter a real source episode while the production resolver is still running.
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_DOWN)
                    Thread.sleep(700)
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_DPAD_CENTER)
                    Thread.sleep(1200)
                    val pendingImage = uiAutomation.takeScreenshot()
                    java.io.File(targetContext.getExternalFilesDir(null), "source-pending.png").outputStream().use { pendingImage.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    pendingImage.recycle()
                    sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
                    Thread.sleep(1500)
                    val returnedImage = uiAutomation.takeScreenshot()
                    java.io.File(targetContext.getExternalFilesDir(null), "source-cancelled.png").outputStream().use { returnedImage.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    returnedImage.recycle()
                }
                output.putString("stream", "$mode displayed; inspect screenshot and scoped player logs\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "playback" || mode == "playback-texture") {
                val pair = runBlocking {
                    val sources = org.kazumi.tv.rules.RuleRepository(targetContext)
                    val rule = sources.rules.first { it.name == "7sefun" }
                    val matches = sources.search(rule, "葬送的芙莉莲")
                    val match = matches.firstOrNull { it.title.trim() == "葬送的芙莉莲" } ?: matches.last()
                    val roads = sources.chapters(rule, match)
                    val request = org.kazumi.tv.playback.WebMediaResolver(targetContext).resolve(roads.last().episodes.first().pageUrl, rule, match.title)
                    val comments = DanmakuRepository(checkNotNull(DanmakuCredentialStore(targetContext).read())).comments(176170001L)
                    request to comments
                }
                val activity = startActivitySync(android.content.Intent(targetContext, MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                val ready = java.util.concurrent.CountDownLatch(1)
                var failed = false
                lateinit var engine: org.kazumi.tv.playback.NativePlayer
                lateinit var videoView: androidx.media3.ui.PlayerView
                runOnMainSync {
                    engine = org.kazumi.tv.playback.NativePlayer(activity)
                    engine.player.addListener(object : androidx.media3.common.Player.Listener {
                        override fun onRenderedFirstFrame() { ready.countDown() }
                        override fun onPlayerError(error: androidx.media3.common.PlaybackException) { failed = true; ready.countDown() }
                    })
                    val frame = android.widget.FrameLayout(activity)
                    videoView = (if (mode == "playback-texture") android.view.LayoutInflater.from(activity)
                        .inflate(org.kazumi.tv.R.layout.player_texture,null) as androidx.media3.ui.PlayerView
                        else org.kazumi.tv.ui.createPlaybackView(activity)).apply { player = engine.player; useController = false }
                    frame.addView(videoView, android.widget.FrameLayout.LayoutParams(-1, -1))
                    frame.addView(org.kazumi.tv.ui.DanmakuView(activity).apply { player = engine.player; timeline = org.kazumi.tv.playback.DanmakuTimeline(pair.second) }, android.widget.FrameLayout.LayoutParams(-1, -1))
                    activity.setContentView(frame)
                    engine.open(pair.first, 0)
                }
                try {
                    check(ready.await(20, java.util.concurrent.TimeUnit.SECONDS) && !failed)
                    Thread.sleep(8000)
                    var diagnostics = ""
                    runOnMainSync {
                        check(engine.player.duration > 600000) { "Expected a full episode, not short media" }
                        check(engine.player.currentPosition > 5000 && !failed) { "Playback did not advance" }
                        diagnostics = "duration=${engine.player.duration}; decoder=${engine.diagnostics.value}; frames=${engine.player.videoDecoderCounters?.renderedOutputBufferCount}; dropped=${engine.player.videoDecoderCounters?.droppedBufferCount}"
                        engine.player.seekTo(60000)
                    }
                    Thread.sleep(8000)
                    runOnMainSync { check(engine.player.currentPosition > 62000 && !failed) { "Seek did not resume" } }
                    val surfaceImage = android.graphics.Bitmap.createBitmap(960,540,android.graphics.Bitmap.Config.ARGB_8888)
                    val copied = java.util.concurrent.CountDownLatch(1)
                    var copyResult = -1
                    runOnMainSync {
                        val surface = videoView.videoSurfaceView as? android.view.SurfaceView
                        val texture = videoView.videoSurfaceView as? android.view.TextureView
                        if (texture != null) {
                            if(texture.getBitmap(surfaceImage) != null) copyResult = 0
                            copied.countDown()
                        } else if (surface == null) copied.countDown() else android.view.PixelCopy.request(surface,surfaceImage,
                            { result -> copyResult = result; copied.countDown() },android.os.Handler(android.os.Looper.getMainLooper()))
                    }
                    check(copied.await(5,java.util.concurrent.TimeUnit.SECONDS))
                    if (copyResult == android.view.PixelCopy.SUCCESS) {
                        java.io.File(targetContext.getExternalFilesDir(null),"tv-video-surface.png").outputStream().use { surfaceImage.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) }
                    }
                    surfaceImage.recycle()
                    val screenshot = uiAutomation.takeScreenshot()
                    java.io.File(targetContext.getExternalFilesDir(null), "tv-playback-danmaku.png").outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    screenshot.recycle()
                    runOnMainSync { output.putString("stream", "TV native playback first_frame=OK; position=${engine.player.currentPosition}; comments=${pair.second.size}; $diagnostics; pixel_copy=$copyResult; screenshot=tv-playback-danmaku.png\n") }
                } finally { runOnMainSync { engine.release() } }
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "sources") {
                val evidence = runBlocking {
                    val repository = org.kazumi.tv.rules.RuleRepository(targetContext)
                    repository.rules.map { rule ->
                        try {
                            val matches = repository.search(rule, "葬送的芙莉莲")
                            val roads = matches.firstOrNull()?.let { repository.chapters(rule, it) }.orEmpty()
                            "${rule.name}:matches=${matches.size},roads=${roads.size},episodes=${roads.sumOf { it.episodes.size }}"
                        } catch (error: Exception) { "${rule.name}:${error.javaClass.simpleName}" + if (error is IllegalStateException) ":${error.message}" else "" }
                    }.joinToString("; ")
                }
                output.putString("stream", evidence + "\n")
                finish(Activity.RESULT_OK, output); return
            }
            if (mode == "render") {
                runOnMainSync {
                    val player = androidx.media3.exoplayer.ExoPlayer.Builder(targetContext).build()
                    try {
                        val view = org.kazumi.tv.ui.DanmakuView(targetContext)
                        view.player = player
                        view.timeline = org.kazumi.tv.playback.DanmakuTimeline(listOf(DanmakuComment(1000, 5, -1, "KazumiTV 弹幕测试")))
                        view.layout(0, 0, 1920, 1080)
                        val bitmap = android.graphics.Bitmap.createBitmap(1920, 1080, android.graphics.Bitmap.Config.ARGB_8888)
                        player.seekTo(2000); view.draw(android.graphics.Canvas(bitmap))
                        val pixels = IntArray(1920 * 1080); bitmap.getPixels(pixels, 0, 1920, 0, 0, 1920, 1080)
                        check(pixels.any { it != 0 })
                        bitmap.eraseColor(0); player.seekTo(9000); view.draw(android.graphics.Canvas(bitmap))
                        bitmap.getPixels(pixels, 0, 1920, 0, 0, 1920, 1080)
                        check(pixels.all { it == 0 })
                        bitmap.recycle()
                    } finally { player.release() }
                }
                output.putString("stream", "TV overlay: pixels_drawn=OK; seek_clears_expired=OK\n")
                finish(Activity.RESULT_OK, output); return
            }
            runBlocking {
                val catalog = CatalogRepository()
                val found = catalog.search("frieren")
                check(found.isNotEmpty())
                check(catalog.detail(found.first().id).summary.isNotBlank())
                val credentials = checkNotNull(DanmakuCredentialStore(targetContext).read())
                val danmaku = DanmakuRepository(credentials)
                val episodes = danmaku.search("葬送的芙莉莲")
                check(episodes.isNotEmpty())
                val comments = danmaku.comments(episodes.first().id)
                check(comments.isNotEmpty())
                output.putString("stream", "TV search=${found.size}; detail=OK; encrypted_credentials=OK; danmaku_episodes=${episodes.size}; comments=${comments.size}\n")
            }
            finish(Activity.RESULT_OK, output)
        } catch (error: Exception) {
            output.putString("stream", "TV smoke FAILED: ${error.javaClass.simpleName} at ${error.stackTrace.take(5).joinToString()}\n")
            finish(Activity.RESULT_CANCELED, output)
        }
    }
}
