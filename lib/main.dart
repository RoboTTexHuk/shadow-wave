import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient, ContentType, HttpRequest, HttpServer, InternetAddress, HttpStatus;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as af_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:eholocator/pushLoc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemChrome, SystemUiOverlayStyle, rootBundle, ByteData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as r;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:provider/provider.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;


import 'locator.dart';

// ============================================================================
// Константы (тени)
// ============================================================================
const String shadowConstLoadedOnceKey = "loaded_event_sent_once";
const String shadowConstStatEndpoint = "https://sprt.spiritinmydream.online/stat";
const String shadowConstCachedFcmKey = "cached_fcm_token";

// ============================================================================
// ShadowBarrel — контейнер сервисов
// ============================================================================
class ShadowBarrel {
  static final ShadowBarrel shadowSingleton = ShadowBarrel._shadowCtor();
  ShadowBarrel._shadowCtor();

  factory ShadowBarrel() => shadowSingleton;

  final FlutterSecureStorage shadowSecure = const FlutterSecureStorage();
  final ShadowLog shadowLog = ShadowLog();
  final Connectivity shadowConnectivity = Connectivity();
}

class ShadowLog {
  final Logger shadowLogger = Logger();
  void shadowInfo(Object shadowMsg) => shadowLogger.i(shadowMsg);
  void shadowWarn(Object shadowMsg) => shadowLogger.w(shadowMsg);
  void shadowError(Object shadowMsg) => shadowLogger.e(shadowMsg);
}

// ============================================================================
// ShadowNet — сеть
// ============================================================================
class ShadowNet {
  final ShadowBarrel shadowBarrel = ShadowBarrel();

  Future<bool> shadowIsOnline() async {
    final shadowConn = await shadowBarrel.shadowConnectivity.checkConnectivity();
    return shadowConn != ConnectivityResult.none;
  }

  Future<void> shadowPostJson(String shadowUrl, Map<String, dynamic> shadowBody) async {
    try {
      await http.post(
        Uri.parse(shadowUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(shadowBody),
      );
    } catch (e) {
      shadowBarrel.shadowLog.shadowError("castBottleJson error: $e");
    }
  }
}

// ============================================================================
// ShadowDevice — сведения об устройстве
// ============================================================================
class ShadowDevice {
  String? shadowDeviceId;
  String? shadowSessionId = "mafia-one-off";
  String? shadowPlatform;
  String? shadowOsVersion;
  String? shadowAppVersion;
  String? shadowLanguage;
  String? shadowTimezone;
  bool shadowPushEnabled = true;

  Future<void> shadowCollect() async {
    final shadowInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await shadowInfo.androidInfo;
      shadowDeviceId = a.id;
      shadowPlatform = "android";
      shadowOsVersion = a.version.release;
    } else if (Platform.isIOS) {
      final i = await shadowInfo.iosInfo;
      shadowDeviceId = i.identifierForVendor;
      shadowPlatform = "ios";
      shadowOsVersion = i.systemVersion;
    }
    final info = await PackageInfo.fromPlatform();
    shadowAppVersion = info.version;
    shadowLanguage = Platform.localeName.split('_')[0];
    shadowTimezone = tz_zone.local.name;
    shadowSessionId = "voyage-${DateTime.now().millisecondsSinceEpoch}";
  }

  Map<String, dynamic> shadowAsMap({String? shadowFcm}) => {
    "fcm_token": shadowFcm ?? 'missing_token',
    "device_id": shadowDeviceId ?? 'missing_id',
    "app_name": "shadowwave",
    "instance_id": shadowSessionId ?? 'missing_session',
    "platform": shadowPlatform ?? 'missing_system',
    "os_version": shadowOsVersion ?? 'missing_build',
    "app_version": shadowAppVersion ?? 'missing_app',
    "language": shadowLanguage ?? 'en',
    "timezone": shadowTimezone ?? 'UTC',
    "push_enabled": shadowPushEnabled,
  };
}

// ============================================================================
// ShadowAppsFlyer — интеграция с AppsFlyer
// ============================================================================
class ShadowAppsFlyer with ChangeNotifier {
  af_core.AppsFlyerOptions? shadowAfOptions;
  af_core.AppsflyerSdk? shadowAfSdk;

  String shadowAfUid = "";
  String shadowAfPayload = "";

  void shadowInit(VoidCallback shadowNudge) {
    final shadowCfg = af_core.AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6755884516",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    shadowAfOptions = shadowCfg;
    shadowAfSdk = af_core.AppsflyerSdk(shadowCfg);

    shadowAfSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    shadowAfSdk?.startSDK(
      onSuccess: () => ShadowBarrel().shadowLog.shadowInfo("Consigliere hoisted"),
      onError: (int shadowCode, String shadowMsg) =>
          ShadowBarrel().shadowLog.shadowError("Consigliere storm $shadowCode: $shadowMsg"),
    );
    shadowAfSdk?.onInstallConversionData((shadowLoot) {
      shadowAfPayload = shadowLoot.toString();
      shadowNudge();
      notifyListeners();
    });
    shadowAfSdk?.getAppsFlyerUID().then((shadowVal) {
      shadowAfUid = shadowVal.toString();
      shadowNudge();
      notifyListeners();
    });
  }
}

// ============================================================================
// Riverpod/Provider теневые
// ============================================================================
final shadowDeviceProvider = r.FutureProvider<ShadowDevice>((shadowRef) async {
  final shadowDev = ShadowDevice();
  await shadowDev.shadowCollect();
  return shadowDev;
});

final shadowAppsFlyerProvider = p.ChangeNotifierProvider<ShadowAppsFlyer>(
  create: (_) => ShadowAppsFlyer(),
);

// ============================================================================
// Фоновые сообщения FCM — тень
// ============================================================================
@pragma('vm:entry-point')
Future<void> shadowOnBackgroundMessage(RemoteMessage shadowMsg) async {
  ShadowBarrel().shadowLog.shadowInfo("bg-parrot: ${shadowMsg.messageId}");
  ShadowBarrel().shadowLog.shadowInfo("bg-cargo: ${shadowMsg.data}");
}

// ============================================================================
// ShadowFcmBridge — мост получения токена из нативного канала
// ============================================================================
class ShadowFcmBridge extends ChangeNotifier {
  final ShadowBarrel shadowBarrel = ShadowBarrel();
  String? shadowToken;
  final List<void Function(String)> shadowAwaiters = [];

  String? get shadowGetToken => shadowToken;

  ShadowFcmBridge() {
    const MethodChannel('com.example.fcm/token').setMethodCallHandler((shadowCall) async {
      if (shadowCall.method == 'setToken') {
        final String shadowVal = shadowCall.arguments as String;
        if (shadowVal.isNotEmpty) {
          shadowSetToken(shadowVal);
        }
      }
    });
    shadowRestoreCached();
  }

  Future<void> shadowRestoreCached() async {
    try {
      final shadowPrefs = await SharedPreferences.getInstance();
      final shadowCached = shadowPrefs.getString(shadowConstCachedFcmKey);
      if (shadowCached != null && shadowCached.isNotEmpty) {
        shadowSetToken(shadowCached, shadowNotifyNative: false);
      } else {
        final shadowSec = await shadowBarrel.shadowSecure.read(key: shadowConstCachedFcmKey);
        if (shadowSec != null && shadowSec.isNotEmpty) {
          shadowSetToken(shadowSec, shadowNotifyNative: false);
        }
      }
    } catch (_) {}
  }

  void shadowSetToken(String shadowNew, {bool shadowNotifyNative = true}) async {
    shadowToken = shadowNew;
    try {
      final shadowPrefs = await SharedPreferences.getInstance();
      await shadowPrefs.setString(shadowConstCachedFcmKey, shadowNew);
      await shadowBarrel.shadowSecure.write(key: shadowConstCachedFcmKey, value: shadowNew);
    } catch (_) {}
    for (final shadowCb in List.of(shadowAwaiters)) {
      try {
        shadowCb(shadowNew);
      } catch (e) {
        shadowBarrel.shadowLog.shadowWarn("parrot-waiter error: $e");
      }
    }
    shadowAwaiters.clear();
    notifyListeners();
  }

  Future<void> shadowAwaitToken(Function(String shadowT) shadowOnToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (shadowToken != null && shadowToken!.isNotEmpty) {
        shadowOnToken(shadowToken!);
        return;
      }
      shadowAwaiters.add(shadowOnToken);
    } catch (e) {
      shadowBarrel.shadowLog.shadowError("ParrotBridge awaitFeather: $e");
    }
  }
}

// ============================================================================
// ShadowLoaderWidget — слово "shadow" с тенью на зелёном фоне
// ============================================================================
class ShadowLoaderWidget extends StatelessWidget {
  const ShadowLoaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.green, // зелёный фон
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: Text(
        'shadow',
        style: TextStyle(
          color: Colors.black,
          fontSize: 48,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: [
            Shadow(offset: Offset(2, 2), blurRadius: 4, color: Colors.black.withOpacity(0.4)),
            Shadow(offset: Offset(-2, -2), blurRadius: 6, color: Colors.black.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ShadowSplash — стартовый экран со «слово shadow» лоадером
// ============================================================================
class ShadowSplash extends StatefulWidget {
  const ShadowSplash({Key? key}) : super(key: key);

  @override
  State<ShadowSplash> createState() => ShadowSplashState();
}

class ShadowSplashState extends State<ShadowSplash> {
  final ShadowFcmBridge shadowFcmBridge = ShadowFcmBridge();
  bool shadowOnce = false;
  Timer? shadowFallbackTimer;
  bool shadowCoverMute = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    shadowFcmBridge.shadowAwaitToken((shadowSig) => shadowGo(shadowSig));
    shadowFallbackTimer = Timer(const Duration(seconds: 8), () => shadowGo(''));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => shadowCoverMute = true);
    });
  }

  void shadowGo(String shadowSig) {
    if (shadowOnce) return;
    shadowOnce = true;
    shadowFallbackTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => ShadowHarbor(shadowSignal: shadowSig)),
    );
  }

  @override
  void dispose() {
    shadowFallbackTimer?.cancel();
    shadowFcmBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: const Stack(
        children: [
          Center(child: ShadowLoaderWidget()),
        ],
      ),
    );
  }
}

// ============================================================================
// ShadowBosunViewModel + ShadowCourier — MVVM прослойка
// ============================================================================
class ShadowBosunViewModel with ChangeNotifier {
  final ShadowDevice shadowDevice;
  final ShadowAppsFlyer shadowAf;

  ShadowBosunViewModel({required this.shadowDevice, required this.shadowAf});

  Map<String, dynamic> shadowDevicePayload(String? shadowToken) => shadowDevice.shadowAsMap(shadowFcm: shadowToken);

  Map<String, dynamic> shadowAfPayload(String? shadowToken) => {
    "content": {
      "af_data": shadowAf.shadowAfPayload,
      "af_id": shadowAf.shadowAfUid,
      "fb_app_name": "shadowwave",
      "app_name": "shadowwave",
      "deep": null,
      "bundle_identifier": "com.eholocator.aghuor.eholocator",
      "app_version": "1.0.0",
      "apple_id": "6755884516",
      "fcm_token": shadowToken ?? "no_token",
      "device_id": shadowDevice.shadowDeviceId ?? "no_device",
      "instance_id": shadowDevice.shadowSessionId ?? "no_instance",
      "platform": shadowDevice.shadowPlatform ?? "no_type",
      "os_version": shadowDevice.shadowOsVersion ?? "no_os",
      "app_version": shadowDevice.shadowAppVersion ?? "no_app",
      "language": shadowDevice.shadowLanguage ?? "en",
      "timezone": shadowDevice.shadowTimezone ?? "UTC",
      "push_enabled": shadowDevice.shadowPushEnabled,
      "useruid": shadowAf.shadowAfUid,
    },
  };
}

class ShadowCourier {
  final ShadowBosunViewModel shadowModel;
  final InAppWebViewController Function() shadowGetWeb;

  ShadowCourier({required this.shadowModel, required this.shadowGetWeb});

  Future<void> shadowSaveDeviceToLocalStorage(String? shadowToken) async {
    final shadowMap = shadowModel.shadowDevicePayload(shadowToken);
    await shadowGetWeb().evaluateJavascript(source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(shadowMap)}));
''');
  }

  Future<void> shadowSendRawToWeb(String? shadowToken) async {
    final shadowPayload = shadowModel.shadowAfPayload(shadowToken);
    final shadowJson = jsonEncode(shadowPayload);
    ShadowBarrel().shadowLog.shadowInfo("SendRawData: $shadowJson");
    await shadowGetWeb().evaluateJavascript(source: "sendRawData(${jsonEncode(shadowJson)});");
  }
}

// ============================================================================
// Переходы/статистика — тень
// ============================================================================
Future<String> shadowResolveFinalUrl(String shadowStart, {int shadowMaxHops = 10}) async {
  final shadowClient = HttpClient();

  try {
    var shadowCurrent = Uri.parse(shadowStart);
    for (int shadowI = 0; shadowI < shadowMaxHops; shadowI++) {
      final shadowReq = await shadowClient.getUrl(shadowCurrent);
      shadowReq.followRedirects = false;
      final shadowRes = await shadowReq.close();
      if (shadowRes.isRedirect) {
        final shadowLoc = shadowRes.headers.value(HttpHeaders.locationHeader);
        if (shadowLoc == null || shadowLoc.isEmpty) break;
        final shadowNext = Uri.parse(shadowLoc);
        shadowCurrent = shadowNext.hasScheme ? shadowNext : shadowCurrent.resolveUri(shadowNext);
        continue;
      }
      return shadowCurrent.toString();
    }
    return shadowCurrent.toString();
  } catch (e) {
    debugPrint("chartFinalUrl error: $e");
    return shadowStart;
  } finally {
    shadowClient.close(force: true);
  }
}

Future<void> shadowPostStat({
  required String shadowEvent,
  required int shadowTimeStart,
  required String shadowUrl,
  required int shadowTimeFinish,
  required String shadowAppSid,
  int? shadowFirstPageTs,
}) async {
  try {
    final shadowFinalUrl = await shadowResolveFinalUrl(shadowUrl);
    final shadowPayload = {
      "event": shadowEvent,
      "timestart": shadowTimeStart,
      "timefinsh": shadowTimeFinish,
      "url": shadowFinalUrl,
      "appleID": "6755884516",
      "open_count": "$shadowAppSid/$shadowTimeStart",
    };

    print("loadingstatinsic $shadowPayload");
    final shadowRes = await http.post(
      Uri.parse("$shadowConstStatEndpoint/$shadowAppSid"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(shadowPayload),
    );
    print(" ur _loaded$shadowConstStatEndpoint/$shadowAppSid");
    debugPrint("_postStat status=${shadowRes.statusCode} body=${shadowRes.body}");
  } catch (e) {
    debugPrint("_postStat error: $e");
  }
}

// ============================================================================
// ShadowHarbor — главный WebView
// ============================================================================
class ShadowHarbor extends StatefulWidget {
  final String? shadowSignal;
  const ShadowHarbor({super.key, required this.shadowSignal});

  @override
  State<ShadowHarbor> createState() => ShadowHarborState();
}

class ShadowHarborState extends State<ShadowHarbor> with WidgetsBindingObserver {
  late InAppWebViewController shadowWebCtrl;
  bool shadowBusy = false;
  final String shadowHome = "https://game.shadowwave.online/";
  final ShadowDevice shadowDevice = ShadowDevice();
  final ShadowAppsFlyer shadowAf = ShadowAppsFlyer();

  int shadowHatch = 0;
  DateTime? shadowSleepAt;
  bool shadowVeil = false;
  double shadowProgress = 0.0;
  late Timer shadowProgressTimer;
  final int shadowWarmSeconds = 6;
  bool shadowCover = true;

  bool shadowLoadedOnceSent = false;
  int? shadowFirstPageTs;

  ShadowCourier? shadowCourier;
  ShadowBosunViewModel? shadowBosun;

  String shadowCurrentUrl = "";
  var shadowStartLoadTs = 0;

  final Set<String> shadowSchemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    'fb', 'instagram', 'twitter', 'x',
  };

  final Set<String> shadowExternalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
    'x.com', 'www.x.com',
    'twitter.com', 'www.twitter.com',
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
    'instagram.com', 'www.instagram.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    shadowFirstPageTs = DateTime.now().millisecondsSinceEpoch;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => shadowCover = false);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => shadowVeil = true);
    });

    shadowBoot();
  }

  Future<void> shadowLoadLoadedFlag() async {
    final shadowPrefs = await SharedPreferences.getInstance();
    shadowLoadedOnceSent = shadowPrefs.getBool(shadowConstLoadedOnceKey) ?? false;
  }

  Future<void> shadowSaveLoadedFlag() async {
    final shadowPrefs = await SharedPreferences.getInstance();
    await shadowPrefs.setBool(shadowConstLoadedOnceKey, true);
    shadowLoadedOnceSent = true;
  }

  Future<void> shadowSendLoadedOnce({required String shadowUrl, required int shadowStart}) async {
    if (shadowLoadedOnceSent) {
      print("Loaded already sent, skipping");
      return;
    }
    final shadowNow = DateTime.now().millisecondsSinceEpoch;
    await shadowPostStat(
      shadowEvent: "Loaded",
      shadowTimeStart: shadowStart,
      shadowTimeFinish: shadowNow,
      shadowUrl: shadowUrl,
      shadowAppSid: shadowAf.shadowAfUid,
      shadowFirstPageTs: shadowFirstPageTs,
    );
    await shadowSaveLoadedFlag();
  }

  void shadowBoot() {
    shadowWarmProgress();
    shadowBindFcm();
    shadowAf.shadowInit(() => setState(() {}));
    shadowBindNotificationChannel();
    shadowPrepareDevice();

    Future.delayed(const Duration(seconds: 6), () async {
      await shadowPushDevice();
      await shadowPushAf();
    });
  }

  void shadowBindFcm() {
    FirebaseMessaging.onMessage.listen((shadowMsg) {
      final shadowLink = shadowMsg.data['uri'];
      if (shadowLink != null) {
        shadowNavigate(shadowLink.toString());
      } else {
        shadowResetHome();
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((shadowMsg) {
      final shadowLink = shadowMsg.data['uri'];
      if (shadowLink != null) {
        shadowNavigate(shadowLink.toString());
      } else {
        shadowResetHome();
      }
    });
  }

  void shadowBindNotificationChannel() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((shadowCall) async {
      if (shadowCall.method == "onNotificationTap") {
        final Map<String, dynamic> shadowPayload = Map<String, dynamic>.from(shadowCall.arguments);
        if (shadowPayload["uri"] != null && !shadowPayload["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => luck_captain_deckload(shadowPayload["uri"].toString())),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> shadowPrepareDevice() async {
    try {
      await shadowDevice.shadowCollect();
      await shadowRequestPushPerms();
      shadowBosun = ShadowBosunViewModel(shadowDevice: shadowDevice, shadowAf: shadowAf);
      shadowCourier = ShadowCourier(shadowModel: shadowBosun!, shadowGetWeb: () => shadowWebCtrl);
      await shadowLoadLoadedFlag();
    } catch (e) {
      ShadowBarrel().shadowLog.shadowError("prepare-quartermaster fail: $e");
    }
  }

  Future<void> shadowRequestPushPerms() async {
    FirebaseMessaging shadowFm = FirebaseMessaging.instance;
    await shadowFm.requestPermission(alert: true, badge: true, sound: true);
  }

  void shadowNavigate(String shadowLink) async {
    if (mounted) {
      await shadowWebCtrl.loadUrl(urlRequest: URLRequest(url: WebUri(shadowLink)));
    }
  }

  void shadowResetHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        shadowWebCtrl.loadUrl(urlRequest: URLRequest(url: WebUri(shadowHome)));
      }
    });
  }

  Future<void> shadowPushDevice() async {
    ShadowBarrel().shadowLog.shadowInfo("TOKEN ship ${widget.shadowSignal}");
    if (!mounted) return;
    setState(() => shadowBusy = true);
    try {
      await shadowCourier?.shadowSaveDeviceToLocalStorage(widget.shadowSignal);
    } finally {
      if (mounted) setState(() => shadowBusy = false);
    }
  }

  Future<void> shadowPushAf() async {
    await shadowCourier?.shadowSendRawToWeb(widget.shadowSignal);
  }

  void shadowWarmProgress() {
    int shadowT = 0;
    shadowProgress = 0.0;
    shadowProgressTimer = Timer.periodic(const Duration(milliseconds: 100), (shadowTimer) {
      if (!mounted) return;
      setState(() {
        shadowT++;
        shadowProgress = shadowT / (shadowWarmSeconds * 10);
        if (shadowProgress >= 1.0) {
          shadowProgress = 1.0;
          shadowProgressTimer.cancel();
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState shadowState) {
    if (shadowState == AppLifecycleState.paused) {
      shadowSleepAt = DateTime.now();
    }
    if (shadowState == AppLifecycleState.resumed) {
      if (Platform.isIOS && shadowSleepAt != null) {
        final shadowNow = DateTime.now();
        final shadowDrift = shadowNow.difference(shadowSleepAt!);
        if (shadowDrift > const Duration(minutes: 25)) {
          shadowReboard();
        }
      }
      shadowSleepAt = null;
    }
  }

  void shadowReboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ShadowHarbor(shadowSignal: widget.shadowSignal)),
            (route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    shadowProgressTimer.cancel();
    super.dispose();
  }

  bool shadowLooksLikeBareEmail(Uri shadowUri) {
    final shadowScheme = shadowUri.scheme;
    if (shadowScheme.isNotEmpty) return false;
    final shadowRaw = shadowUri.toString();
    return shadowRaw.contains('@') && !shadowRaw.contains(' ');
  }

  Uri shadowMakeMailto(Uri shadowUri) {
    final shadowFull = shadowUri.toString();
    final shadowParts = shadowFull.split('?');
    final shadowEmail = shadowParts.first;
    final shadowQ =
    shadowParts.length > 1 ? Uri.splitQueryString(shadowParts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: shadowEmail, queryParameters: shadowQ.isEmpty ? null : shadowQ);
  }

  bool shadowIsPlatformish(Uri shadowU) {
    final shadowScheme = shadowU.scheme.toLowerCase();
    if (shadowSchemes.contains(shadowScheme)) return true;

    if (shadowScheme == 'http' || shadowScheme == 'https') {
      final shadowHost = shadowU.host.toLowerCase();
      if (shadowExternalHosts.contains(shadowHost)) return true;
      if (shadowHost.endsWith('t.me')) return true;
      if (shadowHost.endsWith('wa.me')) return true;
      if (shadowHost.endsWith('m.me')) return true;
      if (shadowHost.endsWith('signal.me')) return true;
      if (shadowHost.endsWith('x.com')) return true;
      if (shadowHost.endsWith('twitter.com')) return true;
      if (shadowHost.endsWith('facebook.com')) return true;
      if (shadowHost.endsWith('instagram.com')) return true;
    }
    return false;
  }

  Uri shadowNormalizeToHttp(Uri shadowU) {
    final shadowS = shadowU.scheme.toLowerCase();

    if (shadowS == 'tg' || shadowS == 'telegram') {
      final shadowQ = shadowU.queryParameters;
      final shadowDomain = shadowQ['domain'];
      if (shadowDomain != null && shadowDomain.isNotEmpty) {
        return Uri.https('t.me', '/$shadowDomain', {if (shadowQ['start'] != null) 'start': shadowQ['start']!});
      }
      final shadowPath = shadowU.path.isNotEmpty ? shadowU.path : '';
      return Uri.https('t.me', '/$shadowPath', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if ((shadowS == 'http' || shadowS == 'https') && shadowU.host.toLowerCase().endsWith('t.me')) {
      return shadowU;
    }

    if (shadowS == 'viber') return shadowU;

    if (shadowS == 'whatsapp') {
      final shadowQ = shadowU.queryParameters;
      final shadowPhone = shadowQ['phone'];
      final shadowText = shadowQ['text'];
      if (shadowPhone != null && shadowPhone.isNotEmpty) {
        return Uri.https('wa.me', '/${shadowOnlyDigits(shadowPhone)}', {if (shadowText != null && shadowText.isNotEmpty) 'text': shadowText});
      }
      return Uri.https('wa.me', '/', {if (shadowText != null && shadowText.isNotEmpty) 'text': shadowText});
    }

    if ((shadowS == 'http' || shadowS == 'https') &&
        (shadowU.host.toLowerCase().endsWith('wa.me') || shadowU.host.toLowerCase().endsWith('whatsapp.com'))) {
      return shadowU;
    }

    if (shadowS == 'skype') return shadowU;

    if (shadowS == 'fb-messenger') {
      final shadowPath = shadowU.pathSegments.isNotEmpty ? shadowU.pathSegments.join('/') : '';
      final shadowQ = shadowU.queryParameters;
      final shadowId = shadowQ['id'] ?? shadowQ['user'] ?? shadowPath;
      if (shadowId.isNotEmpty) {
        return Uri.https('m.me', '/$shadowId', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
      }
      return Uri.https('m.me', '/', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if (shadowS == 'sgnl') {
      final shadowQ = shadowU.queryParameters;
      final shadowPhone = shadowQ['phone'];
      final shadowUser = shadowU.queryParameters['username'];
      if (shadowPhone != null && shadowPhone.isNotEmpty) return Uri.https('signal.me', '/#p/${shadowOnlyDigits(shadowPhone)}');
      if (shadowUser != null && shadowUser.isNotEmpty) return Uri.https('signal.me', '/#u/$shadowUser');
      final shadowPath = shadowU.pathSegments.join('/');
      if (shadowPath.isNotEmpty) return Uri.https('signal.me', '/$shadowPath', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
      return shadowU;
    }

    if (shadowS == 'tel') {
      return Uri.parse('tel:${shadowOnlyDigits(shadowU.path)}');
    }

    if (shadowS == 'mailto') return shadowU;

    if (shadowS == 'bnl') {
      final shadowNew = shadowU.path.isNotEmpty ? shadowU.path : '';
      return Uri.https('bnl.com', '/$shadowNew', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if ((shadowS == 'http' || shadowS == 'https')) {
      final shadowHost = shadowU.host.toLowerCase();
      if (shadowHost.endsWith('x.com') ||
          shadowHost.endsWith('twitter.com') ||
          shadowHost.endsWith('facebook.com') ||
          shadowHost.startsWith('m.facebook.com') ||
          shadowHost.endsWith('instagram.com')) {
        return shadowU;
      }
    }

    if (shadowS == 'fb' || shadowS == 'instagram' || shadowS == 'twitter' || shadowS == 'x') {
      return shadowU;
    }

    return shadowU;
  }

  Future<bool> shadowOpenMail(Uri shadowMailto) async {
    final shadowGmail = shadowGmailize(shadowMailto);
    return await shadowOpenWeb(shadowGmail);
  }

  Uri shadowGmailize(Uri shadowM) {
    final shadowQ = shadowM.queryParameters;
    final Map<String, String> shadowParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (shadowM.path.isNotEmpty) 'to': shadowM.path,
      if ((shadowQ['subject'] ?? '').isNotEmpty) 'su': shadowQ['subject']!,
      if ((shadowQ['body'] ?? '').isNotEmpty) 'body': shadowQ['body']!,
      if ((shadowQ['cc'] ?? '').isNotEmpty) 'cc': shadowQ['cc']!,
      if ((shadowQ['bcc'] ?? '').isNotEmpty) 'bcc': shadowQ['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', shadowParams);
  }

  Future<bool> shadowOpenWeb(Uri shadowU) async {
    try {
      if (await launchUrl(shadowU, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(shadowU, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$shadowU');
      try {
        return await launchUrl(shadowU, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String shadowOnlyDigits(String shadowS) => shadowS.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    shadowBindNotificationChannel(); // повторная привязка на всякий случай

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (shadowCover)
              const ShadowLoaderWidget()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(shadowHatch),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri(shadowHome)),
                      onWebViewCreated: (shadowC) {
                        shadowWebCtrl = shadowC;

                        shadowBosun ??= ShadowBosunViewModel(shadowDevice: shadowDevice, shadowAf: shadowAf);
                        shadowCourier ??= ShadowCourier(shadowModel: shadowBosun!, shadowGetWeb: () => shadowWebCtrl);

                        shadowWebCtrl.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (shadowArgs) async {

                            final server = await _startUnityServer(port: 8080);
                            try {
                              final shadowSaved = shadowArgs.isNotEmpty &&
                                  shadowArgs[0] is Map &&
                                  shadowArgs[0]['savedata'].toString() == "false";

                              print("Load True " + shadowArgs[0].toString());
                              if (shadowSaved)  {



                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (context) => UnityWebGLApp(server:server,)),
                                      (route) => false,
                                );
                              }
                            } catch (_) {}
                            if (shadowArgs.isEmpty) return null;
                            try {
                              return shadowArgs.reduce((shadowCurr, shadowNext) => shadowCurr + shadowNext);
                            } catch (_) {
                              return shadowArgs.first;
                            }
                          },
                        );
                      },
                      onLoadStart: (shadowC, shadowU) async {
                        setState(() {
                          shadowStartLoadTs = DateTime.now().millisecondsSinceEpoch;
                        });
                        setState(() => shadowBusy = true);
                        final shadowV = shadowU;
                        if (shadowV != null) {
                          if (shadowLooksLikeBareEmail(shadowV)) {
                            try {
                              await shadowC.stopLoading();
                            } catch (_) {}
                            final shadowMailto = shadowMakeMailto(shadowV);
                            await shadowOpenMail(shadowMailto);
                            return;
                          }
                          final shadowScheme = shadowV.scheme.toLowerCase();
                          if (shadowScheme != 'http' && shadowScheme != 'https') {
                            try {
                              await shadowC.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (shadowController, shadowUrl, shadowCode, shadowMessage) async {
                        final shadowNow = DateTime.now().millisecondsSinceEpoch;
                        final shadowEv = "InAppWebViewError(code=$shadowCode, message=$shadowMessage)";
                        await shadowPostStat(
                          shadowEvent: shadowEv,
                          shadowTimeStart: shadowNow,
                          shadowTimeFinish: shadowNow,
                          shadowUrl: shadowUrl?.toString() ?? '',
                          shadowAppSid: shadowAf.shadowAfUid,
                          shadowFirstPageTs: shadowFirstPageTs,
                        );
                        if (mounted) setState(() => shadowBusy = false);
                      },
                      onReceivedHttpError: (shadowController, shadowRequest, shadowErrorResponse) async {
                        final shadowNow = DateTime.now().millisecondsSinceEpoch;
                        final shadowEv = "HTTPError(status=${shadowErrorResponse.statusCode}, reason=${shadowErrorResponse.reasonPhrase})";
                        await shadowPostStat(
                          shadowEvent: shadowEv,
                          shadowTimeStart: shadowNow,
                          shadowTimeFinish: shadowNow,
                          shadowUrl: shadowRequest.url?.toString() ?? '',
                          shadowAppSid: shadowAf.shadowAfUid,
                          shadowFirstPageTs: shadowFirstPageTs,
                        );
                      },
                      onReceivedError: (shadowController, shadowRequest, shadowError) async {
                        final shadowNow = DateTime.now().millisecondsSinceEpoch;
                        final shadowDesc = (shadowError.description ?? '').toString();
                        final shadowEv = "WebResourceError(code=${shadowError}, message=$shadowDesc)";
                        await shadowPostStat(
                          shadowEvent: shadowEv,
                          shadowTimeStart: shadowNow,
                          shadowTimeFinish: shadowNow,
                          shadowUrl: shadowRequest.url?.toString() ?? '',
                          shadowAppSid: shadowAf.shadowAfUid,
                          shadowFirstPageTs: shadowFirstPageTs,
                        );
                      },
                      onLoadStop: (shadowC, shadowU) async {
                        await shadowC.evaluateJavascript(source: "console.log('Harbor up!');");
                        await shadowPushDevice();
                        await shadowPushAf();

                        setState(() => shadowCurrentUrl = shadowU.toString());

                        Future.delayed(const Duration(seconds: 20), () {
                          shadowSendLoadedOnce(shadowUrl: shadowCurrentUrl.toString(), shadowStart: shadowStartLoadTs);
                        });

                        if (mounted) setState(() => shadowBusy = false);
                      },
                      shouldOverrideUrlLoading: (shadowC, shadowAction) async {
                        final shadowUri = shadowAction.request.url;
                        if (shadowUri == null) return NavigationActionPolicy.ALLOW;

                        if (shadowLooksLikeBareEmail(shadowUri)) {
                          final shadowMailto = shadowMakeMailto(shadowUri);
                          await shadowOpenMail(shadowMailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final shadowScheme = shadowUri.scheme.toLowerCase();

                        if (shadowScheme == 'mailto') {
                          await shadowOpenMail(shadowUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (shadowScheme == 'tel') {
                          await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (shadowIsPlatformish(shadowUri)) {
                          final shadowWeb = shadowNormalizeToHttp(shadowUri);

                          final shadowHost = (shadowWeb.host.isNotEmpty ? shadowWeb.host : shadowUri.host).toLowerCase();
                          final shadowIsSocial =
                              shadowHost.endsWith('x.com') ||
                                  shadowHost.endsWith('twitter.com') ||
                                  shadowHost.endsWith('facebook.com') ||
                                  shadowHost.startsWith('m.facebook.com') ||
                                  shadowHost.endsWith('instagram.com') ||
                                  shadowHost.endsWith('t.me') ||
                                  shadowHost.endsWith('telegram.me') ||
                                  shadowHost.endsWith('telegram.dog');

                          if (shadowIsSocial) {
                            await shadowOpenWeb(shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https' ? shadowWeb : shadowUri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (shadowWeb.scheme == 'http' || shadowWeb == shadowUri) {
                            await shadowOpenWeb(shadowWeb);
                          } else {
                            try {
                              if (await canLaunchUrl(shadowUri)) {
                                await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                              } else if (shadowWeb != shadowUri && (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https')) {
                                await shadowOpenWeb(shadowWeb);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (shadowScheme != 'http' && shadowScheme != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (shadowC, shadowReq) async {
                        final shadowUri = shadowReq.request.url;
                        if (shadowUri == null) return false;

                        if (shadowLooksLikeBareEmail(shadowUri)) {
                          final shadowMailto = shadowMakeMailto(shadowUri);
                          await shadowOpenMail(shadowMailto);
                          return false;
                        }

                        final shadowScheme = shadowUri.scheme.toLowerCase();

                        if (shadowScheme == 'mailto') {
                          await shadowOpenMail(shadowUri);
                          return false;
                        }

                        if (shadowScheme == 'tel') {
                          await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        if (shadowIsPlatformish(shadowUri)) {
                          final shadowWeb = shadowNormalizeToHttp(shadowUri);

                          final shadowHost = (shadowWeb.host.isNotEmpty ? shadowWeb.host : shadowUri.host).toLowerCase();
                          final shadowIsSocial =
                              shadowHost.endsWith('x.com') ||
                                  shadowHost.endsWith('twitter.com') ||
                                  shadowHost.endsWith('facebook.com') ||
                                  shadowHost.startsWith('m.facebook.com') ||
                                  shadowHost.endsWith('instagram.com') ||
                                  shadowHost.endsWith('t.me') ||
                                  shadowHost.endsWith('telegram.me') ||
                                  shadowHost.endsWith('telegram.dog');

                          if (shadowIsSocial) {
                            await shadowOpenWeb(shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https' ? shadowWeb : shadowUri);
                            return false;
                          }

                          if (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https') {
                            await shadowOpenWeb(shadowWeb);
                          } else {
                            try {
                              if (await canLaunchUrl(shadowUri)) {
                                await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                              } else if (shadowWeb != shadowUri && (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https')) {
                                await shadowOpenWeb(shadowWeb);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (shadowScheme == 'http' || shadowScheme == 'https') {
                          shadowC.loadUrl(urlRequest: URLRequest(url: shadowUri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (shadowC, shadowReq) async {
                        await shadowOpenWeb(shadowReq.url);
                      },
                    ),
                    Visibility(
                      visible: !shadowVeil,
                      child: const ShadowLoaderWidget(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ShadowExternalDeck — отдельный WebView для внешней ссылки (из нотификаций)
// ============================================================================
class ShadowExternalDeck extends StatefulWidget with WidgetsBindingObserver {
  final String shadowUrl;
  const ShadowExternalDeck(this.shadowUrl, {super.key});

  @override
  State<ShadowExternalDeck> createState() => ShadowExternalDeckState();
}

class ShadowExternalDeckState extends State<ShadowExternalDeck> with WidgetsBindingObserver {
  late InAppWebViewController shadowDeckCtrl;

  final Set<String> shadowSchemes = {
    'tg', 'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
    'fb', 'instagram', 'twitter', 'x',
  };

  final Set<String> shadowExternalHosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com', 'www.bnl.com',
    'x.com', 'www.x.com',
    'twitter.com', 'www.twitter.com',
    'facebook.com', 'www.facebook.com', 'm.facebook.com',
    'instagram.com', 'www.instagram.com',
  };

  bool shadowLooksLikeBareEmail(Uri shadowU) {
    final shadowS = shadowU.scheme;
    if (shadowS.isNotEmpty) return false;
    final shadowRaw = shadowU.toString();
    return shadowRaw.contains('@') && !shadowRaw.contains(' ');
  }

  Uri shadowMakeMailto(Uri shadowU) {
    final shadowFull = shadowU.toString();
    final shadowParts = shadowFull.split('?');
    final shadowEmail = shadowParts.first;
    final shadowQ = shadowParts.length > 1 ? Uri.splitQueryString(shadowParts[1]) : <String, String>{};
    return Uri(scheme: 'mailto', path: shadowEmail, queryParameters: shadowQ.isEmpty ? null : shadowQ);
  }

  bool shadowIsPlatformish(Uri shadowU) {
    final shadowS = shadowU.scheme.toLowerCase();
    if (shadowSchemes.contains(shadowS)) return true;

    if (shadowS == 'http' || shadowS == 'https') {
      final shadowH = shadowU.host.toLowerCase();
      if (shadowExternalHosts.contains(shadowH)) return true;
      if (shadowH.endsWith('t.me')) return true;
      if (shadowH.endsWith('wa.me')) return true;
      if (shadowH.endsWith('m.me')) return true;
      if (shadowH.endsWith('signal.me')) return true;
      if (shadowH.endsWith('x.com')) return true;
      if (shadowH.endsWith('twitter.com')) return true;
      if (shadowH.endsWith('facebook.com')) return true;
      if (shadowH.endsWith('instagram.com')) return true;
    }
    return false;
  }

  Uri shadowNormalizeToHttp(Uri shadowU) {
    final shadowS = shadowU.scheme.toLowerCase();

    if (shadowS == 'tg' || shadowS == 'telegram') {
      final shadowQ = shadowU.queryParameters;
      final shadowDomain = shadowQ['domain'];
      if (shadowDomain != null && shadowDomain.isNotEmpty) {
        return Uri.https('t.me', '/$shadowDomain', {if (shadowQ['start'] != null) 'start': shadowQ['start']!});
      }
      final shadowPath = shadowU.path.isNotEmpty ? shadowU.path : '';
      return Uri.https('t.me', '/$shadowPath', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if ((shadowS == 'http' || shadowS == 'https') && shadowU.host.toLowerCase().endsWith('t.me')) {
      return shadowU;
    }

    if (shadowS == 'viber') return shadowU;

    if (shadowS == 'whatsapp') {
      final shadowQ = shadowU.queryParameters;
      final shadowPhone = shadowQ['phone'];
      final shadowText = shadowQ['text'];
      if (shadowPhone != null && shadowPhone.isNotEmpty) {
        return Uri.https('wa.me', '/${shadowOnlyDigits(shadowPhone)}', {if (shadowText != null && shadowText.isNotEmpty) 'text': shadowText});
      }
      return Uri.https('wa.me', '/', {if (shadowText != null && shadowText.isNotEmpty) 'text': shadowText});
    }

    if ((shadowS == 'http' || shadowS == 'https') &&
        (shadowU.host.toLowerCase().endsWith('wa.me') || shadowU.host.toLowerCase().endsWith('whatsapp.com'))) {
      return shadowU;
    }

    if (shadowS == 'skype') return shadowU;

    if (shadowS == 'fb-messenger') {
      final shadowPath = shadowU.pathSegments.isNotEmpty ? shadowU.pathSegments.join('/') : '';
      final shadowQ = shadowU.queryParameters;
      final shadowId = shadowQ['id'] ?? shadowQ['user'] ?? shadowPath;
      if (shadowId.isNotEmpty) {
        return Uri.https('m.me', '/$shadowId', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
      }
      return Uri.https('m.me', '/', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if (shadowS == 'sgnl') {
      final shadowQ = shadowU.queryParameters;
      final shadowPh = shadowQ['phone'];
      final shadowUn = shadowU.queryParameters['username'];
      if (shadowPh != null && shadowPh.isNotEmpty) return Uri.https('signal.me', '/#p/${shadowOnlyDigits(shadowPh)}');
      if (shadowUn != null && shadowUn.isNotEmpty) return Uri.https('signal.me', '/#u/$shadowUn');
      final shadowPath = shadowU.pathSegments.join('/');
      if (shadowPath.isNotEmpty) return Uri.https('signal.me', '/$shadowPath', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
      return shadowU;
    }

    if (shadowS == 'tel') {
      return Uri.parse('tel:${shadowOnlyDigits(shadowU.path)}');
    }

    if (shadowS == 'mailto') return shadowU;

    if (shadowS == 'bnl') {
      final shadowNewPath = shadowU.path.isNotEmpty ? shadowU.path : '';
      return Uri.https('bnl.com', '/$shadowNewPath', shadowU.queryParameters.isEmpty ? null : shadowU.queryParameters);
    }

    if ((shadowS == 'http' || shadowS == 'https')) {
      final shadowHost = shadowU.host.toLowerCase();
      if (shadowHost.endsWith('x.com') ||
          shadowHost.endsWith('twitter.com') ||
          shadowHost.endsWith('facebook.com') ||
          shadowHost.startsWith('m.facebook.com') ||
          shadowHost.endsWith('instagram.com')) {
        return shadowU;
      }
    }

    if (shadowS == 'fb' || shadowS == 'instagram' || shadowS == 'twitter' || shadowS == 'x') {
      return shadowU;
    }

    return shadowU;
  }

  Future<bool> shadowOpenMail(Uri shadowMailto) async {
    final shadowGmail = shadowGmailize(shadowMailto);
    return await shadowOpenWeb(shadowGmail);
  }

  Uri shadowGmailize(Uri shadowM) {
    final shadowQ = shadowM.queryParameters;
    final Map<String, String> shadowParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (shadowM.path.isNotEmpty) 'to': shadowM.path,
      if ((shadowQ['subject'] ?? '').isNotEmpty) 'su': shadowQ['subject']!,
      if ((shadowQ['body'] ?? '').isNotEmpty) 'body': shadowQ['body']!,
      if ((shadowQ['cc'] ?? '').isNotEmpty) 'cc': shadowQ['cc']!,
      if ((shadowQ['bcc'] ?? '').isNotEmpty) 'bcc': shadowQ['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', shadowParams);
  }

  Future<bool> shadowOpenWeb(Uri shadowU) async {
    try {
      if (await launchUrl(shadowU, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(shadowU, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$shadowU');
      try {
        return await launchUrl(shadowU, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String shadowOnlyDigits(String shadowS) => shadowS.replaceAll(RegExp(r'[^0-9+]'), '');

  @override
  Widget build(BuildContext context) {
    final shadowDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: shadowDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            disableDefaultErrorPage: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            allowsPictureInPictureMediaPlayback: true,
            useOnDownloadStart: true,
            javaScriptCanOpenWindowsAutomatically: true,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(widget.shadowUrl)),
          onWebViewCreated: (shadowC) => shadowDeckCtrl = shadowC,
          shouldOverrideUrlLoading: (shadowC, shadowAction) async {
            final shadowUri = shadowAction.request.url;
            if (shadowUri == null) return NavigationActionPolicy.ALLOW;

            if (shadowLooksLikeBareEmail(shadowUri)) {
              final shadowMailto = shadowMakeMailto(shadowUri);
              await shadowOpenMail(shadowMailto);
              return NavigationActionPolicy.CANCEL;
            }

            final shadowScheme = shadowUri.scheme.toLowerCase();

            if (shadowScheme == 'mailto') {
              await shadowOpenMail(shadowUri);
              return NavigationActionPolicy.CANCEL;
            }

            if (shadowScheme == 'tel') {
              await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
              return NavigationActionPolicy.CANCEL;
            }

            if (shadowIsPlatformish(shadowUri)) {
              final shadowWeb = shadowNormalizeToHttp(shadowUri);

              final shadowHost = (shadowWeb.host.isNotEmpty ? shadowWeb.host : shadowUri.host).toLowerCase();
              final shadowIsSocial =
                  shadowHost.endsWith('x.com') ||
                      shadowHost.endsWith('twitter.com') ||
                      shadowHost.endsWith('facebook.com') ||
                      shadowHost.startsWith('m.facebook.com') ||
                      shadowHost.endsWith('instagram.com') ||
                      shadowHost.endsWith('t.me') ||
                      shadowHost.endsWith('telegram.me') ||
                      shadowHost.endsWith('telegram.dog');

              if (shadowIsSocial) {
                await shadowOpenWeb(shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https' ? shadowWeb : shadowUri);
                return NavigationActionPolicy.CANCEL;
              }

              if (shadowWeb.scheme == 'http' || shadowWeb == shadowUri) {
                await shadowOpenWeb(shadowWeb);
              } else {
                try {
                  if (await canLaunchUrl(shadowUri)) {
                    await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                  } else if (shadowWeb != shadowUri && (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https')) {
                    await shadowOpenWeb(shadowWeb);
                  }
                } catch (_) {}
              }
              return NavigationActionPolicy.CANCEL;
            }

            if (shadowScheme != 'http' && shadowScheme != 'https') {
              return NavigationActionPolicy.CANCEL;
            }

            return NavigationActionPolicy.ALLOW;
          },
          onCreateWindow: (shadowC, shadowReq) async {
            final shadowUri = shadowReq.request.url;
            if (shadowUri == null) return false;

            if (shadowLooksLikeBareEmail(shadowUri)) {
              final shadowMailto = shadowMakeMailto(shadowUri);
              await shadowOpenMail(shadowMailto);
              return false;
            }

            final shadowScheme = shadowUri.scheme.toLowerCase();

            if (shadowScheme == 'mailto') {
              await shadowOpenMail(shadowUri);
              return false;
            }

            if (shadowScheme == 'tel') {
              await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
              return false;
            }

            if (shadowIsPlatformish(shadowUri)) {
              final shadowWeb = shadowNormalizeToHttp(shadowUri);

              final shadowHost = (shadowWeb.host.isNotEmpty ? shadowWeb.host : shadowUri.host).toLowerCase();
              final shadowIsSocial =
                  shadowHost.endsWith('x.com') ||
                      shadowHost.endsWith('twitter.com') ||
                      shadowHost.endsWith('facebook.com') ||
                      shadowHost.startsWith('m.facebook.com') ||
                      shadowHost.endsWith('instagram.com') ||
                      shadowHost.endsWith('t.me') ||
                      shadowHost.endsWith('telegram.me') ||
                      shadowHost.endsWith('telegram.dog');

              if (shadowIsSocial) {
                await shadowOpenWeb(shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https' ? shadowWeb : shadowUri);
                return false;
              }

              if (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https') {
                await shadowOpenWeb(shadowWeb);
              } else {
                try {
                  if (await canLaunchUrl(shadowUri)) {
                    await launchUrl(shadowUri, mode: LaunchMode.externalApplication);
                  } else if (shadowWeb != shadowUri && (shadowWeb.scheme == 'http' || shadowWeb.scheme == 'https')) {
                    await shadowOpenWeb(shadowWeb);
                  }
                } catch (_) {}
              }
              return false;
            }

            if (shadowScheme == 'http' || shadowScheme == 'https') {
              shadowC.loadUrl(urlRequest: URLRequest(url: shadowUri));
            }
            return false;
          },
          onDownloadStartRequest: (shadowC, shadowReq) async {
            await shadowOpenWeb(shadowReq.url);
          },
        ),
      ),
    );
  }
}



// ============================================================================
// main()
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(shadowOnBackgroundMessage);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  tz_data.initializeTimeZones();

  runApp(
    p.MultiProvider(
      providers: [
        shadowAppsFlyerProvider,
      ],
      child: r.ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const ShadowSplash(),
        ),
      ),
    ),
  );
}



Future<UnityAssetServer> _startUnityServer({required int port}) async {
  final manifestJson = await rootBundle.loadString('AssetManifest.json');
  final manifest = Map<String, dynamic>.from(json.decode(manifestJson));
  final availableAssets = manifest.keys.toSet();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  debugPrint('Unity asset server listening on http://localhost:$port');

  server.listen((HttpRequest request) async {
    final originalPath =
    request.uri.path == '/' ? '/unity/index.html' : request.uri.path;
    final decodedPath = Uri.decodeComponent(originalPath);

    final assetCandidates = <String>[
      'assets$decodedPath',
      if (decodedPath.endsWith('.data'))
        'assets${decodedPath}.unityweb',
      if (decodedPath.endsWith('.wasm'))
        'assets${decodedPath}.unityweb',
      if (decodedPath.endsWith('.js'))
        'assets${decodedPath}.unityweb',
    ];

    ByteData? byteData;
    String? hitPath;

    for (final candidate in assetCandidates) {
      if (availableAssets.contains(candidate)) {
        hitPath = candidate;
        byteData = await rootBundle.load(candidate);
        break;
      }
    }

    if (byteData == null) {
      debugPrint('404 -> $decodedPath (candidates: $assetCandidates)');
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not found: $decodedPath');
      await request.response.close();
      return;
    }

    final headers = request.response.headers;
    headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=31536000');

    void addEncoding(String encoding) {
      headers.add(HttpHeaders.contentEncodingHeader, encoding);
    }

    if (hitPath!.endsWith('.html')) {
      headers.contentType = ContentType.html;
    } else if (hitPath.endsWith('.js') || hitPath.endsWith('.js.unityweb')) {
      headers.contentType =
          ContentType('application', 'javascript', charset: 'utf-8');
    } else if (hitPath.endsWith('.css')) {
      headers.contentType = ContentType('text', 'css', charset: 'utf-8');
    } else if (hitPath.endsWith('.wasm') || hitPath.endsWith('.wasm.unityweb')) {
      headers.contentType = ContentType('application', 'wasm');
    } else if (hitPath.endsWith('.data') || hitPath.endsWith('.data.unityweb')) {
      headers.contentType = ContentType('application', 'octet-stream');
    } else {
      headers.contentType = ContentType.binary;
    }

    if (hitPath.endsWith('.unityweb')) {
      addEncoding('gzip'); // или 'br', если билд в Brotli
    }

    debugPrint('200 <- $decodedPath (served: $hitPath)');
    request.response.add(byteData.buffer.asUint8List());
    await request.response.close();
  });

  return UnityAssetServer(server);
}



class UnityWebGLApp extends StatelessWidget {
  const UnityWebGLApp({super.key, required this.server});
  final UnityAssetServer server;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unity WebGL (assets)',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: UnityWebGLPage(server: server),
    );
  }
}

class UnityWebGLPage extends StatefulWidget {
  const UnityWebGLPage({super.key, required this.server});
  final UnityAssetServer server;

  @override
  State<UnityWebGLPage> createState() => _UnityWebGLPageState();
}

class _UnityWebGLPageState extends State<UnityWebGLPage> {
  InAppWebViewController? controller;
  double progress = 0;

  @override
  void dispose() {
    widget.server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unityUrl =
    WebUri('http://localhost:${widget.server.port}/unity/index.html');

    return Scaffold(

      body: InAppWebView(
        initialUrlRequest: URLRequest(url: unityUrl),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          useHybridComposition: true,
        ),
        onWebViewCreated: (ctrl) => controller = ctrl,
        onProgressChanged: (_, value) =>
            setState(() => progress = value / 100),
        onConsoleMessage: (_, msg) => debugPrint('WebView console: $msg'),
        onLoadError: (_, url, code, msg) =>
            debugPrint('Load error [$code] $msg for $url'),
      ),
    );
  }
}


