import 'package:re_v/core/utils/error_mapper.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:re_v/l10n/app_localizations.dart';
import 'package:re_v/core/format/rupiah.dart';
import '../../../../core/utils/guest_session.dart';
import '../../../../core/utils/image_compressor.dart';
import '../providers/panel_selection_provider.dart';
import '../providers/customer_intake_provider.dart';
import 'widgets/interactive_car_diagram.dart';
import '../../../../core/widgets/rev_app_bar.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations_extension.dart';

class EstimatorScreen extends ConsumerStatefulWidget {
  const EstimatorScreen({super.key});

  @override
  ConsumerState<EstimatorScreen> createState() => _EstimatorScreenState();
}

class _EstimatorScreenState extends ConsumerState<EstimatorScreen> {
  static const Map<String, List<String>> _carDatabase = {
    'Toyota': ['Avanza', 'Innova', 'Fortuner', 'Agya', 'Calya', 'Yaris', 'Rush', 'Camry', 'Corolla'],
    'Honda': ['Brio', 'HR-V', 'CR-V', 'BR-V', 'City', 'Civic', 'Mobilio', 'Accord', 'Jazz'],
    'Daihatsu': ['Sigra', 'Ayla', 'Xenia', 'Terios', 'Gran Max', 'Sirion'],
    'Suzuki': ['Ertiga', 'XL7', 'Ignis', 'Baleno', 'Jimny', 'Swift'],
    'Mitsubishi': ['Xpander', 'Pajero Sport', 'Outlander', 'Triton'],
    'Nissan': ['Livina', 'Serena', 'X-Trail', 'Magnite', 'Kicks'],
    'Hyundai': ['Creta', 'Stargazer', 'Palisade', 'Santa Fe', 'Ioniq 5', 'Ioniq 6'],
    'Kia': ['Sonet', 'Seltos', 'Carnival', 'Carens'],
    'Mazda': ['CX-3', 'CX-5', 'CX-30', 'Mazda 2', 'Mazda 3'],
    'Wuling': ['Air EV', 'Almaz', 'Confero', 'Cortez', 'Binguo'],
    'Other': [],
  };

  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  
  // Contact
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  
  // Demographics
  String? _selectedMake;
  String? _selectedModel;
  late TextEditingController _customMakeController;
  late TextEditingController _customModelController;
  late TextEditingController _yearController;
  late TextEditingController _licensePlateController;

  // Visual Intake — up to 5 damage photos
  final List<XFile> _selectedImages = [];
  static const int _maxImages = 5;
  bool _isAnalyzing = false;
  bool _consentGiven = false; // PRIV-06: explicit consent required before booking
  String? _aiResult;
  Map<String, dynamic>? _structuredData;
  String? _estimationId;
  int? _engineId;

  @override
  void initState() {
    super.initState();
    final intake = ref.read(customerIntakeProvider);
    _nameController = TextEditingController(text: intake.name);
    _phoneController = TextEditingController(text: intake.phone);
    
    _selectedMake = (_carDatabase.containsKey(intake.brand) || intake.brand.isEmpty) ? (intake.brand.isEmpty ? null : intake.brand) : 'Other';
    _customMakeController = TextEditingController(text: _selectedMake == 'Other' ? intake.brand : '');
    
    if (_selectedMake != null && _selectedMake != 'Other' && _carDatabase[_selectedMake]!.contains(intake.model)) {
      _selectedModel = intake.model;
    } else if (intake.model.isNotEmpty) {
      _selectedModel = 'Other';
    }
    _customModelController = TextEditingController(text: _selectedModel == 'Other' ? intake.model : '');
    
    _yearController = TextEditingController(text: intake.year);
    _licensePlateController = TextEditingController(text: intake.licensePlate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _customMakeController.dispose();
    _customModelController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _addImage(ImageSource source) async {
    if (_selectedImages.length >= _maxImages) return;
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image != null) {
      setState(() => _selectedImages.add(image));
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _aiResult = null;
      _structuredData = null;
    });
  }

  Future<void> _submitToVisionAi() async {
    if (_selectedImages.isEmpty) return;

    // The vision pipeline needs a session (SEC-03 kept that intact), but not an
    // identified one. A visitor is signed in anonymously so the estimate itself
    // stays public; the login prompt belongs to booking, where the workshop
    // actually needs someone it can reach.
    final guestId = await GuestSession.ensure();
    if (guestId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.estimatorLoginRequired)),
      );
      context.push('/login?returnTo=/estimator');
      return;
    }
    
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
      _structuredData = null; // L-03/C-31 fix: clear stale data before each analysis
    });

    try {
      // C-31/L-03 fix: clear estimatedCost before every analysis run
      ref.read(customerIntakeProvider.notifier).updateEstimatedCost(0);

      // PERF-04 fix: parallel uploads with Future.wait
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final List<String> photoUrls = await Future.wait(
        List.generate(_selectedImages.length, (i) async {
          final compressedBytes = await ImageCompressor.compressImage(_selectedImages[i]);
          final fileName = '$guestId/${timestamp}_$i.jpg';
          await Supabase.instance.client.storage
              .from('revive-photos')
              .uploadBinary(fileName, compressedBytes);
          return Supabase.instance.client.storage
              .from('revive-photos')
              .createSignedUrl(fileName, 3600);
        }),
      );

      final selectedPanels = ref.read(selectedPanelsProvider);
      final selectedPanelLabels = selectedPanels.map((p) => p.label).toList();

      final res = await Supabase.instance.client.functions.invoke(
        'vision-estimation',
        body: {
          'photoUrls': photoUrls,          // full array — all images
          'photoUrl': photoUrls.first,     // backwards-compat fallback
          'damageDescription': 'User uploaded car damage',
          'selectedPanels': selectedPanelLabels,
        },
      );

      setState(() {
        _aiResult = res.data['estimation'] ?? 'AI categorization complete.';
        _structuredData = res.data['structuredData'];
        _estimationId = res.data['estimationId']?.toString();
        _engineId = res.data['engineId'] != null ? (res.data['engineId'] as num).toInt() : null;
        if (_structuredData != null) {
          final cost = _structuredData!['financial_estimation']?['calculated_base_cost'] ?? 0;
          ref.read(customerIntakeProvider.notifier).updateEstimatedCost((cost as num).toDouble());
        }
      });

    } catch (e) {
      setState(() {
        _aiResult = 'Estimation Engine Fallback Triggered. Error: $e';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }


  void _onNextStep() async {
    if (_currentStep == 0) {
      if (_aiResult == null) {
        if (_selectedImages.isNotEmpty && ref.read(selectedPanelsProvider).isNotEmpty) {
          await _submitToVisionAi(); // UX-08 fix: await so result is ready before any further action
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.estimatorSelectPanels)),
          );
        }
      } else {
        // C-31 fix: only advance if structuredData has actual panels with cost > 0
        final panels = _structuredData?['assessment']?['damaged_panels_detail'];
        final cost = _structuredData?['financial_estimation']?['calculated_base_cost'] ?? 0;
        if (_structuredData == null || panels == null || (panels as List).isEmpty || cost <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Estimasi belum valid — ulangi analisis foto.')),
          );
          return;
        }
        setState(() => _currentStep += 1);
      }
    } else if (_currentStep < 3) {
      // The contact step must be complete before review: the number is what the
      // workshop uses to arrange pickup. The Form and _formKey existed from the
      // start but validate() was never called, so these fields only looked
      // mandatory. The validators paint their own inline errors, so returning
      // without advancing is the whole gate.
      if (_currentStep == 2 && !(_formKey.currentState?.validate() ?? false)) {
        return;
      }
      setState(() => _currentStep += 1);
    } else {
      // Booking is where identity is genuinely required: this writes a job that
      // a workshop must be able to follow up on. A guest — or an anonymous
      // session — is sent to sign in and returned straight to the estimator,
      // which keeps the photo, panel and panel data they already entered.
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null || user.isAnonymous) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.estimatorLoginRequired)));
        context.push('/login?returnTo=/estimator');
        return;
      }
      
      // PRIV-06 fix: require explicit consent before booking
      if (!_consentGiven) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Centang persetujuan Syarat & Kebijakan Privasi untuk melanjutkan')),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppColors.fireRed)),
      );

      try {
        final intake = ref.read(customerIntakeProvider);
        final contactPhone = intake.phone.trim();

        // The contact step is the only place the app asks for a phone, and until
        // now nothing wrote it anywhere: it lived in SharedPreferences (browser
        // localStorage) and died there, leaving the workshop with no way to reach
        // the customer and ops rendering "No phone provided".
        //
        // A targeted UPDATE, not an upsert. `profiles.full_name` and
        // `profiles.role` are NOT NULL with no defaults, and Postgres validates
        // those before resolving ON CONFLICT — so a partial upsert fails with
        // 23502 even for a row that already exists. It also keeps this off
        // `role`, which is derived from memberships and must not be rewritten
        // from the token here.
        final profileFields = <String, dynamic>{};
        if (intake.name.trim().isNotEmpty) profileFields['full_name'] = intake.name.trim();
        if (contactPhone.isNotEmpty) profileFields['phone'] = contactPhone;

        if (profileFields.isNotEmpty) {
          try {
            await Supabase.instance.client
                .from('profiles')
                .update(profileFields)
                .eq('id', user.id);
          } catch (e) {
            // Non-fatal: the per-job snapshot below is what the workshop reads, so
            // a profile write failure must not block the booking.
            debugPrint('[Estimator] profile contact save failed (non-fatal): $e');
          }
        }

        final vehicleRes = await Supabase.instance.client.from('vehicles').upsert({
          'customer_id': user.id,
          'make': intake.brand,
          'model': intake.model,
          'year': int.tryParse(intake.year) ?? 2020,
          'license_plate': intake.licensePlate.isEmpty ? null : intake.licensePlate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
        }, onConflict: 'customer_id,license_plate').select('id').single(); // B-08/DAT-08 fix: upsert

        // B-11 fix: price from server via create_job_from_estimation — not client-written
        final estimationId = _estimationId;
        late String jobId;
        if (estimationId != null) {
          final jobRes = await Supabase.instance.client.rpc('create_job_from_estimation', params: {
            'p_estimation_id':  estimationId,
            'p_vehicle_make':   intake.brand,
            'p_vehicle_model':  intake.model,
            'p_vehicle_year':   int.tryParse(intake.year) ?? 2020,
            'p_license_plate':  intake.licensePlate,
            'p_contact_phone':  contactPhone.isEmpty ? null : contactPhone,
            'p_service_area':   intake.location.isEmpty ? null : intake.location,
          });
          jobId = jobRes.toString();
        } else {
          // Fallback for older flow without estimation_id
          final jobRes = await Supabase.instance.client.from('repair_jobs').insert({
            'customer_id': user.id,
            'vehicle_id': vehicleRes['id'],
            'initial_estimation_cost': intake.estimatedCost,
            'estimation_result': _structuredData,
            'status': '2_estimated',
            'service_area': intake.location.isEmpty ? null : intake.location,
            'contact_phone': contactPhone.isEmpty ? null : contactPhone,
          }).select('id').single();
          jobId = jobRes['id'].toString();
        }
        
        // PRIV-06: record explicit consent in consents table (record_consent RPC)
        await Supabase.instance.client.rpc('record_consent', params: {
          'p_doc': 'estimation',
          'p_version': '1.0',
        });

        if (context.mounted) {
          Navigator.of(context).pop();
          context.push('/booking/$jobId');
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: Theme.of(context).colorScheme.error));
        }
      }
    }
  }

  Widget _buildProgressSteps() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.lens, color: AppColors.fireRed, size: 15),
                  const SizedBox(width: 4),
                  Text(
                    'STEP ${_currentStep + 1} OF 4: ${_getStepTitle()}',
                    style: const TextStyle(
                      color: AppColors.fireRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Text(
                '${((_currentStep + 1) * 25).toInt()}%',
                style: const TextStyle(
                  color: AppColors.fireRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
                  height: 6,
                  decoration: BoxDecoration(
                    color: index <= _currentStep ? AppColors.fireRed : (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStepLabel('Damage', 'Active', 0),
              _buildStepLabel('Vehicle', 'Step 2', 1),
              _buildStepLabel('Contact', 'Step 3', 2),
              _buildStepLabel('Confirm', 'Step 4', 3),
            ],
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'VISUAL DAMAGE INTAKE';
      case 1: return 'VEHICLE DEMOGRAPHICS';
      case 2: return 'CONTACT DETAILS';
      case 3: return 'BOOKING CONFIRMATION';
      default: return '';
    }
  }

  Widget _buildStepLabel(String title, String subtitle, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = index == _currentStep;
    final isPast = index < _currentStep;
    final textColor = isActive || isPast ? (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface) : (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant);
    final subColor = isActive ? AppColors.fireRed : (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: textColor,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.fireRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info, color: AppColors.fireRed, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle Scan & Damage Triage',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Provide a photo of the damage and select affected panels on the digital twin.\nNote: Make sure to clearly capture any scratches (gores) or dents (penyok).',
                  style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoUpload() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _selectedImages.length;
    final atMax = count >= _maxImages;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceContainerLowest : cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.l10n.estimatorIntakeImagery,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: cs.onSurfaceVariant)),
              Row(
                children: [
                  if (_aiResult != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text(context.l10n.estimatorAiVerified, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.error)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: atMax ? cs.error.withValues(alpha: 0.1) : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$count / $_maxImages',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: atMax ? cs.error : cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Thumbnail strip ─────────────────────────────────────────────
          if (_selectedImages.isNotEmpty) ...[
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final img = _selectedImages[index];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                          color: cs.surfaceContainerLow,
                        ),
                        clipBehavior: Clip.antiAlias,
                        // PLAT-05 fix: XFile.path is a blob URL on web, filesystem path on native.
                        // Image.network fails on native filesystem paths — use readAsBytes() instead.
                        child: FutureBuilder<Uint8List>(
                          future: img.readAsBytes(),
                          builder: (ctx, snap) {
                            if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover);
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                          },
                        ),
                      ),
                      Positioned(
                        top: -14,
                        right: -14,
                        child: IconButton(
                          onPressed: () => _removeImage(index),
                          tooltip: context.l10n.delete,
                          icon: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 1.5)),
                            child: Icon(Icons.close, color: cs.onError, size: 14),
                          ),
                        ),
                      ),
                      if (index == 0)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                            child: Text('Primary', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.onPrimary)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Add photo buttons ───────────────────────────────────────────
          if (!atMax) ...[
            if (_selectedImages.isEmpty)
              ElevatedButton.icon(
                onPressed: () => _addImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera, size: 20),
                label: Text(context.l10n.estimatorCaptureDamage, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 1,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addImage(ImageSource.camera),
                      icon: Icon(Icons.add_a_photo_outlined, size: 16, color: cs.error),
                      label: Text(context.l10n.estimatorAddPhoto, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.outline),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addImage(ImageSource.gallery),
                      icon: Icon(Icons.photo_library_outlined, size: 16, color: cs.onSurfaceVariant),
                      label: Text(context.l10n.estimatorFromGallery, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.outline),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: cs.error),
                const SizedBox(width: 6),
                Text(context.l10n.estimatorMaxReached, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),

          if (_selectedImages.isEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Add up to 5 photos. All photos are analyzed by AI to estimate damage severity. The first photo will be used as the main picture.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDigitalTwin() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.estimatorDigitalTwin, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                  Text(context.l10n.estimatorTapPanels, style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.fireRed, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(context.l10n.estimatorLiveTwin, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 938.0 / 610.0,
                  child: InteractiveCarDiagram(
                    selectedPanels: ref.watch(selectedPanelsProvider),
                    onToggle: (panel) {
                      ref.read(selectedPanelsProvider.notifier).togglePanel(panel);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text('Atau pilih dari daftar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: CarPanel.values.map((panel) {
                    final isSelected = ref.watch(selectedPanelsProvider).contains(panel);
                    return FilterChip(
                      label: Text(panel.label, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) {
                        ref.read(selectedPanelsProvider.notifier).togglePanel(panel);
                      },
                      selectedColor: AppColors.primaryContainer,
                      checkmarkColor: AppColors.onPrimaryContainer,
                      backgroundColor: isDark ? AppColors.surfaceContainerHigh : Theme.of(context).colorScheme.surfaceContainerHighest,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ref.watch(selectedPanelsProvider).map((panel) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 2, offset: const Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, color: AppColors.fireRed, size: 16),
                    const SizedBox(width: 4),
                    Text(panel.label, style: const TextStyle(color: AppColors.fireRed, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Panels the customer flagged that the AI did not return.
  ///
  /// The AI is instructed to report a panel only when it can visually confirm
  /// damage, so an omitted panel means it could not be seen or assessed in the
  /// uploaded photo — NOT that the panel is undamaged. Matching is
  /// case-insensitive because [CarPanel.label] and `pricing_rules.panel_name`
  /// differ in casing for 'Spoiler Bumper Depan'.
  List<CarPanel> _omittedSelectedPanels(List<dynamic> aiPanels) {
    final aiNames = aiPanels
        .map((p) => (p['panel_name'] ?? '').toString().trim().toLowerCase())
        .toSet();
    return ref
        .watch(selectedPanelsProvider)
        .where((sp) => !aiNames.contains(sp.label.trim().toLowerCase()))
        .toList();
  }

  /// Rows for [_omittedSelectedPanels] plus the note explaining why those panels
  /// are absent from the total. Shared by the assessment report and the review
  /// step so both screens word it identically.
  List<Widget> _buildOmittedPanelWidgets(List<CarPanel> omitted, bool isDark) {
    if (omitted.isEmpty) return const [];
    return [
      ...omitted.map((panel) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surfaceContainerLowest),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (isDark ? AppColors.surfaceContainerHigh : Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        panel.label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tidak terlihat di foto — tidak dapat dinilai AI estimator',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Belum dinilai',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.surfaceContainerHighest : Theme.of(context).colorScheme.surfaceContainerHighest),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('TIDAK DINILAI', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                    ),
                  ],
                ),
              ],
            ),
          )),
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.fireRed.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 15, color: AppColors.fireRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Catatan: ${omitted.length} panel yang Anda pilih tidak terlihat dengan jelas pada foto, sehingga tidak dapat dilihat dan dinilai oleh AI estimator. Panel tersebut belum termasuk dalam estimasi ini. Unggah foto yang lebih jelas untuk area tersebut agar dapat dinilai.',
                style: TextStyle(fontSize: 11, height: 1.35, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildDamageAssessmentReport() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_aiResult == null) return const SizedBox.shrink();

    final panels = (_structuredData != null && _structuredData!['assessment'] != null)
        ? (_structuredData!['assessment']['damaged_panels_detail'] as List<dynamic>? ?? [])
        : [];
    final totalCost = _structuredData?['financial_estimation']?['calculated_base_cost'] ?? 0;
    final omittedPanels = _omittedSelectedPanels(panels);

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.fireRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.assignment_turned_in, color: Theme.of(context).colorScheme.surface, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.estimatorAssessmentReport, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                        Text(context.l10n.estimatorTriageMatrix, style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_engineId != null)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('E$_engineId', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${panels.length} Items', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (panels.isEmpty)
                  Text('${context.l10n.estimatorAssessmentLabel}\n$_aiResult', style: TextStyle(color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                ...panels.map((panel) {
                  final severity = (panel['panel_severity']?.toString() ?? 'ringan').toUpperCase();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(panel['panel_name']?.toString() ?? '-', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                            Text(formatRupiah(panel['calculated_cost']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.estimatorObservation, style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                            Expanded(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if ((panel['scratches_found'] as num? ?? 0) > 0)
                                    Text('⚡ Gores', style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.bold)),
                                  if ((panel['scratches_found'] as num? ?? 0) > 0 && (panel['dents_found'] as num? ?? 0) > 0)
                                    Text(' • ', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                                  if ((panel['dents_found'] as num? ?? 0) > 0)
                                    Text('🔨 Penyok', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                                  if ((panel['dents_found'] as num? ?? 0) > 0 && (panel['broken_found'] as num? ?? 0) > 0)
                                    Text(' • ', style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                                  if ((panel['broken_found'] as num? ?? 0) > 0)
                                    Text('💥 Pecah/Ringsek', style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold)),
                                  if ((panel['scratches_found'] as num? ?? 0) == 0 && (panel['dents_found'] as num? ?? 0) == 0 && (panel['broken_found'] as num? ?? 0) == 0 && panel['requires_replacement'] == true)
                                    Text('💥 Pecah/Ringsek', style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold)),
                                  if ((panel['scratches_found'] as num? ?? 0) == 0 && (panel['dents_found'] as num? ?? 0) == 0 && (panel['broken_found'] as num? ?? 0) == 0 && panel['requires_replacement'] != true)
                                    Text('🔨 Penyok', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.fireRed.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Severity: $severity', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                // Flagged panels the AI could not see or assess, plus the note
                // explaining why they are excluded from the total below
                ..._buildOmittedPanelWidgets(omittedPanels, isDark),

                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.surfaceContainer : Theme.of(context).colorScheme.surfaceContainer),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.estimatorTotalEstimation, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                          Text(context.l10n.estimatorIncludesCoat, style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                        ],
                      ),
                      Text(formatRupiah(totalCost), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.fireRed)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedMake,
          decoration: const InputDecoration(labelText: 'Car Brand'),
          items: _carDatabase.keys.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) {
            setState(() {
              _selectedMake = val;
              _selectedModel = null;
              _customMakeController.clear();
              _customModelController.clear();
            });
            // C-71 fix: always clear model in intake when brand changes
            ref.read(customerIntakeProvider.notifier).updateModel('');
            if (val != null && val != 'Other') {
              ref.read(customerIntakeProvider.notifier).updateBrand(val);
            } else if (val == 'Other') {
              ref.read(customerIntakeProvider.notifier).updateBrand('');
            }
          },
        ),
        if (_selectedMake == 'Other')
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: TextFormField(
              controller: _customMakeController,
              decoration: const InputDecoration(labelText: 'Enter Car Brand'),
              onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateBrand(val),
            ),
          ),
        const SizedBox(height: 12),
        if (_selectedMake != null && _selectedMake != 'Other')
          DropdownButtonFormField<String>(
            initialValue: _selectedModel,
            decoration: const InputDecoration(labelText: 'Car Model'),
            items: [..._carDatabase[_selectedMake]!, 'Other'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedModel = val;
                _customModelController.clear();
              });
              if (val != null && val != 'Other') {
                ref.read(customerIntakeProvider.notifier).updateModel(val);
              }
            },
          ),
        if (_selectedMake == 'Other' || _selectedModel == 'Other')
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: TextFormField(
              controller: _customModelController,
              decoration: const InputDecoration(labelText: 'Enter Car Model'),
              onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateModel(val),
            ),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _yearController,
          decoration: const InputDecoration(labelText: 'Year of Production'),
          keyboardType: TextInputType.number,
          onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateYear(val),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _licensePlateController,
          decoration: const InputDecoration(labelText: 'License Plate (e.g. B 1234 XYZ)'),
          textCapitalization: TextCapitalization.characters,
          onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateLicensePlate(val),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Full Name'),
            onChanged: (val) => ref.read(customerIntakeProvider.notifier).updateName(val),
            // Required: this is the name the workshop sees for the booking.
            validator: (val) => (val ?? '').trim().isEmpty ? 'Please enter your full name.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'WhatsApp Number'),
            keyboardType: TextInputType.phone,
            onChanged: (val) => ref.read(customerIntakeProvider.notifier).updatePhone(val),
            // Required: the workshop calls this number to arrange pickup, so a
            // booking without it leaves ops unable to reach anyone.
            validator: (val) =>
                (val ?? '').trim().isEmpty ? 'Please enter a WhatsApp number we can reach you on.' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Select Service Area'),
            initialValue: ref.watch(customerIntakeProvider).location.isEmpty ? null : ref.watch(customerIntakeProvider).location,
            items: [
              'Bandung', 'Cimahi', 'Soreang', 
              'Jakarta Pusat', 'Jakarta Utara', 'Jakarta Timur', 'Jakarta Selatan', 'Jakarta Barat', 
              'Bogor', 'Depok', 'Tangerang', 'Bekasi'
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) {
              if (val != null) {
                ref.read(customerIntakeProvider.notifier).updateLocation(val);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep4() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final intake = ref.watch(customerIntakeProvider);
    final panels = (_structuredData != null && _structuredData!['assessment'] != null)
        ? (_structuredData!['assessment']['damaged_panels_detail'] as List<dynamic>? ?? [])
        : [];
    final totalCost = _structuredData?['financial_estimation']?['calculated_base_cost'] ?? 0;
    final overallSeverity = _structuredData?['assessment']?['severity_classification'] ?? '-';

    // Panels the customer flagged but that the AI did not return. The AI only
    // reports panels it can visually confirm in the photo, so an omitted panel
    // means "not visible / not assessable" — NOT "confirmed undamaged".
    // Rendered explicitly so the total never silently excludes a flagged panel.
    final aiPanelNames = panels
        .map((p) => (p['panel_name'] ?? '').toString().trim().toLowerCase())
        .toSet();
    final omittedPanels = ref
        .watch(selectedPanelsProvider)
        .where((sp) => !aiPanelNames.contains(sp.label.trim().toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.fireRed.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.fireRed.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.fireRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Review your details before confirming. Go back to edit anything.',
                  style: TextStyle(fontSize: 13, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Section 1: Contact ──────────────────────────────────────
        _buildReviewSection(
          icon: Icons.person_outline,
          title: 'Contact Details',
          rows: [
            _ReviewRow('Full Name', intake.name.isEmpty ? '—' : intake.name),
            _ReviewRow('WhatsApp', intake.phone.isEmpty ? '—' : intake.phone),
            _ReviewRow('Service Area', intake.location.isEmpty ? '—' : intake.location),
          ],
        ),
        const SizedBox(height: 12),

        // ── Section 2: Vehicle ──────────────────────────────────────
        _buildReviewSection(
          icon: Icons.directions_car_outlined,
          title: 'Vehicle Details',
          rows: [
            _ReviewRow('Brand', intake.brand.isEmpty ? '—' : intake.brand),
            _ReviewRow('Model', intake.model.isEmpty ? '—' : intake.model),
            _ReviewRow('Year', intake.year.isEmpty ? '—' : intake.year),
            _ReviewRow('License Plate', intake.licensePlate.isEmpty ? '—' : intake.licensePlate),
          ],
        ),
        const SizedBox(height: 12),

        // ── Section 3: Damage Assessment ────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surface),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Column(
            children: [
              // section header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assignment_turned_in_outlined, size: 18, color: AppColors.fireRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Damage Assessment',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface)),
                      ),
                    ),
                    if (overallSeverity != '-')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.fireRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Overall: ${overallSeverity.toString().toUpperCase()}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                        ),
                      ),
                  ],
                ),
              ),
              // panel rows
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (panels.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(context.l10n.estimatorNoAiData, style: TextStyle(color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                      ),
                    ...panels.map((panel) {
                      final severity = (panel['panel_severity']?.toString() ?? 'ringan').toUpperCase();
                      final cost = panel['calculated_cost'] ?? 0;
                      final hasGores = (panel['scratches_found'] as num? ?? 0) > 0;
                      final hasPenyok = (panel['dents_found'] as num? ?? 0) > 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    panel['panel_name']?.toString() ?? '-',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface)),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    [
                                      if (hasGores) '⚡ Gores',
                                      if (hasPenyok) '🔨 Penyok',
                                      if (!hasGores && !hasPenyok) 'Kerusakan Umum',
                                    ].join('  '),
                                    style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatRupiah(cost),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface)),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.fireRed.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    severity,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    
                    // Flagged panels the AI could not see or assess, plus the note
                    // explaining why they are excluded from the total below
                    ..._buildOmittedPanelWidgets(omittedPanels, isDark),

                    // Total cost row
                    if (panels.isNotEmpty) ...[
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.l10n.estimatorEstimatedTotal, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant), letterSpacing: 0.8)),
                              Text('Incl. color matching & clear coat', style: TextStyle(fontSize: 10, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                            ],
                          ),
                          Text(
                            formatRupiah(totalCost),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.fireRed),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // PRIV-06/UX-17 fix: explicit consent checkbox with links
        StatefulBuilder(
          builder: (ctx, setStateLocal) {
            // consent state lives in the parent widget state
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: _consentGiven,
                  onChanged: (v) => setState(() => _consentGiven = v ?? false),
                  title: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      children: [
                        const TextSpan(text: 'Saya menyetujui '),
                        WidgetSpan(child: GestureDetector(
                          onTap: () => context.push('/terms'),
                          child: const Text('Syarat & Ketentuan', style: TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline)),
                        )),
                        const TextSpan(text: ' dan '),
                        WidgetSpan(child: GestureDetector(
                          onTap: () => context.push('/privacy'),
                          child: const Text('Kebijakan Privasi', style: TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline)),
                        )),
                        const TextSpan(text: ' Revive, termasuk pemrosesan foto oleh AI.'),
                      ],
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            );
          },
        ),

        // Consent note (old passive text replaced)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'By confirming, you agree to drop off your vehicle based on the estimated structural damage above. Final price may vary after physical inspection.',
                  style: TextStyle(fontSize: 11, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewSection({
    required IconData icon,
    required String title,
    required List<_ReviewRow> rows,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceContainerLowest : Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceContainerLow : Theme.of(context).colorScheme.surfaceContainerLow),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.fireRed),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: rows.map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label, style: TextStyle(fontSize: 12, color: (isDark ? AppColors.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant))),
                    Text(row.value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: (isDark ? AppColors.onSurface : Theme.of(context).colorScheme.onSurface))),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgressSteps(),
        const SizedBox(height: 16),
        if (_currentStep == 0) ...[
          _buildInstructionBanner(),
          const SizedBox(height: 16),
          _buildPhotoUpload(),
          const SizedBox(height: 16),
          _buildDigitalTwin(),
          const SizedBox(height: 16),
          _buildDamageAssessmentReport(),
        ] else if (_currentStep == 1) ...[
          _buildStep2(),
        ] else if (_currentStep == 2) ...[
          _buildStep3(),
        ] else if (_currentStep == 3) ...[
          _buildStep4(),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String ctaTitle = '';
    String ctaSubtitle = '';
    if (_currentStep == 0) {
      if (_aiResult == null) {
        ctaTitle = 'Analyze Damage';
        ctaSubtitle = 'Run AI vision estimation';
      } else {
        ctaTitle = 'Step 2 Demographics';
        ctaSubtitle = 'Continue to Schedule Booking';
      }
    } else if (_currentStep == 1) {
      ctaTitle = 'Step 3 Contact Details';
      ctaSubtitle = 'Continue to Next Step';
    } else if (_currentStep == 2) {
      ctaTitle = 'Step 4 Confirmation';
      ctaSubtitle = 'Continue to Final Review';
    } else {
      ctaTitle = 'Confirm Booking';
      ctaSubtitle = 'Submit for Workshop Allocation';
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      Widget inner = Scaffold(
      backgroundColor: (isDark ? AppColors.surface : Theme.of(context).colorScheme.surface),
      appBar: const ReVAppBar(
              title: Text('AI Body Repair Estimator'),
              showBackButton: true,
            ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100 + MediaQuery.paddingOf(context).bottom),
            child: _buildContent(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                color: (isDark ? AppColors.surface : Theme.of(context).colorScheme.surface),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.surfaceContainerHighest : Theme.of(context).colorScheme.surfaceContainerHigh),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            setState(() => _currentStep -= 1);
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAnalyzing ? null : _onNextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.fireRed,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(ctaTitle.toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.70), fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              const SizedBox(height: 2),
                              _isAnalyzing
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(ctaSubtitle, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ), // Row
            ), // Container
          ), // SafeArea
        ), // Positioned
      ], // Stack children
    ), // Stack
  ); // Scaffold
      return isDesktop ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: inner)) : inner;
    });
  }
}


class _ReviewRow {
  final String label;
  final String value;
  const _ReviewRow(this.label, this.value);
}
