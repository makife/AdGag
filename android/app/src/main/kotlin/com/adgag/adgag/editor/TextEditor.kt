package com.adgag.adgag.editor

import android.graphics.DashPathEffect
import android.graphics.Paint
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateRotation
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableLongState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import kotlin.math.max
import kotlin.math.min

/** Output time at which a caption has finished entering (what's shown while it's selected and paused). */
private fun settledTimeMs(layer: TextLayer): Long {
    val entrance = max(TextRenderer.ENTRANCE_MS + 100, layer.text.length * 70L + 600)
    val lastSettled = max(layer.startMs, layer.endMs - TextRenderer.exitMsOf(layer) - 1)
    return min(layer.startMs + entrance, lastSettled)
}

/**
 * The captions over the preview video, laid out in the EXPORTED frame's
 * rectangle (fitted into the video area like the video itself), drawn by
 * the same [TextRenderer] as the export. Redrawn per frame without
 * recomposing (it reads [frameGlobalMs] only in the draw phase).
 *
 * Gestures: tap a caption to select it, tap it again to edit, drag to
 * move, pinch to resize, twist to rotate (two fingers also work on the
 * selected caption anywhere on the video). Tapping empty video
 * deselects, or toggles play/pause when nothing is selected.
 */
@UnstableApi
@Composable
fun TextOverlayLayer(
    viewModel: EditorViewModel,
    frameGlobalMs: MutableLongState,
    onEdit: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val onEditUpdated by rememberUpdatedState(onEdit)
    BoxWithConstraints(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val boxW = with(density) { maxWidth.toPx() }
        val boxH = with(density) { maxHeight.toPx() }
        val aspect = viewModel.outputAspect
        val (fw, fh) = if (boxW / boxH > aspect) boxH * aspect to boxH else boxW to boxW / aspect

        // Taps on the letterbox bars: same rule as empty video.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures(onTap = {
                        if (viewModel.selectedTextId != null) viewModel.selectedTextId = null else viewModel.togglePlayPause()
                    })
                },
        )
        Box(
            modifier = Modifier
                .size(with(density) { fw.toDp() }, with(density) { fh.toDp() })
                .drawBehind { drawCaptions(viewModel, frameGlobalMs.longValue) }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val w = size.width.toFloat()
                        val h = size.height.toFloat()
                        val tMs = (viewModel.globalPositionMs() / viewModel.videoSpeed).toLong()
                        fun shown(id: String, start: Long, end: Long) =
                            (tMs >= start && tMs < end) || (id == viewModel.selectedTextId && !viewModel.isPlaying)
                        // Captions are drawn over stickers, so they win the touch.
                        val hit = viewModel.textLayers.asReversed().firstOrNull { layer ->
                            shown(layer.id, layer.startMs, layer.endMs) &&
                                TextRenderer.hitTest(layer, w, h, down.position.x, down.position.y, viewModel.fonts)
                        }?.let { HitOverlay(it.id) } ?: viewModel.stickerLayers.asReversed().firstOrNull { layer ->
                            shown(layer.id, layer.startMs, layer.endMs) &&
                                StickerRenderer.hitTest(layer, w, h, down.position.x, down.position.y)
                        }?.let { HitOverlay(it.id) }
                        val wasSelected = hit != null && hit.id == viewModel.selectedTextId
                        if (hit != null) viewModel.selectedTextId = hit.id
                        var targetId = hit?.id
                        var moved = false
                        var travelled = Offset.Zero
                        do {
                            val event = awaitPointerEvent()
                            val pressed = event.changes.count { it.pressed }
                            if (targetId == null && pressed >= 2) targetId = viewModel.selectedTextId
                            val pan = event.calculatePan()
                            val zoom = event.calculateZoom()
                            val rotation = event.calculateRotation()
                            travelled += pan
                            if (!moved && (travelled.getDistance() > viewConfiguration.touchSlop || zoom != 1f || rotation != 0f)) {
                                moved = true
                            }
                            val id = targetId
                            if (id != null) {
                                if (moved) {
                                    viewModel.textLayers.firstOrNull { it.id == id }?.let { layer ->
                                        viewModel.updateText(
                                            layer.copy(
                                                x = (layer.x + pan.x / w).coerceIn(0f, 1f),
                                                y = (layer.y + pan.y / h).coerceIn(0f, 1f),
                                                scale = (layer.scale * zoom).coerceIn(0.2f, 8f),
                                                rotationDeg = layer.rotationDeg + rotation,
                                            ),
                                        )
                                    }
                                    viewModel.stickerLayers.firstOrNull { it.id == id }?.let { layer ->
                                        viewModel.updateSticker(
                                            layer.copy(
                                                x = (layer.x + pan.x / w).coerceIn(0f, 1f),
                                                y = (layer.y + pan.y / h).coerceIn(0f, 1f),
                                                scale = (layer.scale * zoom).coerceIn(0.2f, 8f),
                                                rotationDeg = layer.rotationDeg + rotation,
                                            ),
                                        )
                                    }
                                }
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        } while (event.changes.any { it.pressed })
                        if (!moved) {
                            when {
                                hit == null ->
                                    if (viewModel.selectedTextId != null) viewModel.selectedTextId = null else viewModel.togglePlayPause()
                                wasSelected -> onEditUpdated(hit.id)
                            }
                        }
                    }
                },
        )
    }
}

private data class HitOverlay(val id: String)

private val selectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = android.graphics.Color.WHITE
    pathEffect = DashPathEffect(floatArrayOf(18f, 12f), 0f)
}

@UnstableApi
private fun DrawScope.drawCaptions(viewModel: EditorViewModel, globalMs: Long) {
    val layers = viewModel.textLayers
    val stickers = viewModel.stickerLayers
    if (layers.isEmpty() && stickers.isEmpty()) return
    val tMs = (globalMs / viewModel.videoSpeed).toLong()
    val w = size.width
    val h = size.height
    val selected = viewModel.selectedTextId
    drawIntoCanvas { c ->
        val canvas = c.nativeCanvas
        // Stickers under the captions (same order as the export).
        stickers.forEach { layer ->
            val frozen = layer.id == selected && !viewModel.isPlaying && (tMs < layer.startMs || tMs >= layer.endMs)
            val t = if (frozen) minOf(layer.startMs + 400L, layer.endMs - 1) else tMs
            StickerRenderer.draw(canvas, layer, w, h, t, viewModel.stickers)
            if (layer.id == selected) {
                val half = StickerRenderer.halfSide(layer, h) * 1.1f
                canvas.save()
                canvas.translate(layer.x * w, layer.y * h)
                canvas.rotate(layer.rotationDeg)
                canvas.scale(layer.scale, layer.scale)
                selectionPaint.strokeWidth = 3f / layer.scale
                canvas.drawRoundRect(-half, -half, half, half, 12f / layer.scale, 12f / layer.scale, selectionPaint)
                canvas.restore()
            }
        }
        layers.forEach { layer ->
            val frozen = layer.id == selected && !viewModel.isPlaying
            val t = if (frozen) settledTimeMs(layer) else tMs
            TextRenderer.draw(canvas, layer, w, h, t, viewModel.fonts)
            if (layer.id == selected) {
                val bounds = TextRenderer.localBounds(TextRenderer.layout(layer, h, viewModel.fonts))
                canvas.save()
                canvas.translate(layer.x * w, layer.y * h)
                canvas.rotate(layer.rotationDeg)
                canvas.scale(layer.scale, layer.scale)
                selectionPaint.strokeWidth = 3f / layer.scale
                canvas.drawRoundRect(bounds, 12f / layer.scale, 12f / layer.scale, selectionPaint)
                canvas.restore()
            }
        }
    }
}

private enum class TextTab(val label: String) { FONT("Font"), STYLE("Style"), MOTION("In"), EXIT("Out"), COLOR("Color"), SIZE("Size") }

/**
 * Edits one caption: its words, then Font / Style / In / Out / Color / Size.
 * Shown IN PLACE of the timeline and tools (not as a sheet over the video
 * — a sheet covered part of it, user report), so the video just gets a
 * bit smaller and stays fully visible; every change shows there live.
 * Font/style/motion choices are live renders of the caption itself.
 */
@UnstableApi
@Composable
fun TextEditorPanel(viewModel: EditorViewModel, layerId: String, onDismiss: () -> Unit) {
    val layer = viewModel.textLayers.firstOrNull { it.id == layerId }
    if (layer == null) {
        LaunchedEffect(layerId) { onDismiss() }
        return
    }
    val close = {
        if (viewModel.textLayers.firstOrNull { it.id == layerId }?.text?.isBlank() == true) viewModel.removeText(layerId)
        onDismiss()
    }
    var tab by remember { mutableStateOf(TextTab.STYLE) }
    BackHandler(onBack = close)

    run {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text = "Text", color = AdGagColors.OnBackground, style = MaterialTheme.typography.titleMedium)
                Row {
                    TextButton(onClick = {
                        viewModel.removeText(layerId)
                        onDismiss()
                    }) {
                        Text(text = "Delete", color = AdGagColors.Danger, style = MaterialTheme.typography.labelLarge)
                    }
                    TextButton(onClick = close) {
                        Text(text = "Done", color = AdGagColors.GradientPink, style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
            OutlinedTextField(
                value = layer.text,
                onValueChange = { viewModel.updateText(layer.copy(text = it.take(120))) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                maxLines = 2,
                placeholder = { Text("Type something", color = AdGagColors.OnSurfaceMuted) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = AdGagColors.OnBackground,
                    unfocusedTextColor = AdGagColors.OnBackground,
                    focusedBorderColor = AdGagColors.GradientPink,
                    unfocusedBorderColor = AdGagColors.Border,
                    cursorColor = AdGagColors.GradientPink,
                ),
            )
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.xs.dp),
            ) {
                TextTab.entries.forEach { t ->
                    val on = t == tab
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                            .background(if (on) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                            .clickable { tab = t }
                            .padding(vertical = AdGagSpacing.sm.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = t.label,
                            color = if (on) AdGagColors.GradientPink else AdGagColors.OnBackground,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Box(modifier = Modifier.fillMaxWidth().height(116.dp)) {
                when (tab) {
                    TextTab.FONT -> PreviewChipRow(
                        viewModel = viewModel,
                        items = TextFonts.all,
                        isSelected = { it.id == layer.fontId },
                        previewOf = { font -> layer.copy(fontId = font.id, text = font.label, animation = TextAnimation.NONE) },
                        label = null,
                        animated = false,
                        onSelect = { viewModel.updateText(layer.copy(fontId = it.id)) },
                    )
                    TextTab.STYLE -> PreviewChipRow(
                        viewModel = viewModel,
                        items = TextStyleEffect.entries,
                        isSelected = { it == layer.style },
                        previewOf = { style -> layer.copy(style = style, text = "Aa", animation = TextAnimation.NONE) },
                        label = { it.label },
                        animated = false,
                        onSelect = { viewModel.updateText(layer.copy(style = it)) },
                    )
                    TextTab.MOTION -> PreviewChipRow(
                        viewModel = viewModel,
                        items = TextAnimation.entries,
                        isSelected = { it == layer.animation },
                        previewOf = { anim -> layer.copy(animation = anim, text = "Wow") },
                        label = { it.label },
                        animated = true,
                        onSelect = { viewModel.updateText(layer.copy(animation = it)) },
                    )
                    // Exits: each chip shows the word, then it leaving (looping).
                    TextTab.EXIT -> PreviewChipRow(
                        viewModel = viewModel,
                        items = TextExit.entries,
                        isSelected = { it == layer.exit },
                        previewOf = { exit -> layer.copy(exit = exit, text = "Bye", animation = TextAnimation.NONE) },
                        label = { it.label },
                        animated = true,
                        onSelect = { viewModel.updateText(layer.copy(exit = it)) },
                        previewEndMs = 1_600L,
                        loopMs = 2_100L,
                    )
                    TextTab.COLOR -> ColorTab(layer, onChange = { viewModel.updateText(it) })
                    TextTab.SIZE -> SizeTab(layer, onChange = { viewModel.updateText(it) })
                }
            }
        }
    }
}

/**
 * Horizontally scrolling chips, each a live render of the caption with one
 * option applied (so a font chip shows that font, a style chip that style
 * in the caption's colours, a motion chip that motion, looping).
 */
@UnstableApi
@Composable
private fun <T> PreviewChipRow(
    viewModel: EditorViewModel,
    items: List<T>,
    isSelected: (T) -> Boolean,
    previewOf: (T) -> TextLayer,
    label: ((T) -> String)?,
    animated: Boolean,
    onSelect: (T) -> Unit,
    /** Where the chip's caption ends (exit previews); otherwise it never ends. */
    previewEndMs: Long = Long.MAX_VALUE / 4,
    loopMs: Long = 2_400L,
) {
    val clock = remember { mutableLongStateOf(0L) }
    if (animated) {
        LaunchedEffect(Unit) {
            val start = withFrameMillis { it }
            while (true) {
                withFrameMillis { clock.longValue = it - start }
            }
        }
    }
    LazyRow(
        contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
    ) {
        items(items) { item ->
            val selected = isSelected(item)
            val preview = previewOf(item).copy(
                x = 0.5f, y = 0.5f, rotationDeg = 0f, scale = 1f, opacity = 1f,
                align = TextAlignment.CENTER, startMs = 0L, endMs = previewEndMs,
            )
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = Modifier
                        .size(width = if (label == null) 104.dp else 76.dp, height = if (label == null) 96.dp else 72.dp)
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .border(
                            BorderStroke(if (selected) 2.dp else 1.dp, if (selected) AdGagColors.GradientPink else AdGagColors.Border),
                            RoundedCornerShape(AdGagRadius.sm.dp),
                        )
                        .background(Color(0xFF2A2A30))
                        .clickable { onSelect(item) }
                        .drawBehind {
                            val t = if (animated) clock.longValue % loopMs else 10_000L
                            val sized = preview.copy(sizeFrac = 0.3f)
                            val layout = TextRenderer.layout(sized, size.height, viewModel.fonts)
                            val fit = min(1f, size.width * 0.72f / max(1f, layout.width))
                            drawIntoCanvas {
                                TextRenderer.draw(it.nativeCanvas, sized.copy(scale = fit), size.width, size.height, t, viewModel.fonts)
                            }
                        },
                )
                if (label != null) {
                    Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
                    Text(
                        text = label(item),
                        color = if (selected) AdGagColors.GradientPink else AdGagColors.OnSurfaceMuted,
                        style = MaterialTheme.typography.labelSmall,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun ColorTab(layer: TextLayer, onChange: (TextLayer) -> Unit) {
    // 0 = text colour, 1 = second colour (outline / glow / box / shadow / 3D).
    var target by remember { mutableIntStateOf(0) }
    val current = if (target == 0) layer.color else layer.accentColor
    fun set(color: Int) = onChange(if (target == 0) layer.copy(color = color) else layer.copy(accentColor = color))

    Column {
        Row(
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            listOf("Text", "Effect colour").forEachIndexed { i, name ->
                val on = i == target
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                        .background(if (on) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .clickable { target = i }
                        .padding(horizontal = AdGagSpacing.md.dp, vertical = AdGagSpacing.xs.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(Color(if (i == 0) layer.color else layer.accentColor)),
                    )
                    Spacer(modifier = Modifier.width(AdGagSpacing.xs.dp))
                    Text(text = name, color = if (on) AdGagColors.GradientPink else AdGagColors.OnBackground, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
        LazyRow(
            contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            items(TextPalette) { c ->
                Box(
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color(c))
                        .border(
                            BorderStroke(if (c == current) 3.dp else 1.dp, if (c == current) AdGagColors.GradientPink else AdGagColors.Border),
                            CircleShape,
                        )
                        .clickable { set(c) },
                )
            }
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
        // Full colour scale: drag along the spectrum (hue), plus white/black ends.
        SpectrumBar(onPick = ::set)
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        LabeledSlider("Opacity", layer.opacity, 0.1f..1f) { onChange(layer.copy(opacity = it)) }
    }
}

private val spectrumColors: List<Color> = listOf(
    Color.White, Color(0xFFFF1744), Color(0xFFFF9100), Color(0xFFFFEA00), Color(0xFF00E676),
    Color(0xFF00E5FF), Color(0xFF2979FF), Color(0xFFD500F9), Color(0xFFFF1744), Color.Black,
)

/** Colour at [f] (0..1) along [spectrumColors]. */
private fun spectrumAt(f: Float): Int {
    val x = f.coerceIn(0f, 1f) * (spectrumColors.size - 1)
    val i = x.toInt().coerceAtMost(spectrumColors.size - 2)
    val t = x - i
    val a = spectrumColors[i]
    val b = spectrumColors[i + 1]
    return android.graphics.Color.rgb(
        ((a.red + (b.red - a.red) * t) * 255).toInt(),
        ((a.green + (b.green - a.green) * t) * 255).toInt(),
        ((a.blue + (b.blue - a.blue) * t) * 255).toInt(),
    )
}

@Composable
private fun SpectrumBar(onPick: (Int) -> Unit) {
    val pick by rememberUpdatedState(onPick)
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = AdGagSpacing.lg.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(AdGagRadius.pill.dp))
            .background(Brush.horizontalGradient(spectrumColors)),
    ) {
        val widthPx = with(LocalDensity.current) { maxWidth.toPx() }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) { detectTapGestures { pick(spectrumAt(it.x / widthPx)) } }
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        change.consume()
                        pick(spectrumAt(change.position.x / widthPx))
                    }
                },
        )
    }
}

@Composable
private fun SizeTab(layer: TextLayer, onChange: (TextLayer) -> Unit) {
    Column {
        LabeledSlider("Size", layer.sizeFrac, 0.025f..0.2f) { onChange(layer.copy(sizeFrac = it)) }
        LabeledSlider("Letter spacing", layer.letterSpacing, -0.05f..0.6f) { onChange(layer.copy(letterSpacing = it)) }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextAlignment.entries.forEach { a ->
                val on = a == layer.align
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                        .background(if (on) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .clickable { onChange(layer.copy(align = a)) }
                        .padding(horizontal = AdGagSpacing.md.dp, vertical = AdGagSpacing.xs.dp),
                ) {
                    Text(
                        text = a.name.lowercase().replaceFirstChar { it.uppercase() },
                        color = if (on) AdGagColors.GradientPink else AdGagColors.OnBackground,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = { onChange(layer.copy(rotationDeg = 0f, scale = 1f, x = 0.5f)) }) {
                Text(text = "Straighten", color = AdGagColors.GradientPink, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun LabeledSlider(label: String, value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.width(96.dp),
        )
        Slider(
            value = value.coerceIn(range.start, range.endInclusive),
            onValueChange = onChange,
            valueRange = range,
            modifier = Modifier.weight(1f),
            colors = SliderDefaults.colors(thumbColor = AdGagColors.GradientPink, activeTrackColor = AdGagColors.GradientPink),
        )
    }
}
