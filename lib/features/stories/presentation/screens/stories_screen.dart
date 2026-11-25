import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/features/settings/presentation/screens/subscription_screen.dart';
import 'package:strazh/features/stories/data/services/stories_service.dart';

const _storyColors = <String>[
  '#6C4AB6',
  '#C44569',
  '#D97706',
  '#168C83',
  '#2864B4',
];

Color _storyColor(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.parse(hex, radix: 16) | 0xFF000000);
}

Future<void> openStoriesForProfile(
  BuildContext context,
  List<Story> stories, {
  required int initialIndex,
  bool canDeleteStories = false,
}) async {
  if (stories.isEmpty) return;
  final selectedStoryId = stories[initialIndex].id;
  final orderedStories = [...stories]
    ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
  final orderedInitialIndex = orderedStories.indexWhere(
    (story) => story.id == selectedStoryId,
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _StoryViewer(
        stories: orderedStories,
        initialIndex: orderedInitialIndex,
        canDeleteStories: canDeleteStories,
      ),
    ),
  );
}

class StoriesBar extends StatefulWidget {
  final String? currentUserId;

  const StoriesBar({super.key, required this.currentUserId});

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> with WidgetsBindingObserver {
  late Future<List<Story>> _storiesFuture;
  bool _isComposing = false;
  Timer? _refreshTimer;
  int _storiesLoadKey = 0;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StoriesService.storiesRevision.addListener(_onStoriesChanged);
    _storiesFuture = StoriesService.getActiveStories();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshStories(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    StoriesService.storiesRevision.removeListener(_onStoriesChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStories();
  }

  void _onStoriesChanged() {
    _refreshStories();
  }

  Future<void> _refreshStories() async {
    final generation = ++_refreshGeneration;
    final storiesFuture = StoriesService.getActiveStories();
    if (mounted) {
      setState(() {
        _storiesLoadKey++;
        _storiesFuture = storiesFuture;
      });
    }

    try {
      final stories = await storiesFuture;
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _storiesLoadKey++;
        _storiesFuture = Future.value(stories);
      });
    } catch (error) {
      if (generation != _refreshGeneration) return;
      debugPrint('Не удалось обновить ленту историй: $error');
    }
  }

  Future<void> _openStory(
    List<List<Story>> authors,
    int initialAuthorIndex,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StoryViewer(
          stories: authors[initialAuthorIndex],
          initialIndex: 0,
          allAuthors: authors,
          initialAuthorIndex: initialAuthorIndex,
          canDeleteStories:
              widget.currentUserId != null &&
              widget.currentUserId == authors[initialAuthorIndex].first.userId,
        ),
      ),
    );
    await _refreshStories();
  }

  Future<void> _composeStory() async {
    if (_isComposing) return;
    _isComposing = true;
    try {
      bool canPublish;
      try {
        canPublish = await StoriesService.refreshPublishAccess();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось проверить подписку: $error')),
        );
        return;
      }

      if (!mounted) return;

      if (!canPublish) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
        if (!mounted) return;
        try {
          canPublish = await StoriesService.refreshPublishAccess();
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось проверить подписку: $error')),
          );
          return;
        }
        if (!mounted || !canPublish) return;
      }

      final published = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF17131F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const _StoryComposer(),
      );
      if (!mounted || published != true) return;

      await _refreshStories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История опубликована на 24 часа')),
      );
    } finally {
      _isComposing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: FutureBuilder<List<Story>>(
        key: ValueKey(_storiesLoadKey),
        future: _storiesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Row(
              children: [
                const Expanded(
                  child: Text(
                    'Не удалось загрузить истории',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                IconButton(
                  tooltip: 'Повторить',
                  onPressed: () => setState(
                    () => _storiesFuture = StoriesService.getActiveStories(),
                  ),
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final grouped = <String, List<Story>>{};
          for (final story in snapshot.data!) {
            grouped.putIfAbsent(story.userId, () => []).add(story);
          }
          for (final stories in grouped.values) {
            stories.sort(
              (first, second) => first.createdAt.compareTo(second.createdAt),
            );
          }
          final currentUserStories = grouped.remove(widget.currentUserId) ?? [];
          final authors = [
            if (currentUserStories.isNotEmpty) currentUserStories,
            ...grouped.values,
          ];

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              _StoryAvatar(
                title: 'Моя история',
                name:
                    Supabase
                        .instance
                        .client
                        .auth
                        .currentUser
                        ?.userMetadata?['name']
                        ?.toString() ??
                    'Вы',
                avatarUrl: Supabase
                    .instance
                    .client
                    .auth
                    .currentUser
                    ?.userMetadata?['avatar_url']
                    ?.toString(),
                hasStory: currentUserStories.isNotEmpty,
                isOwn: true,
                onTap: currentUserStories.isEmpty
                    ? _composeStory
                    : () => _openStory(
                        authors,
                        authors.indexOf(currentUserStories),
                      ),
                onAdd: _composeStory,
              ),
              ...grouped.values.map(
                (stories) => _StoryAvatar(
                  title: stories.first.authorName,
                  name: stories.first.authorName,
                  avatarUrl: stories.first.authorAvatarUrl,
                  hasStory: true,
                  onTap: () => _openStory(authors, authors.indexOf(stories)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final String title;
  final String name;
  final String? avatarUrl;
  final bool hasStory;
  final bool isOwn;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  const _StoryAvatar({
    required this.title,
    required this.name,
    required this.avatarUrl,
    required this.hasStory,
    required this.onTap,
    this.isOwn = false,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final image = avatarUrl == null || avatarUrl!.isEmpty
        ? null
        : NetworkImage(avatarUrl!);

    return SizedBox(
      width: 76,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStory
                        ? const LinearGradient(
                            colors: [Color(0xFF9B5DE5), Color(0xFFF15BB5)],
                          )
                        : null,
                    border: hasStory
                        ? null
                        : Border.all(color: Colors.white24, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFF27232E),
                    backgroundImage: image,
                    child: image == null
                        ? Text(
                            initial,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                ),
                if (isOwn)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0D0A0A),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class StoriesScreen extends StatefulWidget {
  final String? initialUserId;
  final bool openComposerOnStart;

  const StoriesScreen({
    super.key,
    this.initialUserId,
    this.openComposerOnStart = false,
  });

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  late Future<List<Story>> _storiesFuture;
  bool _isComposing = false;
  bool _openedComposer = false;

  @override
  void initState() {
    super.initState();
    _storiesFuture = StoriesService.getActiveStories();
  }

  Future<void> _composeStory() async {
    if (!StoriesService.canPublish) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
      if (!mounted) return;
      setState(() {});
      if (StoriesService.canPublish) {
        await _composeStory();
      }
      return;
    }
    if (_isComposing) return;
    _isComposing = true;
    try {
      final published = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF17131F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const _StoryComposer(),
      );
      if (published == true && mounted) {
        setState(() => _storiesFuture = StoriesService.getActiveStories());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('История опубликована на 24 часа')),
        );
        Navigator.of(context).pop(true);
      }
    } finally {
      _isComposing = false;
    }
  }

  void _openStory(List<Story> stories, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _StoryViewer(stories: stories, initialIndex: initialIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.openComposerOnStart && !_openedComposer) {
      _openedComposer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _composeStory();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0A0A),
        title: const Text('Истории'),
        actions: [
          IconButton(
            tooltip: StoriesService.canPublish
                ? 'Добавить историю'
                : 'Открыть Strazh Infinity',
            onPressed: _composeStory,
            icon: Icon(
              StoriesService.canPublish
                  ? Icons.add_circle_outline
                  : Icons.workspace_premium_outlined,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Story>>(
        future: _storiesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Не удалось загрузить истории',
                    style: TextStyle(color: Colors.white70),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _storiesFuture = StoriesService.getActiveStories(),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final grouped = <String, List<Story>>{};
          for (final story in snapshot.data!) {
            grouped.putIfAbsent(story.userId, () => []).add(story);
          }
          for (final stories in grouped.values) {
            stories.sort(
              (first, second) => first.createdAt.compareTo(second.createdAt),
            );
          }
          final authors = grouped.values.toList()
            ..sort(
              (first, second) =>
                  second.last.createdAt.compareTo(first.last.createdAt),
            );
          final selected = widget.initialUserId == null
              ? null
              : grouped[widget.initialUserId];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (authors.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.auto_awesome_outlined,
                        color: Colors.white38,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Пока нет историй',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Поделитесь короткой мыслью с другими',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              else ...[
                const Text(
                  'Новые истории',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: authors
                        .map(
                          (stories) => Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: _StoryAvatar(
                              title: stories.first.authorName,
                              name: stories.first.authorName,
                              avatarUrl: stories.first.authorAvatarUrl,
                              hasStory: true,
                              onTap: () => _openStory(stories, 0),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 20),
                if (selected != null) ...[
                  _StoryPreviewCard(
                    story: selected.first,
                    onTap: () => _openStory(selected, 0),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ещё истории',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ...authors
                    .where(
                      (stories) =>
                          selected == null ||
                          stories.first.userId != selected.first.userId,
                    )
                    .expand(
                      (stories) => stories.map(
                        (story) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StoryPreviewCard(
                            story: story,
                            onTap: () =>
                                _openStory(stories, stories.indexOf(story)),
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StoryPreviewCard extends StatelessWidget {
  final Story story;
  final VoidCallback onTap;

  const _StoryPreviewCard({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = story.authorAvatarUrl;
    final avatarProvider = avatarUrl == null || avatarUrl.isEmpty
        ? null
        : NetworkImage(avatarUrl);
    return Material(
      color: story.imageUrl == null ? _storyColor(story.backgroundColor) : null,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 168,
          child: Stack(
            children: [
              if (story.imageUrl != null)
                Positioned.fill(
                  child: Image.network(
                    story.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Не удалось загрузить фото истории: $error');
                      return ColoredBox(
                        color: _storyColor(story.backgroundColor),
                      );
                    },
                  ),
                ),
              if (story.imageUrl != null)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.black54,
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarProvider,
                          child: avatarProvider == null
                              ? Text(
                                  story.authorName.isEmpty
                                      ? '?'
                                      : story.authorName[0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            story.authorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _timeAgo(story.createdAt),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      story.text.isEmpty ? 'Фото' : story.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryViewer extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;
  final List<List<Story>>? allAuthors;
  final int initialAuthorIndex;
  final bool canDeleteStories;

  const _StoryViewer({
    required this.stories,
    required this.initialIndex,
    this.allAuthors,
    this.initialAuthorIndex = 0,
    this.canDeleteStories = false,
  });

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  late int _index;
  late int _authorIndex;
  late final List<List<Story>> _authors;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _authorIndex = widget.initialAuthorIndex;
    _authors = widget.allAuthors ?? [widget.stories];
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener(_onProgressStatusChanged);
    _startCurrentStory();
  }

  @override
  void dispose() {
    _progressController
      ..removeStatusListener(_onProgressStatusChanged)
      ..dispose();
    super.dispose();
  }

  List<Story> get _currentStories => _authors[_authorIndex];

  void _startCurrentStory() {
    _progressController
      ..stop()
      ..value = 0
      ..forward();
  }

  void _onProgressStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _showNextStory();
  }

  void _showNextStory() {
    if (_index + 1 < _currentStories.length) {
      setState(() => _index++);
      _startCurrentStory();
      return;
    }

    if (_authorIndex + 1 < _authors.length) {
      setState(() {
        _authorIndex++;
        _index = 0;
      });
      _startCurrentStory();
      return;
    }

    Navigator.of(context).pop();
  }

  void _showPreviousStory() {
    if (_index > 0) {
      setState(() => _index--);
      _startCurrentStory();
      return;
    }

    if (_authorIndex > 0) {
      setState(() {
        _authorIndex--;
        _index = _currentStories.length - 1;
      });
      _startCurrentStory();
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _confirmDeleteStory(Story story) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сторис?'),
        content: const Text('Она исчезнет из твоего профиля и ленты.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isDeleting) return;

    setState(() => _isDeleting = true);
    try {
      await StoriesService.delete(story);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final deletedButImageRemains = error.toString().contains(
        'История удалена, но не удалось удалить',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedButImageRemains
                ? 'Сторис удалена, но фото не удалось очистить с сервера.'
                : 'Не удалось удалить сторис: $error',
          ),
        ),
      );
      if (deletedButImageRemains) {
        Navigator.of(context).pop();
      } else {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stories = _currentStories;
    final currentStory = stories[_index];
    final canDeleteCurrentStory =
        widget.canDeleteStories && currentStory.userId == stories.first.userId;
    final avatarUrl = currentStory.authorAvatarUrl;
    final avatarProvider = avatarUrl == null || avatarUrl.isEmpty
        ? null
        : NetworkImage(avatarUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < 0) {
              _showNextStory();
            } else if (velocity > 0) {
              _showPreviousStory();
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: _storyColor(currentStory.backgroundColor),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (currentStory.imageUrl != null)
                        Image.network(
                          currentStory.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint(
                              'Не удалось загрузить фото истории: $error',
                            );
                            return ColoredBox(
                              color: _storyColor(currentStory.backgroundColor),
                            );
                          },
                        ),
                      if (currentStory.imageUrl != null)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black54,
                                Colors.transparent,
                                Colors.black54,
                              ],
                            ),
                          ),
                        ),
                      if (currentStory.text.isNotEmpty)
                        Align(
                          alignment: Alignment(
                            currentStory.textPositionX * 2 - 1,
                            currentStory.textPositionY * 2 - 1,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 72, 28, 64),
                            child: Text(
                              currentStory.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                top: 72,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showPreviousStory,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showNextStory,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) => Row(
                        children: List.generate(stories.length, (index) {
                          return Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Colors.white38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: index < _index
                                      ? 1
                                      : index == _index
                                      ? _progressController.value
                                      : 0,
                                  child: const ColoredBox(color: Colors.white),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundImage: avatarProvider,
                          child: avatarProvider == null
                              ? const Icon(Icons.person, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentStory.authorName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _timeAgo(currentStory.createdAt),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (canDeleteCurrentStory)
                          IconButton(
                            tooltip: 'Удалить сторис',
                            onPressed: _isDeleting
                                ? null
                                : () => _confirmDeleteStory(currentStory),
                            icon: _isDeleting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                  ),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryComposer extends StatefulWidget {
  const _StoryComposer();

  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  String _selectedColor = _storyColors.first;
  Alignment _textAlignment = Alignment.center;
  XFile? _image;
  Uint8List? _imageBytes;
  bool _isPublishing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 2560,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = image;
        _imageBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать фото: $error')),
      );
    }
  }

  Future<void> _publish() async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _image == null) ||
        text.length > 500 ||
        _isPublishing) {
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await StoriesService.publish(
        text: text,
        backgroundColor: _selectedColor,
        textPositionX: (_textAlignment.x + 1) / 2,
        textPositionY: (_textAlignment.y + 1) / 2,
        image: _image,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось опубликовать: $error')),
      );
      setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final color = _storyColor(_selectedColor);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        bottomInset + MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Новая история',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 250,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_imageBytes != null)
                      Image.memory(_imageBytes!, fit: BoxFit.cover)
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, color.withValues(alpha: 0.72)],
                          ),
                        ),
                      ),
                    if (_imageBytes != null)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black38,
                              Colors.transparent,
                              Colors.black45,
                            ],
                          ),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: _textAlignment,
                        child: SizedBox(
                          width: constraints.maxWidth * 0.82,
                          height: 170,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              TextField(
                                controller: _textController,
                                maxLength: 500,
                                maxLines: 5,
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                decoration: InputDecoration(
                                  hintText: _image == null
                                      ? 'О чём думаете?'
                                      : 'Добавьте текст на фото',
                                  hintStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  border: InputBorder.none,
                                  counterStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  filled: _imageBytes != null,
                                  fillColor: Colors.black.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _textAlignment = Alignment(
                                        (_textAlignment.x +
                                                details.delta.dx /
                                                    constraints.maxWidth *
                                                    2)
                                            .clamp(-0.85, 0.85),
                                        (_textAlignment.y +
                                                details.delta.dy / 250 * 2)
                                            .clamp(-0.85, 0.85),
                                      );
                                    });
                                  },
                                  child: Tooltip(
                                    message:
                                        'Перетащите, чтобы передвинуть текст',
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.open_with,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton.filledTonal(
                        tooltip: _image == null
                            ? 'Добавить фото'
                            : 'Заменить фото',
                        onPressed: _pickImage,
                        icon: Icon(
                          _image == null
                              ? Icons.add_photo_alternate_outlined
                              : Icons.photo_camera_back_outlined,
                        ),
                      ),
                    ),
                    if (_image != null)
                      Positioned(
                        top: 10,
                        right: 58,
                        child: IconButton.filledTonal(
                          tooltip: 'Убрать фото',
                          onPressed: () => setState(() {
                            _image = null;
                            _imageBytes = null;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_image == null) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _storyColors.map((value) {
                  final isSelected = value == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = value),
                    child: Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: _storyColor(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _isPublishing ||
                      (_image == null && _textController.text.trim().isEmpty)
                  ? null
                  : _publish,
              icon: _isPublishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Опубликовать'),
            ),
            const SizedBox(height: 8),
            const Text(
              'История исчезнет через 24 часа',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgo(DateTime date) {
  final elapsed = DateTime.now().difference(date.toLocal());
  if (elapsed.inMinutes < 1) return 'сейчас';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} мин';
  if (elapsed.inDays < 1) return '${elapsed.inHours} ч';
  return '${elapsed.inDays} д';
}
