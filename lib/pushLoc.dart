// -----------------------------------------------------------------------------
// Luck-flavored refactor (snake_case): все классы и переменные в luck-стиле
// -----------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Предполагаемые новые имена экранов в main.dart (оставлены как есть в импорте)
import 'main.dart' show SpiritMafiaHarbor, SpiritCaptainHarbor, CaptainHarbor, CaptainDeck, captain_harbor, ShadowHarbor;

// ============================================================================
// Паттерны/инфраструктура (luck edition, snake_case)
// ============================================================================

class luck_black_box {
  const luck_black_box();
  void luck_log(Object msg) => debugPrint('[LuckBlackBox] $msg');
  void luck_warn(Object msg) => debugPrint('[LuckBlackBox/WARN] $msg');
  void luck_err(Object msg) => debugPrint('[LuckBlackBox/ERR] $msg');
}

class luck_rum_chest {
  static final luck_rum_chest _luck_single = luck_rum_chest._luck();
  luck_rum_chest._luck();
  factory luck_rum_chest() => _luck_single;

  final luck_black_box luck_box = const luck_black_box();
}

/// Утилиты маршрутов/почты (Luck Sextant)
class luck_sextant_kit {
  // Похоже ли на голый e-mail (без схемы)
  static bool looks_like_bare_mail(Uri luck_uri) {
    final s = luck_uri.scheme;
    if (s.isNotEmpty) return false;
    final raw = luck_uri.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  // Превращает "bare" или обычный URL в mailto:
  static Uri to_mailto(Uri luck_uri) {
    final full = luck_uri.toString();
    final bits = full.split('?');
    final who = bits.first;
    final qp = bits.length > 1 ? Uri.splitQueryString(bits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: who,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  // Делает Gmail compose-ссылку
  static Uri gmailize(Uri luck_mailto) {
    final qp = luck_mailto.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (luck_mailto.path.isNotEmpty) 'to': luck_mailto.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  static String just_digits(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// Сервис открытия внешних ссылок/протоколов (Luck Messenger)
class luck_parrot_signal {
  static Future<bool> open(Uri luck_uri) async {
    try {
      if (await launchUrl(luck_uri, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(luck_uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('LuckParrotSignal error: $e; url=$luck_uri');
      try {
        return await launchUrl(luck_uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler — luck-попугай
// ============================================================================
@pragma('vm:entry-point')
Future<void> luck_bg_parrot(RemoteMessage luck_bottle) async {
  debugPrint("Luck Bottle ID: ${luck_bottle.messageId}");
  debugPrint("Luck Bottle Data: ${luck_bottle.data}");
}

// ============================================================================
// Виджет-каюта с webview — luck_captain_deckload
// ============================================================================
class luck_captain_deckload extends StatefulWidget with WidgetsBindingObserver {
  String luck_sea_route;
  luck_captain_deckload(this.luck_sea_route, {super.key});

  @override
  State<luck_captain_deckload> createState() => _luck_captain_deckload_state(luck_sea_route);
}

class _luck_captain_deckload_state extends State<luck_captain_deckload> with WidgetsBindingObserver {
  _luck_captain_deckload_state(this._luck_current_route);

  final luck_rum_chest _luck_rum = luck_rum_chest();

  late InAppWebViewController _luck_helm; // штурвал
  String? _luck_parrot_token; // FCM token
  String? _luck_ship_id; // device id
  String? _luck_ship_build; // os build
  String? _luck_ship_kind; // android/ios
  String? _luck_ship_os; // locale/lang
  String? _luck_app_sextant; // timezone
  bool _luck_cannon_armed = true; // push enabled
  bool _luck_crew_busy = false;
  var _luck_gate_open = true;
  String _luck_current_route;
  DateTime? _luck_last_dock_time;

  // Внешние гавани (tg/wa/bnl)
  final Set<String> _luck_harbor_hosts = {
    't.me', 'telegram.me', 'telegram.dog',
    'wa.me', 'api.whatsapp.com', 'chat.whatsapp.com',
    'bnl.com', 'www.bnl.com',
  };
  final Set<String> _luck_harbor_schemes = {'tg', 'telegram', 'whatsapp', 'bnl'};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(luck_bg_parrot);

    _luck_rig_parrot_fcm();
    _luck_scan_ship_gizmo();
    _luck_wire_foredeck_fcm();
    _luck_bind_bell();

    Future.delayed(const Duration(seconds: 2), () {});
    Future.delayed(const Duration(seconds: 6), () {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState luck_tide) {
    if (luck_tide == AppLifecycleState.paused) {
      _luck_last_dock_time = DateTime.now();
    }
    if (luck_tide == AppLifecycleState.resumed) {
      if (Platform.isIOS && _luck_last_dock_time != null) {
        final now = DateTime.now();
        final drift = now.difference(_luck_last_dock_time!);
        if (drift > const Duration(minutes: 25)) {
          _luck_hard_reload_to_harbor();
        }
      }
      _luck_last_dock_time = null;
    }
  }

  void _luck_hard_reload_to_harbor() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) =>ShadowHarbor(shadowSignal: '',)),
            (route) => false,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Каналы связи
  // --------------------------------------------------------------------------
  void _luck_wire_foredeck_fcm() {
    FirebaseMessaging.onMessage.listen((RemoteMessage luck_bottle) {
      if (luck_bottle.data['uri'] != null) {
        _luck_sail_to(luck_bottle.data['uri'].toString());
      } else {
        _luck_return_to_course();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage luck_bottle) {
      if (luck_bottle.data['uri'] != null) {
        _luck_sail_to(luck_bottle.data['uri'].toString());
      } else {
        _luck_return_to_course();
      }
    });
  }

  void _luck_sail_to(String luck_new_lane) async {
    await _luck_helm.loadUrl(urlRequest: URLRequest(url: WebUri(luck_new_lane)));
  }

  void _luck_return_to_course() async {
    Future.delayed(const Duration(seconds: 3), () {
      _luck_helm.loadUrl(urlRequest: URLRequest(url: WebUri(_luck_current_route)));
    });
  }

  Future<void> _luck_rig_parrot_fcm() async {
    FirebaseMessaging luck_deck = FirebaseMessaging.instance;
    await luck_deck.requestPermission(alert: true, badge: true, sound: true);
    _luck_parrot_token = await luck_deck.getToken();
  }

  // --------------------------------------------------------------------------
  // Досье корабля
  // --------------------------------------------------------------------------
  Future<void> _luck_scan_ship_gizmo() async {
    try {
      final luck_spy = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await luck_spy.androidInfo;
        _luck_ship_id = a.id;
        _luck_ship_kind = "android";
        _luck_ship_build = a.version.release;
      } else if (Platform.isIOS) {
        final i = await luck_spy.iosInfo;
        _luck_ship_id = i.identifierForVendor;
        _luck_ship_kind = "ios";
        _luck_ship_build = i.systemVersion;
      }
      final luck_pkg = await PackageInfo.fromPlatform();
      _luck_ship_os = Platform.localeName.split('_')[0];
      _luck_app_sextant = timezone.local.name;
    } catch (e) {
      debugPrint("Luck Ship Gizmo Error: $e");
    }
  }

  void _luck_bind_bell() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);
        if (payload["uri"] != null && !payload["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => luck_captain_deckload(payload["uri"].toString())),
                (route) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // Построение UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    _luck_bind_bell(); // повторная привязка

    final luck_is_night = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: luck_is_night ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
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
              initialUrlRequest: URLRequest(url: WebUri(_luck_current_route)),
              onWebViewCreated: (luck_controller) {
                _luck_helm = luck_controller;

                _luck_helm.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (luck_args) {
                    _luck_rum.luck_box.luck_log("JS Args: $luck_args");
                    try {
                      return luck_args.reduce((v, e) => v + e);
                    } catch (_) {
                      return luck_args.toString();
                    }
                  },
                );
              },
              onLoadStart: (luck_controller, luck_uri) async {
                if (luck_uri != null) {
                  if (luck_sextant_kit.looks_like_bare_mail(luck_uri)) {
                    try {
                      await luck_controller.stopLoading();
                    } catch (_) {}
                    final mailto = luck_sextant_kit.to_mailto(luck_uri);
                    await luck_parrot_signal.open(luck_sextant_kit.gmailize(mailto));
                    return;
                  }
                  final s = luck_uri.scheme.toLowerCase();
                  if (s != 'http' && s != 'https') {
                    try {
                      await luck_controller.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (luck_controller, luck_uri) async {
                await luck_controller.evaluateJavascript(source: "console.log('Ahoy from JS!');");
              },
              shouldOverrideUrlLoading: (luck_controller, luck_nav) async {
                final luck_uri = luck_nav.request.url;
                if (luck_uri == null) return NavigationActionPolicy.ALLOW;

                if (luck_sextant_kit.looks_like_bare_mail(luck_uri)) {
                  final mailto = luck_sextant_kit.to_mailto(luck_uri);
                  await luck_parrot_signal.open(luck_sextant_kit.gmailize(mailto));
                  return NavigationActionPolicy.CANCEL;
                }

                final sch = luck_uri.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await luck_parrot_signal.open(luck_sextant_kit.gmailize(luck_uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (_luck_is_outer_harbor(luck_uri)) {
                  await luck_parrot_signal.open(_luck_map_outer_to_http(luck_uri));
                  return NavigationActionPolicy.CANCEL;
                }

                if (sch != 'http' && sch != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (luck_controller, luck_req) async {
                final u = luck_req.request.url;
                if (u == null) return false;

                if (luck_sextant_kit.looks_like_bare_mail(u)) {
                  final m = luck_sextant_kit.to_mailto(u);
                  await luck_parrot_signal.open(luck_sextant_kit.gmailize(m));
                  return false;
                }

                final sch = u.scheme.toLowerCase();
                if (sch == 'mailto') {
                  await luck_parrot_signal.open(luck_sextant_kit.gmailize(u));
                  return false;
                }

                if (_luck_is_outer_harbor(u)) {
                  await luck_parrot_signal.open(_luck_map_outer_to_http(u));
                  return false;
                }

                if (sch == 'http' || sch == 'https') {
                  luck_controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),

            if (_luck_crew_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: CircularProgressIndicator(
                      backgroundColor: Colors.grey.shade800,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Luck-утилиты маршрутов (протоколы/внешние гавани)
  // ========================================================================
  bool _luck_is_outer_harbor(Uri luck_uri) {
    final sch = luck_uri.scheme.toLowerCase();
    if (_luck_harbor_schemes.contains(sch)) return true;

    if (sch == 'http' || sch == 'https') {
      final h = luck_uri.host.toLowerCase();
      if (_luck_harbor_hosts.contains(h)) return true;
    }
    return false;
  }

  Uri _luck_map_outer_to_http(Uri luck_uri) {
    final sch = luck_uri.scheme.toLowerCase();

    if (sch == 'tg' || sch == 'telegram') {
      final qp = luck_uri.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = luck_uri.path.isNotEmpty ? luck_uri.path : '';
      return Uri.https('t.me', '/$path', qp.isEmpty ? null : qp);
    }

    if (sch == 'whatsapp') {
      final qp = luck_uri.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${luck_sextant_kit.just_digits(phone)}', {
          if (text != null && text.isNotEmpty) 'text': text,
        });
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    if (sch == 'bnl') {
      final new_path = luck_uri.path.isNotEmpty ? luck_uri.path : '';
      return Uri.https('bnl.com', '/$new_path', luck_uri.queryParameters.isEmpty ? null : luck_uri.queryParameters);
    }

    return luck_uri;
  }
}