import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UserTreeNode {
  const _UserTreeNode({
    required this.name,
    required this.tag,
    required this.role,
    required this.isOnline,
    required this.invitedBy,
    required this.children,
  });

  final String name;
  final String tag;
  final String role;
  final bool isOnline;
  final String? invitedBy;
  final List<_UserTreeNode> children;
}

class _TreeConnectorPainter extends CustomPainter {
  const _TreeConnectorPainter({required this.childWidths, required this.gap});

  final List<double> childWidths;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    if (childWidths.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF9B7AE8).withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final centers = <double>[];
    var left = 0.0;
    for (final width in childWidths) {
      centers.add(left + width / 2);
      left += width + gap;
    }

    const junctionY = 11.0;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, junctionY),
      paint,
    );
    if (centers.length > 1) {
      canvas.drawLine(
        Offset(centers.first, junctionY),
        Offset(centers.last, junctionY),
        paint,
      );
    }
    for (final center in centers) {
      canvas.drawLine(
        Offset(center, junctionY),
        Offset(center, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeConnectorPainter oldDelegate) {
    return oldDelegate.childWidths != childWidths || oldDelegate.gap != gap;
  }
}

class AdminTreeOfUsersScreen extends StatefulWidget {
  const AdminTreeOfUsersScreen({super.key});

  @override
  State<AdminTreeOfUsersScreen> createState() => _AdminTreeOfUsersScreenState();
}

class _AdminTreeOfUsersScreenState extends State<AdminTreeOfUsersScreen> {
  final TransformationController _treeTransformationController =
      TransformationController();
  bool _isLoading = true;
  List<_UserTreeNode> _tree = const [];

  @override
  void dispose() {
    _treeTransformationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
    try {
      final result = await Supabase.instance.client.rpc('get_all_users');
      if (!mounted) return;

      if (result is! List) {
        setState(() => _isLoading = false);
        return;
      }

      final users = result.cast<Map<String, dynamic>>();
      final usersById = <String, Map<String, dynamic>>{};
      final childrenMap = <String, List<String>>{};
      final inviterByUserId = <String, String>{};

      for (final user in users) {
        final userId = (user['id'] ?? '').toString();
        if (userId.isEmpty) continue;

        final metadata = user['raw_user_meta_data'] is Map
            ? Map<String, dynamic>.from(user['raw_user_meta_data'] as Map)
            : <String, dynamic>{};

        final inviterId =
            (user['invited_by_user_id'] ?? metadata['invited_by_user_id'] ?? '')
                .toString();

        usersById[userId] = {
          'name': (user['name'] ?? metadata['name'] ?? 'Без имени').toString(),
          'tag': (user['tag'] ?? metadata['tag'] ?? '').toString(),
          'role': (user['role'] ?? metadata['role'] ?? 'user').toString(),
          'status': (user['status'] ?? metadata['status'] ?? 'offline')
              .toString(),
        };

        if (inviterId.isNotEmpty) {
          inviterByUserId[userId] = inviterId;
          childrenMap.putIfAbsent(inviterId, () => <String>[]).add(userId);
        }
      }

      _UserTreeNode? buildNode(
        String userId, {
        String? invitedBy,
        Set<String> ancestors = const {},
      }) {
        if (ancestors.contains(userId)) return null;
        final data = usersById[userId];
        if (data == null) return null;

        final name = (data['name'] as String?) ?? 'Без имени';
        final nextAncestors = {...ancestors, userId};
        final childIds = childrenMap[userId] ?? const <String>[];
        final children =
            childIds
                .map(
                  (childId) => buildNode(
                    childId,
                    invitedBy: name,
                    ancestors: nextAncestors,
                  ),
                )
                .whereType<_UserTreeNode>()
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

        final tag = (data['tag'] as String?) ?? '';
        final role = (data['role'] as String?) ?? 'user';
        final status = (data['status'] as String?) ?? 'offline';

        return _UserTreeNode(
          name: name,
          tag: tag.isEmpty
              ? '@user'
              : tag.startsWith('@')
              ? tag
              : '@$tag',
          role: role.isEmpty ? 'user' : role,
          isOnline: status.toLowerCase() == 'online',
          invitedBy: invitedBy,
          children: children,
        );
      }

      final rootIds = usersById.keys
          .where((userId) => !usersById.containsKey(inviterByUserId[userId]))
          .toList();

      final rootNodes =
          rootIds
              .map((userId) => buildNode(userId))
              .whereType<_UserTreeNode>()
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) return;
      setState(() {
        _tree = rootNodes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки дерева пользователей: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Древо пользователей',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Сбросить масштаб и положение',
            onPressed: () {
              _treeTransformationController.value = Matrix4.identity();
            },
            icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            )
          : _tree.isEmpty
          ? const Center(
              child: Text(
                'Пользователи не найдены',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  transformationController: _treeTransformationController,
                  constrained: false,
                  minScale: 0.25,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(1200),
                  clipBehavior: Clip.hardEdge,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildLegend(),
                        const SizedBox(height: 24),
                        ..._tree.map(_buildNode),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  static const double _cardWidth = 236;
  static const double _siblingGap = 28;

  double _subtreeWidth(_UserTreeNode node) {
    if (node.children.isEmpty) return _cardWidth;
    final childrenWidth =
        node.children
            .map(_subtreeWidth)
            .fold<double>(0, (sum, width) => sum + width) +
        _siblingGap * (node.children.length - 1);
    return childrenWidth > _cardWidth ? childrenWidth : _cardWidth;
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF17131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined, color: Color(0xFFA78BFA), size: 17),
          SizedBox(width: 8),
          Text(
            'Линия ведёт к приглашённым · pinch для масштаба · перетаскивание для перемещения',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNode(_UserTreeNode node) {
    final childWidths = node.children.map(_subtreeWidth).toList();
    final childrenWidth = childWidths.isEmpty
        ? 0.0
        : childWidths.fold<double>(0, (sum, width) => sum + width) +
              _siblingGap * (childWidths.length - 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _subtreeWidth(node),
          child: Center(child: _buildUserCard(node)),
        ),
        if (node.children.isNotEmpty) ...[
          SizedBox(
            width: childrenWidth,
            height: 30,
            child: CustomPaint(
              painter: _TreeConnectorPainter(
                childWidths: childWidths,
                gap: _siblingGap,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < node.children.length; index++) ...[
                if (index > 0) const SizedBox(width: _siblingGap),
                SizedBox(
                  width: childWidths[index],
                  child: _buildNode(node.children[index]),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildUserCard(_UserTreeNode node) {
    final initials = node.name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.isNotEmpty ? part[0].toUpperCase() : '')
        .join();

    return Container(
      width: _cardWidth,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1B2E),
            const Color(0xFF151515).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: node.invitedBy == null
              ? const Color(0xFF9B7AE8).withValues(alpha: 0.48)
              : Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              if (node.isOnline)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF151515),
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  node.tag,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _roleColor(node.role).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _roleColor(
                              node.role,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          node.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _roleColor(node.role),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (node.children.isNotEmpty) ...[
                      const SizedBox(width: 7),
                      Text(
                        '${node.children.length} ${_inviteeWord(node.children.length)}',
                        style: const TextStyle(
                          color: Color(0xFFB8A9D8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      node.invitedBy == null
                          ? Icons.account_tree_outlined
                          : Icons.subdirectory_arrow_right,
                      color: const Color(0xFFB49AE8),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        node.invitedBy == null
                            ? 'Пригласивший не указан'
                            : 'Пришёл от ${node.invitedBy}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB49AE8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _inviteeWord(int count) {
    final lastTwo = count % 100;
    final last = count % 10;
    if (lastTwo < 11 || lastTwo > 14) {
      if (last == 1) return 'человек';
      if (last >= 2 && last <= 4) return 'человека';
    }
    return 'человек';
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return const Color(0xFFFBBF24);
      case 'admin':
        return const Color(0xFF60A5FA);
      case 'moderator':
        return const Color(0xFF34D399);
      case 'premium':
        return const Color(0xFFF472B6);
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}
