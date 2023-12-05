import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth_example/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

Future<void> main() async {
  runApp(MaterialApp(initialRoute: "MyApp", routes: {
    "MyApp": (context) => const MyApp(),
  }));
}

enum _SupportState {
  unknown,
  supported,
  unsupported,
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isBusy = false;

  final Session _session = Session();
  final _storage = const FlutterSecureStorage();

  final LocalAuthentication auth = LocalAuthentication();
  final _SupportState _supportState = _SupportState.unknown;
  String _authorized = 'Not Authorized';
  bool _isAuthenticating = false;

  final String _siteDomain = "moj.telekom.si";
  final String _ssoDomain = "prijava.telekom.si";
  final String _siteUrl =
      "https://moj.telekom.si/eu/MobileDashboard/Dashboard/Index/041777142";

  // final String _siteDomain = ".fritz.box";
  // final String _siteUrl="http://p71-pc.fritz.box:62778/";

  final WebViewController _webViewController = WebViewController();
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  Future<void>? _sessionCheck;

  double? _webViewHeight = null;

  _MyAppState() {
    _webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    _webViewController.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (navigation) async {
        final host = Uri.parse(navigation.url).host;
        if (host.contains(_ssoDomain)) {
          try {
            _setBusyState();
            signIn();
          } catch (e) {
            _clearSessionCookies();
            _clearRefreshToken();
            _session.clear();
            _clearBusyState();
          }

          await _webViewController.loadRequest(Uri.parse(_siteUrl));
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onPageFinished: (navigation) {
        _clearBusyState();
      },
    ));
  }

  @override
  void initState() {
    super.initState();

    AndroidWebViewController.enableDebugging(true);
    _sessionCheck = _checkSessionOnStartUp();
  }

  Future<bool> _checkSessionOnStartUp() async {
    try {
      _setBusyState();
      // Check if refresh token exists and there is valid SSO session
      if (await _storage.containsKey(key: "refreshToken")) {
        //check owner presence with biometrics
        await _authenticate();
        await _loadRefreshToken();
        if (await _session.refreshTokens(await _loadRefreshToken())) {
          await _cookieManager.clearCookies();
        } else {
          _clearBusyState();
          return false;
        }
      } else {
        // otherwise authenticate user and create new SSO session
        await _session.signInWithAutoCodeExchange();
      }
      // SSO session is now valid so we retrieve MT session cookies
      // Inject cookies and load content
      await _storeRefreshToken(_session.refreshToken);
      await _storeSessionCookies(await _session.getMTSession());
      await _webViewController.loadRequest(Uri.parse(_siteUrl));
      _clearBusyState();
      return true;
    } catch (e) {
      _session.clear();
      _clearSessionCookies();
      _clearRefreshToken();
      _clearBusyState();
      throw SessionException("Failed to check session on startup.");
    }
  }

  Future<void> signIn() async {
    try {
      _setBusyState();
      await _session.signInWithAutoCodeExchange();
      await _storeSessionCookies(await _session.getMTSession());
    } catch (e) {
      _session.clear();
      _clearSessionCookies();
      _clearRefreshToken();
      _clearBusyState();
      throw SessionException("Failed to sign in.");
    }
  }

  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      setState(() {
        _isAuthenticating = true;
        _authorized = 'Authenticating';
      });
      authenticated = await auth.authenticate(
        localizedReason: 'Let OS determine authentication method',
        options: const AuthenticationOptions(
          stickyAuth: true,
        ),
      );
      setState(() {
        _isAuthenticating = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _isAuthenticating = false;
        _authorized = 'Error - ${e.message}';
      });
      return;
    }
    if (!mounted) {
      return;
    }

    setState(
        () => _authorized = authenticated ? 'Authorized' : 'Not Authorized');
  }

  Future<String?> _loadRefreshToken() async {
    if (await _storage.containsKey(key: "refreshToken")) {
      return await _storage.read(key: "refreshToken");
    }
  }

  Future<void> _storeRefreshToken(String? refreshToken) async {
    await _storage.write(key: "refreshToken", value: refreshToken);
  }

  Future<void> _clearRefreshToken() async {
    await _storage.delete(key: "refreshToken");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Sample Code'),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder:
                (BuildContext context, BoxConstraints viewportConstraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewportConstraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: <Widget>[
                        Visibility(
                          visible: _isBusy,
                          child: const LinearProgressIndicator(),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            height: 0,
                            child: WebViewWidget(
                              controller: _webViewController,
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
        ));
  }

  Future<void> signOut() async {
    try {
      await _session.endSession();
    } catch (e) {
      _session.clear();
      _clearSessionCookies();
      _clearRefreshToken();
      throw SessionException("Logout failed.");
    }
  }

  void _clearBusyState() {
    setState(() {
      _isBusy = false;
    });
  }

  void _setBusyState() {
    setState(() {
      _isBusy = true;
    });
  }

  void _showDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDialog(
        context: context,
        builder: (BuildContext context) => Center(
          child: AlertDialog(
            title: const Text('Welcome'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  _session.signInWithAutoCodeExchange().then((value) {});
                  Navigator.of(context).pop();
                },
              ),
            ],
            insetPadding: const EdgeInsets.all(20),
            contentPadding: const EdgeInsets.all(20),
            content: const Text('Seja je žal potekla!'),
          ),
        ),
      );
    });
  }

  Future<void> _storeSessionCookies(List<Cookie> cookies) async {
    for (var cookie in cookies) {
      var webCookie = WebViewCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain ?? _siteDomain,
        path: cookie.path ?? "/",
      );
      await _cookieManager.setCookie(webCookie);
    }
  }

  Future<void> _clearSessionCookies() async {
    await _cookieManager.clearCookies();
  }
}
