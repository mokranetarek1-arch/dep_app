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

const Color kBg = Color(0xFFF4F7FF);
const Color kPanel = Color(0xFFFFFFFF);
const Color kPrimary = Color(0xFF1D4ED8);
const Color kLine = Color(0xFFDCE5FF);
const Color kText = Color(0xFF0F172A);
const Color kMuted = Color(0xFF64748B);
const Color kAccent = Color(0xFF2563EB);
const Color kSuccess = Color(0xFF0F9D58);
const Color kDanger = Color(0xFFC0392B);
const Color kWarning = Color(0xFFD97706);
const String kDriverAuthPassword = 'DriverTest123!';
const String kIncomingTripAsset = 'sounds/depson.mp3';
const String kNotificationVisual = 'iconap';
const AndroidNotificationChannel kTripAlertsChannel =
    AndroidNotificationChannel(
      'trip_alerts_depson',
      'Trip Alerts Depson',
      description: 'Alertes immediates pour les nouvelles courses chauffeur.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('depson'),
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
    String? bigText,
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
          color: kPrimary,
          largeIcon: const DrawableResourceAndroidBitmap(kNotificationVisual),
          styleInformation: BigPictureStyleInformation(
            const DrawableResourceAndroidBitmap(kNotificationVisual),
            largeIcon: const DrawableResourceAndroidBitmap(kNotificationVisual),
            contentTitle: title,
            summaryText: body,
            htmlFormatContentTitle: false,
            htmlFormatSummaryText: false,
          ),
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

    final details = tripNotificationDetails(message);
    final body = details['body']!;

    await showTripNotification(
      title: details['title']!,
      body: body,
      bigText: details['bigText'],
    );
  }

  static Map<String, String> tripNotificationDetails(RemoteMessage message) {
    final tripLabel =
        '${message.data['motif'] ?? message.data['panneType'] ?? message.data['serviceType'] ?? ''}'
            .trim();
    final title =
        '${message.notification?.title ?? message.data['title'] ?? (tripLabel.isEmpty ? 'Nouvelle course' : tripLabel)}'
            .trim();
    final depart =
        '${message.data['depart'] ?? message.data['pickupAddress'] ?? ''}'
            .trim();
    final destination =
        '${message.data['destination'] ?? message.data['destinationAddress'] ?? ''}'
            .trim();
    final client =
        '${message.data['Phone'] ?? message.data['clientPhone'] ?? message.data['phone'] ?? ''}'
            .trim();
    final amount =
        '${message.data['prix'] ?? message.data['price'] ?? message.data['amount'] ?? message.data['fare'] ?? message.data['total'] ?? ''}'
            .trim();
    final route = [depart, destination]
        .where((part) => part.isNotEmpty)
        .join(' -> ');
    final fallbackParts = <String>[
      if (route.isNotEmpty) route,
      if (client.isNotEmpty) 'Client: $client',
      if (amount.isNotEmpty) 'Montant: $amount DA',
    ];
    final incomingBody =
        '${message.notification?.body ?? message.data['body'] ?? ''}'.trim();
    final bodyParts = {
      if (incomingBody.isNotEmpty) incomingBody,
      ...fallbackParts,
    }.toList();
    final body = bodyParts.isEmpty
        ? 'Ouvre l application pour repondre a la course.'
        : bodyParts.join(' | ');

    return {
      'title': title,
      'body': body,
      'bigText': bodyParts.isEmpty ? body : bodyParts.join('\n'),
      'route': route,
      'client': client,
      'amount': amount.isEmpty ? '' : '$amount DA',
      'motif': tripLabel,
    };
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
          indicatorColor: const Color(0xFFDCE5FF),
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
  final _signupFirstNameController = TextEditingController();
  final _signupLastNameController = TextEditingController();
  final _signupPhoneController = TextEditingController();
  final _signupWilayaController = TextEditingController();
  final _signupRegionController = TextEditingController();

  bool _busy = false;
  String _message = '';
  bool _signupMode = false;

  @override
  void dispose() {
    _loginPhoneController.dispose();
    _signupFirstNameController.dispose();
    _signupLastNameController.dispose();
    _signupPhoneController.dispose();
    _signupWilayaController.dispose();
    _signupRegionController.dispose();
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

  Future<void> _submitSignupRequest() async {
    final firstName = _signupFirstNameController.text.trim();
    final lastName = _signupLastNameController.text.trim();
    final phone = normalizePhone(_signupPhoneController.text);
    final wilaya = _signupWilayaController.text.trim();
    final region = _signupRegionController.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        phone.isEmpty ||
        wilaya.isEmpty ||
        region.isEmpty) {
      setState(() {
        _message =
            'Remplis nom, prenom, numero, wilaya et region pour envoyer la demande.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      final driversQuery = await FirebaseFirestore.instance
          .collection('drivers')
          .get();

      final alreadyExists = driversQuery.docs.any((doc) {
        final driverPhone = normalizePhone('${doc.data()['phone'] ?? ''}');
        return phonesMatch(phone, driverPhone);
      });

      if (alreadyExists) {
        setState(() {
          _message =
              'Ce numero existe deja dans les chauffeurs. Connecte-toi directement avec ce numero.';
        });
        return;
      }

      final pendingQuery = await FirebaseFirestore.instance
          .collection('driver_signup_requests')
          .get();

      final hasPendingRequest = pendingQuery.docs.any((doc) {
        final data = doc.data();
        final pendingPhone = normalizePhone('${data['phone'] ?? ''}');
        final pendingStatus = '${data['status'] ?? ''}'.trim().toLowerCase();
        return phonesMatch(phone, pendingPhone) &&
            (pendingStatus.isEmpty || pendingStatus == 'pending');
      });

      if (hasPendingRequest) {
        setState(() {
          _message =
              'Une demande existe deja pour ce numero. Attends la validation depuis le dashboard.';
        });
        return;
      }

      await FirebaseFirestore.instance.collection('driver_signup_requests').add({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'wilaya': wilaya,
        'region': region,
        'status': 'pending',
        'role': 'driver',
        'requestedAt': FieldValue.serverTimestamp(),
        'authEmail': phoneToAuthEmail(phone),
      });

      _signupFirstNameController.clear();
      _signupLastNameController.clear();
      _signupPhoneController.clear();
      _signupWilayaController.clear();
      _signupRegionController.clear();

      setState(() {
        _signupMode = false;
        _loginPhoneController.text = phone;
        _message =
            'Demande envoyee. Quand le dashboard accepte, le compte Auth ${phoneToAuthEmail(phone)} peut etre cree puis tu te connectes avec ton numero.';
      });
    } catch (_) {
      setState(() {
        _message = 'Impossible d envoyer la demande pour le moment. Reessaie.';
      });
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
                        color: Color(0xFFE5E7EB),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Espace chauffeur assistance routiere',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Connexion par numero apres validation dashboard, ou envoie de demande d inscription chauffeur.',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _signupMode = false),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: !_signupMode
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: !_signupMode
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x12000000),
                                            blurRadius: 12,
                                            offset: Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  'Connexion',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        !_signupMode ? kText : kMuted,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _signupMode = true),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: _signupMode
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: _signupMode
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x12000000),
                                            blurRadius: 12,
                                            offset: Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  'Inscription',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _signupMode ? kText : kMuted,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _signupMode
                            ? 'Demande d inscription chauffeur'
                            : 'Connexion chauffeur',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: kText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_signupMode) ...[
                      DriverTextField(
                        controller: _signupFirstNameController,
                        label: 'Prenom',
                        hint: 'Tarek',
                      ),
                      const SizedBox(height: 12),
                      DriverTextField(
                        controller: _signupLastNameController,
                        label: 'Nom',
                        hint: 'Aloui',
                      ),
                      const SizedBox(height: 12),
                      DriverTextField(
                        controller: _signupPhoneController,
                        label: 'Numero de telephone',
                        hint: '0552466823',
                      ),
                      const SizedBox(height: 12),
                      DriverTextField(
                        controller: _signupWilayaController,
                        label: 'Wilaya',
                        hint: 'Alger',
                      ),
                      const SizedBox(height: 12),
                      DriverTextField(
                        controller: _signupRegionController,
                        label: 'Region',
                        hint: 'Est',
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Le dashboard recoit la demande, puis apres validation il cree automatiquement le compte Auth au format numero@driver.crmdep.',
                          style: TextStyle(
                            color: kMuted,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ] else ...[
                      DriverTextField(
                        controller: _loginPhoneController,
                        label: 'Numero de telephone',
                        hint: '0552466823',
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Entre ton numero. Une fois la demande approuvee et le compte active, l app ouvre directement ton espace chauffeur.',
                          style: TextStyle(color: kMuted, height: 1.45),
                        ),
                      ),
                    ],
                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kLine),
                        ),
                        child: Text(
                          _message,
                          style: const TextStyle(
                            color: kText,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
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
                        onPressed:
                            _busy ? null : (_signupMode ? _submitSignupRequest : _login),
                        child: Text(
                          _busy
                              ? 'Veuillez patienter...'
                              : (_signupMode
                                  ? 'Envoyer ma demande'
                                  : 'Entrer'),
                        ),
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

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _requestingLocation = false;
  String? _trackingDriverId;
  String? _notificationDriverId;
  String _locationState = 'Localisation non activee';
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  final Set<String> _seenIncomingRequestIds = <String>{};
  final Map<String, String> _knownRequestStatuses = <String, String>{};
  Map<String, String>? _inAppAlert;
  String? _activeIncomingRequestId;
  bool _incomingRequestsInitialized = false;
  final AudioPlayer _ringtonePlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((message) {
      DriverNotificationService.showTripNotificationFromMessage(message);
      if (DriverNotificationService.isTripMessage(message) && mounted) {
        setState(() {
          _inAppAlert = DriverNotificationService.tripNotificationDetails(
            message,
          );
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _ringtonePlayer.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _dismissInAppAlert() {
    if (!mounted) return;
    setState(() => _inAppAlert = null);
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
    if (_appLifecycleState != AppLifecycleState.resumed) {
      for (final doc in missions) {
        _seenIncomingRequestIds.add(doc.id);
        _knownRequestStatuses[doc.id] = requestStatus(doc.data());
      }
      return;
    }

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
                            color: const Color(0xFFE5E7EB),
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
                inAppAlert: _inAppAlert,
                onDismissAlert: _dismissInAppAlert,
                onOpenAlerts: () => setState(() => _currentIndex = 1),
                onRequestLocation: () =>
                    _activateLocationTracking(driverDoc.id, driver),
                missions: missions,
                onMissionStatusChanged: _updateMissionStatus,
              ),
              AlertsPage(missions: missions),
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
                    icon: Icon(Icons.notifications_none_outlined),
                    selectedIcon: Icon(Icons.notifications),
                    label: 'Alertes',
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
    required this.inAppAlert,
    required this.onDismissAlert,
    required this.onOpenAlerts,
    required this.onRequestLocation,
    required this.missions,
    required this.onMissionStatusChanged,
  });

  final Map<String, dynamic> driver;
  final int inProgressCount;
  final int completedCount;
  final String locationState;
  final Position? lastPosition;
  final Map<String, String>? inAppAlert;
  final VoidCallback onDismissAlert;
  final VoidCallback onOpenAlerts;
  final Future<void> Function() onRequestLocation;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> missions;
  final Future<void> Function(String missionId, String status)
  onMissionStatusChanged;

  @override
  Widget build(BuildContext context) {
    final assignedTrips = missions
        .where((doc) => requestStatus(doc.data()) == 'assigned')
        .toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DriverHeroCard(
                  name: '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'
                      .trim(),
                  phone: '${driver['phone'] ?? '-'}',
                  city: '${driver['wilaya'] ?? '-'}',
                  inProgressCount: inProgressCount,
                  completedCount: completedCount,
                  locationState: locationState,
                ),
                const SizedBox(height: 16),
                if (inAppAlert != null) ...[
                  InAppTripAlertCard(
                    alert: inAppAlert!,
                    onDismiss: onDismissAlert,
                    onOpenAlerts: onOpenAlerts,
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'En attente',
                        value: '${assignedTrips.length}',
                        icon: Icons.notifications_active_outlined,
                        accent: const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        label: 'En mission',
                        value: '$inProgressCount',
                        icon: Icons.route_outlined,
                        accent: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        label: 'Terminees',
                        value: '$completedCount',
                        icon: Icons.check_circle_outline,
                        accent: const Color(0xFF60A5FA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SectionCard(
                  title: 'Live status',
                  subtitle: 'Position chauffeur et disponibilite du GPS.',
                  child: Column(
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
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => onRequestLocation(),
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Actualiser ma position'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionHeader(
                  eyebrow: 'Courses',
                  title: 'Demandes et trajets',
                  subtitle:
                      'Les nouvelles demandes arrivent ici avec les actions chauffeur.',
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: missions.isEmpty
              ? const SliverToBoxAdapter(
                  child: EmptyStateCard(
                    title: 'Aucune course pour le moment',
                    subtitle:
                        'Les nouvelles demandes affectees au chauffeur apparaitront ici en temps reel.',
                    icon: Icons.local_shipping_outlined,
                  ),
                )
              : SliverList.separated(
                  itemCount: missions.length,
                  itemBuilder: (context, index) {
                    final doc = missions[index];
                    final data = doc.data();
                    final status = requestStatus(data);
                    return MissionCard(
                      data: data,
                      status: status,
                      onMissionStatusChanged: (nextStatus) =>
                          onMissionStatusChanged(doc.id, nextStatus),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 14),
                ),
        ),
      ],
    );
  }
}

class AlertsPage extends StatelessWidget {
  const AlertsPage({
    super.key,
    required this.missions,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> missions;

  @override
  Widget build(BuildContext context) {
    final recentAlerts = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      missions,
    )..sort((a, b) {
        final left = extractComparableDate(b.data());
        final right = extractComparableDate(a.data());
        final leftSeconds = left is Timestamp ? left.seconds : 0;
        final rightSeconds = right is Timestamp ? right.seconds : 0;
        return leftSeconds.compareTo(rightSeconds);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderCard(
            title: 'Alertes & historique',
            subtitle:
                'Les demandes recues restent visibles ici avec leurs details et statuts.',
            eyebrow: 'Activity',
            trailing: StatusBadge(
              label: 'Temps reel',
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 18),
          if (recentAlerts.isNotEmpty)
            const QuickFiltersBar(
              labels: ['Toutes', 'Affectees', 'Actives', 'Terminees'],
            ),
          const SizedBox(height: 18),
          if (recentAlerts.isEmpty)
            const EmptyStateCard(
              title: 'Aucune alerte pour le moment',
              subtitle:
                  'Quand une nouvelle course est affectee, elle apparaitra ici avec ses details.',
              icon: Icons.notifications_none_outlined,
            )
          else
            ...recentAlerts.take(15).map((doc) {
              final data = doc.data();
              final route =
                  '${data['depart'] ?? data['pickupAddress'] ?? '-'} -> ${data['destination'] ?? data['destinationAddress'] ?? '-'}';
              final client =
                  '${data['Phone'] ?? data['clientPhone'] ?? data['phone'] ?? '-'}';
              final amount = formatMoney(tripAmount(data));
              return AlertHistoryCard(
                title: tripTitle(data),
                route: route,
                client: client,
                amount: amount,
                status: requestStatus(data),
              );
            }),
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
          EarningsHeroCard(amount: formatMoney(estimatedCommission)),
          const SizedBox(height: 18),
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: paidCommissionFuture,
            builder: (context, snapshot) {
              final paidAmount = (snapshot.data?.docs ?? []).fold<double>(
                0,
                (total, doc) =>
                    total + ((doc.data()['amount'] ?? 0) as num).toDouble(),
              );
              final remaining = (estimatedCommission - paidAmount)
                  .clamp(0, double.infinity)
                  .toDouble();

              return Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Traite',
                      value: formatMoney(paidAmount),
                      backgroundColor: const Color(0xFFDBEAFE),
                      valueColor: kText,
                      labelColor: kMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      label: 'Reste',
                      value: formatMoney(remaining),
                      backgroundColor: const Color(0xFFE0E7FF),
                      valueColor: kText,
                      labelColor: kMuted,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Courses terminees',
            subtitle:
                'Base de calcul actuelle des commissions et paiements chauffeur.',
            child: completedMissions.isEmpty
                ? const EmptyStateCard(
                    title: 'Aucune course terminee',
                    subtitle:
                        'Les commissions s afficheront ici a partir des trajets finalises.',
                    icon: Icons.payments_outlined,
                  )
                : Column(
                    children: completedMissions.map((doc) {
                      final data = doc.data();
                      final amount = tripAmount(data);
                      return CompactEarningRow(
                        title: tripTitle(data),
                        route:
                            '${data['depart'] ?? data['pickupAddress'] ?? '-'} -> ${data['destination'] ?? data['destinationAddress'] ?? '-'}',
                        amount: formatMoney(amount),
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
          ProfileHeroCard(
            name:
                '${driver['firstName'] ?? ''} ${driver['lastName'] ?? ''}'.trim(),
            phone: '${driver['phone'] ?? '-'}',
            region: '${driver['wilaya'] ?? '-'} • ${driver['region'] ?? '-'}',
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Identite chauffeur',
            subtitle: 'Informations de compte visibles dans le dashboard.',
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
                  label: 'Compte mobile',
                  value: driver['accountCreated'] == true ? 'Actif' : 'A finaliser',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Localisation',
            subtitle: 'Etat de la position temps reel du chauffeur.',
            child: Column(
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
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onRequestLocation(),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Synchroniser ma localisation'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: onLogout,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Se deconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverHeroCard extends StatelessWidget {
  const DriverHeroCard({
    super.key,
    required this.name,
    required this.phone,
    required this.city,
    required this.inProgressCount,
    required this.completedCount,
    required this.locationState,
  });

  final String name;
  final String phone;
  final String city;
  final int inProgressCount;
  final int completedCount;
  final String locationState;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1220), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.local_taxi_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Chauffeur' : name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$phone • $city',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const StatusBadge(
                label: 'ON DUTY',
                color: Color(0xFF60A5FA),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: HeroMetric(
                    label: 'En mission',
                    value: '$inProgressCount',
                  ),
                ),
                const HeroDivider(),
                Expanded(
                  child: HeroMetric(
                    label: 'Terminees',
                    value: '$completedCount',
                  ),
                ),
                const HeroDivider(),
                Expanded(
                  child: HeroMetric(
                    label: 'GPS',
                    value: locationState.contains('GPS actif') ? 'ACTIF' : 'CHECK',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HeroMetric extends StatelessWidget {
  const HeroMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class HeroDivider extends StatelessWidget {
  const HeroDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class InAppTripAlertCard extends StatelessWidget {
  const InAppTripAlertCard({
    super.key,
    required this.alert,
    required this.onDismiss,
    required this.onOpenAlerts,
  });

  final Map<String, String> alert;
  final VoidCallback onDismiss;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242563EB),
            blurRadius: 22,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nouvelle course',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          Text(
            alert['title'] ?? 'Demande chauffeur',
            style: const TextStyle(
              color: Color(0xFFEFF6FF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((alert['route'] ?? '').isNotEmpty)
                  Text(
                    alert['route']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if ((alert['client'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Client: ${alert['client']}',
                    style: const TextStyle(color: Color(0xFFE0F2FE)),
                  ),
                ],
                if ((alert['amount'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Montant: ${alert['amount']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Plus tard'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onOpenAlerts,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1D4ED8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            color: kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            color: kText,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: kMuted, height: 1.45),
        ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: kText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: kMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickFiltersBar extends StatelessWidget {
  const QuickFiltersBar({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final selected = index == 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: selected ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? kPrimary : kLine),
            ),
            alignment: Alignment.center,
            child: Text(
              labels[index],
              style: TextStyle(
                color: selected ? Colors.white : kText,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
    );
  }
}

class AlertHistoryCard extends StatelessWidget {
  const AlertHistoryCard({
    super.key,
    required this.title,
    required this.route,
    required this.client,
    required this.amount,
    required this.status,
  });

  final String title;
  final String route;
  final String client;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            route,
            style: const TextStyle(
              color: kText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text('Client: $client', style: const TextStyle(color: kMuted)),
          const SizedBox(height: 8),
          Text(
            amount,
            style: const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class EarningsHeroCard extends StatelessWidget {
  const EarningsHeroCard({super.key, required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Earnings overview',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            amount,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Synthese actuelle des courses finalisees et montants deja traites.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class CompactEarningRow extends StatelessWidget {
  const CompactEarningRow({
    super.key,
    required this.title,
    required this.route,
    required this.amount,
  });

  final String title;
  final String route;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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
                  title,
                  style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(route, style: const TextStyle(color: kMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileHeroCard extends StatelessWidget {
  const ProfileHeroCard({
    super.key,
    required this.name,
    required this.phone,
    required this.region,
  });

  final String name;
  final String phone;
  final String region;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF111827), Color(0xFF1F2937)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Profil chauffeur' : name,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(
                    color: kMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(region, style: const TextStyle(color: kMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: kPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, height: 1.45),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
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
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow.toUpperCase(),
              style: const TextStyle(
                color: kAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
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
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final Widget child;
  final String? subtitle;

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
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kText,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: kMuted,
                height: 1.4,
              ),
            ),
          ],
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
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'TRIP',
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tripTitle(data),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: kText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
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
                InfoLine(
                  label: 'Montant',
                  value: formatMoney(tripAmount(data)),
                ),
              ],
            ),
          ),
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
        border: Border.all(color: Colors.white),
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
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
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
    Color background = const Color(0xFFE5E7EB);
    Color foreground = kWarning;
    String label = 'Affectee';

    switch (status) {
      case 'accepted':
        background = const Color(0xFFDCFCE7);
        foreground = kAccent;
        label = 'Acceptee';
        break;
      case 'on_the_way':
        background = const Color(0xFFDCFCE7);
        foreground = kAccent;
        label = 'En route';
        break;
      case 'arrived':
        background = const Color(0xFFDCFCE7);
        foreground = kAccent;
        label = 'Sur place';
        break;
      case 'completed':
        background = const Color(0xFFDCFCE7);
        foreground = kSuccess;
        label = 'Terminee';
        break;
      case 'cancelled':
        background = const Color(0xFFFEE2E2);
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
  final raw = normalizeStatusValue('${data['status'] ?? ''}');
  final dispatch = normalizeStatusValue('${data['dispatch'] ?? ''}');

  if (raw == 'completed' || dispatch == 'completed') return 'completed';
  if (raw == 'cancelled' || dispatch == 'cancelled') return 'cancelled';
  if (raw == 'arrived' || dispatch == 'arrived') return 'arrived';
  if (raw == 'on_the_way' || dispatch == 'on_the_way') return 'on_the_way';
  if (raw == 'accepted' || dispatch == 'accepted') return 'accepted';
  if (raw == 'assigned' || dispatch == 'assigned') return 'assigned';

  return 'assigned';
}

String normalizeStatusValue(String raw) {
  final value = raw
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('ù', 'u');

  if (value.isEmpty) return '';
  if (value.contains('term') ||
      value.contains('finalis') ||
      value.contains('complete') ||
      value.contains('done')) {
    return 'completed';
  }
  if (value.contains('annul') ||
      value.contains('cancel') ||
      value.contains('refus') ||
      value.contains('reject')) {
    return 'cancelled';
  }
  if (value.contains('sur place') ||
      value.contains('arrive') ||
      value.contains('place')) {
    return 'arrived';
  }
  if (value.contains('route') ||
      value.contains('course') ||
      value.contains('in progress') ||
      value.contains('ongoing') ||
      value.contains('en cours')) {
    return 'on_the_way';
  }
  if (value.contains('accept')) {
    return 'accepted';
  }
  if (value.contains('affect') ||
      value.contains('assigne') ||
      value.contains('assignee') ||
      value.contains('appele') ||
      value.contains('appel') ||
      value.contains('pending')) {
    return 'assigned';
  }

  return value;
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
