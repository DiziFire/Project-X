#import "InlineHook.h"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <dlfcn.h>
#import <mach/vm_map.h>
#import "ProjectXLogging.h"

// VM_PROT constants if not defined
#ifndef VM_PROT_READ
#define VM_PROT_READ    ((vm_prot_t) 0x01)
#endif
#ifndef VM_PROT_WRITE
#define VM_PROT_WRITE   ((vm_prot_t) 0x02)
#endif
#ifndef VM_PROT_EXECUTE
#define VM_PROT_EXECUTE ((vm_prot_t) 0x04)
#endif

// Forward declarations
static bool is_function_hooked(void *function);

// Helper function to better format mach error codes
static void mach_error_string_int(kern_return_t error_code, char *buffer, size_t buffer_size) {
    const char *error_string = mach_error_string(error_code);
    if (error_string) {
        strncpy(buffer, error_string, buffer_size);
        buffer[buffer_size - 1] = '\0';
    } else {
        snprintf(buffer, buffer_size, "Unknown error code: 0x%x", error_code);
    }
}

// Store hooks for later removal
static NSMutableDictionary *installedHooks;

// Initialize the installedHooks dictionary
__attribute__((constructor))
static void initialize_hooks_dict() {
    installedHooks = [NSMutableDictionary dictionary];
}

// ARM64 instructions
typedef enum {
    ARM64_INSTR_B = 0x14000000,    // B instruction
    ARM64_INSTR_BR = 0xD61F0000,   // BR instruction
    ARM64_INSTR_LDR = 0x58000000,  // LDR instruction
    ARM64_MASK_B = 0xFC000000,     // Mask for B instruction
    ARM64_MASK_BR = 0xFFFFFC00,    // Mask for BR instruction
    ARM64_MASK_LDR = 0xFF000000    // Mask for LDR instruction
} ARM64Instructions;

#pragma mark - Memory Management Functions

// Invalidate instruction cache
static void clean_instruction_cache(void *addr, size_t size) {
    // Implementation for iOS
    char *start = (char *)addr;
    char *end = start + size;
    
    // Align start address
    start = (char *)((uintptr_t)start & ~(16UL - 1));
    
    // Flush instruction cache
    asm volatile("isb sy");
    while (start < end) {
        asm volatile("dc civac, %0" :: "r"(start));
        start += 16;
    }
    
    // Memory barriers
    asm volatile("dsb ish");
    asm volatile("isb sy");
}

// Enhanced error logging for memory protection changes
static kern_return_t change_page_protection(void *address, size_t size, vm_prot_t protection) {
    // Get page-aligned address
    uintptr_t pageSize = getpagesize();
    uintptr_t pageStart = ((uintptr_t)address & ~(pageSize - 1));
    size_t adjustedSize = size + ((uintptr_t)address - pageStart);
    
    PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Changing memory at %p (page %p) to protection %d", 
          address, (void*)pageStart, protection);
    
    // Try vm_protect first
    kern_return_t kr = vm_protect(mach_task_self(), pageStart, adjustedSize, FALSE, protection);
    
    if (kr != KERN_SUCCESS) {
        char errorMsg[256];
        mach_error_string_int(kr, errorMsg, sizeof(errorMsg));
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - vm_protect failed: %s (0x%x)", errorMsg, kr);
        
        // Check for common errors
        if (kr == KERN_PROTECTION_FAILURE) {
            PXLog(@"[WeaponX] InlineHook: ⚠️ PROTECTION FAILURE - Address %p is likely in a restricted memory region", address);
            
            // Check if this is a system library address
            Dl_info info;
            if (dladdr(address, &info)) {
                PXLog(@"[WeaponX] InlineHook: ⚠️ Target memory is in %s at offset %lu", 
                      info.dli_fname, (unsigned long)((uintptr_t)address - (uintptr_t)info.dli_fbase));
                
                // Check if it's a system path
                if (strstr(info.dli_fname, "/System/") || strstr(info.dli_fname, "/usr/lib/")) {
                    PXLog(@"[WeaponX] InlineHook: ⚠️ CRITICAL - Attempting to modify a protected system library");
                }
            }
        } else if (kr == KERN_INVALID_ADDRESS) {
            PXLog(@"[WeaponX] InlineHook: ⚠️ INVALID ADDRESS - %p is not a valid memory address", address);
        }
        
        return kr;
    }
    
    PXLog(@"[WeaponX] InlineHook: ✅ Memory protection changed successfully for %p", (void*)pageStart);
    return KERN_SUCCESS;
}

// Add helper function to better format error codes
static bool make_memory_writable(void *address, size_t size) {
    // For iOS, we need VM_PROT constants instead of PROT_* constants
    return change_page_protection(address, size, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE) == KERN_SUCCESS;
}

static bool make_memory_executable(void *address, size_t size) {
    return change_page_protection(address, size, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS;
}

#pragma mark - Hook Management

/**
 * Create a trampoline to execute original function prologue
 */
static void *create_trampoline(void *function, uint8_t *saved_prologue, size_t prologue_size) {
    // Allocate executable memory for trampoline
    void *trampoline = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (trampoline == MAP_FAILED) {
        NSLog(@"[WeaponX] InlineHook: Failed to allocate memory for trampoline");
        return NULL;
    }
    
    // Copy original prologue
    memcpy(trampoline, saved_prologue, prologue_size);
    
    // Calculate return address (after the replaced instructions)
    uintptr_t returnAddress = (uintptr_t)function + prologue_size;
    
    // ARM64: Insert a branch to return address
    // - For ARM64, we need to use a branch instruction (B)
    // - Formula: B instruction | ((destination - source) / 4 & 0x3FFFFFF)
    uint32_t *trampolineCode = (uint32_t *)((uintptr_t)trampoline + prologue_size);
    int64_t offset = ((int64_t)returnAddress - (int64_t)trampolineCode) / 4;
    
    // Check if offset fits in 26 bits (B instruction range)
    if (offset > 0x1FFFFFF || offset < -0x2000000) {
        // If offset is too large, use LDR/BR pattern
        // LDR X16, 8 (load from PC+8, which is where we'll store the address)
        trampolineCode[0] = 0x58000050; // LDR X16, 8
        // BR X16 (branch to address in X16)
        trampolineCode[1] = 0xD61F0200; // BR X16
        // Store the return address
        *(uint64_t *)&trampolineCode[2] = returnAddress;
    } else {
        // Use direct branch
        trampolineCode[0] = ARM64_INSTR_B | (offset & 0x03FFFFFF);
    }
    
    // Make trampoline executable
    make_memory_executable(trampoline, PAGE_SIZE);
    
    // Invalidate instruction cache
    clean_instruction_cache(trampoline, PAGE_SIZE);
    
    return trampoline;
}

/**
 * Analyze function prologue to determine safe inline hook size
 * Returns size of prologue in bytes (must be at least 12 bytes for ARM64)
 */
static size_t analyze_prologue(void *function) {
    // For ARM64, minimum of 12 bytes (3 instructions) to support LDR/BR pattern
    size_t minSize = 12;
    size_t totalSize = 0;
    
    // Analyze at least 8 instructions to find a safe hook point
    for (int i = 0; i < 8 && totalSize < minSize; i++) {
        // TODO: More sophisticated instruction analysis
        // For simplicity, each ARM64 instruction is 4 bytes
        totalSize += 4;
    }
    
    // Ensure we have at least minimum required size
    return (totalSize >= minSize) ? totalSize : minSize;
}

// Enhance the write_jump function with detailed error logging
static bool write_jump(void *source, void *destination) {
    if (!source || !destination) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - NULL pointer in write_jump: source=%p, destination=%p", source, destination);
        return false;
    }
    
    PXLog(@"[WeaponX] InlineHook: 🔄 Writing jump instruction...");
    
    // Calculate the distance between the two functions
    intptr_t distance = (intptr_t)destination - (intptr_t)source;
    PXLog(@"[WeaponX] InlineHook: 🔍 DIAGNOSTIC - Jump distance: %ld bytes", distance);
    PXLog(@"[WeaponX] InlineHook: 🔍 DIAGNOSTIC - Source: %p, Destination: %p", source, destination);
    
    // Check memory permissions before attempting to modify
    PXLog(@"[WeaponX] InlineHook: 🔍 DIAGNOSTIC - Attempting to modify memory protection at %p", source);
    
    // First, try to make the memory writable
    kern_return_t kr = change_page_protection(source, 16, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    
    if (kr != KERN_SUCCESS) {
        PXLog(@"[WeaponX] InlineHook: ⚠️ WARNING - Failed to change memory protection, trying alternative approaches");
        
        // Try direct vm_write as a fallback
        PXLog(@"[WeaponX] InlineHook: 🔄 Trying direct vm_write approach");
        
        vm_address_t target_address = (vm_address_t)source;
        
        // Prepare a buffer with ARM64 branch instruction
        // Use LDR x16, 8; BR x16 pattern for long jumps
        if (labs(distance) > 128 * 1024 * 1024) {  // if the distance is too far for direct B instruction
            PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Using LDR/BR pattern for long jump");
            
            // Instruction sequence: 
            // LDR x16, 8 (load from PC+8)
            // BR x16 (branch to x16)
            // [8 bytes destination address]
            uint32_t instructions[2] = {
                0x58000090, // LDR x16, 8
                0xD61F0200  // BR x16
            };
            
            uint64_t addr = (uint64_t)destination;
            
            // Try vm_write for the instructions
            kr = vm_write(mach_task_self(), target_address, 
                         (vm_offset_t)instructions, sizeof(instructions));
                         
            if (kr != KERN_SUCCESS) {
                char errorMsg[256];
                mach_error_string_int(kr, errorMsg, sizeof(errorMsg));
                PXLog(@"[WeaponX] InlineHook: ❌ ERROR - vm_write failed for instructions: %s (0x%x)", 
                      errorMsg, kr);
                // Try MSHookMemory if available (from Substrate, might be provided by some tweaks)
                void (*MSHookMemory)(void *, const void *, size_t) = 
                    dlsym(RTLD_DEFAULT, "MSHookMemory");
                
                if (MSHookMemory) {
                    PXLog(@"[WeaponX] InlineHook: 🔄 Falling back to MSHookMemory");
                    @try {
                        MSHookMemory(source, instructions, sizeof(instructions));
                        MSHookMemory((void *)((uintptr_t)source + sizeof(instructions)), &addr, sizeof(addr));
                        PXLog(@"[WeaponX] InlineHook: ✅ MSHookMemory succeeded");
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - MSHookMemory failed: %@", exception);
                        return false;
                    }
                } else {
                    PXLog(@"[WeaponX] InlineHook: ❌ ERROR - All memory writing methods failed");
                    return false;
                }
            } else {
                // Write the destination address after the instructions
                kr = vm_write(mach_task_self(), target_address + sizeof(instructions),
                             (vm_offset_t)&addr, sizeof(addr));
                if (kr != KERN_SUCCESS) {
                    char errorMsg[256];
                    mach_error_string_int(kr, errorMsg, sizeof(errorMsg));
                    PXLog(@"[WeaponX] InlineHook: ❌ ERROR - vm_write failed for destination address: %s (0x%x)", 
                          errorMsg, kr);
                    return false;
                }
            }
        } else {
            // For shorter jumps, use a direct branch instruction
            PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Using direct branch instruction for short jump");
            
            // Calculate branch offset (relative to PC+4)
            int32_t offset = (int32_t)(distance - 4) / 4; // Division by 4 because offset is in instructions
            
            // Create a branch (B) instruction: bits[31:26] = 0b000101, bits[25:0] = offset
            uint32_t branch = 0x14000000 | (offset & 0x03FFFFFF);
            
            kr = vm_write(mach_task_self(), target_address, 
                         (vm_offset_t)&branch, sizeof(branch));
            
            if (kr != KERN_SUCCESS) {
                char errorMsg[256];
                mach_error_string_int(kr, errorMsg, sizeof(errorMsg));
                PXLog(@"[WeaponX] InlineHook: ❌ ERROR - vm_write failed for branch instruction: %s (0x%x)", 
                      errorMsg, kr);
                
                // Try MSHookMemory as a last resort
                void (*MSHookMemory)(void *, const void *, size_t) = 
                    dlsym(RTLD_DEFAULT, "MSHookMemory");
                
                if (MSHookMemory) {
                    PXLog(@"[WeaponX] InlineHook: 🔄 Falling back to MSHookMemory");
                    @try {
                        MSHookMemory(source, &branch, sizeof(branch));
                        PXLog(@"[WeaponX] InlineHook: ✅ MSHookMemory succeeded");
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - MSHookMemory failed: %@", exception);
                        return false;
                    }
                } else {
                    PXLog(@"[WeaponX] InlineHook: ❌ ERROR - All memory writing methods failed");
                    return false;
                }
            }
        }
    } else {
        // Memory protection changed successfully, proceed with direct memory write
        PXLog(@"[WeaponX] InlineHook: ✅ Memory is now writable");
        
        // Verify memory is truly writable
        bool is_writable = false;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
        memory_object_name_t object;
        vm_size_t region_size;  // Changed from mach_vm_size_t
        vm_address_t address = (vm_address_t)source;
        
        kr = vm_region_64(mach_task_self(), 
                          &address, 
                          &region_size,  // Changed variable name to avoid confusion
                          VM_REGION_BASIC_INFO_64, 
                          (vm_region_info_t)&info, 
                          &info_count, 
                          &object);
                          
        if (kr == KERN_SUCCESS) {
            is_writable = (info.protection & VM_PROT_WRITE) != 0;
            PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Memory region protection: %d (writable: %@)", 
                  info.protection, is_writable ? @"YES" : @"NO");
        } else {
            PXLog(@"[WeaponX] InlineHook: ⚠️ WARNING - Failed to query memory region info");
        }
        
        // Write the jump instruction
        if (labs(distance) > 128 * 1024 * 1024) {
            // Long jump using LDR/BR pattern
            uint32_t instructions[2] = {
                0x58000090, // LDR x16, 8
                0xD61F0200  // BR x16
            };
            uint64_t addr = (uint64_t)destination;
            
            @try {
                // Copy the instructions
                memcpy(source, instructions, sizeof(instructions));
                // Copy the destination address
                memcpy((void *)((uintptr_t)source + sizeof(instructions)), &addr, sizeof(addr));
                
                // Verify the write succeeded
                uint32_t *written = (uint32_t *)source;
                PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Wrote instructions: 0x%08x 0x%08x", 
                      written[0], written[1]);
                
                uint64_t *addr_written = (uint64_t *)((uintptr_t)source + sizeof(instructions));
                PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Wrote address: 0x%llx", *addr_written);
            } @catch (NSException *e) {
                PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Exception during memory write: %@", e);
                return false;
            }
        } else {
            // Short jump using branch instruction
            int32_t offset = (int32_t)(distance - 4) / 4;
            uint32_t branch = 0x14000000 | (offset & 0x03FFFFFF);
            
            @try {
                // Copy the branch instruction
                memcpy(source, &branch, sizeof(branch));
                
                // Verify the write succeeded
                uint32_t *written = (uint32_t *)source;
                PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Wrote branch instruction: 0x%08x", *written);
            } @catch (NSException *e) {
                PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Exception during memory write: %@", e);
                return false;
            }
        }
        
        // Restore original memory protection
        kr = change_page_protection(source, 16, VM_PROT_READ | VM_PROT_EXECUTE);
        if (kr != KERN_SUCCESS) {
            PXLog(@"[WeaponX] InlineHook: ⚠️ WARNING - Failed to restore memory protection, but jump instruction was written");
        } else {
            PXLog(@"[WeaponX] InlineHook: ✅ Memory protection restored to executable");
        }
    }
    
    // Flush instruction cache
    clean_instruction_cache(source, 16);
    PXLog(@"[WeaponX] InlineHook: ✅ Instruction cache flushed");
    
    return true;
}

#pragma mark - Public API

bool install_inline_hook(void *target_func, void *hook_func, void **original_func) {
    // Validate input parameters
    if (!target_func || !hook_func) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - NULL pointers provided: target=%p, hook=%p", 
              target_func, hook_func);
        return false;
    }
    
    PXLog(@"[WeaponX] InlineHook: 🔍 DIAGNOSTIC - Installing hook from %p to %p", target_func, hook_func);
    
    // Check if function is already hooked
    if (is_function_hooked(target_func)) {
        PXLog(@"[WeaponX] InlineHook: ⚠️ WARNING - Function at %p appears to be already hooked", target_func);
    }
    
    // Check if function is in a protected region
    kern_return_t check_kr = vm_protect(mach_task_self(), 
                                        (vm_address_t)target_func, 
                                        1, 
                                        TRUE, // Check only
                                        VM_PROT_READ | VM_PROT_WRITE);
    
    if (check_kr != KERN_SUCCESS) {
        PXLog(@"[WeaponX] InlineHook: ⚠️ PRE-CHECK - Memory at %p appears to be protected (error: 0x%x)",
              target_func, check_kr);
        
        // Check if it's a system library
        Dl_info info;
        if (dladdr(target_func, &info)) {
            PXLog(@"[WeaponX] InlineHook: 🔍 DETAILED - Target function is in %s", info.dli_fname);
            if (strstr(info.dli_fname, "/System/") || strstr(info.dli_fname, "/usr/lib/")) {
                PXLog(@"[WeaponX] InlineHook: ⚠️ CRITICAL - Attempting to hook a system library function");
            }
        }
    }
    
    // Allocate hook info structure
    InlineHookInfo *hook = (InlineHookInfo *)malloc(sizeof(InlineHookInfo));
    if (!hook) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Failed to allocate memory for hook info");
        return false;
    }
    
    memset(hook, 0, sizeof(InlineHookInfo));
    
    // Dump the first few bytes for diagnostic purposes
    unsigned char *firstBytes = (unsigned char *)target_func;
    PXLog(@"[WeaponX] InlineHook: 📊 DIAGNOSTIC - Target function first bytes: %02x %02x %02x %02x", 
          firstBytes[0], firstBytes[1], firstBytes[2], firstBytes[3]);
    
    // Check if the function is valid ARM64 code
    if ((firstBytes[0] == 0) && (firstBytes[1] == 0) && (firstBytes[2] == 0) && (firstBytes[3] == 0)) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Target function appears to be invalid (all zeros)");
        free(hook);
        return false;
    }
    
    // Analyze the prologue size
    hook->prologue_size = analyze_prologue(target_func);
    if (hook->prologue_size < 8) {
        PXLog(@"[WeaponX] InlineHook: ⚠️ WARNING - Small prologue size detected: %zu bytes", hook->prologue_size);
        if (hook->prologue_size < 4) {
            PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Prologue too small to hook safely");
            free(hook);
            return false;
        }
    } else {
        PXLog(@"[WeaponX] InlineHook: 🔍 DIAGNOSTIC - Analyzed prologue size: %zu bytes", hook->prologue_size);
    }
    
    // Save original prologue
    hook->original_function = target_func;
    hook->replacement_function = hook_func;
    hook->active = false;
    memcpy(hook->saved_prologue, target_func, hook->prologue_size);
    hook->prologue_size = hook->prologue_size;
    
    PXLog(@"[WeaponX] InlineHook: ✅ Saved original prologue");
    
    // Create trampoline
    PXLog(@"[WeaponX] InlineHook: 🔄 Creating trampoline...");
    hook->trampoline = create_trampoline(target_func, hook->saved_prologue, hook->prologue_size);
    if (!hook->trampoline) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Failed to create trampoline");
        free(hook);
        return false;
    }
    
    PXLog(@"[WeaponX] InlineHook: ✅ Created trampoline at address %p", hook->trampoline);
    
    // Set the original function pointer
    if (original_func) {
        *original_func = hook->trampoline;
        PXLog(@"[WeaponX] InlineHook: ✅ Set original function pointer to trampoline");
    }
    
    // Write jump instruction
    @try {
        // Determine if this is a system function that might be protected
        bool isMaybeProtected = false;
        Dl_info info;
        if (dladdr(target_func, &info)) {
            if (strstr(info.dli_fname, "/System/") || 
                strstr(info.dli_fname, "/usr/lib/") || 
                strstr(info.dli_fname, "/usr/libexec/")) {
                PXLog(@"[WeaponX] InlineHook: ⚠️ Target function is in a potentially protected system library: %s", 
                      info.dli_fname);
                isMaybeProtected = true;
            }
        }
        
        if (isMaybeProtected) {
            // Try an alternative approach for system functions
            PXLog(@"[WeaponX] InlineHook: 🔄 Using safer approach for system function hooking");
            
            // Option 1: Try to look for MSHookFunction
            void (*MSHookFunction)(void *, void *, void **) = dlsym(RTLD_DEFAULT, "MSHookFunction");
            if (MSHookFunction) {
                PXLog(@"[WeaponX] InlineHook: 🔄 Found MSHookFunction, using as fallback");
                @try {
                    MSHookFunction(target_func, hook_func, original_func);
                    PXLog(@"[WeaponX] InlineHook: ✅ Successfully hooked function using MSHookFunction");
                    free(hook); // We don't need our hook info since MSHookFunction manages everything
                    return true;
                } @catch (NSException *e) {
                    PXLog(@"[WeaponX] InlineHook: ⚠️ MSHookFunction failed: %@", e);
                    // Continue with our approach as fallback
                }
            }
            
            // Option 2: Use a more careful memory approach
            // Use the riskier direct writing as a last resort
        }
        
        // Write the jump - this is where most crashes would happen
        if (!write_jump(target_func, hook_func)) {
            PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Failed to write jump instruction");
            if (hook->trampoline) {
                // Deallocate the trampoline memory
                vm_deallocate(mach_task_self(), (vm_address_t)hook->trampoline, hook->prologue_size + 16);
            }
            free(hook);
            return false;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] InlineHook: ❌ ERROR - Exception while writing jump: %@", exception);
        if (hook->trampoline) {
            // Deallocate the trampoline memory
            vm_deallocate(mach_task_self(), (vm_address_t)hook->trampoline, hook->prologue_size + 16);
        }
        free(hook);
        return false;
    }
    
    // Add to the hooks list
    NSValue *key = [NSValue valueWithPointer:target_func];
    installedHooks[key] = [NSValue valueWithPointer:hook];
    
    PXLog(@"[WeaponX] InlineHook: ✅ Successfully hooked function %p with hook at %p, trampoline: %p", 
          target_func, hook_func, hook->trampoline);
    
    return true;
}

bool remove_inline_hook(void *target_function) {
    if (!target_function) return false;
    
    // Find hook info
    NSValue *key = [NSValue valueWithPointer:target_function];
    NSValue *infoValue = installedHooks[key];
    if (!infoValue) {
        NSLog(@"[WeaponX] InlineHook: Function %p is not hooked", target_function);
        return false;
    }
    
    InlineHookInfo *hookInfo = [infoValue pointerValue];
    if (!hookInfo->active) {
        return false;
    }
    
    // Make function writable
    if (!make_memory_writable(target_function, hookInfo->prologue_size)) {
        return false;
    }
    
    // Restore original prologue
    memcpy(target_function, hookInfo->saved_prologue, hookInfo->prologue_size);
    
    // Restore memory protection
    make_memory_executable(target_function, hookInfo->prologue_size);
    
    // Flush instruction cache
    clean_instruction_cache(target_function, hookInfo->prologue_size);
    
    // Free trampoline
    munmap(hookInfo->trampoline, PAGE_SIZE);
    
    // Remove hook info from dictionary
    [installedHooks removeObjectForKey:key];
    
    // Free hook info
    free(hookInfo);
    
    NSLog(@"[WeaponX] InlineHook: Successfully removed hook from function %p", target_function);
    return true;
}

// Check if a function is already hooked
static bool is_function_hooked(void *function) {
    if (!function) return false;
    
    // First check in our hooks dictionary
    if (installedHooks && [installedHooks count] > 0) {
        NSValue *key = [NSValue valueWithPointer:function];
        if (installedHooks[key]) {
            return true;
        }
    }
    
    // Also check by examining the first few bytes
    // In ARM64, check if the first instruction is a B or LDR
    uint32_t *instr = (uint32_t *)function;
    uint32_t firstInstr = *instr;
    
    // Check if it's a B instruction (branch)
    if ((firstInstr & ARM64_MASK_B) == ARM64_INSTR_B) {
        return true;
    }
    
    // Check if it's an LDR instruction (common in trampolines)
    if ((firstInstr & ARM64_MASK_LDR) == ARM64_INSTR_LDR && 
        instr[1] == 0xD61F0200) { // BR X16
        return true;
    }
    
    return false;
} 