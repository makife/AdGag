// ADGAG PATCH — live AR face effects (not part of upstream camera_android_camerax).
// See PATCH_NOTES.md, "Live AR".
package io.flutter.plugins.camerax

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.PointF
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.camera.core.CameraEffect
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.UseCase
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.effects.OverlayEffect
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.video.VideoCapture
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.hypot

/**
 * Live AR: ML Kit finds faces in an ImageAnalysis stream, and a CameraX
 * [OverlayEffect] draws the chosen effect on the camera frames themselves —
 * so the SAME pixels show in the preview and end up in the recording.
 *
 * Wiring (all ADGAG PATCH): the app picks an effect over the "adgag/ar"
 * channel ([attach]); if one is picked when the camera is bound,
 * ProcessCameraProviderProxyApi.bindToLifecycle binds through [buildGroup]
 * (Preview + VideoCapture + our ImageAnalysis + the effect). Switching
 * between effects needs no rebind (the draw listener reads
 * [currentEffect]); turning AR on for a camera bound without it needs the
 * app to reopen the camera. With the effect in the pipeline CameraX hands
 * the preview a GL-processed buffer, so the app shows the preview texture
 * itself using [previewInfo] (rotation/mirroring from CameraX) instead of
 * the plugin's rotation guesswork.
 *
 * Coordinates: faces are reported in SENSOR coordinates
 * (MlKitAnalyzer COORDINATE_SYSTEM_SENSOR) and drawn after
 * canvas.setMatrix(frame.sensorToBufferTransform) — the mapping CameraX
 * documents for exactly this.
 */
object AdGagAr {
    private const val TAG = "AdGagAr"

    /** Effect to draw now (null = nothing). Read on the GL thread every frame. */
    @Volatile
    var currentEffect: String? = null
        private set

    /** Latest detected faces (sensor coordinates) and when (frame timestamp, ns). */
    @Volatile
    private var faces: List<FaceGeom> = emptyList()

    @Volatile
    private var facesAtNanos: Long = 0L

    /** True while a camera is bound through [buildGroup] (the AR pipeline is live). */
    @Volatile
    var pipelineBound: Boolean = false
        private set

    /** The last preview SurfaceRequest's transformation (see [previewInfo]). */
    @Volatile
    private var previewTransform: Map<String, Any>? = null

    private var effect: OverlayEffect? = null
    private var detector: FaceDetector? = null
    private val glThread: HandlerThread by lazy { HandlerThread("AdGagArGl").apply { start() } }
    private val analysisExecutor by lazy { Executors.newSingleThreadExecutor() }

    /** Whether the overlay texture currently holds a drawing (so it must be cleared once). */
    private var overlayDirty = false

    /** Per-face smoothing, keyed by ML Kit tracking id. */
    private val smoothed = HashMap<Int, FaceGeom>()

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "adgag/ar").setMethodCallHandler { call, result ->
            when (call.method) {
                "setEffect" -> {
                    currentEffect = call.argument<String>("id")
                    result.success(null)
                }
                "isPipelineBound" -> result.success(pipelineBound)
                "previewInfo" -> result.success(previewTransform)
                else -> result.notImplemented()
            }
        }
    }

    /** Called by ProcessCameraProviderProxyApi: bind with AR when an effect is picked. */
    @JvmStatic
    fun shouldBindWithAr(useCases: List<UseCase>): Boolean =
        currentEffect != null && useCases.any { it is Preview } && useCases.any { it is VideoCapture<*> }

    /** Preview + VideoCapture (+ anything else passed) + face analysis + the overlay effect. */
    @JvmStatic
    fun buildGroup(context: Context, useCases: List<UseCase>): UseCaseGroup {
        effect?.close()
        val overlay = OverlayEffect(
            CameraEffect.PREVIEW or CameraEffect.VIDEO_CAPTURE,
            0, // draw each frame at once with the latest faces (no queue, no added latency)
            Handler(glThread.looper),
        ) { t -> Log.e(TAG, "OverlayEffect error", t) }
        overlay.setOnDrawListener { frame ->
            // frame.overlayCanvas locks the overlay surface: only touched to draw or clear.
            drawFrame(frame.sensorToBufferTransform, frame.timestampNanos) { frame.overlayCanvas }
            true
        }
        effect = overlay

        val faceDetector = detector ?: FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setMinFaceSize(0.12f)
                .enableTracking()
                .build(),
        ).also { detector = it }

        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
                    .build(),
            )
            .build()
        analysis.setAnalyzer(
            analysisExecutor,
            MlKitAnalyzer(listOf(faceDetector), ImageAnalysis.COORDINATE_SYSTEM_SENSOR, analysisExecutor) { result ->
                val found = result.getValue(faceDetector)
                if (found != null) onFaces(found, result.timestamp)
            },
        )

        val builder = UseCaseGroup.Builder()
        useCases.forEach { builder.addUseCase(it) }
        builder.addUseCase(analysis)
        builder.addEffect(overlay)
        pipelineBound = true
        return builder.build()
    }

    /** ProcessCameraProviderProxyApi.unbindAll / an ordinary bind: the AR pipeline is gone. */
    @JvmStatic
    fun onUnbound() {
        pipelineBound = false
        previewTransform = null
        faces = emptyList()
        analysisExecutor.execute { smoothed.clear() } // smoothed belongs to the analysis thread
    }

    /** PreviewProxyApi: remember how the app must show the preview buffer. */
    @JvmStatic
    fun onPreviewSurfaceRequest(request: SurfaceRequest) {
        request.setTransformationInfoListener(analysisExecutor) { info ->
            previewTransform = mapOf(
                "rotationDegrees" to info.rotationDegrees,
                "mirroring" to info.isMirroring,
                "hasCameraTransform" to info.hasCameraTransform(),
                "width" to request.resolution.width,
                "height" to request.resolution.height,
            )
        }
    }

    private fun onFaces(found: List<Face>, timestampNanos: Long) {
        val next = ArrayList<FaceGeom>(found.size)
        val seen = HashSet<Int>()
        for (face in found.take(3)) {
            val raw = FaceGeom.of(face) ?: continue
            val id = face.trackingId
            val geom = if (id != null) {
                seen += id
                val prev = smoothed[id]
                val g = if (prev == null) raw else prev.lerp(raw, 0.55f)
                smoothed[id] = g
                g
            } else {
                raw
            }
            next += geom
        }
        smoothed.keys.retainAll(seen)
        faces = next
        facesAtNanos = timestampNanos
    }

    private fun drawFrame(sensorToBuffer: Matrix, frameNanos: Long, canvas: () -> Canvas) {
        val effectId = currentEffect
        val current = faces
        val fresh = kotlin.math.abs(frameNanos - facesAtNanos) < 500_000_000L
        if (effectId == null || current.isEmpty() || !fresh) {
            if (overlayDirty) {
                canvas().drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
                overlayDirty = false
            }
            return
        }
        val c = canvas()
        c.drawColor(android.graphics.Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR)
        c.save()
        c.setMatrix(sensorToBuffer)
        for (face in current) {
            c.save()
            c.concat(face.localToSensor())
            ArEffects.draw(c, effectId, face)
            c.restore()
        }
        c.restore()
        overlayDirty = true
    }
}

/**
 * One face in sensor coordinates: eye centres, nose base, mouth centre.
 * [localToSensor] builds the face's own frame — origin between the eyes,
 * 1 unit = eye distance, +x toward one eye, +y down the face (toward the
 * mouth) — so effects are drawn once, in face units, at any size/tilt.
 */
data class FaceGeom(val leftEye: PointF, val rightEye: PointF, val nose: PointF, val mouth: PointF) {
    fun lerp(to: FaceGeom, t: Float) = FaceGeom(
        mix(leftEye, to.leftEye, t), mix(rightEye, to.rightEye, t), mix(nose, to.nose, t), mix(mouth, to.mouth, t),
    )

    fun localToSensor(): Matrix {
        val mx = (leftEye.x + rightEye.x) / 2f
        val my = (leftEye.y + rightEye.y) / 2f
        val e = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y).coerceAtLeast(1f)
        // "Down" = from between the eyes toward the mouth.
        var dx = mouth.x - mx
        var dy = mouth.y - my
        val dl = hypot(dx, dy).coerceAtLeast(1e-3f)
        dx /= dl
        dy /= dl
        // Right vector = down rotated -90°, so the frame is a pure rotation (no flip).
        val rx = dy
        val ry = -dx
        return Matrix().apply {
            setValues(floatArrayOf(rx * e, dx * e, mx, ry * e, dy * e, my, 0f, 0f, 1f))
        }
    }

    /** [p] (sensor coordinates) in this face's units. */
    fun toLocal(p: PointF): PointF {
        val inv = Matrix()
        localToSensor().invert(inv)
        val pts = floatArrayOf(p.x, p.y)
        inv.mapPoints(pts)
        return PointF(pts[0], pts[1])
    }

    companion object {
        fun of(face: Face): FaceGeom? {
            val l = face.getLandmark(FaceLandmark.LEFT_EYE)?.position ?: return null
            val r = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position ?: return null
            val box = face.boundingBox
            val nose = face.getLandmark(FaceLandmark.NOSE_BASE)?.position
                ?: PointF(box.exactCenterX(), box.exactCenterY())
            val mouth = face.getLandmark(FaceLandmark.MOUTH_BOTTOM)?.position
                ?: face.getLandmark(FaceLandmark.MOUTH_LEFT)?.position?.let { ml ->
                    face.getLandmark(FaceLandmark.MOUTH_RIGHT)?.position?.let { mr -> PointF((ml.x + mr.x) / 2, (ml.y + mr.y) / 2) }
                }
                ?: PointF(box.exactCenterX(), box.bottom.toFloat())
            return FaceGeom(PointF(l.x, l.y), PointF(r.x, r.y), PointF(nose.x, nose.y), PointF(mouth.x, mouth.y))
        }

        private fun mix(a: PointF, b: PointF, t: Float) = PointF(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
}
