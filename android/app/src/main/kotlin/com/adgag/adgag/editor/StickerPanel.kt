package com.adgag.adgag.editor

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.RectF
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.widget.ImageView
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer

private enum class StickerSource(val label: String) { EMOJI("Emoji"), GIPHY("GIPHY") }

/**
 * The sticker picker, shown in place of the timeline + tools (never over
 * the video). Two sources: the bundled animated emoji, and GIPHY search
 * (stickers or GIFs; trending when the search is empty). Every thumbnail
 * animates. Opened from the "Stickers" tool it ADDS the tapped sticker at
 * the playhead; opened on an existing sticker it REPLACES that one and
 * offers Flip / Delete. The header (title + actions) is [StickerPanelHeader]
 * so the collapsible panel frame can keep it visible while collapsed.
 */
@UnstableApi
@Composable
fun StickerPanel(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    var source by remember { mutableStateOf(StickerSource.EMOJI) }
    val editing = editingId?.let { id -> viewModel.stickerLayers.firstOrNull { it.id == id } }
    val pick = { def: StickerDef ->
        if (editing != null) {
            viewModel.updateSticker(editing.copy(stickerId = def.id))
        } else {
            viewModel.addSticker(def)
            onDismiss()
        }
    }

    Column {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.xs.dp),
        ) {
            StickerSource.entries.forEach { s ->
                val on = s == source
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                        .background(if (on) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .clickable { source = s }
                        .padding(vertical = AdGagSpacing.sm.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = s.label,
                        color = if (on) AdGagColors.GradientPink else AdGagColors.OnBackground,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
        when (source) {
            StickerSource.EMOJI -> EmojiGrid(viewModel, selectedId = editing?.stickerId, onPick = pick)
            StickerSource.GIPHY -> GiphyGrid(viewModel, onPick = pick)
        }
    }
}

/** Title + Flip / Delete / Done — stays visible when the panel is collapsed. */
@UnstableApi
@Composable
fun StickerPanelHeader(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    val editing = editingId?.let { id -> viewModel.stickerLayers.firstOrNull { it.id == id } }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (editing != null) "Change sticker" else "Stickers",
            color = AdGagColors.OnBackground,
            style = MaterialTheme.typography.titleMedium,
        )
        Row {
            if (editing != null) {
                TextButton(onClick = { viewModel.updateSticker(editing.copy(flipX = !editing.flipX)) }) {
                    Text(text = "Flip", color = AdGagColors.OnBackground, style = MaterialTheme.typography.labelLarge)
                }
                TextButton(onClick = {
                    viewModel.removeSticker(editing.id)
                    onDismiss()
                }) {
                    Text(text = "Delete", color = AdGagColors.Danger, style = MaterialTheme.typography.labelLarge)
                }
            }
            TextButton(onClick = onDismiss) {
                Text(text = "Done", color = AdGagColors.GradientPink, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** Bundled emoji, animated: half-resolution sheets are decoded in the background as cells appear. */
@UnstableApi
@Composable
private fun EmojiGrid(viewModel: EditorViewModel, selectedId: String?, onPick: (StickerDef) -> Unit) {
    val store = viewModel.stickers
    val clock = remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        val start = withFrameMillis { it }
        while (true) withFrameMillis { clock.longValue = it - start }
    }
    val thumbs = remember { mutableStateMapOf<String, Bitmap>() }
    Column {
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 60.dp),
            modifier = Modifier.fillMaxWidth().height(196.dp),
            contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.sm.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
            verticalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            items(store.all, key = { it.id }) { def ->
                var loaded by remember { mutableIntStateOf(0) }
                LaunchedEffect(def.id) {
                    withContext(Dispatchers.IO) { store.thumbnail(def) }?.let { thumbs[def.id] = it }
                    withContext(Dispatchers.IO) { store.sheet(def, 2) }
                    loaded++
                }
                val selected = selectedId == def.id
                Box(
                    modifier = Modifier
                        .size(60.dp)
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .background(if (selected) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .border(
                            BorderStroke(if (selected) 2.dp else 0.dp, if (selected) AdGagColors.GradientPink else AdGagColors.Surface),
                            RoundedCornerShape(AdGagRadius.sm.dp),
                        )
                        .clickable { onPick(def) }
                        .drawBehind {
                            @Suppress("UNUSED_EXPRESSION") loaded
                            val inset = size.width * 0.1f
                            val dst = RectF(inset, inset, size.width - inset, size.height - inset)
                            val sheet = store.cachedSheet(def, 2)
                            drawIntoCanvas { c ->
                                if (sheet != null) {
                                    StickerRenderer.drawFrame(c.nativeCanvas, def, sheet, def.frameAt(clock.longValue), dst)
                                } else {
                                    thumbs[def.id]?.let { t -> StickerRenderer.drawFrame(c.nativeCanvas, def.copy(cols = 1), t, 0, dst) }
                                }
                            }
                        },
                )
            }
        }
        Text(
            text = "Animated emoji: Google Noto Emoji (CC BY 4.0)",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
        )
    }
}

@UnstableApi
@Composable
private fun GiphyGrid(viewModel: EditorViewModel, onPick: (StickerDef) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var kind by remember { mutableStateOf(GiphyKind.STICKERS) }
    var query by remember { mutableStateOf("") }
    var submitted by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<GiphyItem>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var importing by remember { mutableStateOf<String?>(null) }

    if (GiphyConfig.apiKey.isBlank()) {
        Text(
            text = "GIPHY search isn't set up yet (no GIPHY_API_KEY in this build).",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(AdGagSpacing.lg.dp),
        )
        return
    }

    LaunchedEffect(kind, submitted) {
        // A short pause so fast typing + Search doesn't fire several requests.
        delay(150)
        loading = true
        error = null
        results = runCatching { Giphy.search(kind, submitted) }
            .onFailure { error = it.message ?: "Couldn't reach GIPHY" }
            .getOrDefault(emptyList())
        loading = false
    }

    Column {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(50) },
                modifier = Modifier.weight(1f).height(52.dp),
                singleLine = true,
                placeholder = { Text("Search GIPHY", color = AdGagColors.OnSurfaceMuted) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { submitted = query }),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = AdGagColors.OnBackground,
                    unfocusedTextColor = AdGagColors.OnBackground,
                    focusedBorderColor = AdGagColors.GradientPink,
                    unfocusedBorderColor = AdGagColors.Border,
                    cursorColor = AdGagColors.GradientPink,
                ),
            )
            GiphyKind.entries.forEach { k ->
                val on = k == kind
                Text(
                    text = k.label,
                    color = if (on) AdGagColors.GradientPink else AdGagColors.OnBackground,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier
                        .padding(start = AdGagSpacing.xs.dp)
                        .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                        .background(if (on) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .clickable { kind = k }
                        .padding(horizontal = AdGagSpacing.sm.dp, vertical = AdGagSpacing.xs.dp),
                )
            }
        }
        Box(modifier = Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
            when {
                loading -> CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp, color = AdGagColors.GradientPink)
                error != null -> Text(text = error ?: "", color = AdGagColors.Danger, style = MaterialTheme.typography.bodySmall)
                results.isEmpty() -> Text(text = "Nothing found", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.bodySmall)
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 76.dp),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
                    horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
                    verticalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
                ) {
                    items(results, key = { it.id }) { item ->
                        Box(
                            modifier = Modifier
                                .size(76.dp)
                                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                                .background(AdGagColors.Surface)
                                .clickable(enabled = importing == null) {
                                    importing = item.id
                                    scope.launch {
                                        runCatching { Giphy.import(context, item) }
                                            .onSuccess {
                                                viewModel.stickers.registerLocal(it)
                                                onPick(it)
                                            }
                                            .onFailure { error = "Couldn't add that one: ${it.message}" }
                                        importing = null
                                    }
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            AnimatedGif(url = item.previewUrl)
                            if (importing == item.id) {
                                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = AdGagColors.GradientPink)
                            }
                        }
                    }
                }
            }
        }
        // GIPHY's attribution requirement.
        Text(
            text = "Powered by GIPHY",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp).width(200.dp),
        )
    }
}

/** An animated GIF thumbnail (AnimatedImageDrawable on API 28+, first frame before). */
@Composable
private fun AnimatedGif(url: String) {
    var drawable by remember(url) { mutableStateOf<Drawable?>(null) }
    val context = LocalContext.current
    LaunchedEffect(url) {
        drawable = runCatching {
            val bytes = Giphy.bytes(url)
            withContext(Dispatchers.Default) {
                if (Build.VERSION.SDK_INT >= 28) {
                    ImageDecoder.decodeDrawable(ImageDecoder.createSource(ByteBuffer.wrap(bytes)))
                } else {
                    BitmapDrawable(context.resources, BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
                }
            }
        }.getOrNull()
    }
    AndroidView(
        factory = { ImageView(it).apply { scaleType = ImageView.ScaleType.FIT_CENTER } },
        modifier = Modifier.fillMaxSize().padding(4.dp),
        update = { view ->
            view.setImageDrawable(drawable)
            if (Build.VERSION.SDK_INT >= 28) (drawable as? AnimatedImageDrawable)?.start()
        },
    )
}
