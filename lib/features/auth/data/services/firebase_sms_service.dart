import 'package:firebase_auth/firebase_auth.dart';

class FirebaseSmsService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String verificationId = '';

  Future<void> sendVerificationCode(
    String phoneNumber,
    Function(String) onCodeSent,
    Function(String) onError,
  ) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          onCodeSent('auto_verified');
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Ошибка отправки');
        },
        codeSent: (String verificationId, int? resendToken) {
          this.verificationId = verificationId;
          onCodeSent('code_sent');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          this.verificationId = verificationId;
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<bool> verifyCode(
    String smsCode,
    Function(String) onError,
  ) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await _auth.signInWithCredential(credential);
      return true;
    } catch (e) {
      if (e is FirebaseAuthException) {
        onError(e.message ?? 'Ошибка верификации');
      } else {
        onError(e.toString());
      }
      return false;
    }
  }
}