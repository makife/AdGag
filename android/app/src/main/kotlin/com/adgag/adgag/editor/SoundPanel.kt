package com.adgag.adgag.editor

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi

/**
 * The sound-effect picker, shown in place of the timeline + tools (like
 * the sticker picker). Category chips, then every effect as a card: tap a
 * card to HEAR it, tap its + to add it at the playhead. Opened on an
 * existing effect, + REPLACES that one instead. The header is
 * [SoundPanelHeader] so the collapsed panel keeps it visible.
 */
@UnstableApi
@Composable
fun SoundPanel(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    val editing = editingId?.let { id -> viewModel.soundLayers.firstOrNull { it.id == id } }
    val store = viewModel.sfx
    var category by remember { mutableStateOf<String?>(null) }
    val shown = store.all.filter { category == null || it.category == category }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = AdGagSpacing.lg.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            CategoryChip(label = "All", selected = category == null) { category = null }
            store.categories.forEach { c -> CategoryChip(label = c, selected = category == c) { category = c } }
        }
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 104.dp),
            modifier = Modifier.fillMaxWidth().height(196.dp),
            contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.sm.dp),
            horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
            verticalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
        ) {
            items(shown, key = { it.id }) { def ->
                val selected = editing?.sfxId == def.id
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .background(if (selected) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface)
                        .border(
                            BorderStroke(if (selected) 2.dp else 0.dp, if (selected) AdGagColors.GradientPink else AdGagColors.Surface),
                            RoundedCornerShape(AdGagRadius.sm.dp),
                        )
                        .clickable { viewModel.sfxPlayer.play(def) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = "Listen",
                        tint = AdGagColors.OnSurfaceMuted,
                        modifier = Modifier.padding(start = 6.dp).size(16.dp),
                    )
                    Column(modifier = Modifier.weight(1f).padding(horizontal = 4.dp)) {
                        Text(
                            text = def.label,
                            color = AdGagColors.OnBackground,
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = formatPreciseSeconds(def.durationMs),
                            color = AdGagColors.OnSurfaceMuted,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                    Icon(
                        imageVector = Icons.Filled.Add,
                        contentDescription = if (editing != null) "Use this sound" else "Add",
                        tint = AdGagColors.OnBackground,
                        modifier = Modifier
                            .size(48.dp)
                            .clickable {
                                if (editing != null) {
                                    viewModel.updateSound(editing.copy(sfxId = def.id))
                                    viewModel.setOverlayTiming(editing.id, editing.startMs, editing.startMs)
                                } else {
                                    viewModel.addSound(def)
                                }
                                viewModel.sfxPlayer.play(def)
                                onDismiss()
                            }
                            .padding(12.dp),
                    )
                }
            }
        }
        Text(
            text = "Tap to listen, + to add at the playhead. Sounds: CC0 (Freesound, Kenney)",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
        )
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
    }
}

/** Title + Delete / Done — stays visible when the panel is collapsed. */
@UnstableApi
@Composable
fun SoundPanelHeader(viewModel: EditorViewModel, editingId: String?, onDismiss: () -> Unit) {
    val editing = editingId?.let { id -> viewModel.soundLayers.firstOrNull { it.id == id } }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (editing != null) "Change sound" else "Sound FX",
            color = AdGagColors.OnBackground,
            style = MaterialTheme.typography.titleMedium,
        )
        Row {
            if (editing != null) {
                TextButton(onClick = {
                    viewModel.removeSound(editing.id)
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

@Composable
private fun CategoryChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text = label,
        color = if (selected) AdGagColors.OnBackground else AdGagColors.OnSurfaceMuted,
        style = MaterialTheme.typography.labelLarge,
        modifier = Modifier
            .clip(RoundedCornerShape(AdGagRadius.pill.dp))
            .background(if (selected) AdGagColors.GradientPink.copy(alpha = 0.35f) else AdGagColors.Surface)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 6.dp),
    )
}
