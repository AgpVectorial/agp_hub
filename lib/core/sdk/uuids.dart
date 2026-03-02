/// UUID-uri standard folosite frecvent.
/// Multe dispozitive folosesc UUID-uri custom; de aceea folosim matching „contains” cu hexa low-case.
class UuidsCfg {
  // Heart Rate: Service 0x180D, Char 0x2A37
  static const String hrService = '180d';
  static const String hrMeasurement = '2a37';

  // Battery: Service 0x180F, Char 0x2A19
  static const String batteryService = '180f';
  static const String batteryLevel = '2a19';

  // SpO2 (Pulse Oximeter): Service 0x1822, Chars 0x2A5F (Continuous) / 0x2A60 (Spot)
  static const String spo2Service = '1822';
  static const String spo2Continuous = '2a5f';
  static const String spo2Spot = '2a60';

  // Step Count: Char 0x2ACD (uneori sub diverse servicii de activitate)
  static const String stepsChar = '2acd';

  // Calories – de obicei NU e standardizat; unele device-uri pun „Energy Expended”
  // ca field în Heart Rate Measurement (dacă bitul 3 din flags este setat).
  // Lăsăm și o listă pentru UUID-uri custom (poți adăuga aici când afli de la OEM).
  static const List<String> caloriesCustomChars = [
    // ex: 'xxxx' // adaugă uuid custom lower-case fără cratime
  ];
}
