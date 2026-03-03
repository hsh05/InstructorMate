// lib/services/web_audio_impl.dart
// Web-only audio implementation using dart:js_interop.
// Never imported directly — only loaded via conditional import in
// web_notification_service.dart when compiling for web.

import 'dart:js_interop';

@JS('AudioContext')
@staticInterop
class _AudioContext {
  external factory _AudioContext();
}

extension _AudioContextExt on _AudioContext {
  external JSObject createOscillator();
  external JSObject createGain();
  external JSObject get destination;
  external double get currentTime;
  external JSPromise resume();
}

extension _NodeExt on JSObject {
  external set type(JSString v);
  external JSObject get frequency;
  external JSObject get gain;
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double endTime);
  external void linearRampToValueAtTime(double value, double endTime);
  external void connect(JSObject destination);
  external void start([double when]);
  external void stop([double when]);
}

_AudioContext? _ctx;
bool _unlocked = false;

void unlockWebAudio() {
  if (_unlocked) return;
  try {
    _ctx ??= _AudioContext();
    _ctx!.resume();
    _unlocked = true;
  } catch (_) {}
}

void playBellChime() {
  if (!_unlocked) return;
  try {
    final ctx = _ctx!;
    final now = ctx.currentTime;
    // Three ascending bell tones: E5 → G#5 → B5
    final notes = [659.0, 830.0, 988.0];
    for (var i = 0; i < notes.length; i++) {
      final t = now + i * 0.18;
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine'.toJS;
      osc.frequency.setValueAtTime(notes[i], t);
      gain.gain.setValueAtTime(0.0, t);
      gain.gain.linearRampToValueAtTime(0.45, t + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 1.2);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + 1.3);
    }
  } catch (_) {}
}
