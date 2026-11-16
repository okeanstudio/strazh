import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strazh/features/home/presentation/screens/home.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/auth/data/services/phone_login_service.dart';

const _background = Color(0xFF000000);
const _surface = Color(0xFF1C1C1E);
const _separator = Color(0xFF2C2C2E);
const _accent = Color(0xFF568AF2);

String _countryCodeDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

int _maxNationalNumberDigits(String countryCode) {
  const maxDigitsByCountryCode = <String, int>{
    '1': 10,
    '7': 10,
    '27': 9,
    '31': 9,
    '32': 9,
    '33': 9,
    '34': 9,
    '39': 11,
    '41': 9,
    '43': 13,
    '44': 10,
    '46': 13,
    '47': 8,
    '48': 9,
    '49': 13,
    '52': 10,
    '54': 10,
    '55': 11,
    '61': 9,
    '81': 10,
    '82': 11,
    '86': 11,
    '90': 10,
    '91': 10,
    '351': 9,
    '358': 12,
    '373': 8,
    '375': 9,
    '380': 9,
    '420': 9,
    '888': 8,
    '972': 9,
    '971': 9,
    '995': 9,
    '994': 9,
    '996': 9,
    '992': 9,
    '998': 9,
    '374': 8,
  };
  return maxDigitsByCountryCode[countryCode] ?? 0;
}

List<_PhoneCountry> _countriesForCode(String digits) {
  final matches =
      _countries.where((country) => digits.startsWith(country.code)).toList()
        ..sort((a, b) => b.code.length.compareTo(a.code.length));
  return matches;
}

_PhoneCountry _countryForDigits(String digits, _PhoneCountry current) {
  final matches = _countriesForCode(digits);
  if (matches.isEmpty) {
    return current;
  }
  return matches.where((country) => country.code == current.code).firstOrNull ??
      matches.first;
}

String _formatNationalNumber(String digits) {
  final groups = <String>[];
  var offset = 0;
  while (offset < digits.length) {
    final remaining = digits.length - offset;
    final groupLength = remaining > 7
        ? 3
        : remaining > 4
        ? 3
        : remaining;
    groups.add(digits.substring(offset, offset + groupLength));
    offset += groupLength;
  }
  return groups.join(' ');
}

String _formatAnonymousNumber(String digits) {
  final groups = <String>[];
  for (var offset = 0; offset < digits.length; offset += 4) {
    final end = (offset + 4).clamp(0, digits.length);
    groups.add(digits.substring(offset, end));
  }
  return groups.join(' ');
}

class _PhoneCountry {
  const _PhoneCountry(
    this.name,
    this.code,
    this.flag, {
    this.isAnonymous = false,
  });

  final String name;
  final String code;
  final String flag;
  final bool isAnonymous;
}

const _countries = <_PhoneCountry>[
  _PhoneCountry('Россия', '7', '🇷🇺'),
  _PhoneCountry('Соединенные Штаты Америки', '1', '🇺🇸'),
  _PhoneCountry('Канада', '1', '🇨🇦'),
  _PhoneCountry('Казахстан', '7', '🇰🇿'),
  _PhoneCountry('Украина', '380', '🇺🇦'),
  _PhoneCountry('Беларусь', '375', '🇧🇾'),
  _PhoneCountry('Узбекистан', '998', '🇺🇿'),
  _PhoneCountry('Грузия', '995', '🇬🇪'),
  _PhoneCountry('Армения', '374', '🇦🇲'),
  _PhoneCountry('Азербайджан', '994', '🇦🇿'),
  _PhoneCountry('Кыргызстан', '996', '🇰🇬'),
  _PhoneCountry('Таджикистан', '992', '🇹🇯'),
  _PhoneCountry('Молдова', '373', '🇲🇩'),
  _PhoneCountry('Великобритания', '44', '🇬🇧'),
  _PhoneCountry('Германия', '49', '🇩🇪'),
  _PhoneCountry('Франция', '33', '🇫🇷'),
  _PhoneCountry('Италия', '39', '🇮🇹'),
  _PhoneCountry('Испания', '34', '🇪🇸'),
  _PhoneCountry('Португалия', '351', '🇵🇹'),
  _PhoneCountry('Нидерланды', '31', '🇳🇱'),
  _PhoneCountry('Бельгия', '32', '🇧🇪'),
  _PhoneCountry('Швейцария', '41', '🇨🇭'),
  _PhoneCountry('Австрия', '43', '🇦🇹'),
  _PhoneCountry('Польша', '48', '🇵🇱'),
  _PhoneCountry('Чехия', '420', '🇨🇿'),
  _PhoneCountry('Швеция', '46', '🇸🇪'),
  _PhoneCountry('Норвегия', '47', '🇳🇴'),
  _PhoneCountry('Финляндия', '358', '🇫🇮'),
  _PhoneCountry('Турция', '90', '🇹🇷'),
  _PhoneCountry('Израиль', '972', '🇮🇱'),
  _PhoneCountry('ОАЭ', '971', '🇦🇪'),
  _PhoneCountry('Индия', '91', '🇮🇳'),
  _PhoneCountry('Китай', '86', '🇨🇳'),
  _PhoneCountry('Япония', '81', '🇯🇵'),
  _PhoneCountry('Южная Корея', '82', '🇰🇷'),
  _PhoneCountry('Австралия', '61', '🇦🇺'),
  _PhoneCountry('Бразилия', '55', '🇧🇷'),
  _PhoneCountry('Мексика', '52', '🇲🇽'),
  _PhoneCountry('Аргентина', '54', '🇦🇷'),
  _PhoneCountry('ЮАР', '27', '🇿🇦'),
  _PhoneCountry('Анонимный номер', '888', '🏴‍☠️', isAnonymous: true),
];

class _NationalPhoneFormatter extends TextInputFormatter {
  _NationalPhoneFormatter(this.countryCode, this.isAnonymousNumber);

  final String Function() countryCode;
  final bool Function() isAnonymousNumber;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final inputDigits = _countryCodeDigits(newValue.text);
    final maxDigits = _maxNationalNumberDigits(countryCode());
    final digits = inputDigits.length > maxDigits
        ? inputDigits.substring(0, maxDigits)
        : inputDigits;
    if (digits.isEmpty) {
      return const TextEditingValue();
    }

    final selectionOffset = newValue.selection.isValid
        ? newValue.selection.extentOffset.clamp(0, newValue.text.length)
        : newValue.text.length;
    final digitsBeforeCursor = _countryCodeDigits(
      newValue.text.substring(0, selectionOffset),
    ).length.clamp(0, maxDigits);
    final formatted = isAnonymousNumber()
        ? _formatAnonymousNumber(digits)
        : _formatNationalNumber(digits);
    var outputOffset = 0;
    var seenDigits = 0;
    while (outputOffset < formatted.length && seenDigits < digitsBeforeCursor) {
      if (RegExp(r'\d').hasMatch(formatted[outputOffset])) {
        seenDigits++;
      }
      outputOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: outputOffset),
    );
  }
}

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _countryCodeController = TextEditingController(text: '7');
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  _PhoneCountry _country = _countries.first;

  @override
  void dispose() {
    _countryCodeController.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _onCountryCodeChanged(String value) {
    final digits = _countryCodeDigits(value);
    if (digits.isEmpty) {
      setState(() {});
      return;
    }
    final candidates = _countriesForCode(digits);
    if (candidates.isNotEmpty) {
      setState(() => _country = _countryForDigits(digits, _country));
      _limitPhoneNumberLength();
    } else {
      setState(() {});
    }
  }

  void _limitPhoneNumberLength() {
    final digits = _countryCodeDigits(_phoneController.text);
    final maxDigits = _maxNationalNumberDigits(
      _countryCodeDigits(_countryCodeController.text),
    );
    final truncated = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;
    final formatted = _country.isAnonymous
        ? _formatAnonymousNumber(truncated)
        : _formatNationalNumber(truncated);
    if (_phoneController.text == formatted) {
      return;
    }
    _phoneController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _onPhoneChanged(String _) {
    setState(() {});
  }

  void _setCountry(_PhoneCountry country) {
    setState(() {
      _country = country;
      _countryCodeController.value = TextEditingValue(
        text: country.code,
        selection: TextSelection.collapsed(offset: country.code.length),
      );
    });
    _limitPhoneNumberLength();
  }

  Future<void> _chooseCountry() async {
    FocusScope.of(context).unfocus();
    final country = await showModalBottomSheet<_PhoneCountry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => const _CountryPickerSheet(),
    );
    if (country != null && mounted) {
      _setCountry(country);
    }
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    final countryCode = _countryCodeDigits(_countryCodeController.text);
    final nationalNumber = _countryCodeDigits(_phoneController.text);
    if (_countriesForCode(countryCode).isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Проверьте код страны')));
      return;
    }
    final maxDigits = _maxNationalNumberDigits(countryCode);
    if (nationalNumber.length < 6 || nationalNumber.length > maxDigits) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Проверьте номер телефона')));
      return;
    }

    final formattedNationalNumber = countryCode == '888'
        ? _formatAnonymousNumber(nationalNumber)
        : _formatNationalNumber(nationalNumber);
    final fullNumber = '+$countryCode $formattedNationalNumber';
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _ConfirmPhoneSheet(
        phoneNumber: fullNumber,
        onEdit: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhoneCodeEntryScreen(phoneNumber: fullNumber),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final countryCode = _countryCodeDigits(_countryCodeController.text);
    final nationalNumber = _countryCodeDigits(_phoneController.text);
    final maxDigits = _maxNationalNumberDigits(countryCode);
    final canContinue =
        _countriesForCode(countryCode).isNotEmpty &&
        nationalNumber.length >= 6 &&
        nationalNumber.length <= maxDigits;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          child: Column(
            children: [
              const Text('☎️', style: TextStyle(fontSize: 76, height: 1.15)),
              const SizedBox(height: 22),
              const Text(
                'Телефон',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Введите свой номер телефона',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 17),
              ),
              if (_country.isAnonymous) ...[
                const SizedBox(height: 8),
                const Text(
                  'Анонимный номер',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _accent, fontSize: 14),
                ),
              ],
              const SizedBox(height: 32),
              InkWell(
                onTap: _chooseCountry,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  child: Row(
                    children: [
                      Text(_country.flag, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _country.name,
                          style: const TextStyle(color: _accent, fontSize: 18),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white54,
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(color: _separator, height: 1),
              Row(
                children: [
                  const Text(
                    '+',
                    style: TextStyle(color: Colors.white, fontSize: 21),
                  ),
                  SizedBox(
                    width: 48,
                    child: TextField(
                      controller: _countryCodeController,
                      onChanged: _onCountryCodeChanged,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 21),
                      decoration: const InputDecoration(
                        filled: false,
                        fillColor: _background,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 44, color: _separator),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      onChanged: _onPhoneChanged,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        _NationalPhoneFormatter(
                          () => _countryCodeDigits(_countryCodeController.text),
                          () =>
                              _countryCodeDigits(_countryCodeController.text) ==
                              '888',
                        ),
                      ],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        letterSpacing: 1,
                      ),
                      decoration: const InputDecoration(
                        filled: false,
                        fillColor: _background,
                        hintText: 'Номер телефона',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: _separator, height: 1),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: canContinue ? _continue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _surface,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Продолжить',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Страна определяется по коду номера. SMS сейчас не отправляется.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final countries = _countries.where((country) {
      return country.name.toLowerCase().contains(query) ||
          country.code.contains(query.replaceAll('+', ''));
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Выберите страну',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Поиск страны или кода',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: countries.length,
              itemBuilder: (context, index) {
                final country = countries[index];
                return ListTile(
                  leading: Text(
                    country.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    country.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: Text(
                    '+${country.code}',
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  onTap: () => Navigator.pop(context, country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmPhoneSheet extends StatelessWidget {
  const _ConfirmPhoneSheet({
    required this.phoneNumber,
    required this.onEdit,
    required this.onConfirm,
  });

  final String phoneNumber;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            phoneNumber,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Правильно ли указан номер?',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          TextButton(
            onPressed: onEdit,
            child: const Text(
              'Изменить',
              style: TextStyle(color: _accent, fontSize: 18),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Продолжить',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhoneCodeEntryScreen extends StatefulWidget {
  const PhoneCodeEntryScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  State<PhoneCodeEntryScreen> createState() => _PhoneCodeEntryScreenState();
}

class _PhoneCodeEntryScreenState extends State<PhoneCodeEntryScreen> {
  final _codeController = TextEditingController();
  final _phoneLoginService = PhoneLoginService();
  String? _requestId;
  String? _requestError;
  bool _isRequestingCode = true;
  bool _isCheckingCode = false;
  bool _codeVerified = false;
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _requestLoginCode();
  }

  Future<void> _requestLoginCode() async {
    setState(() {
      _isRequestingCode = true;
      _requestError = null;
      _requestId = null;
      _codeController.clear();
      _codeVerified = false;
      _codeError = null;
    });
    try {
      final requestId = await _phoneLoginService.requestCode(
        widget.phoneNumber,
      );
      if (mounted) {
        setState(() {
          _requestId = requestId;
          _isRequestingCode = false;
        });
      }
    } catch (error) {
      debugPrint('Не удалось запросить код входа: $error');
      if (mounted) {
        setState(() {
          _requestError = 'Не удалось отправить запрос. Попробуйте ещё раз.';
          _isRequestingCode = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final requestId = _requestId;
    if (requestId == null || _codeController.text.length != 6) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isCheckingCode = true;
      _codeError = null;
    });

    try {
      final response = await _phoneLoginService.verifyCode(
        requestId: requestId,
        code: _codeController.text,
      );
      final session = response.session;
      final user = response.user;
      if (session == null || user == null) {
        throw StateError('Supabase не создал сессию после подтверждения');
      }
      if (!mounted) return;
      setState(() {
        _isCheckingCode = false;
        _codeVerified = true;
        _codeError = null;
      });
      await AuthService().saveUser(
        user.userMetadata?['tag'] as String? ?? '',
        user.id,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (error) {
      debugPrint('Не удалось проверить тестовый код: $error');
      if (mounted) {
        setState(() {
          _isCheckingCode = false;
          _codeError = 'Не удалось проверить код. Попробуйте ещё раз.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          child: Column(
            children: [
              const Text('🔐', style: TextStyle(fontSize: 72, height: 1.2)),
              const SizedBox(height: 22),
              const Text(
                'Введите код',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Номер ${widget.phoneNumber}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Откройте чат «Коды входа» аккаунта и введите код из сообщения.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Код появится там, только если этот номер привязан к аккаунту. SMS и письма не отправляются.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (_isRequestingCode) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: _accent),
              ],
              if (_requestError != null) ...[
                const SizedBox(height: 14),
                Text(
                  _requestError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                TextButton(
                  onPressed: _requestLoginCode,
                  child: const Text('Повторить'),
                ),
              ],
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                enabled:
                    _requestId != null && !_isCheckingCode && !_codeVerified,
                autofocus: true,
                onChanged: (_) => setState(() => _codeError = null),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: '• • • • • •',
                  hintStyle: const TextStyle(
                    color: Colors.white30,
                    fontSize: 22,
                    letterSpacing: 5,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: _surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _separator),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _accent, width: 1.5),
                  ),
                ),
              ),
              if (_codeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _codeError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed:
                      _requestId != null &&
                          _codeController.text.length == 6 &&
                          !_isCheckingCode &&
                          !_codeVerified
                      ? _verifyCode
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _surface,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                    shape: const StadiumBorder(),
                  ),
                  child: _isCheckingCode
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _codeVerified ? 'Код принят' : 'Подтвердить код',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
