package com.danjjohnson.compress_video

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * A started (D-16), main-thread-confined `mediaProcessing` foreground service hosting every
 * opted-in compression job behind a ref count: the first [attach] starts it, every later
 * [attach] refreshes its notification with the current hosted-job count, and the [detach] that
 * empties the count stops it (D-09). No AndroidX Core notification-compatibility helper is used
 * here -- `Notification.Builder`/`NotificationChannel` are the platform's own classes,
 * unconditionally available at API 35+ (the only level this service ever runs at, D-08), and
 * `android/build.gradle.kts` declares no direct dependency on that support library for a wrapper
 * whose only job here is building a notification a compatibility shim buys nothing for.
 *
 * [attach]/[detach] are called from [Compression.startCompress], which already asserts the main
 * Looper before doing anything -- the same confinement discipline [JobRegistry] uses, and for
 * the same reason: no lock and no cross-thread mutable state.
 *
 * The companion delegates its bookkeeping to [Ref], a plain Kotlin class with no Android
 * framework import, so [ForegroundServiceHostTest] can prove ref-counting and the whole
 * [onTimeout] contract on plain JVM -- no Robolectric, no real [Service] instance, no emulator.
 */
class ForegroundServiceHost : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        // The channel must exist BEFORE the notification referencing it is posted -- an
        // unknown channel id makes the system kill the whole process with
        // CannotPostForegroundServiceNotificationException ("invalid channel for service
        // notification"), confirmed live on the API 35 emulator.
        ensureNotificationChannel()
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING,
        )
        return START_NOT_STICKY
    }

    /**
     * The system's six-hour-per-24h foreground-service quota expiry (D-09), API 35+ only. The
     * whole body: cancel every hosted job through [Ref.onTimeout] with the retryable
     * [REASON_INTERRUPTED], then stop -- no filesystem work, no logging round-trip, nothing that
     * can block (05-RESEARCH.md Pitfall 5). Omitting the stop is the documented path to an ANR
     * naming this service (05-RESEARCH.md Anti-Patterns); [Ref.onTimeout] always calls [stop]
     * unconditionally, even with zero hosted jobs, so that can never happen from this override.
     */
    override fun onTimeout(
        startId: Int,
        fgsType: Int,
    ) {
        ref.onTimeout(
            cancel = { jobId -> JobRegistry.cancel(jobId, REASON_INTERRUPTED) },
            stop = { stopSelf(startId) },
        )
    }

    private fun ensureNotificationChannel(): NotificationManager {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW),
            )
        }
        return manager
    }

    private fun refreshNotification() {
        val manager = ensureNotificationChannel()
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val options = latestOptions
        val hostedCount = ref.hostedCount
        val title = options?.notificationTitle?.takeIf { it.isNotBlank() } ?: DEFAULT_TITLE
        val text =
            options?.notificationText?.takeIf { it.isNotBlank() }
                ?: if (hostedCount == 1) "1 video" else "$hostedCount videos"
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(resolveIcon(options?.notificationIconResourceName))
            .setOngoing(true)
            .build()
    }

    /**
     * Resolves [name] against this app's own resources by name (T-05-14): a caller that
     * supplies nothing, or a name this app does not have, still gets a valid notification
     * rather than a crash.
     */
    private fun resolveIcon(name: String?): Int {
        if (name != null) {
            val resId = resources.getIdentifier(name, "drawable", packageName)
            if (resId != 0) {
                return resId
            }
        }
        return android.R.drawable.stat_sys_download
    }

    companion object {
        private const val CHANNEL_ID = "compress_video_media_processing"
        private const val CHANNEL_NAME = "Video compression"
        private const val DEFAULT_TITLE = "Compressing video"
        private const val NOTIFICATION_ID = 4200

        /** The retryable reason [onTimeout] cancels every hosted job with (D-09). */
        internal const val REASON_INTERRUPTED = "interrupted"

        private var instance: ForegroundServiceHost? = null
        private var latestOptions: AndroidForegroundServiceOptionsMessage? = null

        /** The framework-free hosted-job bookkeeping this companion delegates to. */
        internal val ref = Ref()

        /**
         * No-op below API 35 (D-08) -- no service starts and no permission is exercised. At or
         * above it, the first attach starts the service; every attach after that refreshes the
         * notification with the current hosted count.
         */
        fun attach(
            context: Context,
            jobId: String,
            options: AndroidForegroundServiceOptionsMessage,
        ) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                return
            }
            latestOptions = options
            val wasEmpty = ref.hostedCount == 0
            ref.attach(jobId)
            if (wasEmpty) {
                context.startForegroundService(Intent(context, ForegroundServiceHost::class.java))
            } else {
                instance?.refreshNotification()
            }
        }

        /**
         * No-op below API 35, and a no-op for an unknown [jobId]. Stops the service once the
         * last hosted job detaches (D-09) -- called from a `finally` around the engine call in
         * [Compression.startCompress], so success, a thrown typed error, and cancellation all
         * release it (T-05-12).
         */
        fun detach(jobId: String) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                return
            }
            val shouldStop = ref.detach(jobId)
            if (shouldStop) {
                instance?.stopSelf()
            }
        }
    }

    /**
     * Pure, Android-framework-free ref-counted bookkeeping of hosted job ids -- extracted so
     * [ForegroundServiceHostTest] can prove attach/detach counting and [onTimeout]'s cancel-all
     * behaviour on plain JVM, with no Robolectric and no real [Service] instance.
     */
    internal class Ref {
        private val hostedJobIds = LinkedHashSet<String>()

        /** The number of jobs currently hosted. */
        val hostedCount: Int
            get() = hostedJobIds.size

        /** Adds [jobId]. Safe to call more than once for the same id (a no-op the second time). */
        fun attach(jobId: String) {
            hostedJobIds.add(jobId)
        }

        /**
         * Removes [jobId] and returns whether that was the last hosted job -- the caller should
         * stop the service in that case. A no-op (returns `false`) for an unknown [jobId], and
         * for a [jobId] that was already detached.
         */
        fun detach(jobId: String): Boolean {
            if (!hostedJobIds.remove(jobId)) {
                return false
            }
            return hostedJobIds.isEmpty()
        }

        /**
         * Mirrors [Service.onTimeout]'s whole contract on plain JVM: invokes [cancel] for every
         * currently hosted job id, clears them, then unconditionally invokes [stop] -- even with
         * zero hosted jobs, matching the real override's unconditional `stopSelf` (never return
         * from `onTimeout` without stopping, 05-RESEARCH.md Anti-Patterns).
         */
        fun onTimeout(
            cancel: (String) -> Unit,
            stop: () -> Unit,
        ) {
            for (jobId in hostedJobIds.toList()) {
                cancel(jobId)
            }
            hostedJobIds.clear()
            stop()
        }
    }
}
