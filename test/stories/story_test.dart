import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/shared/domain/models/story.dart';
import 'package:strazh/core/utils/subscription_utils.dart';

void main() {
  test('story parses its author, text, color, and expiration', () {
    final story = Story.fromJson({
      'id': 'story-1',
      'user_id': 'user-1',
      'author_name': 'Алексей',
      'author_tag': 'alex',
      'author_avatar_url': null,
      'content': 'Привет!',
      'image_url': 'https://example.test/story-photo.jpg',
      'background_color': '#6C4AB6',
      'text_position_x': 0.8,
      'text_position_y': 0.25,
      'created_at': '2026-11-01T10:00:00Z',
      'expires_at': '2026-11-02T10:00:00Z',
    });

    expect(story.id, 'story-1');
    expect(story.authorName, 'Алексей');
    expect(story.authorTag, 'alex');
    expect(story.text, 'Привет!');
    expect(story.imageUrl, 'https://example.test/story-photo.jpg');
    expect(story.backgroundColor, '#6C4AB6');
    expect(story.textPositionX, 0.8);
    expect(story.textPositionY, 0.25);
    expect(story.expiresAt.difference(story.createdAt).inHours, 24);
  });

  test('only an unexpired Infinity subscription counts as active', () {
    expect(
      isPremiumSubscriptionActive({
        'subscription_type': 'premium',
        'subscription_expires_at': 'forever',
      }),
      isTrue,
    );
    expect(
      isPremiumSubscriptionActive({
        'subscription_type': 'premium',
        'subscription_plan_id': 'forever',
      }),
      isTrue,
    );
    expect(
      isPremiumSubscriptionActive({
        'subscription_type': 'PREMIUM',
        'subscription_expires_at': '2099-01-01T00:00:00Z',
      }),
      isTrue,
    );
    expect(
      isPremiumSubscriptionActive({
        'subscription_type': 'premium',
        'subscription_expires_at': '2020-01-01T00:00:00Z',
      }),
      isFalse,
    );
    expect(
      isPremiumSubscriptionActive({
        'subscription_type': 'free',
        'subscription_expires_at': '2099-01-01T00:00:00Z',
      }),
      isFalse,
    );
  });
}
