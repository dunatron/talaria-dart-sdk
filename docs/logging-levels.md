# Logger levels and hierarchy

Talaria uses a **Logback / Microsoft.Extensions.Logging-style** hierarchy: client `minLevel` is the **default/root**, and scoped loggers can override it (including becoming more verbose). An opt-in hard floor restores the older “raise only” behaviour.

Same semantics apply to the Dart SDK, PHP SDK, and `@newtalaria/browser`.

## Hierarchy

```text
effectiveLevel(logger) =
  logger.assignedMinLevel
  ?? parent.assignedMinLevel
  ?? client.minLevel

if client.enforceDefaultLevel:
  effectiveLevel = max(client.minLevel, effectiveLevel)
```

| Knob | Default | Role |
| --- | --- | --- |
| `minLevel` | `debug` | Default/root for unset scopes; filters **direct** client captures |
| `enforceDefaultLevel` | `false` | Opt-in hard floor (legacy `max()` safety) |
| Scoped `minLevel` | unset → inherit | Assigned override — may be higher **or** lower than root |
| `sampleRate` → `beforeSend` | unchanged | After the level gate |

### Inheritance rules

1. Unset scope → inherits client `minLevel`.
2. Explicit `minLevel` on `logger` / `child` / `withMinLevel` **assigns** (replaces).
3. Direct `Talaria.info()` / `client.captureMessage` always use client `minLevel`.
4. Scoped captures skip the client floor unless `enforceDefaultLevel` is true.

### Example

```dart
await Talaria.init(TalariaOptions(
  dsn: 'https://api.newtalaria.com',
  apiKey: 'tal_live_…',
  environment: 'production',
  minLevel: SeverityLevel.warning,
  enforceDefaultLevel: false,
  loggers: {
    'checkout': LoggerPreset(
      minLevel: SeverityLevel.info,
      tags: {'area': 'checkout'},
    ),
  },
));

Talaria.logger(name: 'checkout').info('Listing loaded'); // sent
await Talaria.info('root info'); // filtered by warning root
```
