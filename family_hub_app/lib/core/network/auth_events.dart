import 'dart:async';

/// App-wide authentication events emitted by the networking layer.
///
/// `AuthInterceptor` emits [sessionExpired] after a failed token refresh (it
/// has already cleared the stored tokens). `SessionController` listens and
/// switches to the signed-out state, which makes the router show `/login`.
class AuthEvents {
  final _sessionExpired = StreamController<void>.broadcast();

  Stream<void> get sessionExpired => _sessionExpired.stream;

  void emitSessionExpired() {
    if (!_sessionExpired.isClosed) _sessionExpired.add(null);
  }

  Future<void> dispose() => _sessionExpired.close();
}
