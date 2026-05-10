import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math' as math;
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolanoTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F9F5),
      ),
      home: const MainShell(),
    );
  }
}

// ─── Thesis-based optimal ranges ───────────────────────────────────────────────
class SolanoRanges {
  static const double tempMin = 27.0;
  static const double tempMax = 30.0;
  static const double humidMin = 65.0;
  static const double humidMax = 80.0;
  static const int soilMin = 30;
  static const int soilMax = 80;
  static const double waterLow = 20.0;
}

// ─── Treatment Group ───────────────────────────────────────────────────────────
enum TreatmentGroup { control, magnetOnly, uvOnly, combined }

extension TreatmentGroupExt on TreatmentGroup {
  String get label {
    switch (this) {
      case TreatmentGroup.control: return 'Control';
      case TreatmentGroup.magnetOnly: return 'Magnet-Only';
      case TreatmentGroup.uvOnly: return 'UV-C Only';
      case TreatmentGroup.combined: return 'Combined';
    }
  }

  Color get color {
    switch (this) {
      case TreatmentGroup.control: return Colors.grey;
      case TreatmentGroup.magnetOnly: return const Color(0xFF6A1B9A);
      case TreatmentGroup.uvOnly: return const Color(0xFFF57F17);
      case TreatmentGroup.combined: return const Color(0xFF2E7D32);
    }
  }

  IconData get icon {
    switch (this) {
      case TreatmentGroup.control: return Icons.block;
      case TreatmentGroup.magnetOnly: return Icons.electric_bolt_rounded;
      case TreatmentGroup.uvOnly: return Icons.wb_sunny_rounded;
      case TreatmentGroup.combined: return Icons.science_rounded;
    }
  }

  // Thesis results
  String get day5Rate {
    switch (this) {
      case TreatmentGroup.control: return '~55%';
      case TreatmentGroup.magnetOnly: return '~68%';
      case TreatmentGroup.uvOnly: return '~72%';
      case TreatmentGroup.combined: return '~80%';
    }
  }

  String get day10Rate {
    switch (this) {
      case TreatmentGroup.control: return '70%';
      case TreatmentGroup.magnetOnly: return '83%';
      case TreatmentGroup.uvOnly: return '87%';
      case TreatmentGroup.combined: return '93%';
    }
  }

  String get rootDay10 {
    switch (this) {
      case TreatmentGroup.control: return '22.5 mm';
      case TreatmentGroup.magnetOnly: return '~28 mm';
      case TreatmentGroup.uvOnly: return '~30 mm';
      case TreatmentGroup.combined: return '34.7 mm';
    }
  }

  String get shootDay10 {
    switch (this) {
      case TreatmentGroup.control: return '15.4 mm';
      case TreatmentGroup.magnetOnly: return '~20 mm';
      case TreatmentGroup.uvOnly: return '~22 mm';
      case TreatmentGroup.combined: return '28.6 mm';
    }
  }

  bool get needsUV => this == TreatmentGroup.uvOnly || this == TreatmentGroup.combined;
  bool get needsMagnet => this == TreatmentGroup.magnetOnly || this == TreatmentGroup.combined;
}

// ─── Main Shell ────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  int soilMoisture = 0;
  double humidity = 0.0;
  double tempC = 0.0;
  double tempF = 0.0;
  double waterLevel = 0.0;

  bool uvActive = false;
  bool magnetActive = false;
  int uvDurationMinutes = 10;
  int magnetDurationMinutes = 15;
  TreatmentGroup selectedGroup = TreatmentGroup.combined;

  int uvSecondsLeft = 0;
  int magnetSecondsLeft = 0;
  Timer? _uvTimer;
  Timer? _magnetTimer;

  final List<Map<String, dynamic>> _history = [];

  late DatabaseReference _dbRef;
  late DatabaseReference _controlRef;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instance.ref("Sensor");
    _controlRef = FirebaseDatabase.instance.ref("Control");

    _dbRef.onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final now = DateTime.now();
        setState(() {
          soilMoisture = (data["SoilMoisture"] ?? 0).toInt();
          humidity = (data["Humidity"] ?? 0).toDouble();
          tempC = (data["TemperatureC"] ?? 0).toDouble();
          tempF = (data["TemperatureF"] ?? 0).toDouble();
          waterLevel = (data["WaterLevel"] ?? 0).toDouble();
        });
        _history.insert(0, {
          "time": "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
          "date": "${now.day}/${now.month}/${now.year}",
          "soilMoisture": soilMoisture,
          "humidity": humidity,
          "tempC": tempC,
          "waterLevel": waterLevel,
          "group": selectedGroup.label,
          "groupColor": selectedGroup.color,
        });
        if (_history.length > 100) _history.removeLast();
      }
    });

    _controlRef.onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          uvActive = (data["UV"] ?? false) as bool;
          magnetActive = (data["Magnet"] ?? false) as bool;
        });
      }
    });
  }

  String _fmt(int s) {
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _startUV() {
    _controlRef.update({"UV": true});
    setState(() { uvActive = true; uvSecondsLeft = uvDurationMinutes * 60; });
    _uvTimer?.cancel();
    _uvTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (uvSecondsLeft > 0) { uvSecondsLeft--; }
        else { uvActive = false; _controlRef.update({"UV": false}); t.cancel(); }
      });
    });
  }

  void _stopUV() {
    _uvTimer?.cancel();
    _controlRef.update({"UV": false});
    setState(() { uvActive = false; uvSecondsLeft = 0; });
  }

  void _startMagnet() {
    _controlRef.update({"Magnet": true});
    setState(() { magnetActive = true; magnetSecondsLeft = magnetDurationMinutes * 60; });
    _magnetTimer?.cancel();
    _magnetTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (magnetSecondsLeft > 0) { magnetSecondsLeft--; }
        else { magnetActive = false; _controlRef.update({"Magnet": false}); t.cancel(); }
      });
    });
  }

  void _stopMagnet() {
    _magnetTimer?.cancel();
    _controlRef.update({"Magnet": false});
    setState(() { magnetActive = false; magnetSecondsLeft = 0; });
  }

  @override
  void dispose() {
    _uvTimer?.cancel();
    _magnetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        soilMoisture: soilMoisture, humidity: humidity,
        tempC: tempC, tempF: tempF, waterLevel: waterLevel,
        uvActive: uvActive, magnetActive: magnetActive,
        selectedGroup: selectedGroup,
      ),
      DeployPage(
        uvActive: uvActive, magnetActive: magnetActive,
        uvSecondsLeft: uvSecondsLeft, magnetSecondsLeft: magnetSecondsLeft,
        uvDurationMinutes: uvDurationMinutes, magnetDurationMinutes: magnetDurationMinutes,
        selectedGroup: selectedGroup,
        soilMoisture: soilMoisture, humidity: humidity,
        tempC: tempC, waterLevel: waterLevel,
        onStartUV: _startUV, onStopUV: _stopUV,
        onStartMagnet: _startMagnet, onStopMagnet: _stopMagnet,
        onUVDurationChanged: (v) => setState(() => uvDurationMinutes = v),
        onMagnetDurationChanged: (v) => setState(() => magnetDurationMinutes = v),
        onGroupChanged: (g) => setState(() => selectedGroup = g),
        formatCountdown: _fmt,
      ),
      HistoryPage(history: _history),
      const SettingsPage(),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.dashboard_rounded, label: "Home", index: 0, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.rocket_launch_rounded, label: "To Deploy", index: 1, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.history_rounded, label: "History", index: 2, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(icon: Icons.settings_rounded, label: "Settings", index: 3, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label; final int index; final int current; final Function(int) onTap;
  const _NavItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2E7D32).withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? const Color(0xFF2E7D32) : Colors.grey.shade400, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.w700 : FontWeight.w400, color: isActive ? const Color(0xFF2E7D32) : Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard ─────────────────────────────────────────────────────────────────
class DashboardPage extends StatelessWidget {
  final int soilMoisture; final double humidity; final double tempC; final double tempF;
  final double waterLevel; final bool uvActive; final bool magnetActive; final TreatmentGroup selectedGroup;

  const DashboardPage({super.key, required this.soilMoisture, required this.humidity,
    required this.tempC, required this.tempF, required this.waterLevel,
    required this.uvActive, required this.magnetActive, required this.selectedGroup});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("SOLANOTRACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF2E7D32), letterSpacing: 2)),
                    Text("Magneto-UV System", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                  ]),
                  Row(children: [
                    _StatusChip(label: "UV", active: uvActive),
                    const SizedBox(width: 8),
                    _StatusChip(label: "MAG", active: magnetActive),
                    const SizedBox(width: 12),
                    Icon(Icons.notifications_outlined, color: Colors.grey.shade600, size: 26),
                  ]),
                ],
              ),
            )),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Text("Dashboard  ", style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: selectedGroup.color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(selectedGroup.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selectedGroup.color)),
                ),
              ]),
            )),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  GaugeCard(label: "Temperature", value: tempC, unit: "°C", min: 0, max: 50, color: const Color(0xFFE65100), optimalMin: SolanoRanges.tempMin, optimalMax: SolanoRanges.tempMax),
                  GaugeCard(label: "Humidity", value: humidity, unit: "%", min: 0, max: 100, color: const Color(0xFF1565C0), optimalMin: SolanoRanges.humidMin, optimalMax: SolanoRanges.humidMax),
                  GaugeCard(label: "Water Tank", value: waterLevel, unit: "%", min: 0, max: 100, color: const Color(0xFF00838F), optimalMin: SolanoRanges.waterLow, optimalMax: 100, lowWarning: waterLevel < SolanoRanges.waterLow),
                  GaugeCard(label: "Soil Moisture", value: soilMoisture.toDouble(), unit: "%", min: 0, max: 100, color: const Color(0xFF558B2F), optimalMin: SolanoRanges.soilMin.toDouble(), optimalMax: SolanoRanges.soilMax.toDouble()),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.92),
              ),
            ),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _SystemStatusCard(tempC: tempC, humidity: humidity, soilMoisture: soilMoisture, waterLevel: waterLevel),
            )),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _ExpectedResultsCard(group: selectedGroup),
            )),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label; final bool active;
  const _StatusChip({required this.label, required this.active});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2E7D32) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (active) ...[Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: active ? Colors.white : Colors.grey.shade500, letterSpacing: 1)),
      ]),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  final double tempC; final double humidity; final int soilMoisture; final double waterLevel;
  const _SystemStatusCard({required this.tempC, required this.humidity, required this.soilMoisture, required this.waterLevel});

  List<Map<String, dynamic>> get alerts {
    final list = <Map<String, dynamic>>[];
    if (tempC < SolanoRanges.tempMin) list.add({"msg": "Temperature below optimal (27°C)", "warn": true});
    if (tempC > SolanoRanges.tempMax) list.add({"msg": "Temperature above optimal (30°C)", "warn": true});
    if (humidity < SolanoRanges.humidMin) list.add({"msg": "Humidity below optimal (65%)", "warn": true});
    if (humidity > SolanoRanges.humidMax) list.add({"msg": "Humidity above optimal (80%)", "warn": true});
    if (soilMoisture < SolanoRanges.soilMin) list.add({"msg": "Soil moisture low — pump may activate", "warn": true});
    if (waterLevel < SolanoRanges.waterLow) list.add({"msg": "Water tank low — please refill", "warn": true});
    if (list.isEmpty) list.add({"msg": "All conditions within optimal range", "warn": false});
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final hasWarn = alerts.any((a) => a["warn"] == true);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hasWarn ? const Color(0xFFE65100).withOpacity(0.3) : const Color(0xFF2E7D32).withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasWarn ? Icons.warning_amber_rounded : Icons.check_circle_rounded, color: hasWarn ? const Color(0xFFE65100) : const Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 8),
          Text("System Status", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
        ]),
        const SizedBox(height: 10),
        ...alerts.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(Icons.circle, size: 6, color: a["warn"] ? const Color(0xFFE65100) : const Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Text(a["msg"], style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        )),
      ]),
    );
  }
}

class _ExpectedResultsCard extends StatelessWidget {
  final TreatmentGroup group;
  const _ExpectedResultsCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: group.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: group.color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.science_rounded, color: group.color, size: 18),
          const SizedBox(width: 8),
          Text("Expected Results — ${group.label}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: group.color)),
        ]),
        const SizedBox(height: 12),
        _ResultRow("Day 5 Germination", group.day5Rate, group.color),
        _ResultRow("Day 10 Germination", group.day10Rate, group.color),
        _ResultRow("Root Length (Day 10)", group.rootDay10, group.color),
        _ResultRow("Shoot Height (Day 10)", group.shootDay10, group.color),
      ]),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label; final String value; final Color color;
  const _ResultRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─── Gauge Card ────────────────────────────────────────────────────────────────
class GaugeCard extends StatelessWidget {
  final String label; final double value; final String unit;
  final double min; final double max; final Color color;
  final double optimalMin; final double optimalMax; final bool lowWarning;

  const GaugeCard({super.key, required this.label, required this.value, required this.unit,
    required this.min, required this.max, required this.color,
    required this.optimalMin, required this.optimalMax, this.lowWarning = false});

  bool get isOptimal => value >= optimalMin && value <= optimalMax;

  @override
  Widget build(BuildContext context) {
    final statusColor = lowWarning ? const Color(0xFFD32F2F) : isOptimal ? const Color(0xFF2E7D32) : Colors.orange.shade700;
    final statusLabel = lowWarning ? "⚠ Low" : isOptimal ? "✓ Optimal" : "↕ Adjust";

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.25), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          height: 100, width: 100,
          child: CustomPaint(
            painter: GaugePainter(value: value, min: min, max: max, color: color),
            child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text("${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}$unit",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              const SizedBox(height: 8),
            ])),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
          child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
        ),
      ]),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value; final double min; final double max; final Color color;
  GaugePainter({required this.value, required this.min, required this.max, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.72);
    final radius = size.width * 0.42;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false,
        Paint()..color = Colors.grey.shade100..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round);

    final progress = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final gaugeColor = progress < 0.5
        ? Color.lerp(const Color(0xFF558B2F), const Color(0xFFFFA000), progress * 2)!
        : Color.lerp(const Color(0xFFFFA000), const Color(0xFFD32F2F), (progress - 0.5) * 2)!;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * progress, false,
        Paint()..color = gaugeColor..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset pos) {
      tp.text = TextSpan(text: text, style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.w600));
      tp.layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    drawLabel(min.toInt().toString(), center + Offset(-radius * 0.85, radius * 0.38));
    drawLabel(max.toInt().toString(), center + Offset(radius * 0.85, radius * 0.38));
  }

  @override
  bool shouldRepaint(GaugePainter old) => old.value != value;
}

// ─── Deploy Page ───────────────────────────────────────────────────────────────
class DeployPage extends StatelessWidget {
  final bool uvActive; final bool magnetActive;
  final int uvSecondsLeft; final int magnetSecondsLeft;
  final int uvDurationMinutes; final int magnetDurationMinutes;
  final TreatmentGroup selectedGroup;
  final int soilMoisture; final double humidity; final double tempC; final double waterLevel;
  final VoidCallback onStartUV; final VoidCallback onStopUV;
  final VoidCallback onStartMagnet; final VoidCallback onStopMagnet;
  final Function(int) onUVDurationChanged; final Function(int) onMagnetDurationChanged;
  final Function(TreatmentGroup) onGroupChanged;
  final String Function(int) formatCountdown;

  const DeployPage({super.key, required this.uvActive, required this.magnetActive,
    required this.uvSecondsLeft, required this.magnetSecondsLeft,
    required this.uvDurationMinutes, required this.magnetDurationMinutes,
    required this.selectedGroup, required this.soilMoisture, required this.humidity,
    required this.tempC, required this.waterLevel,
    required this.onStartUV, required this.onStopUV,
    required this.onStartMagnet, required this.onStopMagnet,
    required this.onUVDurationChanged, required this.onMagnetDurationChanged,
    required this.onGroupChanged, required this.formatCountdown});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("SOLANOTRACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF2E7D32), letterSpacing: 2)),
            Text("To Deploy", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text("Select treatment group and start timed cycles", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            Text("Treatment Group", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            Row(
              children: TreatmentGroup.values.map((g) {
                final selected = g == selectedGroup;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onGroupChanged(g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? g.color : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? g.color : Colors.grey.shade200),
                      ),
                      child: Column(children: [
                        Icon(g.icon, color: selected ? Colors.white : g.color, size: 18),
                        const SizedBox(height: 4),
                        Text(g.label.replaceAll('-', '\n'), textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade600)),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            _TimedControlCard(
              title: "UV-C Treatment", subtitle: "Seed surface sterilization",
              icon: Icons.wb_sunny_rounded, color: const Color(0xFFF57F17),
              active: uvActive, secondsLeft: uvSecondsLeft, durationMinutes: uvDurationMinutes,
              onStart: onStartUV, onStop: onStopUV, onDurationChanged: onUVDurationChanged,
              formatCountdown: formatCountdown, enabled: selectedGroup.needsUV,
            ),
            const SizedBox(height: 14),

            _TimedControlCard(
              title: "Magnet Treatment", subtitle: "DC motor magneto-priming cycle",
              icon: Icons.electric_bolt_rounded, color: const Color(0xFF6A1B9A),
              active: magnetActive, secondsLeft: magnetSecondsLeft, durationMinutes: magnetDurationMinutes,
              onStart: onStartMagnet, onStop: onStopMagnet, onDurationChanged: onMagnetDurationChanged,
              formatCountdown: formatCountdown, enabled: selectedGroup.needsMagnet,
            ),
            const SizedBox(height: 20),

            Text("Pre-Deployment Check", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 10),
            _CheckItem(label: "Temperature", value: "${tempC.toStringAsFixed(1)}°C", detail: "Optimal: 27–30°C", ok: tempC >= SolanoRanges.tempMin && tempC <= SolanoRanges.tempMax),
            const SizedBox(height: 8),
            _CheckItem(label: "Humidity", value: "${humidity.toStringAsFixed(1)}%", detail: "Optimal: 65–80%", ok: humidity >= SolanoRanges.humidMin && humidity <= SolanoRanges.humidMax),
            const SizedBox(height: 8),
            _CheckItem(label: "Soil Moisture", value: "$soilMoisture%", detail: "Optimal: 30–80%", ok: soilMoisture >= SolanoRanges.soilMin && soilMoisture <= SolanoRanges.soilMax),
            const SizedBox(height: 8),
            _CheckItem(label: "Water Tank", value: "${waterLevel.toStringAsFixed(0)}%", detail: "Minimum: 20%", ok: waterLevel >= SolanoRanges.waterLow),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

class _TimedControlCard extends StatelessWidget {
  final String title; final String subtitle; final IconData icon; final Color color;
  final bool active; final int secondsLeft; final int durationMinutes;
  final VoidCallback onStart; final VoidCallback onStop;
  final Function(int) onDurationChanged; final String Function(int) formatCountdown;
  final bool enabled;

  const _TimedControlCard({required this.title, required this.subtitle, required this.icon,
    required this.color, required this.active, required this.secondsLeft,
    required this.durationMinutes, required this.onStart, required this.onStop,
    required this.onDurationChanged, required this.formatCountdown, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: !enabled ? Colors.grey.shade50 : active ? color.withOpacity(0.07) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: !enabled ? Colors.grey.shade200 : active ? color.withOpacity(0.4) : Colors.grey.shade200, width: active ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: !enabled ? Colors.grey.shade100 : active ? color.withOpacity(0.15) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: !enabled ? Colors.grey.shade400 : active ? color : Colors.grey.shade400, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: enabled ? Colors.grey.shade800 : Colors.grey.shade400)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ])),
          if (!enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text("N/A", style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
            ),
        ]),
        if (enabled) ...[
          const SizedBox(height: 14),
          Row(children: [
            Text("Duration: ", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            Text("$durationMinutes min", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
          Slider(
            value: durationMinutes.toDouble(), min: 1, max: 60, divisions: 59,
            activeColor: color, inactiveColor: color.withOpacity(0.15),
            onChanged: active ? null : (v) => onDurationChanged(v.toInt()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: active
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Time remaining", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    Text(formatCountdown(secondsLeft),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, fontFamily: 'monospace')),
                  ])
                : const SizedBox.shrink()),
            GestureDetector(
              onTap: active ? onStop : onStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(color: active ? const Color(0xFFD32F2F) : color, borderRadius: BorderRadius.circular(12)),
                child: Text(active ? "Stop" : "Start", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String label; final String value; final String detail; final bool ok;
  const _CheckItem({required this.label, required this.value, required this.detail, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F), size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          Text(detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ])),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F))),
      ]),
    );
  }
}

// ─── History Page ──────────────────────────────────────────────────────────────
class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const HistoryPage({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("SOLANOTRACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF2E7D32), letterSpacing: 2)),
            Text("History", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text("${history.length} readings logged", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            Expanded(
              child: history.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text("No readings yet", style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                      Text("Data appears once sensors are active", style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                    ]))
                  : ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = history[i];
                        final gc = e['groupColor'] as Color;
                        final tC = e['tempC'] as double;
                        final hC = e['humidity'] as double;
                        final sC = e['soilMoisture'] as int;
                        final wC = e['waterLevel'] as double;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade100)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text("${e['time']}  ${e['date']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: gc.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(e['group'] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: gc)),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              _HistoryChip(label: "🌡 ${tC.toStringAsFixed(1)}°C", ok: tC >= SolanoRanges.tempMin && tC <= SolanoRanges.tempMax),
                              _HistoryChip(label: "💧 ${hC.toStringAsFixed(1)}%", ok: hC >= SolanoRanges.humidMin && hC <= SolanoRanges.humidMax),
                              _HistoryChip(label: "🌱 $sC%", ok: sC >= SolanoRanges.soilMin && sC <= SolanoRanges.soilMax),
                              _HistoryChip(label: "🪣 ${wC.toStringAsFixed(0)}%", ok: wC >= SolanoRanges.waterLow),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label; final bool ok;
  const _HistoryChip({required this.label, required this.ok});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF2E7D32).withOpacity(0.07) : const Color(0xFFD32F2F).withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F))),
    );
  }
}

// ─── Settings Page ─────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notifications = true;
  bool autoRefresh = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("SOLANOTRACK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF2E7D32), letterSpacing: 2)),
            Text("Settings", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
            const SizedBox(height: 24),
            _SettingsSection(title: "Preferences", children: [
              _SettingsTile(icon: Icons.notifications_rounded, label: "Notifications",
                  trailing: Switch(value: notifications, onChanged: (v) => setState(() => notifications = v), activeColor: const Color(0xFF2E7D32))),
              _SettingsTile(icon: Icons.refresh_rounded, label: "Auto Refresh",
                  trailing: Switch(value: autoRefresh, onChanged: (v) => setState(() => autoRefresh = v), activeColor: const Color(0xFF2E7D32))),
            ]),
            const SizedBox(height: 16),
            _SettingsSection(title: "Optimal Ranges (Thesis-based)", children: [
              _SettingsTile(icon: Icons.thermostat_rounded, label: "Temperature", trailing: Text("27–30°C", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              _SettingsTile(icon: Icons.water_drop_rounded, label: "Humidity", trailing: Text("65–80%", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              _SettingsTile(icon: Icons.grass_rounded, label: "Soil Moisture", trailing: Text("30–80%", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              _SettingsTile(icon: Icons.water_rounded, label: "Water Tank Min", trailing: Text("20%", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
            ]),
            const SizedBox(height: 16),
            _SettingsSection(title: "About", children: [
              _SettingsTile(icon: Icons.info_outline_rounded, label: "Version", trailing: Text("1.0.0", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              _SettingsTile(icon: Icons.science_rounded, label: "Project", trailing: Text("SolanoTrack", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              _SettingsTile(icon: Icons.school_rounded, label: "Institution", trailing: Text("UMTC", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title; final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
        child: Column(children: children),
      ),
    ]);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String label; final Widget trailing;
  const _SettingsTile({required this.icon, required this.label, required this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700))),
        trailing,
      ]),
    );
  }
}