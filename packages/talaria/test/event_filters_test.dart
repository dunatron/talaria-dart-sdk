import 'package:talaria/src/event_filters.dart';
import 'package:test/test.dart';

void main() {
  test('ignoreErrors substring drops Autofill', () {
    expect(
      shouldDropEvent(
        message: "Can't find variable: _AutofillCallbackHandler",
        ignoreErrors: ['_AutofillCallbackHandler'],
        ignoreUrls: const [],
      ),
      isTrue,
    );
    expect(
      shouldDropEvent(
        message: 'Checkout failed',
        ignoreErrors: ['_AutofillCallbackHandler'],
        ignoreUrls: const [],
      ),
      isFalse,
    );
  });

  test('ignoreUrls matches stack frames', () {
    expect(
      shouldDropEvent(
        message: 'boom',
        stackTrace: 'at x (https://connect.facebook.net/sdk.js:1:1)',
        ignoreErrors: const [],
        ignoreUrls: ['facebook.net'],
      ),
      isTrue,
    );
  });
}
