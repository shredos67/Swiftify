use std::{
    fs,
    io,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Duration,
};

use flacenc::component::BitRepr;
use flacenc::error::Verify;
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

const DOWNLOAD_TIMEOUT_SECS: u64 = 90;
const FLAC_BITS_PER_SAMPLE: u32 = 24;
pub(crate) const LOCAL_SAMPLE_RATE: u32 = 44_100;

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

fn file_name_for_uri(spotify_uri: &str) -> Option<String> {
    let uri = SpotifyUri::from_uri(spotify_uri).ok()?;
    if !uri.is_playable() {
        return None;
    }
    let id = SpotifyId::try_from(&uri).ok()?;
    let base62 = id.to_base62().ok()?;
    Some(format!("{base62}.{FLAC_EXTENSION}"))
}

pub(crate) fn is_available_locally(downloads_dir: &Path, spotify_uri: &str) -> bool {
    match file_name_for_uri(spotify_uri) {
        Some(name) => downloads_dir.join(name).exists(),
        None => false,
    }
}

pub(crate) fn local_track_path(downloads_dir: &Path, spotify_uri: &str) -> Option<PathBuf> {
    let name = file_name_for_uri(spotify_uri)?;
    let path = downloads_dir.join(name);
    if path.exists() {
        Some(path)
    } else {
        None
    }
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
        if extension != FLAC_EXTENSION {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        if let Ok(spotify_id) = SpotifyId::from_base62(stem) {
            let base62 = spotify_id.to_base62().ok();
            uris.push(format!("spotify:track:{}", base62.unwrap_or_else(|| stem.to_owned())));
        }
    }
    uris.sort();
    uris
}

pub(crate) fn remove_download(downloads_dir: &Path, spotify_uri: &str) -> bool {
    match local_track_path(downloads_dir, spotify_uri) {
        Some(path) => fs::remove_file(path).is_ok(),
        None => false,
    }
}

// ---------------------------------------------------------------------------
// Downloader
// ---------------------------------------------------------------------------

/// Headless Sink that captures the decoded PCM librespot produces for a track.
pub(crate) struct CaptureSink {
    samples: Arc<Mutex<Vec<f32>>>,
}

impl CaptureSink {
    pub(crate) fn new(samples: Arc<Mutex<Vec<f32>>>) -> Self {
        Self { samples }
    }
}

impl Sink for CaptureSink {
    fn start(&mut self) -> SinkResult<()> {
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        Ok(())
    }

    fn write(&mut self, packet: AudioPacket, converter: &mut librespot::playback::convert::Converter) -> SinkResult<()> {
        let samples = match &packet {
            AudioPacket::Samples(samples) => samples.as_slice(),
            AudioPacket::Raw(_) => return Ok(()),
        };
        let converted: &[f32] = &converter.f64_to_f32(samples);
        let mut guard = self
            .samples
            .lock()
            .map_err(|_| SinkError::OnWrite("capture buffer poisoned".to_owned()))?;
        guard.extend_from_slice(converted);
        Ok(())
    }
}

struct DownloadVolume;

impl VolumeGetter for DownloadVolume {
    fn attenuation_factor(&self) -> f64 {
        1.0
    }
}

/// Streams a Spotify track once through a headless player, captures its decoded
/// PCM in memory, and encodes it to a FLAC file in `downloads_dir`.
pub(crate) async fn download_track(
    session: librespot::core::session::Session,
    spotify_uri: String,
    downloads_dir: PathBuf,
) -> Result<(), String> {
    let uri = SpotifyUri::from_uri(&spotify_uri)
        .map_err(|error| format!("invalid spotify uri: {error}"))?;
    if !uri.is_playable() {
        return Err(format!("spotify uri is not directly playable: {spotify_uri}"));
    }
    let track_id = SpotifyId::try_from(&uri)
        .map_err(|error| format!("not a spotify track: {error}"))?;
    let file_name = track_id.to_base62().map_err(|error| error.to_string())?;
    let destination = downloads_dir.join(format!("{file_name}.{FLAC_EXTENSION}"));

    if destination.exists() {
        return Ok(());
    }

    fs::create_dir_all(&downloads_dir)
        .map_err(|error| format!("failed to create downloads directory: {error}"))?;

    let samples: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(vec![]));
    let capture_samples = Arc::clone(&samples);
    let config = PlayerConfig::default();

    let player = Player::new(
        config,
        session.clone(),
        Box::new(DownloadVolume),
        move || Box::new(CaptureSink::new(capture_samples)),
    );

    let mut events = player.get_player_event_channel();
    player.load(uri.clone(), true, 0);

    loop {
        let event = timeout(Duration::from_secs(DOWNLOAD_TIMEOUT_SECS), events.recv())
            .await
            .map_err(|_| "timed out while downloading the Spotify track".to_owned())?
            .ok_or_else(|| "the download player stopped unexpectedly".to_owned())?;

        match event {
            PlayerEvent::EndOfTrack { track_id: ended, .. } if ended == uri => break,
            PlayerEvent::Unavailable {
                track_id: unavailable, ..
            } if unavailable == uri => {
                return Err(format!(
                    "librespot could not download {spotify_uri}; the track may not be available"
                ));
            }
            PlayerEvent::Stopped { track_id: stopped, .. } if stopped == uri => {
                return Err("the track download stopped before completion".to_owned());
            }
            _ => {}
        }
    }

    // Allow the decoder to flush any final buffered samples into the sink.
    tokio::time::sleep(Duration::from_millis(250)).await;

    let buffered = samples
        .lock()
        .map_err(|_| "capture buffer poisoned".to_owned())?;
    if buffered.is_empty() {
        return Err("the Spotify track produced no audio data".to_owned());
    }
    encode_flac_to(&buffered, u16::from(NUM_CHANNELS), LOCAL_SAMPLE_RATE, &destination)?;
    Ok(())
}

/// Encodes interleaved f32 PCM samples (-1.0..=1.0) to a FLAC file.
fn encode_flac_to(samples: &[f32], channels: u16, sample_rate: u32, destination: &Path) -> Result<(), String> {
    use flacenc::{bitsink::ByteSink, config::Encoder, source::MemSource};

    let bits_per_sample = FLAC_BITS_PER_SAMPLE;
    let scale = ((1u64 << (bits_per_sample - 1)) - 1) as f32;
    let int_samples: Vec<i32> = samples
        .iter()
        .map(|sample| (sample.clamp(-1.0, 1.0) * scale).round() as i32)
        .collect();

    let config = Encoder::default()
        .into_verified()
        .map_err(|(_, error)| format!("invalid FLAC encoder config: {error}"))?;

    let source = MemSource::from_samples(
        &int_samples,
        channels as usize,
        bits_per_sample as usize,
        sample_rate as usize,
    );
    let stream = flacenc::encode_with_fixed_block_size(&config, source, config.block_size)
        .map_err(|error| format!("FLAC encoding failed: {error}"))?;

    let mut sink = ByteSink::new();
    stream
        .write(&mut sink)
        .map_err(|error| format!("failed to serialize FLAC stream: {error}"))?;

    fs::write(destination, sink.as_slice())
        .map_err(|error| format!("failed to write FLAC file: {error}"))?;
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
    /// Number of audio channels in the decoded stream.
    pub(crate) channels: u32,
    /// Signals an in-flight decode to stop (on a seek/track change).
    pub(crate) cancel: Arc<AtomicBool>,
}

impl LocalPlayback {
    pub(crate) fn position_ms(&self) -> u32 {
        let channels = self.channels.max(1) as u64;
        let samples = self.pushed_frames.load(Ordering::Relaxed);
        (samples / channels * 1_000 / LOCAL_SAMPLE_RATE as u64) as u32
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
    analysis_samples: [f32; ANALYSIS_SAMPLE_COUNT],
    analysis_index: usize,
}

impl LocalTrackSource {
    pub(crate) fn new(
        decoder: rodio::Decoder<io::BufReader<fs::File>>,
        spectrum: SharedSpectrum,
        pushed_frames: Arc<AtomicU64>,
    ) -> Self {
        Self {
            inner: decoder,
            spectrum,
            pushed_frames,
            analysis_samples: [0.0; ANALYSIS_SAMPLE_COUNT],
            analysis_index: 0,
        }
    }
}

impl Iterator for LocalTrackSource {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        let sample = self.inner.next()?;
        self.pushed_frames.fetch_add(1, Ordering::Relaxed);
        self.analysis_samples[self.analysis_index] = sample;
        self.analysis_index += 1;
        if self.analysis_index == ANALYSIS_SAMPLE_COUNT {
            self.spectrum.push_interleaved_f32(&self.analysis_samples, 1.0);
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
    fn flac_round_trips_through_rodio() {
        let sample_rate = LOCAL_SAMPLE_RATE;
        let channels = 2usize;
        let seconds = 2usize;
        let frame_count = sample_rate as usize * seconds;
        let mut samples = vec![0f32; frame_count * channels];
        for i in 0..frame_count {
            let v = (i as f32 * 0.01).sin() * 0.5;
            samples[i * channels] = v;
            samples[i * channels + 1] = v;
        }

        let dest = std::env::temp_dir().join("swiftify_roundtrip.flac");
        encode_flac_to(&samples, channels as u16, sample_rate, &dest)
            .unwrap_or_else(|e| panic!("encode failed: {e}"));

        let file = std::fs::File::open(&dest).unwrap();
        let mut decoder = rodio::Decoder::new_flac(std::io::BufReader::new(file))
            .unwrap_or_else(|e| panic!("decode failed: {e}"));
        use rodio::Source;
        let count = decoder.by_ref().count();
        assert!(count > 0, "decoder produced no samples");
        std::fs::remove_file(&dest).ok();
    }

    #[test]
    fn flac_encodes_with_non_multiple_tail() {
        // Total samples not a multiple of the encoder block size.
        let sample_rate = LOCAL_SAMPLE_RATE;
        let channels = 1usize;
        let mut samples = vec![0f32; 10_000];
        for (i, s) in samples.iter_mut().enumerate() {
            *s = (i as f32 * 0.05).sin() * 0.5;
        }
        let dest = std::env::temp_dir().join("swiftify_tail.flac");
        encode_flac_to(&samples, channels as u16, sample_rate, &dest)
            .unwrap_or_else(|e| panic!("encode failed: {e}"));
        let file = std::fs::File::open(&dest).unwrap();
        let decoder = rodio::Decoder::new_flac(std::io::BufReader::new(file))
            .unwrap_or_else(|e| panic!("decode failed: {e}"));
        use rodio::Source;
        let total = decoder.total_duration().map(|d| d.as_secs_f64());
        assert!(total.map_or(false, |d| d > 0.0), "total_duration missing");
        std::fs::remove_file(&dest).ok();
    }
}
