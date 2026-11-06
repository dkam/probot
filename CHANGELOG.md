## [Unreleased]

## [0.6.0]

- Match rules from the start of the path, so `Disallow: /ab` no longer blocks `/x/ab`
- Match user-agent groups on the product token, case-insensitively (`twitterbot` applies to `Twitterbot/1.0`)
- Match full URLs against their path and query, so `Disallow: /` no longer matches every URL's scheme
- `$` anchors the end only as the last character of a pattern
- Strip comments anywhere on a line, a leading UTF-8 byte order mark, and accept lines missing their colon
- Accept Google's directive typos (`useragent`, `disalow`, ...)
- Percent-encode non-ASCII octets in patterns before matching
- Rules are `Probot::Rule`s (still Regexps) that carry their line number and group, and `#decisive_rule` returns the one that decided a URL
- Port the RFC test cases from Google's robots.txt parser

## [0.5.0] - 2024-12-24

- Fix bug with Disallow rule containing empty line

## [0.4.0] - 2024-10-31

- Ensure VERISON is available

## [0.3.0] - 2023-09-18

- Only return unique sitemaps.

## [0.2.0] - 2023-09-10

- Correctly handle multiple sitemaps + tests.
## [0.1.0] - 2023-09-09

- Initial release
