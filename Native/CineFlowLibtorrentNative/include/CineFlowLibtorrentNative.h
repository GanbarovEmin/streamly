#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void *cf_libtorrent_engine_create(const char *storage_path, char **error);
void cf_libtorrent_engine_destroy(void *engine);

char *cf_libtorrent_add_magnet(void *engine, const char *uri, const char *storage_path, char **error);
char *cf_libtorrent_add_torrent_file(void *engine, const char *torrent_path, const char *storage_path, char **error);

int32_t cf_libtorrent_start(void *engine, const char *handle, char **error);
int32_t cf_libtorrent_pause(void *engine, const char *handle, char **error);
int32_t cf_libtorrent_resume(void *engine, const char *handle, char **error);
int32_t cf_libtorrent_stop(void *engine, const char *handle, char **error);
int32_t cf_libtorrent_remove(void *engine, const char *handle, bool delete_files, char **error);

char *cf_libtorrent_status_json(void *engine, const char *handle, char **error);
char *cf_libtorrent_files_json(void *engine, const char *handle, char **error);

int32_t cf_libtorrent_select_file(void *engine, const char *handle, const char *file_id, char **error);
int32_t cf_libtorrent_set_sequential(void *engine, const char *handle, bool enabled, char **error);
int32_t cf_libtorrent_set_priority(void *engine, const char *handle, const char *file_id, int32_t priority, char **error);
int32_t cf_libtorrent_set_bandwidth_limits(void *engine, const char *handle, int64_t download_bytes_per_second, int64_t upload_bytes_per_second, char **error);

char *cf_libtorrent_streaming_url(void *engine, const char *handle, char **error);

void cf_libtorrent_string_free(char *value);

#ifdef __cplusplus
}
#endif
