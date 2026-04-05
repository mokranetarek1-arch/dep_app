import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'firebase_options.dart';

const Color kBg = Color(0xFFF6F1E5);
const Color kPanel = Color(0xFFFFFCF6);
const Color kPrimary = Color(0xFFD9481B);
const Color kLine = Color(0xFFE7DCC6);
const Color kText = Color(0xFF1E1E1F);
const Color kMuted = Color(0xFF6C6C70);
const Color kAccent = Color(0xFF0E7490);
const Color kSuccess = Color(0xFF1F7A4D);
const Color kDanger = Color(0xFFC0392B);
const Color kWarning = Color(0xFFD97706);
const String kDriverAuthPassword = 'DriverTest123!';
const String kIncomingTripAsset = 'sounds/depson.mp3';
const AndroidNotificationChannel kTripAlertsChannel =
    AndroidNotificationChannel(
      'trip_alerts',
      'Trip Alerts',
      description: 'Alertes immediates pour les nouvelles courses chauffeur.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await DriverNotificationService.ensureInitialized();
  await DriverNotificationService.showTripNotificationFromMessage(message);
}

class DriverNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;

  static Future<void> ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(kTripAlertsChannel);

    _isInitialized = true;
  }

  static Future<void> requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
  }

  static bool isTripMessage(RemoteMessage message) {
    final title = '${message.notification?.title ?? message.data['title'] ?? ''}'
        .trim()
        .toLowerCase();
    final type = '${message.data['type'] ?? message.data['screen'] ?? ''}'
        .trim()
        .toLowerCase();
    final collection = '${message.data['collection'] ?? ''}'
        .trim()
        .toLowerCase();

    return title.contains('course') ||
        title.contains('mission') ||
        type == 'trip' ||
        type == 'incoming_trip' ||
        collection == 'requests';
  }

  static Future<void> showTripNotification({
    required String title,
    required String body,
  }) async {
    await ensureInitialized();

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kTripAlertsChannel.id,
          kTripAlertsChannel.name,
          channelDescription: kTripAlertsChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'Nouvelle course',
          playSound: true,
          enableVibration: true,
          sound: const RawResourceAndroidNotificationSound('depson'),
        ),
      ),
    );
  }

  static Future<void> showTripNotificationFromMessage(
    RemoteMessage message,
  ) async {
    if (!isTripMessage(message)) {
      return;
    }

    final title =
        '${message.notification?.title ?? message.data['title'] ?? 'Nouvelle course'}'
            .trim();
    final depart =
        '${message.data['depart'] ?? message.data['pickupAddress'] ?? ''}'
            .trim();
    final destination =
        '${message.data['destination'] ?? message.data['destinationAddress'] ?? ''}'
            .trim();
    final fallbackBody = [depart, destination]
        .where((part) => part.isNotEmpty)
        .join(' -> ');
    final body =
        '${message.notification?.body ?? message.data['body'] ?? (fallbackBody.isEmpty ? 'Ouvre l application pour repondre a la course.' : fallbackBody)}'
            .trim();

    await showTripNotification(title: title, body: body);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await DriverNotificationService.ensureInitialized();
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CRMDEP Driver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          primary: kPrimary,
          surface: kPanel,
        ),
        scaffoldBackgroundColor: kBg,
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kPanel,
          indicatorColor: const Color(0xFFFFE1D6),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? kPrimary
                  : kMuted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
            );
          }),
        ),
        cardTheme: CardThemeData(
          color: kPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: kLine),
          ),
        ),
        useMaterial3: true,
      ),
      home: const DriverGate(),
    );
  }
}

class DriverGate extends StatefulWidget {
  const DriverGate({super.key});

  @override
  State<DriverGate> createState() => _DriverGateState();
}

class _DriverGateState extends State<DriverGate> {
  String? _driverPhone;

  void _handleLoginSuccess(String phone) {
    setState(() => _driverPhone = normalizePhone(phone));
  }

  void _handleLogout() {
    setState(() => _driverPhone = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_driverPhone == null) {
      return AuthScreen(onLoginSuccess: _handleLoginSuccess);
    }

    return DriverHome(driverPhone: _driverPhone!, onLogout: _handleLogout);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onLoginSuccess});

  final ValueChanged<String> onLoginSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginPhoneController = TextEditingController();

  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _loginPhoneController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final phone = normalizePhone(_loginPhoneController.text);

    if (phone.isEmpty) {
      setState(() => _message = 'Saisis ton numero de telephone.');
      return;
    }

    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: phoneToAuthEmail(phone),
        password: kDriverAuthPassword,
      );

      final driversQuery = await FirebaseFirestore.instance
          .collection('drivers')
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? matchingDriver;
      for (final doc in driversQuery.docs) {
        final driverPhone = normalizePhone('${doc.data()['phone'] ?? ''}');
        if (phonesMatch(phone, driverPhone)) {
          matchingDriver = doc;
          break;
        }
      }

      if (matchingDriver == null) {
        await FirebaseAuth.instance.signOut();
        setState(
          () => _message = 'Aucun compte chauffeur trouve pour ce numero.',
        );
        return;
      }

      final driverData = matchingDriver.data();
      if (driverData['isApproved'] == false ||
          driverData['isActive'] == false) {
        await FirebaseAuth.instance.signOut();
        setState(
          () => _message = 'Ce compte chauffeur est desactive ou non valide.',
        );
        return;
      }

      widget.onLoginSuccess('${driverData['phone'] ?? phone}');
    } on FirebaseAuthException {
      setState(() {
        _message =
            'Compte Auth introuvable. Cree ${phoneToAuthEmail(phone)} dans Firebase Auth avec le mot de passe $kDriverAuthPassword.';
      });
    } catch (_) {
      setState(
        () => _message = 'Connexion impossible pour le moment. Reessaie.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CRMDEP Driver',
                      style: TextStyle(
                        color: Color(0xFFFFE1D6),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Espace chauffeur assistance routiere',
                      style: TextStyle(
                        color: Color(0xFFFFF8F3),
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Connexion temporaire par numero uniquement pour afficher directement les comptes chauffeurs deja ajoutes.',
                      style: TextStyle(
                        color: Color(0xFFFFEEE7),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kLine),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Connexion chauffeur',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: kText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DriverTextField(
                      controller: _loginPhoneController,
                      label: 'Numero de telephone',
                      hint: '0552466823',
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Mode test temporaire: entre seulement le numero du chauffeur deja present dans drivers.',
                        style: TextStyle(color: kMuted, height: 1.45),
                      ),
                    ),
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _message,
                          style: TextStyle(
                            color: kDanger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _busy ? null : _login,
                        child: Text(_busy ? 'Veuillez patienter...' : 'Entrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverHome extends StatefulWidget {
  const DriverHome({
    super.key,
    required this.driverPhone,
    required this.onLogout,
  });

  final String driverPhone;
  final VoidCallback onLogout;

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  int _currentIndex = 0;
  bool _requestingLocation = false;
  String? _trackingDriverId;
  String? _notificationDriverId;
  String _locationState = 'Localisation non activee';
  Position? _lastPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  final Set<String> _seenIncomingRequestIds = <String>{};
  final Map<String, String> _knownRequestStatuses = <String, String>{};
  String? _activeIncomingRequestId;
  bool _incomingRequestsInitialized = false;
  final AudioPlayer _ringtonePlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((message) {
      DriverNotificationService.showTripNotificationFromMessage(message);
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _ringtonePlayer.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _ringtonePlayer.stop();
    await FirebaseAuth.instance.signOut();
    widget.onLogout();
  }

  Future<void> _activateLocationTracking(
    String driverId,
    Map<String, dynamic> driver,
  ) async {
    if (_requestingLocation || _trackingDriverId == driverId) {
      return;
    }

    _requestingLocation = true;
    if (mounted) {
      setState(() => _locationState = 'Demande de permission GPS...');
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _locationState = 'Active le GPS du telephone');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _locationState = 'Permission localisation refusee');
        }
        return;
      }

      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      );
      await _publishDriverLocation(driverId, driver, current);

      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((position) {
        _publishDriverLocation(driverId, driver, position);
      });

      _trackingDriverId = driverId;
    } catch (_) {
      if (mounted) {
        setState(() => _locationState = 'Localisation indisponible');
      }
    } finally {
      _requestingLocation = false;
    }
  }

  Future<void> _ensureDriverNotificationsReady(String driverId) async {
    if (_notificationDriverId == driverId) {
      return;
    }

    _notificationDriverId = driverId;
    await DriverNotificationService.requestPermissions();
    await _syncNotificationToken(driverId);

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) {
      _saveNotificationToken(driverId, token);
    });
  }

  Future<void> _syncNotificationToken(String driverId) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _saveNotificationToken(driverId, token);
  }

  Future<void> _saveNotificationToken(String driverId, String token) {
    return FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
      'fcmToken': token,
      'notificationTokens': FieldValue.arrayUnion([token]),
      'lastNotificationTokenAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _publishDriverLocation(
    String driverId,
    Map<String, dynamic> driver,
    Position position,
  ) async {
    await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
      'currentLocation': {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
      },
      'lastLocationAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() {
        _lastPosition = position;
        _locationState =
            'GPS actif • precision ${position.accuracy.toStringAsFixed(0)} m';
      });
    }
  }

  Future<void> _updateMissionStatus(String missionId, String status) {
    return FirebaseFirestore.instance
        .collection('requests')
        .doc(missionId)
        .update({
          'status': status,
          'dispatch': requestDispatchLabel(status),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  void _handleIncomingRequests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> missions,
  ) {
    if (!_incomingRequestsInitialized) {
      for (final doc in missions) {
        _seenIncomingRequestIds.add(doc.id);
        _knownRequestStatuses[doc.id] = requestStatus(doc.data());
      }
      _incomingRequestsInitialized = true;
      return;
    }

    final assignedRequests = missions.where((doc) {
      return requestStatus(doc.data()) == 'assigned';
    }).toList();

    for (final doc in assignedRequests) {
      if (_activeIncomingRequestId == doc.id) {
        return;
      }

      final previousStatus = _knownRequestStatuses[doc.id];
      final isNewRequest = !_seenIncomingRequestIds.contains(doc.id);
      final becameAssigned = previousStatus != 'assigned';

      if (isNewRequest || becameAssigned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showIncomingTripDialog(doc);
        });
        return;
      }
    }

    for (final doc in missions) {
      _seenIncomingRequestIds.add(doc.id);
      _knownRequestStatuses[doc.id] = requestStatus(doc.data());
    }
  }

  Future<void> _showIncomingTripDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!mounted || _activeIncomingRequestId == doc.id) {
      return;
    }

    _activeIncomingRequestId = doc.id;
    final data = doc.data();
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    await _ringtonePlayer.stop();
    await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    await _ringtonePlayer.play(AssetSource(kIncomingTripAsset), volume: 1);
    if (!mounted) {
      await _ringtonePlayer.stop();
      _activeIncomingRequestId = null;
      return;
    }
    final ringtoneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      HapticFeedback.mediumImpact();
    });

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Nouvelle course',
        pageBuilder: (context, animation, secondaryAnimation) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: kPanel,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: kPrimary, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 28,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE2D7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Nouvelle course',
                            style: TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          tripTitle(data),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 18),
                        InfoLine(
                          label: 'Depart',
                          value:
                              '${data['depart'] ?? data['pickupAddress'] ?? '-'}',
                        ),
                        InfoLine(
                          label: 'Destination',
                          value:
                              '${data['destination'] ?? data['destinationAddress'] ?? '-'}',
                        ),
                        InfoLine(
                          label: 'Client',
                          value:
                              '${data['Phone'] ?? data['clientPhone'] ?? data['phone'] ?? '-'}',
                        ),
                        InfoLine(
                          label: 'Montant',
                          value: formatMoney(tripAmount(data)),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kDanger,
                                  side: const BorderSide(color: kDanger),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                onPressed: () async {
                                  final navigator = Navigator.of(context);
                                  await _updateMissionStatus(doc.id, 'cancelled');
                                  if (navigator.mounted) {
                                    navigator.pop();
                                  }
                                },
                                child: const Text('Refuser'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                onPressed: () async {
                                  final navigator = Navigator.of(context);
                                  await _updateMissionStatus(doc.id, 'accepted');
                                  if (navigator.mounted) {
                                    navigator.pop();
                                  }
                                },
                                child: const Text('Accepter'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        },
      );
    } finally {
      ringtoneTimer.cancel();
      await _ringtonePlayer.stop();
      _activeIncomingRequestId = null;
      _seenIncomingRequestIds.add(doc.id);
      _knownRequestStatuses[doc.id] = requestStatus(doc.data());
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, driverSnapshot) {
        if (driverSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen(
            message: 'Chargement du profil chauffeur...',
          );
        }

        final driverDocs = driverSnapshot.data?.docs ?? [];
        QueryDocumentSnapshot<Map<String, dynamic>>? matchingDriver;
        for (final doc in driverDocs) {
          final driverPhone = normalizePhone('${doc.data()['phone'] ?? ''}');
          if (phonesMatch(widget.driverPhone, driverPhone)) {
            matchingDriver = doc;
            break;
          }
        }

        if (matchingDriver == null) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_off_outlined,
                        size: 52,
                        color: kDanger,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Profil chauffeur introuvable dans drivers.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _logout,
                        child: const Text('Se deconnecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final driverDoc = matchingDriver;
        final driver = driverDoc.data();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureDriverNotificationsReady(driverDoc.id);
          _activateLocationTracking(driverDoc.id, driver);
        });

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('requests').snapshots(),
          builder: (context, missionSnapshot) {
            if (missionSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen(message: 'Chargement des missions...');
            }

            final List<QueryDocumentSnapshot<Map<String, dynamic>>> missions =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  (missionSnapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                      .where(
                        (doc) => isDriverRequest(doc.data(), driverDoc.id),
                      ),
                )..sort((a, b) {
                  final left = extractComparableDate(b.data());
                  final right = extractComparableDate(a.data());
                  final leftSeconds = left is Timestamp ? left.seconds : 0;
                  final rightSeconds = right is Timestamp ? right.seconds : 0;
                  return leftSeconds.compareTo(rightSeconds);
                });

            final completed = missions
                .where((doc) => isCompletedRequest(doc.data()))
                .toList();
            final inProgress = missions.where((doc) {
              return isInProgressRequest(doc.data());
            }).toList();

            _handleIncomingRequests(missions);

            final paidCommissionFuture = FirebaseFirestore.instance
                .collection('driverPayments')
                .where('driverId', isEqualTo: driverDoc.id)
                .where('regle', isEqualTo: true)
                .get();

            final estimatedCommission = completed.fold<double>(0, (total, doc) {
              final data = doc.data();
              return total + tripAmount(data);
            });

            final pages = [
              TripsPage(
                driver: driver,
                inProgressCount: inProgress.length,
                completedCount: completed.length,
                locationState: _locationState,
                lastPosition: _lastPosition,
                onRequestLocation: () =>
                    _activateLocationTracking(driverDoc.id, driver),
                missions: missions,
                onMissionStatusChanged: _updateMissionStatus,
              ),
              CommissionPage(
                missions: missions,
                estimatedCommission: estimatedCommission,
                paidCommissionFuture: paidCommissionFuture,
              ),
              ProfilePage(
                driver: driver,
                onLogout: _logout,
                locationState: _locationState,
                lastPosition: _lastPosition,
                onRequestLocation: () =>
                    _activateLocationTracking(driverDoc.id, driver),
              ),
            ];

            return Scaffold(
              body: SafeArea(child: pages[_currentIndex]),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) =>
                    setState(() => _currentIndex = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.local_shipping_outlined),
                    selectedIcon: Icon(Icons.local_shipping),
                    label: 'Courses',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.payments_outlined),
                    selectedIcon: Icon(Icons.payments),
                    label: 'Commission',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profil',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class DriverTextField extends StatelessWidget {
  const DriverTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: kMuted),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kLine),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kLine),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class TripsPage extends StatelessWidget {
  const TripsPage({
    super.key,
    required this.driver,
    required this.inProgressCount,
    required this.completedCount,
    required this.locationState,
    required this.lastPosition,
    required this.onRequestLocation,
    required this.missions,
    required this.onMissionStatusChanged,
  });

  final Map<String, dynamic> driver;
  final int inProgressCount;
  final int completedCount;
  final String locationState;
  final Position? lastPosition;
  final Future<void> Function() onRequestLocation;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> missions;
  final Future<void> Function(String missionId, String status)
  onMissionStatusChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderCard(
            title: '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'
                .trim(),
            subtitle: '${driver['phone'] ?? '-'} | ${driver['wilaya'] ?? '-'}',
            eyebrow: 'Chauffeur connecte',
            trailing: const StatusBadge(
              label: 'GPS suivi',
              color: kAccent,
            ),
          ),
          const SizedBox(height: 16),
          MetricCard(
            label: 'Courses en cours',
            value: inProgressCount.toString(),
            backgroundColor: const Color(0xFFFFD8C9),
            valueColor: kText,
            labelColor: kMuted,
          ),
          const SizedBox(height: 12),
          MetricCard(
            label: 'Courses terminees',
            value: completedCount.toString(),
            backgroundColor: const Color(0xFFD7F4E3),
            valueColor: kText,
            labelColor: kMuted,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Localisation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLine(label: 'Etat GPS', value: locationState),
                InfoLine(
                  label: 'Latitude',
                  value: lastPosition == null
                      ? '-'
                      : lastPosition!.latitude.toStringAsFixed(6),
                ),
                InfoLine(
                  label: 'Longitude',
                  value: lastPosition == null
                      ? '-'
                      : lastPosition!.longitude.toStringAsFixed(6),
                ),
                InfoLine(
                  label: 'Precision',
                  value: lastPosition == null
                      ? '-'
                      : '${lastPosition!.accuracy.toStringAsFixed(0)} m',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => onRequestLocation(),
                    child: const Text('Activer ma localisation'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Mes courses',
            child: missions.isEmpty
                ? const Text(
                    'Aucune course pour le moment.',
                    style: TextStyle(color: kMuted),
                  )
                : Column(
                    children: missions.map((doc) {
                      final data = doc.data();
                      final status = requestStatus(data);
                      return MissionCard(
                        data: data,
                        status: status,
                        onMissionStatusChanged: (nextStatus) =>
                            onMissionStatusChanged(doc.id, nextStatus),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class CommissionPage extends StatelessWidget {
  const CommissionPage({
    super.key,
    required this.missions,
    required this.estimatedCommission,
    required this.paidCommissionFuture,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> missions;
  final double estimatedCommission;
  final Future<QuerySnapshot<Map<String, dynamic>>> paidCommissionFuture;

  @override
  Widget build(BuildContext context) {
    final completedMissions = missions
        .where((doc) => isCompletedRequest(doc.data()))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderCard(
            title: 'Commission chauffeur',
            subtitle:
                'Vue simple sur les montants generes et les paiements valides.',
            eyebrow: 'Finance',
          ),
          const SizedBox(height: 16),
          MetricCard(
            label: 'Commission estimee',
            value: formatMoney(estimatedCommission),
            backgroundColor: const Color(0xFF16323A),
            valueColor: Colors.white,
            labelColor: const Color(0xFFABD8E4),
          ),
          const SizedBox(height: 12),
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: paidCommissionFuture,
            builder: (context, snapshot) {
              final paidAmount = (snapshot.data?.docs ?? []).fold<double>(0, (
                total,
                doc,
              ) {
                return total + ((doc.data()['amount'] ?? 0) as num).toDouble();
              });
              final remaining = (estimatedCommission - paidAmount)
                  .clamp(0, double.infinity)
                  .toDouble();

              return Column(
                children: [
                  MetricCard(
                    label: 'Montant traite',
                    value: formatMoney(paidAmount),
                    backgroundColor: const Color(0xFFD7F4E3),
                    valueColor: kText,
                    labelColor: kMuted,
                  ),
                  const SizedBox(height: 12),
                  MetricCard(
                    label: 'Reste estime',
                    value: formatMoney(remaining),
                    backgroundColor: const Color(0xFFF8DDD8),
                    valueColor: kText,
                    labelColor: kMuted,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Courses terminees',
            child: completedMissions.isEmpty
                ? const Text(
                    'Aucune course terminee pour le moment.',
                    style: TextStyle(color: kMuted),
                  )
                : Column(
                    children: completedMissions.map((doc) {
                      final data = doc.data();
                      final amount = tripAmount(data);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kLine),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tripTitle(data),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: kText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${data['depart'] ?? data['pickupAddress'] ?? '-'} -> ${data['destination'] ?? data['destinationAddress'] ?? '-'}',
                                    style: const TextStyle(color: kMuted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatMoney(amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: kPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.driver,
    required this.onLogout,
    required this.locationState,
    required this.lastPosition,
    required this.onRequestLocation,
  });

  final Map<String, dynamic> driver;
  final Future<void> Function() onLogout;
  final String locationState;
  final Position? lastPosition;
  final Future<void> Function() onRequestLocation;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderCard(
            title: 'Mon profil',
            subtitle: 'Informations du chauffeur et etat du compte mobile.',
            eyebrow: 'Profil',
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Localisation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileLine(label: 'Etat GPS', value: locationState),
                ProfileLine(
                  label: 'Latitude',
                  value: lastPosition == null
                      ? '-'
                      : lastPosition!.latitude.toStringAsFixed(6),
                ),
                ProfileLine(
                  label: 'Longitude',
                  value: lastPosition == null
                      ? '-'
                      : lastPosition!.longitude.toStringAsFixed(6),
                ),
                ProfileLine(
                  label: 'Precision',
                  value: lastPosition == null
                      ? '-'
                      : '${lastPosition!.accuracy.toStringAsFixed(0)} m',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onRequestLocation(),
                    child: const Text('Demander la localisation'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Informations',
            child: Column(
              children: [
                ProfileLine(
                  label: 'Prenom',
                  value: '${driver['firstName'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Nom',
                  value: '${driver['lastName'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Telephone',
                  value: '${driver['phone'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Wilaya',
                  value: '${driver['wilaya'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Region',
                  value: '${driver['region'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Camions',
                  value: '${driver['trucks'] ?? '-'}',
                ),
                ProfileLine(
                  label: 'Compte cree',
                  value: driver['accountCreated'] == true ? 'Oui' : 'Non',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: onLogout,
              child: const Text('Se deconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

class HeaderCard extends StatelessWidget {
  const HeaderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBF6), Color(0xFFFFEFE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: kText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: const TextStyle(color: kMuted)),
                  ],
                ),
              ),
              if (trailing != null) const SizedBox(width: 12),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD2C2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class MissionCard extends StatelessWidget {
  const MissionCard({
    super.key,
    required this.data,
    required this.status,
    required this.onMissionStatusChanged,
  });

  final Map<String, dynamic> data;
  final String status;
  final Future<void> Function(String nextStatus) onMissionStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFF5EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD0BF),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tripTitle(data),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
              ),
              StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 10),
          InfoLine(
            label: 'Depart',
            value: '${data['depart'] ?? data['pickupAddress'] ?? '-'}',
          ),
          InfoLine(
            label: 'Destination',
            value:
                '${data['destination'] ?? data['destinationAddress'] ?? '-'}',
          ),
          InfoLine(
            label: 'Client',
            value:
                '${data['Phone'] ?? data['clientPhone'] ?? data['phone'] ?? '-'}',
          ),
          InfoLine(label: 'Montant', value: formatMoney(tripAmount(data))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'assigned')
                ActionButton(
                  label: 'Accepter',
                  onPressed: () => onMissionStatusChanged('accepted'),
                ),
              if (status == 'accepted')
                ActionButton(
                  label: 'Demarrer',
                  onPressed: () => onMissionStatusChanged('on_the_way'),
                ),
              if (status == 'on_the_way')
                ActionButton(
                  label: 'Sur place',
                  onPressed: () => onMissionStatusChanged('arrived'),
                ),
              if (status == 'arrived')
                ActionButton(
                  label: 'Terminer',
                  onPressed: () => onMissionStatusChanged('completed'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.backgroundColor,
    required this.valueColor,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color backgroundColor;
  final Color valueColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            backgroundColor,
            Color.lerp(backgroundColor, Colors.white, 0.32) ?? backgroundColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: labelColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileLine extends StatelessWidget {
  const ProfileLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: kMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: kText, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: kMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color background = const Color(0xFFF7E7C8);
    Color foreground = kWarning;
    String label = 'Affectee';

    switch (status) {
      case 'accepted':
        background = const Color(0xFFD8F0F8);
        foreground = kAccent;
        label = 'Acceptee';
        break;
      case 'on_the_way':
        background = const Color(0xFFD8F0F8);
        foreground = kAccent;
        label = 'En route';
        break;
      case 'arrived':
        background = const Color(0xFFD8F0F8);
        foreground = kAccent;
        label = 'Sur place';
        break;
      case 'completed':
        background = const Color(0xFFD7F4E3);
        foreground = kSuccess;
        label = 'Terminee';
        break;
      case 'cancelled':
        background = const Color(0xFFF8DDD8);
        foreground = kDanger;
        label = 'Annulee';
        break;
      default:
        label = 'Affectee';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: kPrimary),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: kText)),
          ],
        ),
      ),
    );
  }
}

String normalizePhone(String raw) => raw.replaceAll(RegExp(r'\D'), '').trim();

bool phonesMatch(String left, String right) {
  final leftVariants = phoneVariants(left);
  final rightVariants = phoneVariants(right);
  return leftVariants.any(rightVariants.contains);
}

Set<String> phoneVariants(String raw) {
  final phone = normalizePhone(raw);
  final variants = <String>{};

  if (phone.isEmpty) {
    return variants;
  }

  variants.add(phone);

  if (phone.startsWith('213') && phone.length > 3) {
    variants.add(phone.substring(3));
    variants.add('0${phone.substring(3)}');
  }

  if (phone.startsWith('0') && phone.length > 1) {
    variants.add(phone.substring(1));
    variants.add('213${phone.substring(1)}');
  }

  return variants;
}

bool isDriverRequest(Map<String, dynamic> data, String driverDocId) {
  return '${data['driverId'] ?? ''}' == driverDocId ||
      '${data['chauffeur'] ?? ''}' == driverDocId;
}

Object? extractComparableDate(Map<String, dynamic> data) {
  return data['createdAt'] ?? data['timestamp'] ?? data['requestedAt'];
}

String requestStatus(Map<String, dynamic> data) {
  final raw = '${data['status'] ?? ''}'.trim().toLowerCase();
  final dispatch = '${data['dispatch'] ?? ''}'.trim().toLowerCase();

  if (raw == 'accepted' ||
      raw == 'on_the_way' ||
      raw == 'arrived' ||
      raw == 'completed' ||
      raw == 'cancelled') {
    return raw;
  }

  if (dispatch.contains('appel')) return 'assigned';
  if (dispatch.contains('accept')) return 'accepted';
  if (dispatch.contains('route')) return 'on_the_way';
  if (dispatch.contains('place')) return 'arrived';
  if (dispatch.contains('term')) return 'completed';
  if (dispatch.contains('annul')) return 'cancelled';

  return 'assigned';
}

bool isCompletedRequest(Map<String, dynamic> data) =>
    requestStatus(data) == 'completed';

bool isInProgressRequest(Map<String, dynamic> data) {
  final status = requestStatus(data);
  return status == 'assigned' ||
      status == 'accepted' ||
      status == 'on_the_way' ||
      status == 'arrived';
}

String requestDispatchLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Acceptee';
    case 'on_the_way':
      return 'En route';
    case 'arrived':
      return 'Sur place';
    case 'completed':
      return 'Terminee';
    case 'cancelled':
      return 'Annulee';
    default:
      return 'Appele';
  }
}

double tripAmount(Map<String, dynamic> data) {
  final raw = data['price'] ?? data['prix'] ?? data['commission'] ?? 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw'.replaceAll(',', '.')) ?? 0;
}

String tripTitle(Map<String, dynamic> data) {
  final title =
      '${data['motif'] ?? data['panneType'] ?? data['serviceType'] ?? 'Course'}'
          .trim();
  return title.isEmpty ? 'Course' : title;
}

String phoneToAuthEmail(String phone) =>
    '${normalizePhone(phone)}@driver.crmdep';

String formatMoney(double value) => '${value.toStringAsFixed(0)} DA';
