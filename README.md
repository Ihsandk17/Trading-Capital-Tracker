# Capital Candles (Flutter)

A local-first trading balance journal with trade and daily balance-change candles.

## Run

1. Install Flutter SDK.
2. In this folder run `flutter create . --platforms=android,ios` (generates native platform scaffolding).
3. Run `flutter pub get`.
4. Run `flutter run`.

## How it works

- Set the initial capital with the top-right settings icon.
- Tap **Add result**, select Trade or Daily total, Profit or Loss, amount, and date.
- Per trade shows one candle for each trade entry. Manual daily totals update the balance but do not appear as trade candles.
- Per day groups all entries on each date into one candle.
- Each candle opens at the running account balance and closes at the balance after the entry (or day's sum).
- A dashed line marks initial capital.
- History is saved on device using shared_preferences.

**Important:** Avoid entering a manual daily total for a date if it duplicates the individual trades already entered for that date, or the total will be double counted. Daily totals are additive adjustments in this MVP. Candles are balance-change bodies, not actual market OHLC candles; no high/low intraday prices are recorded.

This is a starter app; no cloud sync, authentication, or broker integration.
