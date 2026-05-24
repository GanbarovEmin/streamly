# Streamly Product Specification v1.0

## 1. Назначение продукта

Streamly — нативное macOS-приложение для поиска, каталогизации и воспроизведения torrent-видео в формате Netflix-like / Apple-like медиаплатформы.

Цель продукта — дать пользователю единый медиаклиент, в котором можно находить релизы, видеть метаданные, выбирать качество, запускать просмотр и продолжать воспроизведение без ручного скачивания файла целиком и без перехода между отдельными torrent-клиентами, файловыми менеджерами и видеоплеерами.

Streamly не является поставщиком контента. Приложение является оболочкой и медиаклиентом, который работает с пользовательскими источниками, локальными данными, metadata providers, subtitle providers, torrent engine и playback engine.

## 2. Product Positioning

Streamly v1.0 позиционируется как desktop-first приложение для macOS:

- визуально близкое к Netflix и Apple TV;
- нативное по ощущениям, а не web-wrapper;
- ориентированное на быстрый поиск, понятный выбор релиза и плавный запуск просмотра;
- локальное по данным и приватности;
- архитектурно готовое к будущим аккаунтам, синхронизации и расширяемым источникам.

Основной сценарий v1.0:

1. Пользователь открывает Streamly.
2. Ищет фильм или сериал.
3. Видит карточку с метаданными, постером, описанием, рейтингами и доступными релизами.
4. Выбирает релиз с лучшим качеством и достаточным количеством seeders.
5. Запускает воспроизведение через встроенный playback engine.
6. Возвращается позже через историю просмотра, библиотеку или Continue Watching.

## 3. Platform & Distribution Decisions

### 3.1 Platform

- Название приложения: Streamly.
- Платформа: macOS.
- Поддерживаемая архитектура процессоров: Apple Silicon only.
- Target architecture: arm64.
- Минимальная версия macOS: macOS 13.0+.
- UI framework: SwiftUI.
- Interface mode: только Dark Mode.
- Распространение: вне App Store.

### 3.2 Visual Direction

Визуальный стиль Streamly v1.0:

- гибрид Netflix + Apple TV;
- dark graphite background;
- neon purple accent;
- thin separators;
- soft glow для выбранных и активных элементов;
- Apple-like easing и нативные macOS transitions;
- крупные постеры и media-first browsing;
- спокойная, кинематографичная, темная композиция без светлой темы.

Dark Mode является единственным поддерживаемым режимом интерфейса в v1.0.

## 4. Scope v1.0

Streamly v1.0 включает:

- нативное macOS-приложение на SwiftUI;
- модульную архитектуру с MVVM и Services Layer;
- локальную базу данных SQLite через GRDB;
- embedded libtorrent через внутренний abstraction layer;
- embedded libmpv как playback engine;
- поиск медиа и отображение метаданных;
- TMDB как основной источник метаданных;
- архитектурную готовность metadata layer к IMDb и Trakt;
- source provider architecture для torrent-релизов;
- UI, который не зависит от конкретных torrent-сайтов;
- ranking релизов по качеству и seeders;
- воспроизведение torrent-видео без ручного полного скачивания файла;
- поддержку встроенных субтитров;
- поддержку локальных `.srt` и `.ass` субтитров;
- поиск субтитров через OpenSubtitles;
- языковой приоритет субтитров по умолчанию: русский -> английский;
- возможность изменить порядок языкового приоритета в настройках;
- локальную историю просмотра;
- Continue Watching;
- локальную библиотеку;
- избранное;
- пользовательские списки;
- пользовательские рейтинги;
- локальные diagnostics logs;
- Export Diagnostics;
- автообновления через Sparkle 2 и GitHub Releases;
- `.dmg` installer.

## 5. Out of Scope v1.0

В v1.0 не входят:

- plugin layer и пользовательские плагины;
- multi-profile;
- облачная синхронизация;
- пользовательский аккаунт и login/password flow;
- iOS, tvOS, iPadOS, Android и другие mobile versions;
- Plex integration;
- Jellyfin integration;
- direct HTTP streaming как отдельный playback/source режим;
- AI recommendations;
- App Store distribution;
- обход DRM;
- обход paywall;
- обход captcha;
- обход технических ограничений сторонних сервисов.

Эти ограничения фиксируют границы первой версии. Архитектура может учитывать будущие расширения, но v1.0 не должна реализовывать эти функции частично или скрыто.

## 6. High-Level Architecture

Streamly использует Modular Architecture + MVVM + Services Layer.

### 6.1 UI Layer

UI Layer отвечает за SwiftUI views, navigation, layout, visual states, animations и user interaction.

Требования к UI Layer:

- SwiftUI-first implementation;
- Dark Mode only;
- Netflix-like / Apple TV-like browsing model;
- отсутствие прямой зависимости от конкретных torrent-сайтов;
- отсутствие прямой зависимости от libtorrent, libmpv, TMDB, OpenSubtitles или GRDB;
- работа через ViewModels и сервисные интерфейсы.

### 6.2 Presentation Layer / MVVM

ViewModels отвечают за состояние экранов, подготовку данных для UI, пользовательские действия и координацию сервисов.

ViewModels не должны содержать низкоуровневую torrent, playback, database или network логику. Они вызывают сервисы через протоколы и получают уже подготовленные модели для отображения.

### 6.3 Services Layer

Services Layer содержит бизнес-логику приложения:

- SearchService;
- CatalogService;
- MetadataService;
- TorrentSearchService;
- TorrentSessionService;
- PlaybackService;
- SubtitleService;
- LibraryService;
- WatchHistoryService;
- UserListsService;
- UserRatingsService;
- DiagnosticsService;
- UpdateService.

Сервисы должны быть отделены от SwiftUI и готовы к тестированию отдельно от UI.

### 6.4 Local Database Layer

Локальная база данных:

- SQLite;
- GRDB;
- хранение только локальных пользовательских и прикладных данных;
- отсутствие облачной синхронизации в v1.0.

Локально сохраняются:

- история просмотра;
- Continue Watching;
- библиотека;
- избранное;
- списки пользователя;
- пользовательские рейтинги;
- настройки приложения;
- языковые приоритеты субтитров;
- кэш метаданных, если это допустимо условиями metadata provider;
- diagnostics metadata, необходимая для Export Diagnostics.

### 6.5 Torrent Engine Layer

Torrent engine:

- embedded libtorrent;
- доступ только через внутренний abstraction layer;
- UI и ViewModels не зависят от libtorrent напрямую;
- source providers возвращают нормализованные данные о релизах;
- TorrentSessionService отвечает за подготовку и управление torrent-сессиями.

Архитектура должна позволять заменить или обновить реализацию torrent engine без переписывания UI.

### 6.6 Playback Engine Layer

Playback engine:

- embedded libmpv;
- доступ через PlaybackService;
- поддержка запуска видео из torrent-потока;
- интеграция с историей просмотра и Continue Watching;
- передача событий playback state в Services Layer.

SwiftUI views не должны напрямую управлять libmpv.

### 6.7 Metadata Layer

Основной metadata provider для v1.0:

- TMDB.

Архитектура должна быть готова к будущим providers:

- IMDb;
- Trakt.

Metadata layer должен работать через provider abstraction, чтобы UI и ViewModels не зависели от конкретного API.

### 6.8 Subtitle Layer

Subtitle layer поддерживает:

- встроенные субтитры;
- локальные `.srt`;
- локальные `.ass`;
- поиск через OpenSubtitles.

Языковой приоритет по умолчанию:

1. русский;
2. английский.

Порядок языков должен быть настраиваемым в settings.

### 6.9 Source Provider Architecture

Источники torrent-релизов подключаются через source provider architecture.

Требования:

- UI не знает о конкретных сайтах;
- provider возвращает нормализованные torrent release models;
- provider layer можно расширять без изменения основных экранов;
- v1.0 не включает пользовательский plugin layer;
- будущий plugin layer должен быть возможен архитектурно, но не реализуется в v1.0.

### 6.10 Sync-Ready Architecture

В v1.0 нет аккаунта и облачной синхронизации.

При этом локальные модели и сервисные границы должны учитывать возможную будущую синхронизацию через login/password:

- стабильные локальные identifiers;
- отделение local persistence от business logic;
- возможность добавить remote sync service позже;
- отсутствие жесткой привязки пользовательских данных к устройству в доменной модели.

## 7. Search & Ranking

Search ranking в v1.0 должен помогать пользователю быстро выбрать лучший релиз.

Базовый порядок:

1. сначала релизы с лучшим качеством;
2. среди релизов сопоставимого качества выше показываются релизы с большим количеством seeders;
3. дополнительные сигналы могут использоваться только если они не противоречат первым двум правилам.

Качество релиза должно быть нормализовано source provider layer или отдельным ranking component, чтобы UI получал уже подготовленный список.

UI должен показывать качество, seeders и важные признаки релиза так, чтобы пользователь понимал, почему конкретный релиз выше.

## 8. Local Data & Privacy

Streamly v1.0 является local-first приложением.

В v1.0 без аккаунта локально хранятся:

- история просмотра;
- Continue Watching;
- библиотека;
- избранное;
- пользовательские списки;
- рейтинги пользователя;
- настройки;
- языковые приоритеты;
- diagnostics logs.

Приложение не должно требовать аккаунт для основных сценариев v1.0.

Пользовательские данные должны оставаться локальными, кроме случаев, когда пользователь явно использует внешние metadata, subtitle или source provider функции, требующие network access.

## 9. Diagnostics & Logs

Streamly v1.0 должен иметь локальные diagnostics logs и функцию Export Diagnostics.

Diagnostics должны помогать разбирать:

- ошибки запуска приложения;
- ошибки поиска;
- ошибки metadata providers;
- ошибки source providers;
- torrent session issues;
- playback issues;
- subtitle issues;
- update issues.

Export Diagnostics должен формировать локальный диагностический пакет или файл, который пользователь может передать разработчику вручную.

Diagnostics не должны скрыто отправляться на внешний сервер в v1.0.

## 10. Legal & Content Responsibility

Streamly является медиаклиентом и программной оболочкой.

Приложение:

- не поставляется с нелегальным контентом;
- не содержит встроенной библиотеки пиратского контента;
- не гарантирует доступность сторонних источников;
- не предоставляет пользователю права на просмотр контента;
- не должно обходить DRM;
- не должно обходить paywall;
- не должно обходить captcha;
- не должно обходить технические ограничения сторонних сервисов.

Пользователь самостоятельно отвечает:

- за выбранные источники;
- за права на просмотр контента;
- за соблюдение законодательства своей юрисдикции;
- за соблюдение условий использования сторонних сервисов.

Архитектура source provider layer не должна проектироваться как механизм обхода ограничений сторонних сервисов.

## 11. Release Model

Streamly распространяется вне App Store.

Базовая release-модель v1.0:

- приложение собирается как signed и notarized macOS app;
- пользователь скачивает `.dmg` installer;
- публичная точка скачивания: landing page;
- technical distribution channel: GitHub Releases;
- auto-update: Sparkle 2;
- Sparkle appcast публикуется и обновляется на базе GitHub Releases.

Landing page должен быть публичной точкой входа для скачивания, описания продукта и ссылок на релизы. GitHub Releases используется как технический канал распространения release artifacts.

## 12. Canonical Status

Этот документ является главным продуктовым документом Streamly v1.0.

Все последующие задачи по архитектуре, UI, persistence, torrent engine, playback, metadata, subtitles, diagnostics, release engineering и legal boundaries должны ссылаться на `docs/product-spec.md` как на источник продуктовых и технических решений v1.0.
