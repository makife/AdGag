package com.adgag.adgag.editor

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The sticker picker, shown in place of the timeline + tools (like the
 * text panel, never over the video). Opened from the "Stickers" tool it
 * ADDS the tapped sticker at the playhead; opened on an existing sticker
 * (tap it again on the video, or its timeline bar) it REPLACES that one and
 * offers Flip / Delete. Thumbnails are each sticker's first frame; the
 * animation plays on the video.
 */
@UnstableApi
@Composable
fun StickerPanel(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    BackHandler(onBack = onDismiss)
    val editing = editingId?.let { id -> viewModel.stickerLayers.firstOrNull { it.id == id } }
    val thumbs = remember { mutableStateMapOf<String, Bitmap>() }
    LaunchedEffect(Unit) {
        viewModel.stickers.all.forEach { def ->
            if (thumbs[def.id] == null) {
                withContext(Dispatchers.IO) { viewModel.stickers.thumbnail(def) }?.let { thumbs[def.id] = it }
            }
        }
    }

    Column {
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
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 60.dp),
            modifier = Modifier.fillMaxWidth().height(208.dp),
            contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
            verticalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            items(viewModel.stickers.all, key = { it.id }) { def ->
                val selected = editing?.stickerId == def.id
                Box(
                    modifier = Modifier
                        .size(60.dp)
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .background(if (selected) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .border(
                            BorderStroke(if (selected) 2.dp else 0.dp, if (selected) AdGagColors.GradientPink else AdGagColors.Surface),
                            RoundedCornerShape(AdGagRadius.sm.dp),
                        )
                        .clickable {
                            if (editing != null) {
                                viewModel.updateSticker(editing.copy(stickerId = def.id))
                            } else {
                                viewModel.addSticker(def)
                                onDismiss()
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    thumbs[def.id]?.let {
                        Image(bitmap = it.asImageBitmap(), contentDescription = def.label, modifier = Modifier.size(48.dp))
                    }
                }
            }
        }
        Text(
            text = "Animated emoji: Google Noto Emoji (CC BY 4.0)",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
        )
    }
}
