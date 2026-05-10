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
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

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
STREAM_CHUNK_BYTES = 1024 * 1024


@dataclass
class TorrentEntry:
    handle_id: str
    handle: object
    storage_path: Path
    selected_file_id: str | None = None
    sequential: bool = True
    streaming_url: str | None = None


class TorrentRuntime:
    def __init__(self, storage_path: Path):
        self.storage_path = storage_path
        self.storage_path.mkdir(parents=True, exist_ok=True)
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
        buffered_bytes = self.file_progress(entry, selected_index) if selected_index is not None else downloaded_bytes
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
        storage = entry.handle.torrent_file().files()
        priorities = [0] * storage.num_files()
        priorities[index] = 7
        entry.handle.prioritize_files(priorities)
        entry.handle.set_sequential_download(True)
        entry.selected_file_id = str(index)
        entry.sequential = True

    def set_sequential(self, handle_id: str, enabled: bool) -> None:
        entry = self.entry(handle_id)
        entry.handle.set_sequential_download(enabled)
        entry.sequential = enabled

    def set_priority(self, handle_id: str, file_id: str, priority: int) -> None:
        entry = self.entry(handle_id)
        index = self.file_index(entry, file_id)
        priorities = list(entry.handle.file_priorities())
        while len(priorities) <= index:
            priorities.append(0)
        priorities[index] = PRIORITY_MAP.get(priority, 4)
        entry.handle.prioritize_files(priorities)

    def streaming_url(self, handle_id: str) -> str:
        entry = self.entry(handle_id)
        self.wait_for_metadata(entry)
        if entry.selected_file_id is None:
            media_files = [item for item in self.files(handle_id) if item["isMediaFile"]]
            if not media_files:
                raise RuntimeError("streaming_url_unavailable:no_media_file")
            self.select_file(handle_id, media_files[0]["id"])
        self.ensure_stream_server()
        port = self.stream_server.server_address[1]
        entry.streaming_url = f"http://127.0.0.1:{port}/stream/{handle_id}/{entry.selected_file_id}"
        return entry.streaming_url

    def entry(self, handle_id: str) -> TorrentEntry:
        with self.lock:
            entry = self.entries.get(handle_id)
        if entry is None:
            raise RuntimeError("session_not_found")
        return entry

    def wait_for_metadata(self, entry: TorrentEntry, timeout: float = 30.0) -> None:
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

    def wait_for_file_bytes(self, entry: TorrentEntry, file_index: int, byte_count: int, timeout: float = 45.0) -> None:
        self.wait_for_file_range(entry, file_index, 0, max(0, byte_count - 1), timeout)

    def wait_for_file_range(self, entry: TorrentEntry, file_index: int, start: int, end: int, timeout: float = 45.0) -> None:
        first_piece, last_piece = self.piece_range(entry, file_index, start, end)
        deadline = time.time() + timeout
        self.prioritize_piece_window(entry, first_piece, last_piece)
        while time.time() < deadline:
            if all(entry.handle.have_piece(piece) for piece in range(first_piece, last_piece + 1)):
                return
            entry.handle.set_sequential_download(True)
            time.sleep(0.2)
        raise RuntimeError("buffer_timeout")

    def piece_range(self, entry: TorrentEntry, file_index: int, start: int, end: int) -> tuple[int, int]:
        torrent_info = entry.handle.torrent_file()
        request = torrent_info.map_file(file_index, max(0, start), max(1, end - start + 1))
        piece_length = max(1, int(torrent_info.piece_length()))
        first_piece = int(request.piece)
        last_piece = first_piece + int((request.start + request.length - 1) // piece_length)
        return first_piece, max(first_piece, last_piece)

    def prioritize_piece_window(self, entry: TorrentEntry, first_piece: int, last_piece: int) -> None:
        try:
            for offset, piece in enumerate(range(first_piece, last_piece + 1)):
                entry.handle.set_piece_deadline(piece, offset * 50)
        except Exception:
            return

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
            def do_GET(self):
                runtime.handle_stream(self)

            def log_message(self, format, *args):
                return

        self.stream_server = ThreadingHTTPServer(("127.0.0.1", 0), StreamHandler)
        self.stream_thread = threading.Thread(target=self.stream_server.serve_forever, daemon=True)
        self.stream_thread.start()

    def handle_stream(self, request: BaseHTTPRequestHandler) -> None:
        parts = urlparse(request.path).path.strip("/").split("/")
        if len(parts) != 3 or parts[0] != "stream":
            self.send_error(request, HTTPStatus.NOT_FOUND, "not_found")
            return
        try:
            entry = self.entry(parts[1])
            file_index = self.file_index(entry, parts[2])
            path, size = self.file_path(entry, file_index)
            start, end = self.parse_range(request.headers.get("Range"), size)
            self.wait_for_file_range(entry, file_index, start, end)
            self.send_file_range(request, path, start, end, size)
        except Exception as exc:
            self.send_error(request, HTTPStatus.SERVICE_UNAVAILABLE, str(exc))

    def parse_range(self, range_header: str | None, size: int) -> tuple[int, int]:
        if not range_header or not range_header.startswith("bytes="):
            return 0, min(max(0, size - 1), STREAM_CHUNK_BYTES - 1)
        value = range_header.removeprefix("bytes=").split(",", 1)[0].strip()
        start_text, _, end_text = value.partition("-")
        if start_text == "":
            length = int(end_text)
            return max(0, size - length), max(0, size - 1)
        start = int(start_text)
        end = int(end_text) if end_text else min(size - 1, start + STREAM_CHUNK_BYTES - 1)
        return max(0, start), min(size - 1, end)

    def send_file_range(self, request: BaseHTTPRequestHandler, path: Path, start: int, end: int, size: int) -> None:
        length = max(0, end - start + 1)
        request.send_response(HTTPStatus.PARTIAL_CONTENT)
        request.send_header("Content-Type", "application/octet-stream")
        request.send_header("Accept-Ranges", "bytes")
        request.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        request.send_header("Content-Length", str(length))
        request.end_headers()
        with path.open("rb") as file:
            file.seek(start)
            remaining = length
            while remaining > 0:
                chunk = file.read(min(256 * 1024, remaining))
                if not chunk:
                    break
                request.wfile.write(chunk)
                remaining -= len(chunk)

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
                if path == "/add_magnet":
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
    args = parser.parse_args()

    runtime = TorrentRuntime(Path(args.storage))
    server = ThreadingHTTPServer(("127.0.0.1", 0), make_control_handler(runtime))
    print(json.dumps({"port": server.server_address[1]}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
