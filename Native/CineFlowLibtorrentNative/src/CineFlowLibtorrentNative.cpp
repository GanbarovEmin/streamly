#include "CineFlowLibtorrentNative.h"

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <signal.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

extern char **environ;

namespace {

struct Engine {
    pid_t helper_pid = -1;
    int control_port = 0;
};

std::string escape_json(const char *value) {
    std::string input = value ? value : "";
    std::string output;
    output.reserve(input.size() + 8);
    for (char c : input) {
        switch (c) {
        case '\\': output += "\\\\"; break;
        case '"': output += "\\\""; break;
        case '\n': output += "\\n"; break;
        case '\r': output += "\\r"; break;
        case '\t': output += "\\t"; break;
        default: output += c; break;
        }
    }
    return output;
}

char *copy_string(const std::string &value) {
    char *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (!result) {
        return nullptr;
    }
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

void set_error(char **error, const std::string &message) {
    if (!error) {
        return;
    }
    *error = copy_string(message.empty() ? "native_runtime_error" : message);
}

std::string dirname(std::string path) {
    auto index = path.find_last_of('/');
    if (index == std::string::npos) {
        return ".";
    }
    return path.substr(0, index);
}

bool exists(const std::string &path) {
    return ::access(path.c_str(), X_OK) == 0;
}

std::string framework_root() {
    Dl_info info;
    if (dladdr(reinterpret_cast<void *>(&cf_libtorrent_engine_create), &info) == 0 || !info.dli_fname) {
        return ".";
    }
    std::string path = info.dli_fname;
    std::string current = dirname(path);
    for (int i = 0; i < 5; i += 1) {
        if (current.size() >= 10 && current.rfind(".framework") == current.size() - 10) {
            return current;
        }
        current = dirname(current);
    }
    return dirname(path);
}

std::string helper_path() {
    const std::string root = framework_root();
    std::vector<std::string> candidates = {
        root + "/Resources/streamly-torrent-helper/streamly-torrent-helper",
        root + "/Versions/A/Resources/streamly-torrent-helper/streamly-torrent-helper",
        root + "/Resources/streamly_torrent_helper.py",
        root + "/Versions/A/Resources/streamly_torrent_helper.py"
    };
    for (const auto &candidate : candidates) {
        if (exists(candidate)) {
            return candidate;
        }
    }
    return "";
}

bool read_line(int fd, std::string &line) {
    line.clear();
    char c = 0;
    while (true) {
        ssize_t count = ::read(fd, &c, 1);
        if (count == 1) {
            if (c == '\n') {
                return true;
            }
            line.push_back(c);
            continue;
        }
        return !line.empty();
    }
}

int parse_port(const std::string &line) {
    const std::string key = "\"port\"";
    auto key_index = line.find(key);
    if (key_index == std::string::npos) {
        return 0;
    }
    auto colon_index = line.find(':', key_index + key.size());
    if (colon_index == std::string::npos) {
        return 0;
    }
    return std::atoi(line.c_str() + colon_index + 1);
}

bool launch_helper(const std::string &storage_path, Engine *engine, std::string &error) {
    std::string executable = helper_path();
    if (executable.empty()) {
        error = "libtorrent_helper_not_found";
        return false;
    }

    int pipe_fds[2];
    if (::pipe(pipe_fds) != 0) {
        error = "pipe_failed";
        return false;
    }

    pid_t pid = ::fork();
    if (pid < 0) {
        ::close(pipe_fds[0]);
        ::close(pipe_fds[1]);
        error = "fork_failed";
        return false;
    }

    if (pid == 0) {
        ::dup2(pipe_fds[1], STDOUT_FILENO);
        ::close(pipe_fds[0]);
        ::close(pipe_fds[1]);

        if (executable.size() >= 3 && executable.rfind(".py") == executable.size() - 3) {
            const char *argv[] = {"/usr/bin/python3", executable.c_str(), "--storage", storage_path.c_str(), nullptr};
            ::execve("/usr/bin/python3", const_cast<char *const *>(argv), environ);
        } else {
            const char *argv[] = {executable.c_str(), "--storage", storage_path.c_str(), nullptr};
            ::execve(executable.c_str(), const_cast<char *const *>(argv), environ);
        }
        _exit(127);
    }

    ::close(pipe_fds[1]);
    std::string line;
    bool did_read = read_line(pipe_fds[0], line);
    ::close(pipe_fds[0]);
    if (!did_read) {
        error = "helper_start_failed";
        ::kill(pid, SIGTERM);
        return false;
    }

    int port = parse_port(line);
    if (port <= 0) {
        error = "helper_invalid_port:" + line;
        ::kill(pid, SIGTERM);
        return false;
    }

    engine->helper_pid = pid;
    engine->control_port = port;
    return true;
}

bool send_all(int fd, const std::string &value) {
    const char *cursor = value.data();
    size_t remaining = value.size();
    while (remaining > 0) {
        ssize_t sent = ::send(fd, cursor, remaining, 0);
        if (sent <= 0) {
            return false;
        }
        cursor += sent;
        remaining -= static_cast<size_t>(sent);
    }
    return true;
}

bool recv_all(int fd, std::string &value) {
    value.clear();
    char buffer[8192];
    while (true) {
        ssize_t count = ::recv(fd, buffer, sizeof(buffer), 0);
        if (count > 0) {
            value.append(buffer, static_cast<size_t>(count));
            continue;
        }
        return count == 0;
    }
}

bool http_post(Engine *engine, const std::string &path, const std::string &body, std::string &response, std::string &error) {
    if (!engine || engine->control_port <= 0) {
        error = "engine_unavailable";
        return false;
    }

    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        error = "socket_failed";
        return false;
    }
    timeval timeout{};
    timeout.tv_sec = 90;
    timeout.tv_usec = 0;
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<uint16_t>(engine->control_port));
    ::inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);

    if (::connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
        ::close(fd);
        error = "helper_connect_failed";
        return false;
    }

    std::ostringstream request;
    request << "POST " << path << " HTTP/1.1\r\n";
    request << "Host: 127.0.0.1\r\n";
    request << "Content-Type: application/json\r\n";
    request << "Connection: close\r\n";
    request << "Content-Length: " << body.size() << "\r\n\r\n";
    request << body;

    if (!send_all(fd, request.str())) {
        ::close(fd);
        error = "helper_send_failed";
        return false;
    }

    std::string raw;
    if (!recv_all(fd, raw)) {
        ::close(fd);
        error = "helper_read_failed";
        return false;
    }
    ::close(fd);

    auto header_end = raw.find("\r\n\r\n");
    if (header_end == std::string::npos) {
        error = "helper_invalid_response";
        return false;
    }

    std::string headers = raw.substr(0, header_end);
    response = raw.substr(header_end + 4);
    if (headers.find(" 200 ") == std::string::npos) {
        error = response.empty() ? "helper_request_failed" : response;
        return false;
    }
    return true;
}

char *string_call(Engine *engine, const std::string &path, const std::string &body, char **error) {
    std::string response;
    std::string request_error;
    if (!http_post(engine, path, body, response, request_error)) {
        set_error(error, request_error);
        return nullptr;
    }
    return copy_string(response);
}

int32_t control_call(Engine *engine, const std::string &path, const std::string &body, char **error) {
    std::string response;
    std::string request_error;
    if (!http_post(engine, path, body, response, request_error)) {
        set_error(error, request_error);
        return 1;
    }
    return 0;
}

std::string handle_body(const char *handle) {
    return "{\"handle\":\"" + escape_json(handle) + "\"}";
}

} // namespace

extern "C" {

void *cf_libtorrent_engine_create(const char *storage_path, char **error) {
    if (!storage_path || std::strlen(storage_path) == 0) {
        set_error(error, "storage_path_required");
        return nullptr;
    }

    auto *engine = new Engine();
    std::string launch_error;
    if (!launch_helper(storage_path, engine, launch_error)) {
        delete engine;
        set_error(error, launch_error);
        return nullptr;
    }
    return engine;
}

void cf_libtorrent_engine_destroy(void *raw_engine) {
    auto *engine = static_cast<Engine *>(raw_engine);
    if (!engine) {
        return;
    }
    if (engine->helper_pid > 0) {
        ::kill(engine->helper_pid, SIGTERM);
        for (int attempt = 0; attempt < 20; attempt += 1) {
            pid_t result = ::waitpid(engine->helper_pid, nullptr, WNOHANG);
            if (result == engine->helper_pid) {
                delete engine;
                return;
            }
            ::usleep(50 * 1000);
        }
        ::kill(engine->helper_pid, SIGKILL);
        ::waitpid(engine->helper_pid, nullptr, 0);
    }
    delete engine;
}

char *cf_libtorrent_add_magnet(void *raw_engine, const char *uri, const char *storage_path, char **error) {
    std::string body = "{\"uri\":\"" + escape_json(uri) + "\",\"storagePath\":\"" + escape_json(storage_path) + "\"}";
    return string_call(static_cast<Engine *>(raw_engine), "/add_magnet", body, error);
}

char *cf_libtorrent_add_torrent_file(void *raw_engine, const char *torrent_path, const char *storage_path, char **error) {
    std::string body = "{\"torrentPath\":\"" + escape_json(torrent_path) + "\",\"storagePath\":\"" + escape_json(storage_path) + "\"}";
    return string_call(static_cast<Engine *>(raw_engine), "/add_torrent_file", body, error);
}

int32_t cf_libtorrent_start(void *raw_engine, const char *handle, char **error) {
    return control_call(static_cast<Engine *>(raw_engine), "/start", handle_body(handle), error);
}

int32_t cf_libtorrent_pause(void *raw_engine, const char *handle, char **error) {
    return control_call(static_cast<Engine *>(raw_engine), "/pause", handle_body(handle), error);
}

int32_t cf_libtorrent_resume(void *raw_engine, const char *handle, char **error) {
    return control_call(static_cast<Engine *>(raw_engine), "/resume", handle_body(handle), error);
}

int32_t cf_libtorrent_stop(void *raw_engine, const char *handle, char **error) {
    return control_call(static_cast<Engine *>(raw_engine), "/stop", handle_body(handle), error);
}

int32_t cf_libtorrent_remove(void *raw_engine, const char *handle, bool delete_files, char **error) {
    std::string body = "{\"handle\":\"" + escape_json(handle) + "\",\"deleteFiles\":" + (delete_files ? "true" : "false") + "}";
    return control_call(static_cast<Engine *>(raw_engine), "/remove", body, error);
}

char *cf_libtorrent_status_json(void *raw_engine, const char *handle, char **error) {
    return string_call(static_cast<Engine *>(raw_engine), "/status_json", handle_body(handle), error);
}

char *cf_libtorrent_files_json(void *raw_engine, const char *handle, char **error) {
    return string_call(static_cast<Engine *>(raw_engine), "/files_json", handle_body(handle), error);
}

int32_t cf_libtorrent_select_file(void *raw_engine, const char *handle, const char *file_id, char **error) {
    std::string body = "{\"handle\":\"" + escape_json(handle) + "\",\"fileId\":\"" + escape_json(file_id) + "\"}";
    return control_call(static_cast<Engine *>(raw_engine), "/select_file", body, error);
}

int32_t cf_libtorrent_set_sequential(void *raw_engine, const char *handle, bool enabled, char **error) {
    std::string body = "{\"handle\":\"" + escape_json(handle) + "\",\"enabled\":" + (enabled ? "true" : "false") + "}";
    return control_call(static_cast<Engine *>(raw_engine), "/set_sequential", body, error);
}

int32_t cf_libtorrent_set_priority(void *raw_engine, const char *handle, const char *file_id, int32_t priority, char **error) {
    std::string body = "{\"handle\":\"" + escape_json(handle) + "\",\"fileId\":\"" + escape_json(file_id) + "\",\"priority\":" + std::to_string(priority) + "}";
    return control_call(static_cast<Engine *>(raw_engine), "/set_priority", body, error);
}

int32_t cf_libtorrent_set_bandwidth_limits(void *raw_engine, const char *handle, int64_t download_bytes_per_second, int64_t upload_bytes_per_second, char **error) {
    std::string body = "{\"handle\":\"" + escape_json(handle) + "\",\"downloadBytesPerSecond\":" + std::to_string(download_bytes_per_second) + ",\"uploadBytesPerSecond\":" + std::to_string(upload_bytes_per_second) + "}";
    return control_call(static_cast<Engine *>(raw_engine), "/set_bandwidth_limits", body, error);
}

char *cf_libtorrent_streaming_url(void *raw_engine, const char *handle, char **error) {
    return string_call(static_cast<Engine *>(raw_engine), "/streaming_url", handle_body(handle), error);
}

void cf_libtorrent_string_free(char *value) {
    std::free(value);
}

} // extern "C"
