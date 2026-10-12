import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:re_v/l10n/app_localizations.dart';
import '../../../core/l10n/app_localizations_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/document_picker.dart';
import '../../../core/utils/guest_session.dart';
import '../../../core/widgets/rev_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PartnerRegistrationScreen — 5-page stepper
//
// Page 1: Identity   — name, address, email, phone, tier
// Page 2: Photos     — 4 facility photo slots
// Page 3: Documents  — NIB, NPWP, SIUP, KTP
// Page 4: Location   — geolocation + map pin, service radius
// Page 5: Bank+Sign  — bank details, consent, submit
//
// OTP flow:
//   • WhatsApp OTP: send-partner-otp edge fn → verify-partner-otp before submit
//   • Email: Supabase magic-link sent alongside WA OTP; link click flips
//     email_verified flag on partner_applications row
// ─────────────────────────────────────────────────────────────────────────────

enum _VerifyState { idle, sending, sent, verified, failed }

class PartnerRegistrationScreen extends StatefulWidget {
  const PartnerRegistrationScreen({super.key});

  @override
  State<PartnerRegistrationScreen> createState() =>
      _PartnerRegistrationScreenState();
}

class _PartnerRegistrationScreenState extends State<PartnerRegistrationScreen>
    with SingleTickerProviderStateMixin {
  // ── stepper ────────────────────────────────────────────────────────────────
  int _page = 0; // 0-4
  static const int _totalPages = 5;

  final _pageKeys = List.generate(
      _totalPages, (i) => GlobalKey<FormState>(debugLabel: 'page$i'));

  // ── page 1 — identity ──────────────────────────────────────────────────────
  final _entityNameCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController();
  final _picCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _legalAddressCtrl = TextEditingController();
  int _selectedTier = 2;
  final Set<String> _selectedPaints = {'glasurit'};
  final _customPaintCtrl = TextEditingController();
  bool _showCustomPaintField = false;

  // ── page 2 — photos ────────────────────────────────────────────────────────
  final _imagePicker = ImagePicker();
  final List<Uint8List?> _facilityPhotos = [null, null, null, null];

  // ── page 3 — documents ────────────────────────────────────────────────────
  final Map<String, Uint8List?> _docFiles = {
    'nib': null, 'npwp': null, 'siup': null, 'ktp': null,
  };
  final Map<String, String?> _docFileNames = {
    'nib': null, 'npwp': null, 'siup': null, 'ktp': null,
  };

  // ── page 4 — location ──────────────────────────────────────────────────────
  final _workshopAddressCtrl = TextEditingController();
  bool _sameAsLegal = true;
  LatLng? _pin;
  final _mapCtrl = MapController();
  bool _locating = false;
  double _radius = 12;

  // ── page 5 — bank + consent ────────────────────────────────────────────────
  final _bankNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankHolderCtrl = TextEditingController();
  bool _consentChecked = false;

  // ── OTP ───────────────────────────────────────────────────────────────────
  _VerifyState _waVerify = _VerifyState.idle;
  _VerifyState _emailVerify = _VerifyState.idle;
  final _otpCtrl = TextEditingController();
  String? _otpError;

  // ── submission ────────────────────────────────────────────────────────────
  bool _isSubmitting = false;
  String? _submitStage;
  String? _submitError;
  bool _isSuccess = false;

  static const _bucket = 'revive-photos';

  late final AnimationController _anim;

  // ── label helpers ─────────────────────────────────────────────────────────
  List<String> get _photoLabels => [
        'Workshop Facade',
        'Spray / Oven Booth',
        'Customer Lounge',
        'Mixing Station',
      ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final c in [
      _entityNameCtrl, _brandNameCtrl, _picCtrl, _phoneCtrl, _emailCtrl,
      _legalAddressCtrl, _workshopAddressCtrl,
      _bankNameCtrl, _bankAccountCtrl, _bankHolderCtrl, _otpCtrl,
      _customPaintCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  // ── navigation ────────────────────────────────────────────────────────────
  void _next() {
    final form = _pageKeys[_page].currentState;
    if (form != null && !form.validate()) return;
    if (_page < _totalPages - 1) setState(() => _page++);
  }

  void _back() {
    if (_page > 0) setState(() => _page--);
  }

  // ── geolocation ──────────────────────────────────────────────────────────
  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) throw Exception('Location services disabled');
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = ll);
      _mapCtrl.move(ll, 15);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GPS: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── OTP — WhatsApp ─────────────────────────────────────────────────────────
  Future<void> _sendWaOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _waVerify = _VerifyState.sending; _otpError = null; });
    try {
      await Supabase.instance.client.functions.invoke(
        'send-partner-otp',
        body: {'phone': phone, 'channel': 'whatsapp'},
      );
      setState(() => _waVerify = _VerifyState.sent);
    } catch (e) {
      setState(() { _waVerify = _VerifyState.failed; _otpError = e.toString(); });
    }
  }

  Future<void> _verifyWaOtp() async {
    final phone = _phoneCtrl.text.trim();
    final code = _otpCtrl.text.trim();
    if (code.length != 6) return;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'verify-partner-otp',
        body: {'phone': phone, 'code': code},
      );
      final ok = (res.data as Map?)?['verified'] == true;
      setState(() {
        _waVerify = ok ? _VerifyState.verified : _VerifyState.failed;
        _otpError = ok ? null : 'Kode OTP salah / expired';
      });
    } catch (e) {
      setState(() { _waVerify = _VerifyState.failed; _otpError = e.toString(); });
    }
  }

  // ── OTP — Email ────────────────────────────────────────────────────────────
  Future<void> _sendEmailOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _emailVerify = _VerifyState.sending);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false, // only verification, no account creation here
      );
      setState(() => _emailVerify = _VerifyState.sent);
    } catch (e) {
      // If user doesn't exist we still show "sent" — don't leak existence
      setState(() => _emailVerify = _VerifyState.sent);
    }
  }

  // ── photo picker ──────────────────────────────────────────────────────────
  Future<void> _pickPhoto(int i) async {
    final f = await _imagePicker.pickImage(
        source: ImageSource.gallery, maxWidth: 1920, imageQuality: 80);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _facilityPhotos[i] = bytes);
  }

  // ── doc picker ────────────────────────────────────────────────────────────
  Future<void> _pickDoc(String key) async {
    final f = await DocumentPicker.pick();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) {
      setState(() {
        _docFiles[key] = bytes;
        _docFileNames[key] = f.name;
      });
    }
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final form = _pageKeys[4].currentState;
    if (form != null && !form.validate()) return;
    if (!_consentChecked) {
      setState(() => _submitError = 'Centang persetujuan terlebih dahulu');
      return;
    }

    void stage(String s) { if (mounted) setState(() => _submitStage = s); }
    setState(() { _isSubmitting = true; _submitError = null; _submitStage = 'Memulai sesi aman…'; });

    try {
      final uid = await GuestSession.ensure();
      if (uid == null) throw Exception('Gagal memulai sesi upload. Coba lagi.');

      final storage = Supabase.instance.client.storage;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = '$uid/partner-applications/$stamp';
      final failed = <String>[];

      // — photos
      final photoKeys = <Map<String, dynamic>>[];
      for (var i = 0; i < _facilityPhotos.length; i++) {
        final bytes = _facilityPhotos[i];
        if (bytes == null) continue;
        stage('Upload foto ${_photoLabels[i]}…');
        final key = '$prefix/facility/slot$i.jpg';
        try {
          await storage.from(_bucket).uploadBinary(key, bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '3600', upsert: false));
          photoKeys.add({'slot': i, 'label': _photoLabels[i], 'file_key': key});
        } catch (e) {
          failed.add(_photoLabels[i]);
        }
      }

      // — documents
      final docKeys = <String, String>{};
      for (final t in _docFiles.keys) {
        final bytes = _docFiles[t];
        if (bytes == null) continue;
        stage('Upload ${t.toUpperCase()}…');
        final name = _docFileNames[t] ?? '$t.pdf';
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'pdf';
        final key = '$prefix/docs/${t}_$stamp.$ext';
        try {
          await storage.from(_bucket).uploadBinary(key, bytes,
              fileOptions: FileOptions(
                  contentType: ext == 'pdf' ? 'application/pdf' : 'image/jpeg',
                  cacheControl: '3600', upsert: false));
          docKeys[t] = key;
        } catch (e) {
          failed.add(t.toUpperCase());
        }
      }

      if (failed.isNotEmpty) {
        throw Exception('Gagal upload: ${failed.join(', ')}. Tidak ada data yang terkirim.');
      }

      stage('Mengirim aplikasi…');

      final FunctionResponse res;
      try {
        res = await Supabase.instance.client.functions.invoke(
          'submit-partner-application',
          body: {
            'entity_name': _entityNameCtrl.text.trim(),
            'shop_name': _brandNameCtrl.text.trim(),
            'owner_name': _picCtrl.text.trim(),
            'email': _emailCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'address': _legalAddressCtrl.text.trim(),
            'workshop_address': _sameAsLegal
                ? _legalAddressCtrl.text.trim()
                : _workshopAddressCtrl.text.trim(),
            'latitude': _pin?.latitude,
            'longitude': _pin?.longitude,
            'tier': _selectedTier,
            'paint_brand': [
              ..._selectedPaints,
              if (_showCustomPaintField && _customPaintCtrl.text.trim().isNotEmpty)
                ..._customPaintCtrl.text.trim().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
            ].join(','),
            'throughput_capacity': 12, // default; not exposed to user
            'service_radius_km': _radius.round(),
            'bank_name': _bankNameCtrl.text.trim(),
            'bank_account_number': _bankAccountCtrl.text.trim(),
            'bank_account_holder': _bankHolderCtrl.text.trim(),
            'nib_file_key': docKeys['nib'],
            'npwp_file_key': docKeys['npwp'],
            'siup_file_key': docKeys['siup'],
            'ktp_file_key': docKeys['ktp'],
            'facility_photo_keys': photoKeys,
            'wa_verified': _waVerify == _VerifyState.verified,
          },
        );
      } on FunctionException catch (e) {
        final details = e.details;
        final msg = details is Map && details['error'] != null
            ? details['error'].toString()
            : 'Pengiriman gagal (${e.status}). Coba lagi.';
        throw Exception(msg);
      }

      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      if (!mounted) return;
      setState(() { _isSubmitting = false; _submitStage = null; _isSuccess = true; });
    } catch (e) {
      debugPrint('partner_registration submit: $e');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStage = null;
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: const ReVAppBar(),
      body: _isSuccess
          ? _buildSuccess(theme, l10n)
          : Column(
              children: [
                _buildHeader(theme, l10n, isNarrow),
                _buildStepper(theme, l10n, isNarrow),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 16 : 32, vertical: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Form(
                          key: _pageKeys[_page],
                          child: _buildPage(theme, l10n),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildNavBar(theme, l10n),
              ],
            ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData t, AppL l, bool narrow) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 32, vertical: 20),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go('/'),
            child: Row(children: [
              Icon(Icons.arrow_back, size: 16, color: t.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(l.partnerRegBreadcrumb, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.partnerRegTitle, style: TextStyle(fontSize: narrow ? 18 : 22, fontWeight: FontWeight.w800, color: t.colorScheme.onSurface)),
                Text(l.partnerRegSubtitle, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── stepper bar ───────────────────────────────────────────────────────────
  static const _stepIcons = [
    Icons.badge, Icons.photo_camera, Icons.folder_copy,
    Icons.location_on, Icons.account_balance,
  ];

  Widget _buildStepper(ThemeData t, AppL l, bool narrow) {
    final labels = [
      l.partnerRegStep1, l.partnerRegStep2, l.partnerRegStep3,
      l.partnerRegStep4, l.partnerRegStep5,
    ];
    return Container(
      color: t.colorScheme.surfaceContainer,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: narrow ? 8 : 24),
      child: Row(
        children: List.generate(_totalPages, (i) {
          final done = i < _page;
          final active = i == _page;
          final col = done
              ? Colors.green
              : active
                  ? AppColors.primaryContainer
                  : t.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (i > 0)
                      Expanded(child: Container(height: 2, color: i <= _page ? AppColors.primaryContainer.withValues(alpha: 0.5) : t.colorScheme.outlineVariant.withValues(alpha: 0.3))),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: done ? Colors.green : active ? AppColors.primaryContainer : t.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(done ? Icons.check : _stepIcons[i], size: 15, color: done || active ? Colors.white : col),
                    ),
                    if (i < _totalPages - 1)
                      Expanded(child: Container(height: 2, color: i < _page ? AppColors.primaryContainer.withValues(alpha: 0.5) : t.colorScheme.outlineVariant.withValues(alpha: 0.3))),
                  ],
                ),
                if (!narrow) ...[
                  const SizedBox(height: 4),
                  Text(labels[i], style: TextStyle(fontSize: 9, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? AppColors.primaryContainer : t.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── page router ───────────────────────────────────────────────────────────
  Widget _buildPage(ThemeData t, AppL l) {
    switch (_page) {
      case 0: return _buildPage1(t, l);
      case 1: return _buildPage2(t, l);
      case 2: return _buildPage3(t, l);
      case 3: return _buildPage4(t, l);
      case 4: return _buildPage5(t, l);
      default: return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE 1 — Identity
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPage1(ThemeData t, AppL l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle(t, Icons.badge, l.partnerRegStep1, l.partnerRegStep1Sub),
        const SizedBox(height: 24),

        // Tier selection
        Text(l.partnerRegTier.toUpperCase(), style: _labelStyle(t)),
        const SizedBox(height: 8),
        _buildTierRow(t, l),
        const SizedBox(height: 20),

        _field(t, l.partnerRegEntityName, _entityNameCtrl, required: true),
        const SizedBox(height: 14),
        _field(t, l.partnerRegBrandName, _brandNameCtrl, required: true),
        const SizedBox(height: 14),
        _field(t, l.partnerRegPic, _picCtrl, required: true),
        const SizedBox(height: 14),
        _field(t, l.partnerRegLegalAddress, _legalAddressCtrl, required: true, maxLines: 2),
        const SizedBox(height: 14),

        // Phone with OTP
        _buildPhoneOtpRow(t, l),
        const SizedBox(height: 14),

        // Email with verification
        _buildEmailVerifyRow(t, l),
        const SizedBox(height: 20),

        // Paint brand
        Text(l.partnerRegPaint.toUpperCase(), style: _labelStyle(t)),
        const SizedBox(height: 8),
        _buildPaintRow(t),
      ],
    );
  }

  Widget _buildPhoneOtpRow(ThemeData t, AppL l) {
    final verified = _waVerify == _VerifyState.verified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _field(t, l.partnerRegPhone, _phoneCtrl,
                  required: true,
                  prefix: '+62',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  suffixIcon: verified
                      ? const Icon(Icons.verified, color: Colors.green, size: 18)
                      : null),
            ),
            const SizedBox(width: 10),
            _otpButton(t, l, _waVerify, _sendWaOtp),
          ],
        ),
        if (_waVerify == _VerifyState.sent) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(t, l.partnerRegOtpCode, _otpCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _verifyWaOtp,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                child: Text(l.partnerRegVerify, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_otpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_otpError!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ),
        ],
        if (_waVerify == _VerifyState.verified)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Text(l.partnerRegPhoneVerified, style: const TextStyle(fontSize: 11, color: Colors.green)),
            ]),
          ),
      ],
    );
  }

  Widget _buildEmailVerifyRow(ThemeData t, AppL l) {
    final sent = _emailVerify == _VerifyState.sent || _emailVerify == _VerifyState.verified;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _field(t, l.partnerRegEmail, _emailCtrl,
                required: true, keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l.partnerRegEmailRequired;
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())) return l.partnerRegEmailInvalid;
                  return null;
                })),
            const SizedBox(width: 10),
            _otpButton(t, l, _emailVerify, _sendEmailOtp),
          ],
        ),
        if (sent)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.mail_outline, size: 14, color: Colors.blue),
              const SizedBox(width: 4),
              Expanded(child: Text(l.partnerRegEmailSent, style: const TextStyle(fontSize: 11, color: Colors.blue))),
            ]),
          ),
      ],
    );
  }

  Widget _otpButton(ThemeData t, AppL l, _VerifyState state, VoidCallback onTap) {
    final loading = state == _VerifyState.sending;
    final done = state == _VerifyState.verified;
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: (loading || done) ? null : onTap,
        style: ElevatedButton.styleFrom(
            backgroundColor: done ? Colors.green : t.colorScheme.surfaceContainerHighest,
            foregroundColor: done ? Colors.white : t.colorScheme.onSurface,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14)),
        child: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(done ? l.partnerRegVerified : l.partnerRegSendOtp, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _buildTierRow(ThemeData t, AppL l) {
    return Row(
      children: [
        _tierCard(t, 1, 'TIER 1', Icons.workspace_premium, l.partnerTier1Name, l.partnerTier1Desc, '85%'),
        const SizedBox(width: 10),
        _tierCard(t, 2, 'TIER 2', Icons.store, l.partnerTier2Name, l.partnerTier2Desc, '82%'),
        const SizedBox(width: 10),
        _tierCard(t, 3, 'TIER 3', Icons.build_circle, l.partnerTier3Name, l.partnerTier3Desc, '80%'),
      ],
    );
  }

  Widget _tierCard(ThemeData t, int tier, String badge, IconData icon, String name, String desc, String rev) {
    final sel = _selectedTier == tier;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTier = tier),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sel ? t.colorScheme.surfaceContainerHighest : t.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: sel ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.5), width: 1.5) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: sel ? AppColors.primaryContainer : t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                  child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sel ? Colors.white : t.colorScheme.onSurface)),
                ),
                Icon(icon, size: 16, color: sel ? AppColors.primaryContainer : t.colorScheme.onSurfaceVariant),
              ]),
              const SizedBox(height: 6),
              Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(rev, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaintRow(ThemeData t) {
    const paints = [
      ('glasurit', 'Glasurit 2K', 'BASF Certified'),
      ('spies', 'Spies Hecker', 'Axalta Premium'),
      ('sikkens', 'Sikkens', 'AkzoNobel'),
      ('nippon', 'Nippon Paint', 'Nax Premila'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10, runSpacing: 10,
          children: [
            ...paints.map((p) {
              final sel = _selectedPaints.contains(p.$1);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) {
                    _selectedPaints.remove(p.$1);
                  } else {
                    _selectedPaints.add(p.$1);
                  }
                }),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sel ? t.colorScheme.surfaceContainerHighest : t.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: sel ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.5), width: 1.5) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(sel ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18, color: sel ? AppColors.primaryContainer : t.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
                          Text(p.$3, style: TextStyle(fontSize: 9, color: t.colorScheme.onSurfaceVariant)),
                        ],
                      )),
                    ],
                  ),
                ),
              );
            }),
            // "Lainnya" tile
            GestureDetector(
              onTap: () => setState(() => _showCustomPaintField = !_showCustomPaintField),
              child: Container(
                width: 150,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _showCustomPaintField ? t.colorScheme.surfaceContainerHighest : t.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: _showCustomPaintField
                      ? Border.all(color: AppColors.primaryContainer.withValues(alpha: 0.5), width: 1.5)
                      : Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4), style: BorderStyle.solid),
                ),
                child: Row(
                  children: [
                    Icon(_showCustomPaintField ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18, color: _showCustomPaintField ? AppColors.primaryContainer : t.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lainnya', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
                        Text('Merek lain', style: TextStyle(fontSize: 9, color: t.colorScheme.onSurfaceVariant)),
                      ],
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_showCustomPaintField) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _customPaintCtrl,
            style: TextStyle(fontSize: 13, color: t.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Nama merek cat lainnya (pisahkan koma jika lebih dari satu)',
              filled: true,
              fillColor: t.brightness == Brightness.dark
                  ? const Color(0xFF18191C)
                  : t.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              isDense: true,
              prefixIcon: const Icon(Icons.edit_outlined, size: 16),
            ),
          ),
        ],
        if (_selectedPaints.isNotEmpty || (_showCustomPaintField && _customPaintCtrl.text.isNotEmpty)) ...[
          const SizedBox(height: 8),
          Text(
            'Dipilih: ${[
              ..._selectedPaints.map((id) {
                const names = {'glasurit': 'Glasurit 2K', 'spies': 'Spies Hecker', 'sikkens': 'Sikkens', 'nippon': 'Nippon Paint'};
                return names[id] ?? id;
              }),
              if (_showCustomPaintField && _customPaintCtrl.text.trim().isNotEmpty)
                _customPaintCtrl.text.trim(),
            ].join(', ')}',
            style: TextStyle(fontSize: 11, color: AppColors.primaryContainer, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE 2 — Photos
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPage2(ThemeData t, AppL l) {
    final uploaded = _facilityPhotos.where((p) => p != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle(t, Icons.photo_camera, l.partnerRegStep2, l.partnerRegStep2Sub),
        const SizedBox(height: 8),
        Text('$uploaded / 4 ${l.partnerRegPhotosUploaded}', style: TextStyle(fontSize: 12, color: uploaded == 4 ? Colors.green : t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.4,
          children: List.generate(4, (i) => _photoBox(t, i)),
        ),
        const SizedBox(height: 16),
        Text(l.partnerRegPhotosHint, style: TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _photoBox(ThemeData t, int i) {
    final bytes = _facilityPhotos[i];
    return GestureDetector(
      onTap: () => _pickPhoto(i),
      child: Container(
        decoration: BoxDecoration(
          color: bytes == null ? t.colorScheme.surfaceContainer : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: bytes != null ? Colors.green.withValues(alpha: 0.5) : AppColors.primaryContainer.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Stack(fit: StackFit.expand, children: [
                Image.memory(bytes, fit: BoxFit.cover),
                Positioned(top: 6, right: 6, child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                )),
                Positioned(bottom: 0, left: 0, right: 0, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Text(_photoLabels[i], style: const TextStyle(fontSize: 10, color: Colors.white)),
                )),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_photo_alternate, size: 28, color: AppColors.primaryContainer),
                const SizedBox(height: 6),
                Text(_photoLabels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface), textAlign: TextAlign.center),
                Text('Tap to upload', style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant)),
              ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE 3 — Documents
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPage3(ThemeData t, AppL l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle(t, Icons.folder_copy, l.partnerRegStep3, l.partnerRegStep3Sub),
        const SizedBox(height: 20),
        _docRow(t, l, Icons.description, 'NIB', l.partnerRegDocNib, 'nib'),
        const SizedBox(height: 12),
        _docRow(t, l, Icons.receipt_long, 'NPWP', l.partnerRegDocNpwp, 'npwp'),
        const SizedBox(height: 12),
        _docRow(t, l, Icons.upload_file, 'SIUP', l.partnerRegDocSiup, 'siup'),
        const SizedBox(height: 12),
        _docRow(t, l, Icons.contact_page, 'KTP', l.partnerRegDocKtp, 'ktp'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: t.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.lock_outline, size: 16, color: AppColors.primaryContainer),
            const SizedBox(width: 8),
            Expanded(child: Text(l.partnerRegDocEncrypted, style: TextStyle(fontSize: 11, color: t.colorScheme.onSurfaceVariant))),
          ]),
        ),
      ],
    );
  }

  Widget _docRow(ThemeData t, AppL l, IconData icon, String code, String name, String key) {
    final has = _docFiles[key] != null;
    final fn = _docFileNames[key];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: has ? Colors.green.withValues(alpha: 0.4) : t.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: has ? Colors.green.withValues(alpha: 0.1) : AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(has ? Icons.check_circle_outline : icon, color: has ? Colors.green : AppColors.primaryContainer, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$code — $name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
          Text(fn ?? 'PDF / JPG, maks 10 MB', style: TextStyle(fontSize: 10, color: has ? Colors.green : t.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: () => _pickDoc(key),
          style: ElevatedButton.styleFrom(
              backgroundColor: has ? Colors.green.withValues(alpha: 0.1) : t.colorScheme.surfaceContainerHighest,
              foregroundColor: has ? Colors.green : t.colorScheme.onSurface,
              elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          child: Text(has ? l.partnerRegReplace : l.partnerRegSelectFile, style: const TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE 4 — Location
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPage4(ThemeData t, AppL l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle(t, Icons.location_on, l.partnerRegStep4, l.partnerRegStep4Sub),
        const SizedBox(height: 16),

        // Same as legal address toggle
        Row(children: [
          Checkbox(
            value: _sameAsLegal,
            onChanged: (v) { setState(() => _sameAsLegal = v ?? true); },
            activeColor: AppColors.primaryContainer,
          ),
          Text(l.partnerRegSameAsLegal, style: TextStyle(fontSize: 13, color: t.colorScheme.onSurface)),
        ]),

        if (!_sameAsLegal) ...[
          const SizedBox(height: 12),
          _field(t, l.partnerRegWorkshopAddress, _workshopAddressCtrl, required: true, maxLines: 2),
        ],

        const SizedBox(height: 20),

        // GPS button
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l.partnerRegMapPin, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
          ElevatedButton.icon(
            onPressed: _locating ? null : _locateMe,
            icon: _locating
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.my_location, size: 16),
            label: Text(l.partnerRegLocateMe, style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          ),
        ]),
        if (_pin != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'LAT: ${_pin!.latitude.toStringAsFixed(6)}  LNG: ${_pin!.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.green),
            ),
          ),
        const SizedBox(height: 8),

        // flutter_map tile map
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _pin ?? const LatLng(-6.200000, 106.816666),
                initialZoom: _pin != null ? 15 : 11,
                onTap: (tp, ll) => setState(() => _pin = ll),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 're.v.app',
                ),
                if (_pin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _pin!,
                      width: 36, height: 36,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Text(l.partnerRegMapHint, style: TextStyle(fontSize: 10, color: t.colorScheme.onSurfaceVariant)),
        ),

        // Service radius
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(l.partnerRegRadius, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${_radius.toInt()} km', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
            ]),
            Slider(value: _radius, min: 5, max: 30, activeColor: AppColors.primaryContainer, onChanged: (v) => setState(() => _radius = v)),
          ]),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE 5 — Bank + Consent
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPage5(ThemeData t, AppL l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle(t, Icons.account_balance, l.partnerRegStep5, l.partnerRegStep5Sub),
        const SizedBox(height: 20),

        _field(t, l.partnerRegBankName, _bankNameCtrl, required: true,
            hint: 'BCA / BNI / Mandiri / BRI…'),
        const SizedBox(height: 14),
        _field(t, l.partnerRegBankAccount, _bankAccountCtrl, required: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        const SizedBox(height: 14),
        _field(t, l.partnerRegBankHolder, _bankHolderCtrl, required: true),
        const SizedBox(height: 24),

        if (_submitError != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline, size: 18, color: t.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.partnerRegSubmitFailed, style: TextStyle(fontWeight: FontWeight.bold, color: t.colorScheme.onErrorContainer, fontSize: 13)),
                const SizedBox(height: 4),
                Text(_submitError!, style: TextStyle(fontSize: 11, color: t.colorScheme.onErrorContainer)),
              ])),
            ]),
          ),

        // Consent
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: _consentChecked,
            onChanged: (v) => setState(() => _consentChecked = v ?? false),
            activeColor: AppColors.primaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l.partnerRegConsent, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface, height: 1.5))),
        ]),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Bottom nav bar
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildNavBar(ThemeData t, AppL l) {
    final isLast = _page == _totalPages - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(children: [
        if (_page > 0)
          TextButton.icon(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(l.partnerRegBack),
            style: TextButton.styleFrom(foregroundColor: t.colorScheme.onSurface),
          ),
        const Spacer(),
        if (!isLast)
          ElevatedButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(l.partnerRegNext),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          )
        else
          ElevatedButton.icon(
            onPressed: (_isSubmitting || !_consentChecked) ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.assignment_turned_in, size: 18),
            label: Text(_isSubmitting ? (_submitStage ?? l.partnerRegSubmitting) : l.partnerRegSubmit),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
          ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Success
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSuccess(ThemeData t, AppL l) {
    final photos = _facilityPhotos.where((p) => p != null).length;
    final docs = _docFiles.values.where((f) => f != null).length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text(l.partnerRegSuccessTitle, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
          const SizedBox(height: 12),
          Text(l.partnerRegSuccessBody, style: TextStyle(fontSize: 14, color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('$photos ${l.partnerRegSuccessPhotos} • $docs ${l.partnerRegSuccessDocs}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.colorScheme.onSurface)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
            child: Text(l.partnerRegGoHome),
          ),
        ]),
      ),
    );
  }

  // ── shared helpers ────────────────────────────────────────────────────────
  Widget _pageTitle(ThemeData t, IconData icon, String title, String sub) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 22, color: AppColors.primaryContainer),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
        Text(sub, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant)),
      ])),
    ]);
  }

  TextStyle _labelStyle(ThemeData t) =>
      TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: t.colorScheme.onSurfaceVariant, letterSpacing: 0.8);

  Widget _field(
    ThemeData t,
    String label,
    TextEditingController ctrl, {
    bool required = false,
    String? hint,
    String? prefix,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _labelStyle(t)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(fontSize: 14, color: t.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: t.brightness == Brightness.dark ? const Color(0xFF18191C) : t.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            isDense: true,
          ),
          validator: validator ?? (required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label wajib diisi' : null
              : null),
        ),
      ],
    );
  }
}