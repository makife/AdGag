package com.adgag.adgag.editor

import android.graphics.Bitmap
import android.graphics.RectF
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The sticker picker, shown in place of the timeline + tools (never over
 * the video): the bundled animated emoji, every thumbnail animating.
 * Opened from the "Stickers" tool it ADDS the tapped sticker at the playhead; opened on an existing sticker it REPLACES that one and
 * offers Flip / Delete. The header (title + actions) is [StickerPanelHeader]
 * so the collapsible panel frame can keep it visible while collapsed.
 */
@UnstableApi
@Composable
fun StickerPanel(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    val editing = editingId?.let { id -> viewModel.stickerLayers.firstOrNull { it.id == id } }
    val pick = { def: StickerDef ->
        if (editing != null) {
            viewModel.updateSticker(editing.copy(stickerId = def.id))
        } else {
            viewModel.addSticker(def)
            onDismiss()
        }
    }

    EmojiGrid(viewModel, selectedId = editing?.stickerId, onPick = pick)
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
            text = if (editing != null) tr("Change sticker") else tr("Stickers"),
            color = AdGagColors.OnBackground,
            style = MaterialTheme.typography.titleMedium,
        )
        Row {
            if (editing != null) {
                TextButton(onClick = { viewModel.updateSticker(editing.copy(flipX = !editing.flipX)) }) {
                    Text(text = tr("Flip"), color = AdGagColors.OnBackground, style = MaterialTheme.typography.labelLarge)
                }
                TextButton(onClick = {
                    viewModel.removeSticker(editing.id)
                    onDismiss()
                }) {
                    Text(text = tr("Delete"), color = AdGagColors.Danger, style = MaterialTheme.typography.labelLarge)
                }
            }
            TextButton(onClick = onDismiss) {
                Text(text = tr("Done"), color = AdGagColors.Accent, style = MaterialTheme.typography.labelLarge)
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
                        .background(if (selected) AdGagColors.Accent.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .border(
                            BorderStroke(if (selected) 2.dp else 0.dp, if (selected) AdGagColors.Accent else AdGagColors.Surface),
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
            text = tr("Animated emoji: Google Noto Emoji (CC BY 4.0)"),
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
        )
    }
}
