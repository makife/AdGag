package com.adgag.adgag.editor

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.compose.PlayerSurface
import androidx.media3.ui.compose.SURFACE_TYPE_SURFACE_VIEW

/**
 * Phase 1 native editor UI: preview + trim + one background-music
 * attachment + Next. Deliberately not a redesign of the Flutter
 * editor's full toolset (text/stickers/filters/speed) — those are later
 * phases on this same screen, once phase 1's actual reason for existing
 * (drift-free preview via [CompositionPlayer]) is confirmed on a real
 * device.
 */
@UnstableApi
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    viewModel: EditorViewModel,
    onCancel: () -> Unit,
    onExported: (path: String, durationMs: Long) -> Unit,
    exportOutputPath: String,
) {
    val pickMusic = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) viewModel.setMusic(uri)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Edit") },
                actions = {
                    Button(
                        enabled = !viewModel.isExporting,
                        onClick = {
                            viewModel.export(
                                outputPath = exportOutputPath,
                                onProgress = {},
                                onComplete = { path, error ->
                                    if (path != null) {
                                        onExported(path, viewModel.trimEndMs - viewModel.trimStartMs)
                                    }
                                    // error != null: exportError is already
                                    // surfaced via viewModel.exportError,
                                    // rendered below — the screen stays
                                    // open so the user sees it, matching
                                    // this app's "never silently fail" rule.
                                },
                            )
                        },
                    ) {
                        Text("Next")
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                PlayerSurface(player = viewModel.player, surfaceType = SURFACE_TYPE_SURFACE_VIEW)
                IconButton(onClick = { viewModel.togglePlayPause() }) {
                    Icon(
                        imageVector = if (viewModel.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (viewModel.isPlaying) "Pause" else "Play",
                    )
                }
            }

            Surface(tonalElevation = 2.dp) {
                Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    if (viewModel.durationMs > 0) {
                        Text("Trim", style = MaterialTheme.typography.labelMedium)
                        RangeSlider(
                            value = viewModel.trimStartMs.toFloat()..viewModel.trimEndMs.toFloat(),
                            valueRange = 0f..viewModel.durationMs.toFloat(),
                            onValueChange = { range ->
                                viewModel.setTrim(range.start.toLong(), range.endInclusive.toLong())
                            },
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = { pickMusic.launch("audio/*") }) {
                            Icon(Icons.Filled.MusicNote, contentDescription = "Add music")
                        }
                        Text(
                            text = if (viewModel.musicUri != null) "Music attached" else "No music",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }

                    if (viewModel.isExporting) {
                        val progress = viewModel.exportProgress
                        Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                            Text("Exporting…", style = MaterialTheme.typography.bodySmall)
                            if (progress > 0f) {
                                LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                            } else {
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                    val error = viewModel.exportError
                    if (error != null) {
                        Text(
                            text = "Export failed: $error",
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
            }
        }
    }
}
