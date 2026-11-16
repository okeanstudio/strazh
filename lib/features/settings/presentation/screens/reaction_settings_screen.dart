import 'package:flutter/material.dart';
import 'package:strazh/core/config/reactions.dart';
import 'package:strazh/features/settings/data/services/reaction_settings_service.dart';

class ReactionSettingsScreen extends StatefulWidget {
  const ReactionSettingsScreen({super.key});

  @override
  State<ReactionSettingsScreen> createState() => _ReactionSettingsScreenState();
}

class _ReactionSettingsScreenState extends State<ReactionSettingsScreen> {
  String _selectedReaction = defaultDoubleTapReaction;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  Future<void> _loadSelection() async {
    final reaction = await ReactionSettingsService.getDoubleTapReaction();
    if (!mounted) return;
    setState(() {
      _selectedReaction = reaction;
      _isLoading = false;
    });
  }

  Future<void> _selectReaction(String reaction) async {
    setState(() => _selectedReaction = reaction);
    await ReactionSettingsService.setDoubleTapReaction(reaction);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        title: const Text('Реакции'),
        backgroundColor: const Color(0xFF0D0A0A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1D3A5F), Color(0xFF20232B)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4F84C4).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        color: Color(0xFF9ABDE9),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Реакция по двойному нажатию',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                      Text(
                        _selectedReaction,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Выберите эмодзи',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableReactionEmojis.map((reaction) {
                    final isSelected = reaction == _selectedReaction;
                    return InkWell(
                      onTap: () => _selectReaction(reaction),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF24466D)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6FA8E8)
                                : Colors.white12,
                          ),
                        ),
                        child: Text(
                          reaction,
                          style: const TextStyle(fontSize: 23),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }
}
