import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth_example/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
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
            var result = signIn();
            setState(() {});
            if (await result) {
              await _webViewController.loadRequest(Uri.parse(_siteUrl));
            }
            return NavigationDecision.prevent;
          } catch (_) {
            return NavigationDecision.prevent;
          }
        }
        return NavigationDecision.navigate;
      },
      onPageStarted: (navigation) {
        _setBusyState();
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
      // Check if refresh token exists
      if (await _storage.containsKey(key: "refreshToken")) {
        //check owner presence with biometrics
        setState(() {
          _isAuthenticating = true;
        });
        await _authenticate();
        if (!(_authorized == "Authorized")) {
          //presence check failed
          _clearAll();
          setState(() {
            _isAuthenticating = false;
          });
          return false;
        }
        _setBusyState();
        //Check SSO session and try to refresh SSO token
        if (!await _session.refreshTokens(await _loadRefreshToken())) {
          //SSO session is not valid
          _isAuthenticating = false;
          _clearBusyState();
          return false;
        }
        await _cookieManager.clearCookies();

        // SSO session is valid, store SSO tokens
        await _storeRefreshToken(_session.refreshToken);
        // Retrieve MT session cookies and store them
        await _storeSessionCookies(await _session.getMTSession());
        _isAuthenticating = false;
        await _webViewController.loadRequest(Uri.parse(_siteUrl));
        //do not clear busy state, wait web page to finish loading
        // _clearBusyState();
        return true;
      }
    } catch (e) {
      await _clearAll();

      _clearBusyState();
    }
    return false;
  }

  Future<bool> signIn() async {
    try {
      Future<String?> result = _session.signInWithAutoCodeExchange();
      _setBusyState();
      await result;
      await _storeRefreshToken(_session.refreshToken);
      await _storeSessionCookies(await _session.getMTSession());
      //let operation after signIn clear busy state
      //_clearBusyState();
      return true;
    } catch (e) {
      await _clearAll();
      _clearBusyState();
      throw SessionException("Failed to sign in.");
    }
  }

  Future<void> signOut() async {
    try {
      _setBusyState();
      if (await _session.endSession()) {
        await _clearAll();
      }
      _clearBusyState();
    } catch (e) {
      await _clearAll();
      _clearBusyState();
      throw SessionException("Failed to logout.");
    }
  }

  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      _authorized = 'Authenticating';
      authenticated = await auth.authenticate(
        localizedReason: 'Izberi način prijave',
        authMessages: const <AuthMessages>[
        AndroidAuthMessages(
          signInTitle: "Oops! Biometric authentication required!",
          biometricHint: "Kdo si?",
          cancelButton: "No thanks",
        ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      _authorized = 'Error - ${e.message}';
      return;
    }
    if (!mounted) {
      return;
    }
    _authorized = authenticated ? 'Authorized' : 'Not Authorized';
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
          builder: (BuildContext context, BoxConstraints viewportConstraints) {
            if (_session.isAuthenticating || _isAuthenticating) {
              return const Center(
                child: Text("Prijava v teku ..."),
              );
            } else if (_session.isValid) {
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
            } else {
              return const Center(
                child: Text("Prijavi se!"),
              );
            }
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.login), label: ""),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: ""),
        ],
        onTap: (index) async {
          switch (index) {
            case 0:
              var result = signIn();
              setState(() {});
              await result;
              await _webViewController.loadRequest(Uri.parse(_siteUrl));
              break;
            case 1:
              var result = signOut();
              setState(() {});
              await result;
              //we force login again
              await _webViewController.loadRequest(Uri.parse(_siteUrl));
              break;
          }
        },
      ),
    );
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

  Future<void> _clearAll() async {
    await _session.clear();
    await _clearSessionCookies();
    await _clearRefreshToken();
    _isAuthenticating = false;
  }
}
