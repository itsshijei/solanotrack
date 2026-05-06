import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

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
      title: 'IoT Plant Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Smart Plant Dashboard'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref("Sensor");

  int soilMoisture = 0;
  double humidity = 0.0;
  double tempC = 0.0;
  double tempF = 0.0;

  @override
  void initState() {
    super.initState();

    _dbRef.onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          soilMoisture = data["SoilMoisture"] ?? 0;
          humidity = (data["Humidity"] ?? 0).toDouble();
          tempC = (data["TemperatureC"] ?? 0).toDouble();
          tempF = (data["TemperatureF"] ?? 0).toDouble();
        });
      }
    });
  }

  Widget buildSensorCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, color: Colors.black87),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            buildSensorCard(
              "🌱 Soil Moisture",
              "$soilMoisture",
              Icons.water_drop,
              Colors.brown,
            ),
            buildSensorCard(
              "💧 Humidity",
              "${humidity.toStringAsFixed(1)} %",
              Icons.cloud,
              Colors.blue,
            ),
            buildSensorCard(
              "🌡️ Temperature",
              "${tempC.toStringAsFixed(1)} °C / ${tempF.toStringAsFixed(1)} °F",
              Icons.thermostat,
              Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}
