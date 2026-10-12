import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rev_app_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PartnerApplicationStatusScreen
//
// Shown after a partner applicant clicks their magic-link email.
// Reads partner_applications by the logged-in user's email and shows
// current status + next steps. No editing — read-only view.
// ─────────────────────────────────────────────────────────────────────────────

class PartnerApplicationStatusScreen extends StatefulWidget {
  const PartnerApplicationStatusScreen({super.key});

  @override
  State<PartnerApplicationStatusScreen> createState() =>
      _PartnerApplicationStatusScreenState();
}

class _PartnerApplicationStatusScreenState
    extends State<PartnerApplicationStatusScreen> {
  Map<String, dynamic>? _app;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _loading = false; _error = 'Sesi tidak valid. Gunakan link dari email Anda.'; });
      return;
    }

    try {
      final email = user.email?.toLowerCase().trim();
      if (email == null) throw Exception('Email tidak ditemukan di akun ini.');

      final rows = await Supabase.instance.client
          .from('partner_applications')
          .select('id, shop_name, entity_name, owner_name, email, status, '
              'submitted_at, reviewed_at, revision_notes, rejection_reason, '
              'tier, paint_brand, nib_file_key, npwp_file_key, siup_file_key, '
              'ktp_file_key, facility_photo_keys, wa_verified')
          .eq('email', email)
          .order('submitted_at', ascending: false)
          .limit(1);

      if (mounted) {
        setState(() {
          _loading = false;
          _app = rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final narrow = MediaQuery.of(context).size.width < 640;

    return Scaffold(
      backgroundColor: t.scaffoldBackgroundColor,
      appBar: const ReVAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(t)
              : _app == null
                  ? _buildNotFound(t)
                  : _buildStatus(t, narrow),
    );
  }

  // ── No application found ──────────────────────────────────────────────────
  Widget _buildNotFound(ThemeData t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded, size: 64, color: t.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 20),
          Text('Pendaftaran Tidak Ditemukan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
          const SizedBox(height: 10),
          Text('Tidak ada pendaftaran yang terkait dengan email ini.',
              style: TextStyle(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => context.go('/partner/register'),
            icon: const Icon(Icons.add_business, size: 18),
            label: const Text('Daftar Sekarang'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          ),
        ]),
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildError(ThemeData t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 64, color: t.colorScheme.error),
          const SizedBox(height: 20),
          Text(_error!, style: TextStyle(color: t.colorScheme.onSurface), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextButton(onPressed: _load, child: const Text('Coba Lagi')),
        ]),
      ),
    );
  }

  // ── Main status view ──────────────────────────────────────────────────────
  Widget _buildStatus(ThemeData t, bool narrow) {
    final app = _app!;
    final status = app['status']?.toString() ?? 'pending';
    final shop = app['shop_name']?.toString() ?? app['entity_name']?.toString() ?? '—';
    final submittedAt = _fmtDate(app['submitted_at']?.toString());
    final reviewedAt = _fmtDate(app['reviewed_at']?.toString());
    final docs = ['nib_file_key', 'npwp_file_key', 'siup_file_key', 'ktp_file_key']
        .where((k) => app[k] != null).length;
    final photos = (app['facility_photo_keys'] as List?)?.length ?? 0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 40, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(_statusIcon(status), color: _statusColor(status), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
                const SizedBox(height: 4),
                _StatusBadge(status),
              ])),
            ]),
            const SizedBox(height: 28),

            // ── Status banner ─────────────────────────────────────────────────
            _buildBanner(t, status, app),
            const SizedBox(height: 24),

            // ── Timeline ─────────────────────────────────────────────────────
            _section(t, 'Timeline', [
              _row(t, 'Dikirim', submittedAt),
              if (reviewedAt != null) _row(t, 'Ditinjau', reviewedAt),
            ]),
            const SizedBox(height: 20),

            // ── Evidence summary ──────────────────────────────────────────────
            _section(t, 'Dokumen & Foto', [
              _row(t, 'Dokumen Legal', '$docs / 4 diunggah'),
              _row(t, 'Foto Fasilitas', '$photos / 4 diunggah'),
              _row(t, 'WA Terverifikasi', app['wa_verified'] == true ? 'Ya ✓' : 'Belum'),
            ]),
            const SizedBox(height: 20),

            // ── Application details ───────────────────────────────────────────
            _section(t, 'Detail Pendaftaran', [
              _row(t, 'Entitas Hukum', app['entity_name']),
              _row(t, 'Nama Workshop', app['shop_name']),
              _row(t, 'PIC', app['owner_name']),
              _row(t, 'Email', app['email']),
              _row(t, 'Tier', 'Tier ${app['tier'] ?? '—'}'),
              _row(t, 'Cat', app['paint_brand']),
            ]),
            const SizedBox(height: 32),

            // ── Actions ───────────────────────────────────────────────────────
            _buildActions(t, status),
          ]),
        ),
      ),
    );
  }

  Widget _buildBanner(ThemeData t, String status, Map<String, dynamic> app) {
    switch (status) {
      case 'pending':
        return _banner(t, AppColors.primaryContainer,
          Icons.hourglass_top_rounded,
          'Menunggu Peninjauan',
          'Pendaftaran Anda sedang dalam antrian tinjauan tim Revive. '
          'Proses tinjauan biasanya memakan waktu 1–3 hari kerja. '
          'Anda akan mendapat notifikasi via WhatsApp dan email.');

      case 'pending_review':
        final notes = app['revision_notes']?.toString();
        return _banner(t, const Color(0xFF3B82F6),
          Icons.edit_note_rounded,
          'Diperlukan Perbaikan',
          'Tim Revive memerlukan beberapa perbaikan pada pendaftaran Anda sebelum dapat disetujui.'
          '${notes != null ? '\n\nCatatan tim:\n$notes' : ''}');

      case 'approved':
        return _banner(t, const Color(0xFF10B981),
          Icons.verified_rounded,
          'Pendaftaran Disetujui! 🎉',
          'Selamat! Bengkel Anda telah resmi bergabung dengan jaringan mitra Revive. '
          'Silakan cek email Anda untuk link login ke dashboard mitra.');

      case 'rejected':
        final reason = app['rejection_reason']?.toString();
        return _banner(t, const Color(0xFFd10721),
          Icons.cancel_rounded,
          'Pendaftaran Ditolak',
          'Maaf, pendaftaran Anda tidak dapat kami setujui saat ini.'
          '${reason != null ? '\n\nAlasan:\n$reason' : ''}\n\n'
          'Untuk informasi lebih lanjut hubungi partner@revive.co.id.');

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _banner(ThemeData t, Color color, IconData icon, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(fontSize: 13, color: t.colorScheme.onSurface, height: 1.5)),
        ])),
      ]),
    );
  }

  Widget _buildActions(ThemeData t, String status) {
    if (status == 'pending' || status == 'pending_review') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ada pertanyaan?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text('Hubungi kami di partner@revive.co.id atau balas WhatsApp dari notifikasi yang Anda terima.',
            style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
        if (status == 'pending_review') ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.go('/partner/register'),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Kirim Ulang Pendaftaran'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        ],
      ]);
    }
    if (status == 'approved') {
      return ElevatedButton.icon(
        onPressed: () => context.go('/partner-dashboard'),
        icon: const Icon(Icons.dashboard_rounded, size: 18),
        label: const Text('Buka Dashboard Mitra'),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      );
    }
    return const SizedBox.shrink();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _section(ThemeData t, String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                letterSpacing: 0.8, color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        ...rows,
      ]),
    );
  }

  Widget _row(ThemeData t, String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140,
            child: Text(label, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant))),
        Expanded(child: Text(value?.toString() ?? '—',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.colorScheme.onSurface))),
      ]),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return const Color(0xFF10B981);
      case 'rejected': return const Color(0xFFd10721);
      case 'pending_review': return const Color(0xFF3B82F6);
      default: return const Color(0xFFF59E0B);
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'approved': return Icons.verified_rounded;
      case 'rejected': return Icons.cancel_rounded;
      case 'pending_review': return Icons.edit_note_rounded;
      default: return Icons.hourglass_top_rounded;
    }
  }

  String? _fmtDate(String? dt) {
    if (dt == null) return null;
    try { return DateFormat('d MMM yyyy, HH:mm').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return dt; }
  }
}

// ── Status badge widget ───────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  Color get _color {
    switch (status) {
      case 'approved': return const Color(0xFF10B981);
      case 'rejected': return const Color(0xFFd10721);
      case 'pending_review': return const Color(0xFF3B82F6);
      default: return const Color(0xFFF59E0B);
    }
  }

  String get _label {
    switch (status) {
      case 'approved': return 'Disetujui';
      case 'rejected': return 'Ditolak';
      case 'pending_review': return 'Perlu Revisi';
      default: return 'Menunggu Tinjauan';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(_label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _color)),
    );
  }
}
