// lib/widgets/alarm_ring_overlay.dart
//
// Envuelve la app y escucha `Alarm.ringing`. Cuando una alarma de ruta
// suena, muestra una pantalla completa con un botón "Detener alarma".

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

class AlarmRingOverlay extends StatefulWidget {
  const AlarmRingOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<AlarmRingOverlay> createState() => _AlarmRingOverlayState();
}

class _AlarmRingOverlayState extends State<AlarmRingOverlay> {
  StreamSubscription<AlarmSet>? _sub;
  AlarmSettings? _ringing;

  @override
  void initState() {
    super.initState();
    _sub = Alarm.ringing.listen((alarmSet) {
      final first =
          alarmSet.alarms.isNotEmpty ? alarmSet.alarms.first : null;
      if (!mounted) return;
      setState(() => _ringing = first);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _stop() async {
    final alarm = _ringing;
    if (alarm != null) {
      try {
        await Alarm.stop(alarm.id);
      } catch (_) {}
    }
    if (mounted) setState(() => _ringing = null);
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _ringing;
    return Stack(
      children: [
        widget.child,
        if (ringing != null)
          Positioned.fill(
            child: _AlarmRingScreen(alarm: ringing, onStop: _stop),
          ),
      ],
    );
  }
}

class _AlarmRingScreen extends StatelessWidget {
  const _AlarmRingScreen({required this.alarm, required this.onStop});

  final AlarmSettings alarm;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.alarm,
                  size: 88,
                  color: Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                alarm.notificationSettings.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                alarm.notificationSettings.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 26),
                  label: const Text(
                    'Detener alarma',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
