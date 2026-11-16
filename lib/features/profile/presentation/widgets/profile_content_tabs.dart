import 'package:flutter/material.dart';
import 'package:strazh/features/gifts/presentation/widgets/gift_nft_card.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/features/stories/presentation/screens/stories_screen.dart';

class ProfileContentTabs extends StatefulWidget {
  const ProfileContentTabs({
    super.key,
    required this.stories,
    required this.isLoadingStories,
    required this.storiesError,
    required this.onRetryStories,
    required this.gifts,
    required this.isLoadingGifts,
    required this.canManageGifts,
    required this.onGiftUpgraded,
    required this.onGiftPinned,
    required this.ownerId,
    required this.ownerName,
    required this.ownerTag,
    required this.ownerAvatarUrl,
  });

  final List<Story> stories;
  final bool isLoadingStories;
  final String? storiesError;
  final VoidCallback onRetryStories;
  final List<Map<String, dynamic>> gifts;
  final bool isLoadingGifts;
  final bool canManageGifts;
  final ValueChanged<Map<String, dynamic>> onGiftUpgraded;
  final ValueChanged<Map<String, dynamic>> onGiftPinned;
  final String ownerId;
  final String ownerName;
  final String ownerTag;
  final String ownerAvatarUrl;

  @override
  State<ProfileContentTabs> createState() => _ProfileContentTabsState();
}

class _ProfileContentTabsState extends State<ProfileContentTabs> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final storiesLabel = widget.stories.isEmpty
        ? 'Публикации'
        : 'Публикации ${widget.stories.length}';
    final giftsLabel = widget.gifts.isEmpty
        ? 'Подарки'
        : 'Подарки ${widget.gifts.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF171329).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF9B5CFF).withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              _buildTab(0, storiesLabel, Icons.auto_awesome_outlined),
              _buildTab(1, giftsLabel, Icons.card_giftcard_outlined),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _selectedTab == 0 ? _buildStories() : _buildGifts(),
        ),
      ],
    );
  }

  Widget _buildTab(int index, String title, IconData icon) {
    final selected = _selectedTab == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => setState(() => _selectedTab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF7442F5) : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? Colors.white : Colors.white60,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStories() {
    if (widget.isLoadingStories) return _loadingIndicator();
    if (widget.storiesError != null) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        text: 'Не удалось загрузить публикации',
        action: TextButton.icon(
          onPressed: widget.onRetryStories,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Повторить'),
        ),
      );
    }
    if (widget.stories.isEmpty) {
      return const _MessageState(
        icon: Icons.auto_awesome_outlined,
        text: 'Пока нет активных историй',
      );
    }

    return GridView.builder(
      key: const ValueKey('profile-stories'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 0.72,
      ),
      itemCount: widget.stories.length,
      itemBuilder: (context, index) {
        final story = widget.stories[index];
        return _StoryTile(
          story: story,
          onTap: () => openStoriesForProfile(
            context,
            widget.stories,
            initialIndex: index,
          ),
        );
      },
    );
  }

  Widget _buildGifts() {
    if (widget.isLoadingGifts) return _loadingIndicator();
    if (widget.gifts.isEmpty) {
      return const _MessageState(
        icon: Icons.card_giftcard_outlined,
        text: 'Подарков пока нет',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 9.0;
        final cardWidth = (constraints.maxWidth - spacing * 2) / 3;
        return GridView.builder(
          key: const ValueKey('profile-gifts'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: 1,
          ),
          itemCount: widget.gifts.length,
          itemBuilder: (context, index) {
            final gift = widget.gifts[index];
            return GiftNftCard(
              gift: gift,
              width: cardWidth,
              profileGrid: true,
              canUpgrade: widget.canManageGifts,
              onUpgraded: widget.onGiftUpgraded,
              canPin: widget.canManageGifts,
              onPinned: widget.onGiftPinned,
              ownerId: widget.ownerId,
              ownerName: widget.ownerName,
              ownerTag: widget.ownerTag,
              ownerAvatarUrl: widget.ownerAvatarUrl,
            );
          },
        );
      },
    );
  }

  Widget _loadingIndicator() {
    return const SizedBox(
      height: 110,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Color(0xFF9B5CFF),
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _storyColor(story.backgroundColor);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (story.imageUrl != null)
              Image.network(
                story.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: color,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white60,
                  ),
                ),
              ),
            if (story.imageUrl != null)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
            if (story.imageUrl == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    story.text,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Color _storyColor(String value) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    return Color((parsed ?? 0x6C4AB6) | 0xFF000000);
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF171329),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF9B5CFF).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white38, size: 31),
          const SizedBox(height: 9),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          ?action,
        ],
      ),
    );
  }
}
