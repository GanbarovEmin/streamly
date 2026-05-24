#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import threading
import time
import uuid
import warnings
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

warnings.filterwarnings("ignore", category=DeprecationWarning)

import libtorrent as lt


MEDIA_EXTENSIONS = {
    ".avi", ".m2ts", ".m4v", ".mkv", ".mov", ".mp4", ".mpeg", ".mpg", ".ts", ".webm"
}

PRIORITY_MAP = {
    0: 0,
    1: 1,
    2: 4,
    3: 7,
}
STREAM_CHUNK_BYTES = 256 * 1024
STARTUP_PREBUFFER_BYTES = 1 * 1024 * 1024
INITIAL_STREAM_BYTES = 2 * 1024 * 1024
BACKGROUND_BUFFER_WINDOW_BYTES = 128 * 1024 * 1024
METADATA_TIMEOUT_SECONDS = 8.0
STARTUP_BUFFER_TIMEOUT_SECONDS = 12.0
STREAM_RANGE_TIMEOUT_SECONDS = 18.0
STREAMING_PIECE_PRIORITY = 7
BACKGROUND_FILE_PRIORITY = 7
HELPER_PID_FILE_PREFIX = ".streamly-helper-"
HELPER_PID_FILE_SUFFIX = ".pid"


def process_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def cleanup_orphan_pid_files(storage_path: Path) -> None:
    for pid_file in storage_path.glob(f"{HELPER_PID_FILE_PREFIX}*{HELPER_PID_FILE_SUFFIX}"):
        try:
            payload = json.loads(pid_file.read_text(encoding="utf-8"))
            pid = int(payload.get("pid") or 0)
            parent_pid = int(payload.get("parentPid") or 0)
        except Exception:
            pid_file.unlink(missing_ok=True)
            continue

        if not process_is_alive(pid) or (parent_pid > 0 and not process_is_alive(parent_pid)):
            pid_file.unlink(missing_ok=True)


@dataclass
class TorrentEntry:
    handle_id: str
    handle: object
    storage_path: Path
    selected_file_id: str | None = None
    sequential: bool = True
    streaming_url: str | None = None
    download_limit_bytes_per_second: int | None = None
    upload_limit_bytes_per_second: int | None = None
    max_buffered_bytes: int = 0
    background_thread: threading.Thread | None = None
    background_stop: threading.Event | None = None


class TorrentRuntime:
    def __init__(self, storage_path: Path, parent_pid: int | None = None):
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)
        cleanup_orphan_pid_files(self.storage_path)
        settings = {
            "listen_interfaces": "0.0.0.0:0",
            "enable_dht": True,
            "enable_lsd": True,
            "enable_upnp": True,
            "enable_natpmp": True,
            "alert_mask": 0,
        }
        self.session = lt.session(settings)
        self.entries: dict[str, TorrentEntry] = {}
        self.lock = threading.RLock()
        self.stream_server: ThreadingHTTPServer | None = None
        self.stream_thread: threading.Thread | None = None
        self.parent_pid = parent_pid if parent_pid and parent_pid > 0 else None
        self.shutdown_requested = threading.Event()
        self.pid_file = self.storage_path / f"{HELPER_PID_FILE_PREFIX}{os.getpid()}{HELPER_PID_FILE_SUFFIX}"
        self.write_pid_file()
        self.start_parent_watchdog()

    def write_pid_file(self) -> None:
        payload = {
            "pid": os.getpid(),
            "parentPid": self.parent_pid,
            "createdAt": time.time(),
        }
        self.pid_file.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")

    def start_parent_watchdog(self) -> None:
        if self.parent_pid is None:
            return

        def watch() -> None:
            while not self.shutdown_requested.wait(2.0):
                if not process_is_alive(self.parent_pid):
                    self.shutdown()
                    os._exit(0)

        threading.Thread(target=watch, daemon=True).start()

    def shutdown(self) -> None:
        self.shutdown_requested.set()
        with self.lock:
            entries = list(self.entries.items())
            self.entries.clear()
        for _, entry in entries:
            self.stop_background_download(entry)
            try:
                self.session.remove_torrent(entry.handle, 0)
            except Exception:
                pass
        if self.stream_server is not None:
            try:
                self.stream_server.shutdown()
                self.stream_server.server_close()
            except Exception:
                pass
            self.stream_server = None
        try:
            self.pid_file.unlink(missing_ok=True)
        except Exception:
            pass

    def add_magnet(self, uri: str, storage_path: str) -> str:
        if not uri.lower().startswith("magnet:?"):
            raise RuntimeError("invalid_magnet_uri")
        target = Path(storage_path)
        target.mkdir(parents=True, exist_ok=True)
        params = lt.parse_magnet_uri(uri)
        params.save_path = str(target)
        params.storage_mode = lt.storage_mode_t.storage_mode_sparse
        params.flags |= lt.torrent_flags.default_dont_download
        params.flags |= lt.torrent_flags.sequential_download
        params.flags &= ~lt.torrent_flags.paused
        handle = self.session.add_torrent(params)
        handle_id = uuid.uuid4().hex
        with self.lock:
            self.entries[handle_id] = TorrentEntry(handle_id=handle_id, handle=handle, storage_path=target)
        return handle_id

    def add_torrent_file(self, torrent_path: str, storage_path: str) -> str:
        target = Path(storage_path)
        target.mkdir(parents=True, exist_ok=True)
        info = lt.torrent_info(torrent_path)
        params = lt.add_torrent_params()
        params.ti = info
        params.save_path = str(target)
        params.storage_mode = lt.storage_mode_t.storage_mode_sparse
        params.flags |= lt.torrent_flags.default_dont_download
        params.flags |= lt.torrent_flags.sequential_download
        params.flags &= ~lt.torrent_flags.paused
        handle = self.session.add_torrent(params)
        handle_id = uuid.uuid4().hex
        with self.lock:
            self.entries[handle_id] = TorrentEntry(handle_id=handle_id, handle=handle, storage_path=target)
        return handle_id

    def start(self, handle_id: str) -> None:
        entry = self.entry(handle_id)
        entry.handle.resume()

    def pause(self, handle_id: str) -> None:
        self.entry(handle_id).handle.pause()

    def resume(self, handle_id: str) -> None:
        self.entry(handle_id).handle.resume()

    def stop(self, handle_id: str) -> None:
        self.entry(handle_id).handle.pause()

    def remove(self, handle_id: str, delete_files: bool) -> None:
        with self.lock:
            entry = self.entries.pop(handle_id, None)
        if entry is None:
            raise RuntimeError("session_not_found")
        self.stop_background_download(entry)
        option = lt.options_t.delete_files if delete_files else 0
        self.session.remove_torrent(entry.handle, option)
        if delete_files:
            shutil.rmtree(entry.storage_path, ignore_errors=True)

    def status(self, handle_id: str) -> dict:
        entry = self.entry(handle_id)
        status = entry.handle.status()
        total_bytes = int(getattr(status, "total_wanted", 0) or 0)
        downloaded_bytes = int(getattr(status, "total_wanted_done", 0) or getattr(status, "total_done", 0) or 0)
        selected_index = self.selected_file_index(entry)
        buffered_bytes = downloaded_bytes
        if selected_index is not None:
            selected_total = self.file_size(entry, selected_index)
            if selected_total > 0:
                total_bytes = selected_total
            downloaded_bytes = self.file_progress(entry, selected_index)
            buffered_bytes = self.contiguous_file_progress(entry, selected_index)
            first_chunk_end = min(selected_total - 1, STREAM_CHUNK_BYTES - 1)
            if buffered_bytes > 0:
                first_range_available = self.file_range_is_available(entry, selected_index, 0, first_chunk_end)
                if first_range_available:
                    self.flush_download_cache(entry)
                if (
                    not first_range_available
                    or not self.file_start_is_materialized(entry, selected_index)
                ):
                    buffered_bytes = 0
            entry.max_buffered_bytes = max(entry.max_buffered_bytes, buffered_bytes)
            buffered_bytes = entry.max_buffered_bytes
        return {
            "sessionId": handle_id,
            "state": self.state_name(entry, status),
            "downloadedBytes": downloaded_bytes,
            "totalBytes": total_bytes,
            "bufferedBytes": buffered_bytes,
            "downloadSpeedBytesPerSecond": int(getattr(status, "download_rate", 0) or 0),
            "uploadSpeedBytesPerSecond": int(getattr(status, "upload_rate", 0) or 0),
            "seeders": int(getattr(status, "num_seeds", 0) or 0),
            "leechers": 0,
            "connectedPeers": int(getattr(status, "num_peers", 0) or 0),
            "availability": float(getattr(status, "distributed_copies", 0.0) or 0.0),
            "selectedFileId": entry.selected_file_id,
            "isSequentialDownloadEnabled": entry.sequential,
            "streamingURL": entry.streaming_url,
            "downloadLimitBytesPerSecond": entry.download_limit_bytes_per_second,
            "uploadLimitBytesPerSecond": entry.upload_limit_bytes_per_second,
        }

    def files(self, handle_id: str) -> list[dict]:
        entry = self.entry(handle_id)
        self.wait_for_metadata(entry)
        storage = entry.handle.torrent_file().files()
        progresses = self.file_progresses(entry)
        priorities = list(entry.handle.file_priorities())
        result = []
        for index in range(storage.num_files()):
            path = storage.file_path(index)
            size = int(storage.file_size(index))
            name = os.path.basename(path)
            extension = os.path.splitext(name)[1].lower()
            downloaded = int(progresses[index]) if index < len(progresses) else 0
            result.append({
                "id": str(index),
                "path": path,
                "name": name,
                "lengthBytes": size,
                "isMediaFile": extension in MEDIA_EXTENSIONS,
                "priority": self.swift_priority(priorities[index] if index < len(priorities) else 0),
                "progress": {
                    "downloadedBytes": downloaded,
                    "totalBytes": size,
                    "bufferedBytes": downloaded,
                    "downloadSpeedBytesPerSecond": 0,
                    "uploadSpeedBytesPerSecond": 0,
                },
            })
        return result

    def select_file(self, handle_id: str, file_id: str) -> None:
        entry = self.entry(handle_id)
        index = self.file_index(entry, file_id)
        if entry.selected_file_id is not None and entry.selected_file_id != str(index):
            self.stop_background_download(entry)
        storage = entry.handle.torrent_file().files()
        priorities = [0] * storage.num_files()
        priorities[index] = BACKGROUND_FILE_PRIORITY
        entry.handle.prioritize_files(priorities)
        entry.handle.set_sequential_download(True)
        entry.selected_file_id = str(index)
        entry.sequential = True
        entry.max_buffered_bytes = 0
        self.prioritize_file_start(entry, index)
        self.ensure_background_download(entry, index)

    def set_sequential(self, handle_id: str, enabled: bool) -> None:
        entry = self.entry(handle_id)
        entry.handle.set_sequential_download(enabled)
        entry.sequential = enabled
        selected_index = self.selected_file_index(entry)
        if enabled and selected_index is not None:
            self.prioritize_file_start(entry, selected_index)
            self.ensure_background_download(entry, selected_index)

    def set_priority(self, handle_id: str, file_id: str, priority: int) -> None:
        entry = self.entry(handle_id)
        index = self.file_index(entry, file_id)
        priorities = list(entry.handle.file_priorities())
        while len(priorities) <= index:
            priorities.append(0)
        priorities[index] = BACKGROUND_FILE_PRIORITY if entry.selected_file_id == str(index) and priority > 0 else PRIORITY_MAP.get(priority, 4)
        entry.handle.prioritize_files(priorities)
        if entry.selected_file_id == str(index) and priority > 0:
            entry.handle.set_sequential_download(True)
            entry.sequential = True
            self.prioritize_file_start(entry, index)
            self.ensure_background_download(entry, index)

    def set_bandwidth_limits(self, handle_id: str, download_limit: int | None, upload_limit: int | None) -> None:
        entry = self.entry(handle_id)
        entry.download_limit_bytes_per_second = self.normalized_limit(download_limit)
        entry.upload_limit_bytes_per_second = self.normalized_limit(upload_limit)
        entry.handle.set_download_limit(entry.download_limit_bytes_per_second or 0)
        entry.handle.set_upload_limit(entry.upload_limit_bytes_per_second or 0)

    def streaming_url(self, handle_id: str) -> str:
        entry = self.entry(handle_id)
        self.wait_for_metadata(entry)
        if entry.selected_file_id is None:
            media_files = [item for item in self.files(handle_id) if item["isMediaFile"]]
            if not media_files:
                raise RuntimeError("streaming_url_unavailable:no_media_file")
            self.select_file(handle_id, media_files[0]["id"])
        else:
            selected_index = self.selected_file_index(entry)
            if selected_index is not None:
                entry.handle.set_sequential_download(True)
                entry.sequential = True
                self.prioritize_file_start(entry, selected_index)
                self.ensure_background_download(entry, selected_index)
        self.ensure_stream_server()
        port = self.stream_server.server_address[1]
        entry.streaming_url = f"http://127.0.0.1:{port}/stream/{handle_id}/{entry.selected_file_id}"
        selected_index = self.selected_file_index(entry)
        if selected_index is not None:
            self.ensure_background_download(entry, selected_index)
        return entry.streaming_url

    def entry(self, handle_id: str) -> TorrentEntry:
        with self.lock:
            entry = self.entries.get(handle_id)
        if entry is None:
            raise RuntimeError("session_not_found")
        return entry

    def wait_for_metadata(self, entry: TorrentEntry, timeout: float = METADATA_TIMEOUT_SECONDS) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if entry.handle.has_metadata():
                return
            status = entry.handle.status()
            errc = getattr(status, "errc", None)
            if errc is not None and callable(getattr(errc, "value", None)) and errc.value() != 0:
                raise RuntimeError(f"metadata_unavailable:{status.errc.message()}")
            time.sleep(0.25)
        raise RuntimeError("metadata_timeout")

    def wait_for_file_bytes(self, entry: TorrentEntry, file_index: int, byte_count: int, timeout: float = STREAM_RANGE_TIMEOUT_SECONDS) -> None:
        self.wait_for_file_range(entry, file_index, 0, max(0, byte_count - 1), timeout)

    def wait_for_startup_buffer(self, entry: TorrentEntry, file_index: int) -> None:
        size = self.file_size(entry, file_index)
        if size <= 0:
            return
        end = min(size - 1, STARTUP_PREBUFFER_BYTES - 1)
        self.prioritize_file_start(entry, file_index)
        self.wait_for_file_range(entry, file_index, 0, end, STARTUP_BUFFER_TIMEOUT_SECONDS)
        path, _ = self.file_path(entry, file_index)
        self.wait_for_materialized_media_header(path)

    def wait_for_file_range(self, entry: TorrentEntry, file_index: int, start: int, end: int, timeout: float = STREAM_RANGE_TIMEOUT_SECONDS) -> None:
        first_piece, last_piece = self.piece_range(entry, file_index, start, end)
        deadline = time.time() + timeout
        last_progress_at = time.time()
        last_have_count = -1
        self.prioritize_piece_window(entry, first_piece, last_piece)
        while True:
            if self.file_range_is_readable(entry, file_index, start, end):
                self.flush_download_cache(entry)
                return
            have_count = sum(1 for piece in range(first_piece, last_piece + 1) if entry.handle.have_piece(piece))
            if have_count == last_piece - first_piece + 1:
                self.flush_download_cache(entry)
                if self.file_range_is_readable(entry, file_index, start, end):
                    return
            if have_count > last_have_count:
                last_have_count = have_count
                last_progress_at = time.time()
            now = time.time()
            if now >= deadline:
                timeout_name = "startup_buffer_timeout" if start == 0 else "buffer_timeout"
                raise RuntimeError(f"{timeout_name}:{have_count}/{last_piece - first_piece + 1}")
            if now - last_progress_at > timeout:
                raise RuntimeError(f"buffer_timeout:no_progress:{have_count}/{last_piece - first_piece + 1}")
            entry.handle.set_sequential_download(True)
            self.prioritize_piece_window(entry, first_piece, last_piece)
            time.sleep(0.2)
        raise RuntimeError("buffer_timeout")

    def file_range_is_available(self, entry: TorrentEntry, file_index: int, start: int, end: int) -> bool:
        try:
            if self.file_range_is_readable(entry, file_index, start, end):
                return True
            first_piece, last_piece = self.piece_range(entry, file_index, start, end)
            return all(entry.handle.have_piece(piece) for piece in range(first_piece, last_piece + 1))
        except Exception:
            return False

    def file_range_is_readable(self, entry: TorrentEntry, file_index: int | None, start: int, end: int) -> bool:
        if not self.file_range_is_materialized(entry, file_index, start, end):
            return False
        if start == 0:
            return self.file_start_is_materialized(entry, file_index)
        return True

    def file_range_is_materialized(self, entry: TorrentEntry, file_index: int | None, start: int, end: int) -> bool:
        if file_index is None or end < start:
            return False
        try:
            path, size = self.file_path(entry, file_index)
            if size <= 0 or not path.exists() or start >= size:
                return False
            bounded_end = min(end, size - 1)
            if hasattr(os, "SEEK_DATA") and hasattr(os, "SEEK_HOLE"):
                fd = os.open(path, os.O_RDONLY)
                try:
                    data_start = os.lseek(fd, start, os.SEEK_DATA)
                    if data_start > start:
                        return False
                    hole_start = os.lseek(fd, start, os.SEEK_HOLE)
                    return hole_start > bounded_end
                finally:
                    os.close(fd)

            with path.open("rb") as file:
                file.seek(start)
                data = file.read(min(64 * 1024, bounded_end - start + 1))
            return bool(data) and any(byte != 0 for byte in data)
        except OSError:
            return False
        except Exception:
            return False

    def piece_range(self, entry: TorrentEntry, file_index: int, start: int, end: int) -> tuple[int, int]:
        torrent_info = entry.handle.torrent_file()
        request = torrent_info.map_file(file_index, max(0, start), max(1, end - start + 1))
        piece_length = max(1, int(torrent_info.piece_length()))
        first_piece = int(request.piece)
        last_piece = first_piece + int((request.start + request.length - 1) // piece_length)
        return first_piece, max(first_piece, last_piece)

    def piece_limited_chunk_end(self, entry: TorrentEntry, file_index: int, start: int, end: int) -> int:
        torrent_info = entry.handle.torrent_file()
        request = torrent_info.map_file(file_index, max(0, start), 1)
        piece_length = max(1, int(torrent_info.piece_length()))
        remaining_in_piece = max(1, piece_length - int(request.start))
        return min(end, start + STREAM_CHUNK_BYTES - 1, start + remaining_in_piece - 1)

    def prioritize_piece_window(self, entry: TorrentEntry, first_piece: int, last_piece: int) -> None:
        try:
            entry.handle.resume()
            for offset, piece in enumerate(range(first_piece, last_piece + 1)):
                try:
                    entry.handle.piece_priority(piece, STREAMING_PIECE_PRIORITY)
                except Exception:
                    pass
                try:
                    entry.handle.set_piece_deadline(piece, offset * 50, lt.deadline_flags_t.alert_when_available)
                except TypeError:
                    entry.handle.set_piece_deadline(piece, offset * 50)
        except Exception:
            return

    def flush_download_cache(self, entry: TorrentEntry) -> None:
        try:
            entry.handle.flush_cache()
        except Exception:
            try:
                entry.handle.flush_disk_cache()
            except Exception:
                pass

    def prioritize_file_start(self, entry: TorrentEntry, file_index: int) -> None:
        try:
            torrent_info = entry.handle.torrent_file()
            storage = torrent_info.files()
            size = int(storage.file_size(file_index))
            if size <= 0:
                return
            priorities = [0] * storage.num_files()
            priorities[file_index] = BACKGROUND_FILE_PRIORITY
            entry.handle.prioritize_files(priorities)
            entry.handle.set_sequential_download(True)
            entry.handle.resume()
            end = min(size - 1, INITIAL_STREAM_BYTES - 1)
            first_piece, last_piece = self.piece_range(entry, file_index, 0, end)
            self.prioritize_piece_window(entry, first_piece, last_piece)
        except Exception:
            return

    def ensure_background_download(self, entry: TorrentEntry, file_index: int) -> None:
        if entry.background_thread is not None and entry.background_thread.is_alive():
            return
        stop_event = threading.Event()
        entry.background_stop = stop_event

        def worker() -> None:
            while not stop_event.wait(0.5):
                try:
                    if self.shutdown_requested.is_set():
                        return
                    if entry.selected_file_id != str(file_index):
                        return
                    size = self.file_size(entry, file_index)
                    if size <= 0:
                        continue

                    priorities = [0] * entry.handle.torrent_file().files().num_files()
                    priorities[file_index] = BACKGROUND_FILE_PRIORITY
                    entry.handle.prioritize_files(priorities)
                    entry.handle.set_sequential_download(True)
                    entry.handle.resume()

                    downloaded = self.file_progress(entry, file_index)
                    contiguous = self.contiguous_file_progress(entry, file_index)
                    if downloaded >= size:
                        return

                    if contiguous < STARTUP_PREBUFFER_BYTES:
                        window_start = 0
                        window_end = min(size - 1, INITIAL_STREAM_BYTES - 1)
                    else:
                        window_start = min(contiguous, max(0, size - 1))
                        window_end = min(size - 1, window_start + BACKGROUND_BUFFER_WINDOW_BYTES - 1)
                    first_piece, last_piece = self.piece_range(entry, file_index, window_start, window_end)
                    self.prioritize_piece_window(entry, first_piece, last_piece)
                except Exception:
                    continue

        entry.background_thread = threading.Thread(target=worker, daemon=True)
        entry.background_thread.start()

    def stop_background_download(self, entry: TorrentEntry) -> None:
        if entry.background_stop is not None:
            entry.background_stop.set()
        entry.background_thread = None
        entry.background_stop = None

    def file_index(self, entry: TorrentEntry, file_id: str) -> int:
        self.wait_for_metadata(entry)
        try:
            index = int(file_id)
        except ValueError as exc:
            raise RuntimeError("file_not_found") from exc
        if index < 0 or index >= entry.handle.torrent_file().files().num_files():
            raise RuntimeError("file_not_found")
        return index

    def selected_file_index(self, entry: TorrentEntry) -> int | None:
        if entry.selected_file_id is None:
            return None
        try:
            return int(entry.selected_file_id)
        except ValueError:
            return None

    def file_progresses(self, entry: TorrentEntry) -> list[int]:
        try:
            return [int(value) for value in entry.handle.file_progress()]
        except Exception:
            return []

    def file_progress(self, entry: TorrentEntry, file_index: int | None) -> int:
        if file_index is None:
            return 0
        progresses = self.file_progresses(entry)
        return int(progresses[file_index]) if file_index < len(progresses) else 0

    def file_size(self, entry: TorrentEntry, file_index: int | None) -> int:
        if file_index is None:
            return 0
        try:
            return int(entry.handle.torrent_file().files().file_size(file_index))
        except Exception:
            return 0

    def contiguous_file_progress(self, entry: TorrentEntry, file_index: int | None) -> int:
        if file_index is None:
            return 0
        try:
            torrent_info = entry.handle.torrent_file()
            storage = torrent_info.files()
            size = int(storage.file_size(file_index))
            if size <= 0:
                return 0
            first_piece, last_piece = self.piece_range(entry, file_index, 0, size - 1)
            piece_length = max(1, int(torrent_info.piece_length()))
            first_request = torrent_info.map_file(file_index, 0, 1)
            file_global_start = (int(first_request.piece) * piece_length) + int(first_request.start)
            file_global_end = file_global_start + size
            loaded = 0
            for piece in range(first_piece, last_piece + 1):
                if not entry.handle.have_piece(piece):
                    break
                piece_start = piece * piece_length
                piece_end = piece_start + piece_length
                contribution = max(0, min(piece_end, file_global_end) - max(piece_start, file_global_start))
                loaded += contribution
            materialized = self.contiguous_materialized_file_progress(entry, file_index)
            downloaded = self.file_progress(entry, file_index)
            materialized_downloaded = min(downloaded, materialized) if materialized > 0 else 0
            return min(size, max(int(loaded), materialized_downloaded))
        except Exception:
            materialized = self.contiguous_materialized_file_progress(entry, file_index)
            downloaded = self.file_progress(entry, file_index)
            return min(downloaded, materialized) if materialized > 0 else downloaded

    def contiguous_materialized_file_progress(self, entry: TorrentEntry, file_index: int | None) -> int:
        if file_index is None:
            return 0
        try:
            path, size = self.file_path(entry, file_index)
            if size <= 0 or not path.exists():
                return 0
            if hasattr(os, "SEEK_DATA") and hasattr(os, "SEEK_HOLE"):
                fd = os.open(path, os.O_RDONLY)
                try:
                    data_start = os.lseek(fd, 0, os.SEEK_DATA)
                    if data_start > 0:
                        return 0
                    return min(size, int(os.lseek(fd, 0, os.SEEK_HOLE)))
                finally:
                    os.close(fd)

            loaded = 0
            with path.open("rb") as file:
                while loaded < size:
                    data = file.read(64 * 1024)
                    if not data or not any(byte != 0 for byte in data):
                        break
                    loaded += len(data)
            return min(size, loaded)
        except OSError:
            return 0
        except Exception:
            return 0

    def file_start_is_materialized(self, entry: TorrentEntry, file_index: int | None) -> bool:
        if file_index is None:
            return False
        try:
            path, size = self.file_path(entry, file_index)
            if size <= 0 or not path.exists():
                return False
            with path.open("rb") as file:
                data = file.read(64)
            return bool(data) and any(byte != 0 for byte in data)
        except Exception:
            return False

    def wait_for_materialized_media_header(self, path: Path, timeout: float = 1.5) -> None:
        deadline = time.time() + timeout
        while True:
            try:
                with path.open("rb") as file:
                    data = file.read(64)
                if data and any(byte != 0 for byte in data):
                    return
            except Exception:
                pass
            if time.time() >= deadline:
                raise RuntimeError("buffer_timeout:media_header_unavailable")
            time.sleep(0.05)

    def file_path(self, entry: TorrentEntry, file_index: int) -> tuple[Path, int]:
        self.wait_for_metadata(entry)
        storage = entry.handle.torrent_file().files()
        relative_path = storage.file_path(file_index)
        absolute = (entry.storage_path / relative_path).resolve()
        storage_root = entry.storage_path.resolve()
        if storage_root not in absolute.parents and absolute != storage_root:
            raise RuntimeError("file_not_found:unsafe_path")
        return absolute, int(storage.file_size(file_index))

    def ensure_stream_server(self) -> None:
        if self.stream_server is not None:
            return
        runtime = self

        class StreamHandler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                runtime.handle_stream(self)

            def do_HEAD(self):
                runtime.handle_stream(self, headers_only=True)

            def log_message(self, format, *args):
                return

        self.stream_server = ThreadingHTTPServer(("127.0.0.1", 0), StreamHandler)
        self.stream_thread = threading.Thread(target=self.stream_server.serve_forever, daemon=True)
        self.stream_thread.start()

    def handle_stream(self, request: BaseHTTPRequestHandler, headers_only: bool = False) -> None:
        parts = urlparse(request.path).path.strip("/").split("/")
        if len(parts) != 3 or parts[0] != "stream":
            self.send_error(request, HTTPStatus.NOT_FOUND, "not_found")
            return
        try:
            entry = self.entry(parts[1])
            file_index = self.file_index(entry, parts[2])
            path, size = self.file_path(entry, file_index)
            start, end, is_range_request = self.parse_range(request.headers.get("Range"), size)
            self.send_file_range(
                request,
                entry,
                file_index,
                path,
                start,
                end,
                size,
                is_range_request=is_range_request,
                headers_only=headers_only
            )
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as exc:
            try:
                self.send_error(request, HTTPStatus.SERVICE_UNAVAILABLE, str(exc))
            except (BrokenPipeError, ConnectionResetError):
                return

    def parse_range(self, range_header: str | None, size: int) -> tuple[int, int, bool]:
        if not range_header or not range_header.startswith("bytes="):
            return 0, max(0, size - 1), False
        value = range_header.removeprefix("bytes=").split(",", 1)[0].strip()
        start_text, _, end_text = value.partition("-")
        if start_text == "":
            length = int(end_text)
            return max(0, size - length), max(0, size - 1), True
        start = int(start_text)
        end = int(end_text) if end_text else size - 1
        return max(0, start), min(size - 1, end), True

    def send_file_range(
        self,
        request: BaseHTTPRequestHandler,
        entry: TorrentEntry,
        file_index: int,
        path: Path,
        start: int,
        end: int,
        size: int,
        is_range_request: bool,
        headers_only: bool = False
    ) -> None:
        length = max(0, end - start + 1)
        if not headers_only and length > 0:
            first_chunk_end = self.piece_limited_chunk_end(entry, file_index, start, end)
            timeout = STARTUP_BUFFER_TIMEOUT_SECONDS if start == 0 else STREAM_RANGE_TIMEOUT_SECONDS
            self.wait_for_file_range(entry, file_index, start, first_chunk_end, timeout)
            if start == 0:
                self.wait_for_materialized_media_header(path)

        request.send_response(HTTPStatus.PARTIAL_CONTENT if is_range_request else HTTPStatus.OK)
        request.send_header("Content-Type", "application/octet-stream")
        request.send_header("Accept-Ranges", "bytes")
        if is_range_request:
            request.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            request.send_header("Content-Length", str(length))
        request.end_headers()
        if headers_only:
            return
        with path.open("rb") as file:
            offset = start
            while offset <= end:
                chunk_end = self.piece_limited_chunk_end(entry, file_index, offset, end)
                timeout = STARTUP_BUFFER_TIMEOUT_SECONDS if offset == 0 else STREAM_RANGE_TIMEOUT_SECONDS
                self.wait_for_file_range(entry, file_index, offset, chunk_end, timeout)
                if offset == 0:
                    self.wait_for_materialized_media_header(path)
                file.seek(offset)
                remaining = chunk_end - offset + 1
                while remaining > 0:
                    chunk = file.read(min(256 * 1024, remaining))
                    if not chunk:
                        return
                    request.wfile.write(chunk)
                    remaining -= len(chunk)
                request.wfile.flush()
                offset = chunk_end + 1

    def send_error(self, request: BaseHTTPRequestHandler, status: HTTPStatus, message: str) -> None:
        data = message.encode("utf-8", errors="replace")
        request.send_response(status)
        request.send_header("Content-Type", "text/plain; charset=utf-8")
        request.send_header("Content-Length", str(len(data)))
        request.end_headers()
        request.wfile.write(data)

    def state_name(self, entry: TorrentEntry, status) -> str:
        if status.paused:
            return "paused"
        if status.is_seeding:
            return "seeding"
        if status.has_metadata and entry.selected_file_id is not None:
            return "streaming"
        state = int(status.state)
        if state == int(lt.torrent_status.checking_files):
            return "checking"
        if state in (int(lt.torrent_status.downloading_metadata), int(lt.torrent_status.downloading)):
            return "downloading"
        return "idle"

    def swift_priority(self, libtorrent_priority: int) -> int:
        if libtorrent_priority <= 0:
            return 0
        if libtorrent_priority >= 7:
            return 3
        if libtorrent_priority >= 4:
            return 2
        return 1

    def normalized_limit(self, value: int | None) -> int | None:
        if value is None or value <= 0:
            return None
        return int(value)


def read_json(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0"))
    payload = handler.rfile.read(length).decode("utf-8") if length else "{}"
    return json.loads(payload)


def send_text(handler: BaseHTTPRequestHandler, text: str, status: HTTPStatus = HTTPStatus.OK, content_type: str = "text/plain") -> None:
    data = text.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", f"{content_type}; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def make_control_handler(runtime: TorrentRuntime):
    class ControlHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                payload = read_json(self)
                path = urlparse(self.path).path
                if path == "/shutdown":
                    runtime.shutdown()
                    send_text(self, "ok")
                    threading.Thread(target=self.server.shutdown, daemon=True).start()
                elif path == "/add_magnet":
                    send_text(self, runtime.add_magnet(payload["uri"], payload["storagePath"]))
                elif path == "/add_torrent_file":
                    send_text(self, runtime.add_torrent_file(payload["torrentPath"], payload["storagePath"]))
                elif path == "/start":
                    runtime.start(payload["handle"])
                    send_text(self, "ok")
                elif path == "/pause":
                    runtime.pause(payload["handle"])
                    send_text(self, "ok")
                elif path == "/resume":
                    runtime.resume(payload["handle"])
                    send_text(self, "ok")
                elif path == "/stop":
                    runtime.stop(payload["handle"])
                    send_text(self, "ok")
                elif path == "/remove":
                    runtime.remove(payload["handle"], bool(payload.get("deleteFiles", False)))
                    send_text(self, "ok")
                elif path == "/status_json":
                    send_text(self, json.dumps(runtime.status(payload["handle"]), separators=(",", ":")), content_type="application/json")
                elif path == "/files_json":
                    send_text(self, json.dumps(runtime.files(payload["handle"]), separators=(",", ":")), content_type="application/json")
                elif path == "/select_file":
                    runtime.select_file(payload["handle"], payload["fileId"])
                    send_text(self, "ok")
                elif path == "/set_sequential":
                    runtime.set_sequential(payload["handle"], bool(payload["enabled"]))
                    send_text(self, "ok")
                elif path == "/set_priority":
                    runtime.set_priority(payload["handle"], payload["fileId"], int(payload["priority"]))
                    send_text(self, "ok")
                elif path == "/set_bandwidth_limits":
                    runtime.set_bandwidth_limits(
                        payload["handle"],
                        payload.get("downloadBytesPerSecond"),
                        payload.get("uploadBytesPerSecond"),
                    )
                    send_text(self, "ok")
                elif path == "/streaming_url":
                    send_text(self, runtime.streaming_url(payload["handle"]))
                else:
                    send_text(self, "not_found", HTTPStatus.NOT_FOUND)
            except Exception as exc:
                send_text(self, str(exc), HTTPStatus.INTERNAL_SERVER_ERROR)

        def log_message(self, format, *args):
            return

    return ControlHandler


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--storage", required=True)
    parser.add_argument("--parent-pid", type=int, default=None)
    args = parser.parse_args()

    runtime = TorrentRuntime(Path(args.storage), parent_pid=args.parent_pid)
    server = ThreadingHTTPServer(("127.0.0.1", 0), make_control_handler(runtime))
    print(json.dumps({"port": server.server_address[1]}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        runtime.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
