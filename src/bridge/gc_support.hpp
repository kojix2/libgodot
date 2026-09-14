#pragma once

#include "common.hpp"
#include "bridge_types.hpp"

#include <vector>
#include <mutex>

#ifndef _WIN32
#include <signal.h>
#include <pthread.h>
#endif

struct GC_stack_base {
    void *mem_base;
};

using GCGetStackBaseFn = int (*)(struct GC_stack_base *sb);
using GCRegisterMyThreadFn = int (*)(const struct GC_stack_base *sb);
using GCThreadIsRegisteredFn = int (*)(void);
using GCAllowRegisterThreadsFn = void (*)(void);
using GCInitFn = void (*)(void);
using GCIsInitCalledFn = int (*)(void);
using GCGetSuspendSignalFn = int (*)(void);
using GCGetThrRestartSignalFn = int (*)(void);
using GCUnregisterMyThreadFn = int (*)(void);

struct GCModuleEntry {
    void *handle = nullptr;
    GCGetStackBaseFn get_stack_base = nullptr;
    GCRegisterMyThreadFn register_my_thread = nullptr;
    GCUnregisterMyThreadFn unregister_my_thread = nullptr;
    GCThreadIsRegisteredFn thread_is_registered = nullptr;
    GCAllowRegisterThreadsFn allow_register_threads = nullptr;
    GCInitFn init = nullptr;
    GCGetSuspendSignalFn get_suspend_signal = nullptr;
    GCGetThrRestartSignalFn get_thr_restart_signal = nullptr;
};

static std::vector<GCModuleEntry> g_gc_modules;
static std::recursive_mutex g_gc_modules_mutex;
static thread_local size_t t_gc_registered_module_count = 0;
static void *s_cached_game_module = nullptr;
static bool g_is_addon_module = false;

inline void unregister_gc_thread() {
    // Boehm GC automatically manages thread lifecycle via pthread key destructors
    // (GC_thread_dereg_key) on POSIX/Linux/macOS and via DllMain on Windows.
    // Explicitly invoking GC_unregister_my_thread from a C++ thread_local destructor
    // during thread termination races with GC internal cleanup, dereferencing freed/null
    // thread entries at offset 0x18 (SIGSEGV / signal 11), especially when multiple
    // GDExtension shared libraries are loaded in the same process.
    t_gc_registered_module_count = 0;
}

struct GCThreadRegistrationGuard {
    bool active = false;
    ~GCThreadRegistrationGuard() {
        if (active) {
            active = false;
            unregister_gc_thread();
        }
    }
};
static thread_local GCThreadRegistrationGuard t_gc_registration_guard;



inline void bridge_register_gc_functions(const BridgeGCFunctions *funcs) {
#ifndef _WIN32
    if (!funcs || g_is_addon_module) return;
#else
    if (!funcs) return;
#endif
    std::lock_guard<std::recursive_mutex> lock(g_gc_modules_mutex);
    for (const auto &m : g_gc_modules) {
        if (funcs->register_my_thread && m.register_my_thread == (GCRegisterMyThreadFn)funcs->register_my_thread) {
            return;
        }
    }
    GCModuleEntry entry;
    entry.init = funcs->init;
    entry.register_my_thread = (GCRegisterMyThreadFn)funcs->register_my_thread;
    entry.unregister_my_thread = (GCUnregisterMyThreadFn)funcs->unregister_my_thread;
    entry.thread_is_registered = (GCThreadIsRegisteredFn)funcs->thread_is_registered;
    entry.allow_register_threads = (GCAllowRegisterThreadsFn)funcs->allow_register_threads;
    entry.get_stack_base = (GCGetStackBaseFn)funcs->get_stack_base;
    entry.get_suspend_signal = (GCGetSuspendSignalFn)funcs->get_suspend_signal;
    entry.get_thr_restart_signal = (GCGetThrRestartSignalFn)funcs->get_thr_restart_signal;

    if (entry.allow_register_threads) entry.allow_register_threads();
    g_gc_modules.push_back(entry);
}

inline void init_gc_library(void *game_module_handle = nullptr) {
#ifndef _WIN32
    if (g_is_addon_module) return;
#endif
    std::lock_guard<std::recursive_mutex> lock(g_gc_modules_mutex);

    if (game_module_handle) {
        s_cached_game_module = game_module_handle;
    } else {
        game_module_handle = s_cached_game_module;
    }

#ifdef _WIN32
    HMODULE hGc = GetModuleHandleA("gc.dll");
    if (!hGc) hGc = LoadLibraryA("gc.dll");
    if (hGc) {
        bool found = false;
        for (const auto &m : g_gc_modules) {
            if (m.handle == hGc) {
                found = true;
                break;
            }
        }
        if (!found) {
            GCModuleEntry entry;
            entry.handle = hGc;
            entry.init = reinterpret_cast<GCInitFn>(GetProcAddress(hGc, "GC_init"));
            entry.allow_register_threads = reinterpret_cast<GCAllowRegisterThreadsFn>(GetProcAddress(hGc, "GC_allow_register_threads"));
            entry.get_stack_base = reinterpret_cast<GCGetStackBaseFn>(GetProcAddress(hGc, "GC_get_stack_base"));
            entry.register_my_thread = reinterpret_cast<GCRegisterMyThreadFn>(GetProcAddress(hGc, "GC_register_my_thread"));
            entry.unregister_my_thread = reinterpret_cast<GCUnregisterMyThreadFn>(GetProcAddress(hGc, "GC_unregister_my_thread"));
            entry.thread_is_registered = reinterpret_cast<GCThreadIsRegisteredFn>(GetProcAddress(hGc, "GC_thread_is_registered"));
            GCIsInitCalledFn is_init_called = reinterpret_cast<GCIsInitCalledFn>(GetProcAddress(hGc, "GC_is_init_called"));
            bool already_inited = (is_init_called && is_init_called() != 0);
            if (entry.init && !already_inited) entry.init();
            if (entry.allow_register_threads) entry.allow_register_threads();
            g_gc_modules.push_back(entry);
        }
    }
#else
    // On POSIX platforms where Boehm GC is statically linked into shared libraries,
    // registering multiple static GC instances to track the same OS threads causes
    // fatal collisions in pthread key destructors (signal 11 / SIGSEGV at address 0x18).
    // Only the primary game module should register with g_gc_modules.
    if (!g_gc_modules.empty()) {
        return;
    }

    std::vector<void*> candidates;
    if (game_module_handle) {
        candidates.push_back(game_module_handle);
    } else {
        candidates.push_back(RTLD_DEFAULT);
    }

    for (void *hCand : candidates) {
        GCRegisterMyThreadFn reg_fn = reinterpret_cast<GCRegisterMyThreadFn>(dlsym(hCand, "GC_register_my_thread"));
        if (!reg_fn) continue;

        bool already_registered = false;
        for (const auto &m : g_gc_modules) {
            if (m.register_my_thread == reg_fn) {
                already_registered = true;
                break;
            }
        }
        if (already_registered) {
            if (hCand == game_module_handle) {
                break;
            }
            continue;
        }

        GCModuleEntry entry;
        entry.handle = hCand;
        entry.register_my_thread = reg_fn;
        entry.unregister_my_thread = reinterpret_cast<GCUnregisterMyThreadFn>(dlsym(hCand, "GC_unregister_my_thread"));
        entry.init = reinterpret_cast<GCInitFn>(dlsym(hCand, "GC_init"));
        entry.allow_register_threads = reinterpret_cast<GCAllowRegisterThreadsFn>(dlsym(hCand, "GC_allow_register_threads"));
        entry.get_stack_base = reinterpret_cast<GCGetStackBaseFn>(dlsym(hCand, "GC_get_stack_base"));
        entry.thread_is_registered = reinterpret_cast<GCThreadIsRegisteredFn>(dlsym(hCand, "GC_thread_is_registered"));
        entry.get_suspend_signal = reinterpret_cast<GCGetSuspendSignalFn>(dlsym(hCand, "GC_get_suspend_signal"));
        entry.get_thr_restart_signal = reinterpret_cast<GCGetThrRestartSignalFn>(dlsym(hCand, "GC_get_thr_restart_signal"));

        GCIsInitCalledFn is_init_called = reinterpret_cast<GCIsInitCalledFn>(dlsym(hCand, "GC_is_init_called"));
        bool already_inited = (is_init_called && is_init_called() != 0);
        if (entry.init && hCand != game_module_handle && !already_inited) entry.init();
        if (entry.allow_register_threads) entry.allow_register_threads();
        g_gc_modules.push_back(entry);

        if (hCand == game_module_handle) {
            break;
        }
    }
#endif
}

inline void ensure_gc_thread_registered() {
#ifndef _WIN32
    if (g_is_addon_module) {
        return;
    }
#endif
    if (t_gc_registered_module_count >= g_gc_modules.size() && !g_gc_modules.empty()) {
        return;
    }

    std::vector<GCModuleEntry> modules_snapshot;
    {
        std::lock_guard<std::recursive_mutex> lock(g_gc_modules_mutex);
        if (g_gc_modules.empty()) {
            init_gc_library();
        }
        modules_snapshot = g_gc_modules;
    }
    if (modules_snapshot.empty()) {
        return;
    }

#ifndef _WIN32
    // Unmask Boehm GC thread suspend/restart signals on foreign threads before registering.
    sigset_t set;
    sigemptyset(&set);
    for (const auto &mod : modules_snapshot) {
        if (mod.get_suspend_signal) {
            int sig = mod.get_suspend_signal();
            if (sig > 0) sigaddset(&set, sig);
        }
        if (mod.get_thr_restart_signal) {
            int sig = mod.get_thr_restart_signal();
            if (sig > 0) sigaddset(&set, sig);
        }
    }
#ifdef SIGPWR
    sigaddset(&set, SIGPWR);
#endif
#ifdef SIGXCPU
    sigaddset(&set, SIGXCPU);
#endif
#if defined(SIGRTMIN) && defined(SIGRTMAX)
    for (int s = SIGRTMIN; s <= SIGRTMAX; s++) {
        sigaddset(&set, s);
    }
#elif defined(__SIGRTMIN) && defined(__SIGRTMAX)
    for (int s = __SIGRTMIN; s <= __SIGRTMAX; s++) {
        sigaddset(&set, s);
    }
#endif
    pthread_sigmask(SIG_UNBLOCK, &set, nullptr);
#endif

    struct GC_stack_base sb;
    sb.mem_base = nullptr;
    int rc = -1;

    for (const auto &mod : modules_snapshot) {
        if (mod.get_stack_base) {
            rc = mod.get_stack_base(&sb);
            if (rc == 0 && sb.mem_base != nullptr) {
                break;
            }
        }
    }

#if defined(__APPLE__)
    if (rc != 0 || sb.mem_base == nullptr) {
        sb.mem_base = pthread_get_stackaddr_np(pthread_self());
        rc = 0;
    }
#elif defined(__linux__)
    if (rc != 0 || sb.mem_base == nullptr) {
        pthread_attr_t attr;
        if (pthread_getattr_np(pthread_self(), &attr) == 0) {
            void *stack_addr = nullptr;
            size_t stack_size = 0;
            pthread_attr_getstack(&attr, &stack_addr, &stack_size);
            pthread_attr_destroy(&attr);
            if (stack_addr) {
                sb.mem_base = (void*)((uintptr_t)stack_addr + stack_size);
                rc = 0;
            }
        }
    }
#endif

    if (rc == 0 && sb.mem_base != nullptr) {
        for (const auto &mod : modules_snapshot) {
            if (mod.register_my_thread) {
                if (mod.thread_is_registered && mod.thread_is_registered()) {
                    continue;
                }
                mod.register_my_thread(&sb);

            }
        }
        t_gc_registered_module_count = modules_snapshot.size();
        t_gc_registration_guard.active = true;
    }
}
