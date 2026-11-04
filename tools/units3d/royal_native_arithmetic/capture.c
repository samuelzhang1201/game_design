/* Explicitly loaded diagnostic. Reads this process only; never writes its memory. */
#define _GNU_SOURCE
#include "gdextension_interface.h"
#include <dlfcn.h>
#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if !(defined(__APPLE__) && defined(__aarch64__)) && !(defined(__linux__) && defined(__x86_64__))
#error Unsupported diagnostic architecture
#endif
#ifndef ROYAL_NATIVE_HEADER_SHA256
#error The selected engine ABI header digest must be bound at build time
#endif
#ifndef ROYAL_NATIVE_ENGINE_SHA256
#error The selected engine file digest must be bound at build time
#endif
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#else
#include <elf.h>
#include <link.h>
#endif

static FILE *out;
static unsigned found[3];
static const char *names[] = {"sin", "sinf", "acosf"};

static void quoted(const char *s) {
    fputc('"', out);
    for (; *s; ++s) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') fputc('\\', out);
        if (c < 32) fprintf(out, "\\u%04x", c); else fputc(c, out);
    }
    fputc('"', out);
}

static void hex(const void *p, size_t count) {
    const unsigned char *bytes = p;
    fputc('"', out);
    for (size_t i = 0; i < count; ++i) fprintf(out, "%02x", bytes[i]);
    fputc('"', out);
}

static void address(uintptr_t p) { fprintf(out, "\"0x%" PRIxPTR "\"", p); }

#if defined(__linux__)
static int readonly_span(const void *base, uintptr_t offset, size_t count) {
    const Elf64_Ehdr *h = base;
    const Elf64_Phdr *p = (const void *)((const char *)base + h->e_phoff);
    if (count > 4096 || offset + count < offset) return 0;
    for (unsigned i = 0; i < h->e_phnum; ++i)
        if (p[i].p_type == PT_LOAD && (p[i].p_flags & (PF_R | PF_W)) == PF_R &&
                offset >= p[i].p_vaddr && offset + count <= p[i].p_vaddr + p[i].p_memsz) return 1;
    return 0;
}

/* Acquisition only: recognized scalar VEX RIP operands, never instruction semantics. */
static int rip_operand(const unsigned char *b, size_t available, uintptr_t pc,
        uintptr_t *target, size_t *count) {
    if (available < 8) return 0;
    unsigned op, modrm, pp, wide = 0, map = 1;
    if (b[0] == 0xc5) { op = 2; pp = b[1] & 3; }
    else if (b[0] == 0xc4 && available >= 9) {
        op = 3; pp = b[2] & 3; wide = b[2] >> 7; map = b[1] & 31;
    } else return 0;
    modrm = op + 1;
    if ((b[modrm] & 0xc7) != 5) return 0;
    if (map == 2 && (b[op] == 0x99 || b[op] == 0xa9 || b[op] == 0xb9 ||
                     b[op] == 0x9d || b[op] == 0xad || b[op] == 0xbd)) *count = wide ? 8 : 4;
    else if (map == 1) {
        switch (b[op]) {
            case 0x54: case 0x28: *count = 16; break;
            case 0x7e: *count = 8; break;
            case 0x2e: *count = pp == 1 ? 8 : 4; break;
            case 0x10: case 0x59: case 0x58: case 0x5c: case 0x5e: case 0x51: case 0xc2:
                *count = pp == 3 ? 8 : pp == 2 ? 4 : 16; break;
            default: return 0;
        }
    } else return 0;
    size_t size = modrm + 5 + (b[op] == 0xc2);
    if (available < size) return 0;
    int32_t displacement;
    memcpy(&displacement, b + modrm + 1, 4);
    intptr_t result = (intptr_t)pc + (intptr_t)size + displacement;
    if (result < 0) return 0;
    *target = (uintptr_t)result;
    return 1;
}

static void operand_self_check(void) {
    const unsigned char move[] = {0xc5,0xfb,0x10,0x05,0x78,0x56,0x34,0x12};
    const unsigned char fma[] = {0xc4,0xe2,0xf1,0xa9,0x05,0x78,0x56,0x34,0x12};
    const unsigned char compare[] = {0xc5,0xfb,0xc2,0x05,0,0,0,0,1};
    uintptr_t target; size_t count;
    assert(rip_operand(move, sizeof(move), 0x100, &target, &count) && target == 0x12345780 && count == 8);
    assert(rip_operand(fma, sizeof(fma), 0x100, &target, &count) && target == 0x12345781 && count == 8);
    assert(rip_operand(compare, sizeof(compare), 0x100, &target, &count) && target == 0x109 && count == 8);
    assert(!rip_operand(move, 7, 0x100, &target, &count));
}

struct operand_pool { uintptr_t offset[256]; size_t count[256], used; };

static void add_operand(struct operand_pool *pool, const void *base, uintptr_t offset, size_t count) {
    if (!readonly_span(base, offset, count)) return;
    for (size_t i = 0; i < pool->used; ++i)
        if (pool->offset[i] == offset && pool->count[i] == count) return;
    assert(pool->used < 256);
    pool->offset[pool->used] = offset; pool->count[pool->used++] = count;
}

static void scan_operands(struct operand_pool *pool, const void *base, uintptr_t offset, size_t size) {
    const unsigned char *bytes = (const unsigned char *)base + offset;
    for (size_t i = 0; i < size; ++i) {
        uintptr_t target; size_t count;
        if (rip_operand(bytes + i, size - i, offset + i, &target, &count)) add_operand(pool, base, target, count);
    }
}

static void linux_operands(unsigned index, const void *base, uintptr_t entry) {
    struct operand_pool pool = {0};
    scan_operands(&pool, base, entry, 512);
    const uintptr_t expected[] = {0x6dc10, 0x80670, 0x17ff0};
    const uintptr_t extra[] = {0x6e010, 0x80860, 0x78180};
    const size_t sizes[] = {0x90, 0x30, 0x330};
    fprintf(out, ",\"extra_code\":[");
    if (entry == expected[index] && readonly_span(base, extra[index], sizes[index])) {
        fprintf(out, "{\"offset\":%" PRIuPTR ",\"bytes\":", extra[index]);
        hex((const char *)base + extra[index], sizes[index]); fputc('}', out);
        scan_operands(&pool, base, extra[index], sizes[index]);
        if (index == 0) add_operand(&pool, base, 0xd2be0, 49 * 32);
    }
    fprintf(out, "],\"operands\":[");
    for (size_t i = 0; i < pool.used; ++i) {
        if (i) fputc(',', out);
        fprintf(out, "{\"offset\":%" PRIuPTR ",\"count\":%zu,\"bytes\":", pool.offset[i], pool.count[i]);
        hex((const char *)base + pool.offset[i], pool.count[i]); fputc('}', out);
    }
    fputc(']', out);
}
#endif

#if defined(__APPLE__)
static void image_id(const void *base) {
    const struct mach_header_64 *h = base;
    const struct load_command *c = (const void *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; ++i) {
        if (c->cmd == LC_UUID) { hex(((const struct uuid_command *)c)->uuid, 16); return; }
        c = (const void *)((const char *)c + c->cmdsize);
    }
    quoted("");
}
#else
static void image_id(const void *base) {
    const Elf64_Ehdr *h = base;
    const Elf64_Phdr *p = (const void *)((const char *)base + h->e_phoff);
    for (unsigned i = 0; i < h->e_phnum; ++i) {
        if (p[i].p_type != PT_NOTE) continue;
        const char *cursor = (const void *)((h->e_type == ET_DYN ? (uintptr_t)base : 0) + p[i].p_vaddr);
        const char *end = cursor + p[i].p_memsz;
        while (cursor + sizeof(Elf64_Nhdr) <= end) {
            const Elf64_Nhdr *n = (const void *)cursor;
            size_t ns = (n->n_namesz + 3u) & ~3u, ds = (n->n_descsz + 3u) & ~3u;
            if (cursor + sizeof(*n) + ns + ds > end) break;
            if (n->n_type == NT_GNU_BUILD_ID && n->n_namesz == 4 &&
                    memcmp(cursor + sizeof(*n), "GNU", 4) == 0) {
                hex(cursor + sizeof(*n) + ns, n->n_descsz); return;
            }
            cursor += sizeof(*n) + ns + ds;
        }
    }
    quoted("");
}
#endif

static void binding(unsigned index, const void *slot, const void *target) {
    Dl_info info;
    if (!dladdr(target, &info) || !info.dli_fbase) return;
    if (found[index]++) fputc(',', out);
    fprintf(out, "{\"symbol\":"); quoted(names[index]);
    fprintf(out, ",\"slot\":"); address((uintptr_t)slot);
    fprintf(out, ",\"target\":"); address((uintptr_t)target);
    fprintf(out, ",\"image_base\":"); address((uintptr_t)info.dli_fbase);
    fprintf(out, ",\"image_path\":"); quoted(info.dli_fname);
    fprintf(out, ",\"image_id\":"); image_id(info.dli_fbase);
    fprintf(out, ",\"dlsym_equal\":%s", dlsym(RTLD_DEFAULT, names[index]) == target ? "true" : "false");
    /* Whole reviewed small paths, including branch instructions and literal data. */
#if defined(__APPLE__) && defined(__aarch64__)
    const size_t starts[] = {0x940, 0x3158, 0xbb30};
    const size_t ends[] = {0x10c4, 0x3498, 0xbcc0};
    const size_t entries[] = {0x970, 0x3158, 0xbb30};
    uintptr_t offset = (uintptr_t)target - (uintptr_t)info.dli_fbase;
    fprintf(out, ",\"entry_offset\":%" PRIuPTR, offset);
    if (offset == entries[index]) {
        fprintf(out, ",\"code_offset\":%zu,\"code\":", starts[index]);
        hex((const char *)info.dli_fbase + starts[index], ends[index] - starts[index]);
    }
#else
    /* Unknown profiles retain a bounded executable witness, never an acceptance. */
    fprintf(out, ",\"entry_offset\":%" PRIuPTR, (uintptr_t)target - (uintptr_t)info.dli_fbase);
    fprintf(out, ",\"code_offset\":%" PRIuPTR ",\"code\":", (uintptr_t)target - (uintptr_t)info.dli_fbase);
    if (readonly_span(info.dli_fbase, (uintptr_t)target - (uintptr_t)info.dli_fbase, 512)) {
        hex(target, 512);
        linux_operands(index, info.dli_fbase, (uintptr_t)target - (uintptr_t)info.dli_fbase);
    } else quoted("");
#endif
    fputc('}', out);
}

#if defined(__APPLE__)
static void imports(void) {
    const struct mach_header_64 *h = (const void *)_dyld_get_image_header(0);
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct symtab_command *sym = NULL;
    const struct dysymtab_command *dysym = NULL;
    uintptr_t linkedit = 0;
    const struct load_command *c = (const void *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; ++i) {
        if (c->cmd == LC_SYMTAB) sym = (const void *)c;
        if (c->cmd == LC_DYSYMTAB) dysym = (const void *)c;
        if (c->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *s = (const void *)c;
            if (!strcmp(s->segname, "__LINKEDIT")) linkedit = slide + s->vmaddr - s->fileoff;
        }
        c = (const void *)((const char *)c + c->cmdsize);
    }
    if (!sym || !dysym || !linkedit) return;
    const struct nlist_64 *symbols = (const void *)(linkedit + sym->symoff);
    const char *strings = (const void *)(linkedit + sym->stroff);
    const uint32_t *indirect = (const void *)(linkedit + dysym->indirectsymoff);
    for (unsigned wanted = 0; wanted < 3; ++wanted) {
        if (wanted) fputc(',', out);
        fputc('[', out);
        c = (const void *)(h + 1);
        for (uint32_t i = 0; i < h->ncmds; ++i) {
            if (c->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *s = (const void *)c;
                const struct section_64 *section = (const void *)(s + 1);
                for (uint32_t j = 0; j < s->nsects; ++j) {
                    unsigned type = section[j].flags & SECTION_TYPE;
                    if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) continue;
                    for (uint64_t k = 0; k < section[j].size / sizeof(void *); ++k) {
                        uint64_t ii = section[j].reserved1 + k;
                        if (ii >= dysym->nindirectsyms) continue;
                        uint32_t si = indirect[ii];
                        if (si >= sym->nsyms || symbols[si].n_un.n_strx >= sym->strsize) continue;
                        const char *name = strings + symbols[si].n_un.n_strx;
                        if (name[0] != '_' || strcmp(name + 1, names[wanted])) continue;
                        const void **slot = (const void **)(slide + section[j].addr + k * sizeof(void *));
                        binding(wanted, slot, *slot);
                    }
                }
            }
            c = (const void *)((const char *)c + c->cmdsize);
        }
        fputc(']', out);
    }
}
#else
static int elf_imports(struct dl_phdr_info *info, size_t size, void *data) {
    (void)size; (void)data;
    if (info->dlpi_name && info->dlpi_name[0]) return 0;
    const Elf64_Dyn *dynamic = NULL;
    for (unsigned i = 0; i < info->dlpi_phnum; ++i)
        if (info->dlpi_phdr[i].p_type == PT_DYNAMIC)
            dynamic = (const void *)(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
    if (!dynamic) return 1;
    const Elf64_Sym *symbols = NULL;
    const char *strings = NULL;
    const Elf64_Rela *tables[2] = {NULL, NULL};
    size_t counts[2] = {0, 0};
    for (const Elf64_Dyn *d = dynamic; d->d_tag != DT_NULL; ++d) {
        switch (d->d_tag) {
            case DT_SYMTAB: symbols = (const void *)d->d_un.d_ptr; break;
            case DT_STRTAB: strings = (const void *)d->d_un.d_ptr; break;
            case DT_JMPREL: tables[0] = (const void *)d->d_un.d_ptr; break;
            case DT_RELA: tables[1] = (const void *)d->d_un.d_ptr; break;
            case DT_PLTRELSZ: counts[0] = d->d_un.d_val / sizeof(Elf64_Rela); break;
            case DT_RELASZ: counts[1] = d->d_un.d_val / sizeof(Elf64_Rela); break;
            default: break;
        }
    }
    if (!symbols || !strings) return 1;
    for (unsigned wanted = 0; wanted < 3; ++wanted) {
        if (wanted) fputc(',', out);
        fputc('[', out);
        for (unsigned table = 0; table < 2; ++table) {
            if (!tables[table]) continue;
            for (size_t j = 0; j < counts[table]; ++j) {
                const Elf64_Rela *r = &tables[table][j];
                unsigned type = ELF64_R_TYPE(r->r_info);
                if (type != R_X86_64_JUMP_SLOT && type != R_X86_64_GLOB_DAT) continue;
                if (strcmp(strings + symbols[ELF64_R_SYM(r->r_info)].st_name, names[wanted])) continue;
                const void **slot = (const void **)(info->dlpi_addr + r->r_offset);
                binding(wanted, slot, *slot);
            }
        }
        fputc(']', out);
    }
    return 1;
}
static void imports(void) { dl_iterate_phdr(elf_imports, NULL); }
#endif

static void initialize(void *data, GDExtensionInitializationLevel level) { (void)data; (void)level; }
static void deinitialize(void *data, GDExtensionInitializationLevel level) { (void)data; (void)level; }

GDExtensionBool royal_native_arithmetic_init(GDExtensionInterfaceGetProcAddress get_proc,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    (void)library;
#if defined(__linux__)
    operand_self_check();
#endif
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata = NULL; init->initialize = initialize; init->deinitialize = deinitialize;
    const char *path = getenv("ROYAL_NATIVE_CAPTURE");
    if (!path || !(out = fopen(path, "wx"))) return 0;
    GDExtensionGodotVersion version;
    GDExtensionInterfaceGetGodotVersion get_version = (GDExtensionInterfaceGetGodotVersion)get_proc("get_godot_version");
    if (!get_version) { fclose(out); return 0; }
    get_version(&version);
    Dl_info engine;
    if (!dladdr((const void *)get_proc, &engine)) { fclose(out); return 0; }
    fprintf(out, "{\"schema\":1,\"pid\":%ld,\"engine_path\":", (long)getpid()); quoted(engine.dli_fname);
    fprintf(out, ",\"engine_version\":"); quoted(version.string);
    fprintf(out, ",\"engine_version_components\":[%u,%u,%u]", version.major, version.minor, version.patch);
    fprintf(out, ",\"header_sha256\":"); quoted(ROYAL_NATIVE_HEADER_SHA256);
    fprintf(out, ",\"selected_engine_sha256\":"); quoted(ROYAL_NATIVE_ENGINE_SHA256);
#if defined(__APPLE__)
    fprintf(out, ",\"platform\":\"macos-arm64\",\"engine_image_id\":");
#else
    fprintf(out, ",\"platform\":\"linux-x86_64\",\"engine_image_id\":");
#endif
    image_id(engine.dli_fbase);
    fprintf(out, ",\"imports\":["); imports();
    fprintf(out, "]}\n");
    int failed = ferror(out); if (fclose(out)) failed = 1;
    return failed ? 0 : 1;
}
