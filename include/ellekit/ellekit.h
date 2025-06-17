#ifndef ELLEKIT_H
#define ELLEKIT_H

#include <stddef.h>
#include <stdint.h>
#include <objc/runtime.h>
#include <dlfcn.h>

// Pure ElleKit API implementation - no MobileSubstrate dependency

#ifdef __cplusplus
extern "C" {
#endif

// ElleKit compatibility layer - these don't use % syntax in header

// Hook a function using ElleKit's API
#define EKHookFunction(return_type, function_name, ...) \
    static return_type (*orig)(__VA_ARGS__); \
    static return_type $##function_name(__VA_ARGS__); \
    static __attribute__((constructor)) void _init_##function_name() { \
        EKHook((void *)function_name, (void *)$##function_name, (void **)&orig); \
    } \
    static return_type $##function_name(__VA_ARGS__)

// Initialize hooks - maps to Logos %ctor
#define EKInit() __attribute__((constructor)) static void ek_init(void)

// Inject hooks for a group (will be replaced with proper syntax in preprocessor)
#define EKInject(group) _EK_init_group(group)

// ElleKit API equivalents for Objective-C method hooking 
static __attribute__((unused)) void EKHookMessage(Class _class, SEL sel, IMP imp, IMP *orig) {
    Method method = class_getInstanceMethod(_class, sel);
    if (method) {
        *orig = method_getImplementation(method);
        method_setImplementation(method, imp);
    }
}

// Function prototypes 
static inline void *EKFind(void *image, const char *name) {
    // Use dlsym for symbol lookup
    return dlsym(image ? image : RTLD_DEFAULT, name);
}

static inline void *EKFoundation(const char *class_name) {
    // Convert class name to class object safely
    return (void *)(uintptr_t)objc_getClass(class_name);
}

static inline int EKHook(void *target, void *replacement, void **original) {
    // Check if real ElleKit is available
    typedef int (*EKHookFn)(void *, void *, void **);
    static EKHookFn ellekit_hook = NULL;
    
    if (!ellekit_hook) {
        void *sym = dlsym(RTLD_DEFAULT, "EKHook");
        if (sym) {
            ellekit_hook = (EKHookFn)sym;
        }
    }
    
    // If ElleKit is available, use it
    if (ellekit_hook) {
        return ellekit_hook(target, replacement, original);
    }
    
    // Otherwise, fall back to Objective-C runtime for method swizzling
    // or use MSHookFunction if available
    int result = -1;
    
    // Check if MSHookFunction is available as fallback
    typedef void (*MSHookFn)(void *, void *, void **);
    void *hook_sym = dlsym(RTLD_DEFAULT, "MSHookFunction");
    
    if (hook_sym) {
        MSHookFn ms_hook = (MSHookFn)hook_sym;
        ms_hook(target, replacement, original);
        result = 0;
    }
    
    return result;
}

// Helper functions for ElleKit method comparison
static inline bool EKMethodsEqual(Method m1, Method m2) {
    return m1 == m2 || (
        method_getName(m1) == method_getName(m2) && 
        method_getImplementation(m1) == method_getImplementation(m2)
    );
}

// ElleKit-specific direct callback registration
// These are ElleKit-exclusive features not available in MobileSubstrate
static inline int EKRegisterCallback(void (*callback)(void)) {
    typedef int (*EKRegisterCallbackFn)(void (*callback)(void));
    static EKRegisterCallbackFn registerCallbackFn = NULL;
    
    if (!registerCallbackFn) {
        void *sym = dlsym(RTLD_DEFAULT, "EKRegisterCallback");
        if (sym) {
            registerCallbackFn = (EKRegisterCallbackFn)sym;
        }
    }
    
    if (registerCallbackFn) {
        return registerCallbackFn(callback);
    }
    
    // No op if ElleKit isn't available
    return -1;
}

// ElleKit early initialization - runs before other tweak initializers
static inline int EKEarlyInit(void (*callback)(void)) {
    typedef int (*EKEarlyInitFn)(void (*callback)(void));
    static EKEarlyInitFn earlyInitFn = NULL;
    
    if (!earlyInitFn) {
        void *sym = dlsym(RTLD_DEFAULT, "EKEarlyInit");
        if (sym) {
            earlyInitFn = (EKEarlyInitFn)sym;
        }
    }
    
    if (earlyInitFn) {
        return earlyInitFn(callback);
    }
    
    // No op if ElleKit isn't available
    return -1;
}

// ElleKit memory protection modification
static inline int EKMemoryProtect(void *address, size_t size, int protection) {
    typedef int (*EKMemoryProtectFn)(void *address, size_t size, int protection);
    static EKMemoryProtectFn memoryProtectFn = NULL;
    
    if (!memoryProtectFn) {
        void *sym = dlsym(RTLD_DEFAULT, "EKMemoryProtect");
        if (sym) {
            memoryProtectFn = (EKMemoryProtectFn)sym;
        }
    }
    
    if (memoryProtectFn) {
        return memoryProtectFn(address, size, protection);
    }
    
    // No op if ElleKit isn't available
    return -1;
}

// ElleKit-specific hooks for special scenarios
static inline bool EKIsElleKitEnv(void) {
    return dlsym(RTLD_DEFAULT, "EKMethodsEqual") != NULL;
}

#ifdef __cplusplus
}
#endif

#endif /* ELLEKIT_H */ 