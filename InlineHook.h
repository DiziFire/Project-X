#ifndef INLINEHOOK_H
#define INLINEHOOK_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    void *original_function;  // Address of original function
    void *replacement_function; // Address of replacement function
    void *trampoline;  // Where original instructions are saved
    uint8_t saved_prologue[32]; // Save prologue bytes
    size_t prologue_size;  // Size of saved prologue
    bool active;  // Whether hook is active
} InlineHookInfo;

/**
 * Create and install an inline hook
 * @param target_function Pointer to function to hook
 * @param hook_function Pointer to replacement function
 * @param original_function Pointer to store address of original function trampoline
 * @return true if successful, false otherwise
 */
bool install_inline_hook(void *target_function, void *hook_function, void **original_function);

/**
 * Remove an installed hook
 * @param target_function Pointer to previously hooked function
 * @return true if successful, false otherwise
 */
bool remove_inline_hook(void *target_function);

#endif /* INLINEHOOK_H */ 