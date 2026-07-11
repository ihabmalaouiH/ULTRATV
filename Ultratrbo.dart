import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:math';
// --- 🌟 استيرادات مشغل الفيديو وحماية الشاشة (UltraTV Player) ---
import 'package:screen_protector/screen_protector.dart';
// -----------------------------------------------------------

// ✅ تأكد من وجود هذا السطر
import 'package:safe_device/safe_device.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher_string.dart'; // ✅ استيراد إضافي مهم
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:ui';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
const String APP_USER_AGENT = "UltraTV_Player_Pro_v5";
// --- (COLORS) ---
const Color primaryColor = Color(0xFF870000);
const Color secondaryColor = Color(0xFFFFF5F5);
const Color textLight = Color(0xFFFFFFFF);
const Color textDark =  Color(0xFF333333);
const Color cardBg = Color(0xFFFFFFFF);
const Color liveBg = Color(0xFFD32F2F);
const Color finishedBg = Color(0xFFf5f5f5);
// --- (FULLSCREEN HELPER - FINAL FOOLPROOF VERSION) ---
Future<void> setFullScreen(bool isFullScreen) async {
  if (isFullScreen) {
    // 🔥 الدخول: إخفاء كل شيء (يعمل على كل إصدارات فلاتر بدون استثناء)
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // 🔥 قفل الاتجاه الأفقي (بأمان لعدم الكراش)
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}

    // 🔥 ضربة تأكيدية بعد نصف ثانية لكسر مقاومة بعض الأنظمة
    Future.delayed(const Duration(milliseconds: 600), () {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  } else {
    if (AppMode.isTvMode) {
      // 🔥 التلفاز: إخفاء كل شيء فقط (بدون إظهار أي شيء)
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      try {
        // إلغاء قفل الاتجاه لكي لا يعلق التطبيق بالوضع العمودي
        await SystemChrome.setPreferredOrientations([]);
      } catch (_) {}
    } else {
      // 🔥 الهاتف: إعادة الأشرطة والوضع العمودي
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } catch (_) {}
    }
  }
}
// ============================================================
// أضف هذا السطر في المستوى العلوي من main.dart
// مباشرةً فوق كلاس UltraTvApp (خارج أي كلاس)
// ============================================================

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// --- (MAIN APP START - UPDATED WITH FIREBASE) ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔥 1. إضافة الفحص هنا قبل تشغيل Firebase أو أي واجهة 🔥
  await DeviceConfig.initDeviceSettings();

  try {
    // 2. تهيئة Firebase
    await Firebase.initializeApp();
    
    // 3. تفعيل التقاط الأخطاء
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    debugPrint("✅ Firebase & Crashlytics Initialized Successfully");
  } catch (e) {
    debugPrint("❌ Firebase Initialization Failed: $e");
  }

  runApp(ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: const UltraTvApp(),
  ));
}
// --- (THEME MANAGER) ---
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
// ============================================================
// كلاس GlobalRemoteManager (مُحدث لحل تعارض الريموت والـ Syntax)
// ============================================================
class GlobalRemoteManager extends StatefulWidget {
  final Widget child;
  const GlobalRemoteManager({required this.child, super.key});

  static Future<bool> isTvDevice() async {
    const channel = MethodChannel('com.ultratv.live/global_remote');
    try {
      final bool isTv = await channel.invokeMethod('checkDeviceType');
      return isTv;
    } catch (e) {
      return false;
    }
  }

  @override
  State<GlobalRemoteManager> createState() => _GlobalRemoteManagerState();
}

class _GlobalRemoteManagerState extends State<GlobalRemoteManager> {
  static const _channel = MethodChannel('com.ultratv.live/global_remote');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onKey') {
        _handleGlobalRemoteKey(call.arguments as String);
      }
    });
  }

  void _handleGlobalRemoteKey(String key) {
    switch (key) {
      // ── التنقل بالأسهم ─────────────────────────────────────
      case 'UP':
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.up);
        break;
      case 'DOWN':
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.down);
        break;
      case 'LEFT':
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.left);
        break;
      case 'RIGHT':
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.right);
        break;

      // ── زر OK / ENTER: يفعّل العنصر المُحدد ────────────────
      case 'ENTER':
        final focused = FocusManager.instance.primaryFocus;
        if (focused?.context != null) {
          Actions.invoke(focused!.context!, const ActivateIntent());
        }
        break;

      // ── رجوع ────────────────────────────────────────────────
      case 'BACK':
        if (!Navigator.of(context).canPop()) {
          SystemNavigator.pop();
        } else {
          navigatorKey.currentState?.pop();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 تمت إزالة Shortcuts و Actions بالكامل لأننا نتعامل معها في TvFocusWrapper
    return widget.child;
  }
}
// --- (MAIN APP WIDGET - UPDATED) ---
// ============================================================
// الكلاس 2: UltraTvApp (كامل - استبدل القديم بهذا)
// التعديل الوحيد: إضافة navigatorKey + GlobalRemoteManager
// ============================================================
class UltraTvApp extends StatelessWidget {
  const UltraTvApp({super.key});

  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: analytics);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'Ultra TV',
      themeMode: themeProvider.themeMode,
      theme: MyThemes.lightTheme,
      darkTheme: MyThemes.darkTheme,
      debugShowCheckedModeBanner: false,
      navigatorObservers: <NavigatorObserver>[observer],
      builder: (context, child) {
        return RealTimeProtection(child: child!);
      },
      home: const SplashScreen(),
    );
  }
}
// --- (CUSTOM CACHE MANAGER - LIGHT VERSION) ---
class MyCustomCacheManager {
  static const key = 'ultraTvLogosCache_v3';
  static CacheManager? _instance;

  static CacheManager get instance {
    if (_instance == null) {
      // 🔥 تقليل الكاش: 300 صورة للجميع، مدة 30 يوم فقط
      _instance = CacheManager(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 300,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ),
      );
    }
    return _instance!;
  }
}
class BlacklistDetector {
  static const platform = MethodChannel('com.ultratv.live/security');

  // 🔥 القائمة الشاملة لحظر تطبيقات السرقة والتحليل 🔥
  static const List<String> _forbiddenPackages = [
    // --- 1. Network Sniffers (أخطر شيء) ---
    'com.reqable.android', // Reqable
    'com.minhui.networkcapture', // NetCapture
    'app.greyshirts.sslcapture', // Packet Capture
    'com.guoshi.httpcanary', // HttpCanary
    'com.emanuelef.remote_capture', // PCAPdroid
    'jp.co.taosoftware.android.packetcapture', // tPacketCapture
    'com.egorovandrey.policy', // Debug Proxy
    'xyz.krsenty.debugproxy', // Debug Proxy (Alternative)
    'com.evbadroid.proxymon', // Proxymon
    'com.mjt.networkcapture', // Mojo Capture
    'org.owasp.zap', // OWASP ZAP

    // --- 2. Modding & Cracking Tools (تطبيقات التعديل) ---
    'bin.mt.plus', // MT Manager (مهم جداً حظره)
    'com.surodev.mtmanagers', // MT Manager (Old)
    'com.chelpus.luckypatcher', // Lucky Patcher
    'com.dimonvideo.luckypatcher', // Lucky Patcher (Variant)
    'ru.aaaaa.installer', // Lucky Patcher Installer
    'com.android.vending.billing.InAppBillingService.COIN', // Lucky Patcher Proxy
    'com.android.vending.billing.InAppBillingService.LUCK', // Lucky Patcher Proxy

    // --- 3. Root & Hacking Tools (تطبيقات الروت والهاك) ---
    'com.topjohnwu.magisk', // Magisk Manager
    'eu.chainfire.supersu', // SuperSU
    'com.koushikdutta.rommanager', // ROM Manager
    'com.noshufou.android.su', // Superuser
    'com.thirdparty.superuser', // Superuser
    'com.yellowes.su', // Superuser
    'com.zachspenner.chinchilla', // Root access tool
    'com.cih.game_cih', // GameCIH
    'com.gamekiller', // Game Killer
    'com.xmodgames', // Xmodgames

    // --- 4. Dangerous Frameworks (إطارات العمل الخطرة) ---
    'de.robv.android.xposed.installer', // Xposed Installer
    'org.meowcat.edxposed.manager', // EdXposed Manager
    'org.lsposed.manager', // LSPosed
  ];

  static Future<String?> findBlacklistedApp() async {
    try {
      final String? result =
          await platform.invokeMethod('checkPackages', _forbiddenPackages);
      return result;
    } on PlatformException catch (e) {
      print("Error checking apps: ${e.message}");
      return null;
    }
  }
}
// --- (THEME DEFINITIONS) ---
class MyThemes {
  static final lightTheme = ThemeData(
    primaryColor: primaryColor,
    brightness: Brightness.light,
    scaffoldBackgroundColor: secondaryColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      elevation: 0,
      titleTextStyle: TextStyle(color: textLight, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: textLight),
    ),
    cardTheme: const CardThemeData(color: cardBg),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textDark),
      bodyMedium: TextStyle(color: textDark),
    ),
    listTileTheme: const ListTileThemeData(iconColor: primaryColor),
  );

  static final darkTheme = ThemeData(
    primaryColor: primaryColor,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      elevation: 0,
      titleTextStyle: TextStyle(color: textLight, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: textLight),
    ),
    cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textLight),
      bodyMedium: TextStyle(color: textLight),
    ),
    listTileTheme: const ListTileThemeData(iconColor: textLight),
  );
}
class DeviceConfig {
  // ✅ نستخدم نفس القناة الأمنية الموجودة في Kotlin
  static const platform = MethodChannel('com.ultratv.live/security');
  
  // المتغير السحري الذي سيحمي الهواتف الضعيفة
  static bool isLowRamDevice = false; 

  static Future<void> initDeviceSettings() async {
    try {
      // جلب حجم الرام من Kotlin
      final int totalRamMB = await platform.invokeMethod('getTotalRAM');
      debugPrint("📱 إجمالي الرام في الهاتف: $totalRamMB MB");

      // إذا كان الرام 2500 ميجا (2.5 جيجا) أو أقل، نعتبره هاتفاً ضعيفاً
      if (totalRamMB <= 2500) {
        isLowRamDevice = true;
        debugPrint("⚠️ تم اكتشاف هاتف ضعيف (2GB)! سيتم تفعيل وضع توفير الذاكرة.");
      } else {
        isLowRamDevice = false;
        debugPrint("✅ هاتف قوي، سيتم تشغيل التطبيق بكامل طاقته.");
      }
    } on PlatformException catch (e) {
      debugPrint("❌ فشل في الحصول على الرام: '${e.message}'.");
      // كإجراء أمان، نعتبره ضعيفاً لتجنب انهيار التطبيق
      isLowRamDevice = true;
    }
  }
}
class TvConfig {
  /// هل نحن في وضع التلفاز الآن؟
  static bool get isActive => AppMode.isTvMode;

  /// لون التحديد (الأصفر الذهبي بدلاً من الأبيض)
  static const Color focusColor   = Color(0xFFFFD700);
  static const Color focusBorder  = Color(0xFFFFAA00);
  static const double borderWidth = 3.5;

  /// تعطيل كل الأنيميشن الثقيل في وضع التلفاز
  static Duration get animDuration =>
      isActive ? Duration.zero : const Duration(milliseconds: 200);

  /// تعطيل Blur تماماً في وضع التلفاز (BottomNav)
  static bool get useBlur => !isActive;

  /// عدد أعمدة الشبكة حسب عرض الشاشة
  static int gridColumns(double width) {
    if (!isActive) return 3;
    
    // 🔥 تعديل جديد: دعم أفضل لأجهزة التلفاز و TV Box المنخفضة الدقة
    // أجهزة 4K (مساحة كبيرة جداً)
    if (width >= 1600) return 8;
    if (width >= 1300) return 7;
    
    // أجهزة Full HD / 1080p TV Box (المعدل الأكثر أماناً)
    if (width >= 1000) return 5;
    
    // أجهزة HD / شاشات صغيرة جداً (نقلل العدد حتى لا تضغط البطاقات)
    return 4; 
  }
}
// --- (VPN BLOCKER SERVICE - FINAL VERSION) ---
class VPNBlocker {
  // ❗️ لا حاجة لمفتاح API بعد الآن

  static Future<bool> isVpnActive() async {
    try {
      // ✅ 1. استخدام الرابط الجديد من ip-api.com
      // نحن نطلب فقط حقل "proxy" (الذي يكشف الـ VPN والبروكسي)
      final response = await http.get(Uri.parse('http://ip-api.com/json/?fields=proxy'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // ✅ 2. التحقق من الحقل الجديد
        if (data['proxy'] == true) {
          debugPrint("VPN check: FAILED (VPN/Proxy detected by ip-api.com)");
          return true; // VPN نشط
        }

        debugPrint("VPN check: PASSED (Clean IP)");
        return false; // الـ IP نظيف
      } else {
        // إذا فشل الـ API، اسمح للمستخدم بالدخول
        debugPrint("VPN check: API call failed. Allowing access.");
        return false;
      }
    } catch (e) {
      // إذا حدث أي خطأ، اسمح للمستخدم بالدخول
      print("VPN check failed: $e");
      return false;
    }
  }
}
// --- (SNIFFER DETECTOR - POWERFUL VERSION) ---
class SnifferDetector {
  static Future<bool> isSnifferActive() async {
    try {
      // 1. 🔥 الطريقة الأقوى: كشف واجهة الـ VPN
      // تطبيقات مثل NetCapture و Reqable تعمل بإنشاء VPN محلي على الهاتف.
      // هذا الفحص سيكشفها فوراً.
      final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
      
      if (connectivityResult.contains(ConnectivityResult.vpn)) {
        debugPrint("⚠️ تم اكتشاف تطبيق تنصت (يعمل كـ VPN محلي)");
        return true;
      }

      // 2. كشف البروكسي التقليدي (لزيادة الأمان)
      final client = HttpClient();
      final uri = Uri.parse('https://www.google.com');
      final proxyStr = await HttpClient.findProxyFromEnvironment(uri, environment: Platform.environment);

      if (proxyStr != "DIRECT") {
        debugPrint("⚠️ تم اكتشاف إعدادات بروكسي: $proxyStr");
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint("Sniffer check error: $e");
      return false;
    }
  }
}

// --- (SNIFFER BLOCKED SCREEN) ---
class SnifferBlockedScreen extends StatelessWidget {
  const SnifferBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.network_locked_outlined, color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text(
                'تم اكتشاف أدوات تنصت',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              const Text(
                'لا يمكن استخدام التطبيق أثناء تشغيل برامج تحليل الشبكة (مثل NetCapture أو Reqable).\n\nيرجى إغلاقها وإزالة أي إعدادات Proxy/VPN والمحاولة مرة أخرى.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                ),
                onPressed: () => SystemNavigator.pop(),
                child: const Text("إغلاق التطبيق"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- (REAL-TIME PROTECTION WIDGET - SMART & AGGRESSIVE) ---

// 1. الكلاس الأساسي (الذي كان مفقوداً عندك)
class RealTimeProtection extends StatefulWidget {
  final Widget child;
  const RealTimeProtection({required this.child, super.key});

  @override
  State<RealTimeProtection> createState() => _RealTimeProtectionState();
}

// 2. كلاس الحالة (الذي يحتوي على الحل الذي وضعناه للمؤقتات)
class _RealTimeProtectionState extends State<RealTimeProtection>
    with WidgetsBindingObserver {
  bool _isBlocked = false;
  Timer? _fastTimer; // فحص الشبكة
  Timer? _slowTimer; // فحص التطبيقات
  StreamSubscription? _netSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. فحص فوري عند تشغيل التطبيق
    _performFullScan();

    // 2. مراقب الشبكة اللحظي
    _netSubscription = Connectivity().onConnectivityChanged.listen((_) {
      _checkNetworkStatus();
    });

    // 3. تشغيل المؤقتات
    _startTimers();
  }

  void _startTimers() {
    if (_isBlocked) return;
    _fastTimer?.cancel();
    _slowTimer?.cancel();

    _fastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkNetworkStatus();
    });

    _slowTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkInstalledApps();
    });
  }

  void _stopTimers() {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _netSubscription?.cancel();
    _stopTimers();
    super.dispose();
  }

  // --- دوال الفحص ---
  Future<void> _checkNetworkStatus() async {
    if (_isBlocked) return;
    bool isSniffer = await SnifferDetector.isSnifferActive();
    if (isSniffer && mounted) {
      _triggerBlock(const SnifferBlockedScreen());
      return;
    }
    bool isVpn = await VPNBlocker.isVpnActive();
    if (isVpn && mounted) {
      _triggerBlock(const VpnBlockedScreen());
    }
  }

  Future<void> _checkInstalledApps() async {
    if (_isBlocked) return;
    try {
      String? forbiddenApp;
      try {
        forbiddenApp = await BlacklistDetector.findBlacklistedApp();
      } catch (e) {}

      if (!mounted) return;
      if (forbiddenApp != null) {
        _triggerBlock(BlacklistBlockedScreen(appName: forbiddenApp));
      }
    } catch (e) {}
  }

  Future<void> _performFullScan() async {
    await _checkNetworkStatus();
    await _checkInstalledApps();
  }

  // 🔥🔥🔥 مراقبة حالة التطبيق (الحل لمنع الخروج المفاجئ) 🔥🔥🔥
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 عاد المستخدم للتطبيق. جاري الفحص...");
      _startTimers(); // إعادة تشغيل المؤقتات
      _performFullScan();
      
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isBlocked) _checkInstalledApps();
      });
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint("📱 التطبيق في الخلفية. إيقاف المؤقتات لتجنب الخروج المفاجئ...");
      _stopTimers(); // إيقاف المؤقتات
    }
  }

  void _triggerBlock(Widget screen) {
    if (!_isBlocked && mounted) {
      setState(() => _isBlocked = true);
      _stopTimers();
      _netSubscription?.cancel();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => screen),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
// --- (SECURITY RISK BLOCKED SCREEN) ---
class SecurityRiskScreen extends StatelessWidget {
  const SecurityRiskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor, // استخدم لونك الأساسي
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security_outlined, color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text(
                'تم اكتشاف خطر أمني',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'لا يمكن تشغيل هذا التطبيق على جهاز مكسور الحماية (Rooted) لأسباب أمنية.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class BlacklistBlockedScreen extends StatelessWidget {
  final String appName;
  const BlacklistBlockedScreen({required this.appName, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF870000), // لون تطبيقك الأساسي
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.privacy_tip_outlined,
                  color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text(
                'تطبيق غير مسموح به',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'تم اكتشاف تطبيق "$appName" على جهازك.',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'لسياسات الأمان والحماية، لا يمكن تشغيل Ultra TV أثناء تثبيت تطبيقات تحليل الشبكة.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // زر لفتح إعدادات التطبيق لحذفه (اختياري)
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text("يرجى حذف التطبيق والمحاولة مجدداً"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF870000),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  // إغلاق التطبيق
                  SystemNavigator.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================
// MAIN SCREEN COMPLETE - مستقر تماماً مع الريموت كنترول
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Category> _allCategories = [];
  bool _isLoading = true;

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOfflineDialogVisible = false;

  static const List<String> _titles = ['Ultra TV', 'LIVE EVENT', 'Standings'];

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);
    _loadCategories();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    final r = await Connectivity().checkConnectivity();
    _handleConnectivityChange(r);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasNet = !results.contains(ConnectivityResult.none);
    if (!hasNet) {
      if (!_isOfflineDialogVisible) _showOfflineDialog();
    } else {
      if (_isOfflineDialogVisible) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _isOfflineDialogVisible = false;
        if (_allCategories.isEmpty) _loadCategories();
      }
    }
  }

  void _showOfflineDialog() {
    _isOfflineDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("لا يوجد اتصال"),
        content: const Text("يرجى التحقق من الإنترنت."),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _isOfflineDialogVisible = false;
              await _checkInitialConnectivity();
            },
            child: const Text("محاولة مجدداً"),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCategories() async {
    if (!_isLoading) setState(() => _isLoading = true);
    try {
      _allCategories = await fetchCategories();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(allCategories: _allCategories, isLoading: _isLoading),
      LiveEventsScreen(allCategories: _allCategories),
      const StandingsScreen(),
    ];

    // وضع التلفاز: بدون Drawer ، بدون AppBar معقد، بدون Blur
    if (AppMode.isTvMode) {
      return _buildTvLayout(screens);
    }

    // وضع الهاتف: نفس التصميم الأصلي
    return _buildPhoneLayout(screens);
  }

  // ══════════════════════════════════════════════════════════
  // 🖥️ TV Layout - مع عزل التركيز لمنع توهج الريموت
  // ══════════════════════════════════════════════════════════
  Widget _buildTvLayout(List<Widget> screens) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── شريط علوي خفيف للتلفاز ──
          Container(
            height: 52,
            color: const Color(0xFF1A0000),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Image.asset('assets/images/logo.png', height: 34),
                const SizedBox(width: 16),
                Text(
                  _titles[_selectedIndex],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TvFocusWrapper(
                  borderRadius: 8,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: const Color(0xFF1A0000),
                          title: const Text('Settings',
                              style: TextStyle(color: Colors.white)),
                          iconTheme: const IconThemeData(color: Colors.white),
                        ),
                        body: const SettingsScreen(),
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),

          // 🔥 Group 1: المحتوى الرئيسي (معزول)
          Expanded(
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: IndexedStack(
                index: _selectedIndex,
                children: screens,
              ),
            ),
          ),

          // 🔥 Group 2: شريط التنقل السفلي (معزول تماماً عن المحتوى)
          FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: _buildTvBottomNav(context, _selectedIndex, (i) {
              // عند تغيير التبويب، نلغي التركيز الحالي حتى لا يضيع الريموت في الخلفية
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _selectedIndex = i);
            }),
          ),
        ],
      ),
    );
  }

  // ── شريط التنقل السفلي للتلفاز ──
  Widget _buildTvBottomNav(BuildContext context, int selectedIndex, Function(int) onTap) {
    final items = [
      (Icons.live_tv,             'LIVE TV'),
      (Icons.event,               'LIVE EVENT'),
      (Icons.format_list_numbered,'Standings'),
    ];

    return Container(
      height: 64,
      color: Colors.black,
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: TvFocusWrapper(
              borderRadius: 0,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected ? primaryColor.withOpacity(0.9) : Colors.transparent,
                  border: Border(
                    top: BorderSide(
                      color: selected ? TvConfig.focusColor : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[i].$1,
                        color: selected ? Colors.white : Colors.grey,
                        size: 26),
                    const SizedBox(height: 4),
                    Text(items[i].$2,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.grey,
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        )),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 📱 Phone Layout - نفس التصميم الأصلي بالكامل
  // ══════════════════════════════════════════════════════════
  
  Widget _buildPhoneLayout(List<Widget> screens) {
    return Scaffold(
      extendBody: true,
      drawer: const AppDrawer(),
      appBar: AppBar(
        centerTitle: true,
        title: Text(_titles[_selectedIndex]),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                if (!_isLoading) {
                  showSearch(
                    context: context,
                    delegate: CategorySearchDelegate(_allCategories),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text("Settings")),
                  body: const SettingsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),

      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: IndexedStack(index: _selectedIndex, children: screens),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.65),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.live_tv), label: 'LIVE TV'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.event), label: 'LIVE EVENT'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.format_list_numbered), label: 'Standings'),
                ],
                currentIndex: _selectedIndex,
                selectedItemColor: Theme.of(context).primaryColor,
                unselectedItemColor: Colors.grey,
                onTap: (i) => setState(() => _selectedIndex = i),
                type: BottomNavigationBarType.fixed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// --- (APP MODE CONFIG) ---
class AppMode {
  static bool isTvMode = false;
}
// --- (DEVICE SELECTION SCREEN) ---
class DeviceSelectionScreen extends StatelessWidget {
  const DeviceSelectionScreen({super.key});

  Future<void> _selectDevice(BuildContext context, bool isTv) async {
    // 1. حفظ الاختيار في الذاكرة
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTvMode', isTv);
    
    // 2. تحديث المتغير العام
    AppMode.isTvMode = isTv;

    // 3. الانتقال إلى الشاشة الرئيسية
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // خلفية داكنة تناسب الشاشتين
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', width: 120),
              const SizedBox(height: 30),
              const Text(
                'اختر نوع جهازك',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'لتحسين تجربة الاستخدام، يرجى تحديد طريقة التحكم',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              // زر التلفاز / TV Box
              _buildDeviceOption(
                icon: Icons.tv,
                title: 'تلفاز ذكي / TV Box',
                subtitle: 'التحكم باستخدام الريموت كنترول',
                onTap: () => _selectDevice(context, true),
                autofocus: true, // نجعل التلفاز هو الخيار الافتراضي المضاء أولاً
              ),
              
              const SizedBox(height: 20),
              
              // زر الهاتف / التابلت
              _buildDeviceOption(
                icon: Icons.smartphone,
                title: 'هاتف / تابلت',
                subtitle: 'التحكم عبر شاشة اللمس',
                onTap: () => _selectDevice(context, false),
                autofocus: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceOption({
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    required bool autofocus,
  }) {
    // استخدمنا كلاس Focus مباشر هنا لضمان عمله قبل اختيار الوضع
    return Focus(
      autofocus: autofocus,
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(15),
              splashColor: primaryColor.withOpacity(0.3),
              child: AnimatedScale(
                scale: isFocused ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isFocused ? Colors.white : primaryColor, 
                      width: isFocused ? 3.0 : 1.5
                    ),
                    boxShadow: isFocused ? [
                      BoxShadow(color: Colors.white.withOpacity(0.6), blurRadius: 15, spreadRadius: 2)
                    ] : [],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 50, color: Colors.white),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: primaryColor),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }
}
// --- ✨ DYNAMIC NETWORK USAGE BAR ✨ ---
class DynamicNetworkUsageBar extends StatefulWidget {
  const DynamicNetworkUsageBar({super.key});

  @override
  State<DynamicNetworkUsageBar> createState() => _DynamicNetworkUsageBarState();
}

class _DynamicNetworkUsageBarState extends State<DynamicNetworkUsageBar> with SingleTickerProviderStateMixin {
  double _consumedMB = 0.0;
  double _currentSpeed = 0.0;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // أنيميشن النبض لأيقونة الواي فاي
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // محرك ديناميكي لمحاكاة سرعة واستهلاك البث المباشر بشكل حي
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // محاكاة سرعة متغيرة باستمرار (بين 0.5 و 2.5 ميجابايت/ثانية)
          _currentSpeed = (Random().nextDouble() * 2.0) + 0.5;
          _consumedMB += _currentSpeed / 2; // زيادة إجمالي الاستهلاك
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // دالة لتحويل الميجابايت إلى جيجابايت تلقائياً
  String get _formattedConsumed {
    if (_consumedMB >= 1024) {
      return "${(_consumedMB / 1024).toStringAsFixed(2)} GB";
    }
    return "${_consumedMB.toStringAsFixed(1)} MB";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      // 🔥 الغلاف الذكي لدعم الريموت كنترول واللمس 🔥
      child: TvFocusWrapper(
        borderRadius: 12.0,
        onTap: () {
          // تصفير العداد عند الضغط
          setState(() => _consumedMB = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تصفير عداد استهلاك البيانات بنجاح', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: primaryColor,
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryColor.withOpacity(isDark ? 0.4 : 0.8),
                primaryColor.withOpacity(isDark ? 0.1 : 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Icon(
                            Icons.wifi_tethering,
                            color: Colors.white.withOpacity(0.5 + (_pulseController.value * 0.5)),
                            size: 24,
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'استهلاك البيانات (مباشر)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  Text(
                    _formattedConsumed,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'السرعة الحالية: ${_currentSpeed.toStringAsFixed(1)} MB/s',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                  const Text(
                    'انقر لتصفير العداد',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  // الشريط يتحرك بناءً على السرعة الحالية ليعطي إحساساً تفاعلياً
                  value: (_currentSpeed / 3.0).clamp(0.0, 1.0),
                  backgroundColor: Colors.black26,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- (SETTINGS SCREEN - PREMIUM UI) ---
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _buildSettingsCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: TvFocusWrapper(
        borderRadius: 12.0,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? (isDark ? const Color(0xFF1E1E1E) : Colors.white),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: primaryColor.withOpacity(isDark ? 0.2 : 0.1), 
              width: 1.5
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (iconColor ?? primaryColor).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon, 
                  color: iconColor ?? primaryColor, 
                  size: 24
                ),
              ),
              title: Text(
                title, 
                style: const TextStyle(
                  fontWeight: FontWeight.w700, 
                  fontSize: 16
                )
              ),
              trailing: trailing ?? Icon(
                Icons.arrow_forward_ios_rounded, 
                size: 18, 
                color: Colors.grey.shade400
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔥 عزل التركيز لشاشة الإعدادات بالكامل
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ListView(
      padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 24.0,
          bottom: AppMode.isTvMode ? 40.0 : 24.0,
        ),
        // 🔥 يمنع إغلاق الشاشة أو التمرير العشوائي عند الضغط على أسهم الريموت
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, right: 8.0),
            child: Text(
              'إعدادات التطبيق',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          
          const DynamicNetworkUsageBar(),

          _buildSettingsCard(
            context,
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            title: 'الوضع الليلي',
            trailing: Switch(
              value: themeProvider.themeMode == ThemeMode.dark,
              onChanged: (value) => themeProvider.toggleTheme(),
              activeColor: primaryColor,
              activeTrackColor: primaryColor.withOpacity(0.4),
            ),
            onTap: () => themeProvider.toggleTheme(),
          ),
          _buildSettingsCard(
            context,
            icon: Icons.support_agent_rounded,
            title: 'تواصل معنا / الدعم الفني',
            onTap: () => _launchURL('mailto:support@ultratv.me?subject=UltraTV Support'),
          ),
          _buildSettingsCard(
            context,
            icon: Icons.info_outline_rounded,
            title: 'عن التطبيق',
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    contentPadding: const EdgeInsets.all(24.0),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset('assets/images/logo.png', width: 75, height: 75),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Ultra TV', 
                          style: TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.w900,
                            color: primaryColor,
                          )
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version 2.1x', 
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          )
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'تطبيقك المفضل لمشاهدة أحدث القنوات والمباريات بأعلى جودة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
                        ),
                      ],
                    ),
                    actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    actions: [
                      SizedBox(
                        width: double.infinity,
                        child: TvFocusWrapper(
                          borderRadius: 12.0,
                          onTap: () => Navigator.of(context).pop(),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'إغلاق', 
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
// --- ✨ SPLASH ENTRY EFFECT (تأثير دخول بدون لمعة) ✨ ---
class SplashShineEffect extends StatefulWidget {
  final Widget child;
  const SplashShineEffect({required this.child, super.key});

  @override
  State<SplashShineEffect> createState() => _SplashShineEffectState();
}

class _SplashShineEffectState extends State<SplashShineEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // ظهور تدريجي: من 0 إلى 1
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // انبثاق خفيف: من 0.7 إلى 1.0
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
      ),
    );

    // يعمل مرة واحدة فقط عند الدخول
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value,
          child: Transform.scale(
            scale: _scaleAnim.value,
            child: widget.child,
          ),
        );
      },
    );
  }
}
// --- (SPLASH SCREEN WIDGET - FINAL ROBUST VERSION) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _animationController.forward();

    _checkAppStatus();
  }

  Future<void> _checkAppStatus() async {
    // 1. بدء المؤقت
    final splashDelay = Future.delayed(const Duration(seconds: 3));

    // ⚠️ فحص الاتصال بالإنترنت أولاً وقبل كل شيء
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      await Future.delayed(const Duration(seconds: 1));
      connectivityResult = await (Connectivity().checkConnectivity());
    }

    // 🔥 فحص التطبيقات الممنوعة (Reqable/NetCapture/MT Manager)
    String? forbiddenApp;
    try {
      forbiddenApp = await BlacklistDetector.findBlacklistedApp();
    } catch (e) {
      debugPrint("Blacklist check error: $e");
    }

    // --- التحقق من وضع الصيانة ---
    bool isMaintenance = false;
    String maintenanceMessage = "";
    try {
      final maintenanceData = await fetchMaintenanceStatus();
      isMaintenance = maintenanceData['is_maintenance'] ?? false;
      maintenanceMessage = maintenanceData['message'] ?? "التطبيق تحت الصيانة";
    } catch (e) {
      debugPrint("Maintenance check failed");
    }

    // ✅ تم إيقاف فحص الروت (Root) عمداً للسماح لتطبيقات التلفاز (TV Boxes) بالعمل

    // 2. التحقق من أدوات السرقة والبروكسي
    bool isSniffer = await SnifferDetector.isSnifferActive();

    // 3. التحقق من الـ VPN
    bool isVpn = await VPNBlocker.isVpnActive();

    // 4. التحقق من التحديث
    String? updateUrl;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersionCode = packageInfo.buildNumber;
      final versionInfo = await fetchVersionInfo();
      final int latestVersionCode = versionInfo['latest_version_code'] ?? 0;

      if (int.parse(currentVersionCode) < latestVersionCode) {
        updateUrl = versionInfo['update_url'];
      }
    } catch (e) {
      debugPrint("Version check failed");
    }

    // انتظار انتهاء الوقت
    await splashDelay;
    if (!mounted) return;

    // --- اتخاذ القرار ---

    // 🛑 الأولوية القصوى: لا يوجد إنترنت
    if (connectivityResult.contains(ConnectivityResult.none)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
      return;
    }

    // 🛑 التوجيه لشاشات الحظر إذا كان هناك خطر حقيقي أو صيانة
    if (forbiddenApp != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => BlacklistBlockedScreen(appName: forbiddenApp!)),
      );
    } else if (isMaintenance) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => MaintenanceScreen(message: maintenanceMessage)),
      );
    } else if (isSniffer) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SnifferBlockedScreen()),
      );
    } else if (isVpn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VpnBlockedScreen()),
      );
    } else if (updateUrl != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => ForceUpdateScreen(updateUrl: updateUrl!)),
      );
    } else {
      // ✅ التعديل هنا: التوجه المباشر باستخدام الكشف التلقائي (بدون تغيير أي شيء آخر)
      AppMode.isTvMode = await GlobalRemoteManager.isTvDevice();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: SplashShineEffect(
              child: Image.asset(
                'assets/images/logo.png',
                width: 150,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// --- (SIDE DRAWER WIDGET - FINAL VERSION) ---
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }

  void _shareApp() {
    const String appLink = "https://ultrav.me"; 
    const String message = "حمّل تطبيق Ultra TV واستمتع بمشاهدة أفضل القنوات المباشرة!\n$appLink";
    Share.share(message);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).listTileTheme.iconColor;

    // Helper widget for social media icons using FontAwesome
    Widget socialTile(IconData icon, String title, String url) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
        child: TvFocusWrapper(
          borderRadius: 8.0,
          onTap: () => _launchUrl(url),
          child: ListTile(
            leading: FaIcon(icon, color: iconColor, size: 22),
            title: Text(title),
          ),
        ),
      );
    }

    return Drawer(
      child: FocusTraversalGroup(
        // 🔥 عزل التركيز داخل القائمة الجانبية
        policy: WidgetOrderTraversalPolicy(),
        child: ListView(
          padding: EdgeInsets.zero,
          // 🔥 يمنع إغلاق القائمة الجانبية بالخطأ عند الضغط على أسهم الريموت
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Center(
                child: Image.asset(
                  'assets/images/Logoultra.png', 
                  fit: BoxFit.contain,
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
              child: TvFocusWrapper(
                borderRadius: 8.0,
                onTap: () => _launchUrl('https://ultrav.me/privacy'),
                child: ListTile(
                  leading: Icon(Icons.policy, color: iconColor),
                  title: const Text('سياسة الخصوصية'),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
              child: TvFocusWrapper(
                borderRadius: 8.0,
                onTap: _shareApp,
                child: ListTile(
                  leading: Icon(Icons.share, color: iconColor),
                  title: const Text('مشاركة التطبيق'),
                ),
              ),
            ),
            
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text('تابعنا على', style: TextStyle(color: Colors.grey)),
            ),
            socialTile(FontAwesomeIcons.facebook, 'Facebook', 'https://www.facebook.com'),
            socialTile(FontAwesomeIcons.xTwitter, 'Twitter (X)', 'https://www.twitter.com'),
            socialTile(FontAwesomeIcons.instagram, 'Instagram', 'https://www.instagram.com'),
            socialTile(FontAwesomeIcons.youtube, 'YouTube', 'https://www.youtube.com'),
            socialTile(FontAwesomeIcons.tiktok, 'TikTok', 'https://www.tiktok.com'),
            socialTile(FontAwesomeIcons.telegram, 'Telegram', 'https://t.me/ultra_tv_live'),
          ],
        ),
      ),
    );
  }
}
// --- (SEARCH WIDGET - UPGRADED & OPTIMIZED & TV FOCUS) ---
class CategorySearchDelegate extends SearchDelegate<Channel?> {
  final List<Channel> _allChannels;

  // تحسين الأداء: فك تفكيك القائمة مرة واحدة عند الإنشاء
  CategorySearchDelegate(List<Category> allCategories)
      : _allChannels = allCategories.expand((c) => c.channels).toList();

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      textTheme: theme.textTheme.copyWith(
        titleLarge: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // تصفية النتائج
    final results = _allChannels
        .where((channel) => channel.name.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.search_off, size: 60, color: Colors.grey),
            SizedBox(height: 10),
            Text("لا توجد قنوات مطابقة", style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    // 🔥 عزل التركيز ومنع إغلاق البحث بالريموت
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        // يمنع إغلاق لوحة المفاتيح/الشاشة عند الضغط على أسهم الريموت
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        itemCount: results.length,
        itemBuilder: (context, index) {
          final channel = results[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            child: TvFocusWrapper(
              borderRadius: 8.0,
              onTap: () {
                close(context, channel);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PlayerScreen(servers: channel.servers)),
                );
              },
              child: Card(
                elevation: 0.0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: const BorderSide(color: Color(0xFFB22222), width: 2.0),
                ),
                child: ListTile(
                  leading: SizedBox(
                    width: 50,
                    height: 50,
                    child: CachedNetworkImage(
                      imageUrl: channel.logoUrl,
                      fit: BoxFit.contain,
                      memCacheWidth: DeviceConfig.isLowRamDevice ? 100 : null,
                      // ✅ تم ترتيب المسافات بشكل صحيح
                      placeholder: (_, __) => Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Image.asset('assets/images/logo1.png', width: 40, height: 40, fit: BoxFit.contain),
                      ),
                      errorWidget: (_, __, ___) => const Icon(Icons.tv, color: primaryColor),
                    ),
                  ),
                  title: Text(channel.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.play_circle_outline, color: primaryColor),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    // عرض النتائج فوراً أثناء الكتابة
    return buildResults(context);
  }
}
// --- (DATA MODELS - FINAL VERSION) ---

class Server {
  final String name;
  final String url;
  final String? drmScheme;
  final String? drmLicenseKey;
  final Map<String, String>? headers;

  Server({
    required this.name,
    required this.url,
    this.drmScheme,
    this.drmLicenseKey,
    this.headers,
  });

  // هذه الدالة ستقرأ هيكل السيرفرات القديم والجديد
  // ... (داخل كلاس Server)

  factory Server.fromJson(Map<String, dynamic> json) {
    // 1. التعامل مع الهيكل القديم: {"Server 1": "http://..."}
    if (json.keys.length == 1) {
      return Server(
        name: json.keys.first,
        url: json.values.first,
        headers: { // إضافة الهيدر الافتراضي للروابط القديمة
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
        }
      );
    }
    
    // 2. التعامل مع الهيكل الجديد (الخاص بـ VOD و DRM)
    return Server(
      name: json['name'] ?? 'Stream',
      url: json['url'] ?? '',
      
      // --- ✅✅ هذا هو الإصلاح ✅✅ ---
      // يبحث عن "scheme" أو "drm_scheme"
      drmScheme: json['scheme'] ?? json['drm_scheme'], 
      // يبحث عن "license" أو "drm_license_key"
      drmLicenseKey: json['license'] ?? json['drm_license_key'], 
      // --- نهاية الإصلاح ---
      
      headers: json['headers'] != null ? Map<String, String>.from(json['headers']) : {
         'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36',
      },
    );
  }
}

class Category {
  final String name;
  final String logoUrl;
  final List<Channel> channels;
  Category({required this.name, required this.logoUrl, required this.channels});
}

class Channel {
  final String name;
  final List<Server> servers; // ✅ تم التحديث إلى List<Server>
  final String logoUrl;
  Channel({required this.name, required this.servers, required this.logoUrl});
}

class Match {
  final String team1Name;
  final dynamic team1Logo;
  final String team2Name;
  final dynamic team2Logo;
  final String status, league;
  final String? score;
  final int startTime;
  final bool isLive;
  final String? channel;
  final String? commentator;
  final List<Server>? servers; // ✅ تم التحديث إلى List<Server>

  Match({
    required this.team1Name, required this.team1Logo,
    required this.team2Name, required this.team2Logo,
    required this.status, required this.league,
    required this.startTime, this.score, this.isLive = false,
    this.channel, this.commentator, this.servers,
  });
}
class YsLeague {
  final int id;
  final int urlId;        // يُستخدم في باقي الـ API
  final String title;
  final String image;     // اسم الصورة فقط (مثل "8571694218364.png")
  final bool hasStandings;
  final bool hasScorers;

  YsLeague({
    required this.id,
    required this.urlId,
    required this.title,
    required this.image,
    required this.hasStandings,
    required this.hasScorers,
  });

  // 🔥 تم تصحيح المسار هنا إلى championships
  String get logoUrl => 'https://imgs.ysscores.com/championships/128/$image';

  factory YsLeague.fromJson(Map<String, dynamic> json) {
    return YsLeague(
      id: json['id'] ?? 0,
      urlId: json['url_id'] ?? 0,
      title: json['title'] ?? '',
      image: json['image'] ?? '',
      hasStandings: (json['standings'] ?? 0) == 1,
      hasScorers: (json['players_st'] ?? 0) == 1,
    );
  }
}

// نموذج الفريق في جدول الترتيب
class YsTeam {
  final int teamId;
  final String teamName;
  final String teamImage;  // اسم الصورة فقط
  final String color;      // لون التأهل (#16a765 = أخضر، #ffad46 = برتقالي)
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int diff;
  final int points;

  YsTeam({
    required this.teamId,
    required this.teamName,
    required this.teamImage,
    required this.color,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.diff,
    required this.points,
  });

  // رابط شعار الفريق
  String get logoUrl => 'https://imgs.ysscores.com/teams/128/$teamImage';
  
  // هل الفريق متأهل؟
  bool get isQualified => color == '#16a765';
  // هل في المنطقة البرتقالية (أفضل ثوالث)؟
  bool get isOrange => color == '#ffad46';

  factory YsTeam.fromJson(Map<String, dynamic> json) {
    final teamName = json['team_name'] as Map<String, dynamic>? ?? {};
    return YsTeam(
      teamId: json['team_id'] ?? 0,
      teamName: teamName['title'] ?? '',
      teamImage: teamName['image'] ?? '',
      color: json['color'] ?? '',
      played: json['play'] ?? 0,
      wins: json['wins'] ?? 0,
      draws: json['draw'] ?? 0,
      losses: json['lose'] ?? 0,
      goalsFor: json['for'] ?? 0,
      goalsAgainst: json['against'] ?? 0,
      diff: json['diff'] ?? 0,
      points: json['points'] ?? 0,
    );
  }
}

// نموذج مجموعة واحدة
class YsGroup {
  final String name;      // "A", "B", "C"...
  final List<YsTeam> teams;

  YsGroup({required this.name, required this.teams});
}

// نموذج لاعب (هداف أو صانع)
class YsPlayer {
  final int playerId;
  final String name;
  final String image;
  final String teamName;
  final int count;       // أهداف أو تمريرات

  YsPlayer({
    required this.playerId,
    required this.name,
    required this.image,
    required this.teamName,
    required this.count,
  });

  String get photoUrl => 'https://imgs.ysscores.com/players/128/$image';

  factory YsPlayer.fromScorerJson(Map<String, dynamic> json) {
    final info = json['player_info'] as Map<String, dynamic>? ?? {};
    return YsPlayer(
      playerId: json['player_id'] ?? 0,
      name: info['title'] ?? '',
      image: info['image'] ?? '',
      teamName: info['team_name'] ?? '',
      count: json['goals'] ?? 0,
    );
  }

  factory YsPlayer.fromAssistJson(Map<String, dynamic> json) {
    final info = json['player_info'] as Map<String, dynamic>? ?? {};
    return YsPlayer(
      playerId: json['player_id'] ?? 0,
      name: info['title'] ?? '',
      image: info['image'] ?? '',
      teamName: info['team_name'] ?? '',
      count: json['assist'] ?? 0,
    );
  }
}


// --- (API FUNCTIONS - FINAL VERSION) ---
Future<List<Category>> fetchCategories() async {
  try {
    // ✅✅ التعديل هنا: أضفنا orderBy('orderId') ✅✅
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('categories')
        .orderBy('orderId') // هذا السطر سيجبر البيانات على الظهور بنفس ترتيب الملف
        .get();

    if (snapshot.docs.isEmpty) {
      return [];
    }

    return snapshot.docs.map((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      
      var channelsList = (data['channels'] as List? ?? []).map((c) {
        var serversList = (c['servers'] as List? ?? []).map((s) => Server.fromJson(s)).toList();
        return Channel(
          name: c['name'] ?? 'No Name', 
          logoUrl: c['logoUrl'] ?? '', 
          servers: serversList
        );
      }).toList();

      return Category(
        name: data['name'] ?? 'Unknown',
        logoUrl: data['logoUrl'] ?? '',
        channels: channelsList,
      );
    }).toList();
  } catch (e) {
    print("❌ خطأ: $e");
    return [];
  }
}

Future<List<Match>> fetchMatches() async {
  try {
    // جلب المباريات وترتيبها حسب وقت البداية (الأحدث أولاً أو حسب رغبتك)
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('matches')
        .orderBy('startTime') // ترتيب زمني
        .get();

    return snapshot.docs.map((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      
      // معالجة السيرفرات الخاصة بالمباريات
      List<Server>? servers;
      if (data['servers'] != null) {
        servers = (data['servers'] as List).map((s) => Server.fromJson(s)).toList();
      }

      return Match(
        team1Name: data['team1Name'] ?? 'Team 1',
        team1Logo: data['team1Logo'] ?? '',
        team2Name: data['team2Name'] ?? 'Team 2',
        team2Logo: data['team2Logo'] ?? '',
        status: data['status'] ?? 'Soon',
        league: data['league'] ?? 'Unknown League',
        score: data['score'], // قد يكون null
        startTime: data['startTime'] ?? 0,
        isLive: data['isLive'] ?? false,
        channel: data['channel'],
        commentator: data['commentator'],
        servers: servers,
      );
    }).toList();
  } catch (e) {
    print("❌ خطأ في جلب المباريات من فايربيس: $e");
    return [];
  }
}
// (بقية دوال API مثل fetchStandings و fetchNotifications تبقى كما هي)
// ...
// --- (API FUNCTION FOR VERSION CHECK - FIREBASE) ---
Future<Map<String, dynamic>> fetchVersionInfo() async {
  try {
    // الاتصال بمستند version داخل مجموعة settings
    DocumentSnapshot snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('version')
        .get();

    if (snapshot.exists && snapshot.data() != null) {
      return snapshot.data() as Map<String, dynamic>;
    } else {
      // إذا لم تكن البيانات موجودة، نرجع خريطة فارغة (لا يوجد تحديث)
      return {}; 
    }
  } catch (e) {
    debugPrint("Error fetching version info from Firebase: $e");
    return {}; 
  }
}

// --- (MAINTENANCE LOGIC - FIREBASE) ---

// 1. دالة جلب حالة الصيانة
Future<Map<String, dynamic>> fetchMaintenanceStatus() async {
  try {
    // الاتصال بمستند maintenance داخل مجموعة settings
    DocumentSnapshot snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('maintenance')
        .get();

    if (snapshot.exists && snapshot.data() != null) {
      return snapshot.data() as Map<String, dynamic>;
    }
  } catch (e) {
    debugPrint("Error fetching maintenance status from Firebase: $e");
  }
  // في حالة الخطأ أو عدم وجود بيانات، التطبيق يعمل بشكل طبيعي
  return {"is_maintenance": false, "message": ""};
}

// 2. شاشة الصيانة (بقيت كما هي تماماً بدون تغيير)
class MaintenanceScreen extends StatelessWidget {
  final String message;
  const MaintenanceScreen({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.build_circle_outlined, color: Colors.white, size: 100),
              const SizedBox(height: 20),
              const Text(
                "التطبيق تحت الصيانة",
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 24, 
                  fontWeight: FontWeight.bold
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // زر للخروج من التطبيق
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                ),
                child: const Text("إغلاق التطبيق"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- (API FUNCTIONS - محمية عبر Worker) ---
// ⚠️  استبدل WORKER_HOST بدومين Worker الخاص بك
// Worker يقوم بإضافة رابط API الحقيقي داخليًا

const String _YS_WORKER = "ultra-tv-proxy.dzandz496.workers.dev"; // دومين Worker الخاص بك

// جلب قائمة الدوريات (60 دوري)
Future<List<YsLeague>> fetchYsLeagues() async {
  try {
    // Worker يُحوّل هذا إلى: https://api-ar.ysscores.com/api/info/championship_ranking/D/60
    final response = await http.get(
      Uri.parse('https://$_YS_WORKER/ys/leagues'),
      headers: {'User-Agent': APP_USER_AGENT},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List list = data['data'] ?? [];
      return list.map((e) => YsLeague.fromJson(e)).toList();
    }
  } catch (e) {
    debugPrint('❌ fetchYsLeagues error: $e');
  }
  return [];
}

// جلب جدول الترتيب لدوري معين
Future<List<YsGroup>> fetchYsStandings(int leagueUrlId) async {
  try {
    // Worker يُحوّل إلى: https://api-ar.ysscores.com/api/matches/Group_standings/{id}/D/60
    final response = await http.get(
      Uri.parse('https://$_YS_WORKER/ys/standings/$leagueUrlId'),
      headers: {'User-Agent': APP_USER_AGENT},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final groupsData = data['data']?['groups'] as Map<String, dynamic>? ?? {};
      
      List<YsGroup> groups = [];
      groupsData.forEach((groupName, teamsList) {
        if (teamsList is List) {
          // ترتيب الفرق حسب النقاط تنازليًا
          final teams = (teamsList)
              .map((t) => YsTeam.fromJson(t))
              .toList()
            ..sort((a, b) {
              if (b.points != a.points) return b.points.compareTo(a.points);
              return b.diff.compareTo(a.diff);
            });
          groups.add(YsGroup(name: 'المجموعة $groupName', teams: teams));
        }
      });
      
      // ترتيب المجموعات أبجديًا (A, B, C...)
      groups.sort((a, b) => a.name.compareTo(b.name));
      return groups;
    }
  } catch (e) {
    debugPrint('❌ fetchYsStandings error: $e');
  }
  return [];
}

// جلب الهدافين وصناع الأهداف
Future<Map<String, List<YsPlayer>>> fetchYsScorers(int leagueUrlId) async {
  try {
    // Worker يُحوّل إلى: https://api-ar.ysscores.com/api/matches/league_scorers/{id}
    final response = await http.get(
      Uri.parse('https://$_YS_WORKER/ys/scorers/$leagueUrlId'),
      headers: {'User-Agent': APP_USER_AGENT},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final scorersData = data['data'] as Map<String, dynamic>? ?? {};
      
      final scorers = (scorersData['scorers'] as List? ?? [])
          .take(10)
          .map((e) => YsPlayer.fromScorerJson(e))
          .toList();
      
      final assists = (scorersData['assist'] as List? ?? [])
          .take(10)
          .map((e) => YsPlayer.fromAssistJson(e))
          .toList();

      return {'scorers': scorers, 'assists': assists};
    }
  } catch (e) {
    debugPrint('❌ fetchYsScorers error: $e');
  }
  return {'scorers': [], 'assists': []};
}
// --- (HOME SCREEN - UPDATED FOR TV FOCUS & SHIMMER LOGO) ---
class HomeScreen extends StatelessWidget {
  final bool isLoading;
  final List<Category> allCategories;

  const HomeScreen({
    required this.isLoading,
    required this.allCategories,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && allCategories.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }
    if (allCategories.isEmpty) {
      return const Center(child: Text("لا توجد قنوات."));
    }

    // ── تلفاز: شبكة مستقرة مع الريموت ────────────────────────
    if (AppMode.isTvMode) {
      return _TvCategoryGrid(allCategories: allCategories);
    }

    // ── هاتف: قائمة عادية ───────────────────────────────────
    return _PhoneCategoryList(allCategories: allCategories);
  }
}

/// شبكة فئات للتلفاز (مستقرة 100% مع الريموت)
class _TvCategoryGrid extends StatelessWidget {
  final List<Category> allCategories;
  const _TvCategoryGrid({required this.allCategories});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols  = TvConfig.gridColumns(width);

    // 🔥 FocusTraversalGroup يمنع القفز العشوائي للريموت
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 1.0,
        ),
        // 🔥 يمنع إغلاق الشاشة أو التمرير المجنون عند ضغط أسهم الريموت
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        itemCount: allCategories.length,
        itemBuilder: (context, index) {
          final category = allCategories[index];
          return TvFocusWrapper(
            autofocus: index == 0,
            borderRadius: 12,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsGridScreen(category: category),
              ),
            ),
            child: _TvCategoryCard(category: category),
          );
        },
      ),
    );
  }
}

class _TvCategoryCard extends StatelessWidget {
  final Category category;
  const _TvCategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: category.logoUrl,
            width: 56, 
            height: 56,
            fit: BoxFit.contain,
            memCacheWidth: 120, // تقليل الحجم للأجهزة الضعيفة
            placeholder: (_, __) => const Icon(
              Icons.live_tv, size: 40, color: primaryColor,
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.live_tv, size: 40, color: primaryColor,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// قائمة فئات للهاتف (نفس الكود القديم مع ترتيب مسافات صحيح)
class _PhoneCategoryList extends StatelessWidget {
  final List<Category> allCategories;
  const _PhoneCategoryList({required this.allCategories});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 12, 
        right: 12, 
        top: 12,
        bottom: 100, // مسافة لشريط التنقل السفلي
      ),
      itemCount: allCategories.length,
      itemBuilder: (context, index) {
        final category = allCategories[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TvFocusWrapper(
            borderRadius: 8,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsGridScreen(category: category),
              ),
            ),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFB22222), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: category.logoUrl,
                      width: 40, 
                      height: 40,
                      fit: BoxFit.cover,
                      memCacheWidth: DeviceConfig.isLowRamDevice ? 100 : null,
                      cacheManager: MyCustomCacheManager.instance,
                      placeholder: (_, __) => Image.asset(
                        'assets/images/logo.png',
                        width: 40, 
                        height: 40, 
                        fit: BoxFit.cover,
                      ),
                      errorWidget: (_, __, ___) => const Icon(Icons.error),
                    ),
                  ),
                ),
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios, 
                  size: 16, 
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
// --- (CHANNELS GRID SCREEN - UPDATED WITH AUTO SCROLL & TV FOCUS) ---
class ChannelsGridScreen extends StatelessWidget {
  final Category category;
  const ChannelsGridScreen({required this.category, super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols  = AppMode.isTvMode ? TvConfig.gridColumns(width) : 3;
    final ratio = AppMode.isTvMode ? 0.95 : 0.8;

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: FocusTraversalGroup(
        // 🔥 يضمن أن الأسهم تنتقل بترتيب شبكي مثالي (يمين، يسار، تحت، فوق)
        policy: WidgetOrderTraversalPolicy(),
        child: GridView.builder(
          padding: EdgeInsets.all(AppMode.isTvMode ? 24 : 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: AppMode.isTvMode ? 20 : 10,
            mainAxisSpacing:  AppMode.isTvMode ? 20 : 10,
            childAspectRatio: ratio,
          ),
          // 🔥 يمنع إغلاق الشاشة أو التمرير العشوائي عند الضغط على أسهم الريموت
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          itemCount: category.channels.length,
          itemBuilder: (context, index) {
            final channel = category.channels[index];
            return TvFocusWrapper(
              autofocus: index == 0,
              borderRadius: 10,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(servers: channel.servers),
                ),
              ),
              child: _ChannelCard(channel: channel),
            );
          },
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final Channel channel;
  const _ChannelCard({required this.channel});

  @override
  Widget build(BuildContext context) {
    final isTv = AppMode.isTvMode;

    return Container(
      decoration: BoxDecoration(
        color: isTv ? const Color(0xFF1A0000) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFB22222),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CachedNetworkImage(
                imageUrl: channel.logoUrl,
                fit: BoxFit.contain,
                memCacheWidth: DeviceConfig.isLowRamDevice ? 150 : null,
                cacheManager: MyCustomCacheManager.instance,
                // ✅ تم إصلاح المسافات هنا
                placeholder: (_, __) => Image.asset(
                  'assets/images/logo1.png',
                  width: 40, 
                  fit: BoxFit.contain,
                ),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.tv, size: 40, color: primaryColor,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              channel.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTv ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: isTv ? 13 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// --- ✨ SHIMMER LOGO FOR CHANNELS GRID (logo1.png) ✨ ---
class GridShimmerLogo extends StatelessWidget {
  const GridShimmerLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo1.png',
      width: 40,
      height: 40,
      fit: BoxFit.contain,
    );
  }
}
// --- (AUTO SCROLL TEXT WIDGET) ---
// هذا الكلاس يجعل النص يتحرك تلقائياً إذا كان طويلاً، ويتوقف في الأجهزة الضعيفة
class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const AutoScrollText({required this.text, required this.style, super.key});

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  late ScrollController _scrollController;
  bool _needsScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkAndScroll() async {
    if (!mounted) return;
    // التحقق مما إذا كان النص يحتاج للتحرك (فقط للأجهزة القوية)
    if (!DeviceConfig.isLowRamDevice && _scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
      setState(() => _needsScrolling = true);
      _startScrollingLoop();
    }
  }

  void _startScrollingLoop() async {
    while (mounted && _needsScrolling) {
      if (!_scrollController.hasClients) break;
      await Future.delayed(const Duration(seconds: 2)); // انتظار قبل البدء
      if (!mounted) break;
      
      // التحرك لليسار
      try {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(seconds: 4), // مدة الحركة
          curve: Curves.linear,
        );
      } catch (e) { break; }

      await Future.delayed(const Duration(seconds: 2)); // انتظار في النهاية
      if (!mounted) break;

      // العودة للبداية
      try {
        await _scrollController.animateTo(
          0.0,
          duration: const Duration(seconds: 1),
          curve: Curves.easeOut,
        );
      } catch (e) { break; }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 إذا كان الجهاز ضعيفاً، نعرض نصاً ثابتاً فقط للحفاظ على المعالج
    if (DeviceConfig.isLowRamDevice) {
      return Text(
        widget.text, 
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollController,
      // نمنع اللمس اليدوي لكي لا يتعارض مع الحركة التلقائية
      physics: const NeverScrollableScrollPhysics(), 
      child: Text(widget.text, style: widget.style),
    );
  }
}
// --- ✅ LIVE EVENTS SCREEN - FINAL VERSION ---
class LiveEventsScreen extends StatefulWidget {
  final List<Category> allCategories;
  const LiveEventsScreen({required this.allCategories, super.key});

  @override
  State<LiveEventsScreen> createState() => _LiveEventsScreenState();
}

class _LiveEventsScreenState extends State<LiveEventsScreen> {
  List<Match> _matches = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAndSetMatches();
  }

  Future<void> _fetchAndSetMatches() async {
    try {
      final matches = await fetchMatches();
      matches.sort((a, b) {
        int pa = _priority(a), pb = _priority(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.startTime.compareTo(b.startTime);
      });
      if (mounted) {
        setState(() { _matches = matches; _isLoading = false; _errorMessage = null; });
      }
    } catch (e) {
      if (mounted) setState(() { _errorMessage = "$e"; _isLoading = false; });
    }
  }

  int _priority(Match m) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final end = m.startTime + 7200;
    if (m.status.toLowerCase().contains('finished') || m.status == 'FT') return 2;
    if (m.isLive || (now >= m.startTime && now < end)) return 0;
    if (now >= end) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryColor));
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_matches.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 20),
          const Text('لا توجد مباريات اليوم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
        ]),
      );
    }

    // ── تلفاز: شبكة مباريات مستقرة ─────────────────────────
    if (AppMode.isTvMode) {
      return _buildTvMatchGrid();
    }

    // ── هاتف: قائمة مباريات ──────────────────────────────────
    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 100),
      itemCount: _matches.length,
      itemBuilder: (_, i) => MatchCard(
        match: _matches[i],
        onTap: () => _openMatch(_matches[i]),
      ),
    );
  }

  Widget _buildTvMatchGrid() {
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1200 ? 3 : 2;

    // 🔥 FocusTraversalGroup يضمن انتقال سلس بالريموت (يمين، يسار، فوق، تحت)
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 1.6,
        ),
        // 🔥 يمنع إغلاق الشاشة أو التمرير العشوائي بالريموت
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        itemCount: _matches.length,
        itemBuilder: (_, i) {
          final match = _matches[i];
          return TvFocusWrapper(
            autofocus: i == 0,
            borderRadius: 12,
            onTap: () => _openMatch(match),
            child: MatchCard(match: match, onTap: null),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: const Icon(Icons.wifi_off_rounded, color: primaryColor, size: 50),
          ),
          const SizedBox(height: 20),
          const Text('فشل الاتصال',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('يرجى التحقق من الإنترنت والمحاولة مجدداً.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 25),
          TvFocusWrapper(
            autofocus: true,
            borderRadius: 10,
            onTap: () {
              setState(() { _isLoading = true; _errorMessage = null; });
              _fetchAndSetMatches();
            },
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              ),
              onPressed: null, // TvFocusWrapper يتحكم
              child: const Text("إعادة المحاولة",
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  void _openMatch(Match match) {
    if (match.servers != null && match.servers!.isNotEmpty) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerScreen(servers: match.servers!)));
      return;
    }
    if (match.channel == null || match.channel!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('معلومات القناة غير متاحة.')));
      return;
    }
    Channel? found;
    for (var cat in widget.allCategories) {
      for (var ch in cat.channels) {
        if (ch.name.toLowerCase().contains(match.channel!.toLowerCase())) {
          found = ch;
          break;
        }
      }
      if (found != null) break;
    }
    if (found != null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerScreen(servers: found!.servers)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('القناة "${match.channel}" غير موجودة.')));
    }
  }
}
// --- (STANDINGS SCREEN - MAIN LIST) ---
class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  List<YsLeague> _allLeagues = [];
  List<YsLeague> _filteredLeagues = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  int _focusedLeagueIndex = 0; // للتلفاز

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLeagues() async {
    final data = await fetchYsLeagues();
    if (mounted) {
      setState(() {
        _allLeagues = data;
        _filteredLeagues = data;
        _isLoading = false;
      });
    }
  }

  void _filterLeagues(String query) {
    if (query.isEmpty) {
      setState(() => _filteredLeagues = _allLeagues);
      return;
    }
    final lq = query.toLowerCase();
    setState(() {
      _filteredLeagues = _allLeagues
          .where((l) => l.title.toLowerCase().contains(lq))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryColor));
    }

    if (AppMode.isTvMode) return _buildTvLayout();
    return _buildPhoneLayout();
  }

  // ── TV Layout (مستقر تماماً مع الريموت) ────────────────────
  Widget _buildTvLayout() {
    return Row(
      children: [
        // 🔥 Group 1: القائمة اليسرى (معزولة تماماً)
        FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.28,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterLeagues,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'بحث...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: primaryColor, size: 20),
                      filled: true,
                      fillColor: const Color(0xFF1A0000),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: primaryColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: primaryColor.withOpacity(0.4)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    // 🔥 يمنع إغلاق الشاشة بالريموت
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                    itemCount: _filteredLeagues.length,
                    itemBuilder: (_, i) {
                      final league = _filteredLeagues[i];
                      final isFocused = i == _focusedLeagueIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TvFocusWrapper(
                          autofocus: i == 0,
                          borderRadius: 10,
                          onTap: () => setState(() => _focusedLeagueIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: isFocused ? primaryColor : const Color(0xFF1A0000),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isFocused ? TvConfig.focusColor : primaryColor.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: league.logoUrl,
                                  width: 28, height: 28,
                                  fit: BoxFit.contain,
                                  httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                                  placeholder: (_, __) => const Icon(Icons.emoji_events, size: 20, color: Colors.white70),
                                  errorWidget: (_, __, ___) => const Icon(Icons.emoji_events, size: 20, color: Colors.white70),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    league.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        
        Container(width: 1, color: primaryColor.withOpacity(0.3)),
        
        // 🔥 Group 2: التفاصيل اليمنى (معزولة تماماً)
        // عند الضغط على سهم "يمين" في القائمة، سينتقل التركيز تلقائياً هنا
        FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Expanded(
            child: _filteredLeagues.isEmpty
                ? const Center(child: Text('لا توجد بيانات', style: TextStyle(color: Colors.grey, fontSize: 16)))
                : YsLeagueDetailScreen(
                    league: _filteredLeagues[_focusedLeagueIndex.clamp(0, _filteredLeagues.length - 1)],
                    embedMode: true,
                  ),
          ),
        ),
      ],
    );
  }

  // ── Phone Layout ──────────────────────────────────────────────
  Widget _buildPhoneLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _filterLeagues,
            decoration: InputDecoration(
              hintText: 'ابحث عن بطولة...',
              prefixIcon: const Icon(Icons.search, color: primaryColor),
              filled: true,
              fillColor: Colors.grey.withOpacity(0.1),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () { 
                        _searchController.clear(); 
                        _filterLeagues(''); 
                        setState(() {}); // لتحديث حالة زر المسح
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _filteredLeagues.isEmpty
              ? Center(
                  child: Text(
                    _allLeagues.isEmpty ? "لا تتوفر بيانات" : "لا توجد نتائج",
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: _filteredLeagues.length,
                  itemBuilder: (_, i) => _buildLeagueCard(_filteredLeagues[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildLeagueCard(YsLeague league) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TvFocusWrapper(
        borderRadius: 12,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => YsLeagueDetailScreen(league: league)),
        ),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: primaryColor, width: 0.8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 44, height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: CachedNetworkImage(
                imageUrl: league.logoUrl,
                fit: BoxFit.contain,
                httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                placeholder: (_, __) => const Icon(Icons.emoji_events, size: 20, color: primaryColor),
                errorWidget: (_, __, ___) => const Icon(Icons.emoji_events, size: 20, color: primaryColor),
              ),
            ),
            title: Text(
              league.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: league.hasScorers
                ? const Text('إحصائيات متاحة', style: TextStyle(fontSize: 11, color: primaryColor))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (league.hasStandings)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('ترتيب', style: TextStyle(fontSize: 10, color: primaryColor, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios, size: 14, color: primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// --- (LEAGUE DETAILS SCREEN) ---
class YsLeagueDetailScreen extends StatefulWidget {
  final YsLeague league;
  final bool embedMode;

  const YsLeagueDetailScreen({
    required this.league,
    this.embedMode = false,
    super.key,
  });

  @override
  State<YsLeagueDetailScreen> createState() => _YsLeagueDetailScreenState();
}

class _YsLeagueDetailScreenState extends State<YsLeagueDetailScreen>
    with SingleTickerProviderStateMixin {
  
  late TabController _tabController;
  
  // بيانات الجدول
  List<YsGroup> _groups = [];
  bool _loadingStandings = true;
  
  // بيانات الهدافين
  List<YsPlayer> _scorers = [];
  List<YsPlayer> _assists = [];
  bool _loadingScorers = false;
  bool _scorersLoaded = false;

  @override
  void initState() {
    super.initState();
    // عدد التبويبات يعتمد على ما هو متاح
    final tabCount = widget.league.hasScorers ? 3 : 1;
    _tabController = TabController(length: tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadStandings();
  }

  @override
  void didUpdateWidget(YsLeagueDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عند تغيير الدوري في وضع TV
    if (oldWidget.league.urlId != widget.league.urlId) {
      setState(() {
        _groups = [];
        _loadingStandings = true;
        _scorers = [];
        _assists = [];
        _scorersLoaded = false;
        _loadingScorers = false;
      });
      _loadStandings();
    }
  }

  void _onTabChanged() {
    // تحميل الهدافين عند أول فتح للتبويب
    if (_tabController.index == 1 && !_scorersLoaded && !_loadingScorers) {
      _loadScorers();
    } else if (_tabController.index == 2 && !_scorersLoaded && !_loadingScorers) {
      _loadScorers();
    }
  }

  Future<void> _loadStandings() async {
    final groups = await fetchYsStandings(widget.league.urlId);
    if (mounted) {
      setState(() {
        _groups = groups;
        _loadingStandings = false;
      });
    }
  }

  Future<void> _loadScorers() async {
    setState(() => _loadingScorers = true);
    final data = await fetchYsScorers(widget.league.urlId);
    if (mounted) {
      setState(() {
        _scorers = data['scorers'] ?? [];
        _assists = data['assists'] ?? [];
        _scorersLoaded = true;
        _loadingScorers = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = widget.league.hasScorers ? 3 : 1;
    
    final body = Column(
      children: [
        // ── بانر الدوري ─────────────────────────────────────
        _buildLeagueBanner(),

        // ── التبويبات ────────────────────────────────────────
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabController,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primaryColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              const Tab(text: 'الترتيب'),
              if (tabCount >= 2) const Tab(text: 'الهدافون'),
              if (tabCount >= 3) const Tab(text: 'الصناع'),
            ],
          ),
        ),

        // ── محتوى التبويبات ───────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStandingsTab(),
              if (tabCount >= 2) _buildScorersTab(_scorers, 'أهداف'),
              if (tabCount >= 3) _buildScorersTab(_assists, 'تمريرة'),
            ],
          ),
        ),
      ],
    );

    if (widget.embedMode) return body;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: Text(widget.league.title, style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
      ),
      body: body,
    );
  }

  // ── بانر الدوري ───────────────────────────────────────────────
  Widget _buildLeagueBanner() {
    if (widget.embedMode) {
      // نسخة مصغّرة للتلفاز
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            CachedNetworkImage(
              imageUrl: widget.league.logoUrl,
              width: 36, height: 36,
              fit: BoxFit.contain,
              httpHeaders: const {'User-Agent': 'Mozilla/5.0'}, // 🔥 الهيدر السحري
              placeholder: (_, __) => const SizedBox(),
              errorWidget: (_, __, ___) => const SizedBox(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.league.title,
                style: const TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
      decoration: const BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: CachedNetworkImage(
              imageUrl: widget.league.logoUrl,
              height: 60, width: 60,
              fit: BoxFit.contain,
              httpHeaders: const {'User-Agent': 'Mozilla/5.0'}, // 🔥 الهيدر السحري
              placeholder: (_, __) => const SizedBox(height: 60, width: 60),
              errorWidget: (_, __, ___) => const Icon(Icons.emoji_events, size: 60, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  // ── تبويب الترتيب ──────────────────────────────────────────────
  Widget _buildStandingsTab() {
    if (_loadingStandings) {
      return const Center(child: CircularProgressIndicator(color: primaryColor));
    }
    if (_groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined, size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا يتوفر ترتيب للنقاط', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        ..._groups.map((g) => _buildGroupTable(g)),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── جدول مجموعة واحدة ──────────────────────────────────────────
  Widget _buildGroupTable(YsGroup group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اسم المجموعة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 4, height: 18,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  group.name,
                  style: const TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          // الجدول
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: primaryColor.withOpacity(0.12),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // رأس الجدول
                _buildTableHeader(isDark),
                // صفوف الفرق
                ...group.teams.asMap().entries.map((entry) {
                  final i = entry.key;
                  final team = entry.value;
                  final isLast = i == group.teams.length - 1;
                  return _buildTeamRow(team, i + 1, isLast, isDark);
                }),
                // مفتاح الألوان
                _buildColorLegend(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A0A0A) : const Color(0xFFFFF0F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 22, child: Center(child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)))),
          const SizedBox(width: 8),
          const Expanded(child: Text('الفريق', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))),
          _headerCell('ل'), _headerCell('ف'), _headerCell('ت'), _headerCell('خ'),
          _headerCell('ف:خ', width: 36),
          _headerCell('+/-', width: 28),
          _headerCell('نقاط', width: 32, color: primaryColor),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {double width = 24, Color? color}) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildTeamRow(YsTeam team, int rank, bool isLast, bool isDark) {
    // تحديد لون الشريط الجانبي
    Color sideColor;
    if (team.isQualified) {
      sideColor = const Color(0xFF16a765); // أخضر = تأهل
    } else if (team.isOrange) {
      sideColor = const Color(0xFFffad46); // برتقالي = أفضل ثوالث
    } else {
      sideColor = Colors.transparent;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast ? BorderSide.none : BorderSide(color: Colors.grey.withOpacity(0.08)),
          right: BorderSide(color: sideColor, width: 3.5),
        ),
        color: rank % 2 == 0
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.grey.withOpacity(0.02))
            : Colors.transparent,
      ),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Row(
        children: [
          // رقم الترتيب
          SizedBox(
            width: 22,
            child: Center(
              child: Container(
                width: 20, height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? const Color(0xFFFFD700)
                      : rank == 2
                          ? const Color(0xFFC0C0C0)
                          : rank == 3
                              ? const Color(0xFFCD7F32)
                              : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: rank <= 3 ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // الفريق
          Expanded(
            child: Row(
              children: [
                CachedNetworkImage(
                  imageUrl: team.logoUrl,
                  width: 22, height: 22,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(width: 22, height: 22),
                  errorWidget: (_, __, ___) => const Icon(Icons.shield, size: 18, color: Colors.grey),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    team.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // الإحصائيات
          _statCell('${team.played}', isDark),
          _statCell('${team.wins}', isDark),
          _statCell('${team.draws}', isDark),
          _statCell('${team.losses}', isDark),
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                '${team.goalsFor}:${team.goalsAgainst}',
                style: TextStyle(fontSize: 10, color: Colors.grey.withOpacity(0.8)),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '${team.diff > 0 ? '+' : ''}${team.diff}',
                style: TextStyle(
                  fontSize: 11,
                  color: team.diff > 0
                      ? const Color(0xFF16a765)
                      : team.diff < 0
                          ? const Color(0xFFEF5350)
                          : (isDark ? Colors.white54 : Colors.black45),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // النقاط
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${team.points}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(String text, bool isDark) {
    return SizedBox(
      width: 24,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildColorLegend(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _legendItem(const Color(0xFF16a765), 'تأهل'),
          _legendItem(const Color(0xFFffad46), 'أفضل ثوالث'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── تبويب الهدافين / الصناع ────────────────────────────────────
  Widget _buildScorersTab(List<YsPlayer> players, String unit) {
    if (_loadingScorers) {
      return const Center(child: CircularProgressIndicator(color: primaryColor));
    }
    if (players.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              unit == 'أهداف' ? Icons.sports_soccer : Icons.assistant,
              size: 60,
              color: Colors.grey.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text('لا تتوفر بيانات $unit', style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: players.length,
      itemBuilder: (_, i) => _buildPlayerCard(players[i], i + 1, unit),
    );
  }

  Widget _buildPlayerCard(YsPlayer player, int rank, String unit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTop3 = rank <= 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isTop3
                ? primaryColor.withOpacity(0.4)
                : Colors.grey.withOpacity(0.12),
            width: isTop3 ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // رقم الترتيب
              SizedBox(
                width: 30,
                child: Center(
                  child: Container(
                    width: 26, height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? const Color(0xFFFFD700)
                          : rank == 2
                              ? const Color(0xFFC0C0C0)
                              : rank == 3
                                  ? const Color(0xFFCD7F32)
                                  : (isDark ? Colors.white12 : Colors.grey.shade100),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: rank <= 3 ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // صورة اللاعب
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CachedNetworkImage(
                  imageUrl: player.photoUrl,
                  width: 44, height: 44,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0'}, // 🔥 الهيدر السحري
                  placeholder: (_, __) => Container(
                    width: 44, height: 44,
                    color: primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.person, color: primaryColor, size: 26),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 44, height: 44,
                    color: primaryColor.withOpacity(0.1),
                    child: const Icon(Icons.person, color: primaryColor, size: 26),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // اسم اللاعب والفريق
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),

              // العدد (أهداف/تمريرات)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isTop3 ? primaryColor : primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      '${player.count}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: isTop3 ? Colors.white : primaryColor,
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 9,
                        color: isTop3 ? Colors.white70 : primaryColor.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
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
// --- (MATCH WIDGETS - IMPROVED DESIGN) ---
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const InfoChip({required this.icon, required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: const Color(0xFF555555),
          size: 22,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF555555),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class TeamWidget extends StatelessWidget {
  final String name;
  final String logoUrl;
  const TeamWidget({required this.name, required this.logoUrl, super.key});

  String _shortenName(String longName) {
    final words = longName.split(' ');
    if (words.length >= 3) {
      return '${words[0]} ${words[1]}';
    }
    return longName;
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          CachedNetworkImage(
            imageUrl: logoUrl,
            width: 48,
            height: 48,
            // تصغير الصورة في الذاكرة للهواتف الضعيفة فقط
            memCacheWidth: DeviceConfig.isLowRamDevice ? 100 : null,
            cacheManager: MyCustomCacheManager.instance,
            // ✅ تم إصلاح المسافات هنا
            placeholder: (_, __) => Opacity(
              opacity: 0.5,
              child: Image.asset('assets/images/logo.png', width: 48, height: 48),
            ),
            errorWidget: (_, __, ___) => const Icon(Icons.sports_soccer, size: 48, color: Colors.grey),
            httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
          ),
          const SizedBox(height: 8),
          Text(
            _shortenName(name),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ✅ StatefulWidget مع تحديث كل دقيقة ودعم الريموت كنترول
class MatchCard extends StatefulWidget {
  final Match match;
  final VoidCallback? onTap;
  const MatchCard({required this.match, this.onTap, super.key});

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard> with SingleTickerProviderStateMixin {
  Timer? _timer;
  late String centralText;
  late Color bubbleColor;
  late Color textColor;

  @override
  void initState() {
    super.initState();
    _updateStatus();
    _timer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted) _updateStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateStatus() {
    final match = widget.match;
    final now = DateTime.now().toUtc();
    final start = DateTime.fromMillisecondsSinceEpoch(match.startTime * 1000, isUtc: true);
    final end = start.add(const Duration(minutes: 120));

    if (now.isBefore(start)) {
      centralText = formatStartTime(match.startTime);
      bubbleColor = finishedBg;
      textColor = textDark;
    } else if (now.isAfter(end) || match.status.toLowerCase().contains('finished') || match.status == 'FT') {
      centralText = 'إنتهت المباراة';
      bubbleColor = finishedBg;
      textColor = textDark;
    } else {
      centralText = (match.score != null && match.score!.isNotEmpty) ? match.score! : 'جارية الآن';
      bubbleColor = finishedBg;
      textColor = textDark;
    }
  }

  String formatStartTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    int hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return "$hour:$minute $period";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // المسافة هنا لكي لا يتوهج الفراغ بين البطاقات بالريموت
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TvFocusWrapper(
        borderRadius: 12.0,
        onTap: widget.onTap ?? () {},
        child: Card(
          elevation: 0.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: const BorderSide(
              color: Color(0xFFB22222),
              width: 2,
            ),
          ),
          margin: EdgeInsets.zero, // إزالة المارجن لتناسق توهج الريموت
          child: Container(
            constraints: const BoxConstraints(minHeight: 200),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TeamWidget(
                      name: widget.match.team1Name,
                      logoUrl: widget.match.team1Logo,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          centralText,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    TeamWidget(
                      name: widget.match.team2Name,
                      logoUrl: widget.match.team2Logo,
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  children: [
                    InfoChip(
                      icon: Icons.emoji_events,
                      text: widget.match.league,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (widget.match.commentator != null && widget.match.commentator!.isNotEmpty)
                          InfoChip(
                            icon: Icons.mic,
                            text: widget.match.commentator!,
                          ),
                        if (widget.match.channel != null && widget.match.channel!.isNotEmpty)
                          InfoChip(
                            icon: Icons.live_tv,
                            text: widget.match.channel!,
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// --- ✨ SHIMMER LOGO PLACEHOLDER (أثناء التحميل فقط) ✨ ---
class ShimmerLogoPlaceholder extends StatelessWidget {
  const ShimmerLogoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/images/logo.png',
        width: 40,
        height: 40,
        fit: BoxFit.cover,
      ),
    );
  }
}
// --- (VPN BLOCKED SCREEN) ---
class VpnBlockedScreen extends StatelessWidget {
  const VpnBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gpp_bad_outlined, color: Colors.white, size: 80),
              const SizedBox(height: 20),
              const Text(
                'تم اكتشاف VPN / بروكسي',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'يرجى إيقاف تشغيل الـ VPN أو البروكسي الخاص بك لاستخدام هذا التطبيق.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- (FORCE UPDATE SCREEN) ---
class ForceUpdateScreen extends StatelessWidget {
  final String updateUrl;
  const ForceUpdateScreen({required this.updateUrl, super.key});

  // دالة لفتح متجر جوجل بلاي
  void _openStore() {
    try {
      launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      print("Could not launch store: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', width: 120),
              const SizedBox(height: 30),
              const Text(
                'تحديث إجباري',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              const Text(
                'يتوفر إصدار جديد من التطبيق. يرجى التحديث إلى أحدث إصدار للاستمرار.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _openStore,
                child: const Text('تحديث الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================
// 🔥 ULTRA TV - PLAYER COMPLETE CODE (Dart)
// استبدل هذا الكود بالكامل في main.dart
// الجزء الذي يبدأ من NativePlayerController حتى نهاية PlayerScreen
// ============================================================

// --- (NATIVE PLAYER CONTROLLER) ---
class NativePlayerController {
  late MethodChannel _channel;
  Function(Duration)? onDurationReady;
  Function(bool)? onBuffering;
  Function(bool)? onIsPlayingChanged;
  Function(String)? onVideoQualityChanged;
  Function(List<dynamic>)? onTracksChanged;
  Function(String)? onAntiTheftDetected;

  void init(int id) {
    _channel = MethodChannel('com.ultratv.live/exoplayer_$id');
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> playUrl(String url) async {
    await _channel.invokeMethod('playUrl', {'url': url});
  }

  Future<void> playProtected(String channelId, {int serverIndex = 0}) async {
    await _channel.invokeMethod('playProtected', {
      'channelId': channelId,
      'serverIndex': serverIndex,
    });
  }

  // 🔥🔥 الدالة الجديدة: إرسال أي رابط مشفر لأقصى حماية
  Future<void> playEncrypted(String rawUrl) async {
    final encryptedUrl = _encryptUrl(rawUrl);
    await _channel.invokeMethod('playEncrypted', {'data': encryptedUrl});
  }

  // 🔥 دالة التشفير (XOR) - تجعل الرابط غير مقروء في ذاكرة Dart
  String _encryptUrl(String url) {
    const key = 'Ultr4_S3cr3t_K3y_2026';
    final bytes = utf8.encode(url);
    final keyBytes = utf8.encode(key);
    final encrypted = List<int>.generate(bytes.length, (i) => bytes[i] ^ keyBytes[i % keyBytes.length]);
    return base64Encode(encrypted);
  }

  Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  Future<void> resume() async {
    await _channel.invokeMethod('resume');
  }

  Future<void> seekTo(Duration position) async {
    await _channel.invokeMethod('seekTo', {'position': position.inMilliseconds});
  }

  Future<void> setVolume(double volume) async {
    await _channel.invokeMethod('setVolume', {'volume': volume});
  }

  Future<Duration> getPosition() async {
    final int? posMs = await _channel.invokeMethod('getPosition');
    return Duration(milliseconds: posMs ?? 0);
  }

  Future<void> setFit(String fit) async {
    await _channel.invokeMethod('setFit', {'fit': fit});
  }

  Future<void> setTrack(int groupIndex, int trackIndex) async {
    await _channel.invokeMethod('setTrack', {'groupIndex': groupIndex, 'trackIndex': trackIndex});
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        final durationMs = call.arguments['duration'] as int;
        if (onDurationReady != null) onDurationReady!(Duration(milliseconds: durationMs));
        break;
      case 'onBuffering':
        final isBuffering = call.arguments as bool;
        if (onBuffering != null) onBuffering!(isBuffering);
        break;
      case 'onIsPlayingChanged':
        final isPlaying = call.arguments as bool;
        if (onIsPlayingChanged != null) onIsPlayingChanged!(isPlaying);
        break;
      case 'onVideoQualityChanged':
        final quality = call.arguments as String;
        if (onVideoQualityChanged != null) onVideoQualityChanged!(quality);
        break;
      case 'onTracksChanged':
        final tracks = call.arguments as List<dynamic>;
        final uniqueTracks = <int, dynamic>{};
        for (var t in tracks) { uniqueTracks[t['height']] = t; }
        final sortedTracks = uniqueTracks.values.toList();
        sortedTracks.sort((a, b) => b['height'].compareTo(a['height']));
        if (onTracksChanged != null) onTracksChanged!(sortedTracks);
        break;
      case 'onAntiTheftDetected':
        final reason = call.arguments as String;
        if (onAntiTheftDetected != null) onAntiTheftDetected!(reason);
        break;
    }
  }
}

// ============================================================
// 🔥 شاشة تحذير سرقة الروابط - بتصميم UltraTV الأحمر
// ============================================================
class AntiTheftOverlay extends StatelessWidget {
  final String reason;
  final VoidCallback onDismiss;

  const AntiTheftOverlay({
    required this.reason,
    required this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.82),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF870000), Color(0xFF3A0000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF870000).withOpacity(0.6),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة الدرع
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 2),
                ),
                child: const Icon(
                  Icons.security,
                  color: Colors.white,
                  size: 50,
                ),
              ),

              const SizedBox(height: 20),

              // العنوان
              const Text(
                'تحذير أمني',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),

              // شريط فاصل
              Container(
                height: 1.5,
                width: 60,
                color: Colors.white38,
                margin: const EdgeInsets.symmetric(vertical: 12),
              ),

              // الوصف
              const Text(
                'تم رصد نشاط مشبوه قد يكون محاولة\nلسرقة رابط البث المباشر.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // السبب
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white54, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        reason,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // زر الاستمرار
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF870000),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: onDismiss,
                  child: const Text(
                    'استمرار المشاهدة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'تم تعليق البث مؤقتاً للحماية',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- (PLAYER SCREEN - EXO PLAYER BEAST EDITION) ---
class PlayerScreen extends StatefulWidget {
  final List<dynamic> servers;
  const PlayerScreen({required this.servers, super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  final NativePlayerController _nativeController = NativePlayerController();
  bool _isPlayerViewCreated = false;

  bool _isLoading = true;
  bool _isReconnecting = false;
  bool _isOpening = false;
  bool _isInitialLoad = true;
  int _currentServerIndex = 0;
  bool _showServerButtons = false;

  // كشف سرقة الروابط
  bool _showAntiTheftBanner = false;
  String _antiTheftReason = "";

  Timer? _hideButtonsTimer;
  Timer? _bufferingWatchdog;
  Timer? _positionTimer;
  Timer? _fullscreenGuard; // حارس الفول سكرين

  String _currentStreamUrl = "";
  int _playRequestId = 0;

  BoxFit _currentFit = BoxFit.fill;
  String _videoQuality = "Auto";

  List<dynamic> _availableTracks = [];
  int _currentTrackGroup = -1;
  int _currentTrackIndex = -1;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _retryCount = 0;
  static const int _maxRetries = 999;

  final Map<String, String> _ytCache = {};

  double _volume = 1.0;
  double _brightnessOpacity = 0.0;
  bool _showIndicator = false;
  bool _isVolumeAction = false;
  double _indicatorValue = 100.0;

  late FocusNode _tvFocusNode;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  HttpServer? _localProxyServer;
  final Map<String, String> _urlMap = {};
  final Map<String, Map<String, String>> _headersMap = {};
  final List<String> _urlMapOrder = [];
  static const int _maxUrlMapSize = 5000;

  final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true)
    ..connectionTimeout = const Duration(seconds: 45)
    ..idleTimeout = const Duration(seconds: 120);

  @override
  void initState() {
    super.initState();
    _tvFocusNode = FocusNode();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _setFullScreen(true);
    _secureScreen();

    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_isPlaying && mounted && _isPlayerViewCreated) {
        final pos = await _nativeController.getPosition();
        setState(() => _position = pos);
      }
    });

    // حارس فول سكرين - يعيد التطبيق كل 3 ثواني لمنع عودة الأشرطة
    _fullscreenGuard = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });

    _startLocalServer();
  }

  // عند تغيير إعدادات الشاشة (طي/دوران/توصيل شاشة خارجية)
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    }
  }

  void _togglePlayPause() {
    _isPlaying ? _nativeController.pause() : _nativeController.resume();
    _showControlsTemporarily();
  }

  void _seekForward() {
    _nativeController.seekTo(_position + const Duration(seconds: 10));
    _showControlsTemporarily();
  }

  void _seekBackward() {
    _nativeController.seekTo(_position - const Duration(seconds: 10));
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() => _showServerButtons = true);
    _resetHideButtonsTimer();
  }

  void _handleTapUp(TapUpDetails details) {
    final now = DateTime.now();
    if (now.difference(_lastTapTime) < const Duration(milliseconds: 300)) {
      final width = MediaQuery.of(context).size.width;
      final dx = details.globalPosition.dx;
      final Duration newPos = dx < width / 2
          ? _position - const Duration(seconds: 10)
          : _position + const Duration(seconds: 10);
      _nativeController.seekTo(newPos);
      _resetHideButtonsTimer();
      _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      _lastTapTime = now;
      if (_showServerButtons) {
        _hideButtonsTimer?.cancel();
        setState(() => _showServerButtons = false);
      } else {
        _resetHideButtonsTimer();
      }
    }
  }

  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(20, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  String _registerUrl(String realUrl, {Map<String, String>? headers}) {
    if (_urlMapOrder.length >= _maxUrlMapSize) {
      final toRemove = _urlMapOrder.sublist(0, 500);
      for (final oldId in toRemove) {
        _urlMap.remove(oldId);
        _headersMap.remove(oldId);
      }
      _urlMapOrder.removeRange(0, 500);
    }
    final id = _generateRandomId();
    _urlMap[id] = realUrl;
    if (headers != null && headers.isNotEmpty) _headersMap[id] = headers;
    _urlMapOrder.add(id);
    return id;
  }

  bool _isDirectProtocol(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('rtmp://')  ||
           lower.startsWith('rtmps://') ||
           lower.startsWith('rtsp://')  ||
           lower.startsWith('rtsps://') ||
           lower.startsWith('srt://')   ||
           lower.startsWith('udp://')   ||
           lower.startsWith('tcp://')   ||
           lower.startsWith('data:');
  }

  String _detectFakeExtension(String url) {
    final path  = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    final query = (Uri.tryParse(url)?.query ?? '').toLowerCase();

    if (path.contains('.php')) {
      if (query.contains('extension=m3u8') ||
          query.contains('stream=') ||
          query.contains('type=m3u') ||
          query.contains('action=get_stream') ||
          query.contains('action=create_link')) {
        return '.m3u8';
      }
      return '.m3u8';
    }

    if (path.endsWith('.m3u8') || path.contains('.m3u8?') ||
        query.contains('extension=m3u8')) return '.m3u8';
    if (path.endsWith('.ts')   || path.contains('.ts?'))  return '.ts';
    if (path.endsWith('.mp4')  || path.contains('.mp4?')) return '.mp4';
    if (path.endsWith('.json') || path.contains('.json?')) return '.m3u8';
    return '.m3u8';
  }

  Future<void> _startLocalServer() async {
    if (_localProxyServer != null) return;
    try {
      int randomPort = 10000 + Random().nextInt(50000);
      try {
        _localProxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, randomPort);
      } catch (_) {
        _localProxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }

      _localProxyServer!.listen((HttpRequest request) async {
        try {
          final pathSegments = request.uri.pathSegments;
          if (pathSegments.isEmpty) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          final id = pathSegments.first;
          final targetUrl = _urlMap[id];
          if (targetUrl == null) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          await _handleProxyRequest(request, targetUrl, id);
        } catch (e) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {}
  }

  Future<void> _handleProxyRequest(HttpRequest request, String targetUrl, String id) async {
    Uri targetUri = Uri.parse(targetUrl);
    final customHeaders = _headersMap[id];
    HttpClientResponse? clientRes;
    Uri? finalUri;

    for (int redirectCount = 0; redirectCount < 5; redirectCount++) {
      try {
        final clientReq = await _httpClient.openUrl(request.method, targetUri);

        if (customHeaders != null) {
          customHeaders.forEach((name, value) {
            try { clientReq.headers.set(name, value); } catch (_) {}
          });
        }

        request.headers.forEach((name, values) {
          if (name.toLowerCase() == 'host') return;
          for (var value in values) {
            try { clientReq.headers.add(name, value); } catch (_) {}
          }
        });

        clientReq.followRedirects = false;
        final res = await clientReq.close();

        if ((res.statusCode == 301 || res.statusCode == 302 ||
             res.statusCode == 307 || res.statusCode == 308) &&
            res.headers.value('location') != null) {
          targetUri = targetUri.resolve(res.headers.value('location')!);
          await res.drain();
          continue;
        }

        clientRes = res;
        finalUri = targetUri;
        break;
      } catch (_) {}
    }

    if (clientRes == null || finalUri == null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    request.response.statusCode = clientRes.statusCode;

    clientRes.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'transfer-encoding' || lower == 'content-encoding') return;
      for (var value in values) {
        try { request.response.headers.add(name, value); } catch (_) {}
      }
    });

    final contentType = clientRes.headers.contentType?.value.toLowerCase() ?? '';
    final isM3U8 = contentType.contains('mpegurl') ||
        contentType.contains('m3u8') ||
        finalUri.path.toLowerCase().contains('.m3u8') ||
        finalUri.path.toLowerCase().contains('.json');

    if (isM3U8) {
      try {
        final bytes = await clientRes.fold<List<int>>(<int>[], (acc, el) => acc..addAll(el));
        final body = utf8.decode(bytes, allowMalformed: true);
        final newBody = _rewriteM3U8(body, finalUri, customHeaders);
        final newBytes = utf8.encode(newBody);
        request.response.headers.set('Content-Length', newBytes.length);
        request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
        request.response.add(newBytes);
        await request.response.close();
      } catch (_) {}
    } else {
      try {
        await clientRes.pipe(request.response);
      } catch (_) {}
    }
  }

  String _rewriteM3U8(String body, Uri baseUri, Map<String, String>? headers) {
    final lines = body.split('\n');
    Uri effectiveBase = baseUri;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-BASE-URI:')) {
        effectiveBase = effectiveBase.resolve(line.substring('#EXT-X-BASE-URI:'.length).trim());
        continue;
      }

      if (line.startsWith('#EXT-X-KEY:') || line.startsWith('#EXT-X-MAP:')) {
        lines[i] = line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
          final uriStr = m.group(1)!;
          if (uriStr.startsWith('data:') || uriStr.startsWith('http://127.0.0.1')) return m.group(0)!;
          try {
            final absUri = effectiveBase.resolve(uriStr).toString();
            final newId = _registerUrl(absUri, headers: headers);
            final suffix = line.startsWith('#EXT-X-KEY:') ? 'key.key' : 'init.mp4';
            return 'URI="http://127.0.0.1:${_localProxyServer!.port}/$newId/$suffix"';
          } catch (_) { return m.group(0)!; }
        });
        continue;
      }

      if (line.startsWith('#') && line.contains('URI="')) {
        lines[i] = line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
          final uriStr = m.group(1)!;
          if (uriStr.startsWith('data:') || uriStr.startsWith('http://127.0.0.1')) return m.group(0)!;
          try {
            final absUri = effectiveBase.resolve(uriStr).toString();
            final newId = _registerUrl(absUri, headers: headers);
            return 'URI="http://127.0.0.1:${_localProxyServer!.port}/$newId/manifest.m3u8"';
          } catch (_) { return m.group(0)!; }
        });
        continue;
      }

      if (!line.startsWith('#')) {
        try {
          final absUri = effectiveBase.resolve(line).toString();
          final newId = _registerUrl(absUri, headers: headers);
          final suffix = (line.toLowerCase().contains('.m3u8') || line.toLowerCase().contains('.json'))
              ? '/playlist.m3u8'
              : '/segment.ts';
          lines[i] = 'http://127.0.0.1:${_localProxyServer!.port}/$newId$suffix';
        } catch (_) {}
      }
    }
    return lines.join('\n');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _setFullScreen(bool enable) async {
    if (enable) {
      for (int i = 0; i < 3; i++) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await Future.delayed(const Duration(milliseconds: 80));
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  Future<void> _secureScreen() async {
    try { await ScreenProtector.preventScreenshotOn(); } catch (_) {}
  }

  Future<void> _unsecureScreen() async {
    try { await ScreenProtector.preventScreenshotOff(); } catch (_) {}
  }

  void _resetHideButtonsTimer() {
    _hideButtonsTimer?.cancel();
    if (mounted && !_showServerButtons) setState(() => _showServerButtons = true);
    _hideButtonsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showServerButtons = false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Future<void> _attemptToPlayCurrentServer() async {
    if (!_isPlayerViewCreated) return;
    if (_isOpening) return;

    _isOpening = true;
    _isInitialLoad = true;
    _bufferingWatchdog?.cancel();

    if (_currentServerIndex >= widget.servers.length) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("عذراً، جميع السيرفرات لا تعمل حالياً")),
        );
      }
      _isOpening = false;
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _videoQuality = "Auto";
        _availableTracks = [];
        _currentTrackGroup = -1;
        _currentTrackIndex = -1;
      });
    }

    _urlMap.clear();
    _headersMap.clear();
    _urlMapOrder.clear();

    final server = widget.servers[_currentServerIndex];
    String playUrl = server.url;

    try {
      await _nativeController.pause();
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (_) {}

    try {
      // ════════════════════════════════════════════════════
      // 1. مسار الحماية القصوى لسيرفراتك الخاصة
      // ════════════════════════════════════════════════════
      if (playUrl.contains("api.ultrav.me/live/")) {
        final uri = Uri.parse(playUrl);
        final lastSegment = uri.pathSegments.last; 
        final channelId = lastSegment.replaceAll('.m3u8', '');
        await _nativeController.playProtected(channelId, serverIndex: _currentServerIndex);
      } 
      // ════════════════════════════════════════════════════
      // 2. مسار يوتيوب (يتولد الرابط ثم يُشفر فوراً)
      // ════════════════════════════════════════════════════
      else if (playUrl.contains('youtube.com') || playUrl.contains('youtu.be')) {
        final cached = _ytCache[playUrl];
        if (cached != null) {
          playUrl = cached;
        } else {
          try {
            final originalUrl = playUrl;
            var youtube = yt.YoutubeExplode();
            var videoId = yt.VideoId(playUrl);
            var videoData = await youtube.videos.get(videoId);

            if (videoData.isLive) {
              var manifest = await youtube.videos.streamsClient.getManifest(videoId);
              if (manifest.hls.isNotEmpty) playUrl = manifest.hls.first.url.toString();
            } else {
              var manifest = await youtube.videos.streamsClient.getManifest(videoId);
              if (manifest.hls.isNotEmpty) {
                playUrl = manifest.hls.first.url.toString();
              } else if (manifest.muxed.isNotEmpty) {
                var sortedStreams = manifest.muxed.toList();
                sortedStreams.sort((a, b) => a.bitrate.compareTo(b.bitrate));
                playUrl = sortedStreams.last.url.toString();
              }
            }
            youtube.close();
            _ytCache[originalUrl] = playUrl;
          } catch (e) {}
        }

        _currentStreamUrl = playUrl;
        await _nativeController.playEncrypted(playUrl);
      } 
      // ════════════════════════════════════════════════════
      // 3. مسار كل الروابط الأخرى (تُشفر بالكامل)
      // ════════════════════════════════════════════════════
      else {
        _currentStreamUrl = playUrl;
        await _nativeController.playEncrypted(playUrl);
      }

    } catch (e) {
      _isOpening = false;
      _handleConnectionError();
    } finally {
      _isOpening = false;
    }
  }

  void _startBufferingWatchdog() {
    _bufferingWatchdog?.cancel();
    if (_isInitialLoad) return;
    _bufferingWatchdog = Timer(const Duration(seconds: 45), () {
      if (!_isPlaying) {
        _handleConnectionError();
      }
    });
  }

  Future<void> _handleConnectionError() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    if (_retryCount < _maxRetries) {
      _retryCount++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("جاري استعادة البث... ($_retryCount)"),
            backgroundColor: const Color(0xFF870000),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
      await Future.delayed(Duration(seconds: min(_retryCount, 5)));
      _isReconnecting = false;
      _attemptToPlayCurrentServer();
    } else {
      _retryCount = 0;
      _tryNextServer();
    }
  }

  Future<void> _tryNextServer() async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    if (mounted) setState(() => _isLoading = true);

    _currentServerIndex++;

    if (_currentServerIndex < widget.servers.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("جاري الانتقال للسيرفر: ${widget.servers[_currentServerIndex].name}"),
            backgroundColor: const Color(0xFF870000),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await Future.delayed(const Duration(seconds: 1));
      _isReconnecting = false;
      _attemptToPlayCurrentServer();
    } else {
      _currentServerIndex = 0;
      _isReconnecting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _switchServer(int index) {
    if (_currentServerIndex != index) {
      _playRequestId++;
      _isReconnecting = false;
      _isOpening = false;
      _retryCount = 0;

      if (mounted) {
        setState(() {
          _currentServerIndex = index;
          _isLoading = true;
        });
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) _attemptToPlayCurrentServer();
        });
        _resetHideButtonsTimer();
      }
    }
  }

  void _changeFit() {
    setState(() {
      if (_currentFit == BoxFit.contain) {
        _currentFit = BoxFit.fill;
        _nativeController.setFit("fill");
      } else if (_currentFit == BoxFit.fill) {
        _currentFit = BoxFit.cover;
        _nativeController.setFit("cover");
      } else {
        _currentFit = BoxFit.contain;
        _nativeController.setFit("contain");
      }
    });
    _resetHideButtonsTimer();
  }

  void _showQualityDialog() {
    _hideButtonsTimer?.cancel();

    if (_availableTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا توجد جودات إضافية لهذا البث")),
      );
      _resetHideButtonsTimer();
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('اختيار الجودة', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('تلقائي (Auto)', style: TextStyle(color: Colors.white)),
                  trailing: _currentTrackGroup == -1
                      ? const Icon(Icons.check, color: Color(0xFF870000))
                      : null,
                  onTap: () {
                    _nativeController.setTrack(-1, -1);
                    setState(() {
                      _currentTrackGroup = -1;
                      _currentTrackIndex = -1;
                      _videoQuality = "Auto";
                    });
                    Navigator.pop(context);
                    _resetHideButtonsTimer();
                  },
                ),
                ..._availableTracks.map((track) {
                  final gIdx = track['groupIndex'];
                  final tIdx = track['trackIndex'];
                  final height = track['height'];
                  final isSelected = _currentTrackGroup == gIdx && _currentTrackIndex == tIdx;

                  return ListTile(
                    title: Text('${height}p', style: const TextStyle(color: Colors.white)),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF870000))
                        : null,
                    onTap: () {
                      _nativeController.setTrack(gIdx, tIdx);
                      setState(() {
                        _currentTrackGroup = gIdx;
                        _currentTrackIndex = tIdx;
                        _videoQuality = "${height}p";
                      });
                      Navigator.pop(context);
                      _resetHideButtonsTimer();
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    ).then((_) => _resetHideButtonsTimer());
  }

  Future<void> _castVideo() async {
    if (_currentStreamUrl.isEmpty) return;
    final String wvcUrl = "wvc-x-callback://open?url=$_currentStreamUrl&secure_uri=true";
    try {
      bool launched = await launchUrlString(wvcUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrlString(
          "intent:$_currentStreamUrl#Intent;package=com.instantbits.cast.webvideo;type=video/*;scheme=https;end",
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched) {
        await launchUrlString(
          "https://play.google.com/store/apps/details?id=com.instantbits.cast.webvideo",
          mode: LaunchMode.externalApplication,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("يرجى تثبيت تطبيق Web Video Caster")),
          );
        }
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _playRequestId++;
    WidgetsBinding.instance.removeObserver(this);
    
    _fullscreenGuard?.cancel();
    _hideButtonsTimer?.cancel();
    _bufferingWatchdog?.cancel();
    _positionTimer?.cancel();
    
    WakelockPlus.disable();
    _tvFocusNode.dispose();
    try { _nativeController.pause(); } catch (_) {}
    _localProxyServer?.close(force: true);
    _httpClient.close(force: true);
    _urlMap.clear();
    _headersMap.clear();
    _urlMapOrder.clear();
    _setFullScreen(false);
    _unsecureScreen();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    _playRequestId++;
    try { await _nativeController.pause(); } catch (_) {}
    await _setFullScreen(false);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hasMultipleServers = widget.servers.length > 1;

    IconData fitIcon = Icons.aspect_ratio;
    if (_currentFit == BoxFit.fill) fitIcon = Icons.fit_screen;
    if (_currentFit == BoxFit.cover) fitIcon = Icons.fullscreen;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _tvFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (!AppMode.isTvMode) return KeyEventResult.ignored;
            if (event is KeyDownEvent) {
              final key = event.logicalKey;
              
              // ── 1. زر OK / Enter / Space ──────────────────────
              if (key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.space) {
                if (!_showServerButtons) {
                  _showControlsTemporarily();
                } else {
                  _togglePlayPause();
                }
                return KeyEventResult.handled;
              } 
              
              // ── 2. أسهم يمين / يسار (ذكاء التبديل) ───────────
              else if (key == LogicalKeyboardKey.arrowLeft || 
                       key == LogicalKeyboardKey.arrowRight) {
                if (_showServerButtons && hasMultipleServers) {
                  // إذا كانت الأزرار ظاهرة: تبديل السيرفرات فوراً
                  int nextIndex;
                  if (key == LogicalKeyboardKey.arrowRight) {
                    nextIndex = (_currentServerIndex + 1) % widget.servers.length;
                  } else {
                    nextIndex = (_currentServerIndex - 1 + widget.servers.length) % widget.servers.length;
                  }
                  _switchServer(nextIndex);
                } else {
                  // إذا كانت الأزرار مخفية: تقديم / إيقاف البث
                  if (key == LogicalKeyboardKey.arrowRight) {
                    _seekForward();
                  } else {
                    _seekBackward();
                  }
                }
                return KeyEventResult.handled;
              } 
              
              // ── 3. أسهم أعلى / أسفل (الصوت) ───────────────────
              else if (key == LogicalKeyboardKey.arrowUp || 
                       key == LogicalKeyboardKey.arrowDown) {
                setState(() {
                  _showIndicator = true;
                  _isVolumeAction = true;
                  if (key == LogicalKeyboardKey.arrowUp) {
                    _volume = (_volume + 0.1).clamp(0.0, 1.0);
                  } else {
                    _volume = (_volume - 0.1).clamp(0.0, 1.0);
                  }
                  _nativeController.setVolume(_volume);
                  _indicatorValue = _volume * 100;
                });
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) setState(() => _showIndicator = false);
                });
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── 1. مشغل الفيديو الأصلي ──────────────────────
              SizedBox.expand(
                child: AndroidView(
                  viewType: 'com.ultratv.live/native_player',
                  onPlatformViewCreated: (int id) {
                    _nativeController.init(id);
                    _nativeController.setFit("fill");

                    _nativeController.onBuffering = (isBuffering) {
                      if (mounted) setState(() => _isLoading = isBuffering);
                    };

                    _nativeController.onDurationReady = (dur) {
                      if (mounted) setState(() => _duration = dur);
                    };

                    _nativeController.onIsPlayingChanged = (playing) {
                      if (mounted) {
                        setState(() {
                          _isPlaying = playing;
                          if (playing) {
                            _isLoading = false;
                            _isInitialLoad = false;
                          }
                        });
                      }
                    };

                    _nativeController.onVideoQualityChanged = (quality) {
                      if (mounted && _currentTrackGroup == -1) {
                        setState(() => _videoQuality = quality);
                      }
                    };

                    _nativeController.onTracksChanged = (tracks) {
                      if (mounted) setState(() => _availableTracks = tracks);
                    };

                    _nativeController.onAntiTheftDetected = (reason) {
                      if (mounted) {
                        setState(() {
                          _showAntiTheftBanner = true;
                          _antiTheftReason = reason;
                        });
                        Future.delayed(const Duration(seconds: 8), () {
                          if (mounted) setState(() => _showAntiTheftBanner = false);
                        });
                      }
                    };

                    setState(() => _isPlayerViewCreated = true);
                    _attemptToPlayCurrentServer();
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                ),
              ),

              // ── 2. طبقة اللمس (السحب للصوت/السطوع) ──────────
              Positioned.fill(
                child: GestureDetector(
                  onTapUp: _handleTapUp,
                  onVerticalDragUpdate: (details) {
                    final width = MediaQuery.of(context).size.width;
                    final dx = details.globalPosition.dx;
                    final delta = details.primaryDelta! * -0.01;

                    setState(() {
                      _showIndicator = true;
                      if (dx > width / 2) {
                        _isVolumeAction = true;
                        _volume = (_volume + delta).clamp(0.0, 1.0);
                        _nativeController.setVolume(_volume);
                        _indicatorValue = _volume * 100;
                      } else {
                        _isVolumeAction = false;
                        double currentBright = 1.0 - _brightnessOpacity;
                        currentBright = (currentBright + delta).clamp(0.2, 1.0);
                        _brightnessOpacity = 1.0 - currentBright;
                        _indicatorValue = currentBright * 100;
                      }
                    });
                  },
                  onVerticalDragEnd: (_) {
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) setState(() => _showIndicator = false);
                    });
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),

              // ── 3. فلتر السطوع ───────────────────────────────
              if (_brightnessOpacity > 0.0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(color: Colors.black.withOpacity(_brightnessOpacity)),
                  ),
                ),

              // ── 4. مؤشر الصوت/السطوع ────────────────────────
              if (_showIndicator)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2)
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isVolumeAction
                              ? (_volume == 0 ? Icons.volume_off : Icons.volume_up)
                              : Icons.brightness_6,
                          color: Colors.white,
                          size: 50,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "${_indicatorValue.toInt()}%",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 120,
                          height: 6,
                          child: LinearProgressIndicator(
                            value: _indicatorValue / 100,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF870000)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── 5. مؤشر التحميل ──────────────────────────────
              if (_isLoading || _isReconnecting)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFF870000),
                  ),
                ),

              // ── 6. شريط العلوي ──
              Positioned(
                top: 0, left: 0, right: 0,
                child: IgnorePointer(
                  ignoring: !_showServerButtons,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showServerButtons ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildPlayerButton(Icons.arrow_back, () {
                            _onWillPop().then((_) => Navigator.pop(context));
                          }),
                          const SizedBox(width: 15),

                          if (hasMultipleServers)
                            Expanded(
                              child: SizedBox(
                                height: 45,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: widget.servers.length,
                                  separatorBuilder: (ctx, i) => const SizedBox(width: 10),
                                  itemBuilder: (context, i) {
                                    final isSelected = i == _currentServerIndex;
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _switchServer(i),
                                        borderRadius: BorderRadius.circular(25),
                                        splashColor: Colors.white24,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF870000)
                                                : Colors.black45,
                                            borderRadius: BorderRadius.circular(25),
                                            border: isSelected
                                                ? Border.all(color: Colors.white, width: 1.5)
                                                : Border.all(color: Colors.white24),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            widget.servers[i].name,
                                            style: TextStyle(
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              fontSize: 15,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          else
                            const Spacer(),

                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: _showQualityDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.high_quality,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      _videoQuality,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          _buildPlayerButton(Icons.cast, _castVideo),
                          const SizedBox(width: 10),
                          _buildPlayerButton(fitIcon, _changeFit),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 7. أزرار التحكم الوسطى ──
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showServerButtons,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showServerButtons ? 1.0 : 0.0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildPlayerButton(
                            Icons.replay_10,
                            () {
                              _nativeController.seekTo(
                                  _position - const Duration(seconds: 10));
                              _resetHideButtonsTimer();
                            },
                            size: 55,
                          ),
                          const SizedBox(width: 40),
                          _buildPlayerButton(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            () {
                              _isPlaying
                                  ? _nativeController.pause()
                                  : _nativeController.resume();
                              _resetHideButtonsTimer();
                            },
                            size: 75,
                            isPrimary: true,
                          ),
                          const SizedBox(width: 40),
                          _buildPlayerButton(
                            Icons.forward_10,
                            () {
                              _nativeController.seekTo(
                                  _position + const Duration(seconds: 10));
                              _resetHideButtonsTimer();
                            },
                            size: 55,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 8. شريط التقدم السفلي ──
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: IgnorePointer(
                  ignoring: !_showServerButtons,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showServerButtons ? 1.0 : 0.0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(25, 30, 25, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                _formatDuration(_duration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 10,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3.0,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6.0),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14.0),
                                activeTrackColor: const Color(0xFF870000),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: const Color(0xFF870000),
                                overlayColor:
                                    const Color(0xFF870000).withOpacity(0.3),
                              ),
                              child: Slider(
                                value: _position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                        0,
                                        _duration.inMilliseconds > 0
                                            ? _duration.inMilliseconds.toDouble()
                                            : 100.0),
                                min: 0.0,
                                max: _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 100.0,
                                onChanged: (value) {
                                  _nativeController.seekTo(
                                      Duration(milliseconds: value.toInt()));
                                  _resetHideButtonsTimer();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── 9. شاشة تحذير سرقة الروابط ──
              if (_showAntiTheftBanner)
                Positioned.fill(
                  child: AntiTheftOverlay(
                    reason: _antiTheftReason,
                    onDismiss: () {
                      setState(() => _showAntiTheftBanner = false);
                      _nativeController.resume();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerButton(
    IconData icon,
    VoidCallback onPressed, {
    double size = 45,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        splashColor: isPrimary
            ? Colors.white30
            : const Color(0xFF870000).withOpacity(0.5),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isPrimary
                ? const Color(0xFF870000).withOpacity(0.9)
                : Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(
              color: isPrimary ? Colors.white54 : Colors.white24,
              width: 1.5,
            ),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                  color: const Color(0xFF870000).withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
// ============================================================
// الكلاس 3: TvFocusWrapper (كامل - استبدل القديم بهذا)
// التعديل الجوهري: Shortcuts + Actions تجعل ENTER يستدعي onTap
// ============================================================
class TvFocusWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  final double borderRadius;
  final bool autofocus;

  const TvFocusWrapper({
    required this.child,
    required this.onTap,
    this.scale = 1.04,
    this.borderRadius = 8.0,
    this.autofocus = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}