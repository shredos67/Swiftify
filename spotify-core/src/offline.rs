use std::{
    fs,
    io::{self, BufWriter},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Duration,
};

use librespot::{
    core::{SpotifyId, SpotifyUri},
    playback::{
        NUM_CHANNELS,
        audio_backend::{Sink, SinkError, SinkResult},
        config::PlayerConfig,
        decoder::AudioPacket,
        mixer::VolumeGetter,
        player::{Player, PlayerEvent},
    },
};
use rodio::Source;
use tokio::time::timeout;

use crate::spectrum::{ANALYSIS_SAMPLE_COUNT, SharedSpectrum};

pub(crate) const FLAC_EXTENSION: &str = "flac";
pub(crate) const WAV_EXTENSION: &str = "wav";

const DOWNLOAD_TIMEOUT_SECS: u64 = 90;
const WAV_BITS_PER_SAMPLE: u16 = 24;
pub(crate) const LOCAL_SAMPLE_RATE: u32 = 44_100;

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

fn base_name_for_uri(spotify_uri: &str) -> Option<String> {
    let uri = SpotifyUri::from_uri(spotify_uri).ok()?;
    if !uri.is_playable() {
        return None;
    }
    let id = SpotifyId::try_from(&uri).ok()?;
    id.to_base62().ok()
}

fn path_for_extension(downloads_dir: &Path, spotify_uri: &str, extension: &str) -> Option<PathBuf> {
    let base_name = base_name_for_uri(spotify_uri)?;
    Some(downloads_dir.join(format!("{base_name}.{extension}")))
}

pub(crate) fn is_available_locally(downloads_dir: &Path, spotify_uri: &str) -> bool {
    local_track_path(downloads_dir, spotify_uri).is_some()
}

pub(crate) fn local_track_path(downloads_dir: &Path, spotify_uri: &str) -> Option<PathBuf> {
    for extension in [WAV_EXTENSION, FLAC_EXTENSION] {
        let path = path_for_extension(downloads_dir, spotify_uri, extension)?;
        if path.exists() {
            return Some(path);
        }
    }
    None
}

pub(crate) fn downloaded_track_uris(downloads_dir: &Path) -> Vec<String> {
    let Ok(entries) = fs::read_dir(downloads_dir) else {
        return vec![];
    };
    let mut uris = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(extension) = path.extension().and_then(|ext| ext.to_str()) else {
            continue;
        };
        if extension != WAV_EXTENSION && extension != FLAC_EXTENSION {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        if let Ok(spotify_id) = SpotifyId::from_base62(stem) {
            let base62 = spotify_id.to_base62().ok();
            uris.push(format!(
                "spotify:track:{}",
                base62.unwrap_or_else(|| stem.to_owned())
            ));
        }
    }
    uris.sort();
    uris
}

pub(crate) fn remove_download(downloads_dir: &Path, spotify_uri: &str) -> bool {
    let mut removed = false;
    for extension in [WAV_EXTENSION, FLAC_EXTENSION] {
        let Some(path) = path_for_extension(downloads_dir, spotify_uri, extension) else {
            continue;
        };
        if path.exists() && fs::remove_file(path).is_ok() {
            removed = true;
        }
    }
    removed
}

// ---------------------------------------------------------------------------
// Downloader
// ---------------------------------------------------------------------------

type DownloadWriter = hound::WavWriter<BufWriter<fs::File>>;

/// Headless sink that writes librespot's decoded PCM directly to a temporary
/// WAV file. This keeps memory usage effectively constant for long tracks.
pub(crate) struct CaptureSink {
    writer: Arc<Mutex<Option<DownloadWriter>>>,
}

impl CaptureSink {
    pub(crate) fn new(writer: Arc<Mutex<Option<DownloadWriter>>>) -> Self {
        Self { writer }
    }
}

impl Sink for CaptureSink {
    fn start(&mut self) -> SinkResult<()> {
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        Ok(())
    }

    fn write(
        &mut self,
        packet: AudioPacket,
        converter: &mut librespot::playback::convert::Converter,
    ) -> SinkResult<()> {
        let samples = match &packet {
            AudioPacket::Samples(samples) => samples.as_slice(),
            AudioPacket::Raw(_) => return Ok(()),
        };
        let converted: &[f32] = &converter.f64_to_f32(samples);
        let mut guard = self
            .writer
            .lock()
            .map_err(|_| SinkError::OnWrite("download writer poisoned".to_owned()))?;
        let writer = guard
            .as_mut()
            .ok_or_else(|| SinkError::OnWrite("download writer is unavailable".to_owned()))?;
        let scale = ((1u64 << (WAV_BITS_PER_SAMPLE - 1)) - 1) as f32;
        for sample in converted {
            let value = (sample.clamp(-1.0, 1.0) * scale).round() as i32;
            writer.write_sample(value).map_err(|error| {
                SinkError::OnWrite(format!("failed to write download: {error}"))
            })?;
        }
        Ok(())
    }
}

struct DownloadVolume;

impl VolumeGetter for DownloadVolume {
    fn attenuation_factor(&self) -> f64 {
        1.0
    }
}

/// Streams a Spotify track once through a headless player and writes its decoded
/// PCM directly to a lossless WAV file in `downloads_dir`.
pub(crate) async fn download_track(
    session: librespot::core::session::Session,
    spotify_uri: String,
    downloads_dir: PathBuf,
) -> Result<(), String> {
    let uri = SpotifyUri::from_uri(&spotify_uri)
        .map_err(|error| format!("invalid spotify uri: {error}"))?;
    if !uri.is_playable() {
        return Err(format!(
            "spotify uri is not directly playable: {spotify_uri}"
        ));
    }
    let track_id =
        SpotifyId::try_from(&uri).map_err(|error| format!("not a spotify track: {error}"))?;
    let file_name = track_id.to_base62().map_err(|error| error.to_string())?;
    let destination = downloads_dir.join(format!("{file_name}.{WAV_EXTENSION}"));
    let partial_destination = downloads_dir.join(format!("{file_name}.{WAV_EXTENSION}.download"));

    if is_available_locally(&downloads_dir, &spotify_uri) {
        return Ok(());
    }

    fs::create_dir_all(&downloads_dir)
        .map_err(|error| format!("failed to create downloads directory: {error}"))?;

    if partial_destination.exists() {
        fs::remove_file(&partial_destination)
            .map_err(|error| format!("failed to clear incomplete download: {error}"))?;
    }

    let specification = hound::WavSpec {
        channels: u16::from(NUM_CHANNELS),
        sample_rate: LOCAL_SAMPLE_RATE,
        bits_per_sample: WAV_BITS_PER_SAMPLE,
        sample_format: hound::SampleFormat::Int,
    };
    let writer = hound::WavWriter::create(&partial_destination, specification)
        .map_err(|error| format!("failed to create download file: {error}"))?;
    let writer = Arc::new(Mutex::new(Some(writer)));
    let capture_writer = Arc::clone(&writer);
    let config = PlayerConfig {
        position_update_interval: Some(Duration::from_secs(10)),
        ..PlayerConfig::default()
    };

    let player = Player::new(
        config,
        session.clone(),
        Box::new(DownloadVolume),
        move || Box::new(CaptureSink::new(capture_writer)),
    );

    let mut events = player.get_player_event_channel();
    player.load(uri.clone(), true, 0);

    let playback_result = async {
        loop {
            let event = timeout(Duration::from_secs(DOWNLOAD_TIMEOUT_SECS), events.recv())
                .await
                .map_err(|_| "timed out while downloading the Spotify track".to_owned())?
                .ok_or_else(|| "the download player stopped unexpectedly".to_owned())?;

            match event {
                PlayerEvent::EndOfTrack {
                    track_id: ended, ..
                } if ended == uri => break,
                PlayerEvent::Unavailable {
                    track_id: unavailable,
                    ..
                } if unavailable == uri => {
                    return Err(format!(
                        "librespot could not download {spotify_uri}; the track may not be available"
                    ));
                }
                PlayerEvent::Stopped {
                    track_id: stopped, ..
                } if stopped == uri => {
                    return Err("the track download stopped before completion".to_owned());
                }
                _ => {}
            }
        }
        Ok::<(), String>(())
    }
    .await;

    if let Err(error) = playback_result {
        drop(player);
        if let Ok(mut guard) = writer.lock() {
            guard.take();
        }
        let _ = fs::remove_file(&partial_destination);
        return Err(error);
    }

    // Allow the decoder to flush any final packet before finalizing the WAV.
    tokio::time::sleep(Duration::from_millis(250)).await;
    drop(player);

    let wav_writer = writer
        .lock()
        .map_err(|_| "download writer poisoned".to_owned())?
        .take()
        .ok_or_else(|| "download writer is unavailable".to_owned())?;
    if let Err(error) = wav_writer.finalize() {
        let _ = fs::remove_file(&partial_destination);
        return Err(format!("failed to finalize download: {error}"));
    }
    let file_size = fs::metadata(&partial_destination)
        .map_err(|error| format!("failed to inspect completed download: {error}"))?
        .len();
    if file_size <= 44 {
        let _ = fs::remove_file(&partial_destination);
        return Err("the Spotify track produced no audio data".to_owned());
    }
    if let Err(error) = fs::rename(&partial_destination, &destination) {
        let _ = fs::remove_file(&partial_destination);
        return Err(format!("failed to publish completed download: {error}"));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Local playback
// ---------------------------------------------------------------------------

/// Active local-file playback session.
#[derive(Clone)]
pub(crate) struct LocalPlayback {
    /// On-disk path of the FLAC file being played (needed for re-decoding on seek).
    pub(crate) path: PathBuf,
    /// Total duration in milliseconds.
    pub(crate) duration_ms: u64,
    /// Number of decoded samples (all channels) already consumed.
    pub(crate) pushed_frames: Arc<AtomicU64>,
    /// Absolute position represented by the first sample in the active source.
    pub(crate) base_position_ms: u64,
    /// Number of audio channels in the decoded stream.
    pub(crate) channels: u32,
    /// Sample rate of the decoded stream.
    pub(crate) sample_rate: u32,
    /// Signals an in-flight decode to stop (on a seek/track change).
    pub(crate) cancel: Arc<AtomicBool>,
}

impl LocalPlayback {
    pub(crate) fn position_ms(&self) -> u32 {
        let channels = self.channels.max(1) as u64;
        let sample_rate = self.sample_rate.max(1) as u64;
        let samples = self.pushed_frames.load(Ordering::Relaxed);
        self.base_position_ms
            .saturating_add(samples / channels * 1_000 / sample_rate)
            .min(u32::MAX as u64) as u32
    }
}

/// Wraps a rodio `Decoder` so decoded samples are forwarded to the live sink,
/// fed into the spectrum analyzer, and counted for position tracking.
///
/// The source is decoded lazily by rodio's playback thread at real time, so the
/// sample count naturally reflects the actual playback position (and stalls
/// while paused).
pub(crate) struct LocalTrackSource {
    inner: rodio::Decoder<io::BufReader<fs::File>>,
    spectrum: SharedSpectrum,
    pushed_frames: Arc<AtomicU64>,
    cancel: Arc<AtomicBool>,
    analysis_samples: [f32; ANALYSIS_SAMPLE_COUNT],
    analysis_index: usize,
}

impl LocalTrackSource {
    pub(crate) fn new(
        decoder: rodio::Decoder<io::BufReader<fs::File>>,
        spectrum: SharedSpectrum,
        pushed_frames: Arc<AtomicU64>,
        cancel: Arc<AtomicBool>,
    ) -> Self {
        Self {
            inner: decoder,
            spectrum,
            pushed_frames,
            cancel,
            analysis_samples: [0.0; ANALYSIS_SAMPLE_COUNT],
            analysis_index: 0,
        }
    }
}

impl Iterator for LocalTrackSource {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        if self.cancel.load(Ordering::Relaxed) {
            return None;
        }
        let sample = self.inner.next()?;
        self.pushed_frames.fetch_add(1, Ordering::Relaxed);
        self.analysis_samples[self.analysis_index] = sample;
        self.analysis_index += 1;
        if self.analysis_index == ANALYSIS_SAMPLE_COUNT {
            self.spectrum
                .push_interleaved_f32(&self.analysis_samples, 1.0);
            self.analysis_index = 0;
        }
        Some(sample)
    }
}

impl Source for LocalTrackSource {
    fn current_span_len(&self) -> Option<usize> {
        self.inner.current_span_len()
    }

    fn channels(&self) -> rodio::ChannelCount {
        self.inner.channels()
    }

    fn sample_rate(&self) -> rodio::SampleRate {
        self.inner.sample_rate()
    }

    fn total_duration(&self) -> Option<Duration> {
        self.inner.total_duration()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wav_round_trips_through_rodio() {
        let sample_rate = LOCAL_SAMPLE_RATE;
        let channels = 2usize;
        let seconds = 2usize;
        let frame_count = sample_rate as usize * seconds;
        let destination = std::env::temp_dir().join("swiftify_roundtrip.wav");
        let specification = hound::WavSpec {
            channels: channels as u16,
            sample_rate,
            bits_per_sample: WAV_BITS_PER_SAMPLE,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&destination, specification).unwrap();
        let scale = ((1u64 << (WAV_BITS_PER_SAMPLE - 1)) - 1) as f32;
        for index in 0..frame_count {
            let sample = ((index as f32 * 0.01).sin() * 0.5 * scale).round() as i32;
            writer.write_sample(sample).unwrap();
            writer.write_sample(sample).unwrap();
        }
        writer.finalize().unwrap();

        let file = std::fs::File::open(&destination).unwrap();
        let mut decoder = rodio::Decoder::new(std::io::BufReader::new(file))
            .unwrap_or_else(|e| panic!("decode failed: {e}"));
        let count = decoder.by_ref().count();
        assert!(count > 0, "decoder produced no samples");
        std::fs::remove_file(&destination).ok();
    }

    #[test]
    fn local_position_includes_seek_offset() {
        let playback = LocalPlayback {
            path: PathBuf::new(),
            duration_ms: 120_000,
            pushed_frames: Arc::new(AtomicU64::new(LOCAL_SAMPLE_RATE as u64 * 2)),
            base_position_ms: 30_000,
            channels: 2,
            sample_rate: LOCAL_SAMPLE_RATE,
            cancel: Arc::new(AtomicBool::new(false)),
        };
        assert_eq!(playback.position_ms(), 31_000);
    }
}
