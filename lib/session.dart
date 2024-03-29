import 'dart:ffi';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:flutter_appauth/flutter_appauth.dart';

class Session {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  String? _codeVerifier;
  String? _nonce;
  String? _authorizationCode;
  String? _refreshToken;
  String? _accessToken;
  String? _idToken;
  bool _isValid = false;
  bool _isAuthenticating = false;

  get isValid {
    return _isValid;
  }

  get isAuthenticating {
    return _isAuthenticating;
  }

  final String _clientId = 'test-client';
  final String _redirectUrl = 'com.duendesoftware.demo:/oauthredirect';
  final String _issuer = 'https://prijava.telekom.si/prijava/realms/telekom';
  final String _discoveryUrl =
      'https://prijava.telekom.si/prijava/realms/telekom/.well-known/openid-configuration';
  final String _logoutUrl =
      "https://prijava.telekom.si/prijava/realms/telekom/protocol/openid-connect/logout";
  final String _postLogoutRedirectUrl = 'com.duendesoftware.demo:/';
  final List<String> _scopes = <String>[
    'openid',
//    'profile',
//    'email',
//    'offline_access',
//    'api'
  ];

  final String _sessionUrl =
      "https://moj.telekom.si/sc-api/api/SessionProvider/GetMtSession";

  String? get refreshToken {
    return _refreshToken;
  }

  Future<bool> refreshTokens(String? refreshToken) async {
    _isValid = false;
    final TokenResponse? result = await _appAuth.token(TokenRequest(
        _clientId, _redirectUrl,
        refreshToken: refreshToken, issuer: _issuer, scopes: _scopes));
    if (result != null) {
      _processTokenResponse(result);
      _isValid = true;
      return true;
    }
    return false;
  }

  Future<String?> signInWithAutoCodeExchange(
      {bool preferEphemeralSession = false}) async {
    _isAuthenticating = true;
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
    if (result != null) {
      _processAuthTokenResponse(result);
      _isAuthenticating = false;
      _isValid = true;
      return _refreshToken;
    }
    _isAuthenticating = false;
    _isValid = false;
    return null;
  }

  Future<bool> endSessionBrowser() async {
    if (_idToken != null) {
      await _appAuth.endSession(EndSessionRequest(
        idTokenHint: _idToken,
        issuer: _issuer,
        postLogoutRedirectUrl: _postLogoutRedirectUrl,
      ));
      await clear();
      _isValid = false;
      return true;
    }
    return false;
  }

  Future<bool> endSession() async {
    try {
      http.Response response = await http.post(
        Uri.parse(_logoutUrl),
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $_refreshToken',
          // replace 'YOUR_TOKEN' with your actual token
        },
        body:
            'client_id=${Uri.encodeQueryComponent(_clientId)}&refresh_token=${Uri.encodeQueryComponent(_refreshToken ?? "")}',
      );
      if (response.statusCode == HttpStatus.noContent) {
        _isValid = false;
        return true;
      }
      return false;
    } catch (e) {
      throw SessionException("Failed to log out user.");
    }
  }

  Future<void> clear() async {
    _codeVerifier = null;
    _nonce = null;
    _authorizationCode = null;
    _accessToken = null;
    _idToken = null;
    _refreshToken = null;
    _isValid = false;
    _isAuthenticating = false;
  }

  void _processAuthTokenResponse(AuthorizationTokenResponse response) {
    _accessToken = response.accessToken!;
    _idToken = response.idToken!;
    _refreshToken = response.refreshToken!;
  }

  void _processAuthResponse(AuthorizationResponse response) {
    _codeVerifier = response.codeVerifier;
    _nonce = response.nonce;
    _authorizationCode = response.authorizationCode!;
  }

  void _processTokenResponse(TokenResponse? response) {
    _accessToken = response!.accessToken!;
    _idToken = response.idToken!;
    _refreshToken = response.refreshToken!;
  }

  Future<List<Cookie>> getMTSession() async {
    try {
      await refreshTokens(_refreshToken);
      HttpClient client = HttpClient();
      HttpClientRequest request = await client.getUrl(Uri.parse(_sessionUrl));
      request.headers.set("Authorization", "Bearer $_accessToken");
      var response = await request.close();
      if (response.statusCode == 204) {
        return response.cookies;
      } else {
        return <Cookie>[];
      }
    } catch (e) {
      throw SessionException("Failed to get MT session cookies.");
    }
  }
}

class SessionException implements Exception {
  final String message;

  SessionException(this.message);

  @override
  String toString() {
    return "SessionException: $message";
  }
}
