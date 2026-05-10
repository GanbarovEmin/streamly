import GRDB

extension DatabaseManager {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: """
                CREATE TABLE media_items (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN ('movie', 'series')),
                    overview TEXT NOT NULL DEFAULT '',
                    release_year INTEGER,
                    poster_path TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE movies (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    tmdb_id INTEGER,
                    imdb_id TEXT,
                    runtime_minutes INTEGER,
                    release_date TEXT,
                    certification TEXT
                );

                CREATE TABLE series (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    tmdb_id INTEGER,
                    imdb_id TEXT,
                    first_air_date TEXT,
                    status TEXT,
                    season_count INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE seasons (
                    id TEXT PRIMARY KEY,
                    series_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    season_number INTEGER NOT NULL,
                    title TEXT,
                    overview TEXT,
                    UNIQUE(series_id, season_number)
                );

                CREATE TABLE episodes (
                    id TEXT PRIMARY KEY,
                    season_id TEXT NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
                    series_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    episode_number INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    overview TEXT,
                    runtime_minutes INTEGER,
                    air_date TEXT,
                    UNIQUE(season_id, episode_number)
                );

                CREATE TABLE torrent_releases (
                    id TEXT PRIMARY KEY,
                    media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    magnet_uri TEXT,
                    source_provider_id TEXT NOT NULL,
                    quality INTEGER NOT NULL,
                    seeders INTEGER NOT NULL DEFAULT 0,
                    size_bytes INTEGER,
                    added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE playback_progress (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    position_seconds REAL NOT NULL DEFAULT 0,
                    duration_seconds REAL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE watch_history (
                    id TEXT PRIMARY KEY,
                    media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    watched_at TEXT NOT NULL,
                    position_seconds REAL NOT NULL DEFAULT 0
                );

                CREATE TABLE library_items (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    source TEXT NOT NULL DEFAULT 'manual'
                );

                CREATE TABLE user_lists (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    is_default INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE user_list_items (
                    list_id TEXT NOT NULL REFERENCES user_lists(id) ON DELETE CASCADE,
                    media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (list_id, media_id)
                );

                CREATE TABLE user_ratings (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 10),
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE cached_images (
                    url TEXT PRIMARY KEY,
                    local_path TEXT NOT NULL,
                    width INTEGER,
                    height INTEGER,
                    cached_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE metadata_cache (
                    cache_key TEXT PRIMARY KEY,
                    provider TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    expires_at TEXT,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE source_accounts (
                    id TEXT PRIMARY KEY,
                    provider_id TEXT NOT NULL,
                    username TEXT,
                    credential_keychain_id TEXT NOT NULL,
                    authentication_status TEXT NOT NULL DEFAULT 'unknown',
                    last_validation_at TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE app_settings (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE TABLE diagnostics_events (
                    id TEXT PRIMARY KEY,
                    level TEXT NOT NULL,
                    subsystem TEXT NOT NULL,
                    message TEXT NOT NULL,
                    metadata_json TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX idx_media_items_kind ON media_items(kind);
                CREATE INDEX idx_torrent_releases_media_quality_seeders ON torrent_releases(media_id, quality, seeders DESC);
                CREATE INDEX idx_watch_history_media_date ON watch_history(media_id, watched_at DESC);
                CREATE INDEX idx_user_list_items_media ON user_list_items(media_id);
                CREATE INDEX idx_metadata_cache_provider ON metadata_cache(provider);
                CREATE INDEX idx_diagnostics_events_created_at ON diagnostics_events(created_at DESC);
                """)
        }

        migrator.registerMigration("v2_image_cache_metadata") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(cached_images)").compactMap { row in
                row["name"] as String?
            }

            if !columns.contains("file_size") {
                try db.execute(sql: "ALTER TABLE cached_images ADD COLUMN file_size INTEGER NOT NULL DEFAULT 0")
            }
            if !columns.contains("created_at") {
                try db.execute(sql: "ALTER TABLE cached_images ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP")
            }
            if !columns.contains("last_accessed_at") {
                try db.execute(sql: "ALTER TABLE cached_images ADD COLUMN last_accessed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP")
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cached_images_last_accessed ON cached_images(last_accessed_at)")
        }

        migrator.registerMigration("v3_library_favorites") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS favorite_items (
                    media_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_favorite_items_added_at ON favorite_items(added_at DESC);
                """)
        }

        migrator.registerMigration("v4_expanded_playback_history") { db in
            let playbackColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(playback_progress)").compactMap { row in
                row["name"] as String?
            }
            if !playbackColumns.contains("episode_id") {
                try db.execute(sql: "ALTER TABLE playback_progress ADD COLUMN episode_id TEXT")
            }
            if !playbackColumns.contains("release_id") {
                try db.execute(sql: "ALTER TABLE playback_progress ADD COLUMN release_id TEXT")
            }
            if !playbackColumns.contains("progress_percent") {
                try db.execute(sql: "ALTER TABLE playback_progress ADD COLUMN progress_percent REAL NOT NULL DEFAULT 0")
            }
            if !playbackColumns.contains("last_watched_at") {
                try db.execute(sql: "ALTER TABLE playback_progress ADD COLUMN last_watched_at TEXT")
                try db.execute(sql: "UPDATE playback_progress SET last_watched_at = updated_at WHERE last_watched_at IS NULL")
            }
            if !playbackColumns.contains("completed") {
                try db.execute(sql: "ALTER TABLE playback_progress ADD COLUMN completed INTEGER NOT NULL DEFAULT 0")
            }

            let historyColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(watch_history)").compactMap { row in
                row["name"] as String?
            }
            if !historyColumns.contains("episode_id") {
                try db.execute(sql: "ALTER TABLE watch_history ADD COLUMN episode_id TEXT")
            }
            if !historyColumns.contains("release_id") {
                try db.execute(sql: "ALTER TABLE watch_history ADD COLUMN release_id TEXT")
            }
            if !historyColumns.contains("duration_seconds") {
                try db.execute(sql: "ALTER TABLE watch_history ADD COLUMN duration_seconds REAL")
            }
            if !historyColumns.contains("progress_percent") {
                try db.execute(sql: "ALTER TABLE watch_history ADD COLUMN progress_percent REAL NOT NULL DEFAULT 0")
            }
            if !historyColumns.contains("completed") {
                try db.execute(sql: "ALTER TABLE watch_history ADD COLUMN completed INTEGER NOT NULL DEFAULT 0")
            }

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_progress_continue ON playback_progress(completed, last_watched_at DESC)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_watch_history_watched_at ON watch_history(watched_at DESC)")
        }

        migrator.registerMigration("v5_playback_progress_episode_keys") { db in
            let playbackColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(playback_progress)").compactMap { row in
                row["name"] as String?
            }
            guard !playbackColumns.contains("progress_key") else {
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_progress_continue ON playback_progress(completed, last_watched_at DESC)")
                return
            }

            try db.execute(sql: """
                CREATE TABLE playback_progress_new (
                    progress_key TEXT PRIMARY KEY,
                    media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
                    episode_id TEXT,
                    release_id TEXT,
                    position_seconds REAL NOT NULL DEFAULT 0,
                    duration_seconds REAL,
                    progress_percent REAL NOT NULL DEFAULT 0,
                    last_watched_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    completed INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """)

            try db.execute(sql: """
                INSERT INTO playback_progress_new (
                    progress_key,
                    media_id,
                    episode_id,
                    release_id,
                    position_seconds,
                    duration_seconds,
                    progress_percent,
                    last_watched_at,
                    completed,
                    updated_at
                )
                SELECT
                    CASE
                        WHEN episode_id IS NULL OR episode_id = '' THEN media_id
                        ELSE media_id || ':' || episode_id
                    END,
                    media_id,
                    episode_id,
                    release_id,
                    position_seconds,
                    duration_seconds,
                    progress_percent,
                    COALESCE(last_watched_at, updated_at, CURRENT_TIMESTAMP),
                    completed,
                    updated_at
                FROM playback_progress;
                """)

            try db.execute(sql: "DROP TABLE playback_progress")
            try db.execute(sql: "ALTER TABLE playback_progress_new RENAME TO playback_progress")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_progress_continue ON playback_progress(completed, last_watched_at DESC)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_playback_progress_media_episode ON playback_progress(media_id, episode_id)")
        }

        migrator.registerMigration("v6_user_lists_metadata") { db in
            let listColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(user_lists)").compactMap { row in
                row["name"] as String?
            }
            if !listColumns.contains("description") {
                try db.execute(sql: "ALTER TABLE user_lists ADD COLUMN description TEXT")
            }
            if !listColumns.contains("is_default") {
                try db.execute(sql: "ALTER TABLE user_lists ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0")
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_user_lists_default ON user_lists(is_default)")
        }

        migrator.registerMigration("v7_source_account_auth_metadata") { db in
            let sourceAccountColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(source_accounts)").compactMap { row in
                row["name"] as String?
            }
            if !sourceAccountColumns.contains("authentication_status") {
                try db.execute(sql: "ALTER TABLE source_accounts ADD COLUMN authentication_status TEXT NOT NULL DEFAULT 'unknown'")
            }
            if !sourceAccountColumns.contains("last_validation_at") {
                try db.execute(sql: "ALTER TABLE source_accounts ADD COLUMN last_validation_at TEXT")
            }
        }

        return migrator
    }
}
