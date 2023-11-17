import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

void main() => runApp(MaterialApp(home: MyApp()));

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
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final _storage = const FlutterSecureStorage();
  String? _codeVerifier;
  String? _nonce;
  String? _authorizationCode;
  String? _refreshToken;
  String? _accessToken;
  String? _idToken;

  final LocalAuthentication auth = LocalAuthentication();
  _SupportState _supportState = _SupportState.unknown;
  String _authorized = 'Not Authorized';
  bool _isAuthenticating = false;

  final TextEditingController _authorizationCodeTextController =
      TextEditingController();
  final TextEditingController _accessTokenTextController =
      TextEditingController();
  final TextEditingController _accessTokenExpirationTextController =
      TextEditingController();
  final TextEditingController _idTokenTextController = TextEditingController();
  final TextEditingController _refreshTokenTextController =
      TextEditingController();
  final TextEditingController _refreshTokenExpirationTextController =
      TextEditingController();
  String? _userInfo;

  // For a list of client IDs, go to https://demo.duendesoftware.com
  final String _clientId = 'test-client';
  final String _redirectUrl = 'com.duendesoftware.demo:/oauthredirect';

  // final String _issuer = 'https://p71-pc.fritz.box/auth/realms/test';
  // final String _discoveryUrl =
  //     'https://p71-pc.fritz.box/auth/realms/test/.well-known/openid-configuration';
  final String _issuer = 'https://prijava.telekom.si/prijava/realms/telekom';
  final String _discoveryUrl =
      'https://prijava.telekom.si/prijava/realms/telekom/.well-known/openid-configuration';
  final String _postLogoutRedirectUrl = 'com.duendesoftware.demo:/';
  final List<String> _scopes = <String>[
    'openid',
//    'profile',
//    'email',
//    'offline_access',
//    'api'
  ];

  @override
  void initState() {
    super.initState();
    _storage.containsKey(key: "refreshToken").then((value) {
      if (value) {
        _authenticate().then((value) {
          _loadRefreshToken().then((value) {
            _refresh().then((value) {
              if (value) {
                _clearBusyState();
              } else {
                _showDialog();
              }
            });
          });
        });
      } else {
        _signInWithAutoCodeExchange().then((value) {});
      }
    });
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
      print(e);
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

  Future<void> _loadRefreshToken() async {
    if (await _storage.containsKey(key: "refreshToken")) {
      _refreshToken = await _storage.read(key: "refreshToken");
    }
  }

  Future<void> _storeRefreshToken(String? refreshToken) async {
    await _storage.write(key: "refreshToken", value: refreshToken);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Visibility(
                visible: _isBusy,
                child: const LinearProgressIndicator(),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                child: const Text('Sign in with auto code exchange'),
                onPressed: () => _signInWithAutoCodeExchange(),
              ),
              ElevatedButton(
                onPressed: _refreshToken != null ? _refresh : null,
                child: const Text('Refresh token'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _idToken != null
                    ? () async {
                        await _endSession();
                      }
                    : null,
                child: const Text('End session'),
              ),
              ElevatedButton(
                onPressed: _authenticate,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Authenticate'),
                    Icon(Icons.perm_device_information),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('authorization code'),
              TextField(
                controller: _authorizationCodeTextController,
              ),
              const Text('access token'),
              TextField(
                controller: _accessTokenTextController,
              ),
              const Text('access token expiration'),
              TextField(
                controller: _accessTokenExpirationTextController,
              ),
              const Text('id token'),
              TextField(
                controller: _idTokenTextController,
              ),
              const Text('refresh token'),
              TextField(
                controller: _refreshTokenTextController,
              ),
              const Text('refresh token expiration'),
              TextField(
                controller: _refreshTokenExpirationTextController,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _endSession() async {
    try {
      _setBusyState();
      await _appAuth.endSession(EndSessionRequest(
        idTokenHint: _idToken,
        issuer: _issuer,
        postLogoutRedirectUrl: _postLogoutRedirectUrl,
      ));
      await _clearSessionInfo();
    } catch (_) {}
    _clearBusyState();
  }

  Future<void> _clearSessionInfo() async {
    setState(() {
      _codeVerifier = null;
      _nonce = null;
      _authorizationCode = null;
      _authorizationCodeTextController.clear();
      _accessToken = null;
      _accessTokenTextController.clear();
      _idToken = null;
      _idTokenTextController.clear();
      _refreshToken = null;
      _refreshTokenTextController.clear();
      _accessTokenExpirationTextController.clear();
      _refreshTokenExpirationTextController.clear();
      _userInfo = null;
    });
    await _storage.delete(key: "refreshToken");
  }

  Future<bool> _refresh() async {
    try {
      _setBusyState();
      final TokenResponse? result = await _appAuth.token(TokenRequest(
          _clientId, _redirectUrl,
          refreshToken: _refreshToken, issuer: _issuer, scopes: _scopes));
      _processTokenResponse(result);
      _storeRefreshToken(_refreshToken);
      _clearBusyState();
    } catch (_) {
      _clearSessionInfo();
      _clearBusyState();
      return false;
    }
    return true;
  }

  Future<void> _signInWithAutoCodeExchange(
      {bool preferEphemeralSession = false}) async {
    try {
      _setBusyState();

      /*
        This shows that we can also explicitly specify the endpoints rather than
        getting from the details from the discovery document.
      */
      final AuthorizationTokenResponse? result =
          await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUrl,
          issuer: _issuer,
          scopes: _scopes,
          promptValues: ["login"],
          additionalParameters: {"max_age": "0"},
          preferEphemeralSession: preferEphemeralSession,
        ),
      );

      /*
        This code block demonstrates passing in values for the prompt
        parameter. In this case it prompts the user login even if they have
        already signed in. the list of supported values depends on the
        identity provider

        ```dart
        final AuthorizationTokenResponse result = await _appAuth
        .authorizeAndExchangeCode(
          AuthorizationTokenRequest(_clientId, _redirectUrl,
              serviceConfiguration: _serviceConfiguration,
              scopes: _scopes,
              promptValues: ['login']),
        );
        ```
      */

      if (result != null) {
        _processAuthTokenResponse(result);
        _storeRefreshToken(_refreshToken);
        _clearBusyState();
      }
    } catch (_) {
      _clearBusyState();
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

  void _processAuthTokenResponse(AuthorizationTokenResponse response) {
    setState(() {
      _accessToken = _accessTokenTextController.text = response.accessToken!;
      _idToken = _idTokenTextController.text = response.idToken!;
      _refreshToken = _refreshTokenTextController.text = response.refreshToken!;
      _accessTokenExpirationTextController.text =
          response.accessTokenExpirationDateTime!.toIso8601String();
      DateTime? ret = _parseJSONWebTokenExpirationTime(response.refreshToken);
      _refreshTokenExpirationTextController.text =
          (ret == null) ? "" : ret.toIso8601String();
    });
  }

  void _processAuthResponse(AuthorizationResponse response) {
    setState(() {
      /*
        Save the code verifier and nonce as it must be used when exchanging the
        token.
      */
      _codeVerifier = response.codeVerifier;
      _nonce = response.nonce;
      _authorizationCode =
          _authorizationCodeTextController.text = response.authorizationCode!;
      _isBusy = false;
    });
  }

  void _processTokenResponse(TokenResponse? response) {
    setState(() {
      _accessToken = _accessTokenTextController.text = response!.accessToken!;
      _idToken = _idTokenTextController.text = response.idToken!;
      _refreshToken = _refreshTokenTextController.text = response.refreshToken!;
      _accessTokenExpirationTextController.text =
          response.accessTokenExpirationDateTime!.toIso8601String();
      DateTime? ret = _parseJSONWebTokenExpirationTime(response.refreshToken);
      _refreshTokenExpirationTextController.text =
          (ret == null) ? "" : ret.toIso8601String();
    });
  }

  void _showDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await showDialog(
        context: context,
        builder: (BuildContext context) => Center(
          child: AlertDialog(
            title: Text('Welcome'),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  _signInWithAutoCodeExchange().then((value) {});
                  Navigator.of(context).pop();
                },
              ),
            ],
            insetPadding: EdgeInsets.all(20),
            contentPadding: EdgeInsets.all(20),
            content: Text('Seja je žal potekla!'),
          ),
        ),
      );
    });
  }
}

DateTime? _parseJSONWebTokenExpirationTime(String? token) {
  if (token == null) return null;

  List<String> parts = token.split(".");

  if (parts.length != 3) {
    throw Exception("Invalid token");
  }

  String payload = parts[1];
  String normalizedPayload = base64Url.normalize(payload);
  String decodedPayload = utf8.decode(base64Url.decode(normalizedPayload));

  Map<String, dynamic> payloadMap = jsonDecode(decodedPayload);

  if (payloadMap.containsKey("exp")) {
    int timestamp = payloadMap["exp"];
    DateTime expirationDate =
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return expirationDate;
  } else {
    return null;
  }
}
