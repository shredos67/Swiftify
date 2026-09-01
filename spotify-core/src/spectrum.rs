use std::{
    f32::consts::TAU,
    ops::Range,
    sync::{
        Arc, Mutex,
        mpsc::{SyncSender, sync_channel},
    },
    thread,
    time::{Duration, Instant},
};

use librespot::playback::{
    NUM_CHANNELS, SAMPLE_RATE,
    audio_backend::{Sink, SinkError, SinkResult},
    convert::Converter,
    decoder::AudioPacket,
    mixer::VolumeGetter,
};
use rodio::Source;
use rustfft::{Fft, FftPlanner, num_complex::Complex};

pub(crate) const BAND_COUNT: usize = 48;

const FFT_SIZE: usize = 2_048;
const HOP_SIZE: usize = 512;
pub(crate) const ANALYSIS_SAMPLE_COUNT: usize = HOP_SIZE * NUM_CHANNELS as usize;
const MIN_FREQUENCY_HZ: f32 = 40.0;
const MAX_FREQUENCY_HZ: f32 = 16_000.0;
const NOISE_FLOOR_DB: f32 = -72.0;

#[derive(Clone)]
pub(crate) struct SharedSpectrum {
    analyzer: Arc<Mutex<SpectrumAnalyzer>>,
}

impl SharedSpectrum {
    pub(crate) fn new() -> Self {
        Self {
            analyzer: Arc::new(Mutex::new(SpectrumAnalyzer::new())),
        }
    }

    pub(crate) fn levels(&self) -> Vec<f32> {
        self.analyzer
            .lock()
            .map(|mut analyzer| analyzer.next_levels().to_vec())
            .unwrap_or_else(|_| vec![0.0; BAND_COUNT])
    }

    pub(crate) fn clear(&self) {
        if let Ok(mut analyzer) = self.analyzer.lock() {
            analyzer.clear();
        }
    }

    pub(crate) fn push_interleaved_f32(&self, samples: &[f32], output_gain: f64) {
        if let Ok(mut analyzer) = self.analyzer.lock() {
            analyzer.push_interleaved_f32(samples, output_gain);
        }
    }
}

pub(crate) struct SpectrumSink {
    rodio_sink: rodio::Sink,
    _stream: rodio::OutputStream,
    spectrum: SharedSpectrum,
    output_volume: Box<dyn VolumeGetter + Send>,
    analysis_sender: SyncSender<AnalysisChunk>,
    _analysis_worker: thread::JoinHandle<()>,
}

impl SpectrumSink {
    pub(crate) fn new(
        spectrum: SharedSpectrum,
        output_volume: Box<dyn VolumeGetter + Send>,
    ) -> Self {
        let mut stream = rodio::OutputStreamBuilder::open_default_stream()
            .expect("failed to open the default audio output");
        stream.log_on_drop(false);
        let rodio_sink = rodio::Sink::connect_new(stream.mixer());
        let (analysis_sender, analysis_receiver) = sync_channel::<AnalysisChunk>(1);
        let worker_spectrum = spectrum.clone();
        let analysis_worker = thread::Builder::new()
            .name("swiftify-spectrum".to_owned())
            .spawn(move || {
                while let Ok(chunk) = analysis_receiver.recv() {
                    worker_spectrum.push_interleaved_f32(&chunk.samples, chunk.output_gain);
                }
            })
            .expect("failed to start the spectrum analysis worker");

        Self {
            rodio_sink,
            _stream: stream,
            spectrum,
            output_volume,
            analysis_sender,
            _analysis_worker: analysis_worker,
        }
    }
}

impl Sink for SpectrumSink {
    fn start(&mut self) -> SinkResult<()> {
        self.rodio_sink.play();
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        self.rodio_sink.sleep_until_end();
        self.rodio_sink.pause();
        self.spectrum.clear();
        Ok(())
    }

    fn write(&mut self, packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        let samples = packet
            .samples()
            .map_err(|error| SinkError::OnWrite(error.to_string()))?;
        let source = AnalyzedSource::new(
            converter.f64_to_f32(samples),
            self.analysis_sender.clone(),
            self.output_volume.attenuation_factor(),
        );
        self.rodio_sink.append(source);

        // Keep the same bounded queue as librespot's Rodio backend. The spectrum
        // tap lives inside the Source iterator, so queued audio is not analyzed
        // until Rodio actually consumes it for the output stream.
        while self.rodio_sink.len() > 26 {
            thread::sleep(Duration::from_millis(10));
        }

        Ok(())
    }
}

struct AnalysisChunk {
    samples: [f32; ANALYSIS_SAMPLE_COUNT],
    output_gain: f64,
}

struct AnalyzedSource {
    inner: rodio::buffer::SamplesBuffer,
    analysis_sender: SyncSender<AnalysisChunk>,
    output_gain: f64,
    analysis_samples: [f32; ANALYSIS_SAMPLE_COUNT],
    analysis_index: usize,
}

impl AnalyzedSource {
    fn new(
        samples: Vec<f32>,
        analysis_sender: SyncSender<AnalysisChunk>,
        output_gain: f64,
    ) -> Self {
        Self {
            inner: rodio::buffer::SamplesBuffer::new(NUM_CHANNELS.into(), SAMPLE_RATE, samples),
            analysis_sender,
            output_gain,
            analysis_samples: [0.0; ANALYSIS_SAMPLE_COUNT],
            analysis_index: 0,
        }
    }
}

impl Iterator for AnalyzedSource {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        let sample = self.inner.next()?;
        self.analysis_samples[self.analysis_index] = sample;
        self.analysis_index += 1;

        if self.analysis_index == ANALYSIS_SAMPLE_COUNT {
            // The single-slot channel is deliberately lossy. If analysis ever
            // falls behind, discard this frame instead of creating visual lag.
            let _ = self.analysis_sender.try_send(AnalysisChunk {
                samples: self.analysis_samples,
                output_gain: self.output_gain,
            });
            self.analysis_index = 0;
        }

        Some(sample)
    }
}

impl Source for AnalyzedSource {
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

struct SpectrumAnalyzer {
    fft: Arc<dyn Fft<f32>>,
    fft_buffer: Vec<Complex<f32>>,
    window: Vec<f32>,
    band_ranges: Vec<Range<usize>>,
    samples: Vec<f32>,
    write_index: usize,
    filled: usize,
    frames_since_transform: usize,
    target_levels: [f32; BAND_COUNT],
    display_levels: [f32; BAND_COUNT],
    slow_band_decibels: [f32; BAND_COUNT],
    has_reference_level: bool,
    last_transform: Option<Instant>,
}

impl SpectrumAnalyzer {
    fn new() -> Self {
        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FFT_SIZE);
        let window = (0..FFT_SIZE)
            .map(|index| 0.5 - 0.5 * (TAU * index as f32 / (FFT_SIZE - 1) as f32).cos())
            .collect();

        Self {
            fft,
            fft_buffer: vec![Complex::default(); FFT_SIZE],
            window,
            band_ranges: logarithmic_band_ranges(),
            samples: vec![0.0; FFT_SIZE],
            write_index: 0,
            filled: 0,
            frames_since_transform: 0,
            target_levels: [0.0; BAND_COUNT],
            display_levels: [0.0; BAND_COUNT],
            slow_band_decibels: [NOISE_FLOOR_DB; BAND_COUNT],
            has_reference_level: false,
            last_transform: None,
        }
    }

    #[cfg(test)]
    fn push_interleaved(&mut self, samples: &[f64], output_gain: f64) {
        // librespot applies soft volume before packets reach the audio sink. Undo it
        // for analysis so changing listening volume does not flatten the visualizer.
        let inverse_output_gain = if output_gain > 1.0e-4 {
            output_gain.recip()
        } else {
            1.0
        };

        for frame in samples.chunks_exact(NUM_CHANNELS as usize) {
            let mono = frame.iter().sum::<f64>() / NUM_CHANNELS as f64 * inverse_output_gain;
            self.push_mono(mono as f32);
        }
    }

    fn push_interleaved_f32(&mut self, samples: &[f32], output_gain: f64) {
        let inverse_output_gain = if output_gain > 1.0e-4 {
            output_gain.recip() as f32
        } else {
            1.0
        };

        for frame in samples.chunks_exact(NUM_CHANNELS as usize) {
            let mono = frame.iter().sum::<f32>() / NUM_CHANNELS as f32 * inverse_output_gain;
            self.push_mono(mono);
        }
    }

    fn push_mono(&mut self, sample: f32) {
        self.samples[self.write_index] = sample;
        self.write_index = (self.write_index + 1) % FFT_SIZE;

        if self.filled < FFT_SIZE {
            self.filled += 1;
            if self.filled == FFT_SIZE {
                self.transform();
                self.frames_since_transform = 0;
            }
        } else {
            self.frames_since_transform += 1;
            if self.frames_since_transform >= HOP_SIZE {
                self.transform();
                self.frames_since_transform -= HOP_SIZE;
            }
        }
    }

    fn transform(&mut self) {
        for output_index in 0..FFT_SIZE {
            let sample_index = (self.write_index + output_index) % FFT_SIZE;
            self.fft_buffer[output_index] =
                Complex::new(self.samples[sample_index] * self.window[output_index], 0.0);
        }

        self.fft.process(&mut self.fft_buffer);

        let mut band_decibels = [NOISE_FLOOR_DB; BAND_COUNT];

        for (band, frequency_range) in self.band_ranges.iter().enumerate() {
            let first_bin = frequency_range.start;
            let end_bin = frequency_range.end;
            let bin_count = (end_bin - first_bin).max(1) as f32;
            let band_energy = self.fft_buffer[first_bin..end_bin]
                .iter()
                .map(|sample| {
                    let magnitude = sample.norm() * 4.0 / FFT_SIZE as f32;
                    magnitude * magnitude
                })
                .sum::<f32>();
            let root_mean_square = (band_energy / bin_count).sqrt();
            let center_frequency = bin_to_frequency((first_bin + end_bin) / 2);
            let decibels =
                20.0 * root_mean_square.max(1.0e-8).log10() + perceptual_gain_db(center_frequency);
            band_decibels[band] = decibels.max(NOISE_FLOOR_DB);
        }

        if !self.has_reference_level {
            self.slow_band_decibels = band_decibels;
            self.has_reference_level = true;
        }

        let frame_peak = band_decibels.iter().copied().fold(NOISE_FLOOR_DB, f32::max);
        if frame_peak <= NOISE_FLOOR_DB + 1.0 {
            self.target_levels.fill(0.0);
            self.last_transform = Some(Instant::now());
            return;
        }
        let frame_energy = ((frame_peak - NOISE_FLOOR_DB) / 55.0).clamp(0.25, 1.0);

        for (band, &decibels) in band_decibels.iter().enumerate() {
            let relative_energy = ((decibels - frame_peak + 30.0) / 30.0)
                .clamp(0.0, 1.0)
                .powf(1.55);
            let transient = ((decibels - self.slow_band_decibels[band]) / 10.0).clamp(0.0, 1.0);

            // Spectral contrast keeps neighboring bands distinct; the transient term
            // makes short kick/bass events visibly punch above the slow envelope.
            self.target_levels[band] =
                (0.04 + 0.56 * relative_energy * frame_energy + 0.48 * transient).clamp(0.0, 1.0);

            self.slow_band_decibels[band] += (decibels - self.slow_band_decibels[band]) * 0.035;
        }

        self.last_transform = Some(Instant::now());
    }

    fn next_levels(&mut self) -> [f32; BAND_COUNT] {
        if self
            .last_transform
            .is_none_or(|instant| instant.elapsed().as_secs_f32() > 0.12)
        {
            self.target_levels.fill(0.0);
        }

        for band in 0..BAND_COUNT {
            let smoothing = if self.target_levels[band] > self.display_levels[band] {
                0.70
            } else {
                0.28
            };
            self.display_levels[band] +=
                (self.target_levels[band] - self.display_levels[band]) * smoothing;
        }

        self.display_levels
    }

    fn clear(&mut self) {
        self.samples.fill(0.0);
        self.target_levels.fill(0.0);
        self.display_levels.fill(0.0);
        self.slow_band_decibels.fill(NOISE_FLOOR_DB);
        self.has_reference_level = false;
        self.write_index = 0;
        self.filled = 0;
        self.frames_since_transform = 0;
        self.last_transform = None;
    }
}

fn frequency_to_bin(frequency: f32) -> usize {
    (frequency * FFT_SIZE as f32 / SAMPLE_RATE as f32).ceil() as usize
}

fn bin_to_frequency(bin: usize) -> f32 {
    bin as f32 * SAMPLE_RATE as f32 / FFT_SIZE as f32
}

fn logarithmic_band_ranges() -> Vec<Range<usize>> {
    let first_bin = frequency_to_bin(MIN_FREQUENCY_HZ).max(1);
    let last_bin = frequency_to_bin(MAX_FREQUENCY_HZ).min(FFT_SIZE / 2);
    assert!(last_bin - first_bin >= BAND_COUNT);

    let frequency_ratio = MAX_FREQUENCY_HZ / MIN_FREQUENCY_HZ;
    let mut edges = Vec::with_capacity(BAND_COUNT + 1);
    edges.push(first_bin);

    for edge in 1..BAND_COUNT {
        let progress = edge as f32 / BAND_COUNT as f32;
        let desired = frequency_to_bin(MIN_FREQUENCY_HZ * frequency_ratio.powf(progress));
        let minimum = edges.last().copied().unwrap_or(first_bin) + 1;
        let maximum = last_bin - (BAND_COUNT - edge);
        edges.push(desired.clamp(minimum, maximum));
    }

    edges.push(last_bin);
    edges.windows(2).map(|pair| pair[0]..pair[1]).collect()
}

fn perceptual_gain_db(frequency: f32) -> f32 {
    let position = (frequency / MIN_FREQUENCY_HZ).ln() / (MAX_FREQUENCY_HZ / MIN_FREQUENCY_HZ).ln();
    -1.5 + 7.0 * position.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::{BAND_COUNT, FFT_SIZE, HOP_SIZE, SAMPLE_RATE, SpectrumAnalyzer, frequency_to_bin};

    fn band_for_frequency(analyzer: &SpectrumAnalyzer, frequency: f32) -> usize {
        let bin = frequency_to_bin(frequency);
        analyzer
            .band_ranges
            .iter()
            .position(|range| range.contains(&bin))
            .expect("frequency should be covered by the visualizer")
    }

    #[test]
    fn places_a_tone_in_its_frequency_band() {
        let mut analyzer = SpectrumAnalyzer::new();
        let frequency = 440.0;
        let mut stereo_samples = Vec::with_capacity(FFT_SIZE * 2);

        for index in 0..FFT_SIZE {
            let sample =
                (std::f64::consts::TAU * frequency * index as f64 / SAMPLE_RATE as f64).sin() * 0.7;
            stereo_samples.extend([sample, sample]);
        }

        analyzer.push_interleaved(&stereo_samples, 1.0);
        let levels = analyzer.next_levels();
        let expected_band = band_for_frequency(&analyzer, frequency as f32);
        let strongest_band = levels
            .iter()
            .enumerate()
            .max_by(|(_, left), (_, right)| left.total_cmp(right))
            .map(|(index, _)| index);

        assert!(
            strongest_band.is_some_and(|band| band.abs_diff(expected_band) <= 1),
            "expected {expected_band}, got {strongest_band:?}: {levels:?}"
        );
        assert!(levels[expected_band] > 0.2);
    }

    #[test]
    fn silence_produces_no_visible_bands() {
        let mut analyzer = SpectrumAnalyzer::new();
        analyzer.push_interleaved(&vec![0.0; FFT_SIZE * 2], 1.0);

        assert_eq!(analyzer.next_levels(), [0.0; BAND_COUNT]);
    }

    #[test]
    fn bass_energy_retains_visual_headroom() {
        let mut analyzer = SpectrumAnalyzer::new();
        let frame_count = SAMPLE_RATE as usize;
        let mut samples = Vec::with_capacity(frame_count * 2);

        for index in 0..frame_count {
            let sample =
                (std::f64::consts::TAU * 80.0 * index as f64 / SAMPLE_RATE as f64).sin() * 0.25;
            samples.extend([sample, sample]);
        }

        analyzer.push_interleaved(&samples, 1.0);
        let bass_band = band_for_frequency(&analyzer, 80.0);
        let mut levels = [0.0; BAND_COUNT];
        for _ in 0..12 {
            levels = analyzer.next_levels();
        }

        assert!(levels[bass_band] > 0.35);
        assert!(levels[bass_band] < 0.85);
        assert!(
            levels[bass_band]
                > levels
                    .iter()
                    .enumerate()
                    .filter(|(band, _)| band.abs_diff(bass_band) > 2)
                    .map(|(_, level)| *level)
                    .fold(0.0, f32::max)
        );
    }

    #[test]
    fn amplitude_changes_create_smooth_visible_motion() {
        let mut analyzer = SpectrumAnalyzer::new();
        let frame_count = SAMPLE_RATE as usize;
        let mut samples = Vec::with_capacity(frame_count * 2);

        for index in 0..frame_count {
            let time = index as f64 / SAMPLE_RATE as f64;
            let envelope = 0.08 + 0.42 * (0.5 + 0.5 * (std::f64::consts::TAU * 4.0 * time).sin());
            let sample = (std::f64::consts::TAU * 440.0 * time).sin() * envelope;
            samples.extend([sample, sample]);
        }

        let motion_band = band_for_frequency(&analyzer, 440.0);
        let mut motion = Vec::new();
        for chunk in samples.chunks(HOP_SIZE * 2) {
            analyzer.push_interleaved(chunk, 1.0);
            motion.push(analyzer.next_levels()[motion_band]);
        }

        let minimum = motion.iter().copied().fold(f32::INFINITY, f32::min);
        let maximum = motion.iter().copied().fold(f32::NEG_INFINITY, f32::max);
        let largest_step = motion
            .windows(2)
            .map(|pair| (pair[1] - pair[0]).abs())
            .fold(0.0_f32, f32::max);

        assert!(maximum - minimum > 0.15);
        assert!(largest_step < 0.48);
    }

    #[test]
    fn clear_discards_prior_audio() {
        let mut analyzer = SpectrumAnalyzer::new();
        let mut samples = Vec::with_capacity(FFT_SIZE * 2);
        for index in 0..FFT_SIZE {
            let sample =
                (std::f64::consts::TAU * 440.0 * index as f64 / SAMPLE_RATE as f64).sin() * 0.5;
            samples.extend([sample, sample]);
        }
        analyzer.push_interleaved(&samples, 1.0);
        assert!(analyzer.next_levels().iter().any(|level| *level > 0.0));

        analyzer.clear();

        assert_eq!(analyzer.next_levels(), [0.0; BAND_COUNT]);
    }

    #[test]
    fn analysis_is_independent_of_output_volume() {
        let mut full_volume = SpectrumAnalyzer::new();
        let mut low_volume = SpectrumAnalyzer::new();
        let mut full_samples = Vec::with_capacity(FFT_SIZE * 2);
        let mut quiet_samples = Vec::with_capacity(FFT_SIZE * 2);

        for index in 0..FFT_SIZE {
            let sample =
                (std::f64::consts::TAU * 220.0 * index as f64 / SAMPLE_RATE as f64).sin() * 0.55;
            full_samples.extend([sample, sample]);
            quiet_samples.extend([sample * 0.08, sample * 0.08]);
        }

        full_volume.push_interleaved(&full_samples, 1.0);
        low_volume.push_interleaved(&quiet_samples, 0.08);

        let full_levels = full_volume.next_levels();
        let quiet_levels = low_volume.next_levels();
        for band in 0..BAND_COUNT {
            assert!((full_levels[band] - quiet_levels[band]).abs() < 0.015);
        }
    }

    #[test]
    fn bass_transient_punches_above_the_other_bands() {
        let mut analyzer = SpectrumAnalyzer::new();
        let chunk_frames = HOP_SIZE;
        let bass_band = band_for_frequency(&analyzer, 75.0);
        let bed_band = band_for_frequency(&analyzer, 1_200.0);

        let mut kick_levels = [0.0; BAND_COUNT];
        for chunk_index in 0..14 {
            let mut samples = Vec::with_capacity(chunk_frames * 2);
            for frame in 0..chunk_frames {
                let index = chunk_index * chunk_frames + frame;
                let time = index as f64 / SAMPLE_RATE as f64;
                let bed = (std::f64::consts::TAU * 1_200.0 * time).sin() * 0.08;
                let kick = if chunk_index == 10 {
                    (std::f64::consts::TAU * 75.0 * time).sin() * 0.85
                } else {
                    0.0
                };
                samples.extend([bed + kick, bed + kick]);
            }
            analyzer.push_interleaved(&samples, 1.0);
            if chunk_index == 10 {
                kick_levels = analyzer.next_levels();
            }
        }

        assert!(kick_levels[bass_band] > 0.68, "{kick_levels:?}");
        assert!(
            kick_levels[bass_band] > kick_levels[bed_band] + 0.18,
            "{kick_levels:?}"
        );
    }

    #[test]
    fn separated_tones_light_independent_bands() {
        let mut analyzer = SpectrumAnalyzer::new();
        let low_frequency = 90.0;
        let high_frequency = 4_200.0;
        let mut stereo_samples = Vec::with_capacity(FFT_SIZE * 2);

        for index in 0..FFT_SIZE {
            let time = index as f64 / SAMPLE_RATE as f64;
            let low = (std::f64::consts::TAU * low_frequency * time).sin() * 0.55;
            let high = (std::f64::consts::TAU * high_frequency * time).sin() * 0.45;
            stereo_samples.extend([low + high, low + high]);
        }

        analyzer.push_interleaved(&stereo_samples, 1.0);
        let levels = analyzer.next_levels();
        let low_band = band_for_frequency(&analyzer, low_frequency as f32);
        let high_band = band_for_frequency(&analyzer, high_frequency as f32);

        assert!(low_band.abs_diff(high_band) > 20);
        assert!(levels[low_band] > 0.2, "{levels:?}");
        assert!(levels[high_band] > 0.2, "{levels:?}");
    }
}
