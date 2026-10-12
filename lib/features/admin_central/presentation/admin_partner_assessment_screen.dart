import 'package:re_v/core/utils/error_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/signed_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/rev_app_bar.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _red   = Color(0xFFd10721);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _blue  = Color(0xFF3B82F6);

const _bucket = 'revive-photos';

const _docKeyColumns = <String, String>{
  'NIB': 'nib_file_key', 'NPWP': 'npwp_file_key',
  'SIUP': 'siup_file_key', 'KTP': 'ktp_file_key',
};

// ─── Pagination constants ─────────────────────────────────────────────────────
const _pageSize = 20;

// ─── Providers ────────────────────────────────────────────────────────────────

// Applications — paginated, filter by status
final _appPageProvider = StateProvider.autoDispose<int>((ref) => 0);
final _appStatusFilterProvider = StateProvider.autoDispose<String>((ref) => 'pending');
final _appSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final _applicationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (int, String, String)>((ref, args) async {
  final (page, status, search) = args;
  dynamic q = Supabase.instance.client
      .from('partner_applications')
      .select('id, shop_name, entity_name, owner_name, email, phone, '
          'tier, paint_brand, throughput_capacity, service_radius_km, '
          'status, submitted_at, created_at, wa_verified, '
          'nib_file_key, npwp_file_key, siup_file_key, ktp_file_key, facility_photo_keys');

  if (status != 'all') {
    if (status == 'pending') {
      q = (q as dynamic).inFilter('status', ['pending', 'pending_review']);
    } else {
      q = (q as dynamic).eq('status', status);
    }
  }
  if (search.isNotEmpty) {
    q = (q as dynamic).or('shop_name.ilike.%$search%,entity_name.ilike.%$search%,email.ilike.%$search%');
  }

  final rows = await (q as dynamic)
      .order('submitted_at', ascending: false)
      .range(page * _pageSize, (page + 1) * _pageSize - 1);
  return List<Map<String, dynamic>>.from(rows as List);
});

// Partners — paginated
final _partnerPageProvider = StateProvider.autoDispose<int>((ref) => 0);
final _partnerStatusFilterProvider = StateProvider.autoDispose<String>((ref) => 'all');
final _partnerSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final _partnersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (int, String, String)>((ref, args) async {
  final (page, status, search) = args;
  dynamic q = Supabase.instance.client
      .from('partners')
      .select('id, shop_name, entity_name, owner_name, tier, status, is_active, '
          'email, phone, address, paint_brand, throughput_capacity, service_radius_km, '
          'working_bays, spray_booths, created_at, '
          'nib_file_key, npwp_file_key, siup_file_key, ktp_file_key');

  if (status != 'all') q = (q as dynamic).eq('status', status);
  if (search.isNotEmpty) {
    q = (q as dynamic).or('shop_name.ilike.%$search%,entity_name.ilike.%$search%,email.ilike.%$search%');
  }

  final rows = await (q as dynamic)
      .order('created_at', ascending: false)
      .range(page * _pageSize, (page + 1) * _pageSize - 1);
  return List<Map<String, dynamic>>.from(rows as List);
});

// Selection state
final _selectedApplicationIdProvider = StateProvider.autoDispose<String?>((ref) => null);
final _selectedPartnerIdProvider = StateProvider.autoDispose<String?>((ref) => null);

// Document/photo providers (used by partner detail panel)
final _partnerDocumentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, partnerId) async {
  final rows = await Supabase.instance.client
      .from('partner_documents').select()
      .eq('partner_id', partnerId).order('uploaded_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

final _partnerPhotosProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, partnerId) async {
  final rows = await Supabase.instance.client
      .from('partner_facility_photos').select()
      .eq('partner_id', partnerId).order('uploaded_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

final _partnerMessagesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, partnerId) async {
  final rows = await Supabase.instance.client
      .from('partner_messages').select()
      .eq('partner_id', partnerId).order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
});

// ─── Root screen ──────────────────────────────────────────────────────────────

class AdminPartnerAssessmentScreen extends ConsumerStatefulWidget {
  const AdminPartnerAssessmentScreen({super.key});

  @override
  ConsumerState<AdminPartnerAssessmentScreen> createState() =>
      _AdminPartnerAssessmentScreenState();
}

class _AdminPartnerAssessmentScreenState
    extends ConsumerState<AdminPartnerAssessmentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _rootTabs;

  @override
  void initState() {
    super.initState();
    _rootTabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _rootTabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const ReVAppBar(showBackButton: true),
      body: Column(children: [
        // ── Top bar ────────────────────────────────────────────────────────
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(children: [
            const Icon(Icons.store_mall_directory_outlined, color: _red, size: 20),
            const SizedBox(width: 10),
            Text('Partner Assessment',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const Spacer(),
            TabBar(
              controller: _rootTabs,
              isScrollable: true,
              labelColor: _red,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: _red,
              indicatorWeight: 2,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Pendaftaran'),
                Tab(text: 'Mitra Aktif'),
              ],
            ),
          ]),
        ),

        // ── Tab content ────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(controller: _rootTabs, children: [
            _ApplicationsTab(cs: cs),
            _PartnersTab(cs: cs),
          ]),
        ),
      ]),
    );
  }
}

// ─── Tab: Pending Applications ────────────────────────────────────────────────

class _ApplicationsTab extends ConsumerStatefulWidget {
  final ColorScheme cs;
  const _ApplicationsTab({required this.cs});

  @override
  ConsumerState<_ApplicationsTab> createState() => _ApplicationsTabState();
}

class _ApplicationsTabState extends ConsumerState<_ApplicationsTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final page = ref.watch(_appPageProvider);
    final status = ref.watch(_appStatusFilterProvider);
    final search = ref.watch(_appSearchProvider);
    final selectedId = ref.watch(_selectedApplicationIdProvider);
    final appsAsync = ref.watch(_applicationsProvider((page, status, search)));

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Left: table ──────────────────────────────────────────────────────
      Container(
        width: 380,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border(right: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(children: [
          // Search + filters
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  ref.read(_appSearchProvider.notifier).state = v.toLowerCase();
                  ref.read(_appPageProvider.notifier).state = 0;
                },
                decoration: InputDecoration(
                  hintText: 'Cari nama / email…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in ['pending', 'approved', 'rejected', 'all'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          ref.read(_appStatusFilterProvider.notifier).state = s;
                          ref.read(_appPageProvider.notifier).state = 0;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: status == s
                                ? _statusColor(s).withValues(alpha: 0.15)
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            s == 'pending' ? 'Pending' :
                            s == 'approved' ? 'Approved' :
                            s == 'rejected' ? 'Rejected' : 'Semua',
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold,
                              color: status == s ? _statusColor(s) : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: cs.outlineVariant),

          // List
          Expanded(
            child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e',
                  style: TextStyle(color: cs.error, fontSize: 12))),
              data: (apps) {
                if (apps.isEmpty) {
                  return Center(child: Text('Tidak ada pendaftaran.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)));
                }
                return ListView.separated(
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (ctx, i) {
                    final a = apps[i];
                    final id = a['id']?.toString() ?? '';
                    final isSelected = selectedId == id;
                    final appStatus = a['status']?.toString() ?? 'pending';
                    final docCount = _docKeyColumns.values.where((k) => a[k] != null).length;
                    final photoCount = (a['facility_photo_keys'] as List?)?.length ?? 0;
                    return InkWell(
                      onTap: () {
                        ref.read(_selectedApplicationIdProvider.notifier).state = id;
                        ref.read(_selectedPartnerIdProvider.notifier).state = null;
                      },
                      child: Container(
                        color: isSelected ? _amber.withValues(alpha: 0.1) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(
                              a['shop_name']?.toString() ?? a['entity_name']?.toString() ?? '—',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                  color: cs.onSurface),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            )),
                            _StatusChip(appStatus),
                          ]),
                          const SizedBox(height: 2),
                          Text(a['entity_name']?.toString() ?? '',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(a['email']?.toString() ?? '',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(children: [
                            _Badge('T${a['tier'] ?? '?'}', cs.surfaceContainerHigh, cs.onSurface),
                            const SizedBox(width: 6),
                            _Badge('$docCount/4 dok',
                                docCount == 4 ? _green.withValues(alpha: 0.12) : _amber.withValues(alpha: 0.12),
                                docCount == 4 ? _green : _amber),
                            const SizedBox(width: 6),
                            _Badge('$photoCount/4 foto',
                                photoCount == 4 ? _green.withValues(alpha: 0.12) : _amber.withValues(alpha: 0.12),
                                photoCount == 4 ? _green : _amber),
                            if (isSelected) ...[
                              const Spacer(),
                              const Icon(Icons.chevron_right, size: 16, color: _amber),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            _fmtDate(a['submitted_at']?.toString() ?? a['created_at']?.toString()),
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Pagination
          _PaginationBar(
            page: page,
            hasNext: appsAsync.value?.length == _pageSize,
            onPrev: page > 0 ? () => ref.read(_appPageProvider.notifier).state-- : null,
            onNext: (appsAsync.value?.length == _pageSize)
                ? () => ref.read(_appPageProvider.notifier).state++
                : null,
            cs: cs,
          ),
        ]),
      ),

      // ── Right: detail panel ───────────────────────────────────────────────
      Expanded(
        child: selectedId == null
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.inbox_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Pilih pendaftaran untuk ditinjau',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
              ]))
            : _ApplicationDetailPanel(
                key: ValueKey('app_$selectedId'),
                applicationId: selectedId,
                cs: cs,
                onActionDone: () {
                  ref.invalidate(_applicationsProvider);
                  ref.read(_selectedApplicationIdProvider.notifier).state = null;
                },
              ),
      ),
    ]);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return _green;
      case 'rejected': return _red;
      case 'pending': return _amber;
      default: return _blue;
    }
  }

  String _fmtDate(String? dt) {
    if (dt == null) return '—';
    try { return DateFormat('d MMM yyyy, HH:mm').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return dt; }
  }
}

// ─── Tab: Active Partners ─────────────────────────────────────────────────────

class _PartnersTab extends ConsumerStatefulWidget {
  final ColorScheme cs;
  const _PartnersTab({required this.cs});

  @override
  ConsumerState<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends ConsumerState<_PartnersTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final page = ref.watch(_partnerPageProvider);
    final status = ref.watch(_partnerStatusFilterProvider);
    final search = ref.watch(_partnerSearchProvider);
    final selectedId = ref.watch(_selectedPartnerIdProvider);
    final partnersAsync = ref.watch(_partnersProvider((page, status, search)));

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Left: table ──────────────────────────────────────────────────────
      Container(
        width: 340,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border(right: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  ref.read(_partnerSearchProvider.notifier).state = v.toLowerCase();
                  ref.read(_partnerPageProvider.notifier).state = 0;
                },
                decoration: InputDecoration(
                  hintText: 'Cari nama / email…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in ['all', 'approved', 'pending', 'rejected'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          ref.read(_partnerStatusFilterProvider.notifier).state = s;
                          ref.read(_partnerPageProvider.notifier).state = 0;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: status == s
                                ? _statusColor(s).withValues(alpha: 0.15)
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            s == 'all' ? 'Semua' :
                            s == 'approved' ? 'Approved' :
                            s == 'pending' ? 'Pending' : 'Rejected',
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold,
                              color: status == s ? _statusColor(s) : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: partnersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e',
                  style: TextStyle(color: cs.error, fontSize: 12))),
              data: (partners) {
                if (partners.isEmpty) {
                  return Center(child: Text('Tidak ada mitra.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)));
                }
                return ListView.separated(
                  itemCount: partners.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                  itemBuilder: (ctx, i) {
                    final p = partners[i];
                    final id = p['id']?.toString() ?? '';
                    final isSelected = selectedId == id;
                    final pStatus = p['status']?.toString() ?? 'pending';
                    final isActive = p['is_active'] == true;
                    final docCount = _docKeyColumns.values.where((k) => p[k] != null).length;
                    return InkWell(
                      onTap: () {
                        ref.read(_selectedPartnerIdProvider.notifier).state = id;
                        ref.read(_selectedApplicationIdProvider.notifier).state = null;
                      },
                      child: Container(
                        color: isSelected ? _red.withValues(alpha: 0.06) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Container(width: 8, height: 8,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive ? _green : cs.outlineVariant)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              p['shop_name']?.toString().isNotEmpty == true
                                  ? p['shop_name'].toString()
                                  : p['entity_name']?.toString() ?? '—',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(p['email']?.toString() ?? '',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(children: [
                              _Badge('T${p['tier'] ?? '?'}', cs.surfaceContainerHigh, cs.onSurface),
                              const SizedBox(width: 6),
                              _Badge('$docCount/4 dok',
                                  docCount == 4 ? _green.withValues(alpha: 0.12) : _amber.withValues(alpha: 0.12),
                                  docCount == 4 ? _green : _amber),
                            ]),
                          ])),
                          const SizedBox(width: 8),
                          _StatusChip(pStatus),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _PaginationBar(
            page: page,
            hasNext: partnersAsync.value?.length == _pageSize,
            onPrev: page > 0 ? () => ref.read(_partnerPageProvider.notifier).state-- : null,
            onNext: (partnersAsync.value?.length == _pageSize)
                ? () => ref.read(_partnerPageProvider.notifier).state++
                : null,
            cs: cs,
          ),
        ]),
      ),

      // ── Right: partner detail ─────────────────────────────────────────────
      Expanded(
        child: selectedId == null
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.store_mall_directory_outlined, size: 64,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('Pilih mitra untuk melihat detail',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
              ]))
            : _PartnerDetailPanel(
                key: ValueKey(selectedId),
                partnerId: selectedId,
                cs: cs,
                onStatusChanged: () => ref.invalidate(_partnersProvider),
              ),
      ),
    ]);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved': return _green;
      case 'rejected': return _red;
      case 'pending': return _amber;
      default: return _blue;
    }
  }
}

// ─── Pagination bar ───────────────────────────────────────────────────────────
class _PaginationBar extends StatelessWidget {
  final int page;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ColorScheme cs;
  const _PaginationBar({required this.page, required this.hasNext,
      this.onPrev, this.onNext, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Halaman ${page + 1}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        Row(children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            iconSize: 18,
            color: onPrev != null ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.3),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            iconSize: 18,
            color: onNext != null ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.3),
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ]),
    );
  }
}

// ─── Application detail panel (pre-approval) ─────────────────────────────────
// Full review view for a partner_applications row — all fields, signed-URL docs
// and facility photos, plus Setujui / Revisi / Tolak actions.

class _ApplicationDetailPanel extends ConsumerStatefulWidget {
  final String applicationId;
  final ColorScheme cs;
  final VoidCallback onActionDone;

  const _ApplicationDetailPanel({
    super.key,
    required this.applicationId,
    required this.cs,
    required this.onActionDone,
  });

  @override
  ConsumerState<_ApplicationDetailPanel> createState() =>
      _ApplicationDetailPanelState();
}

class _ApplicationDetailPanelState
    extends ConsumerState<_ApplicationDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _isSaving = false;
  Map<String, dynamic>? _app;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadApplication();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadApplication() async {
    try {
      final row = await Supabase.instance.client
          .from('partner_applications')
          .select()
          .eq('id', widget.applicationId)
          .single();
      if (mounted) setState(() { _app = Map<String, dynamic>.from(row); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openFile(String key, String label) async {
    try {
      final url = await Supabase.instance.client.storage
          .from('revive-photos')
          .createSignedUrl(key, 3600);
      final messenger = ScaffoldMessenger.of(context);
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        messenger.showSnackBar(const SnackBar(content: Text('URL disalin ke clipboard')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red));
      }
    }
  }

  Future<String?> _showReasonDialog({
    required String title,
    required String hint,
    required String actionLabel,
    required Color actionColor,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wajib diisi — akan dikirim ke mitra via WhatsApp & email.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Batal', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: actionColor, foregroundColor: Colors.white),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _approve() async {
    setState(() => _isSaving = true);
    try {
      final res = await Supabase.instance.client.functions
          .invoke('approve-partner', body: {'applicationId': widget.applicationId});
      if ((res.data as Map?)?['error'] != null) throw Exception(res.data['error']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pendaftaran disetujui — mitra diundang.'),
            backgroundColor: _green));
        widget.onActionDone();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red));
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _reject() async {
    final reason = await _showReasonDialog(
      title: 'Tolak Pendaftaran',
      hint: 'Jelaskan alasan penolakan kepada mitra…',
      actionLabel: 'Tolak & Kirim Notifikasi',
      actionColor: _red,
    );
    if (reason == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
          'reject-partner', body: {'applicationId': widget.applicationId, 'reason': reason});
      if ((res.data as Map?)?['error'] != null) throw Exception(res.data['error']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pendaftaran ditolak — mitra dinotifikasi.'),
            backgroundColor: _red));
        widget.onActionDone();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red));
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _requestRevision() async {
    final notes = await _showReasonDialog(
      title: 'Minta Revisi',
      hint: 'Dokumen X belum lengkap, foto Y kurang jelas…',
      actionLabel: 'Kirim Permintaan Revisi',
      actionColor: _amber,
    );
    if (notes == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
          'request-revision-partner',
          body: {'applicationId': widget.applicationId, 'notes': notes});
      if ((res.data as Map?)?['error'] != null) throw Exception(res.data['error']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permintaan revisi terkirim.'),
            backgroundColor: _amber));
        widget.onActionDone();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red));
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error', style: TextStyle(color: cs.error)));
    final app = _app!;

    final shop = app['shop_name']?.toString() ?? 'Unnamed';
    final entity = app['entity_name']?.toString() ?? '';
    final status = app['status']?.toString() ?? 'pending';
    final tier = (app['tier'] as num?)?.toInt() ?? 0;

    final docs = <String, String>{};
    for (final e in {'NIB': 'nib_file_key', 'NPWP': 'npwp_file_key',
        'SIUP': 'siup_file_key', 'KTP': 'ktp_file_key'}.entries) {
      if (app[e.value] != null) docs[e.key] = app[e.value].toString();
    }
    final photos = (app['facility_photo_keys'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => m['file_key'] != null)
            .toList() ??
        [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ───────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.inbox_outlined, color: _amber, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
              Text(entity, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(children: [
                _StatusChip(status),
                const SizedBox(width: 8),
                if (tier > 0) _Badge('Tier $tier', cs.surfaceContainerHigh, cs.onSurface),
                const SizedBox(width: 8),
                _Badge('Pendaftaran Baru', _amber.withValues(alpha: 0.12), _amber),
              ]),
            ])),
            // Action buttons
            _isSaving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: _amber, strokeWidth: 2))
                : Wrap(spacing: 8, children: [
                    ElevatedButton.icon(
                      onPressed: _approve,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Setujui'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _requestRevision,
                      icon: const Icon(Icons.edit_note_outlined, size: 16),
                      label: const Text('Revisi'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _amber, side: const BorderSide(color: _amber),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reject,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Tolak'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _red, side: const BorderSide(color: _red),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    ),
                  ]),
          ]),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: _amber,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: _amber,
            indicatorWeight: 2,
            tabs: const [Tab(text: 'Detail'), Tab(text: 'Dokumen'), Tab(text: 'Foto Fasilitas')],
          ),
        ]),
      ),

      // ── Tab content ───────────────────────────────────────────────────────
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          // ── Tab 0: Details ───────────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Wrap(spacing: 16, runSpacing: 12, children: [
              _InfoCard('Identitas Bisnis', [
                ('Nama Entitas Hukum', app['entity_name']),
                ('Nama Workshop', app['shop_name']),
                ('PIC / Manajer', app['owner_name']),
                ('Email', app['email']),
                ('WhatsApp', app['phone']),
                ('Alamat Hukum', app['address']),
                ('Alamat Workshop', app['workshop_address'] ?? app['address']),
              ], cs),
              _InfoCard('Kapasitas & Operasional', [
                ('Tier', 'Tier ${app['tier'] ?? '—'}'),
                ('Merek Cat', app['paint_brand']),
                ('Kapasitas Harian', '${app['throughput_capacity'] ?? '—'} panel/hari'),
                ('Radius Layanan', '${app['service_radius_km'] ?? '—'} km'),
              ], cs),
              _InfoCard('Rekening Payout', [
                ('Bank', app['bank_name']),
                ('Nomor Rekening', app['bank_account_number']),
                ('Nama Pemilik', app['bank_account_holder']),
              ], cs),
              _InfoCard('Lokasi GPS', [
                ('Latitude', app['latitude']?.toString()),
                ('Longitude', app['longitude']?.toString()),
                ('WA Terverifikasi', app['wa_verified'] == true ? 'Ya ✓' : 'Belum'),
              ], cs),
              _InfoCard('Status Pendaftaran', [
                ('Status', app['status']),
                ('Dikirim', _fmtDate(app['submitted_at']?.toString())),
                ('Catatan Revisi', app['revision_notes']),
                ('Alasan Tolak', app['rejection_reason']),
              ], cs),
            ]),
          ),

          // ── Tab 1: Documents ─────────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dokumen legal yang diunggah oleh pelamar.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              for (final entry in {'NIB — Nomor Induk Berusaha': 'nib_file_key',
                  'NPWP Badan Usaha': 'npwp_file_key',
                  'SIUP — Izin Operasional': 'siup_file_key',
                  'KTP Direktur / PIC': 'ktp_file_key'}.entries) ...[
                _AppDocRow(
                  cs: cs,
                  label: entry.key,
                  fileKey: app[entry.value]?.toString(),
                  onOpen: app[entry.value] != null
                      ? () => _openFile(app[entry.value].toString(), entry.key)
                      : null,
                ),
                const SizedBox(height: 10),
              ],
            ]),
          ),

          // ── Tab 2: Facility Photos ────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: photos.isEmpty
                ? Center(child: Text('Tidak ada foto diunggah.',
                    style: TextStyle(color: cs.onSurfaceVariant)))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${photos.length}/4 foto fasilitas diunggah.',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12, crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: photos.map((p) {
                        final key = p['file_key'].toString();
                        final label = p['label']?.toString() ??
                            'Slot ${p['slot'] ?? ''}';
                        return GestureDetector(
                          onTap: () => _openFile(key, label),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SignedImage(
                                fileKey: key,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorWidget: Container(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(Icons.broken_image_outlined,
                                      color: cs.onSurfaceVariant, size: 32)),
                              ),
                            ),
                            Positioned(bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8)),
                                ),
                                child: Row(children: [
                                  Expanded(child: Text(label,
                                      style: const TextStyle(fontSize: 10, color: Colors.white))),
                                  const Icon(Icons.open_in_new, size: 12, color: Colors.white70),
                                ]),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ]),
          ),
        ]),
      ),
    ]);
  }

  String _fmtDate(String? dt) {
    if (dt == null) return '—';
    try {
      return DateFormat('d MMM yyyy, HH:mm').format(DateTime.parse(dt).toLocal());
    } catch (_) { return dt; }
  }
}

// ── Doc row for application detail ───────────────────────────────────────────
class _AppDocRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String? fileKey;
  final VoidCallback? onOpen;
  const _AppDocRow({required this.cs, required this.label, this.fileKey, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final has = fileKey != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: has ? _green.withValues(alpha: 0.4) : cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: has ? _green.withValues(alpha: 0.1) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(has ? Icons.check_circle_outline : Icons.upload_file_outlined,
              color: has ? _green : cs.onSurfaceVariant, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface))),
        if (has)
          OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Buka', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: BorderSide(color: _blue.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          )
        else
          Text('Tidak diunggah', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

// ─── Partner list tile ────────────────────────────────────────────────────────

class _PartnerListTile extends StatelessWidget {
  final Map<String, dynamic> partner;
  final bool isSelected;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _PartnerListTile({
    required this.partner, required this.isSelected,
    required this.cs, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = partner['shop_name']?.toString().isNotEmpty == true
        ? partner['shop_name'].toString()
        : partner['entity_name']?.toString() ?? 'Unnamed Workshop';
    final status = partner['status']?.toString() ?? 'pending';
    final tier = (partner['tier'] as num?)?.toInt() ?? 0;
    final isActive = partner['is_active'] == true;

    // Doc completion
    final docKeys = ['nib_file_key', 'npwp_file_key', 'siup_file_key', 'ktp_file_key'];
    final docCount = docKeys.where((k) => partner[k] != null).length;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? _red.withValues(alpha: 0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // Active dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? _green : cs.outlineVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              if (tier > 0) ...[
                _Badge('T$tier', cs.surfaceContainerHigh, cs.onSurface),
                const SizedBox(width: 4),
              ],
              _Badge('$docCount/4 docs',
                  docCount == 4
                      ? _green.withValues(alpha: 0.15)
                      : _amber.withValues(alpha: 0.15),
                  docCount == 4 ? _green : _amber),
            ]),
          ])),
          const SizedBox(width: 8),
          _StatusChip(status),
        ]),
      ),
    );
  }
}

// ─── Partner detail panel ─────────────────────────────────────────────────────

class _PartnerDetailPanel extends ConsumerStatefulWidget {
  final String partnerId;
  final ColorScheme cs;
  final VoidCallback onStatusChanged;

  const _PartnerDetailPanel({
    super.key,
    required this.partnerId,
    required this.cs,
    required this.onStatusChanged,
  });

  @override
  ConsumerState<_PartnerDetailPanel> createState() => _PartnerDetailPanelState();
}

class _PartnerDetailPanelState extends ConsumerState<_PartnerDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _isSaving = true);
    try {
      // C-24 fix: use admin_review_partner RPC — has real effects (deactivate, audit, membership)
      await Supabase.instance.client.rpc('admin_review_partner', params: {
        'p_partner_id': widget.partnerId,
        'p_decision':   status == 'approved' ? 'approve' : 'reject',
        'p_reason':     null,
      });
      widget.onStatusChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Partner status updated to $status'),
          backgroundColor: status == 'approved' ? _green : _red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red,
        ));
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _updateStatusWithDialog(String decision) async {
    final isRevision = decision == 'revision';
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            isRevision ? 'Minta Revisi' : 'Tolak Mitra',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                isRevision
                    ? 'Jelaskan apa yang perlu diperbaiki — dikirim ke mitra via WhatsApp & email.'
                    : 'Alasan penolakan wajib diisi — dikirim ke mitra via WhatsApp & email.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isRevision
                      ? 'Dokumen X belum lengkap, foto Y kurang jelas…'
                      : 'Alasan penolakan…',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Batal', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: isRevision ? _amber : _red,
                  foregroundColor: Colors.white),
              child: Text(isRevision
                  ? 'Kirim Permintaan Revisi'
                  : 'Tolak & Kirim Notifikasi'),
            ),
          ],
        );
      },
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final fnName = isRevision ? 'request-revision-partner' : 'reject-partner';
      final bodyKey = isRevision ? 'notes' : 'reason';
      final res = await Supabase.instance.client.functions.invoke(
        fnName,
        body: {'applicationId': widget.partnerId, bodyKey: reason},
      );
      if ((res.data as Map?)?['error'] != null) {
        throw Exception(res.data['error']);
      }
      widget.onStatusChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isRevision
              ? 'Permintaan revisi terkirim ke mitra.'
              : 'Pendaftaran ditolak — mitra dinotifikasi.'),
          backgroundColor: isRevision ? _amber : _red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(mapRawErrorToUserMessage(e)),
            backgroundColor: _red));
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('partner_messages').insert({
        'partner_id': widget.partnerId,
        'sender_id': user?.id,
        'content': content.trim(),
        'from_admin': true,
        'is_read': false,
      });
      _notesCtrl.clear();
      ref.invalidate(_partnerMessagesProvider(widget.partnerId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final listAsync = ref.watch(_partnersProvider((0, 'all', '')));

    return listAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (partners) {
        final partner = partners.where((p) => p['id'] == widget.partnerId).firstOrNull;
        if (partner == null) return const Center(child: Text('Partner not found'));

        final name = partner['shop_name']?.toString().isNotEmpty == true
            ? partner['shop_name'].toString()
            : partner['entity_name']?.toString() ?? 'Unnamed Workshop';
        final status = partner['status']?.toString() ?? 'pending';

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Avatar
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.store_outlined, color: _red, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  Text(partner['entity_name']?.toString() ?? '',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(children: [
                    _StatusChip(status),
                    const SizedBox(width: 8),
                    if ((partner['tier'] as num?)?.toInt() != null)
                      _Badge('Tier ${partner['tier']}',
                          cs.surfaceContainerHigh, cs.onSurface),
                    const SizedBox(width: 8),
                    if (partner['is_active'] == true)
                      _Badge('Online', _green.withValues(alpha: 0.1), _green)
                    else
                      _Badge('Offline', cs.surfaceContainerHigh, cs.onSurfaceVariant),
                  ]),
                ])),
                // Assessment action buttons
                if (status == 'pending' || status == 'pending_review' || status == 'approved')
                  _isSaving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: _red, strokeWidth: 2))
                      : Wrap(spacing: 8, children: [
                          if (status != 'approved')
                            ElevatedButton.icon(
                              onPressed: () => _updateStatus('approved'),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Setujui'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                            ),
                          if (status != 'approved')
                            OutlinedButton.icon(
                              onPressed: () => _updateStatusWithDialog('revision'),
                              icon: const Icon(Icons.edit_note_outlined, size: 16),
                              label: const Text('Revisi'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: _amber,
                                  side: const BorderSide(color: _amber),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _updateStatusWithDialog('rejected'),
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Tolak'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: _red,
                                side: const BorderSide(color: _red),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                          ),
                        ]),
              ]),
              const SizedBox(height: 12),
              // Tabs
              TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: _red,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: _red,
                indicatorWeight: 2,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Documents'),
                  Tab(text: 'Facility Photos'),
                  Tab(text: 'Commlink'),
                ],
              ),
            ]),
          ),

          // ── Tab content ────────────────────────────────────────────────
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              // Tab 0: Details
              _DetailsTab(partner: partner, cs: cs),

              // Tab 1: Documents
              _DocumentsTab(partnerId: widget.partnerId, cs: cs),

              // Tab 2: Photos
              _PhotosTab(partnerId: widget.partnerId, cs: cs),

              // Tab 3: Commlink
              _CommlinkTab(
                partnerId: widget.partnerId,
                cs: cs,
                msgCtrl: _notesCtrl,
                onSend: _sendMessage,
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

// ─── Tab: Details ─────────────────────────────────────────────────────────────

class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> partner;
  final ColorScheme cs;
  const _DetailsTab({required this.partner, required this.cs});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(spacing: 16, runSpacing: 12, children: [
        _InfoCard('Business', [
          ('Legal Entity', partner['entity_name']),
          ('Brand Name', partner['shop_name']),
          ('Owner / PIC', partner['owner_name']),
          ('Email', partner['email']),
          ('Phone', partner['phone']),
          ('Address', partner['address']),
        ], cs),
        _InfoCard('Capacity', [
          ('Tier', 'Tier ${partner['tier'] ?? '—'}'),
          ('Paint Brand', partner['paint_brand']),
          ('Working Bays', '${partner['working_bays'] ?? '—'} bays'),
          ('Spray Booths', '${partner['spray_booths'] ?? '—'}'),
          ('Throughput', '${partner['throughput_capacity'] ?? '—'} panels/day'),
          ('Service Radius', '${partner['service_radius_km'] ?? '—'} km'),
        ], cs),
        _InfoCard('Registration', [
          ('Status', partner['status']),
          ('Joined', _fmtDate(partner['created_at']?.toString())),
        ], cs),
      ]),
    );
  }

  String _fmtDate(String? dt) {
    if (dt == null) return '—';
    try {
      final d = DateTime.parse(dt).toLocal();
      return DateFormat('d MMM yyyy').format(d);
    } catch (_) { return dt; }
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, dynamic)> rows;
  final ColorScheme cs;
  const _InfoCard(this.title, this.rows, this.cs);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                letterSpacing: 0.8, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 120,
                  child: Text(r.$1,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
              Expanded(child: Text(r.$2?.toString() ?? '—',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface))),
            ]),
          ),
      ]),
    );
  }
}

// ─── Tab: Documents ───────────────────────────────────────────────────────────

class _DocumentsTab extends ConsumerWidget {
  final String partnerId;
  final ColorScheme cs;
  const _DocumentsTab({required this.partnerId, required this.cs});

  static const _docLabels = {
    'nib':  'NIB — Nomor Induk Berusaha',
    'npwp': 'NPWP Badan Usaha',
    'siup': 'SIUP — Izin Operasional',
    'ktp':  'KTP Direktur / PIC',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(_partnerDocumentsProvider(partnerId));

    return docsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (docs) {
        // Group by doc_type
        final Map<String, List<Map<String, dynamic>>> grouped = {
          'nib': [], 'npwp': [], 'siup': [], 'ktp': [],
        };
        for (final d in docs) {
          final t = d['doc_type']?.toString() ?? '';
          if (grouped.containsKey(t)) grouped[t]!.add(d);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All uploaded documents are preserved. Current version is highlighted.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (final entry in grouped.entries) ...[
              _AdminDocSection(
                label: _docLabels[entry.key] ?? entry.key.toUpperCase(),
                versions: entry.value,
                cs: cs,
              ),
              const SizedBox(height: 14),
            ],
          ]),
        );
      },
    );
  }
}

class _AdminDocSection extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> versions;
  final ColorScheme cs;
  const _AdminDocSection({required this.label, required this.versions, required this.cs});

  @override
  State<_AdminDocSection> createState() => _AdminDocSectionState();
}

class _AdminDocSectionState extends State<_AdminDocSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final hasDocs = widget.versions.isNotEmpty;
    final current = widget.versions.where((v) => v['is_current'] == true).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: hasDocs ? _green.withValues(alpha: 0.3) : cs.outlineVariant),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(hasDocs ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                color: hasDocs ? _green : cs.outlineVariant, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface)),
              if (current != null)
                Text('Current: ${current['file_name']} · ${_fmtDate(current['uploaded_at']?.toString())}',
                    style: const TextStyle(fontSize: 11, color: _green),
                    overflow: TextOverflow.ellipsis),
              if (!hasDocs)
                Text('Not uploaded', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ])),
            if (hasDocs) ...[
              // Download current
              _DownloadButton(
                label: 'Download',
                fileKey: current?['file_key']?.toString() ?? '',
              ),
              const SizedBox(width: 8),
            ],
            if (widget.versions.length > 1)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(foregroundColor: _red),
                child: Text(
                    _expanded ? 'Hide' : '${widget.versions.length} versions',
                    style: const TextStyle(fontSize: 11)),
              ),
          ]),
        ),
        // Version history
        if (_expanded && widget.versions.length > 1) ...[
          Divider(height: 1, color: cs.outlineVariant),
          for (final v in widget.versions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: v['is_current'] == true
                    ? _green.withValues(alpha: 0.05)
                    : null,
                border: Border(bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(children: [
                Icon(
                  v['is_current'] == true
                      ? Icons.radio_button_checked
                      : Icons.history,
                  size: 14,
                  color: v['is_current'] == true ? _green : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v['file_name']?.toString() ?? '—',
                      style: TextStyle(fontSize: 12, color: cs.onSurface)),
                  Text(
                    '${_fmtDate(v['uploaded_at']?.toString())}'
                    '${v['file_size'] != null ? ' · ${_fmtSize(v['file_size'] as int)}' : ''}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ])),
                if (v['is_current'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('current',
                        style: TextStyle(fontSize: 9, color: _green, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 8),
                _DownloadButton(
                    label: 'DL',
                    fileKey: v['file_key']?.toString() ?? ''),
              ]),
            ),
        ],
      ]),
    );
  }

  String _fmtDate(String? dt) {
    if (dt == null) return '—';
    try {
      final d = DateTime.parse(dt).toLocal();
      return DateFormat('d MMM yyyy HH:mm').format(d);
    } catch (_) { return dt; }
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// ─── Tab: Facility Photos ─────────────────────────────────────────────────────

class _PhotosTab extends ConsumerWidget {
  final String partnerId;
  final ColorScheme cs;
  const _PhotosTab({required this.partnerId, required this.cs});

  static const _slotLabels = [
    'Workshop Facade', 'Spray Oven Booth', 'Customer Lounge', 'Mixing Station'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(_partnerPhotosProvider(partnerId));
    final sb = Supabase.instance.client;

    return photosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (photos) {
        // Group by slot
        final List<List<Map<String, dynamic>>> slots = [[], [], [], []];
        for (final p in photos) {
          final slot = (p['slot'] as num?)?.toInt() ?? 0;
          if (slot >= 0 && slot <= 3) slots[slot].add(p);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All facility photo uploads are preserved. Each slot shows the latest version.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            for (int i = 0; i < 4; i++) ...[
              Text(_slotLabels[i].toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      letterSpacing: 0.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              _AdminPhotoSlot(
                slotPhotos: slots[i],
                cs: cs,
                sb: sb,
              ),
              const SizedBox(height: 16),
            ],
          ]),
        );
      },
    );
  }
}

class _AdminPhotoSlot extends StatefulWidget {
  final List<Map<String, dynamic>> slotPhotos;
  final ColorScheme cs;
  final SupabaseClient sb;
  const _AdminPhotoSlot({required this.slotPhotos, required this.cs, required this.sb});

  @override
  State<_AdminPhotoSlot> createState() => _AdminPhotoSlotState();
}

class _AdminPhotoSlotState extends State<_AdminPhotoSlot> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final current = widget.slotPhotos.where((p) => p['is_current'] == true).firstOrNull;
    final hasPhoto = current != null;

    String? publicUrl;
    if (hasPhoto) {
      final key = current['file_key']?.toString() ?? '';
      // SEC-04: Bucket private — simpan file_key, bukan public URL
      // TODO: Load signed URL async: await signedPhotoUrl(key)
      publicUrl = key.isNotEmpty ? key : null;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Photo preview
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                bottomLeft: Radius.circular(9)),
            child: SizedBox(
              width: 160, height: 110,
              child: hasPhoto
                  ? SignedImage(fileKey: publicUrl, fit: BoxFit.cover,
                      errorWidget: Icon(Icons.image_not_supported_outlined,
                          color: cs.onSurfaceVariant, size: 36))
                  : Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      child: Icon(Icons.add_photo_alternate_outlined,
                          color: cs.onSurfaceVariant, size: 36)),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hasPhoto ? 'Photo uploaded' : 'No photo yet',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface)),
              if (hasPhoto)
                Text(_fmtDate(current['uploaded_at']?.toString()),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              if (widget.slotPhotos.length > 1) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => setState(() => _showHistory = !_showHistory),
                  child: Text(
                    _showHistory
                        ? 'Hide history'
                        : '${widget.slotPhotos.length} versions — show history',
                    style: const TextStyle(fontSize: 11, color: _red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ]),
          )),
          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _DownloadButton(
                  label: 'Download',
                  fileKey: current['file_key']?.toString() ?? ''),
            ),
        ]),
        // History
        if (_showHistory && widget.slotPhotos.length > 1) ...[
          Divider(height: 1, color: cs.outlineVariant),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              itemCount: widget.slotPhotos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final p = widget.slotPhotos[i];
                final key = p['file_key']?.toString() ?? '';
                // SEC-04: Bucket private — simpan file_key, UI request signed URL on-demand
                // TODO: FutureBuilder dengan await signedPhotoUrl(key)
                final url = key;  // file_key sementara
                final isCurrent = p['is_current'] == true;
                return Stack(children: [
                  SignedImage(
                    fileKey: url,
                    width: 80, height: 80, fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(6),
                    errorWidget: Container(width: 80, height: 80, color: cs.surfaceContainerHighest),
                  ),
                  if (isCurrent)
                    Positioned(top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: _green, shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 10, color: Colors.white),
                      ),
                    ),
                  Positioned(bottom: 2, left: 2, right: 2,
                    child: Text(_fmtDate(p['uploaded_at']?.toString()),
                        style: const TextStyle(
                            fontSize: 7, color: Colors.white,
                            shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                        textAlign: TextAlign.center),
                  ),
                ]);
              },
            ),
          ),
        ],
      ]),
    );
  }

  String _fmtDate(String? dt) {
    if (dt == null) return '—';
    try {
      final d = DateTime.parse(dt).toLocal();
      return DateFormat('d MMM yy').format(d);
    } catch (_) { return '—'; }
  }
}

// ─── Tab: Commlink ────────────────────────────────────────────────────────────

class _CommlinkTab extends ConsumerWidget {
  final String partnerId;
  final ColorScheme cs;
  final TextEditingController msgCtrl;
  final void Function(String) onSend;

  const _CommlinkTab({
    required this.partnerId, required this.cs,
    required this.msgCtrl, required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgsAsync = ref.watch(_partnerMessagesProvider(partnerId));

    return Column(children: [
      Expanded(
        child: msgsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (messages) {
            if (messages.isEmpty) {
              return Center(child: Text('No messages yet.',
                  style: TextStyle(color: cs.onSurfaceVariant)));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (ctx, i) {
                final m = messages[i];
                final isAdmin = m['from_admin'] == true;
                final content = m['content']?.toString() ?? '';
                final dt = DateTime.tryParse(m['created_at']?.toString() ?? '');
                return Align(
                  alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isAdmin
                          ? _red.withValues(alpha: 0.1)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isAdmin ? 12 : 0),
                        bottomRight: Radius.circular(isAdmin ? 0 : 12),
                      ),
                      border: Border.all(
                          color: isAdmin
                              ? _red.withValues(alpha: 0.2)
                              : cs.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Column(crossAxisAlignment: isAdmin
                        ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                      Text(isAdmin ? 'Admin' : 'Partner',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isAdmin ? _red : cs.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(content, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                      if (dt != null) ...[
                        const SizedBox(height: 4),
                        Text(DateFormat('d MMM HH:mm').format(dt.toLocal()),
                            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                      ],
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
      // Reply bar
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: msgCtrl,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'Send a message as admin…',
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              onSubmitted: onSend,
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => onSend(msgCtrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Icon(Icons.send_rounded, size: 18),
          ),
        ]),
      ),
    ]);
  }
}

// ─── Shared micro-widgets ─────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  Color get _color {
    switch (status) {
      case 'approved': return _green;
      case 'rejected': return _red;
      case 'pending':  return _amber;
      default:         return _blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12)),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _color),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold)),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _EvidenceChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.attach_file, size: 10, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 10, color: cs.onSurface)),
        ]),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final String label;
  final String fileKey;
  const _DownloadButton({required this.label, required this.fileKey});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: fileKey.isEmpty
          ? null
          : () async {
              try {
                final url = await Supabase.instance.client.storage
                    .from('revive-photos')
                    .createSignedUrl(fileKey, 3600);
                // C-28 fix: open URL directly with launchUrl
                final uri = Uri.parse(url);
                final messenger = ScaffoldMessenger.of(context);
                final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!launched && context.mounted) {
                  // Fallback: copy to clipboard
                  await Clipboard.setData(ClipboardData(text: url));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('URL disalin ke clipboard')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(mapRawErrorToUserMessage(e)), backgroundColor: _red),
                  );
                }
              }
            },
      icon: const Icon(Icons.download_outlined, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          side: BorderSide(color: _blue.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
    );
  }
}
