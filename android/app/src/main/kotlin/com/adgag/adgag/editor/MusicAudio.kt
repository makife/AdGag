package com.adgag.adgag.editor

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.SpeedParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import java.nio.ByteBuffer
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** A speed that never changes — Media3's SpeedProvider for a whole item. */
@UnstableApi
class ConstantSpeedProvider(private val speed: Float) : SpeedProvider {
    override fun getSpeed(timeUs: Long): Float = speed
    override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
}

/**
 * Linear fade-in over the first [fadeInMs] and fade-out over the last
 * [fadeOutMs] of a [totalMs]-long stream, counted from the first sample
 * this processor sees (the music item is clipped to exactly the used
 * part, so sample 0 = where the music starts in the Ad). Deliberately
 * NOT Media3's GainProcessor: that one positions itself from the
 * stream's position offset after a flush, and what that offset is for a
 * clipped item inside a Transformer sequence is an internal detail.
 */
@UnstableApi
class MusicFadeAudioProcessor(
    private val fadeInMs: Long,
    private val fadeOutMs: Long,
    private val totalMs: Long,
) : BaseAudioProcessor() {
    private var frames = 0L

    override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException("Expected 16-bit or float PCM.", inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun isActive(): Boolean = super.isActive() && (fadeInMs > 0 || fadeOutMs > 0)

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        val format = inputAudioFormat
        val out = replaceOutputBuffer(inputBuffer.remaining())
        while (inputBuffer.hasRemaining()) {
            val ms = frames * 1000 / format.sampleRate
            val gain = fadeGain(ms, fadeInMs, fadeOutMs, totalMs)
            repeat(format.channelCount) {
                if (format.encoding == C.ENCODING_PCM_16BIT) {
                    out.putShort((inputBuffer.getShort() * gain).toInt().toShort())
                } else {
                    out.putFloat(inputBuffer.getFloat() * gain)
                }
            }
            frames++
        }
        out.flip()
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        frames = 0
    }

    override fun onReset() {
        frames = 0
    }
}

/** The music's volume at [ms] into its used part — shared by the preview (player volume) and the export processor. */
fun fadeGain(ms: Long, fadeInMs: Long, fadeOutMs: Long, totalMs: Long): Float {
    var g = 1f
    if (fadeInMs > 0 && ms < fadeInMs) g = minOf(g, ms.toFloat() / fadeInMs)
    val remaining = totalMs - ms
    if (fadeOutMs > 0 && remaining < fadeOutMs) g = minOf(g, remaining.toFloat() / fadeOutMs)
    return g.coerceIn(0f, 1f)
}

/**
 * Writes [input] re-timed to [speed] (pitch kept) as a new AAC file and
 * returns its path — used so the preview player and the export can both
 * just play an already-sped-up/slowed-down song. Must be called from the
 * main thread (Transformer needs a Looper; its callbacks come back here).
 */
@UnstableApi
@androidx.annotation.OptIn(ExperimentalApi::class)
suspend fun bakeMusicSpeed(context: Context, input: String, speed: Float): String {
    val output = File(context.filesDir, "editor_music_${System.currentTimeMillis()}_x$speed.m4a")
    val inputUri = Uri.fromFile(File(input))
    val item = EditedMediaItem.Builder(MediaItem.fromUri(inputUri))
        .setRemoveVideo(true)
        .setSpeed(SpeedParameters(ConstantSpeedProvider(speed), /* shouldMaintainPitch = */ true))
        .apply { EditorViewModel.probeDurationUs(context, inputUri)?.let { setDurationUs(it) } }
        .build()
    val composition = Composition.Builder(
        ImmutableList.of(EditedMediaItemSequence.withAudioFrom(ImmutableList.of(item))),
    ).build()
    return suspendCancellableCoroutine { cont ->
        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    cont.resume(output.absolutePath)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    output.delete()
                    cont.resumeWithException(exportException)
                }
            })
            .build()
        transformer.start(composition, output.absolutePath)
        cont.invokeOnCancellation { transformer.cancel() }
    }
}
